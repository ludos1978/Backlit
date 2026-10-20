import AppKit
import CoreGraphics

class AppDelegate: NSObject, NSApplicationDelegate {
    private var wakeObserver: NSObjectProtocol?

    /// False when the previous run did not terminate cleanly (crash, force quit,
    /// power loss). Persisted display adjustments are then NOT re-applied
    /// automatically at launch — a pathological state (e.g. an almost-black
    /// gamma) must never lock the user out across relaunches.
    nonisolated(unsafe) private(set) static var previousExitWasClean = true
    private static let cleanExitKey = "fd.session.cleanExit"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Crash guard: was the previous session closed cleanly?
        let defaults = UserDefaults.standard
        Self.previousExitWasClean = defaults.object(forKey: Self.cleanExitKey) == nil
            || defaults.bool(forKey: Self.cleanExitKey)
        defaults.set(false, forKey: Self.cleanExitKey)   // cleared again in applicationWillTerminate
        if !Self.previousExitWasClean {
            print("[Backlit] Previous session did not exit cleanly — persisted display adjustments are not re-applied automatically.")
        }

        // Prevent duplicate launches: exit immediately if another instance is already running
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        if runningApps.count > 1 {
            print("[Backlit] Another instance is already running, exiting.")
            NSApp.terminate(nil)
            return
        }

        // Brightness-key interception (F1/F2 → external display under the cursor) and
        // volume-key interception (→ monitor speakers when they are the sound output)
        // are opt-in via Settings. The toggles start/stop the event tap live; here we
        // only honour the saved choice.
        BrightnessKeyService.shared.updateTapState()

        // Launch is passive: starting Backlit never changes brightness, dimming, gamma,
        // XDR or contrast — only an explicit user action does (a slider, a toggle, a
        // preset). Drop output state persisted by the previous session so the controls
        // show what is actually on screen. XDR, adaptive brightness and accessibility
        // contrast simply aren't re-enabled; only their non-output settings load.
        GammaService.shared.clearAllSavedStates()
        BrightnessService.shared.clearPersistedSoftwareBrightness()
        XDRBrightnessService.shared.restoreSavedLevel()

        // Observe System Settings contrast changes before the menu is first opened.
        _ = AccessibilityService.shared

        // Build the display manager now — it registers the reconfiguration
        // callback and performs the initial display scan. Display layout (where
        // displays sit relative to each other) is not Backlit's job — it never
        // moves displays.
        _ = DisplayManager.shared

        // Track built-in brightness changes made outside the app (keys, Control
        // Center, System Settings) so the launch restore never uses a stale value.
        BrightnessService.shared.startBuiltinObservation()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                // Give WindowServer 2 seconds to stabilize after wake before
                // touching display state.
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let dm = DisplayManager.shared
                dm.refreshDisplays()
                try? await Task.sleep(nanoseconds: 500_000_000)
                // Each area re-applies only while Backlit owns it (Settings →
                // "Who controls each setting"); macOS-controlled areas are left alone.
                let settings = SettingsService.shared
                for display in dm.displays {
                    // Apply software brightness factor first so GammaService
                    // can read the up-to-date factor when it re-applies its formula.
                    if settings.isAuthoritative(.brightness) {
                        BrightnessService.shared.reapplySoftwareBrightnessIfNeeded(for: display)
                    }
                    if settings.isAuthoritative(.imageAdjustment) {
                        GammaService.shared.reapplyIfNeeded(for: display.displayID)
                    }
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Self.cleanExitKey)
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        BrightnessKeyService.shared.stop()
        // GammaService already handles CGDisplayRestoreColorSyncSettings via willTerminateNotification observer.
        VirtualDisplayService.shared.destroyAll()
    }
}
