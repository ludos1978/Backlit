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
    /// True while the administrator password prompt is open (the picker is disabled).
    @Published private(set) var isBusy = false

    private var displayAssertion: IOPMAssertionID = 0
    private static let ownsDisableSleepKey = "fd.keepAwake.sleepDisabledByBacklit"

    private init() {}

    /// Switches mode. Changes that need `pmset` ask for the password in a separate
    /// process, so the menu stays responsive while the prompt is open.
    func setMode(_ newMode: Mode) {
        guard newMode != mode, !isBusy else { return }
        lastError = nil

        let command: String?
        if newMode == .closedLid {
            // Only flip it (and own it) if it isn't on already.
            command = Self.isSleepDisabled() ? nil : "pmset -a disablesleep 1"
        } else if mode == .closedLid, ownsDisableSleep, Self.isSleepDisabled() {
            command = "pmset -a disablesleep 0"
        } else {
            command = nil
        }

        guard let command else {
            if mode == .closedLid { ownsDisableSleep = false }
            finish(newMode)
            return
        }
        isBusy = true
        Task {
            let err = await Self.runPrivilegedAsync(command)
            isBusy = false
            if let err { lastError = err; return }
            ownsDisableSleep = newMode == .closedLid
            finish(newMode)
        }
    }

    private func finish(_ newMode: Mode) {
        if newMode == .system { releaseDisplayAssertion() } else { takeDisplayAssertion() }
        mode = newMode
    }

    private var ownsDisableSleep: Bool {
        get { UserDefaults.standard.bool(forKey: Self.ownsDisableSleepKey) }
        set {
            if newValue { UserDefaults.standard.set(true, forKey: Self.ownsDisableSleepKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.ownsDisableSleepKey) }
        }
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

    /// Quit / launch: turns `disablesleep` off again if Backlit turned it on
    /// (blocking — the app is quitting or not yet interactive).
    private func releaseDisableSleep() -> String? {
        guard ownsDisableSleep else { return nil }
        if Self.isSleepDisabled(), let err = Self.runPrivileged("pmset -a disablesleep 0") {
            return err
        }
        ownsDisableSleep = false
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
    /// privileges, blocking. Returns nil on success, or an error message.
    private static func runPrivileged(_ command: String) -> String? {
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(command)\" with administrator privileges")?
            .executeAndReturnError(&error)
        guard let error else { return nil }
        return describe(error[NSAppleScript.errorMessage] as? String ?? "unknown error")
    }

    /// Same, via `osascript` in its own process, without blocking the main thread.
    private static func runPrivilegedAsync(_ command: String) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "do shell script \"\(command)\" with administrator privileges"]
            let errPipe = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errPipe
            process.terminationHandler = { p in
                let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                let msg = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                cont.resume(returning: p.terminationStatus == 0 ? nil : describe(msg.isEmpty ? "exit \(p.terminationStatus)" : msg))
            }
            do { try process.run() } catch { cont.resume(returning: "pmset failed: \(error.localizedDescription)") }
        }
    }

    nonisolated private static func describe(_ message: String) -> String {
        message.localizedCaseInsensitiveContains("cancel") ? "Password prompt cancelled" : "pmset failed: \(message)"
    }
}
