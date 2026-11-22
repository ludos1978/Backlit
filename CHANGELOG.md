# Changelog

All notable changes to Backlit are documented here. Versions follow semantic versioning
(major.minor.patch): fixes bump the patch number, new features the minor number.
Backlit started as a fork of [FreeDisplay](https://github.com/huberdf/FreeDisplay); its first
release is 0.3.0.

---

## Unreleased

### Changed
- Settings panel uses the same rows as the other option panels (grouped: general, Keys, Who controls each setting); toggle labels are no longer cut off.

### Fixed
- Keep Awake remembers its mode across restarts. *Lid Closed* asks for the administrator password again at launch, because the setting is undone on quit.
- Keep Awake "Lid Closed": the menu no longer freezes while the administrator password prompt is open (the prompt runs in its own process; the picker shows "Waiting for the administrator password…").
- Adaptive brightness could leave a screen capture running in the background when its samplers were rebuilt while one was still starting (wake, display change, quick setting changes).

## v0.8.1 (2026-11-21)

### Changed

- **Adaptive brightness reacts in ~0.2–0.5 s instead of 1–8 s.** A screen-content change is
  applied immediately instead of on the next 1 s tick; *Response* is now a transition time
  (0.12 / 0.4 / 1.5 s) instead of a per-second step limit; a big lightness jump commits at once.
- **Adaptive brightness is much lighter on 4K/5K screens.** The screen is sampled as a fixed
  64-pixel-wide frame at nominal resolution (cost no longer grows with the panel), and the
  analysis uses lookup tables (≈40× less CPU per frame). Sampling is 2 / 5 / 10 fps, default 5.
- **Unified option rows.** Adaptive Brightness, Image Adjustment and Keep Awake use the same
  row layout (icon · label · control), and the Adaptive Brightness panel is grouped into
  *Brightness*, *Behaviour*, *Displays* and *Ignored Apps*.

---

## v0.8.0 (2026-11-21)

### Added

- **Keep Awake** (Options): *System* (default — macOS sleeps with its own settings), *Screens*
  (screens and Mac stay awake while Backlit runs) and *Lid Closed* (the Mac stays awake even
  with the lid closed and no external display; uses `pmset disablesleep` and asks for an
  administrator password). The mode always starts as *System*; Backlit undoes its
  `disablesleep` on quit and after a crash, and never touches one that was already on.

---

## v0.7.1 (2026-11-17)

### Fixed

- **A switched-off display disappeared from the menu and couldn't be turned back on.** A disabled
  display is also reported as disconnected, and the unplug check forgot it immediately. It now
  stays listed as *Off* with a switch to turn it back on (quitting Backlit also turns it back on).

---

## v0.7.0 (2026-11-16)

### Added

- **Turn individual displays off.** Each screen in *Individual Screens* has a switch that
  disconnects it in software (like BlackOut): macOS moves its windows to the other screens.
  The last enabled display can't be turned off; switched-off displays come back when you flip
  the switch, quit Backlit, log out or restart — and at the next launch if Backlit crashed.

### Changed

- **Build script pushes.** `scripts/build-dmg.sh` now pushes its "Version X.Y.Z" commit
  (`--no-push` to skip).

---

## v0.6.2 (2026-10-20)

### Fixed

- **Starting Backlit no longer changes the resolution.** Saved virtual displays were re-created
  automatically on the first menu open after launch, and macOS re-fitted (or mirrored) the
  physical screens around the new display. Virtual displays are now only created when you click
  them; the *Auto* (create at launch) option is removed.

---

## v0.6.1 (2026-10-20)

### Changed

- **Display layout is no longer Backlit's job.** *Arrange Displays* and *Set as Main Display*
  are removed (with the "Arrangement" ownership switch); Backlit never moves displays.

---

## v0.6.0 (2026-10-20)

### Added

- **Monitor speaker volume.** External displays with DDC audio get a volume slider and mute
  button in their panel (hidden when the monitor doesn't support it). Optional *Intercept
  Volume Keys* routes the volume/mute keys to the monitor when it is the macOS sound output
  (HDMI/DisplayPort audio).

### Changed

- **Presets never change resolution or layout.** The *Restore display arrangement* option is
  gone; presets only carry brightness, dimming, gamma/image adjustment, XDR, contrast and
  adaptive brightness.
- **Only the Display Modes list changes a resolution.** Presets no longer store or restore
  resolutions (older presets keep the values but they are ignored), the resolution is no
  longer re-applied after wake, and *Auto-enable HiDPI on New Displays* is removed.
- **Launching Backlit changes nothing.** It no longer restores brightness, extra dimming,
  gamma/image adjustments, XDR, accessibility contrast or adaptive brightness from the last
  session; those only change when you use a control or apply a preset.

### Fixed

- **Gamma adjustments on projectors.** Adjustments are re-applied after mode changes and once
  more after a display connects (macOS reset them), are saved per physical display instead of
  per display ID, and displays that reject gamma (AirPlay, Sidecar, DisplayLink) show a warning.

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

