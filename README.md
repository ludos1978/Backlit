# FreeDisplay

> **Free & open-source alternative to [BetterDisplay](https://github.com/waydabber/BetterDisplay)** — all the core display management features, zero cost.

BetterDisplay is a great app, but its best features are locked behind a paid Pro license. FreeDisplay implements the most essential BetterDisplay features as a completely free, open-source macOS menu bar app.

[Download Latest Release](https://github.com/ludos1978/FreeDisplay/releases/latest) | [Report an Issue](https://github.com/huberdf/FreeDisplay/issues)

---

## What BetterDisplay Features Does This Replace?

| BetterDisplay Feature | FreeDisplay | Notes |
|----------------------|:-----------:|-------|
| DDC Brightness & Contrast | ✅ | Hardware control via IOKit I2C (Intel) / IOAVService (Apple Silicon) |
| Software Brightness (Gamma) | ✅ | Per-display gamma table control with smooth transitions |
| Keyboard Brightness Keys for External Displays | ✅ | Intercepts brightness keys when cursor is on external display, shows native macOS OSD |
| Auto Brightness Sync | ✅ | Syncs external display brightness with built-in display changes |
| HiDPI Virtual Displays | ✅ | Creates HiDPI dummy displays via CGVirtualDisplay private API |
| Display Arrangement | ✅ | Position displays (external above built-in, etc.) |
| Resolution & HiDPI Switching | ✅ | Browse and switch all available display modes including HiDPI |
| ICC Color Profile Management | ✅ | Switch color profiles per display via ColorSync |
| Image Adjustment (Gamma/Temperature) | ✅ | Software contrast, color temperature, RGB channels, invert |
| Display Presets | ✅ | Save & restore full display configurations with one click |
| Virtual Display (Dummy) | ✅ | Create headless virtual displays |
| Notch Management | ✅ | Hide the MacBook notch with a black overlay |
| Launch at Login | ✅ | Via SMAppService |

### Not Included (intentionally)

- Screen streaming / PiP — rarely used, adds complexity
- EDID override — requires SIP disabled
- XDR/HDR extra brightness — requires specific hardware

---

## Screenshots

*Coming soon*

---

## Installation

### Option 1: Download DMG

1. Download `FreeDisplay.dmg` from [Releases](https://github.com/ludos1978/FreeDisplay/releases/latest)
2. Open the DMG and drag **FreeDisplay.app** to **Applications**
3. First launch: right-click → **Open** (unsigned app, one-time approval)

### Option 2: Build from Source

Requirements: Xcode and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/ludos1978/FreeDisplay.git
cd FreeDisplay
./build.sh --run          # clean Debug build, then launches the app
```

`build.sh` does a **clean build** every time and prints where the app ended up
(`build/Build/Products/Debug/FreeDisplay.app`; the full compiler log is in
`build/xcodebuild.log`). Options:

| Command | What it does |
|---------|--------------|
| `./build.sh` | clean Debug build |
| `./build.sh --release` | clean Release build (`build/Build/Products/Release/FreeDisplay.app`) |
| `./build.sh --run` | build, then quit any running copy and launch the new one |
| `SIGN=adhoc ./build.sh` | force ad-hoc signing even if a certificate is installed |

**Signing:** the script uses the project's Apple Development certificate when one is
installed (`security find-identity -v -p codesigning`), and otherwise signs the app
**ad-hoc**. Ad-hoc builds run normally, but because every rebuild produces a new
signature, macOS permission grants (Accessibility, Screen Recording) may need to be
re-approved after rebuilding.

Manual equivalent, if you prefer not to use the script:

```bash
xcodegen generate
xcodebuild -scheme FreeDisplay -configuration Release clean build \
    CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=    # omit these two when you have a certificate
```

---

## Permissions

| Permission | Why |
|------------|-----|
| **Accessibility** | Only if you enable *Intercept Brightness Keys* in Settings (F1/F2 → external display under the cursor) |
| **Screen Recording** | Only for *Show in Window* (streaming a display's content into a floating window) |
| **Administrator password** | Only when enabling HiDPI overrides (writes to `/Library/Displays`) |

No internet connection required (the optional update check is off by default).

---

## Security & Privacy

Audited 2026-09-08 (full source review). What the app does and does not do:

- **Network:** exactly one HTTPS request exists — the optional update check against the
  GitHub Releases API for `ludos1978/FreeDisplay` (Settings → *Check for Updates at Launch*,
  **off by default**, once per hour at most, nothing about your machine is sent, only an
  `https://github.com` page is ever opened).
  There is no telemetry, analytics, crash reporting, or any other network code.
- **What it stores:** settings in `UserDefaults` (all keys prefixed `fd.`) and presets in
  `~/Library/Application Support/FreeDisplay/presets.json` — display UUIDs, resolutions,
  brightness/gamma values, preset names. Nothing is shared or uploaded.
- **Privileged operation:** enabling HiDPI overrides copies a plist into
  `/Library/Displays/…/Overrides/` after the *system's own* administrator password dialog.
  The command contains only numeric display IDs; the app never sees your password. It only
  overwrites or deletes override files it created itself (marked `FreeDisplayManaged`).
  This file affects every user of the Mac for that display model.
- **Input monitoring (opt-in):** *Intercept Brightness Keys* installs an event tap whose
  mask covers only system media/function-key events (`NX_SYSDEFINED`) — it cannot see
  typed text — and acts solely on the two brightness keys.
- **Screen capture (on demand):** *Show in Window* streams a display with ScreenCaptureKit
  straight into a local window; frames are never saved or transmitted.
- **Runs automatically:** at launch/wake the app re-applies *your own* saved settings
  (gamma, extra dimming, XDR, accessibility contrast, chosen resolution) and probes external
  displays over DDC. After a crash or force-quit, persisted display adjustments are NOT
  re-applied (crash guard), so a bad setting can never lock you out.
- **Private Apple APIs:** used for built-in brightness (DisplayServices), auto-brightness
  (CoreDisplay), accessibility contrast (UniversalAccess/SkyLight), virtual displays
  (CGVirtualDisplay) and DDC on Apple Silicon (IOAVService). All local; none can reach
  beyond its stated purpose. The accessibility-contrast settings are system-wide and persist
  after quitting.
- **Sandbox & signing:** unsandboxed (required for IOKit/DDC), hardened runtime with no
  exceptions. Builds are ad-hoc or development signed, not notarized — Gatekeeper requires a
  one-time right-click → Open, and permission grants may need re-approval after rebuilds.

---

## Tech Stack

- **Swift 6** + **SwiftUI** (MenuBarExtra)
- **IOKit** — DDC/CI I2C for hardware brightness/contrast
- **CoreGraphics** — Display enumeration, resolution, arrangement
- **ColorSync** — ICC color profile management
- **CGVirtualDisplay** — Virtual display creation (private API, macOS 14+)
- **CoreDisplay** — Built-in display brightness reading (private API, via dlopen)
- Zero third-party dependencies

---

## Project Structure

```
FreeDisplay/
├── App/              # AppDelegate, app entry point
├── Models/           # DisplayInfo, DisplayMode, DisplayPreset
├── Services/         # System-level services (DDC, brightness, resolution, gamma, etc.)
└── Views/            # SwiftUI views for each feature section
```

---

## How It Works

FreeDisplay sits in your menu bar and talks directly to your displays:

- **External monitors**: Uses DDC/CI protocol over I2C (Intel) or IOAVService (Apple Silicon) to control hardware brightness, contrast, and other settings
- **Built-in display**: Uses CoreGraphics gamma tables for software brightness adjustment
- **Brightness keys**: Installs a CGEventTap to intercept keyboard brightness keys and route them to the display under your mouse cursor
- **Auto brightness**: Polls the built-in display brightness via CoreDisplay private API and proportionally adjusts external displays
- **HiDPI**: Creates virtual displays via CGVirtualDisplay private API, or writes display override plists for persistent HiDPI

---

## Contributing

Issues and PRs welcome. This project uses:
- `xcodegen` for project generation (edit `project.yml`, not `.xcodeproj`)
- Swift 6 with `SWIFT_STRICT_CONCURRENCY: minimal`
- MVVM architecture (View → ViewModel → Service)

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Acknowledgments

- Inspired by [BetterDisplay](https://github.com/waydabber/BetterDisplay), [MonitorControl](https://github.com/MonitorControl/MonitorControl), and [Lunar](https://lunar.fyi/)
- CGVirtualDisplay bridging header based on [Chromium's virtual_display_mac_util.mm](https://chromium.googlesource.com/chromium/src/+/main/ui/display/mac/test/virtual_display_mac_util.mm)
