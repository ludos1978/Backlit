# Changelog

All notable changes to Backlit are documented here. Versions follow semantic versioning
(major.minor.patch): fixes bump the patch number, new features the minor number.
Backlit started as a fork of [FreeDisplay](https://github.com/huberdf/FreeDisplay); its first
release is 0.3.0.

---

## v0.5.2 (2026-09-12)

Bug-fix release. Ad-hoc signed, not notarized: after installing run
`xattr -d com.apple.quarantine /Applications/Backlit.app` (or use the Homebrew tap `ludos1978/backlit`).

### Fixed

- **"Show in Window" is no longer slow.** The stream captured the display at its full native
  resolution no matter how small the window was, and the frame rate is bound by exactly that:
  measured at 30 fps requested on a 1728x1117 display, a native-size capture delivered 21 fps
  where a 960-pixel-wide one delivered the full 30 at less than half the data rate. A 4K monitor
  has 4.8x more pixels again, so it could not reach 30 fps at all. The stream now captures at the
  window's pixel size, follows window resizes and moves between screens, and stops completely
  while the window is minimized or fully covered by other windows.

### Documentation

- `CHANGELOG.md` now carries the release notes for every version, linked from the README.

## v0.5.1 (2026-09-10)

Bug-fix release. Ad-hoc signed, not notarized: after installing run
`xattr -d com.apple.quarantine /Applications/Backlit.app` (or use the Homebrew tap `ludos1978/backlit`).

### Fixed

- **DDC targets the right monitor with identical displays.** On Apple Silicon two monitors of the
  same model were assigned to their DDC channels by list order, so brightness from sliders, presets
  and adaptive brightness could land on the wrong one. Channels are now matched through the
  IORegistry (EDID UUID → framebuffer serial number → CoreGraphics display); the old vendor/product
  and index fallbacks remain only as a last resort.
- **Presets apply their all-display values to every screen.** Brightness, extra dimming and image
  adjustment now also reach displays that were attached after the preset was saved; resolution,
  refresh rate and positions stay limited to the displays the preset stores. Presets also remember
  whether adaptive brightness was on and restore it. Areas set to "macOS controls" are left untouched.
- **Preset "Update" button and "Current" badge.** Changes on a display the preset does not cover now
  count as modifications (Update adds the display); "Current" means the preset's full stored state
  matches, so a preset is either Current or offers Update, never both.
- **Adaptive brightness no longer fights a manual change** in its first second after a slider or key
  adjustment.

## v0.5.0 (2026-09-09)

### Added

- **Adaptive Brightness** replaces "Auto Brightness". Brightness is driven by **screen content**
  (dark content → brighter, bright content → dimmer), the **ambient light sensor** (read on Apple
  Silicon through the HID event system, no permissions needed), **both**, or **follow built-in**
  (externals mirror the built-in panel, the previous behaviour). Each display learns a brightness
  surface over content lightness × ambient light from your manual adjustments (slider, keys,
  Control Center).
- Options: mode, live lux/lightness/target readout, sensitivity, minimum, maximum, response speed,
  capture rate (2/4/8 fps), lightness metric (average/RMS), learning on/off, per-display enable,
  ignore list with "Ignore ‹frontmost app›" and remembered per-app brightness, reset learned curves.
  Screen-content mode needs Screen Recording permission (the row tells you if it is missing); a hint
  appears if macOS's own "Automatically adjust brightness" is on.

### Changed

- The last brightness is remembered from what the OS reports (keys, Control Center, System
  Settings), so relaunching never overwrites a brightness you set outside the app.
- Settings/presets migration from the FreeDisplay identity continues to apply for users upgrading
  from 0.3.x.

## v0.4.0 (2026-09-09)

FreeDisplay is now **Backlit**. Same app, new name and bundle identifier
(`io.github.ludos1978.backlit`); settings and presets are migrated automatically on first launch.

### Added

- **Per-area ownership** in Settings ("Who controls each setting"): each area is either
  Backlit-controlled (applies its saved values at launch, editable) or macOS-controlled (read-only,
  click opens System Settings, nothing applied automatically).
- **Show in Window**: live stream of any display (physical or virtual) into a floating window.
- **build.sh** with automatic signing fallback (Apple Development certificate if present, ad-hoc
  otherwise); Homebrew tap `ludos1978/backlit`.

### Changed

- Menu order: presets → all-display controls → foldable "Individual Screens" → foldable "Options"
  (Arrange Displays, Virtual Displays, Auto Brightness, XDR, Settings). Native/HiDPI resolution
  presets removed.
- Per-screen brightness and "Dim Below Minimum" live inside Image Adjustment as regular rows;
  unified typography.
- Presets: "Update" button when the selected preset's values drift; display positions are restored
  only on opt-in and never for the built-in display.
- Auto-brightness starts at launch when enabled (no longer only when its row is unfolded).

### Security

- Security review, all findings fixed: gamma safety floor + crash guard, marker-guarded HiDPI
  overrides, debug-only logging, validated update URL, hardened privileged command, DDC mapping
  warning. Provenance audit of third-party techniques (no GPL code copied).

## v0.3.0 (2026-09-08)

First release of the ludos1978 fork (ad-hoc signed, not notarized).

### Added

- All-display sliders: brightness, gamma, "Dim Below Minimum" (software dimming below the backlight
  floor), accessibility Increase Contrast / Display Contrast.
- **XDR Brightness** mode for Liquid Retina XDR panels (self-calibrating EDR boost).
- Levels-style gamma curve (black point / midtone / white point) in Image Adjustment.
- Presets capture everything (gamma, dimming, XDR, contrast, built-in display) with an Update button
  when the selected preset drifts.
- Every value control has a reset; ⌘Z undoes changes.
- Opt-in update check (off by default) pointing at this repository.

### Fixed

- Menu actually opens (MenuBarExtra ScrollView collapse fixed).
- Built-in brightness works on Apple Silicon (DisplayServices); sliders follow brightness keys live.
- Entire UI in English.

### Removed

- Auto-arrange of displays. Brightness-key interception and auto-HiDPI are now opt-in settings
  (off by default).

