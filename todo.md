# FreeDisplay — Feature TODO

> Backlog of researched-but-not-yet-implemented features (2026-09-07).
> Sources researched: MacOS-DPIManager (MIT), SimpleDisplay (GPL-3.0), BrightIntosh (GPL-3.0).
> GPL sources: techniques may be reimplemented, code must NOT be copied.

## From MacOS-DPIManager (MIT — code reuse allowed with attribution)

- [ ] **`target-default-ppmm` key in HiDPI override plist** — nudges macOS toward
      picking the intended default scaled mode (DPIManager writes 10.0699301 ≈ 256 PPI).
      One extra dictionary entry in `HiDPIService.enableHiDPIPlist`. Effort: tiny.
- [ ] **Flagged 16-byte `scale-resolutions` variants ("fix underscaled")** — emit a second
      entry per resolution with the one-key-hidpi-style flag words in addition to the
      current 8-byte (backingW, backingH) entries. Fixes displays that come up underscaled.
      Change in `HiDPIService.generateScaledModes`. Effort: small.
- [ ] **Font smoothing control** — `defaults -currentHost write -g AppleFontSmoothing -int <-1…3>`
      picker in Settings (needs logout/login to apply, no admin). Effort: small.

## From SimpleDisplay (GPL-3.0 — reimplement, do not copy)

- [ ] **Disable/enable physical displays without unplugging** (BetterDisplay "disconnect"
      equivalent). Private CGS symbol `CGSConfigureDisplayEnabled` (dlsym) inside a
      `CGBeginDisplayConfiguration`/`CGCompleteDisplayConfiguration` transaction.
      Requires: UUID-based tracking of disabled displays (IDs are reassigned on topology
      changes), persistence, last-display safety countdown. Effort: medium. ⚠️ Private API —
      ask user before implementing (per project rules).
- [ ] **Stable serial/identity + ColorSync sRGB pinning for virtual displays** — persist a
      bounded serial-slot per `VirtualDisplayConfig` so identity is stable across relaunches;
      pin profile via `ColorSyncDeviceSetCustomProfiles` (avoid `ColorSyncUnregisterDevice`,
      it hangs). Fixes .icc churn / mode-swap-after-relaunch. Effort: small.
- [ ] **URL scheme + CLI automation** — `freedisplay://` URL commands plus a tiny
      `freedisplayctl` binary (create/remove virtual displays, presets, brightness, JSON
      status export). Scriptable from Shortcuts/SSH/launchd. Effort: medium.
- [ ] **Virtual display device presets** — iPhone/iPad/TV resolution preset table on top of
      the existing CGVirtualDisplay support. Effort: tiny.

## Security / trust audit

- [x] **Verify no code connects to the internet without specific need** (audited 2026-09-07;
      re-verify before each release). Full list of network/exec/dynamic-loading touchpoints:
      1. `UpdateService.swift` — the ONLY network code: GET
         `https://api.github.com/repos/<owner>/<repo>/releases/latest` for the update check.
         Currently **inert** (placeholder owner "OWNER" guard returns early); when configured,
         it runs only if "Check for Updates at Launch" is on, max once/hour, sends no payload.
         `openReleasePage()` opens the release URL in the browser on explicit user click.
      2. `HiDPIService.swift` — `NSAppleScript` "do shell script … with administrator
         privileges" to copy the HiDPI override plist into /Library/Displays (local only).
      3. `AutoBrightnessService.swift` — `dlopen`/`dlsym` of Apple's own
         /System/Library/Frameworks/CoreDisplay.framework (built-in brightness read; private
         API but Apple's framework, no third-party code).
      4. `BrightnessService.swift` — `dlopen`/`dlsym` of Apple's DisplayServices private
         framework (built-in brightness get/set; the IODisplay API is dead on Apple Silicon).
      5. `AccessibilityService.swift` — `dlopen`/`dlsym` of Apple's UniversalAccess
         (UAIncreaseContrastIs/SetEnabled) and SkyLight (CGSSetDisplayContrast) private
         frameworks; all local, no data leaves the machine.
      6. `DisplayStreamService.swift` — ScreenCaptureKit capture of a display for the
         virtual-display stream window (local rendering only; needs Screen Recording permission).
      No `Process`/`NSTask`/shell execution, no sockets, no third-party dependencies,
      no encoded/obfuscated blobs found (grep for base64/hex literals: none).
- [ ] Re-run this audit before each tagged release (network grep + Process grep + blob grep).
- [x] **Copyright / license provenance audit** (2026-09-08): no files from BrightIntosh (GPL-3.0),
      SimpleDisplay (GPL-3.0) or MacOS-DPIManager (MIT) are in the repo; XDR feature written from
      a prose description, never from source. Mechanical comparison against the BrightIntosh
      sources: 10 identical lines, all single Apple-API assignments (no other way to write them);
      token similarity 0.08–0.11 (unrelated-file range). The only derived specifics — the boost
      calibration constants — were replaced by a self-calibrating design (measured potential and
      full-backlight headroom, own gain constant). Levels curve came from the user's own notes.

## Arrangement follow-ups

- [ ] **Preserve arrangement across resolution/HiDPI switches** — when a display's point size
      changes (Native ↔ HiDPI presets, mode list), macOS reflows neighbours to avoid overlap and
      the layout drifts. Snapshot relative origins before a mode switch and restore them after
      (externals only, never the built-in). Effort: small-medium.

## XDR / gamma follow-ups (own backlog)

- [ ] XDR mode: conflict detection with other gamma-touching apps (f.lux, Lunar,
      MonitorControl, Vivid…) and per-display back-off, as BrightIntosh does.
- [ ] XDR mode: optional auto-disable on lid close / screen saver / session switch.
- [ ] XDR mode: gamma-integrity poll (re-read table every ~2 s, re-apply on drift).
- [ ] Levels curve: optional per-channel black/white/mid points (gray-cast correction).
- [ ] Smooth fade (~0.2 s) when the XDR boost factor changes to avoid visible steps.
