# Phase 16: Comprehensive Bug Fixes

> Goal: fix the 37 issues found in the audit, executed in three batches by priority

## Batch A: P0 - Crashes/Data Loss (5 items)

- [x] A1: Fix the race condition when AutoBrightnessService iterates displays
  - **File**: `AutoBrightnessService.swift` applyBrightness method
  - **Problem**: accessing `DisplayManagerAccessor.shared.displays` and modifying `display.brightness` has no synchronization protection, and may crash on hot-plug
  - **Fix**: take an array snapshot with `let snapshot = displays` before iterating, or add `@MainActor` to ensure main-thread access
  - **Verify**: hot-plugging a display with auto brightness enabled does not crash

- [x] A2: Fix the BrightnessService refreshBrightness memory leak
  - **File**: `BrightnessService.swift` refreshBrightness method
  - **Problem**: the completion handler of DDCService.shared.readAsync() implicitly captures self, so the callback dangles after the display is released
  - **Fix**: capture with `[weak self]` in the completion, and `guard let self else { return }` inside the callback
  - **Verify**: after repeatedly refreshing brightness, Instruments shows no memory leak

- [x] A3: Fix the BrightnessSliderView onChange boundary condition
  - **File**: `BrightnessSliderView.swift` onChange(of: display.brightness)
  - **Problem**: `abs(newValue - localBrightness) > 1` uses `>`, so a change of exactly 1% does not sync
  - **Fix**: change to `abs(newValue - localBrightness) >= 1`
  - **Verify**: externally change brightness by 1% -> UI syncs and updates

- [x] A4: Fix the DDCService readBatchVCPCodes sparse cache problem
  - **File**: `DDCService.swift` readBatchVCPCodes method
  - **Problem**: when building the dictionary from the cache, compactMap skips missing codes, so the result has fewer entries than requested with no indication
  - **Fix**: codes that miss the cache go through an actual read, and the final result explicitly marks which reads failed (return `[UInt8: UInt16?]`)
  - **Verify**: batch read 11 VCP codes -> all are returned (success or an explicit failure)

- [x] A5: Fix the lack of error handling in DisplayModeListView resolution switching
  - **File**: `DisplayModeListView.swift` switchTo method
  - **Problem**: after `ResolutionService.shared.setDisplayMode()` fails there is no retry and no user notice
  - **Fix**: on failure show an error Toast (using `@State var errorMessage`), and add one automatic retry
  - **Verify**: simulate a switch failure -> the user sees an error message

## Batch B: P1 - Functional Anomalies (11 items)

- [x] B1: Fix the hardcoded initial brightness value in DisplayInfo
  - **File**: `DisplayInfo.swift` init
  - **Problem**: the built-in display brightness is initialized to 50.0 instead of reading the actual value
  - **Fix**: immediately after init completes, call `BrightnessService.shared.refreshBrightness(for: self)` to read the real value
  - **Verify**: open the app -> the brightness slider shows the real system brightness

- [x] B2: Fix the single-display state key in GammaService
  - **File**: `GammaService.swift` saveState/loadSavedState
  - **Problem**: the UserDefaults key is fixed to `"GammaService.savedAdjustment"`, so with multiple displays only the last one is saved
  - **Fix**: change the key to `"GammaService.savedAdjustment.\(displayID)"`
  - **Verify**: adjust gamma on two displays separately -> restart the app -> each restores its correct value

- [x] B3: Fix MirrorView async defer executing too early
  - **File**: `MirrorView.swift` toggleMirror method
  - **Problem**: in an async function, `defer { isSwitching = false }` runs before the await, so the loading state disappears instantly
  - **Fix**: remove the defer, and set `isSwitching = false` after the await completes and in the catch block respectively
  - **Verify**: click the mirror button -> the loading animation lasts until the operation completes

- [x] B4: Fix the ColorProfileView loadProfiles race condition
  - **File**: `ColorProfileView.swift` loadProfiles
  - **Problem**: after the View disappears, the async task still updates @State, triggering a SwiftUI warning
  - **Fix**: use `.task { }` instead of a manual Task (SwiftUI cancels it automatically), or add `@State var loadTask: Task<Void, Never>?` and cancel it in onDisappear
  - **Verify**: quickly expand/collapse the color panel -> no console warning

- [x] B5: Fix the non-MainActor state update in IntegratedControlView
  - **File**: `IntegratedControlView.swift` readFromDevice
  - **Problem**: a non-@MainActor method directly updates @State variables
  - **Fix**: mark the method `@MainActor`, or use `await MainActor.run { isReading = false }`
  - **Verify**: builds with no concurrency warnings

- [x] B6: Fix the ColorProfileView applyProfile concurrency problem
  - **File**: `ColorProfileView.swift` applyProfile
  - **Problem**: the function is not marked @MainActor but updates UI state internally
  - **Fix**: mark it `@MainActor`
  - **Verify**: apply an ICC Profile -> no concurrency warnings

- [x] B7: Verify the HiDPIService plist path construction (confirmed correct, no change needed)
  - **File**: `HiDPIService.swift` overridePlistURL
  - **Problem**: the audit pointed out that the vendor/product path may be incorrect
  - **Fix**: check whether the actually generated plist path matches the path macOS expects (`/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-XXXX/DisplayProductID-YYYY`), and correct any mismatch
  - **Verify**: write the plist -> confirm the path is correct with `ls` -> after re-enumeration, HiDPI appears in the mode list

- [x] B8: Fix DisplayDetailView task not being cancelled
  - **File**: `DisplayDetailView.swift` .task(id:)
  - **Problem**: after a display disconnects and reconnects, the old task may update stale data
  - **Fix**: use `Task.checkCancellation()` to check the cancellation state after awaits
  - **Verify**: hot-plug a display -> the detail panel data is correct

- [x] B9: Fix the inaccurate return value of RotationService
  - **File**: `RotationService.swift` setRotation
  - **Problem**: it returns the result of `IOServiceRequestProbe`, but that only means the probe request succeeded, not that the rotation took effect
  - **Fix**: after the probe sleep 100ms, then verify the actual angle with `CGDisplayRotation(displayID)`
  - **Verify**: rotate a display -> the return value accurately reflects whether it took effect

- [x] B10: Clean up the dead code in DisplayInfo.lookupDisplayName
  - **File**: `DisplayInfo.swift` lookupDisplayName
  - **Problem**: this method is never called (it has been replaced by NSScreen.localizedName)
  - **Fix**: delete the whole method
  - **Verify**: builds successfully

- [x] B11: Fix the ResolutionService .permanently vs .forSession inconsistency
  - **File**: `ResolutionService.swift` vs `ArrangementService.swift`
  - **Problem**: resolution uses .permanently while arrangement uses .forSession, so the behavior is inconsistent
  - **Fix**: change both to `.forSession` (safer to let macOS restore system settings after restart), or use `.permanently` for both and explain in the docs
  - **Verify**: switch resolution/arrangement -> behavior after restart is as expected

## Batch C: P2 - Minor Issues/Code Quality (21 items)

- [x] C1: AutoBrightnessService readAmbientLux may block the main thread
  - **Fix**: make sure it is called from a background thread, or dispatch to a background queue inside the method

- [x] C2: AutoBrightnessService lux scaling constants are undocumented
  - **Fix**: add a comment explaining the derivation of `rawAvg / 1_000_000.0 * 1_000.0`

- [x] C3: BrightnessSliderView DispatchAfter cannot be cancelled
  - **Fix**: replace with `DispatchWorkItem`, or use SwiftUI `.task` + `Task.sleep`

- [x] C4: ColorProfileService ICC header assumes ASCII
  - **Fix**: add an encoding check, with a fallback for non-ASCII

- [x] C5: DDCService buffer count capture is fragile
  - **Fix**: inline the count or extract a helper method

- [x] C6: Redundant filter logic in DisplayModeListView
  - **Fix**: simplify `.filter { $0.isNative || (!$0.isHiDPI && $0.isNative) || ($0.isNative) }` to `.filter { $0.isNative }`

- [x] C7: ImageAdjustmentView quantization boundary condition
  - **Fix**: change `quantLevels >= 256` to `quantLevels >= 255` or `== 256`

- [x] C8: ImageAdjustmentView resetAll lacks a MainActor guarantee
  - **Fix**: confirm GammaService.restoreColorSync() is called on the MainActor

- [x] C9: MenuBarView update check may block the UI
  - **Fix**: add a timeout and move it to run in the background

- [x] C10: HiDPIService refreshModes is not awaited
  - **Fix**: store the Task reference and cancel it at the appropriate time

- [x] C11: DDCService lock release and callback order are inconsistent
  - **Fix**: unify to the "unlock first, then callback" pattern

- [x] C12: VirtualDisplayService addAndCreate does not roll back on creation failure
  - **Fix**: remove it from configs when `create()` fails

- [x] C13: ArrangementService .forSession may not be what the user expects
  - **Fix**: handle together with B11

- [x] C14: UpdateService JSON parsing fails silently
  - **Fix**: add a `print("[UpdateService] JSON parse error:")` log

- [x] C15: BrightnessService overuses withCheckedContinuation
  - **Fix**: return directly from a dispatch async, or simplify to a synchronous call

- [x] C16: DisplayDetailView @EnvironmentObject MainActor is not explicitly annotated
  - **Fix**: add a comment explaining it

- [x] C17: BrightnessSliderView @ObservedObject concurrency safety
  - **Fix**: ensure all DisplayInfo updates happen on the main thread

- [x] C18: DDCService memory pointer theoretical safety issue
  - **Fix**: confirm the use of withUnsafeMutableBytes is correct (it is, marked as reviewed)

- [x] C19: BrightnessService IOObjectRelease iterator cleanup
  - **Fix**: confirm the iterator is released after being fully drained (it is, marked as reviewed)

- [x] C20: DisplayDetailView ResolutionSliderView reference
  - **Fix**: confirm the component exists, otherwise delete the reference

- [x] C21: Global code cleanup - delete unused imports and commented-out code
  - **Fix**: scan and clean up globally

## Acceptance Criteria

```bash
# 1. Build with no warnings
xcodebuild -scheme Backlit -configuration Debug build 2>&1 | grep -E "warning:|error:" | head -20

# 2. Manual test checklist
# - Open the app -> brightness shows the real value (not 50%)
# - Hot-plug a display -> no crash
# - Adjust gamma -> close the panel -> screen restored
# - Mirror operation -> loading animation shown throughout
# - Switch color Profile -> no console warnings
# - HiDPI toggle -> plist written to the correct path
```
