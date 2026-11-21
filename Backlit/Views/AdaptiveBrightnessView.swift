import SwiftUI

/// Adaptive brightness: screen-content and/or ambient-light driven, learning
/// from manual adjustments. Shown under the "Adaptive Brightness" row in Options.
struct AdaptiveBrightnessView: View {
    @ObservedObject private var service = AdaptiveBrightnessService.shared
    @EnvironmentObject var displayManager: DisplayManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToggleSettingRow(icon: "power", label: "Enabled", isOn: $service.isEnabled, accent: .orange,
                             help: "Adjusts brightness from what is on screen and/or the ambient light sensor, learning from your manual changes")

            if service.isEnabled {
                AdaptiveStatusSection()
                AdaptiveRangeSection()
                AdaptiveBehaviourSection()
                AdaptiveDisplaysSection()
                AdaptiveIgnoredAppsSection()

                Button("Reset Learned Curves") { service.resetCurve() }
                    .controlSize(.mini)
                    .help("Forget everything learned from manual adjustments (all displays)")
                    .padding(.horizontal, SettingRowMetrics.horizontalPadding)
                    .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - Source, live readout and warnings

private struct AdaptiveStatusSection: View {
    @ObservedObject private var service = AdaptiveBrightnessService.shared
    @ObservedObject private var ambient = AmbientLightService.shared
    @EnvironmentObject var displayManager: DisplayManager

    var body: some View {
        PickerSettingRow(icon: "dot.radiowaves.left.and.right", label: "Source", selection: $service.mode,
                         options: AdaptiveMode.allCases, title: \.title, accent: .orange, segmented: false,
                         help: "Screen content: dark content → brighter, bright content → dimmer. Ambient light: brighter room → brighter screen. Follow built-in: external displays follow the built-in panel.")

        HintRow(text: readout, systemImage: "waveform.path.ecg")

        if service.mode.usesContent, let err = service.contentError {
            HintRow(text: err, systemImage: "exclamationmark.triangle.fill", color: .red) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
        }
        if service.mode.usesAmbient && !ambient.isAvailable {
            HintRow(text: "No ambient light sensor reading available on this Mac.", systemImage: "sensor", color: .orange)
        }
        if service.systemAutoBrightnessOn {
            HintRow(text: "macOS's own “Automatically adjust brightness” is on and will fight this — turn it off in Displays settings.",
                    systemImage: "exclamationmark.triangle.fill", color: .orange) {
                PreferenceArea.openOSPanel(.brightness)
            }
        }
    }

    /// e.g. "320 lux · DELL U3225QE 42 % → 61 %"
    private var readout: String {
        if service.isPausedForApp, let name = service.frontmostName { return "Paused while \(name) is in front" }
        var parts: [String] = []
        if service.mode.usesAmbient { parts.append(ambient.lux.map { "\(Int($0)) lux" } ?? "no sensor") }
        for d in displayManager.displays where !service.disabledDisplayUUIDs.contains(d.displayUUID) {
            var item = d.isBuiltin ? "Built-in" : d.name
            if service.mode.usesContent, let l = service.lightness[d.displayUUID] { item += " \(Int(l * 100)) %" }
            if let t = service.target[d.displayUUID] { item += " → \(Int(t)) %" }
            parts.append(item)
        }
        return parts.isEmpty ? service.mode.title : parts.joined(separator: " · ")
    }
}

// MARK: - Brightness range

private struct AdaptiveRangeSection: View {
    @ObservedObject private var service = AdaptiveBrightnessService.shared

    var body: some View {
        SettingGroupHeader(title: "Brightness")
        slider("Sensitivity", icon: "dial.medium", value: $service.sensitivity, range: 0.5...1.5, step: 0.05, defaultValue: 1.0,
               format: { "\(Int($0 * 100))%" }, help: "Multiplier on the learned brightness")
        slider("Minimum", icon: "sun.min", value: $service.minBrightness, range: 0...100, step: 1, defaultValue: 25,
               format: { "\(Int($0))%" }, help: "Never go below this brightness")
        slider("Maximum", icon: "sun.max", value: $service.maxBrightness, range: 0...100, step: 1, defaultValue: 100,
               format: { "\(Int($0))%" }, help: "Never go above this brightness")
    }

    private func slider(_ label: String, icon: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                        defaultValue: Double, format: @escaping (Double) -> String, help: String) -> SliderSettingRow {
        SliderSettingRow(icon: icon, label: label, value: value, accent: .orange, range: range, step: step,
                         defaultValue: defaultValue, format: format, help: help,
                         onBegin: {
                             let previous = value.wrappedValue
                             UndoService.shared.push { value.wrappedValue = previous }
                         })
    }
}

// MARK: - Response, sampling, learning

private struct AdaptiveBehaviourSection: View {
    @ObservedObject private var service = AdaptiveBrightnessService.shared

    var body: some View {
        SettingGroupHeader(title: "Behaviour")
        PickerSettingRow(icon: "speedometer", label: "Response", selection: $service.speed,
                         options: ResponseSpeed.allCases, title: \.title, accent: .orange,
                         help: "How quickly brightness follows a change (0.12 s / 0.4 s / 1.5 s)")
        if service.mode.usesContent {
            PickerSettingRow(icon: "camera.metering.center.weighted", label: "Sampling", selection: $service.captureFPS,
                             options: AdaptiveBrightnessService.fpsOptions, title: { "\($0) fps" }, accent: .orange,
                             help: "How often the screen is checked. Higher reacts sooner but costs WindowServer more CPU.")
            PickerSettingRow(icon: "chart.bar.xaxis", label: "Measure", selection: $service.metric,
                             options: LightnessMetric.allCases, title: \.title, accent: .orange, segmented: false,
                             help: "How a frame's lightness is measured")
        }
        ToggleSettingRow(icon: "graduationcap", label: "Learn", isOn: $service.learningEnabled, accent: .orange,
                         help: "Manual brightness changes teach the curve for the current content and light")
    }
}

// MARK: - Per-display enable

private struct AdaptiveDisplaysSection: View {
    @ObservedObject private var service = AdaptiveBrightnessService.shared
    @EnvironmentObject var displayManager: DisplayManager

    var body: some View {
        if displayManager.displays.count > 1 {
            SettingGroupHeader(title: "Displays")
            ForEach(displayManager.displays) { d in
                ToggleSettingRow(icon: d.isBuiltin ? "laptopcomputer" : "display",
                                 label: d.isBuiltin ? "Built-in" : d.name,
                                 isOn: Binding(
                                    get: { !service.disabledDisplayUUIDs.contains(d.displayUUID) },
                                    set: { service.setDisplay(d, enabled: $0) }),
                                 accent: .orange)
            }
        }
    }
}

// MARK: - Ignore list

private struct AdaptiveIgnoredAppsSection: View {
    @ObservedObject private var service = AdaptiveBrightnessService.shared

    var body: some View {
        SettingGroupHeader(title: "Ignored Apps")
        ForEach(service.ignoredApps, id: \.self) { id in
            HStack(spacing: 8) {
                SettingRowLabel(icon: "app.dashed", label: service.appName(for: id), accent: .secondary)
                Spacer()
                if let b = service.appBrightness[id] {
                    Text("\(Int(b))%").font(.caption).foregroundColor(.secondary).monospacedDigit()
                }
                Button { service.unignore(id) } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove from the ignore list")
            }
            .padding(.horizontal, SettingRowMetrics.horizontalPadding)
            .padding(.vertical, SettingRowMetrics.verticalPadding)
        }
        if let name = service.frontmostName, let id = service.frontmostBundleID, !service.ignoredApps.contains(id) {
            Button("Ignore \(name)") { service.ignoreFrontmostApp() }
                .controlSize(.mini)
                .help("Pause adaptive brightness while this app is in front; its brightness is remembered separately")
                .padding(.horizontal, SettingRowMetrics.horizontalPadding)
                .padding(.vertical, 2)
        } else if service.ignoredApps.isEmpty {
            HintRow(text: "Apps listed here pause adaptive brightness while in front.")
        }
    }
}
