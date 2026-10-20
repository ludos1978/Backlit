# Blocking Issues — Backlit

> Updated: 2026-03-02 | **Must read before starting work; if there are unresolved P0/P1 issues, handle them first**

## Dispatch Rules

1. After reading this file → if there are P0/P1 issues → **resolve them one by one from highest priority to lowest, and only do the ROADMAP once all are cleared**
2. If there are only P2 issues → you may do ROADMAP tasks first, interleaving P2 fixes
3. After resolving → move to the "Resolved" section below, and write down the solution
4. If you get stuck on a new problem during work → add it here immediately

---

## 🔴 P0 — Hard Blockers

(None)

---

## 🟡 P1 — High Priority

(None)

---

## 🔵 P2 — Normal Priority

### B-005: Gamma has no effect on some projectors (cause unconfirmed)
- **Symptom**: gamma slider (even at -100) does nothing on a projector (saved state for display ID 9, Oct 2026)
- **Known history**: WindowServer's display config shows many 1920×1080-class externals mirrored with the built-in screen — mirroring is the prime suspect; AirPlay/DisplayLink outputs are the other. No system logs survived to confirm.
- **Already fixed (9cee755)**: re-apply after mode change / delayed after connect, UUID-keyed state, warning when CGSetDisplayTransfer* fails
- **Next step**: with the projector attached run `swift scripts/gamma-check.swift` and note mirror state, write result and whether the projector dims. If "write OK" + mirrored but no dimming → apply the gamma to the mirror source / all members of the mirror set.

---

## ✅ Resolved

### ~~B-004: HiDPI virtual display triggers system mirroring UI + mouse movement lag~~
- **Solution**: `CGConfigureDisplayMirrorOfDisplay` triggers hardware mirroring mode on Apple Silicon, which is a dead end. Switched to the same plist override approach as BetterDisplay: write `scale-resolutions` to `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-XXXX/DisplayProductID-XXXX`, requires admin privileges (NSAppleScript), takes effect after reconnecting the display. All mirroring-related code has been removed (enableHiDPIVirtual/disableHiDPIVirtual/hiDPIMirrorMap, etc.).
- **Resolved on**: 2026-03-05
- **Lesson**: macOS HiDPI has only two routes: (1) plist override (BetterDisplay approach, needs admin + reconnect) (2) CGVirtualDisplay pure virtual display (not mirrored with a physical screen). ❌ Never use CGConfigureDisplayMirrorOfDisplay.

### ~~B-002: CGVirtualDisplay is a private API with no public header~~
- **Solution**: The user approved using the private API. Created Backlit-Bridging-Header.h declaring the CGVirtualDisplay + IOAVService interfaces, and VirtualDisplayService now implements full virtual display creation/destruction.
- **Resolved on**: 2026-03-03

### ~~B-003: DDC brightness control does not work on some external displays~~
- **Solution**: Root cause confirmed: the IOFramebuffer I2C API used by DDCService does not work at all on Apple Silicon. Added an IOAVService ARM64 DDC path (finding external displays via DCPAVServiceProxy), and added a CGSetDisplayTransferByTable gamma table software brightness fallback.
- **Resolved on**: 2026-03-03

### ~~B-001: DisplayInfo.name shows only "Display N" instead of the real display name~~
- **Solution**: Enumerate all IODisplayConnect services with `IOServiceMatching("IODisplayConnect")` + `IODisplayCreateInfoDictionary`, match by DisplayVendorID + DisplayProductID, and take the product name of the first locale from the DisplayProductName dictionary; for the built-in display, directly return "Built-in Display"
- **Resolved on**: 2026-03-02
- **Lesson**: Integer values in IOKit CF dictionaries may be of type Int rather than UInt32, so try both types

### ~~B-000: Missing GENERATE_INFOPLIST_FILE causes compile failure~~
- **Solution**: Add `GENERATE_INFOPLIST_FILE: YES` to the project.yml settings
- **Resolved on**: 2026-03-02
- **Lesson**: xcodegen doesn't generate Info.plist automatically, it must be enabled explicitly

### ~~B-000b: DDCService static singleton Swift 6 concurrency error~~
- **Solution**: Mark the class `@unchecked Sendable`, and set `SWIFT_STRICT_CONCURRENCY: minimal` in project.yml
- **Resolved on**: 2026-03-02
- **Lesson**: Under Swift 6 strict concurrency checking, singletons need to be explicitly marked Sendable
