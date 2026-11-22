import SwiftUI

/// Keep-awake mode picker: System (default) / Screens / Lid Closed.
struct KeepAwakeView: View {
    @ObservedObject private var service = KeepAwakeService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PickerSettingRow(icon: service.mode == .system ? "moon.zzz.fill" : "cup.and.saucer.fill",
                             label: "Keep Awake",
                             selection: Binding(get: { service.mode }, set: { service.setMode($0) }),
                             options: KeepAwakeService.Mode.allCases, title: \.title,
                             accent: service.mode == .system ? .secondary : .brown,
                             help: service.mode.help)
            if let error = service.lastError {
                HintRow(text: error, systemImage: "exclamationmark.triangle.fill", color: .red)
            } else if service.mode != .system {
                HintRow(text: service.mode.help)
            }
        }
    }
}
