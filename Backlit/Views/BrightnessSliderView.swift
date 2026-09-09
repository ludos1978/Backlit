import Combine
import CoreGraphics
import SwiftUI

struct CombinedBrightnessView: View {
    let displays: [DisplayInfo]
    @State private var combinedBrightness: Double = 50
    @State private var isDragging: Bool = false
    /// Throttle DDC writes during drag to ~100ms intervals.
    @State private var lastDDCWrite: Date = .distantPast

    private var averageBrightness: Double {
        guard !displays.isEmpty else { return 50 }
        return displays.map(\.brightness).reduce(0, +) / Double(displays.count)
    }

    /// True if any display in the group uses DDC (so we apply throttle).
    private var anyDDC: Bool {
        displays.contains { BrightnessService.shared.isDDCAvailable(for: $0.displayID) == true }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "sun.max.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                    .accessibilityHidden(true)
                Text("Brightness (All Displays)")
                    .font(.body)
                Spacer()
                Text("\(Int(combinedBrightness))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                ResetButton(visible: Int(combinedBrightness) != 50) {
                    captureUndoSnapshot()
                    combinedBrightness = 50
                    Task { @MainActor in
                        for display in displays {
                            BrightnessService.shared.setBrightnessSmooth(50, for: display)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "sun.min")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 14)
                    .accessibilityHidden(true)

                Slider(value: $combinedBrightness, in: 5...100, step: 1) { editing in
                    isDragging = editing
                    if editing {
                        captureUndoSnapshot()
                    }
                    if !editing {
                        // Drag ended — flush final value to all displays with smooth transition.
                        Task { @MainActor in
                            for display in displays {
                                BrightnessService.shared.setBrightnessSmooth(combinedBrightness, for: display)
                            }
                        }
                        lastDDCWrite = Date()
                    }
                }
                .accessibilityLabel("Combined brightness")
                .accessibilityValue("\(Int(combinedBrightness))%")
                .onChange(of: combinedBrightness) { _, newValue in
                    guard isDragging else { return }
                    let now = Date()
                    if anyDDC && now.timeIntervalSince(lastDDCWrite) < 0.1 {
                        // Throttle DDC — update model only; drag-end flushes final value.
                        for display in displays { display.brightness = newValue }
                        return
                    }
                    lastDDCWrite = now
                    Task { @MainActor in
                        for display in displays {
                            display.brightness = newValue
                            await BrightnessService.shared.setBrightness(newValue, for: display)
                        }
                    }
                }

                Image(systemName: "sun.max")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 14)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onAppear {
            combinedBrightness = averageBrightness
        }
        .onReceive(UndoService.shared.$undoTick) { _ in
            guard !isDragging else { return }
            combinedBrightness = averageBrightness
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            // Follow external brightness changes (keys, Control Center) live.
            guard !isDragging else { return }
            // Built-in brightness changes happen outside the app — re-read it so
            // the average tracks reality even when no display row is expanded.
            for display in displays where display.isBuiltin {
                Task { await BrightnessService.shared.refreshBrightness(for: display) }
            }
            if abs(combinedBrightness - averageBrightness) >= 1 {
                combinedBrightness = averageBrightness
            }
        }
    }

    /// Pushes every display's current brightness onto the undo stack (⌘Z).
    private func captureUndoSnapshot() {
        let snapshots = displays.map { ($0.displayID, $0.brightness) }
        UndoService.shared.push {
            Task { @MainActor in
                for (id, previous) in snapshots {
                    guard let d = DisplayManagerAccessor.shared.displays.first(where: { $0.displayID == id }) else { continue }
                    d.brightness = previous
                    await BrightnessService.shared.setBrightness(previous, for: d)
                }
            }
        }
    }
}

// MARK: - CombinedGammaView

/// Global gamma slider: brightens or darkens the midtones of all displays at once
/// (0 = neutral, + = brighter, − = darker). Applied per display via GammaService
/// so it persists and is re-applied after sleep/wake.
struct CombinedGammaView: View {
    let displays: [DisplayInfo]
    @State private var gammaValue: Double = 0
    @State private var isDragging: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundColor(.purple)
                    .font(.caption)
                    .accessibilityHidden(true)
                Text("Gamma (All Displays)")
                    .font(.body)
                Spacer()
                Text("\(gammaValue > 0 ? "+" : "")\(Int(gammaValue))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                ResetButton(visible: gammaValue != 0) {
                    captureUndoSnapshot()
                    gammaValue = 0
                    apply()
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "moon")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 14)
                    .accessibilityHidden(true)

                Slider(value: $gammaValue, in: -100...100, step: 1) { editing in
                    isDragging = editing
                    if editing {
                        captureUndoSnapshot()
                    } else {
                        apply()
                    }
                }
                .accessibilityLabel("Combined gamma")
                .accessibilityValue("\(Int(gammaValue))")
                .help("Brighten or darken midtones on all displays")
                .onChange(of: gammaValue) { _, _ in
                    guard isDragging else { return }
                    apply()
                }

                Image(systemName: "sun.max")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 14)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onAppear { load() }
        .onReceive(GammaService.stateDidChange) { _ in
            // Re-sync when another control (per-display panel, undo) edits gamma.
            guard !isDragging else { return }
            load()
        }
    }

    /// Pushes every display's current saved adjustment onto the undo stack (⌘Z).
    private func captureUndoSnapshot() {
        let snapshots = displays.map { ($0.displayID, GammaService.shared.loadSavedState(for: $0.displayID)) }
        UndoService.shared.push {
            for (id, previous) in snapshots {
                if let previous {
                    GammaService.shared.apply(previous, for: id)
                    GammaService.shared.saveState(previous, for: id)
                } else {
                    GammaService.shared.clearSavedState(for: id)
                    GammaService.shared.resetSingleDisplay(id)
                }
            }
        }
    }

    /// Initializes the slider from the average of the saved per-display gamma values.
    private func load() {
        let values = displays.map {
            GammaService.shared.loadSavedState(for: $0.displayID)?.gammaVal ?? 0
        }
        gammaValue = values.isEmpty ? 0 : (values.reduce(0, +) / Double(values.count)).rounded()
    }

    private func apply() {
        for display in displays {
            var adj = GammaService.shared.loadSavedState(for: display.displayID) ?? GammaAdjustment()
            // Never silently resume a display whose adjustments the user paused.
            guard !adj.isPaused else { continue }
            adj.gammaVal = gammaValue
            if adj.isNeutral {
                GammaService.shared.clearSavedState(for: display.displayID)
                GammaService.shared.resetSingleDisplay(display.displayID)
            } else {
                GammaService.shared.apply(adj, for: display.displayID)
                GammaService.shared.saveState(adj, for: display.displayID)
            }
        }
    }
}

// MARK: - ExtraDimmingRow

/// "Dim Below Minimum": extra software dimming (gamma-ramp scale) applied on top
/// of hardware brightness, for panels whose backlight floor is still too bright.
/// Shown for the built-in panel and DDC displays; DDC-less externals are already
/// software-dimmed by their brightness slider, so the row hides itself for them.
/// Reuses BrightnessService's software-brightness factor: persisted per display,
/// re-applied on wake, composed with image adjustments and the XDR boost.
struct ExtraDimmingRow: View {
    let displays: [DisplayInfo]
    var title: String = "Dim Below Minimum"
    @State private var dimming: Double = 0
    @State private var isDragging: Bool = false

    private var eligible: [DisplayInfo] {
        displays.filter { BrightnessService.shared.supportsExtraDimming($0) }
    }

    var body: some View {
        if !eligible.isEmpty {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "moon.zzz.fill")
                    .foregroundColor(dimming > 0 ? .indigo : .secondary)
                    .font(.caption)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body)
                Spacer()
                Text(dimming > 0 ? "\u{2212}\(Int(dimming))%" : "Off")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                ResetButton(visible: dimming > 0) {
                    captureUndoSnapshot()
                    dimming = 0
                    apply()
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "sun.min")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 14)
                    .accessibilityHidden(true)

                Slider(value: $dimming, in: 0...95, step: 1) { editing in
                    isDragging = editing
                    if editing {
                        captureUndoSnapshot()
                    } else {
                        apply()
                    }
                }
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(dimming))%")
                .help("Software dimming below the hardware minimum (applied via the gamma ramp)")
                .onChange(of: dimming) { _, _ in
                    guard isDragging else { return }
                    apply()
                }

                Image(systemName: "moon.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 14)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onAppear { load() }
        .onReceive(UndoService.shared.$undoTick) { _ in
            guard !isDragging else { return }
            load()
        }
    }

    private func load() {
        let values = eligible.map { BrightnessService.shared.extraDimming(for: $0.displayID) }
        dimming = values.isEmpty ? 0 : (values.reduce(0, +) / Double(values.count)).rounded()
    }

    private func apply() {
        for display in eligible {
            BrightnessService.shared.setExtraDimming(dimming, for: display.displayID)
        }
    }

    /// Pushes every eligible display's current extra dimming onto the undo stack (⌘Z).
    private func captureUndoSnapshot() {
        let snapshots = eligible.map { ($0.displayID, BrightnessService.shared.extraDimming(for: $0.displayID)) }
        UndoService.shared.push {
            for (id, previous) in snapshots {
                BrightnessService.shared.setExtraDimming(previous, for: id)
            }
        }
    }
}
