import SwiftUI

/// Adaptive brightness: screen-content and/or ambient-light driven, learning
/// from manual adjustments. All options in one place.
struct AdaptiveBrightnessView: View {
    @ObservedObject private var service = AdaptiveBrightnessService.shared
    @ObservedObject private var ambient = AmbientLightService.shared
    @EnvironmentObject var displayManager: DisplayManager
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Master toggle
            HStack {
                MenuItemIcon(systemName: "sun.and.horizon.fill", color: service.isEnabled ? .orange : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Adaptive Brightness").font(.body)
                    Text(statusText).font(.caption2).foregroundColor(.secondary).lineLimit(2)
                }
                Spacer()
                Toggle("", isOn: $service.isEnabled).toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.primary.opacity(isHovered ? 0.06 : 0))
            .onHover { isHovered = $0 }
            .contentShape(Rectangle())
            .help("Adjusts brightness from what is on screen and/or the ambient light sensor, learning from your manual changes")

            if service.isEnabled {
                // Input mode
                Picker("", selection: $service.mode) {
                    ForEach(AdaptiveMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small)
                .padding(.horizontal, 12)
                .help("Screen content: dark content → brighter, bright content → dimmer. Ambient light: brighter room → brighter screen. Follow built-in: external displays mirror the built-in panel.")

                // Hints
                if service.mode.usesContent, let err = service.contentError {
                    hint(err, color: .red, systemImage: "exclamationmark.triangle.fill") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                    }
                }
                if service.mode.usesAmbient && !ambient.isAvailable {
                    hint("No ambient light sensor reading available on this Mac.", color: .orange, systemImage: "sensor")
                }
                if service.systemAutoBrightnessOn {
                    hint("macOS's own “Automatically adjust brightness” is on and will fight this — turn it off in Displays settings.", color: .orange, systemImage: "exclamationmark.triangle.fill") {
                        PreferenceArea.openOSPanel(.brightness)
                    }
                }
                if service.isPausedForApp, let name = service.frontmostName {
                    hint("Paused while \(name) is in front (ignore list).", color: .secondary, systemImage: "pause.circle")
                }

                // Live readout
                HStack(spacing: 10) {
                    if service.mode.usesAmbient {
                        Label(ambient.lux.map { "\(Int($0)) lux" } ?? "– lux", systemImage: "light.max")
                    }
                    if service.mode.usesContent {
                        ForEach(displayManager.displays.filter { !service.disabledDisplayUUIDs.contains($0.displayUUID) }) { d in
                            Label("\(Int((service.lightness[d.displayUUID] ?? 0.5) * 100))% \(shortName(d))", systemImage: "rectangle.on.rectangle")
                        }
                    }
                    Spacer()
                }
                .font(.caption2).foregroundColor(.secondary)
                .padding(.horizontal, 12)

                Divider().padding(.horizontal, 12).padding(.vertical, 2)

                // Value options — same row style as the image adjustments
                optionRow("Sensitivity", icon: "dial.medium", value: $service.sensitivity, range: 0.5...1.5, step: 0.05, defaultValue: 1.0, format: { "\(Int($0 * 100))%" },
                          help: "Multiplier on the learned brightness")
                optionRow("Minimum", icon: "sun.min", value: $service.minBrightness, range: 0...100, step: 1, defaultValue: 25, format: { "\(Int($0))%" },
                          help: "Never go below this brightness")
                optionRow("Maximum", icon: "sun.max", value: $service.maxBrightness, range: 0...100, step: 1, defaultValue: 100, format: { "\(Int($0))%" },
                          help: "Never go above this brightness")

                HStack(spacing: 8) {
                    Text("Response").font(.body).frame(width: 104, alignment: .leading)
                    Picker("", selection: $service.speed) { ForEach(ResponseSpeed.allCases) { Text($0.title).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden().controlSize(.small)
                }
                .padding(.horizontal, 12).padding(.vertical, 3)
                .help("How quickly brightness follows changes")

                if service.mode.usesContent {
                    HStack(spacing: 8) {
                        Text("Sampling").font(.body).frame(width: 104, alignment: .leading)
                        Picker("", selection: $service.captureFPS) { ForEach([2, 4, 8], id: \.self) { Text("\($0) fps").tag($0) } }
                            .labelsHidden().controlSize(.small).frame(width: 90)
                        Picker("", selection: $service.metric) { ForEach(LightnessMetric.allCases) { Text($0.title).tag($0) } }
                            .labelsHidden().controlSize(.small)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 3)
                    .help("Capture rate and how a frame's lightness is measured")
                }

                Toggle(isOn: $service.learningEnabled) {
                    Text("Learn from my adjustments").font(.body)
                }
                .toggleStyle(.switch).controlSize(.small)
                .padding(.horizontal, 12).padding(.vertical, 2)
                .help("Manual brightness changes teach the curve for the current content/light")

                // Per-display enable
                if displayManager.displays.count > 1 {
                    ForEach(displayManager.displays) { d in
                        Toggle(isOn: Binding(
                            get: { !service.disabledDisplayUUIDs.contains(d.displayUUID) },
                            set: { on in
                                if on { service.disabledDisplayUUIDs.remove(d.displayUUID) } else { service.disabledDisplayUUIDs.insert(d.displayUUID) }
                                service.rebuildSamplers()
                            }
                        )) {
                            Text(d.name).font(.body).lineLimit(1)
                        }
                        .toggleStyle(.switch).controlSize(.small)
                        .padding(.horizontal, 12).padding(.vertical, 1)
                    }
                }

                Divider().padding(.horizontal, 12).padding(.vertical, 2)

                // Ignore list
                HStack {
                    Text("Ignored apps").font(.body)
                    Spacer()
                    if let name = service.frontmostName, let id = service.frontmostBundleID, !service.ignoredApps.contains(id) {
                        Button("Ignore \(name)") { service.ignoreFrontmostApp() }
                            .controlSize(.mini)
                            .help("Pause adaptive brightness while this app is in front; its brightness is remembered separately")
                    }
                }
                .padding(.horizontal, 12)
                ForEach(service.ignoredApps, id: \.self) { id in
                    HStack(spacing: 6) {
                        Image(systemName: "app.dashed").font(.caption).foregroundColor(.secondary)
                        Text(service.appName(for: id)).font(.body).lineLimit(1)
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
                    .padding(.horizontal, 12).padding(.vertical, 2)
                }

                Divider().padding(.horizontal, 12).padding(.vertical, 2)

                HStack {
                    Button("Reset learned curves") { service.resetCurve() }
                        .controlSize(.mini)
                        .help("Forget everything learned from manual adjustments (all displays)")
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.bottom, 6)
            }
        }
    }

    private var statusText: String {
        guard service.isEnabled else { return "Screen content · ambient light sensor · learns from you" }
        if service.isPausedForApp, let n = service.frontmostName { return "Paused for \(n)" }
        var parts: [String] = []
        if service.mode.usesAmbient { parts.append(ambient.lux.map { "\(Int($0)) lux" } ?? "no sensor") }
        if let t = service.target.values.first { parts.append("→ \(Int(t))%") }
        return parts.isEmpty ? service.mode.title : parts.joined(separator: " ")
    }

    private func shortName(_ d: DisplayInfo) -> String {
        d.isBuiltin ? "built-in" : String(d.name.prefix(10))
    }

    @ViewBuilder
    private func hint(_ text: String, color: Color, systemImage: String, action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: systemImage).font(.caption2).foregroundColor(color).accessibilityHidden(true)
            Text(text).font(.caption2).foregroundColor(color == .secondary ? .secondary : color).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { action?() }
    }

    @ViewBuilder
    private func optionRow(_ label: String, icon: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                           defaultValue: Double, format: @escaping (Double) -> String, help: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(.orange).frame(width: 18).font(.caption).accessibilityHidden(true)
            Text(label).font(.body).lineLimit(1).frame(width: 104, alignment: .leading)
            Slider(value: value, in: range, step: step) { editing in
                if editing {
                    let previous = value.wrappedValue
                    UndoService.shared.push { value.wrappedValue = previous }
                }
            }
            Text(format(value.wrappedValue)).font(.caption).foregroundColor(.secondary).frame(width: 38, alignment: .trailing).monospacedDigit()
            ResetButton(visible: value.wrappedValue != defaultValue) {
                let previous = value.wrappedValue
                UndoService.shared.push { value.wrappedValue = previous }
                value.wrappedValue = defaultValue
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 3)
        .help(help)
    }
}
