# Code Map — Backlit (Quick Reference)

> **Purpose**: quick reference for Claude's code navigation. See `file-tree.md` for the detailed file tree and `relationships.md` for the module relationship diagram.
> **Maintenance**: update descriptions and the module relationship diagram after major structural changes.

---

## Entry Files / Key Entry Points

- `CLAUDE.md`
- `docs/codemap/CLAUDE.md` (this file)
- `docs/roadmap/CLAUDE.md`

Details: [file-tree.md](file-tree.md) | [relationships.md](relationships.md)

---

## Module Summary / Module Summary

| Module | Responsibility | Key Files | Notes |
|------|------|---------|---------|
| **App** | App lifecycle, MenuBarExtra scene declaration | `BacklitApp.swift` | DisplayManager is created here and injected as an environmentObject |
| **Models** | Pure data structures, ObservableObject | `DisplayInfo.swift`, `DisplayMode.swift` | After changing DisplayInfo properties, grep globally and update all references |
| **Services** | System framework interaction, no UI | `DDCService.swift`, `DisplayManager.swift`, `BrightnessService.swift` etc. | Most Services are @MainActor singletons |
| **Views** | SwiftUI views, presentation and interaction only | `MenuBarView.swift`, `DisplayDetailView.swift` | Do not put business logic in Views; call a Service |
| **Utilities** | System type extensions | `NSScreenExtension.swift` | Depended on in many places; avoid changing |

---

## High-Risk Files / High-Risk Files ⚠️

| File | Risk | Required When Changing |
|------|---------|---------|
| `Models/DisplayInfo.swift` | 12+ @Published properties; all Views and Services depend on it | grep all references and update them |
| `Services/DisplayManager.swift` | @Published displays injected globally, hot-plug callback | After changes, verify hot-plug and multi-display enumeration |
| `Services/DDCService.swift` | Low-level IOKit I2C communication, foundation of all external display features | Must be tested manually on a real external display |
| `Views/MenuBarView.swift` | Entry container for all features, nests all Section entries | After adding a Section, check layout and scroll height |
| `Views/DisplayDetailView.swift` | Expansion container for 12 Sections, many state variables | When adding a Section, avoid @State naming conflicts |

---

## Common Tasks → Files to Modify / Task Reference Table

| Task | Files to Modify |
|------|--------------|
| Add a display property (e.g. HDR state) | `Models/DisplayInfo.swift` → grep all references → related Views/Services |
| Add a DDC VCP feature (e.g. volume control) | `Services/DDCService.swift` (add VCP constant) → new Service → new View → `Views/DisplayDetailView.swift` (add Section) → `docs/codemap/CLAUDE.md` |
| Add a menu bar tool entry (not display-related) | `Views/MenuBarView.swift` (add entry in tools area) → new View/Service → `docs/codemap/CLAUDE.md` |
| Change resolution switching logic | `Services/ResolutionService.swift`, `Models/DisplayMode.swift`; test impact on `Views/DisplayModeListView.swift` |
| Change brightness read/write | `Services/BrightnessService.swift`; for external displays also check `Services/DDCService.swift` |
| Change image adjustment effects | `Services/GammaService.swift` (formula/Table computation), `Views/ImageAdjustmentView.swift` (UI slider mapping) |
| Add a new persisted setting | `Services/SettingsService.swift` (Keys + @Published property + loadAll/persist) → related View |
| Change notification/hot-plug handling | `Services/DisplayManager.swift` (displayReconfigCallback + refreshDisplays) |
| Change HiDPI Override generation | `Services/HiDPIService.swift` (generateScaledModes + plist path) |
| Change color picker/color history | `Views/SystemColorView.swift` (SystemColorViewModel), `Services/SettingsService.swift` (colorPickerHistory) |
| Change virtual display logic | `Services/VirtualDisplayService.swift`, `Backlit-Bridging-Header.h` (private API declarations) |

---

## Pitfalls / Pitfalls

- **DisplayInfo property coupling**: after changing `DisplayInfo` → grep all references and update them, otherwise it may compile but behave incorrectly
- **project.yml**: after changing it, run `xcodegen generate` to regenerate the xcodeproj
- **New source files**: xcodegen automatically includes all `.swift` files under `Backlit/`; no need to edit `project.yml`
- **Swift 6 concurrency**: the project sets `SWIFT_STRICT_CONCURRENCY: minimal`; handle concurrency errors with `@MainActor` or `@unchecked Sendable`
- **No Sandbox**: entitlements have App Sandbox disabled; direct access to IOKit, /Library/Displays, etc. works
- **Bridging Header private APIs**: the CGVirtualDisplay / IOAVService declarations in `Backlit-Bridging-Header.h` were verified against Chromium source; re-check property names before changing
- **HiDPIService permissions**: writing to `/Library/Displays/` requires administrator privileges; without them an error string is returned for the UI to display
- **CGHelpers.runWithTimeout**: WindowServer IPC may block the main thread; all CG configuration transactions must run through this utility on a background thread with timeout protection
