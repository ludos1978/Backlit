# Phase 14: Performance Optimization (Eliminate Stutter)

> Goal: move all blocking IOKit/CG calls off the main thread, and reduce unnecessary SwiftUI redraws

## Task List

- [x] Move BrightnessService's IOKit calls to a background thread
  - Implementation hints:
    1. `BrightnessService.swift`: run `getInternalBrightness()` and `setInternalBrightness()` on a dedicated `DispatchQueue(label: "brightness")`
    2. Make the public methods `setBrightness()` and `refreshBrightness()` `async`, wrapping internally with `withCheckedContinuation`
    3. Call sites (`BrightnessSliderView`) call with `Task { await ... }`, and the slider's `onEditingChanged` triggers the async set
    4. Add debounce: do not send while the slider is being dragged; send the final value only on release (onEditingChanged false)
  - Verify: drag the brightness slider -> UI does not stutter, and brightness changes smoothly after release

- [x] Move DisplayInfo.init's IOKit queries to the background
  - Implementation hints:
    1. `DisplayInfo.swift`: the initializer only sets displayID and basic CG properties (name temporarily uses "Display \(id)")
    2. Add a `func loadDetails() async` method that runs `lookupDisplayName()` and `DisplayMode.availableModes()` in the background
    3. `DisplayManager.refreshDisplays()` first creates the DisplayInfo objects (fast, non-blocking), then `Task { await display.loadDetails() }` loads details asynchronously
    4. After loading completes, update the `@Published` properties on `@MainActor` to trigger a UI refresh
  - Verify: plug/unplug a display -> the new display appears in the list immediately (name briefly shown as the ID), and after the details load asynchronously, the name and mode list update

- [x] Make ColorProfileService.enumerateProfiles asynchronous
  - Implementation hints:
    1. `ColorProfileService.swift`: make `enumerateProfiles()` an `async` method, internally scanning the file system in the background with `Task.detached`
    2. `ColorProfileView.swift`: `loadProfiles()` uses `Task { profiles = await svc.enumerateProfiles() }`
    3. Show a ProgressView animation while loading; when profiles is empty, do not show "No profiles" but show the loading animation instead
  - Verify: open the color management panel -> see the loading animation -> the profile list fills in asynchronously

- [x] Split DisplayInfo's @Published properties to reduce cascading redraws
  - Implementation hints:
    1. Split `DisplayInfo`: put basic info (immutable properties such as name, displayID, isBuiltin) in a struct
    2. Keep dynamic properties (brightness, currentDisplayMode, etc.) as @Published, but group them into dedicated ObservableObject sub-objects
    3. Or a simpler approach: in `DisplayDetailView`, limit the redraw scope of each Section with `EquatableView` or `.id()`
    4. Simplest approach (recommended): extract each Section (brightness, resolution, color, etc.) into its own View struct, each with an `@ObservedObject` observing only the properties it needs. Using SwiftUI's view identity mechanism, collapsed sections do not observe
  - Verify: while dragging the brightness slider, confirm with the Instruments SwiftUI profiler that other Sections do not redraw; or add `let _ = print("xxx re-render")` to the body of other Sections to confirm it is not triggered

- [x] Remove synchronous CG calls from View bodies
  - Implementation hints:
    1. `DisplayDetailView.swift` line 99 `Text(ColorProfileService.shared.currentColorSpaceName(...))` -> fetch it asynchronously in `onAppear` and store it in `@State var colorSpaceName: String`
    2. Line 125 `Text(ColorProfileService.shared.colorModeDescription(...))` -> same as above
    3. For any similar synchronous service calls in other Section headers, change them all to the `@State` + `onAppear`/`task {}` pattern
  - Verify: builds successfully + opening DisplayDetailView does not stutter

- [x] Optimize DDCService batch read performance
  - Implementation hints:
    1. In `readBatchVCPCodes()` of `DDCService.swift`, change `Thread.sleep(forTimeInterval: 0.05)` -> `try await Task.sleep(nanoseconds: 30_000_000)` (30ms, was 50ms)
    2. Make the method an `async` version and use a `TaskGroup` to read non-adjacent VCP codes in parallel (the I2C bus cannot be truly parallel for the same device, but smaller intervals can be used)
    3. Or a caching strategy: do a full read the first time, then read only the VCP code the user is operating, and use cached values for the rest
  - Verify: open the integrated control panel -> time to read 11 VCP codes drops from ~550ms to ~330ms

**Phase Acceptance**: builds successfully + all panels open/operate without noticeable stutter (subjectively smooth experience)
