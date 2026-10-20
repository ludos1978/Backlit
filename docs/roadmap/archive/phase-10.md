# Phase 10: Virtual Displays ✅

> Core value: create dummy displays / virtual screens, extend HiDPI support

## Task List

- [x] Implement virtual display creation (`Backlit/Services/VirtualDisplayService.swift`)
  - Implementation hints:
    Use the macOS 14+ `CGVirtualDisplay` API:
    ```swift
    import CoreGraphics

    let descriptor = CGVirtualDisplayDescriptor()
    descriptor.queue = DispatchQueue.global()
    descriptor.name = "Backlit Virtual"
    descriptor.maxPixelsWide = 3840
    descriptor.maxPixelsHigh = 2160
    descriptor.sizeInMillimeters = CGSize(width: 600, height: 340) // 27 inch
    descriptor.productID = 0x1234
    descriptor.vendorID = 0x5678
    descriptor.serialNum = 0

    let display = CGVirtualDisplay(descriptor: descriptor)

    // Add display modes
    let settings = CGVirtualDisplaySettings()
    settings.hiDPI = 1  // Enable HiDPI
    let mode = CGVirtualDisplayMode(width: 1920, height: 1080, refreshRate: 60)
    settings.modes = [mode, ...]
    display?.applySettings(settings)
    ```
    Features:
    - Create a virtual display (specify name, resolution, DPI)
    - Destroy a virtual display
    - List currently active virtual displays
    - Persist configuration (UserDefaults/JSON), auto-create on launch
    Note: once created, the system treats the virtual display as a real display, usable for HiDPI and Sidecar scenarios.
  - Verify: after creating a virtual display, a new display appears in System Settings

- [x] Implement HiDPI enhancement (based on virtual displays) (`HiDPIService` extension)
  - Implementation hints:
    Phase 3 implemented HiDPI via plist override; here we enhance it with a virtual display approach:
    1. Create a virtual display matching the external display's resolution (HiDPI enabled)
    2. Mirror the external display to the virtual display
    3. The external display inherits the virtual display's HiDPI modes
    This is the core way BetterDisplay implements HiDPI - no system file modification, no SIP needed.
    Add a "High Resolution (HiDPI)" toggle in ResolutionService; when enabled, automatically create a paired virtual display.
  - Verify: after enabling HiDPI on an external display, scaled modes appear in the resolution list

- [x] Implement the virtual display management UI (`Backlit/Views/VirtualDisplayView.swift`)
  - Implementation hints:
    Add a "Displays and Virtual Screens" entry in the "Tools" area (following the screenshot).
    Clicking opens a management panel/window:
    - Current virtual display list (name, resolution, status)
    - "+" button to add a new virtual display (pops up a configuration form: name, resolution, DPI)
    - A delete button on each row
    - Configuration persistence option (auto-create on next launch)
  - Verify: the full create/delete flow of virtual displays works

- [x] Implement the "High Resolution (HiDPI)" one-click toggle UI
  - Implementation hints:
    Add a "High Resolution (HiDPI)" row (blue ⊕ icon) in each display's menu area, following the screenshot.
    The Toggle controls: when on, automatically create a paired virtual display and mirror;
    when off, destroy the virtual display and cancel mirroring.
    State persisted to UserDefaults.
  - Verify: after enabling HiDPI, the external display's resolution list changes

## Phase Acceptance

- Virtual display creation/destruction works
- HiDPI takes effect via the virtual display approach
- The virtual display management UI is complete
- Configuration persistence works (restored after restart)

**After completion**: running project-optimize for reflection is recommended
