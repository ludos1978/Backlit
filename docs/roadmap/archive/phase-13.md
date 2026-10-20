# Phase 13: Critical Bug Fixes

> Goal: fix three functional bugs reported by users

## Task List

- [x] Fix the afterimage problem after closing image adjustment
  - Implementation hints:
    1. Add `.onDisappear` to `ImageAdjustmentView.swift`: check whether all sliders are at zero, and if not call `GammaService.shared.restoreColorSync()`
    2. Register an `NSApplication.willTerminateNotification` observer in `GammaService.swift`'s `init()`, and call `CGDisplayRestoreColorSyncSettings()` in the callback
    3. Add one more safeguard in `applicationWillTerminate` of `AppDelegate.swift`: `CGDisplayRestoreColorSyncSettings()`
    4. Consider adding `saveState()` / `restoreState()` methods to GammaService: save the current adjustment values to UserDefaults on onDisappear and restore them on onAppear (so closing the panel does not lose settings, but everything is fully cleaned up when the app quits)
  - Verify: adjust gamma -> collapse the image adjustment panel -> screen returns to normal; force quit the app -> screen returns to normal

- [x] Fix the 1920x1080 resolution being unclickable
  - Implementation hints:
    1. In the `switchTo()` method of `DisplayModeListView.swift`: remove the silent guard on `mode.id != display.currentDisplayMode?.id`; instead, if it is the current mode, show an "Already the current mode" hint (flash a highlight with `withAnimation`)
    2. Change the `ResolutionService.shared.setDisplayMode()` call to `Task { @MainActor in }`, set `isSwitching = true` before the call, and set `isSwitching = false` after the await completes
    3. Make `setDisplayMode` in `ResolutionService.swift` an `async` method, internally wrapping `CGConfigureDisplayWithDisplayMode` + `CGCompleteDisplayConfiguration` with `withCheckedContinuation`
    4. Add failure feedback: if `setDisplayMode` returns false, show an error message
  - Verify: click 1920x1080 -> loading is shown -> the switch succeeds or an error message is shown; click the mode that is already current -> "Already the current mode" is shown

- [x] Fix HiDPI scaled modes not showing / requiring reconnection
  - Implementation hints:
    1. After `enableHiDPI()` in `HiDPIService.swift` finishes writing the plist, call `CGDisplayForceToMirror(displayID, 0)` and then `CGDisplayForceToMirror(displayID, kCGNullDirectDisplay)` to trigger the display to re-enumerate modes (following BetterDisplay's approach)
    2. If the above is unavailable, fallback: use `IOServiceRequestProbe` to notify IOKit to rescan
    3. After refreshing, call `DisplayMode.availableModes(for:)` to re-fetch the mode list and update `display.availableModes`
    4. Add a "Refresh mode list" button to `DisplayModeListView` as a fallback
  - Verify: click enable HiDPI -> the mode list refreshes automatically, and new HiDPI scaled resolutions appear (e.g. 1920x1080 HiDPI)

- [x] Improve the HiDPI categorized display of DisplayMode
  - Implementation hints:
    1. In the grouping logic of `DisplayModeListView.swift`: add a "HiDPI Scaled Modes" group that specifically shows modes with `isHiDPI && !isNative`
    2. For 2K displays (e.g. the user's HKC 2560x1440), HiDPI scaled modes should include: 1280x720 HiDPI (native 2x) and lower-resolution HiDPI modes
    3. Show "logical resolution @ actual pixel density" info on each mode row, to help users understand what HiDPI means
  - Verify: the mode list clearly shows the groups "Default and Native Modes", "HiDPI Scaled Modes", and "Other Modes"

**Phase Acceptance**: builds successfully + all four verification scenarios above are satisfied
