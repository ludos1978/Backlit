# Lessons Learned — Cross-Service Coordination / Concurrency / Resource Management

> Updated: 2026-03-05

## Feature Interaction / Cross-Service Coordination (Round 3-4 optimizations)

### L-008: Two Services writing the same CoreGraphics resource overwrite each other
- **Symptom**: After setting a gamma adjustment, dragging the brightness slider makes the gamma effect disappear (or vice versa)
- **Cause**: GammaService and BrightnessService both call CGSetDisplayTransfer*, and the later call completely overrides the earlier one
- **Fix**: Make GammaService the sole writer; BrightnessService stores the brightness factor in softwareBrightnessFactors, and GammaService reads it in applyFormula and multiplies it into rHi/gHi/bHi
- **Lesson**: When two Services share an underlying resource, designate a single owner; others influence it through an interface rather than writing directly
- **Date**: 2026-03-04

### L-009: macOS sleep/wake resets all CGSetDisplayTransfer* effects
- **Symptom**: Gamma adjustments and software brightness are all lost after the Mac sleeps
- **Cause**: macOS resets the display transfer function to system defaults on sleep; CGSetDisplayTransfer* effects are not persistent
- **Fix**: Register NSWorkspace.didWakeNotification and re-apply to all displays 500ms after wake
- **Lesson**: Any feature that writes display hardware state must consider the reset after sleep/wake, and tests must cover this scenario
- **Date**: 2026-03-04

### L-010: CGDisplayRegisterReconfigurationCallback must use passRetained
- **Symptom**: Theoretical crash risk: the C callback accesses a dangling pointer
- **Cause**: passUnretained does not increment the reference count; after self is released the callback accesses a dangling pointer
- **Fix**: passRetained + paired release (in stopMonitoring/deinit)
- **Lesson**: Always use passRetained for the self pointer passed to C callbacks; this has already occurred twice in the project (DisplayManager + ConfigProtectionService)
- **Date**: 2026-03-04

### L-011: AutoBrightness and manual adjustment need a cooldown mechanism
- **Symptom**: Brightness adjusted manually is overridden by AutoBrightness 2 seconds later
- **Cause**: applyBrightness only checks the difference and has no "user recently adjusted manually" protection
- **Fix**: Add an isAutoAdjust parameter to setBrightness; manual calls record lastManualAdjustDate, and AutoBrightness checks a 30s cooldown
- **Lesson**: Automatic adjustment features must pause after manual intervention
- **Date**: 2026-03-04

## Concurrency / Resource Management (Round 5 optimizations)

### L-012: The GammaService activeAdjustments dictionary must be locked
- **Symptom**: Data race risk: BrightnessService reads hasActiveAdjustment from a background queue while GammaService writes activeAdjustments from the MainActor
- **Cause**: The dictionary has no synchronization; concurrent multi-threaded reads and writes are undefined behavior in Swift (may crash or corrupt data)
- **Fix**: Add an NSLock and lock all activeAdjustments reads and writes (hasActiveAdjustment/apply/reapply/reset, etc.)
- **Lesson**: Any mutable state accessed by multiple Actors must be locked, whether or not a race is currently triggered
- **Date**: 2026-03-04

### L-013: The GammaService quantized path must sync the brightness factor
- **Symptom**: Software brightness silently stops working in quantized mode (quantizationLevels < 256)
- **Cause**: applyFormula reads the softwareBrightness factor but applyQuantizedTable does not, so the two paths are inconsistent
- **Fix**: applyQuantizedTable also reads brightnessFactor and scales rHi/gHi/bHi
- **Lesson**: When one Service has multiple execution paths, all paths must apply the same modification logic
- **Date**: 2026-03-04

### L-014: On wake, BrightnessService must reapply before GammaService
- **Symptom**: The screen briefly flashes white (full brightness) on wake before recovering
- **Cause**: When GammaService.reapply is called first, softwareBrightnessFactors has not been restored yet, so applyFormula reads 1.0 and writes it to the hardware
- **Fix**: On wake, call BrightnessService.reapply first, then GammaService.reapply (ensures the factor is ready)
- **Lesson**: Dependent reapply calls must run in dependency order; BrightnessService is the data provider for GammaService
- **Date**: 2026-03-04

### L-015: Closing an NSWindow must stop the associated SCStream
- **Symptom**: When the user clicks the red close button of a PiP/Stream window, the stream keeps running in the background and wastes resources
- **Cause**: NSWindowController does not implement NSWindowDelegate.windowWillClose, so the close event does not trigger stopCapture
- **Fix**: PiPWindowController/StreamWindowController implement windowWillClose → viewModel.stopCapture(), and set window.delegate = self
- **Lesson**: Both the system close entry (red button) and the in-app close button must clean up resources; handling only one is not enough
- **Date**: 2026-03-04

### L-016: Never call removeValue while iterating a Dictionary
- **Symptom**: NotchOverlayManager.screenParametersChanged() calls removeValue while iterating overlayWindows, a potential crash
- **Cause**: Swift Dictionary does not support mutating itself during for-in iteration; behavior is undefined
- **Fix**: Collect the keys to delete into a temporary array and delete them together after the loop
- **Lesson**: Never add or remove elements of a collection while iterating it with for-in (equivalent to ConcurrentModificationException in other languages)
- **Date**: 2026-03-04

### L-017: UserDefaults keys must have an app namespace prefix
- **Symptom**: SettingsService/AutoBrightnessService/ConfigProtectionService use bare keys (such as "launchAtLogin")
- **Cause**: Bare keys may collide with macOS system defaults or future third-party libraries, causing unexpected values to be read or system settings to be overwritten
- **Fix**: Add the `fd.` prefix uniformly (fd.launchAtLogin, fd.AutoBrightnessEnabled, etc.)
- **Lesson**: UserDefaults key naming convention: `<app_prefix>.<key>`
- **Date**: 2026-03-04

### L-018: Mirror source/target API query direction
- **Symptom**: refreshMirrorState queries with CGDisplayMirrorsDisplay(source) and always gets nil (the source does not clone anyone)
- **Cause**: CGDisplayMirrorsDisplay(X) returns "the target that X clones", and the SOURCE itself is not a cloner
- **Fix**: Query in reverse: iterate all displays and find the one where CGDisplayMirrorsDisplay(candidate) == source (that is the target)
- **Lesson**: Mirror API semantics: the SOURCE is the one being cloned, the TARGET is the cloner; query from the TARGET's perspective ("who is cloning me")
- **Date**: 2026-03-04

### L-019: IOPMAssertion must be released before creating a new assertion
- **Symptom**: ManageDisplayView leaks an IOPMAssertion each time the prevent-sleep switch is turned on; the old ID is overwritten and cannot be released
- **Cause**: createSleepAssertion() does not check sleepAssertionID != 0 and overwrites it directly
- **Fix**: Release the old assertion before creating; onDisappear releases only when !preventSleep (so it stays in effect while the switch is ON)
- **Lesson**: System resources (IOPMAssertion, IO iterators, etc.) must be strictly paired create/release; release the old one before overwriting its ID
- **Date**: 2026-03-04

## ScreenCaptureKit: capture size, not CPU, is the cost (2026-09-10)

- **Symptom**: the "Show in Window" display stream felt slow/laggy.
- **Measured** (standalone probe, 4 s per configuration, one display, 30 fps requested):

  | capture size | delivered fps | pixel throughput |
  |---|---|---|
  | 1728×1117 (native) | 21 | 157 MB/s |
  | 1920×1241 | 29 | 261 MB/s |
  | 960×620 | 31 | 72 MB/s |

  The frame rate is bound by how many pixels WindowServer has to hand over, not by the
  consumer. A 4K display is 4.8× larger again, so a native-size capture of a 3840×2160
  monitor cannot reach 30 fps at all.
- **Fix**: ask `SCStreamConfiguration` for the size you actually display (the window's
  backing pixel size, clamped to the display's native size) and follow window resizes with
  `SCStream.updateConfiguration(_:)`. ScreenCaptureKit scales on the GPU during capture,
  so the downscale is free while the transport savings are the full difference.
- **Also free**: stop the stream while the window is occluded or minimized
  (`windowDidChangeOcclusionState`) — a hidden window otherwise keeps a full capture
  pipeline alive.
- **Not the problem**: the per-frame pixel analysis. The adaptive-brightness lightness
  loop over a 240×135 frame measures 0.126 ms (a vImage histogram would be 0.042 ms), which
  at 2–8 fps is noise. Do not optimize the analysis before the capture size.
- The lightness sampler already captures at 1/16 resolution and only runs when the mode
  actually uses screen content, so it is not a candidate for further trimming.
