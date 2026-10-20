# Phase 3: Resolution Management and HiDPI ✅

> Core value: resolution switching and HiDPI support, BetterDisplay's core selling point

## Task List

- [x] Implement resolution mode enumeration (`Backlit/Models/DisplayMode.swift`)
  - Implementation hint:
    Model properties: `width: Int`, `height: Int`, `refreshRate: Double`, `bitDepth: Int`,
    `isHiDPI: Bool`, `isNative: Bool`, `ioDisplayModeID: Int32`.
    Use `CGDisplayCopyAllDisplayModes(displayID, options)` to get all modes.
    Add `kCGDisplayShowDuplicateLowResolutionModes: true` to the options dictionary to show HiDPI modes.
    Get the current mode with `CGDisplayCopyDisplayMode(displayID)`.
    Detect HiDPI: it is HiDPI when `CGDisplayModeGetPixelWidth > CGDisplayModeGetWidth`.
    Display format modeled on BetterDisplay: `1470x956` + tags (notch/60Hz/10bit).
  - Verify: can list all modes of the built-in screen, including 1470x956 (HiDPI), 2560x1664 (native), etc.

- [x] Implement resolution switching (`Backlit/Services/ResolutionService.swift`)
  - Implementation hint:
    ```swift
    func setDisplayMode(_ mode: CGDisplayMode, for displayID: CGDirectDisplayID) -> Bool
    ```
    Switch in three steps: `CGBeginDisplayConfiguration` → `CGConfigureDisplayWithDisplayMode` →
    `CGCompleteDisplayConfiguration(.permanently)`.
    Save the current mode before switching and roll back on failure.
    Note: switching to HiDPI modes may require the private API `CGSConfigureDisplayMode`
    or injecting HiDPI modes by creating a custom timing (covered in depth in the Phase 10 virtual display part).
  - Verify: the display's actual resolution changes after switching

- [x] Implement the resolution slider UI (`Backlit/Views/ResolutionSliderView.swift`)
  - Implementation hint:
    Modeled on the resolution area of the BetterDisplay screenshot: horizontal Slider + current resolution text on the right.
    The Slider's steps correspond to indices in the list of available modes.
    Small display icon on the left, `1470x956` text on the right.
    While dragging, the resolution text previews changes in real time; the switch happens on release.
  - Verify: dragging the slider changes the resolution text

- [x] Implement the display mode list UI (`Backlit/Views/DisplayModeListView.swift`)
  - Implementation hint:
    An expandable "Display Modes" section (modeled on the BetterDisplay screenshot layout).
    Two groups:
    1. "Default and native modes": native resolution + system default HiDPI modes
    2. "Matching default filtered modes": other available modes
    One row per mode: icon (●/◉/⊙) + resolution text + tags on the right (notch/60Hz/10bit).
    The currently selected mode is highlighted (blue circular icon).
    Click to switch.
    Add a "favorites" feature and a "Filter..." button (modeled on the ☆ manage and ⊙ filter in the screenshot).
  - Verify: the display mode list matches the BetterDisplay screenshot layout

- [x] HiDPI mode injection (`Backlit/Services/HiDPIService.swift`)
  - Implementation hint:
    External displays do not offer HiDPI modes by default. Enable them in one of these ways:
    1. Use `CGVirtualDisplay` to create a virtual display matching the external resolution (recommended, refined in Phase 10)
    2. Or modify the IOKit display override plist to inject custom resolutions
       Path: `/System/Library/Displays/Contents/Resources/Overrides/`
       Format: `DisplayVendorID-XXXX/DisplayProductID-XXXX`
    Phase 3 implements option 2 (plist override) first; Phase 10 later enhances it with the virtual display option.
    Note: macOS SIP protects system directories, so the user must be guided to disable SIP or use a user-level override.
  - Verify: the external display gains HiDPI scaled modes it did not have before

## Phase Acceptance

- The resolution mode lists of built-in and external displays are fully shown
- Clicking a mode list item successfully switches the resolution
- The resolution slider works correctly
- The display mode list UI matches the BetterDisplay style

**After completion**: running project-optimize for reflection is recommended
