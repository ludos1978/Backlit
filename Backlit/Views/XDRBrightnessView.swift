import SwiftUI

/// XDR brightness section — drives Apple XDR panels beyond their SDR brightness
/// limit for normal content (EDR trigger overlay + gamma boost via GammaService).
struct XDRBrightnessView: View {
    @ObservedObject private var service = XDRBrightnessService.shared
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Main toggle
            HStack {
                MenuItemIcon(systemName: "sun.max.circle.fill", color: service.isEnabled ? .yellow : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("XDR Brightness")
                        .font(.body)
                    Text(statusText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { service.isEnabled },
                    set: { newValue in
                        service.pushUndoSnapshot()
                        service.isEnabled = newValue
                    }
                ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(isHovered ? 0.06 : 0))
            .onHover { isHovered = $0 }
            .contentShape(Rectangle())
            .help("Unlock the panel's full XDR brightness for normal (SDR) content")

            if service.isEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "sun.min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 14)
                        .accessibilityHidden(true)

                    Slider(value: $service.level, in: 0...1) { editing in
                        if editing { service.pushUndoSnapshot() }
                    }
                        .accessibilityLabel("XDR boost strength")
                        .accessibilityValue("\(Int(service.level * 100))%")
                        .help("How far to push into the extended brightness range")

                    Image(systemName: "sun.max.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                        .frame(width: 14)
                        .accessibilityHidden(true)

                    Text("\(Int(service.level * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 38, alignment: .trailing)
                        .monospacedDigit()

                    ResetButton(visible: service.level != 1.0) {
                        service.pushUndoSnapshot()
                        service.level = 1.0
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)

                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.caption2)
                        .accessibilityHidden(true)
                    Text("Uses the HDR headroom — HDR video may look dimmer while active.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
            }
        }
    }

    private var statusText: String {
        if !service.isEnabled {
            return "Boost brightness beyond the SDR limit"
        }
        if service.currentHeadroom > 1.05 {
            return String(format: "Active — %.1f× headroom engaged", service.currentHeadroom)
        }
        return "Waiting for HDR headroom…"
    }
}

// MARK: - XDRQuickSliderView

/// Compact XDR slider for the top section of the menu: at 0 the XDR mode is off,
/// dragging up enables it and sets the boost strength in one gesture.
struct XDRQuickSliderView: View {
    @ObservedObject private var service = XDRBrightnessService.shared

    private var sliderValue: Binding<Double> {
        Binding(
            get: { service.isEnabled ? service.level : 0 },
            set: { newValue in
                if newValue <= 0.001 {
                    if service.isEnabled { service.isEnabled = false }
                } else {
                    // Set the level BEFORE enabling — start() would otherwise
                    // apply a stale (or forced-to-full) boost for one cycle,
                    // visibly flashing the panel.
                    service.level = newValue
                    if !service.isEnabled { service.isEnabled = true }
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "sun.max.circle.fill")
                    .foregroundColor(service.isEnabled ? .yellow : .secondary)
                    .font(.caption)
                    .accessibilityHidden(true)
                Text("XDR Brightness")
                    .font(.body)
                Spacer()
                Text(service.isEnabled ? "\(Int(service.level * 100))%" : "Off")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                ResetButton(visible: service.isEnabled) {
                    service.pushUndoSnapshot()
                    service.isEnabled = false
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "sun.min")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 14)
                    .accessibilityHidden(true)

                Slider(value: sliderValue, in: 0...1) { editing in
                    if editing { service.pushUndoSnapshot() }
                }
                    .accessibilityLabel("XDR brightness")
                    .accessibilityValue(service.isEnabled ? "\(Int(service.level * 100))%" : "off")
                    .help("0 turns XDR mode off; drag up to boost beyond the SDR limit")

                Image(systemName: "sun.max.fill")
                    .font(.caption2)
                    .foregroundColor(.yellow)
                    .frame(width: 14)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
