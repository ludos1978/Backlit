# Phase 22: Auto Brightness Rewrite — Follow the Built-in Display

> Status: Done | Estimate: high complexity

## Goal

Rewrite the auto brightness feature: drop the Intel-only AppleLMUController approach and instead **watch the built-in display's brightness changes and sync them proportionally to external displays**. This is the approach BetterDisplay uses, and it is stable and reliable on Apple Silicon.

## Technical Approach

macOS already adjusts the built-in display's brightness automatically (based on ambient light). Backlit only needs to:
1. Poll the built-in display's current brightness every 2 seconds (`IODisplayGetFloatParameter` or the CoreDisplay private API)
2. If the brightness changes by more than a threshold (2%), sync it to the external display using the user-defined mapping curve
3. Set the external display's brightness via DDC VCP 0x10, or fall back to the gamma table (software dimming)

**Key APIs**:
- Reading built-in display brightness: `CoreDisplay_Display_GetUserBrightness(displayID)` — reliable on Apple Silicon
- Alternative: `IODisplayGetFloatParameter(service, kNilOptions, kIODisplayBrightnessKey, &brightness)`
- Setting external display brightness: reuse the existing `BrightnessService.setBrightness()`

## Tasks

### Task 1: Rewrite AutoBrightnessService — follow mode
- [x] Remove the `AppleLMUController` sensor polling logic (delete `findSensorPort`, `readAmbientLux`, etc. entirely)
- [x] Add `readBuiltinBrightness() -> Double?`: read the built-in display's current brightness (0.0-1.0)
  - Preferred: `@_silgen_name("CoreDisplay_Display_GetUserBrightness") func CoreDisplay_Display_GetUserBrightness(_ display: CGDirectDisplayID) -> Double`
  - Alternative: `IODisplayGetFloatParameter` iterating over IODisplayConnect
- [x] Add `@Published var builtinBrightness: Double = 0` to replace `lastLux`
- [x] Change the polling logic to: read built-in brightness → if it changed by > 2% → compute the external display's target brightness via the mapping curve → call BrightnessService
- [x] Mapping curve: `externalTarget = builtinBrightness * sensitivityMultiplier` (sensitivity range 0.5-1.5, default 1.0)
- [x] Keep the 30-second cooldown after manual adjustment
- [x] Keep the UserDefaults keys `fd.AutoBrightnessEnabled` and `fd.AutoBrightnessSensitivity`

**Implementation hint**: `CoreDisplay_Display_GetUserBrightness` is a private API but exists stably on macOS 14+, and open-source projects such as MonitorControl/Lunar all use it. Declaring it with `@_silgen_name` is enough. If `CoreDisplay_Display_GetUserBrightness` returns 0 (on some system versions), fall back to IODisplayGetFloatParameter.

### Task 2: Rewrite AutoBrightnessView — adapt to the new approach
- [x] Remove the `lastLux` display (there is no lux value anymore)
- [x] Change it to show "Built-in display brightness: XX%" (`builtinBrightness` shown in real time)
- [x] Change the sensor-unavailable message to "No built-in display detected" (only shown when there is no built-in display)
- [x] Keep the Sensitivity slider, with the label changed to "Sync ratio"
- [x] Add a description: "Automatically adjusts external displays to follow the built-in display's brightness"

**Implementation hint**: Change the `sensorUnavailable` logic to check `builtinBrightness > 0 || hasBuiltinDisplay`, no longer checking lux.

### Task 3: Verify reading the built-in display's brightness
- [x] Write a temporary test: at AppDelegate launch, print `CoreDisplay_Display_GetUserBrightness(builtinDisplayID)` to `~/Desktop/brightness_test.log`
- [x] Adjust the brightness slider manually and confirm the reading changes in real time (range 0.0-1.0)
- [x] If CoreDisplay returns 0 or something abnormal → switch to the IODisplayGetFloatParameter path
- [x] Delete the temporary test code once the test passes

**Implementation hint**: Filter for the built-in display ID with `CGDisplayIsBuiltin(displayID)`. For debugging, file logging is more reliable than print (a menu bar app has no stdout).

### Task 4: Build verification + integration testing
- [x] Build passes
- [x] Real test: enable auto brightness → adjust the MacBook brightness → observe whether the external display follows
- [x] Edge-case testing: unplug the external display → no crash; with no built-in display → show the message
- [x] Update the AutoBrightnessService description in `docs/CODEMAP.md`

## Acceptance Criteria

```bash
# Build passes
xcodebuild -scheme Backlit -configuration Debug build 2>&1 | tail -3

# Manual testing
# 1. Enable auto brightness → adjust the MacBook brightness → the external display brightness follows
# 2. Adjust the "Sync ratio" slider → the external display responds
# 3. Adjust the external display brightness manually → auto brightness does not override it within 30 seconds
# 4. Close the lid / unplug the display → no crash
```
