# Phase 19: Display Preset System

> Status: Done | Estimate: medium complexity

## Goal

Extend one-click HiDPI into a general display preset system, where the user can save the current display state as a preset and switch between configurations with one click.

## Tasks

### Task 1: Preset data model
- [x] Create `Models/DisplayPreset.swift` and define the preset struct:
  - `id: UUID`, `name: String`, `icon: String` (SF Symbol name)
  - `displays: [DisplayPresetEntry]`, where each entry contains:
    - `displayUUID: String` (matches the physical display)
    - `width: Int`, `height: Int`, `isHiDPI: Bool` (target resolution)
    - `brightness: Double?` (optional brightness)
    - `arrangement: CGPoint?` (optional arrangement position)
    - `enableHiDPIVirtual: Bool` (whether to enable the HiDPI virtual display)
- [x] Create `Services/PresetService.swift`: load/save/apply presets
- [x] Store presets in `~/Library/Application Support/Backlit/presets.json`

**Implementation hint**: Match displays by `display.displayUUID` (stable UUID generation logic already exists). When applying a preset, skip an entry if its display is not online.

### Task 2: Built-in default presets
- [x] "HiDPI Mode": reuse the current HiDPIPresetRow logic (enableHiDPIVirtual + 1920×1080 + arrangement)
- [x] "Native Mode": disable HiDPI virtual + restore the display's native resolution + arrangement
- [x] Built-in presets cannot be deleted; mark them `isBuiltin: true`

**Implementation hint**: Move HiDPIPresetRow's turnOn/turnOff logic into PresetService.applyPreset(), and change HiDPIPresetRow to call PresetService.

### Task 3: Save current state as a preset
- [x] Add a "Save as Preset" button to the menu bar (below the preset list)
- [x] Clicking it shows an inline form: enter a name, choose an icon
- [x] Automatically capture the current resolution, HiDPI state, brightness, and arrangement position of all displays
- [x] Save to presets.json

**Implementation hint**: Follow the inline form pattern of CreateVirtualDisplayForm. For icon selection use a Picker with a few predefined SF Symbols.

### Task 4: Preset list and one-click switching
- [x] Show the preset list in MenuBarView (replace the HiDPIPresetRow position with a preset section)
- [x] Each preset shows: icon + name + whether it is the current one (green "Current" badge)
- [x] Click a preset → apply it (show a loading spinner)
- [x] Long press / right click → delete (non-built-in presets)

**Implementation hint**: Preset match detection: iterate over each DisplayPresetEntry and check whether the current resolution and HiDPI state are the same. If all match, mark it as "Current".

## Acceptance Criteria

```bash
# Build passes
xcodebuild -scheme Backlit -configuration Debug build 2>&1 | tail -3

# Manual testing
# 1. Enable HiDPI → save as preset "Work Mode" → disable HiDPI → click "Work Mode" → HiDPI is restored
# 2. Switch to 1280×720 → save as preset "Low Resolution" → switch between the two presets
# 3. The built-in "HiDPI Mode" and "Native Mode" cannot be deleted
```
