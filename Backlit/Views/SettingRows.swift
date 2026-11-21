import SwiftUI

// Shared rows for option panels (Image Adjustment, Adaptive Brightness, Keep Awake …).
// Every row uses the same grid — 18 pt icon · 104 pt label · control — so controls
// line up across panels.

enum SettingRowMetrics {
    static let iconWidth: CGFloat = 18
    static let labelWidth: CGFloat = 104
    static let valueWidth: CGFloat = 38
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 3
}

/// Icon + fixed-width label: the leading column of every setting row.
struct SettingRowLabel: View {
    let icon: String
    let label: String
    var accent: Color = .blue

    var body: some View {
        Image(systemName: icon)
            .foregroundColor(accent)
            .frame(width: SettingRowMetrics.iconWidth)
            .font(.caption)
            .accessibilityHidden(true)
        Text(label)
            .font(.body)
            .lineLimit(1)
            .frame(width: SettingRowMetrics.labelWidth, alignment: .leading)
    }
}

private extension View {
    func settingRowPadding() -> some View {
        padding(.horizontal, SettingRowMetrics.horizontalPadding)
            .padding(.vertical, SettingRowMetrics.verticalPadding)
    }
}

/// Small grey title above a group of rows.
struct SettingGroupHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, SettingRowMetrics.horizontalPadding)
            .padding(.top, 6)
            .padding(.bottom, 1)
    }
}

/// Slider row: icon · label · slider · value · reset.
/// `onBegin` runs when a drag (or reset) starts — push undo there; `onCommit`
/// when it ends; `onLive` on every change during a drag.
struct SliderSettingRow: View {
    let icon: String
    let label: String
    @Binding var value: Double
    var accent: Color = .blue
    var range: ClosedRange<Double>
    var step: Double = 1
    var defaultValue: Double
    var format: (Double) -> String
    var help: String? = nil
    var onBegin: () -> Void = {}
    var onCommit: () -> Void = {}
    var onLive: ((Double) -> Void)? = nil

    @State private var highlighted = false
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 8) {
            SettingRowLabel(icon: icon, label: label, accent: accent)

            Slider(value: $value, in: range, step: step) { editing in
                isDragging = editing
                if editing {
                    onBegin()
                } else {
                    onCommit()
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
                onLive?(newValue)
            }

            Text(format(value))
                .font(.caption)
                .foregroundColor(highlighted ? accent : .secondary)
                .frame(width: SettingRowMetrics.valueWidth, alignment: .trailing)
                .monospacedDigit()
                .contentTransition(.numericText())

            ResetButton(visible: value != defaultValue) {
                onBegin()
                value = defaultValue
                onCommit()
            }
        }
        .settingRowPadding()
        .help(help ?? "")
    }
}

/// Picker row: icon · label · segmented (or pop-up) picker.
struct PickerSettingRow<Value: Hashable>: View {
    let icon: String
    let label: String
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    var accent: Color = .blue
    var segmented = true
    var help: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            SettingRowLabel(icon: icon, label: label, accent: accent)
            picker
                .labelsHidden()
                .controlSize(.small)
        }
        .settingRowPadding()
        .help(help ?? "")
    }

    @ViewBuilder private var picker: some View {
        let p = Picker(label, selection: $selection) {
            ForEach(options, id: \.self) { Text(title($0)).tag($0) }
        }
        if segmented { p.pickerStyle(.segmented) } else { p.pickerStyle(.menu) }
    }
}

/// Toggle row: icon · label · … · switch.
struct ToggleSettingRow: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool
    var accent: Color = .blue
    var help: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            SettingRowLabel(icon: icon, label: label, accent: accent)
            Spacer()
            Toggle(label, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
        }
        .settingRowPadding()
        .help(help ?? "")
    }
}

/// One-line explanation or warning under a group; tappable when it has an action.
struct HintRow: View {
    let text: String
    var systemImage: String = "info.circle"
    var color: Color = .secondary
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundColor(color)
                .frame(width: SettingRowMetrics.iconWidth)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption2)
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SettingRowMetrics.horizontalPadding)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { action?() }
    }
}
