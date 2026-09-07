import AppKit
import Combine

// MARK: - Private accessibility APIs (dlsym)
//
// Writing the com.apple.universalaccess preference domain does NOT work from an
// app: the domain is TCC-protected (silent failure without Full Disk Access) and
// even a successful write is not applied live by universalaccessd. The private
// UniversalAccess / SkyLight entry points below are what actually drive the
// effect — verified working on this machine (set + readback round trip).

private let _UAIncreaseContrastIsEnabled: (@convention(c) () -> Bool)? = {
    guard let h = dlopen("/System/Library/PrivateFrameworks/UniversalAccess.framework/UniversalAccess", RTLD_LAZY),
          let sym = dlsym(h, "UAIncreaseContrastIsEnabled") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) () -> Bool).self)
}()

private let _UAIncreaseContrastSetEnabled: (@convention(c) (Bool) -> Void)? = {
    guard let h = dlopen("/System/Library/PrivateFrameworks/UniversalAccess.framework/UniversalAccess", RTLD_LAZY),
          let sym = dlsym(h, "UAIncreaseContrastSetEnabled") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (Bool) -> Void).self)
}()

private let _CGSSetDisplayContrast: (@convention(c) (Float) -> Int32)? = {
    guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
          let sym = dlsym(h, "CGSSetDisplayContrast") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (Float) -> Int32).self)
}()

/// Bridges the macOS Accessibility display settings — "Increase contrast" and
/// "Display Contrast" — into the menu.
@MainActor
final class AccessibilityService: ObservableObject, @unchecked Sendable {
    static let shared = AccessibilityService()

    private enum Keys {
        static let displayContrast = "fd.accessibility.displayContrast"
    }

    /// True when the private entry points are available (they are on supported
    /// macOS versions); the UI can hide the section otherwise.
    var isAvailable: Bool {
        _UAIncreaseContrastSetEnabled != nil && _CGSSetDisplayContrast != nil
    }

    /// The "Increase contrast" accessibility toggle (adds borders, stronger UI contrast).
    @Published var increaseContrast: Bool = false {
        didSet {
            guard !isReloading, oldValue != increaseContrast else { return }
            _UAIncreaseContrastSetEnabled?(increaseContrast)
        }
    }

    /// The "Display Contrast" accessibility effect: 0 = normal … 1 = maximum.
    /// Applied live via SkyLight; persisted in our own domain (the system pref
    /// domain is TCC-protected) and re-applied at launch.
    @Published var displayContrast: Double = 0 {
        didSet {
            guard !isReloading, oldValue != displayContrast else { return }
            let clamped = Float(min(max(displayContrast, 0), 1))
            _ = _CGSSetDisplayContrast?(clamped)
            UserDefaults.standard.set(displayContrast, forKey: Keys.displayContrast)
        }
    }

    private var isReloading = false
    private var observer: NSObjectProtocol?

    private init() {
        reload()
        // Restore our display-contrast value from the previous session.
        // Property observers do NOT fire inside init, so apply explicitly.
        let saved = UserDefaults.standard.double(forKey: Keys.displayContrast)
        if saved > 0 {
            displayContrast = saved
            _ = _CGSSetDisplayContrast?(Float(min(max(saved, 0), 1)))
        }
        // Follow changes made in System Settings while the app runs.
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in AccessibilityService.shared.reload() }
        }
    }

    /// Pushes the current accessibility contrast state onto the undo stack (⌘Z).
    func pushUndoSnapshot() {
        let previousIncrease = increaseContrast
        let previousContrast = displayContrast
        UndoService.shared.push {
            Task { @MainActor in
                let service = AccessibilityService.shared
                service.increaseContrast = previousIncrease
                service.displayContrast = previousContrast
            }
        }
    }

    /// Re-reads the effective "Increase contrast" state from the system.
    /// (There is no getter for the SkyLight display contrast; our own stored
    /// value remains authoritative for the slider.)
    func reload() {
        isReloading = true
        defer { isReloading = false }
        increaseContrast = _UAIncreaseContrastIsEnabled?()
            ?? NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }
}
