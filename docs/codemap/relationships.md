# Module Relationships — Backlit

> Module relationship diagram, Services internal dependencies, data flow. Quick reference: [CLAUDE.md](CLAUDE.md), file tree: [file-tree.md](file-tree.md).

---

## Module Relationship Diagram / Module Relationship Diagram

```
App (BacklitApp)
  └── @StateObject DisplayManager
        └── @Published [DisplayInfo]
              └── MenuBarView (@EnvironmentObject DisplayManager)
                    ├── DisplayRowView
                    │     └── DisplayDetailView  ← 12 Sections (three groups)
                    │           ├── BrightnessSliderView     → BrightnessService → DDCService
                    │           ├── DisplayModeListView      → ResolutionService
                    │           ├── ColorProfileView         → ColorProfileService
                    │           ├── ImageAdjustmentView      → GammaService
                    │           ├── NotchView                → NotchOverlayManager
                    │           └── HiDPIVirtualRowView      → VirtualDisplayService
                    ├── VirtualDisplayView       → VirtualDisplayService
                    ├── AutoBrightnessView       → AutoBrightnessService → BrightnessService
                    ├── SystemColorMenuEntry     → SystemColorView → SettingsService
                    └── SettingsView             → SettingsService, LaunchService
```

---

## Services Internal Dependencies / Services Internal Dependencies

```
BrightnessService ──────────→ DDCService (external display DDC brightness read/write)
AutoBrightnessService ──────→ BrightnessService (called after mapping lux→brightness)
DisplayManager ─────────────→ BrightnessService (async brightness init on refresh)
               ─────────────→ arrangeExternalAboveBuiltin() (auto-position external display after hot-plug)

CGHelpers (shared utility) ────────→ used by the following Services (WindowServer IPC timeout protection):
  ResolutionService (applyModeSync CG transaction)
  VirtualDisplayService (CGVirtualDisplay apply transaction)

GammaService (gamma owner) ─→ the only Service that writes CGSetDisplayTransferByFormula/Table
  BrightnessService ─────────→ GammaService (software brightness is written via GammaService, not directly to CG)
  ❌ The View layer must not call CGSetDisplayTransferByFormula/Table
  ❌ Do not use CGDisplayRestoreColorSyncSettings() (global); use GammaService.resetSingleDisplay(displayID)

ResolutionService ──────────→ VirtualDisplayService.virtualDisplayID(for:) (mirror detection fallback)
```

---

## Data Flow / Data Flow

```
Unidirectional data flow (reactive):
  CGDisplayAPI / IOKit → Services → DisplayInfo (@Published) → Views (reactive SwiftUI)
  User interaction    → Views   → Services → Hardware

Sleep/wake data flow:
  NSWorkspace.didWakeNotification → AppDelegate
    → GammaService.reapplyIfNeeded()
    → BrightnessService.reapplySoftwareBrightnessIfNeeded()

Hot-plug data flow:
  CGDisplayRegisterReconfigurationCallback → DisplayManager.displayReconfigCallback
    → refreshDisplays()
    → arrangeExternalAboveBuiltin()
    → @Published displays updated → all Views re-render

Virtual display data flow (runtime, not persisted):
  VirtualDisplayView → VirtualDisplayService.enableHiDPIVirtual()
    → CGVirtualDisplay(descriptor:) [main thread, vendorID=0xEEEE]
    → HiDPI mode available (disappears after restart)
```
