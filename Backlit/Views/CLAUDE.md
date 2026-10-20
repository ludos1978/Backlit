# Views — SwiftUI View Layer

> Pure presentation and interaction, ❌ no business logic in Views, don't call Services directly.

## Structure

- **MenuBarView.swift** — main menu bar view, the entry container for all features
- **DisplayDetailView.swift** — per-display expanded panel, container for collapsible Sections
- Each Section corresponds to a separate View file (BrightnessSliderView, ColorProfileView, etc.)

## File list

| File | Purpose |
|------|------|
| MenuBarView.swift | Main menu bar view + all Section entry points |
| DisplayDetailView.swift | Display expanded panel (12 Sections) |
| BrightnessSliderView.swift | Brightness/contrast sliders |
| DisplayModeListView.swift | Resolution mode list (favorites pinned on top) |
| ColorProfileView.swift | ICC Profile selection |
| SystemColorView.swift | System color configuration |
| ImageAdjustmentView.swift | Image adjustment (gamma/contrast) |
| VirtualDisplayView.swift | HiDPI virtual display |
| NotchView.swift | Notch mask |
| AutoBrightnessView.swift | Ambient light auto-brightness |

## Key patterns

- `@EnvironmentObject var displayManager: DisplayManager` — injected globally
- `@ObservedObject` for shared singletons (❌ don't wrap .shared in @StateObject)
- Row components needing hover/loading state → extract into a standalone `struct` (❌ don't use @ViewBuilder functions)
- Component naming: reusable rows are `XxxRow` or `XxxRowView`
- Unified hover effect: `.background(isHovered ? Color.primary.opacity(0.07) : .clear)`

## Change checklist

- Adding a Section → change DisplayDetailView.swift + check the MenuBarView layout
- Adding a tool entry → change the tools area in MenuBarView.swift
- Adding a row component → must be a standalone struct, not a @ViewBuilder function
