import Foundation
import IOKit.pwr_mgt

/// Keep-awake modes, built on IOPM power assertions like `caffeinate` — no
/// administrator rights, no system setting changed. macOS drops the assertions
/// when Backlit quits or crashes, so nothing is ever left behind.
/// - `.system`: no assertion — macOS sleeps with its own settings.
/// - `.displays`: screens (and so the Mac) don't sleep on idle (`caffeinate -d`).
/// - `.closedLid`: additionally the Mac doesn't sleep at all, even with the lid
///   closed and no external display (`caffeinate -s`). macOS honours this only on
///   the power adapter; on battery, closing the lid still sleeps.
///
/// The chosen mode is remembered (`fd.keepAwake.mode`) and restored at launch.
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
            case .closedLid: return "The Mac stays awake even with the lid closed and no external display — on the power adapter only (macOS ignores this on battery)"
            }
        }

        /// IOPM assertion types held in this mode.
        fileprivate var assertionTypes: [String] {
            switch self {
            case .system:    return []
            case .displays:  return [kIOPMAssertPreventUserIdleDisplaySleep]
            // "PreventSystemSleep" is what `caffeinate -s` asserts (the SDK constant is
            // marked deprecated, but powerd still honours it on AC power).
            case .closedLid: return [kIOPMAssertPreventUserIdleDisplaySleep, "PreventSystemSleep"]
            }
        }
    }

    @Published private(set) var mode: Mode = .system
    /// Last failure, shown under the picker.
    @Published private(set) var lastError: String?

    private var assertions: [String: IOPMAssertionID] = [:]
    private static let modeKey = "fd.keepAwake.mode"
    /// Set by versions that used `pmset -a disablesleep` (≤ 0.8.1).
    private static let legacyOwnsDisableSleepKey = "fd.keepAwake.sleepDisabledByBacklit"

    private init() {}

    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        apply(newMode)
        UserDefaults.standard.set(newMode.rawValue, forKey: Self.modeKey)
    }

    /// Launch: restores the remembered mode.
    func restoreAtLaunch() {
        cleanUpLegacyDisableSleep()
        let saved = Mode(rawValue: UserDefaults.standard.string(forKey: Self.modeKey) ?? "") ?? .system
        if saved != .system { apply(saved) }
    }

    /// Quit: release everything (macOS would do it anyway). The mode stays remembered.
    func restoreSystemDefault() {
        apply(.system)
    }

    // MARK: - Private

    private func apply(_ newMode: Mode) {
        lastError = nil
        let wanted = Set(newMode.assertionTypes)
        for (type, id) in assertions where !wanted.contains(type) {
            IOPMAssertionRelease(id)
            assertions[type] = nil
        }
        for type in wanted where assertions[type] == nil {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "Backlit: keep awake" as CFString, &id)
            if result == kIOReturnSuccess {
                assertions[type] = id
            } else {
                lastError = "Could not keep the Mac awake (error \(result))"
            }
        }
        mode = newMode
    }

    /// Older versions turned on `pmset disablesleep` for Lid Closed and undid it on
    /// quit. If one crashed with it on, undo it once (asks for the password one last time).
    private func cleanUpLegacyDisableSleep() {
        let d = UserDefaults.standard
        guard d.bool(forKey: Self.legacyOwnsDisableSleepKey) else { return }
        d.removeObject(forKey: Self.legacyOwnsDisableSleepKey)
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"pmset -a disablesleep 0\" with administrator privileges")?
            .executeAndReturnError(&error)
    }
}
