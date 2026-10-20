# Roadmap — Backlit

> Created: 2026-03-02 | Goal: a free macOS menu bar display management app that fully replaces BetterDisplay
> **See detailed implementation hints in**: `docs/roadmap/phase-N.md`

## Archived Phases (0-17)

> Details: `docs/roadmap/archive/`

- Phase 0: Project initialization ✅
- Phase 1: Display detection and menu UI ✅
- Phase 2: Brightness control (DDC + built-in) ✅
- Phase 3: Resolution management and HiDPI ✅
- Phase 4: Screen rotation and display arrangement ✅
- Phase 5: Color management ✅
- Phase 6: Image adjustment ✅
- Phase 7: Advanced display management ✅
- Phase 8: Screen mirroring ✅
- Phase 9: Screen streaming and Picture-in-Picture ✅
- Phase 10: Virtual displays ✅
- Phase 11: Config protection and auto brightness ✅
- Phase 12: Wrap-up and release ✅
- Phase 13: Critical bug fixes ✅
- Phase 14: Performance optimization (eliminate stutter) ✅
- Phase 15: Interaction polish ✅
- Phase 16: Comprehensive bug fixes ✅
- Phase 17: Core feature fixes — DDC/HiDPI/notch ✅

## Phase 18: Stability Hardening ✅
> Details: `docs/roadmap/phase-18.md`

### Task 1: Unified timeout protection for blocking CG calls
- [x] Extract VirtualDisplayService's `runWithTimeout` into a shared utility function
- [x] MirrorService: add timeout protection to `enableMirror`/`disableMirror`
- [x] ArrangementService: add timeout protection to `setPosition`
- [x] ResolutionService: add 10-second timeout protection to `applyModeSync`

### Task 2: Automatic re-arrangement on display configuration change
- [x] Register `CGDisplayRegisterReconfigurationCallback`
- [x] After the configuration change completes, call `arrangeExternalAboveBuiltin()` with a 500ms delay
- [x] Debounce (when the callback fires multiple times within 500ms, only the last one runs)

### Task 3: Automatically restore HiDPI after sleep/wake
- [x] On wake, check for active HiDPI sessions and recreate them if lost
- [x] Restore sequence: create → apply settings → sleep 500ms → mirror → setDisplayMode → arrange
- [x] Persist HiDPI state to UserDefaults (`fd.hiDPI.activePhysicalIDs`)

### Task 4: Error recovery and user feedback
- [x] Show a menu bar status message when a CG call times out
- [x] Prompt the user to re-enable HiDPI manually when HiDPI restoration fails
- [x] Automatically disable HiDPI and notify the user after 3 consecutive failures

## Phase 19: Display Preset System ✅
> Details: `docs/roadmap/phase-19.md`

### Task 1: Preset data model
- [x] Create `Models/DisplayPreset.swift`
- [x] Create `Services/PresetService.swift`: load/save/apply presets
- [x] Store presets in `~/Library/Application Support/Backlit/presets.json`

### Task 2: Built-in default presets
- [x] "HiDPI Mode": enableHiDPIVirtual + 1920×1080 + arrangement
- [x] "Native Mode": disable HiDPI virtual + restore native resolution + arrangement
- [x] Built-in presets cannot be deleted (`isBuiltin: true`)

### Task 3: Save current state as a preset
- [x] Add a "Save as Preset" button to the menu bar
- [x] Inline form: enter a name, choose an icon
- [x] Automatically capture the current state of all displays and save it

### Task 4: Preset list and one-click switching
- [x] Show the preset list in MenuBarView (replacing the HiDPIPresetRow position)
- [x] Each preset shows icon + name + a "current match" badge
- [x] Click a preset → apply it (loading spinner)
- [x] Long press / right click → delete (non-built-in presets)

## Phase 20: Release Preparation ✅
> Details: `docs/roadmap/phase-20.md`

### Task 1: App icon
- [x] Design a display icon and generate all AppIcon.appiconset sizes
- [x] Update project.yml to reference AppIcon

### Task 2: Launch at Login improvements
- [x] Confirm `SMAppService.mainApp` is used (macOS 13+)
- [x] On first launch, ask the user whether to start at login

### Task 3: DMG packaging
- [x] Create the `scripts/build-dmg.sh` script
- [x] Release build + DMG packaging (Backlit.app + Applications shortcut)

### Task 4: GitHub Release
- [x] Add feature screenshots to README.md
- [x] Add CHANGELOG.md
- [x] `scripts/release.sh`: build → package DMG → gh release create

### Task 5: UpdateService polish
- [x] Confirm the update check logic points to the GitHub Releases API
- [x] Show a download link when a new version is detected
- [x] Confirm the "Check for updates on launch" toggle works
