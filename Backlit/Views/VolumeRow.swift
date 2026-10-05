import SwiftUI

// MARK: - VolumeRow

/// Speaker volume + mute for an external monitor via DDC (VCP 0x62 / 0x8D).
/// Hidden when the monitor doesn't answer a volume read (no speakers or no DDC).
struct VolumeRow: View {
    @ObservedObject var display: DisplayInfo
    @ObservedObject private var volumeService = VolumeService.shared
    @State private var volume: Double = 50
    @State private var isDragging = false
    /// Throttle DDC writes during drag to ~100ms intervals.
    @State private var lastDDCWrite: Date = .distantPast

    private var state: VolumeState? { volumeService.states[display.displayID] }

    var body: some View {
        Group {
            if let state {
                content(state)
            }
        }
        .onAppear { VolumeService.shared.probe(display) }
        .onChange(of: state?.volume) { _, newValue in
            guard !isDragging, let newValue else { return }
            volume = newValue
        }
    }

    private func content(_ state: VolumeState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Volume")
                    .font(.body)
                Spacer()
                Text(state.isMuted ? "Muted" : "\(Int(volume))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                Button {
                    VolumeService.shared.toggleMute(for: display)
                } label: {
                    Image(systemName: state.isMuted ? "speaker.slash.fill" : "speaker.fill")
                        .font(.caption)
                        .foregroundColor(state.isMuted ? .red : .secondary)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
                .help(state.isMuted ? "Unmute the monitor's speakers" : "Mute the monitor's speakers")
                .accessibilityLabel(state.isMuted ? "Unmute" : "Mute")

                Slider(value: $volume, in: 0...100, step: 1) { editing in
                    isDragging = editing
                    if !editing {
                        // Drag ended — flush the final value.
                        VolumeService.shared.setVolume(volume, for: display)
                        lastDDCWrite = Date()
                    }
                }
                .opacity(state.isMuted ? 0.5 : 1)
                .accessibilityLabel("\(display.name) volume")
                .accessibilityValue(state.isMuted ? "Muted" : "\(Int(volume))%")
                .onChange(of: volume) { _, newValue in
                    guard isDragging else { return }
                    let now = Date()
                    let write = now.timeIntervalSince(lastDDCWrite) >= 0.1
                    if write { lastDDCWrite = now }
                    VolumeService.shared.setVolume(newValue, for: display, write: write)
                }

                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 14)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onAppear { volume = state.volume }
        .help("Speaker volume of this monitor (DDC)")
    }
}
