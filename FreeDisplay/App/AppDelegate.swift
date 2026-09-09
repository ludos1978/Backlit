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
            print("[FreeDisplay] Previous session did not exit cleanly — persisted display adjustments are not re-applied automatically.")
        }

        // Prevent duplicate launches: exit immediately if another instance is already running
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        if runningApps.count > 1 {
            print("[FreeDisplay] Another instance is already running, exiting.")
            NSApp.terminate(nil)
            return
        }

        // Brightness-key interception (F1/F2 → external display under the cursor)
        // is opt-in: Settings → "Intercept Brightness Keys". The toggle starts/stops
        // the event tap live; here we only honour the saved choice.
        if SettingsService.shared.interceptBrightnessKeys {
            BrightnessKeyService.shared.start()
        }

        // Restore XDR brightness mode if it was enabled in the previous session.
        if SettingsService.shared.isAuthoritative(.xdr) {
            XDRBrightnessService.shared.restoreSavedState()
        }

        // Warm up auto-brightness so an enabled setting starts at launch — it is a
        // lazy singleton, and starting it on first UI access (unfolding its row)
        // suddenly synced every external display to the built-in brightness.
        _ = AutoBrightnessService.shared

        // Warm up the accessibility bridge so saved display contrast is restored
        // and System Settings changes are observed before the menu is first opened.
        _ = AccessibilityService.shared

        // Build the display manager now — it registers the reconfiguration
        // callback and performs the initial display scan. The app never
        // rearranges displays on its own; layout changes only happen through
        // explicit user actions (arrangement canvas, Set as Main, presets).
        _ = DisplayManager.shared

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
                // Each area re-applies only while FreeDisplay owns it (Settings →
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
                    // Re-apply any custom resolution that macOS may have reset on wake
                    if settings.isAuthoritative(.resolution) {
                        ResolutionService.shared.reapplySavedModeIfNeeded(for: display.displayID)
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
