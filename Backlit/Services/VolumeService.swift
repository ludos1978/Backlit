import AppKit
import CoreAudio
import CoreGraphics

// MARK: - VolumeState

/// Speaker state of one external display, as far as DDC lets us know it.
struct VolumeState: Equatable {
    /// Volume 0–100 (scaled from the monitor's own 0…max range).
    var volume: Double
    var isMuted: Bool
    /// True if the monitor answered a VCP 0x8D (audio mute) read. When false, mute is
    /// emulated by writing volume 0 and restoring the remembered volume afterwards.
    var hasMuteControl: Bool
    /// The monitor's maximum for VCP 0x62 (usually 100).
    var maxValue: UInt16
}

// MARK: - VolumeService

/// Controls the built-in speakers (or headphone jack) of external monitors via DDC/CI,
/// the way MonitorControl does: VCP 0x62 (audio speaker volume) and 0x8D (audio mute).
///
/// Many monitors report their volume unreliably, so the last value Backlit set is
/// remembered per display (`fd.volume.uuid.*`) and used when the read-back looks wrong.
@MainActor
final class VolumeService: ObservableObject {
    static let shared = VolumeService()
    private init() {}

    /// Displays whose volume could be read. Absent here and from `unsupported` = not probed yet.
    @Published private(set) var states: [CGDirectDisplayID: VolumeState] = [:]
    /// Displays that did not answer a VCP 0x62 read (no speakers or no DDC).
    @Published private(set) var unsupported: Set<CGDirectDisplayID> = []

    private let defaults = UserDefaults.standard
    private static let volumeKeyPrefix = "fd.volume.uuid."
    private static let mutedKeyPrefix  = "fd.volumeMuted.uuid."

    // MARK: - Probe

    /// Reads volume and mute state over DDC. Safe to call repeatedly (DDC reads are cached).
    func probe(_ display: DisplayInfo) {
        guard !display.isBuiltin else { return }
        let displayID = display.displayID
        let uuid = display.displayUUID

        DDCService.shared.readAsync(displayID: displayID, command: DDCService.volumeVCP) { volResult in
            DDCService.shared.readAsync(displayID: displayID, command: DDCService.muteVCP) { muteResult in
                Task { @MainActor in
                    let service = VolumeService.shared
                    guard let volResult, volResult.max > 0 else {
                        service.states[displayID] = nil
                        service.unsupported.insert(displayID)
                        return
                    }
                    service.unsupported.remove(displayID)

                    var volume = Double(volResult.current) / Double(volResult.max) * 100
                    // Mute codes: 1 = muted, 2 = unmuted. Anything else → treat as unsupported.
                    let hasMute = muteResult.map { $0.current == 1 || $0.current == 2 } ?? false
                    var muted = hasMute ? muteResult?.current == 1 : service.savedMuted(uuid: uuid)

                    // Emulated mute is stored as volume 0 on the monitor — show the remembered level.
                    if !hasMute, muted, let saved = service.savedVolume(uuid: uuid) {
                        if volume == 0 { volume = saved } else { muted = false }
                    }

                    service.states[displayID] = VolumeState(
                        volume: volume.rounded(),
                        isMuted: muted,
                        hasMuteControl: hasMute,
                        maxValue: volResult.max
                    )
                }
            }
        }
    }

    func isSupported(_ displayID: CGDirectDisplayID) -> Bool { states[displayID] != nil }

    // MARK: - Set

    /// Sets the volume (0–100). Raising the volume while muted unmutes, like macOS.
    /// - Parameter write: false updates the model only (used to throttle slider drags).
    func setVolume(_ value: Double, for display: DisplayInfo, write: Bool = true) {
        guard var state = states[display.displayID] else { return }
        let clamped = max(0, min(100, value)).rounded()
        state.volume = clamped
        let unmute = state.isMuted && clamped > 0
        if unmute { state.isMuted = false }
        states[display.displayID] = state
        saveVolume(clamped, uuid: display.displayUUID)
        guard write else { return }

        if unmute { writeMute(false, state: state, display: display) }
        writeVolume(clamped, state: state, displayID: display.displayID)
    }

    func setMuted(_ muted: Bool, for display: DisplayInfo) {
        guard var state = states[display.displayID], state.isMuted != muted else { return }
        state.isMuted = muted
        states[display.displayID] = state
        defaults.set(muted, forKey: Self.mutedKeyPrefix + display.displayUUID)
        writeMute(muted, state: state, display: display)
    }

    func toggleMute(for display: DisplayInfo) {
        guard let state = states[display.displayID] else { return }
        setMuted(!state.isMuted, for: display)
    }

    // MARK: - DDC Writes

    private func writeVolume(_ value: Double, state: VolumeState, displayID: CGDirectDisplayID) {
        let raw = UInt16((value / 100 * Double(state.maxValue)).rounded())
        DDCService.shared.writeAsync(displayID: displayID, command: DDCService.volumeVCP, value: raw)
    }

    private func writeMute(_ muted: Bool, state: VolumeState, display: DisplayInfo) {
        if state.hasMuteControl {
            DDCService.shared.writeAsync(displayID: display.displayID, command: DDCService.muteVCP,
                                         value: muted ? 1 : 2)
        } else {
            // No mute control: silence by volume 0, restore the remembered level on unmute.
            writeVolume(muted ? 0 : state.volume, state: state, displayID: display.displayID)
        }
    }

    // MARK: - Persistence

    private func savedVolume(uuid: String) -> Double? {
        let key = Self.volumeKeyPrefix + uuid
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.double(forKey: key)
    }

    private func saveVolume(_ value: Double, uuid: String) {
        defaults.set(value, forKey: Self.volumeKeyPrefix + uuid)
    }

    private func savedMuted(uuid: String) -> Bool {
        defaults.bool(forKey: Self.mutedKeyPrefix + uuid)
    }

    // MARK: - Audio Output Matching

    /// The external display whose speakers are the current macOS sound output, or nil
    /// if the output is something else (built-in speakers, USB, Bluetooth, AirPlay…).
    ///
    /// CoreAudio exposes no display ID for HDMI/DisplayPort audio, so the device is
    /// matched by name against the display names. If that fails and exactly one
    /// external display supports DDC volume, that one is assumed.
    func displayForCurrentAudioOutput(in displays: [DisplayInfo]) -> DisplayInfo? {
        guard let device = Self.defaultOutputDevice(),
              let transport = Self.transportType(of: device),
              transport == kAudioDeviceTransportTypeHDMI ||
              transport == kAudioDeviceTransportTypeDisplayPort
        else { return nil }

        let candidates = displays.filter { !$0.isBuiltin }
        if let name = Self.deviceName(of: device)?.lowercased(), !name.isEmpty {
            if let exact = candidates.first(where: { $0.name.lowercased() == name }) { return exact }
            if let partial = candidates.first(where: {
                let displayName = $0.name.lowercased()
                return displayName.contains(name) || name.contains(displayName)
            }) { return partial }
        }
        let supported = candidates.filter { isSupported($0.displayID) }
        return supported.count == 1 ? supported[0] : nil
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func transportType(of device: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport)
        return status == noErr ? transport : nil
    }

    private static func deviceName(of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }
}
