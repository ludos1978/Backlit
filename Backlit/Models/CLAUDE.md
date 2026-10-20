# Models — Data Model Layer

> Pure data structures, ObservableObject.

## Files

| File | Purpose |
|------|------|
| DisplayInfo.swift | State model for a single display (high risk) |
| DisplayMode.swift | Display mode value type (resolution + refresh rate + HiDPI) |

---

## DisplayInfo.swift — High risk

Core display model with multiple `@Published` properties. **All Views and Services depend on this class.**

### Change protocol

1. Adding/removing `@Published` properties → `grep -r "DisplayInfo" Backlit/ --include="*.swift"` to find all references
2. Update all references in sync (compiling ≠ logically correct)
3. `loadDetails()` is an async method, called for new displays in `DisplayManager.refreshDisplays()`

### Key property notes

- `displayID: CGDirectDisplayID` — hardware identifier, may change after hot-plug (do not use as a persistent key)
- `isBuiltin` — determined with `CGDisplayIsBuiltin()`
- `bounds` — from `CGDisplayBounds()`, must be refreshed after hot-plug/arrangement changes
- `name` — from `NSScreen.localizedName` (more reliable than IOKit vendorID)
- The `rotation` property was removed in Phase 21 (deleted along with RotationService/RotationView)

---

## DisplayMode.swift

Value type for a single display mode (resolution + refresh rate + HiDPI flag).

- `currentMode(for:)` static method gets the current mode
- `availableModes(for:)` gets the list of available modes (including HiDPI variants)
- Changes affect ResolutionService and DisplayModeListView

### HiDPI notes

- HiDPI modes are distinguished by the `kIOScalingModeKey` flag, not simply 2× resolution
- HiDPI modes of virtual displays are injected dynamically by VirtualDisplayService, not from DisplayMode
