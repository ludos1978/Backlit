import SwiftUI

// MARK: - PresetListView

/// Section in MenuBarView listing the user's presets plus "Save as Preset".
struct PresetListView: View {
    @ObservedObject private var presetService = PresetService.shared
    /// The last applied preset whose stored values no longer match the live state.
    @State private var modifiedPresetID: UUID?

    private var userPresets: [DisplayPreset] {
        presetService.presets.filter { !$0.isBuiltin }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // User-created presets as rows
            ForEach(userPresets) { preset in
                PresetRow(
                    preset: preset,
                    isCurrentMatch: presetService.currentPresetMatch() == preset.id,
                    isApplying: presetService.applyingPresetID == preset.id,
                    showUpdate: modifiedPresetID == preset.id,
                    onUpdate: {
                        presetService.updatePreset(id: preset.id)
                        modifiedPresetID = nil
                    }
                )
            }

            // Save preset button
            SavePresetView()
        }
        .onAppear { refreshModified() }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            refreshModified()
        }
        .onReceive(GammaService.stateDidChange) { _ in refreshModified() }
        .onReceive(UndoService.shared.$undoTick) { _ in refreshModified() }
    }

    /// Recomputes whether the last applied preset has been modified by the user.
    private func refreshModified() {
        guard let id = presetService.lastAppliedPresetID,
              let preset = presetService.presets.first(where: { $0.id == id }),
              presetService.isModified(preset) else {
            if modifiedPresetID != nil { modifiedPresetID = nil }
            return
        }
        if modifiedPresetID != id { modifiedPresetID = id }
    }
}

// MARK: - PresetRow (for user-created presets)

struct PresetRow: View {
    let preset: DisplayPreset
    let isCurrentMatch: Bool
    let isApplying: Bool
    var showUpdate: Bool = false
    var onUpdate: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            if isApplying {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 20, height: 20)
            } else {
                MenuItemIcon(systemName: preset.icon, color: isCurrentMatch ? .accentColor : .gray)
            }

            Text(preset.name)
                .font(.body)
                .lineLimit(1)

            Spacer()

            if showUpdate {
                Button("Update", action: onUpdate)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .help("Overwrite this preset with the current settings (⌘Z to undo)")
            }

            if isCurrentMatch {
                Text("Current")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(isHovered ? 0.06 : 0))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !PresetService.shared.isApplying else { return }
            Task { await PresetService.shared.applyPreset(preset) }
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(role: .destructive) {
                PresetService.shared.deletePreset(id: preset.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .disabled(PresetService.shared.isApplying)
    }
}
