# Phase 0: Project Initialization ⏳

> Executed automatically by project-planner

## Task List

- [ ] Create the project directory structure
  ```
  Backlit/
  ├── project.yml                    # xcodegen project config
  ├── Backlit/
  │   ├── App/
  │   │   ├── BacklitApp.swift   # @main entry, MenuBarExtra
  │   │   └── AppDelegate.swift      # NSApplicationDelegate, permission requests
  │   ├── Views/                     # SwiftUI view layer
  │   ├── ViewModels/                # ViewModel layer
  │   ├── Models/                    # Data models
  │   ├── Services/                  # Low-level services (DDC, display management, etc.)
  │   ├── Utilities/                 # Utility functions
  │   ├── Resources/
  │   │   └── Assets.xcassets/       # Icon assets
  │   └── Backlit.entitlements   # Entitlements declaration
  └── docs/
      └── roadmap/                   # This file lives here
  ```
  - Implementation hint: create all directories with `mkdir -p`

- [ ] Create `project.yml` (xcodegen config)
  - Implementation hint: configure a macOS app target, minimum deployment macOS 14.0, App Sandbox off,
    Hardened Runtime configured, link IOKit.framework, CoreGraphics.framework,
    ScreenCaptureKit.framework, ColorSync.framework.
    The entitlements file points to Backlit/Backlit.entitlements
  - Verify: `xcodegen generate` successfully generates Backlit.xcodeproj

- [ ] Create `Backlit/Backlit.entitlements`
  - Implementation hint: turn off App Sandbox (`com.apple.security.app-sandbox` = false),
    enable Hardened Runtime related entitlements
  - Verify: the file exists and its XML is valid

- [ ] Create `Backlit/App/BacklitApp.swift`
  - Implementation hint: use `@main` + the SwiftUI `App` protocol,
    `MenuBarExtra("Backlit", systemImage: "display")` creates the menu bar icon,
    initially put a "Backlit v0.1" text + a "Quit" button in the menu.
    Set `.menuBarExtraStyle(.window)` to support custom views.
  - Verify: after building and running, a display icon appears in the menu bar and clicking it opens a panel

- [ ] Create `Backlit/App/AppDelegate.swift`
  - Implementation hint: `NSApplicationDelegate`, in `applicationDidFinishLaunching`
    hide the Dock icon (`NSApp.setActivationPolicy(.accessory)`)
  - Verify: after running there is no Dock icon, only the menu bar is visible

- [ ] Create `Backlit/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
  - Implementation hint: use the standard macOS app icon set Contents.json template, do not include actual icon files yet
  - Verify: no asset catalog warnings when xcodegen generates the project

- [ ] Create skeleton files (with TODO comments)
  - `Backlit/Models/DisplayInfo.swift`: `class DisplayInfo: ObservableObject, Identifiable` stores info for a single display
  - `Backlit/Services/DisplayManager.swift`: `class DisplayManager: ObservableObject` manages all displays
  - `Backlit/Services/DDCService.swift`: `class DDCService` DDC/CI I2C communication
  - `Backlit/Views/MenuBarView.swift`: main menu view skeleton
  - Each file contains imports, the class declaration, key method signatures + `// TODO: Phase N` comments

- [ ] Generate the Xcode project with xcodegen and build
  - Implementation hint: `cd ~/Desktop/Backlit && xcodegen generate && xcodebuild -scheme Backlit -configuration Debug build`
  - Verify: `xcodebuild build` succeeds with no compile errors

## Phase Acceptance

```bash
cd ~/Desktop/Backlit
xcodegen generate   # successfully generates .xcodeproj
xcodebuild -scheme Backlit -configuration Debug build  # build succeeds
# After running: a display icon appears in the menu bar, clicking it opens "Backlit v0.1" + a Quit button
```
