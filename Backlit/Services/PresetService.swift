import Foundation
import CoreGraphics

/// Manages display configuration presets: save, load, and one-click apply.
@MainActor
final class PresetService: ObservableObject, @unchecked Sendable {
    static let shared = PresetService()

    @Published var presets: [DisplayPreset] = []
    @Published var isApplying: Bool = false
    @Published var applyingPresetID: UUID? = nil

    private let filename = "presets.json"
    private let lastAppliedKey = "fd.presets.lastApplied"

    /// The preset the user last applied or saved — the one an "Update" button
    /// refers to once the live state drifts from what it stores.
    @Published private(set) var lastAppliedPresetID: UUID? {
        didSet { UserDefaults.standard.set(lastAppliedPresetID?.uuidString, forKey: lastAppliedKey) }
    }

    private init() {
        loadPresets()
        lastAppliedPresetID = UserDefaults.standard.string(forKey: lastAppliedKey).flatMap(UUID.init)
    }

    // MARK: - Persistence

    func loadPresets() {
        let saved = SettingsService.shared.load([DisplayPreset].self, filename: filename) ?? []
        // Only user-created presets exist now (the generated Native/HiDPI resolution
        // presets were removed as confusing); ignore any stale built-in entries.
        presets = saved.filter { !$0.isBuiltin }
    }

    func savePresets() {
        // Only persist user-created presets; built-ins are always regenerated
        let toSave = presets.filter { !$0.isBuiltin }
        SettingsService.shared.save(toSave, filename: filename)
    }

    // MARK: - CRUD

    func addPreset(_ preset: DisplayPreset) {
        presets.append(preset)
        savePresets()
        lastAppliedPresetID = preset.id
    }

    func deletePreset(id: UUID) {
        guard let index = presets.firstIndex(where: { $0.id == id }),
              !presets[index].isBuiltin else { return }
        presets.remove(at: index)
        savePresets()
        if lastAppliedPresetID == id { lastAppliedPresetID = nil }
    }

    // MARK: - Update (selected preset modified by the user)

    /// True when the live display state differs from what `preset` stores.
    /// Only the values a preset actually carries are compared (older presets with
    /// nil fields ignore those); disconnected displays are skipped.
    func isModified(_ preset: DisplayPreset) -> Bool {
        guard !preset.isBuiltin else { return false }
        let now = captureCurrentState(name: preset.name, icon: preset.icon,
                                      includeArrangement: preset.restoresArrangement == true)
        let displays = DisplayManagerAccessor.shared.displays
        // A connected display the preset does not cover yet (e.g. presets saved
        // before an external was attached) — updating would add it.
        let covered = Set(preset.displays.map(\.displayUUID))
        if now.displays.contains(where: { !covered.contains($0.displayUUID) }) { return true }
        for entry in preset.displays {
            guard let cur = now.displays.first(where: { $0.displayUUID == entry.displayUUID }) else { continue }
            let isBuiltin = displays.first { $0.displayUUID == entry.displayUUID }?.isBuiltin ?? false
            if !isBuiltin,
               entry.width != cur.width || entry.height != cur.height || entry.isHiDPI != cur.isHiDPI {
                return true
            }
            if let b = entry.brightness, let c = cur.brightness, abs(b - c) > 0.01 { return true }
            if let adj = entry.gammaAdjustment, let c = cur.gammaAdjustment, adj != c { return true }
            if let d = entry.softwareDimming, let c = cur.softwareDimming, abs(d - c) > 0.5 { return true }
            if preset.restoresArrangement == true,
               let x = entry.arrangementX, let y = entry.arrangementY,
               let cx = cur.arrangementX, let cy = cur.arrangementY,
               Int(x) != Int(cx) || Int(y) != Int(cy) {
                return true
            }
        }
        if let enabled = preset.xdrEnabled {
            if enabled != XDRBrightnessService.shared.isEnabled { return true }
            if enabled, let level = preset.xdrLevel,
               abs(level - XDRBrightnessService.shared.level) > 0.005 { return true }
        }
        if let ic = preset.increaseContrast, ic != AccessibilityService.shared.increaseContrast { return true }
        if let ad = preset.adaptiveBrightnessEnabled, ad != AdaptiveBrightnessService.shared.isEnabled { return true }
        if let dc = preset.displayContrast, abs(dc - AccessibilityService.shared.displayContrast) > 0.005 { return true }
        return false
    }

    /// Overwrites a user preset with the current display state, keeping its id,
    /// name, icon and arrangement opt-in. Undoable with ⌘Z.
    func updatePreset(id: UUID) {
        guard let index = presets.firstIndex(where: { $0.id == id }),
              !presets[index].isBuiltin else { return }
        let previous = presets[index]
        var fresh = captureCurrentState(name: previous.name, icon: previous.icon,
                                        includeArrangement: previous.restoresArrangement == true)
        fresh.id = previous.id
        presets[index] = fresh
        savePresets()
        lastAppliedPresetID = previous.id
        UndoService.shared.push { [weak self] in
            Task { @MainActor in
                guard let self, let i = self.presets.firstIndex(where: { $0.id == previous.id }) else { return }
                self.presets[i] = previous
                self.savePresets()
            }
        }
    }

    // MARK: - Apply

    /// Applies a preset: for each entry, finds the matching display and applies settings.
    func applyPreset(_ preset: DisplayPreset) async {
        guard !isApplying else {
            debugLog("[PresetService] applyPreset: already applying, skipped")
            return
        }
        isApplying = true
        applyingPresetID = preset.id
        defer {
            isApplying = false
            applyingPresetID = nil
        }
        lastAppliedPresetID = preset.id

        let settings = SettingsService.shared
        let displays = DisplayManagerAccessor.shared.displays
        debugLog("[PresetService] applyPreset '\(preset.name)': \(displays.count) display(s) online, preset has \(preset.displays.count) entr(ies)")

        if displays.isEmpty {
            debugLog("[PresetService] WARNING: displays list is empty – DisplayManagerAccessor may not be set up")
        }

        for (i, display) in displays.enumerated() {
            debugLog("[PresetService]   display[\(i)] uuid=\(display.displayUUID) id=\(display.displayID) online=\(display.isOnline) modes=\(display.availableModes.count)")
        }

        var anyActionTaken = false

        for entry in preset.displays {
            debugLog("[PresetService] entry uuid=\(entry.displayUUID) target=\(entry.width)×\(entry.height) hiDPI=\(entry.isHiDPI)")

            guard let display = displays.first(where: { $0.displayUUID == entry.displayUUID }) else {
                debugLog("[PresetService]   -> no display matched UUID '\(entry.displayUUID)' – skipping")
                continue
            }
            guard display.isOnline else {
                debugLog("[PresetService]   -> display '\(display.name)' is offline – skipping")
                continue
            }

            let displayID = display.displayID
            debugLog("[PresetService]   -> matched display '\(display.name)' (id=\(displayID)), \(display.availableModes.count) available modes")

            // Set resolution — never for the built-in display (policy), but
            // brightness/gamma below still apply to it. Skipped while macOS owns
            // the Resolution area.
            if display.isBuiltin || !settings.isAuthoritative(.resolution) {
                debugLog("[PresetService]   -> built-in display, skipping resolution change")
            } else {
                let targetMode = display.availableModes.first(where: {
                    $0.width == entry.width &&
                    $0.height == entry.height &&
                    $0.isHiDPI == entry.isHiDPI
                }) ?? display.availableModes.first(where: {
                    $0.width == entry.width && $0.height == entry.height
                })

                if let mode = targetMode {
                    let currentMode = display.currentDisplayMode
                    let alreadyActive = currentMode?.width == mode.width
                        && currentMode?.height == mode.height
                        && currentMode?.isHiDPI == mode.isHiDPI
                    if alreadyActive {
                        debugLog("[PresetService]   -> resolution \(mode.width)×\(mode.height) hiDPI=\(mode.isHiDPI) already active, skipping mode switch")
                    } else {
                        debugLog("[PresetService]   -> setting mode \(mode.width)×\(mode.height) hiDPI=\(mode.isHiDPI)")
                        let ok = await ResolutionService.shared.setDisplayMode(mode, for: displayID)
                        debugLog("[PresetService]   -> setDisplayMode result: \(ok)")
                        anyActionTaken = true
                    }
                } else {
                    debugLog("[PresetService]   -> WARNING: no matching mode found for \(entry.width)×\(entry.height) hiDPI=\(entry.isHiDPI)")
                    debugLog("[PresetService]      available: \(display.availableModes.map { "\($0.width)×\($0.height)/\($0.isHiDPI)" }.joined(separator: ", "))")
                }
            }

            // Set brightness if specified (convert 0.0-1.0 to 0-100 range used by BrightnessService)
            if let brightness = entry.brightness, settings.isAuthoritative(.brightness) {
                debugLog("[PresetService]   -> setting brightness \(brightness)")
                await BrightnessService.shared.setBrightness(
                    brightness * 100.0,
                    for: display,
                    isAutoAdjust: false
                )
                anyActionTaken = true
            }

            // Restore the captured gamma/image adjustment (nil = preset from an
            // older version → leave gamma untouched).
            if let adj = entry.gammaAdjustment, settings.isAuthoritative(.imageAdjustment) {
                debugLog("[PresetService]   -> applying gamma adjustment (neutral=\(adj.isNeutral))")
                if adj.isNeutral {
                    GammaService.shared.clearSavedState(for: displayID)
                    GammaService.shared.resetSingleDisplay(displayID)
                } else {
                    GammaService.shared.apply(adj, for: displayID)
                    GammaService.shared.saveState(adj, for: displayID)
                }
                anyActionTaken = true
            }

            // Restore extra dimming below the hardware minimum (nil = older preset
            // or not applicable to this display → untouched).
            if let dim = entry.softwareDimming, settings.isAuthoritative(.brightness),
               BrightnessService.shared.supportsExtraDimming(display) {
                debugLog("[PresetService]   -> setting extra dimming \(dim)%")
                BrightnessService.shared.setExtraDimming(dim, for: displayID)
                anyActionTaken = true
            }

            // Restore arrangement only for presets that opted in (older presets have
            // nil → never), never for the built-in display (moving it onto (0,0)
            // makes it the main display and displaces every external). Skip no-op
            // moves: every display-configuration transaction dismisses the menu.
            if preset.restoresArrangement == true, !display.isBuiltin,
               SettingsService.shared.isAuthoritative(.arrangement),
               let x = entry.arrangementX, let y = entry.arrangementY,
               Int(x) != Int(display.bounds.origin.x) || Int(y) != Int(display.bounds.origin.y) {
                debugLog("[PresetService]   -> setting arrangement x=\(x) y=\(y)")
                let ok = await ArrangementService.shared.setPosition(
                    x: Int(x), y: Int(y), for: displayID
                )
                debugLog("[PresetService]   -> setPosition result: \(ok)")
                anyActionTaken = true
            }
        }

        // Displays the preset does not cover (attached after it was saved) still
        // get its generic, non-hardware-specific values — brightness, extra
        // dimming and image adjustment — from a template entry (the built-in's
        // if stored, else the first). Resolution/refresh rate and positions are
        // hardware-specific and stay untouched on such displays.
        let covered = Set(preset.displays.map(\.displayUUID))
        let template = preset.displays.first(where: { e in displays.first { $0.displayUUID == e.displayUUID }?.isBuiltin == true })
            ?? preset.displays.first
        if let template {
            for display in displays where display.isOnline && !covered.contains(display.displayUUID)
                && !VirtualDisplayService.shared.isVirtualDisplay(display.displayID) {
                let displayID = display.displayID
                debugLog("[PresetService] uncovered display '\(display.name)' → generic values from template")
                if let brightness = template.brightness, settings.isAuthoritative(.brightness) {
                    await BrightnessService.shared.setBrightness(brightness * 100.0, for: display, isAutoAdjust: false)
                    anyActionTaken = true
                }
                if let adj = template.gammaAdjustment, settings.isAuthoritative(.imageAdjustment) {
                    if adj.isNeutral {
                        GammaService.shared.clearSavedState(for: displayID)
                        GammaService.shared.resetSingleDisplay(displayID)
                    } else {
                        GammaService.shared.apply(adj, for: displayID)
                        GammaService.shared.saveState(adj, for: displayID)
                    }
                    anyActionTaken = true
                }
                if let dim = template.softwareDimming, settings.isAuthoritative(.brightness),
                   BrightnessService.shared.supportsExtraDimming(display) {
                    BrightnessService.shared.setExtraDimming(dim, for: displayID)
                    anyActionTaken = true
                }
            }
        }

        // Adaptive brightness would otherwise pull the brightness away again
        // seconds after the preset applied it — restore the state it was saved with.
        if let adaptive = preset.adaptiveBrightnessEnabled, settings.isAuthoritative(.brightness),
           AdaptiveBrightnessService.shared.isEnabled != adaptive {
            AdaptiveBrightnessService.shared.isEnabled = adaptive
        }

        // Restore app-level state captured with the preset (nil = older preset,
        // leave untouched). Level is set before the enabled flag so start()
        // never applies a stale boost.
        if let level = preset.xdrLevel, settings.isAuthoritative(.xdr) {
            XDRBrightnessService.shared.level = level
        }
        if let enabled = preset.xdrEnabled, settings.isAuthoritative(.xdr), XDRBrightnessService.shared.isEnabled != enabled {
            XDRBrightnessService.shared.isEnabled = enabled
        }
        if let increase = preset.increaseContrast, settings.isAuthoritative(.accessibilityContrast) {
            AccessibilityService.shared.increaseContrast = increase
        }
        if let contrast = preset.displayContrast, settings.isAuthoritative(.accessibilityContrast) {
            AccessibilityService.shared.displayContrast = contrast
        }

        debugLog("[PresetService] applyPreset '\(preset.name)' complete. anyActionTaken=\(anyActionTaken)")
    }

    // MARK: - Capture

    /// Snapshots all current online displays into a new preset.
    /// The built-in display IS captured (brightness + gamma) — without it a
    /// MacBook with no external display would save empty presets. Only its
    /// resolution is exempt from apply (see applyPreset).
    /// `includeArrangement` stores display positions for restore on apply — opt-in,
    /// because replaying positions captured under a different display setup
    /// scrambles the layout (and moving the built-in display changes the main screen).
    func captureCurrentState(name: String, icon: String, includeArrangement: Bool = false) -> DisplayPreset {
        let displays = DisplayManagerAccessor.shared.displays
        let entries: [DisplayPresetEntry] = displays.compactMap { display in
            guard display.isOnline else { return nil }
            let mode = display.currentDisplayMode
            return DisplayPresetEntry(
                displayUUID: display.displayUUID,
                width: mode?.width ?? display.pixelWidth,
                height: mode?.height ?? display.pixelHeight,
                isHiDPI: mode?.isHiDPI ?? false,
                brightness: display.brightness / 100.0,
                arrangementX: includeArrangement && !display.isBuiltin ? display.bounds.origin.x : nil,
                arrangementY: includeArrangement && !display.isBuiltin ? display.bounds.origin.y : nil,
                // Neutral (not nil) when no adjustment is saved, so applying the
                // preset restores the neutral state rather than leaving stale gamma.
                gammaAdjustment: GammaService.shared.loadSavedState(for: display.displayID) ?? GammaAdjustment(),
                softwareDimming: BrightnessService.shared.supportsExtraDimming(display)
                    ? BrightnessService.shared.extraDimming(for: display.displayID) : nil
            )
        }
        var preset = DisplayPreset(name: name, icon: icon, displays: entries)
        preset.restoresArrangement = includeArrangement
        preset.adaptiveBrightnessEnabled = AdaptiveBrightnessService.shared.isEnabled
        preset.xdrEnabled = XDRBrightnessService.shared.isEnabled
        preset.xdrLevel = XDRBrightnessService.shared.level
        preset.increaseContrast = AccessibilityService.shared.increaseContrast
        preset.displayContrast = AccessibilityService.shared.displayContrast
        return preset
    }

    /// The preset whose stored state matches the live state, preferring the one
    /// last applied. nil when nothing matches (then the last applied preset shows
    /// its Update button instead of the Current badge).
    func currentPresetMatch() -> UUID? {
        if let id = lastAppliedPresetID, let p = presets.first(where: { $0.id == id }), !isModified(p) {
            return id
        }
        return presets.first { !$0.isBuiltin && !$0.displays.isEmpty && !isModified($0) }?.id
    }

}
