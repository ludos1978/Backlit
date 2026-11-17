import Foundation
import CoreGraphics

/// Disables ("disconnects") individual physical displays in software, like BlackOut or
/// BetterDisplay, via the private `CGSConfigureDisplayEnabled` (loaded with dlsym).
///
/// A disabled display stays online but inactive: macOS moves its windows to the
/// remaining screens and re-fits the layout itself — Backlit never moves displays.
///
/// Safety:
/// - at least one physical display always stays enabled;
/// - the change is made for the login session only (logout / restart restores it);
/// - every display Backlit disabled is re-enabled on quit, and at the next launch
///   if Backlit crashed while one was off (`fd.disabledDisplays`);
/// - a disabled display that comes back on by other means (replugged, another app,
///   logout) is forgotten. A disabled display is also *offline* to CoreGraphics, so
///   "offline" can't be used to detect an unplug — that would lose the only way back.
@MainActor
final class DisplayDisableService: ObservableObject, @unchecked Sendable {
    static let shared = DisplayDisableService()

    private typealias ConfigureEnabledFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

    private static let configureEnabled: ConfigureEnabledFn? = {
        // RTLD_DEFAULT: the symbol is exported by CoreGraphics (forwarded to SkyLight).
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSConfigureDisplayEnabled") else { return nil }
        return unsafeBitCast(sym, to: ConfigureEnabledFn.self)
    }()

    private static let disabledKey = "fd.disabledDisplays"

    /// Displays Backlit disabled this session: displayID → name (an inactive display
    /// has no NSScreen, so its name is remembered from when it was active).
    @Published private(set) var disabled: [CGDirectDisplayID: String] = [:] {
        didSet {
            let stored = Dictionary(uniqueKeysWithValues: disabled.map { (String($0.key), $0.value) })
            UserDefaults.standard.set(stored, forKey: Self.disabledKey)
        }
    }

    var isAvailable: Bool { Self.configureEnabled != nil }

    private init() {}

    func isDisabled(_ displayID: CGDirectDisplayID) -> Bool { disabled[displayID] != nil }

    /// Sorted for a stable menu order.
    var disabledList: [(id: CGDirectDisplayID, name: String)] {
        disabled.map { (id: $0.key, name: $0.value) }.sorted { $0.id < $1.id }
    }

    /// False when `display` is the last enabled physical display (it must stay on).
    func canDisable(_ display: DisplayInfo) -> Bool {
        guard isAvailable, !isDisabled(display.displayID) else { return false }
        return activePhysicalDisplayIDs().contains { $0 != display.displayID }
    }

    func disable(_ display: DisplayInfo) {
        guard canDisable(display) else { return }
        guard configure(display.displayID, enabled: false) else { return }
        disabled[display.displayID] = display.name
    }

    func enable(_ displayID: CGDirectDisplayID) {
        guard disabled[displayID] != nil else { return }
        _ = configure(displayID, enabled: true)
        // Forget it even if the call failed (e.g. the display was unplugged meanwhile).
        disabled[displayID] = nil
    }

    func enableAll() {
        for id in Array(disabled.keys) { enable(id) }
    }

    /// Launch: re-enables displays left disabled by a session that crashed. Only
    /// displays Backlit itself disabled are touched; launch changes nothing else.
    func restoreAfterUncleanExit() {
        guard let stored = UserDefaults.standard.dictionary(forKey: Self.disabledKey) as? [String: String],
              !stored.isEmpty else { return }
        for key in stored.keys {
            guard let id = CGDirectDisplayID(key) else { continue }
            _ = configure(id, enabled: true)
        }
        UserDefaults.standard.removeObject(forKey: Self.disabledKey)
    }

    /// Drops disabled displays that are active again (turned back on outside Backlit).
    func pruneReenabled() {
        for id in disabled.keys where CGDisplayIsActive(id) != 0 {
            disabled[id] = nil
        }
    }

    // MARK: - Private

    private func activePhysicalDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).filter { !VirtualDisplayService.shared.isVirtualDisplay($0) }
    }

    private func configure(_ displayID: CGDirectDisplayID, enabled: Bool) -> Bool {
        guard let fn = Self.configureEnabled else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        let err = fn(config, displayID, enabled)
        guard err == .success else {
            CGCancelDisplayConfiguration(config)
            print("[DisplayDisableService] CGSConfigureDisplayEnabled(\(displayID), \(enabled)) failed: \(err.rawValue)")
            return false
        }
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }
}
