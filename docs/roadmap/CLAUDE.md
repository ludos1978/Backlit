# Roadmap — Backlit

> Created: 2026-03-02 | Goal: a free macOS menu bar display management app that fully replaces BetterDisplay

## Background and Motivation

BetterDisplay is the most full-featured display management tool on macOS, but it is expensive. This project aims to build a free, open-source alternative with equivalent features, covering all core functionality such as DDC control, HiDPI management, screen streaming/Picture-in-Picture, and virtual displays.

## Requirements Summary

### Feature Area 1: Basic Display Management
- Multi-display detection and list view (built-in + external)
- Brightness slider control (DDC protocol for external displays, system API for the built-in display)
- Resolution switching (including the HiDPI mode list, native + scaled modes)
- Set as main display
- Screen rotation (90°/180°/270°)
- Display arrangement (visual drag and drop)

### Feature Area 2: Full DDC/CI Control
- Read and set brightness, contrast, and volume
- Input source switching
- Read all VCP parameters from the device and update them

### Feature Area 3: Color and Image
- Color mode switching (8-bit/10-bit, SDR/HDR, framebuffer type)
- ICC color profile switching
- Image adjustment (contrast, gamma, gain, color temperature, independent RGB channel adjustment)
- Invert colors

### Feature Area 4: Screen Mirroring and Streaming
- Screen mirroring (select source → target)
- Screen streaming (including flip/rotate/scale/underscan/opacity/crop/video filters)
- Picture-in-Picture (floating window, with options such as level, lock, click-through, shadow)

### Feature Area 5: Advanced Features
- Virtual display / Dummy Display creation and management
- Config protection (prevent the system from resetting resolution/refresh rate/color settings)
- Auto brightness
- Display notch management
- Prevent sleep while connected

## Technical Approach Overview

- **Tech stack**: Swift 6.2 + SwiftUI (MenuBarExtra) + IOKit + CoreGraphics + ScreenCaptureKit + ColorSync
- **Architecture**: macOS menu bar app (MenuBarExtra), MVVM architecture, project managed with xcodegen
- **Minimum system**: macOS 14.0 (CGVirtualDisplay requires macOS 14+)
- **Key constraints**: requires Accessibility permission (DDC), Screen Recording permission (streaming), App Sandbox disabled

### Core Design Decisions

| Decision | Choice | Reason |
|------|------|------|
| UI framework | SwiftUI MenuBarExtra | Native support on macOS 13+, lightweight, no Dock icon |
| Project management | xcodegen + project.yml | CLI friendly, avoids managing .xcodeproj by hand |
| DDC communication | Direct IOKit I2C communication | No third-party library dependency, based on the open-source MonitorControl implementation |
| Screen capture | ScreenCaptureKit | Official Apple API, macOS 12.3+, replaces the deprecated CGDisplayStream |
| Virtual display | CGVirtualDisplay | Official API on macOS 14+, more stable than the old IOKit approach |
| Color management | ColorSync + CoreGraphics | Native system ICC management |
| Architecture | MVVM | SwiftUI best practice, View-ViewModel-Service layering |

## Phase Overview

| Phase | Name | Status | Details |
|-------|------|------|------|
| 0-17 | Archived | ✅ | [archive/](archive/) |
| 18 | Stability hardening | ✅ | [phase-18.md](phase-18.md) |
| 19 | Display preset system | ✅ | [phase-19.md](phase-19.md) |
| 20 | Release preparation | ✅ | [phase-20.md](phase-20.md) |
| 21 | Feature trimming | ✅ | [phase-21.md](phase-21.md) |
| 22 | Auto brightness rewrite | ✅ | [phase-22.md](phase-22.md) |

## Decision Log

| Date | Decision | Alternatives | Rationale |
|------|------|---------|------|
| 2026-03-02 | Use xcodegen instead of a hand-made Xcode project | SPM executable, manual xcodeproj | CLI friendly, git-manageable, auto-generates xcodeproj |
| 2026-03-02 | MenuBarExtra instead of NSStatusItem | NSStatusItem + NSPopover | Native SwiftUI, simpler code, supported on macOS 13+ |
| 2026-03-02 | Minimum macOS 14 | macOS 12/13 | CGVirtualDisplay requires 14+, the user is currently on macOS 15 |
| 2026-03-02 | No third-party dependencies | MonitorControl/Lunar libraries | Fully self-controlled, learn the low-level APIs |
| 2026-03-04 | Plan Phase 18-20 | Keep fixing bugs | Features are complete; focus on stability → preset system → release and distribution |

## Requirements Confirmation Log

| Date | Item | Content |
|------|--------|------|
| 2026-03-02 | Feature scope | User confirmed: all features are wanted, including streaming/PiP/virtual displays |
| 2026-03-02 | Project location | ~/Desktop/Backlit |
| 2026-03-02 | Dev environment | Xcode installed, xcodegen 2.44.1 installed |
| 2026-03-02 | User hardware | MacBook built-in display + HKC H2435Q 2K external display |
| 2026-03-04 | HiDPI debugging notes | Constraints such as CGVirtualDisplay needing a non-zero vendorID, main-thread creation, and HiDPI config being purely runtime have been recorded in lessons |
