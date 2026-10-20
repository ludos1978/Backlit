# Phase 8: Screen Mirroring ✅

> Core value: mirror the content of one display to another display

## Task List

- [x] Implement hardware mirroring (`Backlit/Services/MirrorService.swift`)
  - Implementation hint:
    macOS natively supports hardware-level screen mirroring through CoreGraphics APIs:
    ```swift
    func enableMirror(source: CGDirectDisplayID, target: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&config)
        CGConfigureDisplayMirrorOfDisplay(config, target, source)
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    func disableMirror(displayID: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&config)
        CGConfigureDisplayMirrorOfDisplay(config, displayID, kCGNullDirectDisplay)
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }
    ```
    Check whether mirroring is active: `CGDisplayMirrorsDisplay(displayID)` returns the source display ID,
    and if it returns `kCGNullDirectDisplay` it is not mirrored.
    Note: hardware mirroring requires the two displays to have compatible resolutions.
  - Verify: after enabling mirroring both displays show the same content

- [x] Implement the screen mirroring UI (`Backlit/Views/MirrorView.swift`)
  - Implementation hint:
    An expandable "Screen Mirroring" section, modeled on the BetterDisplay screenshot:
    text below the title: "Mirror this display's content to:"
    The list shows available target displays (e.g. "H2435Q"), each row with a display icon on the left.
    A "Stop Mirroring" button at the bottom (toggling between grayed out / enabled).
    Mirroring starts immediately after choosing a target.
  - Verify: mirroring takes effect after choosing the target display, and returns to normal after clicking stop

## Phase Acceptance

- Built-in → external mirroring works
- External → built-in mirroring works
- Stopping mirroring restores normal state
- UI matches the BetterDisplay screenshot

**After completion**: running project-optimize for reflection is recommended
