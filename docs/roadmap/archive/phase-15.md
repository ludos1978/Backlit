# Phase 15: Interaction Experience Polish

> Goal: give every operation instant visual feedback, so the overall interaction feels lively and smooth

## Task List

- [x] Add Loading states and visual feedback to all slow operations
  - Implementation hints:
    1. `DisplayModeListView.swift`: when switching resolution, show a small `ProgressView()` on the clicked row, and disable the other rows
    2. `ColorProfileView.swift`: show a ProgressView on the corresponding row when applying an ICC Profile
    3. `MirrorView.swift`: show status when enabling/disabling mirroring
    4. Unified pattern: create a `LoadingButton` component - after a click it automatically shows a spinner until the async operation completes
    5. For all Service methods that are async, call sites uniformly use the `Task { isLoading = true; defer { isLoading = false }; await ... }` pattern
  - Verify: click any switching operation -> immediately see the loading animation -> it disappears when done

- [x] Add live value display and haptic feedback to Slider operations
  - Implementation hints:
    1. Show the current percentage value next to every Slider (brightness, contrast, gamma, etc.), updating live while dragging
    2. On release, briefly highlight the value text (change color with `withAnimation(.easeOut(duration: 0.3))`)
    3. Add `.sensoryFeedback(.selection, trigger: value)` to sliders, or use `NSHapticFeedbackManager` (on a MacBook trackpad)
    4. Unified value format: `"75%"` rather than `"0.75"` or `"0%"` (image adjustment currently shows 0% because the value really is 0, but the format needs to be consistent)
  - Verify: drag a slider -> the percentage number beside it follows live -> a slight animation feedback on release

- [x] Add Section expand/collapse animations
  - Implementation hints:
    1. For all Sections in `DisplayDetailView.swift`, wrap the expand/collapse state change in `withAnimation(.spring(response: 0.3, dampingFraction: 0.8))`
    2. Add enter/exit animation to Section content with `.transition(.opacity.combined(with: .move(edge: .top)))`
    3. The arrow icon in the Section header uses `.rotationEffect` to rotate 90°->0° on expand (or use a chevron.right -> chevron.down switching animation)
    4. Make sure the animation does not hurt performance: collapsed Section content should be conditionally rendered `if expanded { ... }` rather than hidden with opacity
  - Verify: click a Section header -> content expands/collapses smoothly, with the arrow rotation animation

- [x] Improve the overall interaction feel of the menu
  - Implementation hints:
    1. Add a hover effect on row clicks: `.onHover { isHovered = $0 }` + background color transition `Color.primary.opacity(isHovered ? 0.05 : 0)`
    2. Add a scale animation on button press: `.scaleEffect(isPressed ? 0.97 : 1.0)` + `.animation(.easeInOut(duration: 0.1))`
    3. Use `Divider().opacity(0.3)` for separators between list items to make the visual hierarchy clearer
    4. Check that all Toggle switches have a unified style and that state changes are smooth
  - Verify: hovering over rows gives a fade in/out highlight -> clicking gives slight scale feedback -> the overall feel is lively

- [x] Fix the @StateObject singleton anti-pattern
  - Implementation hints:
    1. `MenuBarView.swift`: `@StateObject private var updateService = UpdateService.shared` -> change to `@ObservedObject private var updateService = UpdateService.shared`
    2. Same for `SettingsService.shared`
    3. Check all Views that wrap a shared singleton in `@StateObject`, and change them uniformly to `@ObservedObject`
    4. Use `@StateObject` only for objects the View creates and owns itself (e.g. `@StateObject private var vm = SomeViewModel()`)
  - Verify: builds successfully + opening and closing the menu repeatedly causes no flicker from duplicate subscriptions

**Phase Acceptance**: builds successfully + subjectively smooth and lively experience: clicks give instant feedback, slider dragging is smooth, expand/collapse is animated, no stutter
