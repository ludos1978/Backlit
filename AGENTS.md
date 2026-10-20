# AGENTS.md — Backlit Project Harness Configuration

> This file defines the harness rules for AI agents working on this project.
> AI agents MUST read this file before making any changes.
> For deeper context, read CLAUDE.md first — especially its "Scope rules".

## Project Overview

- **Name**: Backlit
- **Language**: Swift 6.0 (concurrency checking set to minimal)
- **Framework**: SwiftUI (MenuBarExtra) + AppKit
- **Package Manager**: None (zero third-party dependencies, system frameworks only)
- **Build Tool**: XcodeGen (`project.yml`) + xcodebuild
- **Minimum OS**: macOS 14.0
- **Architecture**: MVVM — View → ViewModel → Service

## Architecture Rules

### Layer Separation

```
Views/          → UI presentation; only read ViewModel or read Service directly (simple cases)
ViewModels/     → State management, bridges View and Service
Services/       → Business logic, interacts with system frameworks (IOKit/CoreGraphics/DDC)
Models/         → Pure data structures (DisplayInfo, DisplayMode, DisplayPreset)
```

- The View layer must not call CoreGraphics / IOKit / CGSet* APIs directly
- Writing the gamma table must go through GammaService, never bypass it
- BrightnessService (software brightness) writes through GammaService, not by calling CGSetDisplayTransferByTable directly

### Module Boundaries

| Directory | Responsibility |
|------|------|
| `Backlit/Services/` | All system-level operations (DDC, brightness, resolution, HiDPI, arrangement, etc.) |
| `Backlit/Views/` | SwiftUI views, file name format: `XxxView.swift` or `XxxRow.swift` |
| `Backlit/ViewModels/` | State management, 1:1 with a View or shared across several Views |
| `Backlit/Models/` | Data structures, no side effects |
| `Backlit/Utilities/` | General utility functions |
| `Backlit/Resources/` | Static resources |
| `docs/` | Project documentation (do not change structure) |
| `scripts/` | Build and release scripts |

### Protected Files

State the reason before modifying the following files:

- `Backlit/Backlit.entitlements` — permission declarations, changes affect signing and App Sandbox
- `project.yml` — XcodeGen config, must re-run `xcodegen generate` after changes
- `ExportOptions.plist` — release signing config
- `docs/roadmap/` — planning docs, only update `[x]` progress markers, don't change structure

## Coding Standards

### Style Guide

- Swift 6.0 syntax, no downgraded compatibility code
- Prefer SwiftUI views, use AppKit only when necessary
- Private frameworks (CoreDisplay, etc.) must be loaded at runtime with `dlopen` + `dlsym`; `@_silgen_name` is forbidden

### Naming Conventions

- Service classes: `XxxService.swift`, singletons use `static let shared`
- View files: `XxxView.swift`
- Reusable row components: `XxxRow` (struct, supports `@State`)
- UserDefaults keys: must have the `fd.` prefix (e.g. `fd.launchAtLogin`)
- Bare keys are forbidden (e.g. `"launchAtLogin"`)

### SwiftUI Component Rules

- Row components that need local state (`isHovered`, `isLoading`) → must be a standalone `struct`
- Do not use `@ViewBuilder` functions to host components that carry `@State`

### Concurrency Rules

- Swift 6 concurrency errors → prefer `@MainActor` or `@unchecked Sendable`
- Long-lived C callbacks (e.g. CGDisplayRegisterReconfigurationCallback) → use `Unmanaged.passRetained(self)`, and `release()` on unregister
- `passUnretained` is forbidden (dangling pointer risk)
- Only make truly slow operations async (file system scans, network requests); keep microsecond-level IOKit calls synchronous

## Testing Requirements

### Verification Commands

```bash
# Build check (Debug) — run after every change
./build.sh   # clean Debug build (ad-hoc signing fallback)

# Linkage check (when interfaces/models changed)
grep -r "DisplayInfo\|DisplayManager\|DDCService" Backlit/ --include="*.swift" | grep -v "^Binary"

# Regenerate xcodeproj (required when project.yml changed)
xcodegen generate

# Release: bump version, build, sign, write build/Builds/Backlit-X.Y.Z.{dmg,zip}, commit + push
./scripts/build-dmg.sh [patch|minor|major|X.Y.Z|--no-bump] [--install] [--no-commit] [--no-push]

# Publish the current version as a GitHub release (explicit step only)
./scripts/release.sh
```

### Test Coverage

- This project has no automated test suite (heavily hardware-dependent, mostly manual testing)
- New DDC features must be manually verified on a real external display
- New HiDPI features must be verified by reconnecting the display to confirm they take effect

## Git Discipline

### Branch Naming

- `feature/xxx` — new feature
- `fix/xxx` — bug fix
- `refactor/xxx` — refactor
- `phase-N/xxx` — changes for the corresponding ROADMAP Phase

### Commit Message Format

Follow Conventional Commits:

```
feat: add auto-brightness adjustment feature
fix: fix HiDPI plist write permission issue
refactor: extract GammaService to manage the transfer function in one place
```

### Co-Author Line

```
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

## Forbidden Operations

- Do NOT: call `CGSetDisplayTransferByTable` / `CGSetDisplayTransferByFormula` directly (bypasses GammaService)
- Do NOT: call `CGDisplayRestoreColorSyncSettings()` (global reset) — use `GammaService.resetSingleDisplay(displayID)`
- Do NOT: use `CGConfigureDisplayMirrorOfDisplay` to implement HiDPI (triggers hardware mirroring + mouse lag on Apple Silicon)
- Do NOT: use `@_silgen_name` to reference private framework symbols (undefined symbol at link time)
- Do NOT: use `CGDisplayVendorNumber/ModelNumber` to match IOKit services (unreliable for some displays)
- Do NOT: set `DisplayProductName` in the plist (overrides the system display name)
- Do NOT: change the structure of the `docs/roadmap/` directory
- Do NOT: add third-party dependencies (project policy: zero dependencies)
- Do NOT: access low-level system framework APIs directly in the View layer

## Agent-Specific Notes

### Start-of-work checklist

1. Read `docs/BLOCKING.md` first; resolve any P0/P1 first
2. Read `docs/roadmap/CLAUDE.md` to learn the current Phase
3. Read `docs/codemap/CLAUDE.md` → `docs/codemap/file-tree.md` to locate relevant files

### Post-change linkage checks

- Changed a `DisplayInfo` property → grep all references and update them in sync
- Changed `project.yml` → must run `xcodegen generate`
- Added a Service/View file → update `docs/codemap/file-tree.md`
- Phase task complete → mark `[x]` in both `docs/roadmap/phase-N.md` and `docs/ROADMAP.md`
- Hit a pitfall → write it to `docs/lessons/{topic}.md` and update the index
- Sleep/wake related changes → confirm the Service responds to `NSWorkspace.didWakeNotification`

### When to stop and ask the user

- Need to use a new private API (CoreDisplay, etc.)
- Need SIP disabled or special system permissions
- Architecture direction change (MVVM to another pattern)

### Core frameworks quick reference

| Framework | Purpose |
|------|------|
| CoreGraphics | Display enumeration, resolution, arrangement |
| IOKit | DDC/CI I2C communication, brightness/contrast |
| ColorSync | ICC Profile management |
| CGVirtualDisplay (private) | Virtual displays, vendorID must be non-zero, call on main thread |
| CoreDisplay (dlsym) | Built-in display brightness reading |

<!-- Generated by Harness Engineering system on 2026-03-12. Review and customize. -->
