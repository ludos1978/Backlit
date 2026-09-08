import Combine
import SwiftUI

/// Expandable image-adjustment section — 11 sliders for software gamma/image adjustments.
/// Mirrors BetterDisplay's Image Adjustment panel.
struct ImageAdjustmentView: View {
    @ObservedObject var display: DisplayInfo

    // MARK: - Local adjustment state (mirrors GammaAdjustment)
    @State private var contrast: Double = 0           // -100 … +100
    @State private var gammaVal: Double = 0           // -100 … +100
    @State private var gain: Double = 0               // -100 … +100
    @State private var blackPoint: Double = 0         // 0 … 100 (input black clip)
    @State private var midPoint: Double = 0           // -100 … +100 (midtone lift)
    @State private var whitePoint: Double = 0         // 0 … 100 (input white clip)
    @State private var colorTemperature: Double = 0   // -100 … +100
    @State private var quantLevels: Double = 256      // 2 … 256 (256 = ∞)
    @State private var rGamma: Double = 0
    @State private var gGamma: Double = 0
    @State private var bGamma: Double = 0
    @State private var rGain: Double = 0
    @State private var gGain: Double = 0
    @State private var bGain: Double = 0
    @State private var isInverted: Bool = false
    @State private var isPaused: Bool = false

    // MARK: - Brightness / extra dimming (same row style as the adjustments)
    @ObservedObject private var ddcService = DDCService.shared
    @State private var brightness: Double = 50        // 5 … 100 (hardware / DDC / software)
    @State private var extraDim: Double = 0           // 0 … 95 (software dimming below the floor)
    @State private var lastDDCWrite: Date = .distantPast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Brightness + Dim Below Minimum ─────────────────────────────
            AdjustRow(icon: "sun.max.fill", label: "Brightness", value: $brightness, accent: .orange,
                      range: 5...100, defaultValue: 50,
                      beginAction: captureBrightnessUndo,
                      commitAction: commitBrightness,
                      liveAction: liveBrightness)
                .help(brightnessHelp)
            if !display.isBuiltin, let warning = ddcService.mappingWarning {
                // DDC monitor-mapping warning (multi-display setups)
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption2)
                        .accessibilityHidden(true)
                    Text(warning)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            }
            if BrightnessService.shared.supportsExtraDimming(display) {
                AdjustRow(icon: "moon.zzz.fill", label: "Dim Below Min", value: $extraDim, accent: .indigo,
                          range: 0...95, defaultValue: 0,
                          beginAction: captureExtraDimUndo,
                          commitAction: commitExtraDim,
                          liveAction: { _ in commitExtraDim() })
                    .help("Software dimming below the hardware minimum (applied via the gamma ramp)")
            }

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 2)

            // ── Group 1: Global adjustments ────────────────────────────────
            adjustRow(icon: "circle.righthalf.filled",   label: "Contrast", value: $contrast).help("Adjust contrast")
            adjustRow(icon: "sparkle",                   label: "Gamma", value: $gammaVal).help("Adjust gamma")
            adjustRow(icon: "bolt.fill",                 label: "Gain", value: $gain).help("Adjust gain")
            adjustRow(icon: "thermometer.medium",        label: "Color Temp", value: $colorTemperature).help("Adjust color temperature")
            quantizationRow

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 2)

            // ── Levels: black point / midtone / white point ────────────────
            // Photoshop-style curve via LUT — the midtone moves independently
            // of the endpoints, which a plain gamma exponent cannot do.
            adjustRow(icon: "circle.fill",        label: "Black Point", value: $blackPoint, accent: .indigo, range: 0...100).help("Clip dark grays to black (raises perceived contrast)")
            adjustRow(icon: "circle.circle.fill", label: "Midtone",     value: $midPoint,   accent: .indigo).help("Lift or lower midtones independently of black/white point")
            adjustRow(icon: "circle",             label: "White Point", value: $whitePoint, accent: .indigo, range: 0...100).help("Compress highlights to white")

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 2)

            // ── Group 2: Per-channel gamma ─────────────────────────────────
            adjustRow(icon: "r.circle",      label: "Gamma R", value: $rGamma, accent: .red).help("Adjust red gamma")
            adjustRow(icon: "g.circle",      label: "Gamma G", value: $gGamma, accent: .green).help("Adjust green gamma")
            adjustRow(icon: "b.circle",      label: "Gamma B", value: $bGamma, accent: .blue).help("Adjust blue gamma")

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 2)

            // ── Group 3: Per-channel gain ──────────────────────────────────
            adjustRow(icon: "r.circle.fill", label: "Gain R", value: $rGain,  accent: .red).help("Adjust red gain")
            adjustRow(icon: "g.circle.fill", label: "Gain G", value: $gGain,  accent: .green).help("Adjust green gain")
            adjustRow(icon: "b.circle.fill", label: "Gain B", value: $bGain,  accent: .blue).help("Adjust blue gain")

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 2)

            // ── HDR warning ────────────────────────────────────────────────
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                Text("Adjustments may affect HDR content!")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            // ── Action buttons ─────────────────────────────────────────────
            HStack(spacing: 8) {
                actionButton(
                    title: "Invert Colors",
                    systemImage: "circle.lefthalf.filled",
                    isActive: isInverted
                ) {
                    captureUndoSnapshot()
                    isInverted.toggle()
                    commitAdjustment()
                }
                .help("Invert display colors (similar to a night mode)")

                actionButton(
                    title: isPaused ? "Resume" : "Pause",
                    systemImage: isPaused ? "play.circle" : "pause.circle",
                    isActive: isPaused
                ) {
                    captureUndoSnapshot()
                    isPaused.toggle()
                    if isPaused {
                        GammaService.shared.applyIdentity(for: display.displayID)
                    } else {
                        commitAdjustment()
                    }
                }
                .help("Temporarily disable color adjustments and restore the original output")

                actionButton(
                    title: "Reset All",
                    systemImage: "arrow.counterclockwise",
                    isActive: false
                ) {
                    resetAll()
                }
                .help("Reset all color adjustments to their defaults")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .onAppear {
            reloadFromSaved(reapply: true)
            brightness = display.brightness
            extraDim = BrightnessService.shared.extraDimming(for: display.displayID)
        }
        .onChange(of: display.brightness) { _, newValue in
            if abs(newValue - brightness) >= 1 { brightness = newValue }
        }
        .onReceive(UndoService.shared.$undoTick) { _ in
            extraDim = BrightnessService.shared.extraDimming(for: display.displayID)
        }
        .task(id: display.displayID) {
            // Built-in brightness changes outside the app (brightness keys pass
            // through to macOS, Control Center) — poll while visible so the slider follows.
            guard display.isBuiltin else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await BrightnessService.shared.refreshBrightness(for: display)
            }
        }
        .onReceive(GammaService.stateDidChange) { changedID in
            // Another control (combined gamma slider, undo, …) edited this
            // display's adjustment — re-sync the local slider state.
            guard changedID == display.displayID else { return }
            reloadFromSaved(reapply: false)
        }
        .onDisappear {
            let isAtZero = contrast == 0 && gammaVal == 0 && gain == 0 &&
                blackPoint == 0 && midPoint == 0 && whitePoint == 0 &&
                colorTemperature == 0 && rGamma == 0 && gGamma == 0 && bGamma == 0 &&
                rGain == 0 && gGain == 0 && bGain == 0 && !isInverted &&
                quantLevels == 256
            if isAtZero {
                GammaService.shared.clearSavedState(for: display.displayID)
                GammaService.shared.resetSingleDisplay(display.displayID)
            } else {
                let adj = GammaAdjustment(
                    contrast: contrast, gammaVal: gammaVal, gain: gain,
                    blackPoint: blackPoint, midPoint: midPoint, whitePoint: whitePoint,
                    colorTemperature: colorTemperature,
                    rGamma: rGamma, gGamma: gGamma, bGamma: bGamma,
                    rGain: rGain, gGain: gGain, bGain: bGain,
                    quantizationLevels: Int(quantLevels),
                    isInverted: isInverted, isPaused: isPaused
                )
                GammaService.shared.saveState(adj, for: display.displayID)
            }
        }
    }

    // MARK: - Brightness / extra dimming helpers

    private var brightnessHelp: String {
        if display.isBuiltin { return "Brightness (system backlight)" }
        switch BrightnessService.shared.isDDCAvailable(for: display.displayID) {
        case true: return "Brightness (DDC hardware control)"
        case false: return "Brightness (software, via the gamma ramp)"
        default: return "Brightness"
        }
    }

    private func captureBrightnessUndo() {
        let displayID = display.displayID
        let previous = display.brightness
        UndoService.shared.push {
            Task { @MainActor in
                guard let d = DisplayManagerAccessor.shared.displays.first(where: { $0.displayID == displayID }) else { return }
                d.brightness = previous
                await BrightnessService.shared.setBrightness(previous, for: d)
            }
        }
    }

    /// Live drag: apply immediately; throttle DDC writes to ~100 ms so the I2C bus is not flooded.
    private func liveBrightness(_ value: Double) {
        let isDDC = BrightnessService.shared.isDDCAvailable(for: display.displayID) == true
        let now = Date()
        display.brightness = value
        if isDDC && now.timeIntervalSince(lastDDCWrite) < 0.1 { return }
        lastDDCWrite = now
        Task { @MainActor in await BrightnessService.shared.setBrightness(value, for: display) }
    }

    private func commitBrightness() {
        display.brightness = brightness
        BrightnessService.shared.setBrightnessSmooth(brightness, for: display)
        lastDDCWrite = Date()
    }

    private func captureExtraDimUndo() {
        let displayID = display.displayID
        let previous = BrightnessService.shared.extraDimming(for: displayID)
        UndoService.shared.push { BrightnessService.shared.setExtraDimming(previous, for: displayID) }
    }

    private func commitExtraDim() {
        BrightnessService.shared.setExtraDimming(extraDim, for: display.displayID)
    }

    // MARK: - Slider row builder

    private func adjustRow(
        icon: String,
        label: String,
        value: Binding<Double>,
        accent: Color = .blue,
        range: ClosedRange<Double> = -100...100
    ) -> some View {
        AdjustRow(icon: icon, label: label, value: value, accent: accent, range: range,
                  beginAction: captureUndoSnapshot, commitAction: commitAdjustment)
    }

    /// Syncs the local slider state from the persisted adjustment (or defaults
    /// when none is saved). With `reapply` the adjustment is also written to the
    /// display so it visually matches the sliders.
    private func reloadFromSaved(reapply: Bool) {
        let saved = GammaService.shared.loadSavedState(for: display.displayID) ?? GammaAdjustment()
        contrast = saved.contrast
        gammaVal = saved.gammaVal
        gain = saved.gain
        blackPoint = saved.blackPoint
        midPoint = saved.midPoint
        whitePoint = saved.whitePoint
        colorTemperature = saved.colorTemperature
        rGamma = saved.rGamma; gGamma = saved.gGamma; bGamma = saved.bGamma
        rGain = saved.rGain;   gGain = saved.gGain;   bGain = saved.bGain
        quantLevels = Double(saved.quantizationLevels)
        isInverted = saved.isInverted
        isPaused = saved.isPaused
        if reapply && !saved.isNeutral && !saved.isPaused {
            GammaService.shared.apply(saved, for: display.displayID)
        }
    }

    /// Pushes the display's current persisted adjustment onto the undo stack.
    /// Called when an edit gesture begins, before any value changes.
    private func captureUndoSnapshot() {
        let displayID = display.displayID
        let previous = GammaService.shared.loadSavedState(for: displayID)
        UndoService.shared.push {
            if let previous {
                GammaService.shared.apply(previous, for: displayID)
                GammaService.shared.saveState(previous, for: displayID)
            } else {
                GammaService.shared.clearSavedState(for: displayID)
                GammaService.shared.resetSingleDisplay(displayID)
            }
        }
    }

    // MARK: - Quantization row

    private var quantizationRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.fill")
                .foregroundColor(.blue)
                .frame(width: 18)
                .font(.caption)

            Text("Quantize")
                .font(.caption)
                .frame(width: 72, alignment: .leading)

            Slider(value: $quantLevels, in: 2...256, step: 1) { editing in
                if editing {
                    captureUndoSnapshot()
                } else {
                    commitAdjustment()
                }
            }
            .help("Adjust quantization levels")

            Text(quantLevels >= 255 ? "∞" : "\(Int(quantLevels))")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 38, alignment: .trailing)
                .monospacedDigit()

            ResetButton(visible: quantLevels != 256) {
                captureUndoSnapshot()
                quantLevels = 256
                commitAdjustment()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    // MARK: - Action button builder

    private func actionButton(
        title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.08))
            .foregroundColor(isActive ? .blue : .primary)
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func commitAdjustment() {
        guard !isPaused else { return }
        let adj = GammaAdjustment(
            contrast: contrast,
            gammaVal: gammaVal,
            gain: gain,
            blackPoint: blackPoint,
            midPoint: midPoint,
            whitePoint: whitePoint,
            colorTemperature: colorTemperature,
            rGamma: rGamma, gGamma: gGamma, bGamma: bGamma,
            rGain: rGain,   gGain: gGain,   bGain: bGain,
            quantizationLevels: Int(quantLevels),
            isInverted: isInverted,
            isPaused: false
        )
        // Persist immediately so other controls editing the same state (combined
        // gamma slider, undo) always see the current values.
        if adj.isNeutral {
            GammaService.shared.clearSavedState(for: display.displayID)
            GammaService.shared.resetSingleDisplay(display.displayID)
        } else {
            GammaService.shared.apply(adj, for: display.displayID)
            GammaService.shared.saveState(adj, for: display.displayID)
        }
    }

    @MainActor
    private func resetAll() {
        captureUndoSnapshot()
        contrast = 0; gammaVal = 0; gain = 0; colorTemperature = 0
        blackPoint = 0; midPoint = 0; whitePoint = 0
        rGamma = 0; gGamma = 0; bGamma = 0
        rGain = 0;  gGain = 0;  bGain = 0
        quantLevels = 256
        isInverted = false
        isPaused = false
        GammaService.shared.clearSavedState(for: display.displayID)
        // Explicit user-initiated reset: also restore the factory ICC profile.
        GammaService.shared.resetSingleDisplay(display.displayID, restoreFactoryProfile: true)
    }
}

private struct AdjustRow: View {
    let icon: String
    let label: String
    @Binding var value: Double
    let accent: Color
    var range: ClosedRange<Double> = -100...100
    var defaultValue: Double = 0
    let beginAction: () -> Void
    let commitAction: () -> Void
    /// Called with every value change during a drag (for controls that should follow live).
    var liveAction: ((Double) -> Void)? = nil

    @State private var highlighted: Bool = false
    @State private var isDragging: Bool = false

    private func percentLabel(_ v: Double) -> String {
        // Only show a "+" sign for bipolar ranges where 0 is the neutral midpoint.
        let sign = (v > 0 && range.lowerBound < 0) ? "+" : ""
        return "\(sign)\(Int(v))%"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(accent)
                .frame(width: 18)
                .font(.caption)

            Text(label)
                .font(.caption)
                .frame(width: 80, alignment: .leading)

            Slider(value: $value, in: range, step: 1) { editing in
                isDragging = editing
                if editing {
                    beginAction()
                } else {
                    commitAction()
                    withAnimation(.easeOut(duration: 0.3)) { highlighted = true }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        withAnimation(.easeOut(duration: 0.3)) { highlighted = false }
                    }
                }
            }
            .tint(accent)
            .onChange(of: value) { _, newValue in
                guard isDragging else { return }
                liveAction?(newValue)
            }

            Text(percentLabel(value))
                .font(.caption)
                .foregroundColor(highlighted ? accent : .secondary)
                .frame(width: 38, alignment: .trailing)
                .monospacedDigit()
                .contentTransition(.numericText())

            ResetButton(visible: value != defaultValue) {
                beginAction()
                value = defaultValue
                commitAction()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}
