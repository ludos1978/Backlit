# File Tree — Backlit (Annotated)

> Full annotated directory structure. Quick reference: [CLAUDE.md](CLAUDE.md), module relationships: [relationships.md](relationships.md).

---

```
Backlit/
├── docs/                           # Project documentation directory
│   ├── roadmap/                    # Phase planning docs (planner output, do not hand-edit the structure)
│   │   ├── CLAUDE.md               # roadmap overview and current phase notes
│   │   ├── phase-0.md              # Phase 0: Foundation scaffolding
│   │   ├── phase-1.md              # Phase 1: Display enumeration + menu bar entry
│   │   ├── phase-2.md              # Phase 2: DDC brightness/contrast control
│   │   ├── phase-3.md              # Phase 3: Resolution switching
│   │   ├── phase-4.md              # Phase 4: Rotation + arrangement
│   │   ├── phase-5.md              # Phase 5: Color management (ICC Profile)
│   │   ├── phase-6.md              # Phase 6: Image adjustment (Gamma/software filters)
│   │   ├── phase-7.md              # Phase 7: Advanced display management
│   │   ├── phase-8.md              # Phase 8: Screen mirroring
│   │   ├── phase-9.md              # Phase 9: Screen streaming + picture-in-picture
│   │   ├── phase-10.md             # Phase 10: Virtual displays
│   │   ├── phase-11.md             # Phase 11: Auto brightness + config protection
│   │   ├── phase-12.md             # Phase 12: System color picker + video filters + settings
│   │   ├── phase-13.md             # Phase 13: Critical bug fixes
│   │   ├── phase-14.md             # Phase 14: Performance optimization
│   │   ├── phase-15.md             # Phase 15: Other enhancements
│   │   ├── phase-16.md             # Phase 16: HiDPI virtual displays + presets
│   │   └── phase-17.md             # Phase 17: UI/UX polish
│   ├── codemap/                    # Code navigation map (this directory)
│   │   ├── CLAUDE.md               # Quick reference index (module summary, high-risk files, task table)
│   │   ├── file-tree.md            # Full annotated directory structure (this file)
│   │   └── relationships.md        # Module relationship diagram + service internal dependencies + data flow
│   ├── BLOCKING.md                 # Blocking issue tracker (must read before starting work)
│   ├── habits.md                   # Development preferences and working habits log
│   ├── lessons.md                  # Lessons learned and pitfalls
│   └── ROADMAP.md                  # Overall progress tracking (autopilot tracks [x] marks here)
├── build.sh                        # Clean build script: xcodegen generate → xcodebuild clean build into build/ (ad-hoc signing when no Apple Development certificate; --release, --run; SIGN=adhoc)
├── Backlit/                    # Swift source directory (xcodegen automatically includes all .swift files)
│   ├── App/                        # App entry point, SwiftUI App lifecycle
│   │   ├── AppDelegate.swift       # NSApplicationDelegate, ensures the app shows only in the menu bar; changes affect App lifecycle hooks
│   │   └── BacklitApp.swift    # @main entry point, creates DisplayManager and mounts MenuBarView; changes affect the whole App initialization chain
│   ├── Models/                     # Data model layer (pure data, no side effects)
│   │   ├── DisplayInfo.swift       # ⚠️ Core display model, 12+ @Published properties; all Views/Services depend on this class, adding or removing properties requires a global grep to sync
│   │   ├── DisplayMode.swift       # Value type for a single display mode (resolution + refresh rate + HiDPI flag); changes to enumeration logic affect resolution switching and mode list display
│   │   └── DisplayPreset.swift     # Display configuration preset model: DisplayPreset (preset) + DisplayPresetEntry (single display snapshot); Codable, persisted by PresetService. Entry carries an optional GammaAdjustment snapshot + optional softwareDimming (extra dimming %); preset carries optional XDR (enabled/level) + accessibility contrast state (legacy resolution/position fields are decoded but never applied)
│   ├── Services/                   # Business logic layer, interacts directly with system frameworks
│   │   ├── AdaptiveBrightnessService.swift # Adaptive brightness engine: per-display learned curve (content lightness × ambient light), modes content/ambient/both/follow-built-in, min/max/sensitivity/speed, learning from manual changes, ignore list with per-app brightness; drives BrightnessService
│   │   ├── AmbientLightService.swift       # Ambient light sensor (lux) via IOHIDEventSystemClient SPI (Apple Silicon), BezelServices fallback; smoothed; wake-safe
│   │   ├── ContentLightnessSampler.swift   # Per-display ScreenCaptureKit stream at 1/16 scale → CIE L* lightness (mean/RMS), stabilized; frames analysed in memory only
│   │   ├── BrightnessService.swift         # Unified brightness interface: built-in display uses IODisplayGetFloatParameter, external displays use DDC VCP 0x10; changes affect all brightness read/write paths
│   │   ├── CGHelpers.swift                 # Shared blocking CG call utility: CGHelpers.runWithTimeout(seconds:fallback:operation:) runs WindowServer IPC blocking operations on a background thread with timeout protection; used by ResolutionService, VirtualDisplayService
│   │   ├── ColorProfileService.swift       # ICC Profile enumeration (scans 3 system directories) and switching (ColorSync API); changes affect the color profile list and switching
│   │   ├── DDCService.swift                # ⚠️ Core of IOKit I2C DDC/CI communication: IOFramebuffer lookup, VCP read/write, 5 second TTL cache, 3 retries; low-level dependency of almost all external display features, change with extreme care
│   │   ├── DisplayManager.swift            # ⚠️ Display enumeration (CGGetOnlineDisplayList) + CGDisplay hot-plug callback (auto-arrange feature removed 2026-09-07 — the app never moves displays on its own); @Published displays is injected globally, changes affect the whole display list data flow
│   │   ├── GammaService.swift              # Software Gamma adjustment: CGSetDisplayTransferByFormula/Table, supports contrast/gain/color temperature/quantization/invert; the sole entry point for all gamma/software brightness writes; changes affect image adjustment effects
│   │   ├── HiDPIService.swift              # Writes /Library/Displays/...plist to inject HiDPI scaled modes, requires administrator privileges; changes affect HiDPI override generation logic
│   │   ├── LaunchService.swift             # SMAppService manages launch at login (macOS 13+); changes only affect the Launch at Login feature
│   │   ├── NotchOverlayManager.swift       # Creates a black mask NSWindow (screenSaver level) over the built-in display's notch area; changes affect the visual effect and level of the notch mask
│   │   ├── ResolutionService.swift         # Switches display modes via CGConfigureDisplayWithDisplayMode; applyModeSync is now async, the whole CG transaction runs inside CGHelpers.runWithTimeout; resolvedTargetDisplayID() falls back to VirtualDisplayService during mirror detection; changes affect the resolution switching success rate
│   │   ├── SettingsService.swift           # UserDefaults + JSON file persistence of global and per-display settings; PreferenceArea ownership model (authoritativeAreas: Backlit-controlled vs macOS-controlled per area, gates launch/wake re-apply) + per-display brightness by UUID; when changing, mind key naming (must use the fd. prefix) and backward compatibility. Opt-in (default OFF) switches: interceptBrightnessKeys (event tap), interceptVolumeKeys (volume keys → monitor speakers)
│   │   ├── AccessibilityService.swift      # Bridges macOS Accessibility "Increase contrast" + "Display Contrast" via private SPI (UAIncreaseContrastSetEnabled, CGSSetDisplayContrast, dlsym) — the pref domain is TCC-protected and pref writes are not applied live; follows System Settings changes via NSWorkspace notification
│   │   ├── DisplayStreamService.swift      # Live stream window for a (virtual) display: ScreenCaptureKit SCStream → AVSampleBufferDisplayLayer in a floating aspect-locked NSWindow on a physical screen; needs Screen Recording permission
│   │   ├── UndoService.swift               # App-wide undo stack for display adjustments (⌘Z in the menu window); controls push restore closures on gesture begin, views re-sync via undoTick
│   │   ├── UpdateService.swift             # Checks for new versions via the GitHub Releases API, semantic version comparison; changes affect update check logic
│   │   ├── VolumeService.swift             # Monitor speaker volume/mute via DDC (VCP 0x62/0x8D), remembered per display (fd.volume.uuid.*), CoreAudio match of HDMI/DP sound output → display for the volume keys
│   │   ├── XDRBrightnessService.swift      # XDR brightness mode (BrightIntosh-style, clean-room): 1×1 EDR trigger overlay per XDR panel + gamma-table boost via GammaService.setXDRBoost; persists fd.xdr.* keys, polls EDR headroom 1s
│   │   ├── VirtualDisplayService.swift     # Virtual display creation/destruction: CGVirtualDisplay private API (vendorID must be non-zero such as 0xEEEE, created on the main thread), HiDPI via mirror mode, CGHelpers.runWithTimeout timeout protection, hiDPILog file debug log, ObjC type Sendable extensions; HiDPI config only takes effect at runtime and is not persisted; changes affect virtual displays and the one-click HiDPI preset feature
│   │   └── PresetService.swift             # Preset management (user presets only; generated Native/HiDPI built-ins removed 2026-09-08): save/load/apply display configuration presets; uses DisplayManagerAccessor to read current display state; presets.json is stored in ~/Library/Application Support/Backlit/. Captures the built-in display too (brightness + gamma; its resolution is never changed on apply) plus XDR and accessibility contrast state
│   ├── Utilities/                  # Utility extensions
│   │   └── NSScreenExtension.swift         # NSScreen extension: finds the NSScreen by CGDirectDisplayID, gets displayID; depended on by NotchView, NotchOverlayManager
│   ├── Backlit-Bridging-Header.h       # Private API declarations: CGVirtualDisplay (macOS 14+) and IOAVService (Apple Silicon DDC); property names verified against Chromium source (maxPixelsWide/maxPixelsHigh, not maxPixelSize)
│   └── Views/                      # SwiftUI view layer
│       ├── AdaptiveBrightnessView.swift    # Adaptive Brightness options (mode, live lux/lightness, sensitivity/min/max, response, sampling, learning, per-display, ignore list, reset)
│       ├── BrightnessSliderView.swift      # All-displays controls: CombinedBrightnessView, CombinedGammaView, ExtraDimmingRow (the per-display brightness/dim rows now live inside ImageAdjustmentView). Also CombinedGammaView (all-displays gamma) and ExtraDimmingRow ("Dim Below Minimum": software dimming below the hardware floor via BrightnessService.setExtraDimming; per-display + all-displays)
│       ├── ColorProfileView.swift          # ICC Profile list (recommended/all grouping) and switching; depends on ColorProfileService
│       ├── DisplayDetailView.swift         # ⚠️ Per-display expanded panel, container of collapsible Sections (three groups); adding/removing a Section requires changing this file and syncing MenuBarView
│       ├── DisplayModeListView.swift       # Resolution mode list (HiDPI/native/other groups), favorites pinned with a star, click to switch; depends on ResolutionService
│       ├── ImageAdjustmentView.swift       # Image adjustment fold: brightness + Dim Below Min rows (BrightnessService) followed by contrast/gamma/gain/temp/levels/per-channel/quantization/invert (GammaService), all in the same AdjustRow style
│       ├── MenuBarView.swift               # ⚠️ Main menu bar view: display list + expand/collapse + tools area + settings area + PresetListView; the entry container for all features, changes affect the global layout
│       ├── NotchView.swift                 # Notch info display + mask toggle (shown only for built-in displays with a notch); depends on NotchOverlayManager
│       ├── SystemColorView.swift           # System color picker (NSColorSampler) + HEX/RGB/HSB display + history; depends on SettingsService for persisting color history
│       ├── DisplayStreamRowView.swift      # "Show in Window" row in each display panel (physical or virtual) → DisplayStreamService
│       ├── OSControlledModifier.swift      # .osControlled(area): read-only + click opens the macOS settings panel while the area is macOS-controlled
│       ├── HiDPIView.swift                 # HiDPI Override status row (plist approach) + write/restore buttons; depends on HiDPIService
│       ├── AccessibilityContrastView.swift # System-wide accessibility contrast controls (Increase Contrast toggle + Display Contrast slider) in the top section; depends on AccessibilityService
│       ├── XDRBrightnessView.swift         # XDR brightness section (tools panel: toggle + level slider) + XDRQuickSliderView (top-section quick slider, 0 = off); depends on XDRBrightnessService
│       ├── VirtualDisplayView.swift        # Virtual display config list + creation form (preset resolutions) + one-click HiDPI preset; depends on VirtualDisplayService
│       ├── VolumeRow.swift                 # Per-display volume slider + mute button (DisplayDetailView, external only; hidden when DDC volume is unsupported); depends on VolumeService
│       └── SavePresetView.swift            # Saves the current display state as a preset; inline form (name + icon picker); calls PresetService.captureCurrentState + addPreset
├── Backlit.xcodeproj/          # Xcode project file (generated by xcodegen, do not edit manually)
├── .gitignore                      # Git ignore rules
├── build.sh                        # Quick build script
├── CLAUDE.md                       # Claude context entry point (project rules, decision conventions)
└── project.yml                     # xcodegen config, must re-run xcodegen generate after changes
```
