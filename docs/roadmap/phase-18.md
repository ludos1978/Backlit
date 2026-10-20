# Phase 18: Stability Hardening

> Status: Done | Estimate: medium complexity

## Goal

Extend the timeout protection pattern for blocking CG calls across the whole project, ensure HiDPI state is restored automatically after sleep/wake, and ensure the arrangement is re-applied automatically after a display configuration change.

## Tasks

### Task 1: Unified timeout protection for blocking CG calls
- [x] Extract VirtualDisplayService's `runWithTimeout` into a shared utility function (put it in `Utilities/` or `Services/CGHelpers.swift`)
- [x] MirrorService: wrap the `CGCompleteDisplayConfiguration` calls in `enableMirror`/`disableMirror` with `runWithTimeout`
- [x] ArrangementService: wrap the `CGCompleteDisplayConfiguration` call in `setPosition` with `runWithTimeout`
- [x] ResolutionService: add 10-second timeout protection to `applyModeSync` (currently waits forever on `CGCompleteDisplayConfiguration`)

**Implementation hint**: `runWithTimeout` has already been proven to work in VirtualDisplayService; reuse the same pattern directly. Watch the `@Sendable` constraint.

### Task 2: Automatic re-arrangement on display configuration change
- [x] Register `CGDisplayRegisterReconfigurationCallback` in AppDelegate or DisplayManager
- [x] Detect in the callback that the configuration change has finished (`flags` contains `beginConfigurationFlag`, then wait for the callback that does not)
- [x] After the configuration change completes, call `displayManager.arrangeExternalAboveBuiltin()` with a 500ms delay
- [x] Avoid duplicate triggers: use a debounce mechanism so that when the callback fires multiple times within 500ms only the last one runs

**Implementation hint**: Use `Unmanaged.passRetained(self)` for the context parameter of `CGDisplayRegisterReconfigurationCallback` to prevent dangling pointers (already a rule in CLAUDE.md). The callback runs on a system thread; switch back to the main thread with `DispatchQueue.main.async`.

### Task 3: Automatically restore HiDPI after sleep/wake
- [x] In AppDelegate's `didWakeNotification` handler, check whether `VirtualDisplayService.hiDPIActiveDisplayIDs` has active sessions
- [x] If so, check whether the virtual display is still online (`CGDisplayIsOnline`); if it is gone, recreate it + mirror + apply the resolution
- [x] Restore sequence: create → apply settings → sleep 500ms → mirror → sleep 500ms → setDisplayMode → arrangeExternalAboveBuiltin
- [x] Persist HiDPI state to UserDefaults (`fd.hiDPI.activePhysicalIDs`) so it can also be restored after an app restart

**Implementation hint**: After wake, WindowServer needs time to stabilize, so add a 2-second initial delay to the whole restore sequence. Refer to the existing `enableHiDPIVirtual` flow in VirtualDisplayService.

### Task 4: Error recovery and user feedback
- [x] Show a menu bar status message when a CG call times out (not a popup; use the `statusMessage` pattern)
- [x] Prompt the user to re-enable HiDPI manually when HiDPI restoration fails
- [x] Automatically disable HiDPI and notify the user after 3 consecutive failures

**Implementation hint**: Reuse the existing `statusMessage` pattern in HiDPIVirtualRowView.

## Acceptance Criteria

```bash
# Build passes
xcodebuild -scheme Backlit -configuration Debug build 2>&1 | tail -3

# Manual testing
# 1. Enable HiDPI → close lid to sleep → wake → HiDPI is restored automatically + arrangement is correct
# 2. Enable HiDPI → unplug the external display → replug → no crash
# 3. Switch resolution → arrangement stays directly above
```
