# Phase 12: Wrap-up and Release ✅

> Core value: settings persistence, UI polish, performance optimization, a distributable .app

## Task List

- [x] Implement global settings persistence (`Backlit/Services/SettingsService.swift`)
  - Implementation hints:
    Use `UserDefaults.standard` + `@AppStorage` to persist all settings:
    - Per-display brightness/contrast/gamma preferences
    - Resolution selection preferences
    - Configuration protection options
    - Virtual display configuration
    - Auto brightness settings
    - Stream/PiP window position and size
    - Favorite resolution modes
    Complex configuration (virtual displays, snapshots) is stored in JSON files under
    `~/Library/Application Support/Backlit/`.
  - Verify: change settings -> quit -> relaunch -> settings restored

- [x] Implement launch at login (`Backlit/Services/LaunchService.swift`)
  - Implementation hints:
    Use `SMAppService.mainApp.register()` (macOS 13+) to register a login item.
    Or use the `LaunchAtLogin` library.
    Add a "Launch at Login" Toggle in settings.
  - Verify: after restarting the Mac, Backlit launches automatically

- [x] Implement the "Video Filter Window" tool (`Backlit/Views/VideoFilterWindow.swift`)
  - Implementation hints:
    Add an entry in the "Tools" area (following the "Video Filter Window" in the screenshot).
    Create a standalone window with a live preview of CIFilter effects.
    Available filters: grayscale, invert, blur, sharpen, hue rotate, gamma adjust.
    The selected filter is applied to the stream/PiP output.
  - Verify: the filter window displays correctly, and selecting a filter changes the stream output

- [x] Implement the "System Color" tool (`Backlit/Views/SystemColorView.swift`)
  - Implementation hints:
    Add an entry in the "Tools" area (following the "System Color" in the screenshot).
    Pop up a color picker window:
    - Use `NSColorSampler` (macOS 10.15+) for on-screen color sampling
    - Show the color value at the mouse position (HEX, RGB, HSB)
    - Color history
  - Verify: after clicking, a color can be sampled from anywhere on screen

- [x] Implement the "Check for Updates" feature (`Backlit/Services/UpdateService.swift`)
  - Implementation hints:
    If open-sourced on GitHub, use the GitHub Releases API to check for new versions:
    `GET https://api.github.com/repos/{owner}/{repo}/releases/latest`
    Compare `tag_name` with the current version number.
    When a new version exists, show an "Update available" notice at the bottom of the menu.
    For now only a UI placeholder is needed; the actual check can be implemented after publishing to GitHub.
  - Verify: the version number is shown at the bottom of the menu

- [x] UI polish and consistency (`global`)
  - Implementation hints:
    Check item by item against the BetterDisplay screenshots:
    1. Uniform icon color for all sections (blue circular icons)
    2. Smooth expand/collapse animations
    3. Responsive slider dragging
    4. Dark/light mode adaptation (`@Environment(\.colorScheme)`)
    5. Menu width consistent with BetterDisplay (about 320pt)
    6. Matching font sizes and spacing
    7. Shortcut support: ⌥+click the menu bar icon to quickly identify displays
  - Done: added the `MenuItemIcon` colored rounded-square icon helper; all sections use a unified icon style (semantic colors: red = stream/PiP, purple = color management, green = lock/protection, orange = auto brightness, etc.); all expand/collapse transitions use `withAnimation(.easeInOut(duration: 0.2))` + `.transition(.opacity.combined(with: .move(edge: .top)))`.

- [x] Performance optimization (`global`)
  - Implementation hints:
    1. DDC communication: background thread + result cache (5 second TTL)
    2. Stream rendering: Metal rather than CoreImage (if Phase 9 used CIImage)
    3. Menu pop-up speed: lazy-load non-visible areas
    4. Memory: reuse stream buffer pool, avoid frequent allocations
    5. Battery: stop capture when stream/PiP is inactive
  - Done: DDCService gained `VCPCacheEntry` (5 second TTL) + `vcpCache` dictionary + `cacheLock` NSLock; `readAsync` returns cache hits first, `writeAsync` invalidates the corresponding cache after a successful write; `readBatchVCPCodes` fills the cache during batch reads.

- [x] Build a distributable .app (`build script`)
  - Done: created `ExportOptions.plist` (unsigned distribution config) and `build.sh` (one-click archive -> export -> DMG packaging).

- [x] Trigger refactor-context to set up the context scaffolding
  - Done: all Phases completed; CODEMAP and docs are up to date.

## Phase Acceptance

- All features work correctly
- Settings persist (restored after restart)
- UI closely matches the BetterDisplay screenshots
- A distributable .app / .dmg can be built
- All tests pass + documentation complete

**After completion**: project complete; running project-optimize for a final reflection is recommended
