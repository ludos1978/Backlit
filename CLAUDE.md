# Backlit — Claude Context Entry Point

> Version: 2026-03-05 | Status: Phase 22 complete

## What this project is

A free, open-source alternative to BetterDisplay. A macOS menu bar app for managing displays: DDC brightness/contrast control, resolution/HiDPI management, color management, virtual displays, monitor speaker volume.
Tech stack: Swift 6 + SwiftUI (MenuBarExtra) + IOKit + CoreGraphics, zero third-party dependencies.

## Quick navigation (load on demand)

| What to do | Which file to read |
|-----------|-----------|
| **Check blocking issues before starting work** | `docs/BLOCKING.md` |
| Understand code structure, find files | `docs/codemap/CLAUDE.md` (index) → `docs/codemap/file-tree.md` (file tree) → `docs/codemap/relationships.md` (relationship graph) |
| View project plan, current progress | `docs/roadmap/CLAUDE.md` (overview) → `docs/roadmap/phase-N.md` (details) |
| View working habits/preferences | `docs/habits.md` |
| View pitfalls/lessons learned | `docs/lessons/CLAUDE.md` (index) → `docs/lessons/{topic}.md` (details) |

## Current focus

- **Current phase**: Phase 22 complete. Feature trimming (removed rotation/streaming/PiP/mirroring/config protection, etc.) + auto-brightness rewrite + HiDPI plist override implementation.
- **Do not touch**: `docs/roadmap/` — do not change its structure (planner output), only update `[x]` progress markers
- **Recent changes**: Phase 21 feature trimming (15+ files deleted), Phase 22 auto-brightness rewrite (CoreDisplay dlsym), HiDPI switched from mirroring approach to plist override, arrangement center-alignment fix, HiDPI presets

## Scope rules (set by the maintainer — never break)

- **Resolution:** only the user's direct pick in the Display Modes list (and its ⌘Z undo) or the HiDPI switch may change a physical display's mode. No presets, wake/connect handling, probes or automation.
- **Layout:** where displays sit relative to each other is not Backlit's job — never move displays (no `CGConfigureDisplayOrigin`, no mirroring).
- **Exception:** virtual displays may be created and their own features (resolution, HiDPI) set.
- **Presets:** brightness-related state only (brightness, dimming, gamma/image adjustment, XDR, contrast, adaptive brightness).
- **Launch is passive:** starting Backlit changes no brightness-related output; only an explicit user action (control, toggle, preset) does.
- **Commit every finished change** (atomic commits); pushing is a separate, explicit step.

## Autonomous decision rules

> **Blockers first (the first thing when starting work):**
- Every start → read `docs/BLOCKING.md` first → resolve any P0/P1 first → only do ROADMAP once all are cleared
- Problem you can't solve → add it to `docs/BLOCKING.md`

> **Linkage rules:**
- Changed a `DisplayInfo` property → grep all references and update them in sync
- Changed `project.yml` → must run `xcodegen generate` to regenerate the xcodeproj
- Added a Service/View file → update `docs/codemap/file-tree.md`

> **Fix/development:**
- Compile failure → fix until it passes, don't skip
- Swift 6 concurrency errors → use `@MainActor` or `@unchecked Sendable` (the project already sets `SWIFT_STRICT_CONCURRENCY: minimal`)
- New files don't require changing project.yml (xcodegen automatically includes all source files under Backlit/)

> **SwiftUI component rules:**
- Row components that need local state (isHovered, isLoading) → must be a standalone `struct`, ❌ not a `@ViewBuilder` function (@ViewBuilder functions don't support @State)
- Reusable row components are consistently named `XxxRow` (e.g. DetailRow, ExpandableRow, ProtectionRowView)

> **UserDefaults key naming convention:**
- All UserDefaults keys must have the `fd.` prefix (e.g. `fd.launchAtLogin`, `fd.AutoBrightnessEnabled`)
- ❌ Bare keys (e.g. `"launchAtLogin"`) may collide with system or third-party keys

> **Coordination principle for Services writing shared resources:**
- Two Services must not independently write the same CoreGraphics resource (e.g. gamma table) → designate one Service as the owner responsible for the final write
- BrightnessService (software brightness) writes the transfer function through GammaService, not directly via CGSetDisplayTransferByTable
- ❌ View layer calling `CGSetDisplayTransferByFormula/Table` directly (bypassing GammaService) → ✅ operate indirectly through `GammaService.apply()` or `GammaService.resetSingleDisplay()`
- ❌ `CGDisplayRestoreColorSyncSettings()` (global) → ✅ `GammaService.resetSingleDisplay(displayID)` resets only a single display

> **Sleep/wake handling (required):**
- Services that write display hardware state (gamma, software brightness) must respond to `NSWorkspace.didWakeNotification` and re-apply
- Already registered: AppDelegate listens for wake → GammaService.reapplyIfNeeded + BrightnessService.reapplySoftwareBrightnessIfNeeded

> **C callback Unmanaged rules:**
- Long-lived C callbacks (CGDisplayRegisterReconfigurationCallback, etc.) → must use `Unmanaged.passRetained(self)`, and `release()` on unregister
- ❌ `passUnretained` (dangling pointer risk)

> **IOKit display matching:**
- Don't use CGDisplayVendorNumber/ModelNumber to match IOKit services (unreliable for some displays)
- Use `NSScreen.localizedName` for the display name
- For IOKit service lookup, enumerate IODisplayConnect with IOServiceGetMatchingServices (❌ CGDisplayIOServicePort is deprecated)
- DDC external brightness control is not always available → UI must degrade gracefully (prompt the user when detection fails)

> **Async principle:**
- Only make truly slow operations async (file system scans, network requests)
- Microsecond-level IOKit calls (name lookup, property reads) stay synchronous; not worth making async

> **CGVirtualDisplay private API (must follow):**
- `vendorID` must be non-zero (e.g. `0xEEEE`); when 0, `CGVirtualDisplay(descriptor:)` returns nil
- `CGVirtualDisplay(descriptor:)` must be called on the main thread (returns nil on a background thread); `apply(settings)` may run in the background
- Bridging header property names follow Chromium `virtual_display_mac_util.mm` (`maxPixelsWide`/`maxPixelsHigh`, not `maxPixelSize`)

> **HiDPI implementation (must follow):**
- ❌ `CGConfigureDisplayMirrorOfDisplay` for HiDPI — triggers hardware mirroring mode + mouse lag on Apple Silicon
- ✅ Plist override written to `/Library/Displays/Contents/Resources/Overrides/` — same approach as BetterDisplay
- Writing the plist requires admin privileges → use `NSAppleScript("do shell script ... with administrator privileges")`
- ❌ Setting `DisplayProductName` in the plist — overrides the system display name
- After enabling, the display must be reconnected to take effect (IOServiceRequestProbe is not always reliable)

> **Dynamic loading of private frameworks:**
- ❌ `@_silgen_name` referencing private framework symbols (undefined symbol at link time)
- ✅ `dlopen` + `dlsym` runtime loading (e.g. CoreDisplay_Display_GetUserBrightness)

> **Stop and ask the user:**
- Need to use a private API (CoreDisplay, etc.)
- Need SIP disabled or special system permissions
- Architecture direction change (MVVM→other)

> **Self-maintenance rules:**
- Add/remove/change files → update `docs/codemap/file-tree.md`
- Phase task complete → mark `[x]` in `docs/roadmap/phase-N.md` **and also mark `[x]` in `docs/ROADMAP.md`** (autopilot tracks progress via the latter)
- Hit a pitfall → write it to `docs/lessons/{topic}.md` (and update the `docs/lessons/CLAUDE.md` index)
- Discovered a preference/pattern → write it to `docs/habits.md`
- Got stuck → add to `docs/BLOCKING.md`
- Resolved a BLOCKING item → move it to the resolved section

## Verification chain (run after every change)

```bash
# 1. Build check
./build.sh   # clean Debug build (ad-hoc signing fallback)

# 2. Linkage check (when interfaces/models changed)
grep -r "DisplayInfo\|DisplayManager\|DDCService" Backlit/ --include="*.swift" | grep -v "^Binary"
```

## Common operation playbooks

### Add a feature Section (most common operation in Phases 2-12)
1. Create a new Service in `Services/` (e.g. `BrightnessService.swift`)
2. Create the matching View in `Views/` (e.g. `BrightnessSliderView.swift`)
3. If state management is needed, create a ViewModel in `ViewModels/`
4. Embed the new View in `MenuBarView.swift`
5. Update `DisplayInfo.swift` to add the needed properties
6. Run the verification chain

### Implement a DDC feature
1. Implement IOKit I2C communication in `DDCService.swift`
2. Look up the VCP code for the new feature in the DDC/CI standard (e.g. 0x10=brightness)
3. Call `DDCService.shared.read/write` from the Service
4. Run the verification chain + test manually on a real external display

### Fix a bug
1. Determine whether it is a compile error or a runtime error
2. Compile error → locate it from the xcodebuild output
3. Runtime error → check logs in Console.app or the Xcode debugger
4. Fix → run the verification chain

## Design resources

- **App icon design**: Use [Nano Banana](https://nano-banana.ai/) (an AI image generator powered by Google Gemini) to generate high-quality icons
  - Supports generating icons, logos, UI elements from text descriptions
  - After generating, use Python PIL to crop/scale into the multi-size PNGs macOS needs (16/32/64/128/256/512/1024)
  - Icon files are located in `Backlit/Assets.xcassets/AppIcon.appiconset/`

## Key conventions

- **Language**: Swift 6.0 (concurrency checking minimal)
- **Minimum OS**: macOS 14.0
- **Architecture**: MVVM (View → ViewModel → Service)
- **Build**: `xcodegen generate && xcodebuild -scheme Backlit -configuration Debug build`
- **No Sandbox**: entitlements have App Sandbox turned off (required for DDC/IOKit)
- **No third-party dependencies**: system frameworks only

## Core frameworks

| Framework | Purpose | Phase |
|------|------|-------|
| CoreGraphics | Display enumeration, resolution, arrangement | 1-4 |
| IOKit | DDC/CI I2C communication, brightness/contrast | 2 |
| ColorSync | ICC Profile management | 5 |
| CoreGraphics (CGVirtualDisplay) | Virtual displays | 10 |
| CoreDisplay (dlsym) | Built-in display brightness reading | 22 |
