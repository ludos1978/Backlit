import SwiftUI

/// System-wide accessibility contrast controls (mirrors System Settings →
/// Accessibility → Display): the "Increase contrast" toggle and the
/// "Display Contrast" slider.
struct AccessibilityContrastView: View {
    @ObservedObject private var service = AccessibilityService.shared
    @State private var isHovered = false

    var body: some View {
        if service.isAvailable {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Increase contrast toggle
            HStack {
                Image(systemName: "circle.righthalf.filled.inverse")
                    .foregroundColor(service.increaseContrast ? .primary : .secondary)
                    .font(.caption)
                    .accessibilityHidden(true)
                Text("Increase Contrast (System)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                ResetButton(visible: service.increaseContrast) {
                    service.pushUndoSnapshot()
                    service.increaseContrast = false
                }
                Toggle("", isOn: Binding(
                    get: { service.increaseContrast },
                    set: { newValue in
                        service.pushUndoSnapshot()
                        service.increaseContrast = newValue
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
            }
            .help("The macOS accessibility setting that adds borders and stronger UI contrast")

            // Display contrast slider
            HStack(spacing: 6) {
                Image(systemName: "circle.lefthalf.striped.horizontal")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 14)
                    .accessibilityHidden(true)

                Slider(value: Binding(
                    get: { service.displayContrast },
                    set: { service.displayContrast = $0 }
                ), in: 0...1) { editing in
                    if editing { service.pushUndoSnapshot() }
                }
                .accessibilityLabel("System display contrast")
                .accessibilityValue("\(Int(service.displayContrast * 100))%")
                .help("The macOS accessibility Display Contrast setting (system-wide)")

                Image(systemName: "circle.lefthalf.filled")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 14)
                    .accessibilityHidden(true)

                Text("\(Int(service.displayContrast * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 38, alignment: .trailing)
                    .monospacedDigit()

                ResetButton(visible: service.displayContrast != 0) {
                    service.pushUndoSnapshot()
                    service.displayContrast = 0
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(isHovered ? 0.03 : 0))
        .onHover { isHovered = $0 }
    }
}
