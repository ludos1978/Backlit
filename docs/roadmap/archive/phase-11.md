# Phase 11: Configuration Protection and Auto Brightness ✅

> Core value: prevent the system from resetting display settings + ambient-light auto brightness

## Task List

- [x] Implement configuration snapshots (`Backlit/Services/ConfigProtectionService.swift`)
  - Implementation hints:
    Save a snapshot of the current full display configuration:
    ```swift
    struct DisplayConfig: Codable {
        let displayID: UInt32
        let displayName: String
        let resolution: (width: Int, height: Int)
        let refreshRate: Double
        let rotation: Int
        let colorProfile: String
        let brightness: Double
        let contrast: Double
        let hdrEnabled: Bool
        let isMain: Bool
        let isMirrored: Bool
        let mirrorSource: UInt32?
        let origin: CGPoint
    }
    ```
    Snapshots are stored in `~/Library/Application Support/Backlit/configs/`, JSON format.
    Supports multiple named snapshots ("Day Config", "Night Config", etc.).
  - Verify: after saving a snapshot, the JSON file is generated correctly

- [x] Implement configuration protection monitoring (`ConfigProtectionService` extension)
  - Implementation hints:
    Following the "Configuration Protection" section of the BetterDisplay screenshot, selectable protected items:
    - Resolution, refresh rate, color mode, HDR color mode, rotation,
      color profile, HDR color profile, HDR state, mirroring, main display state
    Use `CGDisplayRegisterReconfigurationCallback` to listen for display configuration changes.
    When a protected item is detected as changed, automatically restore it to the snapshot value.
    Shortcut buttons to enable/disable all protections.
  - Verify: with resolution protected, changing the resolution from System Settings gets automatically restored

- [x] Implement the configuration protection UI (`Backlit/Views/ConfigProtectionView.swift`)
  - Implementation hints:
    Expandable "Configuration Protection" section, following the screenshot:
    Protected item list, one Toggle per row:
    Resolution(📺) / Refresh Rate(📡) / Color Mode(🎨) / HDR Color Mode / Rotation(🔄) /
    Color Profile(🎯) / HDR Color Profile / HDR State / Mirroring(📋) / Main Display State(Ⓜ)
    Bottom:
    - Two buttons: "Enable All Protections" / "Disable All Protections"
    - Description text: "Settings made by this app are protected."
  - Verify: the UI matches the BetterDisplay screenshot

- [x] Implement auto brightness (`Backlit/Services/AutoBrightnessService.swift`)
  - Implementation hints:
    Built-in macOS displays have an ambient light sensor.
    Read ambient light: `IOServiceGetMatchingService` + `AppleLMUController` to read the lux value.
    Or use `CBTrueToneClient` (private framework) to get ambient light data.
    Simplified approach: use the `IOReport` framework or read the IOKit ambient light sensor value.
    Brightness mapping curve: logarithmic lux -> brightness mapping, with a user-adjustable curve offset.
    Auto brightness for external displays: adjust in sync with the built-in sensor value (via DDC).
    Settings: "Auto Brightness" Toggle + sensitivity slider.
  - Verify: covering the ambient light sensor automatically lowers screen brightness

- [x] Implement the auto brightness UI (`Backlit/Views/AutoBrightnessView.swift`)
  - Implementation hints:
    Add an "Auto Brightness" option (Ⓐ blue icon) at the bottom of the menu or in the display details, following the screenshot.
    Toggle switch + optional sensitivity slider.
  - Verify: the toggle works, and brightness follows ambient light

## Phase Acceptance

- All configuration protection items work
- Protected configuration is automatically restored after system changes
- Auto brightness follows ambient light changes
- All settings persist (take effect after restart)

**After completion**: running project-optimize for reflection is recommended
