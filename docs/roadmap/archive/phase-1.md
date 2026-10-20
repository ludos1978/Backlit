# Phase 1: Display Detection and Menu UI ✅

> Core value: list all connected displays, show basic info, establish the UI framework

## Task List

- [x] Implement the `DisplayInfo` model (`Backlit/Models/DisplayInfo.swift`)
  - Implementation hint: properties include `displayID: CGDirectDisplayID`, `name: String`,
    `isBuiltin: Bool`, `isMain: Bool`, `isOnline: Bool`, `vendorNumber: UInt32`,
    `modelNumber: UInt32`, `serialNumber: UInt32`, `bounds: CGRect`,
    `pixelWidth: Int`, `pixelHeight: Int`, `rotation: Double`.
    Obtain them with CG functions such as `CGDisplayIsBuiltin()` / `CGDisplayIsMain()`.
    The display name comes from `kDisplayProductName` in `IODisplayCreateInfoDictionary`.
  - Verify: correctly identifies the built-in display and the name of the H2435Q external display

- [x] Implement `DisplayManager` detection logic (`Backlit/Services/DisplayManager.swift`)
  - Implementation hint: `@Published var displays: [DisplayInfo]`.
    Use `CGGetOnlineDisplayList(16, &displayIDs, &count)` to get all online displays.
    Listen with `CGDisplayRegisterReconfigurationCallback` to refresh automatically on display hot-plug.
    Run one scan at startup.
  - Verify: the list updates automatically when a display is plugged in or unplugged

- [x] Implement the menu bar main view (`Backlit/Views/MenuBarView.swift`)
  - Implementation hint: vertical ScrollView, with the display list at the top (one row per display, containing name + a Toggle switch),
    modeled on the BetterDisplay screenshot layout: display name on the left, Toggle switch on the right.
    Append an Ⓜ marker after the built-in display name to indicate the main display.
    Use `@EnvironmentObject var displayManager: DisplayManager`.
    Put a "Tools" section and a "Quit Backlit" button at the bottom.
  - Verify: the menu shows two rows, H2435Q and the built-in display

- [x] Implement the display detail expansion area (`Backlit/Views/DisplayDetailView.swift`)
  - Implementation hint: clicking a display row expands the details, using `DisclosureGroup` or a custom expand animation.
    When expanded, show the feature list (brightness, resolution, etc.), with a section header for each feature.
    Phase 1 uses placeholder text first, to be implemented gradually in later Phases.
    Follow the section list style of the BetterDisplay screenshot (blue icon + text + right arrow).
  - Verify: clicking a display row expands it and shows the feature section list

- [x] Display on/off function (`Backlit/Services/DisplayManager.swift`)
  - Implementation hint: the Toggle controls display on/off. External displays use DDC VCP code 0xD6 (Power Mode)
    to send a standby command. Built-in displays use `IORegistryEntrySetCFProperty` to set brightness to 0.
    Note: full DDC communication is implemented in Phase 2; for now `CGDisplayCapture` / `CGDisplayRelease` can be used to simulate it.
  - Verify: the screen goes black when the Toggle turns off the external display

## Phase Acceptance

- After building and running, clicking the menu bar icon opens a panel
- The panel shows all connected displays (names are correct)
- Display rows can be expanded and show a placeholder list of feature sections
- A "Quit Backlit" button at the bottom works

**After completion**: running project-optimize for reflection is recommended
