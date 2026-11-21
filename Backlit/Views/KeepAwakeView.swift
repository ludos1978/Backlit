import SwiftUI

/// Keep-awake mode picker: System (default) / Screens / Lid Closed.
struct KeepAwakeView: View {
    @ObservedObject private var service = KeepAwakeService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                MenuItemIcon(systemName: service.mode == .system ? "moon.zzz.fill" : "cup.and.saucer.fill",
                             color: service.mode == .system ? .secondary : .brown)
                Text("Keep Awake")
                Spacer()
            }

            Picker("", selection: Binding(
                get: { service.mode },
                set: { service.setMode($0) }
            )) {
                ForEach(KeepAwakeService.Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .help(service.mode.help)
            .accessibilityLabel("Keep awake mode")

            Text(service.lastError ?? service.mode.help)
                .font(.caption2)
                .foregroundColor(service.lastError == nil ? .secondary : .red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
