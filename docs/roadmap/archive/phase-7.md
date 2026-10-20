# Phase 7: Advanced Display Management ✅

> Core value: main display switching, notch management, integrated control, manage display settings

## Task List

- [x] Implement the "Set as Main Display" UI and logic (`Backlit/Views/MainDisplayView.swift`)
  - Implementation hint:
    Add a "Set as Main Display" option to the menu (Ⓜ icon), modeled on the blue circular M icon in the screenshot.
    The logic was already implemented in Phase 4's ArrangementService (move to the coordinate origin).
    This is the UI layer: show an Ⓜ marker next to the current main display in the display list.
    Click the "Set as Main Display" button of another display to switch.
  - Verify: after clicking, the Dock and menu bar move to the target display

- [x] Implement "Show Notch" management (`Backlit/Views/NotchView.swift`)
  - Implementation hint:
    MacBooks have a notch, which affects resolution and layout.
    Feature: label modes with a "notch" tag in the resolution list (modeled on "notch 60Hz 10bit" in the screenshot).
    Detect the notch: `NSScreen.safeAreaInsets.top > 0` or check the device model.
    Provide a "Hide Notch" option: implemented by covering the notch area with a black bar
    (create a borderless, always-on-top black NSWindow covering the notch area).
  - Verify: the "notch" tag is correctly shown next to the built-in screen resolution

- [x] Implement "Integrated Control" (DDC extension) (`Backlit/Views/IntegratedControlView.swift`)
  - Implementation hint:
    An expandable "Integrated Control" section, modeled on the screenshot layout:
    - "Read from device and update" button: read all DDC VCP codes and refresh the UI
    - "Configure integrated controls..." button: opens a configuration window
    DDCService extension: batch read common VCP codes:
    0x10 (brightness), 0x12 (contrast), 0x14 (color temperature select), 0x16 (video gain R),
    0x18 (video gain G), 0x1A (video gain B), 0x60 (input source), 0x62 (volume),
    0x87 (color saturation), 0xD6 (power mode), 0xDC (display mode)
    Store the results in the `ddcValues: [UInt8: UInt16]` dictionary of DisplayInfo.
  - Verify: after clicking "Read from device", the external display's DDC parameters are displayed correctly

- [x] Implement "Manage Display" settings (`Backlit/Views/ManageDisplayView.swift`)
  - Implementation hint:
    An expandable "Manage Display" section, modeled on the screenshot:
    - "Configure display...": opens the Displays panel of System Preferences
      `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings")!)`
    - "Visual identification": pops up a full-screen identification window on the target display (showing display name + ID),
      which closes automatically after 3 seconds. Use NSWindow + NSScreen to position it on the target display.
    - Hint text: "Use ⌥ Option + click on the display menu title to identify quickly."
    - "Prevent sleep while connected": use `IOPMAssertionCreateWithName` to create a power assertion
      that prevents system sleep (`kIOPMAssertionTypePreventSystemSleep`).
  - Verify: after clicking "Visual identification", an identification window pops up on the target display

## Phase Acceptance

- Main display switching works
- The notch tag is shown correctly
- Integrated control can read DDC parameters
- All sub-features of Manage Display work

**After completion**: running project-optimize for reflection is recommended
