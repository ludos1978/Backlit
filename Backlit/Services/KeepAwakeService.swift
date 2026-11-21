import Foundation
import AppKit
import IOKit.pwr_mgt

/// Keep-awake modes (like Amphetamine / caffeinate):
/// - `.system`: no influence — macOS sleeps with its own settings (default).
/// - `.displays`: screens don't sleep on idle (and so the Mac doesn't either).
/// - `.closedLid`: additionally keeps the Mac awake with the lid closed and no
///   external display (`pmset -a disablesleep 1`, needs an administrator password).
///
/// The mode is not persisted: every launch starts in `.system` (launch is passive).
/// `disablesleep` is a system-wide setting that survives Backlit, so it is undone on
/// quit, and at the next launch if Backlit crashed while it was on
/// (`fd.keepAwake.sleepDisabledByBacklit`). A `disablesleep` that was already on
/// before (set by another tool or by hand) is never touched.
@MainActor
final class KeepAwakeService: ObservableObject, @unchecked Sendable {
    static let shared = KeepAwakeService()

    enum Mode: String, CaseIterable, Identifiable {
        case system, displays, closedLid
        var id: String { rawValue }

        var title: String {
            switch self {
            case .system:    return "System"
            case .displays:  return "Screens"
            case .closedLid: return "Lid Closed"
            }
        }

        var help: String {
            switch self {
            case .system:    return "macOS sleeps with its own settings"
            case .displays:  return "Screens (and the Mac) stay awake while Backlit runs"
            case .closedLid: return "The Mac stays awake even with the lid closed and no external display (asks for an administrator password)"
            }
        }
    }

    @Published private(set) var mode: Mode = .system
    /// Last failure (e.g. the password prompt was cancelled), shown under the picker.
    @Published private(set) var lastError: String?

    private var displayAssertion: IOPMAssertionID = 0
    private static let ownsDisableSleepKey = "fd.keepAwake.sleepDisabledByBacklit"

    private init() {}

    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        lastError = nil

        if newMode == .closedLid {
            // Only flip it (and own it) if it isn't on already.
            if !Self.isSleepDisabled() {
                if let err = Self.runPrivileged("pmset -a disablesleep 1") {
                    lastError = err
                    return
                }
                UserDefaults.standard.set(true, forKey: Self.ownsDisableSleepKey)
            }
        } else if mode == .closedLid {
            if let err = releaseDisableSleep() {
                lastError = err
                return
            }
        }

        if newMode == .system { releaseDisplayAssertion() } else { takeDisplayAssertion() }
        mode = newMode
    }

    /// Quit: back to the system's own sleep behaviour.
    func restoreSystemDefault() {
        releaseDisplayAssertion()
        _ = releaseDisableSleep()
        mode = .system
    }

    /// Launch: a previous session crashed with `disablesleep` on — turn it off again.
    func restoreAfterUncleanExit() {
        guard UserDefaults.standard.bool(forKey: Self.ownsDisableSleepKey) else { return }
        _ = releaseDisableSleep()
    }

    // MARK: - Private

    private func takeDisplayAssertion() {
        guard displayAssertion == 0 else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Backlit: keep awake" as CFString,
            &displayAssertion)
        if result != kIOReturnSuccess {
            displayAssertion = 0
            lastError = "Could not keep the screens awake (error \(result))"
        }
    }

    private func releaseDisplayAssertion() {
        guard displayAssertion != 0 else { return }
        IOPMAssertionRelease(displayAssertion)
        displayAssertion = 0
    }

    /// Turns `disablesleep` off again if Backlit turned it on. Returns an error message.
    private func releaseDisableSleep() -> String? {
        guard UserDefaults.standard.bool(forKey: Self.ownsDisableSleepKey) else { return nil }
        if Self.isSleepDisabled(), let err = Self.runPrivileged("pmset -a disablesleep 0") {
            return err
        }
        UserDefaults.standard.removeObject(forKey: Self.ownsDisableSleepKey)
        return nil
    }

    /// `pmset -g` reports "SleepDisabled 1" while `disablesleep` is on.
    private static func isSleepDisabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        return output.split(separator: "\n").contains {
            let parts = $0.split(whereSeparator: \.isWhitespace)
            return parts.count >= 2 && parts[0] == "SleepDisabled" && parts[1] == "1"
        }
    }

    /// Runs a fixed command (only the two pmset calls above) with administrator
    /// privileges. Returns nil on success, or an error message.
    private static func runPrivileged(_ command: String) -> String? {
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(command)\" with administrator privileges")?
            .executeAndReturnError(&error)
        guard let error else { return nil }
        let msg = error[NSAppleScript.errorMessage] as? String ?? "unknown error"
        return msg.localizedCaseInsensitiveContains("cancel") ? "Password prompt cancelled" : "pmset failed: \(msg)"
    }
}
