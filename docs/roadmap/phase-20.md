# Phase 20: Release Preparation

> Status: Done | Estimate: medium complexity

## Goal

Package Backlit from its development state into a distributable, official macOS app, including icon, code cleanup, DMG installer, and GitHub Release.

## Tasks

### Task 1: Code cleanup + App icon
- [x] Delete the deprecated `HiDPIPresetRow` in MenuBarView (replaced by PresetListView)
- [x] Search for and clean up other unused code / dead code
- [x] Generate the App icon with a Python PIL/Pillow script: rounded-rectangle display + "F" letter + blue-purple gradient
- [x] Generate all AppIcon.appiconset sizes (16/32/64/128/256/512/1024)
- [x] Create `Backlit/Assets.xcassets/AppIcon.appiconset/Contents.json` + PNG files
- [x] Update project.yml to reference the AppIcon asset catalog

**Implementation hint**: Generate a 1024×1024 PNG with a Python script and scale to each size with `sips -z H W`. project.yml needs `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` added.

### Task 2: Launch at Login (SMAppService)
- [x] In `LaunchService.swift`, migrate the existing implementation to `SMAppService.mainApp` (macOS 13+)
- [x] `register()` / `unregister()` replace the old API; requires `import ServiceManagement`
- [x] Confirm the existing `fd.launchAtLogin` toggle in SettingsService is wired up correctly
- [x] First-launch prompt: if `fd.launchAtLogin` has never been set, show a one-time prompt

**Implementation hint**: `SMAppService.mainApp.register()` is a single line of code. Check status with `.status == .enabled`.

### Task 3: Release build + Ad-hoc signing + DMG packaging
- [x] Create the one-step script `scripts/build-dmg.sh`
- [x] Release build: `xcodebuild -scheme Backlit -configuration Release build`
- [x] Ad-hoc signing: `codesign --force --deep --sign - Backlit.app` (minimum requirement when there is no Developer ID)
- [x] Package the DMG with `hdiutil`: Backlit.app + Applications shortcut
- [x] Explain in the README that on first open the user must right-click → Open (to bypass Gatekeeper)

**Implementation hint**: `hdiutil create -volname "Backlit" -srcfolder build/ -ov -format UDZO Backlit.dmg`. An app without Developer ID signing must be trusted manually by the user.

### Task 4: README + CHANGELOG + GitHub Release script
- [x] Write README.md: project introduction, feature list, installation instructions, screenshot placeholders, Gatekeeper bypass instructions
- [x] Write CHANGELOG.md: summarize the main changes from Phase 0-20
- [x] Create `scripts/release.sh`: build → sign → package DMG → `gh release create`
- [x] Add a download badge to the README

**Implementation hint**: Screenshots need to be taken manually with `screencapture` after running the app; use placeholders for now. `gh release create v1.0.0 --title "Backlit v1.0.0" --notes-file CHANGELOG.md *.dmg`.

### Task 5: UpdateService polish
- [x] Confirm that UpdateService's update check logic points to the GitHub Releases API
- [x] Use the placeholder URL `https://api.github.com/repos/OWNER/Backlit/releases/latest` (replace when the user publishes)
- [x] Show a download link in the menu bar when a new version is detected
- [x] Confirm the "Check for updates on launch" toggle in the settings UI works

**Implementation hint**: The GitHub Releases API returns JSON; parse `tag_name` and compare it with the current `CFBundleShortVersionString`.

## Acceptance Criteria

```bash
# Release build
xcodebuild -scheme Backlit -configuration Release build 2>&1 | tail -3

# DMG packaging
./scripts/build-dmg.sh

# Verification
# 1. Double-click the DMG to install → drag to Applications → launches normally
# 2. The App icon displays correctly in the Dock/Finder
# 3. The Launch at Login toggle works
# 4. README/CHANGELOG content is complete
```
