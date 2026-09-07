import AppKit
import CoreGraphics

class AppDelegate: NSObject, NSApplicationDelegate {
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent duplicate launches: exit immediately if another instance is already running
        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        if runningApps.count > 1 {
            print("[FreeDisplay] Another instance is already running, exiting.")
            NSApp.terminate(nil)
            return
        }

        // Start intercepting brightness keys to route them to the display under the cursor.
        BrightnessKeyService.shared.start()

        // Restore XDR brightness mode if it was enabled in the previous session.
        XDRBrightnessService.shared.restoreSavedState()

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
                for display in dm.displays {
                    // Apply software brightness factor first so GammaService
                    // can read the up-to-date factor when it re-applies its formula.
                    BrightnessService.shared.reapplySoftwareBrightnessIfNeeded(for: display)
                    GammaService.shared.reapplyIfNeeded(for: display.displayID)
                    // Re-apply any custom resolution that macOS may have reset on wake
                    ResolutionService.shared.reapplySavedModeIfNeeded(for: display.displayID)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        BrightnessKeyService.shared.stop()
        // GammaService already handles CGDisplayRestoreColorSyncSettings via willTerminateNotification observer.
        VirtualDisplayService.shared.destroyAll()
    }
}
