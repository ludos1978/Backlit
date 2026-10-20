# Services — Business Logic Layer

> System framework interaction layer, no UI. All Services are `@MainActor` singletons (`static let shared`).

## Responsibilities

Interact directly with macOS system frameworks (IOKit, CoreGraphics, ScreenCaptureKit, ColorSync)
and provide high-level APIs for Views/ViewModels.

## Key patterns

- **Singleton + @MainActor**: all Services are marked `@MainActor final class: ObservableObject, @unchecked Sendable`
- **DDC communication**: DDCService is the low-level dependency of all external display features; Apple Silicon uses IOAVService
- **Sole writer of the gamma table**: GammaService owns write access to CGSetDisplayTransfer*
  - BrightnessService's software brightness writes indirectly through GammaService
  - ❌ No Service/View should call CGSetDisplayTransferByFormula/Table directly
- **CGHelpers.runWithTimeout**: blocking CG calls (apply settings, enableMirror) must be wrapped with it

## File list

| File | Purpose |
|------|------|
| DDCService.swift | Low-level IOKit I2C / IOAVService DDC communication |
| DisplayManager.swift | Display enumeration, refresh, cross-Service coordination |
| BrightnessService.swift | Software brightness (writes through GammaService) |
| GammaService.swift | Sole writer of the gamma table |
| AutoBrightnessService.swift | Syncs external display brightness to the built-in display (CoreDisplay API) |
| ResolutionService.swift | Resolution/HiDPI mode switching |
| HiDPIService.swift | HiDPI detection and management |
| VirtualDisplayService.swift | CGVirtualDisplay creation/destruction |
| ColorProfileService.swift | ColorSync ICC Profile |
| NotchOverlayManager.swift | Notch mask overlay |
| SettingsService.swift | UserDefaults persistence |
| UpdateService.swift | App update detection |
| LaunchService.swift | Launch at login |
| CGHelpers.swift | Timeout wrapper for blocking CG calls |

## Cross-Service rules

- **Sleep/wake reapply order**: BrightnessService → GammaService (Brightness is the data provider for Gamma)
  - AppDelegate listens for `NSWorkspace.didWakeNotification` → calls reapply
- **C callbacks**: use `Unmanaged.passRetained(self)` + matching `release()`, ❌ do not use passUnretained
- **VirtualDisplayService**: virtual displays are only created by an explicit click — ❌ no auto-create at launch/menu open
  (`autoCreate` is legacy, decoded but ignored; see L-029),
  `CGVirtualDisplay(descriptor:)` init must be on the main thread

## Testing notes

- DDC/IOKit features must be tested manually on a real external display
- After creating via VirtualDisplayService, verify `CGVirtualDisplay` is non-nil (vendorID must be non-zero)
