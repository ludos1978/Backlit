# Phase 4: Screen Rotation and Display Arrangement ✅

> Core value: screen rotation and spatial arrangement of multiple displays

## Task List

- [x] Implement screen rotation (`Backlit/Services/RotationService.swift`)
  - Implementation hint:
    Use `CGBeginDisplayConfiguration` → `CGConfigureDisplayOrigin` together with rotation.
    Rotation on macOS is set through IOKit:
    ```swift
    IOServiceRequestProbe(service, kIOFBSetTransform)  // trigger rotation
    ```
    Or use `CGDisplayRotation()` to get the current rotation angle,
    and set rotation through the private API `CGSConfigureDisplayMode`.
    Alternative: follow the approach of the `displayplacer` CLI tool and operate directly through IOKit.
    Supported angles: 0°, 90°, 180°, 270°.
  - Verify: after choosing 90° rotation, the display image actually rotates

- [x] Implement the screen rotation UI (`Backlit/Views/RotationView.swift`)
  - Implementation hint:
    An expandable "Screen Rotation" section.
    Four options: rotate screen 90°/180°/270° + turn rotation off.
    One row per option, with a rotation direction arrow icon (↻/↓/←) on the left and text on the right.
    The current rotation state is highlighted.
    Modeled on the screen rotation area layout of the BetterDisplay screenshot.
  - Verify: the UI shows four rotation options and clicking one actually rotates the screen

- [x] Implement display arrangement (`Backlit/Services/ArrangementService.swift`)
  - Implementation hint:
    Use `CGBeginDisplayConfiguration` → `CGConfigureDisplayOrigin(config, displayID, x, y)`
    → `CGCompleteDisplayConfiguration` to set the display position in the virtual desktop.
    Get the current position: the origin returned by `CGDisplayBounds(displayID)`.
    Coordinate system for multiple displays: the main display's top-left is (0,0), other displays are offset relative to it.
  - Verify: after adjusting a display's position in code, the arrangement in System Preferences really changes

- [x] Implement the arrange displays UI (`Backlit/Views/ArrangementView.swift`)
  - Implementation hint:
    An expandable "Arrange Displays" section.
    The content is a grid view, modeled on the BetterDisplay screenshot:
    display thumbnails (blue rectangle + name) on a gray background, draggable.
    Use SwiftUI's `.gesture(DragGesture())` to implement dragging.
    Display rectangle sizes are scaled proportionally to the actual resolution.
    After dragging ends, call ArrangementService to update the position.
    The grid background uses light gray squares to represent the virtual desktop extent.
  - Verify: the display arrangement view matches the BetterDisplay screenshot layout, and positions update after dragging

- [x] Set as main display feature (`Backlit/Services/DisplayManager.swift` extension)
  - Implementation hint:
    Add `func setAsMainDisplay(_ displayID: CGDirectDisplayID)` to DisplayManager.
    Use `CGBeginDisplayConfiguration` → `CGConfigureDisplayOrigin(config, displayID, 0, 0)`
    to move the target display to the origin (on macOS the main display = the display at the coordinate origin).
    Adjust the coordinates of other displays accordingly.
  - Verify: after setting as main display, the Dock and menu bar move to the target display

## Phase Acceptance

- Screen rotation works in all four directions
- Visual drag-and-drop display arrangement works
- The set as main display feature works
- UI layout matches the BetterDisplay screenshot

**After completion**: running project-optimize for reflection is recommended
