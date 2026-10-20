# Working Habits — Backlit

> Updated: 2026-03-02

## Build and Test

- Build command: `cd ~/Desktop/Backlit && xcodebuild -scheme Backlit -configuration Debug build 2>&1 | tail -5`
- After changing project.yml, run `xcodegen generate` before building
- Build output is very long, only look at the last few lines (`| tail -5`)

## Code Style

- Keep SwiftUI views declarative, extract complex logic into ViewModel/Service
- Annotate all ObservableObject classes with @MainActor (resolves Swift 6 concurrency checking)
- Service layer uses the singleton pattern (`static let shared`), marked `@unchecked Sendable`

## Project Management

- xcodegen manages the project, don't edit .xcodeproj by hand
- Put new files in the matching subdirectory under Backlit/, xcodegen includes them automatically
- After each Phase is complete, update the `[x]` markers in the roadmap

## Agent Execution Quality Control

- Instructions to agents should contain **exact code changes** (which line to change to what), not high-level descriptions
- Compiling ≠ working; runtime behavior must be verified
- For features involving hardware interaction (DDC, IOKit), agents can hardly verify them; manual testing is needed to confirm

## Multi-Agent Optimization Workflow (verified effective in Rounds 3-4)

- **Separate scanning and fixing**: first run 4 scanning agents in parallel (read-only), collect all issues, then dispatch fixing agents — fixing agents have full context and don't miss related fixes
- **Scans must cover "feature interaction chains"**: don't just scan single-file bugs; cover the full chain of each feature "user action → UI → Service → system API → callback", only then are cross-Service interaction issues found
- **Fix P0 first, compile once per batch**: don't accumulate too many changes before compiling, failures are hard to locate
- **0 warnings is the quality floor**: clear all warnings before the end of each round

## SwiftUI Component Development

- Row components needing local state such as hover/loading → extract into a standalone struct (don't use @ViewBuilder functions, @ViewBuilder doesn't support @State)
- Naming convention: reusable row components use `XxxRow` or `XxxRowView`, private structs get the `private` modifier
- Standard hover effect template: `@State private var isHovered = false` + `.background(Color.primary.opacity(isHovered ? 0.06 : 0))` + `.onHover { isHovered = $0 }` + `.animation(.easeInOut(duration: 0.15), value: isHovered)`

## Multi-Agent UX Polish Workflow (verified effective over 3 rounds)

- **Group by feature domain**: assign MenuBar/DetailView/Sliders/FeatureViews to different agents, never let two agents edit the same file
- **Read before changing**: tell the agent "read the whole file first, then change according to the list", to avoid changes based on assumptions
- **Compile and verify at the end of each round**: after all agents report, do a final compile check with `xcodebuild`
- **Make the improvement list specific**: instructions to agents must include the target struct name, @State variable name, and the exact modifier code, not high-level descriptions like "add a hover effect"

## Debugging Patterns

- **File logging**: when stdout/stderr is not visible (e.g. a menu bar app), write a `~/Desktop/xxx_debug.log` file to trace the execution flow; more reliable than print/NSLog
- **Reference implementation verification**: don't guess private APIs; use a known working open-source project (Chromium, BetterDisplay, node-mac-virtual-display) as the authoritative reference and compare property names and call patterns

## UX Patterns

- **One-click preset pattern**: wrap multi-step operations (create virtual display + set resolution + arrange) into a single toggle for the best UX; applies to every feature that is only meaningful as a combination of actions

## HiDPI Development Experience

- **Plist override is the only viable HiDPI approach**: write to `/Library/Displays/Contents/Resources/Overrides/`, needs admin privileges (NSAppleScript), takes effect after reconnecting the display
- **Don't set DisplayProductName in the override plist**: it overrides the system display name
- **Getting the native resolution**: use `availableModes.max()` instead of `CGDisplayPixelsWide/High` (the latter returns the current resolution)
- **Private framework loading**: always use dlopen+dlsym, not @_silgen_name (causes a linker error)
