# Changelog

All notable changes to Backlit are documented here. Versions follow semantic versioning
(major.minor.patch): fixes bump the patch number, new features the minor number.
The ludos1978 fork restarted numbering at 0.3.0; the v1.0.0 entry at the bottom describes the
upstream FreeDisplay code the fork started from.

---

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

---

## v1.0.0 (2026-03-05)

Initial public release — full-featured BetterDisplay alternative.

### Core Features

- **Display Detection & Menu Bar UI** (Phase 1)
  - Multi-monitor detection (built-in + external)
  - MenuBarExtra-based UI with per-display panels
  - Display identification (visual flash)

- **DDC Brightness & Contrast Control** (Phase 2)
  - IOKit I2C DDC/CI communication
  - Hardware brightness and contrast sliders for external monitors
  - Software gamma brightness for built-in displays

- **Resolution Management & HiDPI** (Phase 3)
  - Resolution list with HiDPI/native/scaled modes
  - HiDPI virtual display creation (CGVirtualDisplay)
  - Resolution slider for quick switching

- **Rotation & Arrangement** (Phase 4)
  - Display rotation: 0°/90°/180°/270°
  - Visual display arrangement editor

- **Color Management** (Phase 5)
  - ICC color profile switching per display
  - Color mode display (8-bit/10-bit, SDR/HDR)

- **Image Adjustment** (Phase 6)
  - Software contrast, gamma, color temperature
  - Per-channel RGB gain control
  - Color inversion

- **Advanced Display Management** (Phase 7)
  - Set primary display
  - Display info panel (resolution, refresh rate, vendor)

- **Screen Mirroring** (Phase 8)
  - Mirror any display to any other display
  - Mirror enable/disable toggle

- **Screen Streaming & Picture-in-Picture** (Phase 9)
  - ScreenCaptureKit-based screen capture
  - Floating PiP window with configurable size and position
  - Stream controls: flip, rotate, scale, crop, opacity, video filters

- **Virtual Display** (Phase 10)
  - Create HiDPI virtual/dummy displays
  - Useful for headless Macs or extending workspace

- **Config Protection & Auto Brightness** (Phase 11)
  - Prevent macOS from resetting display configuration
  - Time-based auto brightness scheduling

- **Notch Management** (Phase 12)
  - Notch overlay show/hide for MacBooks with notch

### Stability & Polish

- **Critical Bug Fixes** (Phase 13)
  - DDC communication reliability improvements
  - CoreGraphics API usage corrections

- **Performance Optimization** (Phase 14)
  - Async display enumeration
  - Reduced UI blocking on IOKit calls

- **UX Improvements** (Phase 15)
  - Improved slider responsiveness
  - Better error states and user feedback

- **Comprehensive Bug Fixes — 134 bugs** (Phase 16)
  - 5 rounds of systematic bug fixing across all features
  - 3 rounds of UI/UX polish
  - Unified hover effects across all views
  - Extracted reusable components: DetailRow, ExpandableRow, ProtectionRowView
  - DisplayDetailView three-group layout
  - Rotation 2×2 grid layout
  - ArrangementView interior/exterior display thumbnail distinction
  - DisplayModeList favorites pinned to top
  - ConfigProtection active protection badge

- **DDC / HiDPI / Notch Targeted Fixes** (Phase 17)
  - CGVirtualDisplay: vendorID must be non-zero
  - CGVirtualDisplay must be created on main thread
  - Bridging header property name corrections
  - One-click display presets completed

- **CG Timeout Protection + Wake Recovery** (Phase 18)
  - CoreGraphics call timeout protection
  - Sleep/wake display state recovery
  - GammaService wake notification handler
  - BrightnessService wake reapplication

### Preset System

- **Display Preset One-Click Switching** (Phase 19)
  - Save full display configuration as named preset
  - Instant restore: resolution, brightness, rotation, color profile
  - Preset management UI (create, rename, delete)

### Release

- **App Icon, DMG Packaging, Launch at Login** (Phase 20)
  - App icon: gradient blue-purple monitor with "F" lettermark
  - DMG installer with Applications shortcut
  - SMAppService-based launch at login (macOS 13+)
  - README, CHANGELOG, release automation script
  - UpdateService pointing to GitHub Releases API
