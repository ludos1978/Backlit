import SwiftUI

/// App settings, shown under the "Settings" row in Options.
struct SettingsView: View {
    @ObservedObject private var settings = SettingsService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToggleSettingRow(icon: "power", label: "Launch at Login",
                             isOn: Binding(get: { settings.launchAtLogin }, set: setLaunchAtLogin),
                             accent: .green, help: "Start Backlit automatically when you log in")
            if !settings.launchAtLoginPrompted {
                HintRow(text: "Tip: enable Launch at Login (click to dismiss)", systemImage: "lightbulb") {
                    settings.launchAtLoginPrompted = true
                }
            }
            ToggleSettingRow(icon: "sun.min.fill", label: "Show Combined Brightness",
                             isOn: $settings.showCombinedBrightness, accent: .yellow,
                             help: "Show a single slider that controls the brightness of all displays")
            ToggleSettingRow(icon: "arrow.clockwise.circle", label: "Check for Updates at Launch",
                             isOn: $settings.checkUpdatesOnLaunch, accent: .blue,
                             help: "Automatically check for a new version at every launch")

            SettingGroupHeader(title: "Keys")
            ToggleSettingRow(icon: "keyboard", label: "Intercept Brightness Keys",
                             isOn: keyTap(\.interceptBrightnessKeys), accent: .purple,
                             help: "Route F1/F2 to the external display under the cursor via DDC, with Backlit's own on-screen indicator (needs Accessibility permission)")
            ToggleSettingRow(icon: "speaker.wave.2.fill", label: "Intercept Volume Keys",
                             isOn: keyTap(\.interceptVolumeKeys), accent: .pink,
                             help: "When the sound output is a monitor (HDMI/DisplayPort audio), route the volume and mute keys to its speakers via DDC (needs Accessibility permission)")

            SettingGroupHeader(title: "Who controls each setting")
            HintRow(text: "On: Backlit owns it — applies its saved values at launch and lets you change them here. Off: macOS owns it — Backlit only shows the current value, and clicking a control opens the macOS settings panel.")
            ForEach(PreferenceArea.allCases) { area in
                ToggleSettingRow(icon: area.icon, label: area.title,
                                 isOn: Binding(get: { settings.isAuthoritative(area) },
                                               set: { settings.setAuthoritative(area, $0) }),
                                 accent: area.color,
                                 help: "On: Backlit controls \(area.title). Off: macOS controls it (System Settings → \(area.osPanelName)); Backlit only displays it.")
            }
        }
        .padding(.vertical, 4)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        if on { LaunchService.shared.enable() } else { LaunchService.shared.disable() }
        settings.launchAtLogin = on
    }

    /// Binding for a key-interception flag; re-arms the event tap on change.
    private func keyTap(_ key: ReferenceWritableKeyPath<SettingsService, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: key] },
                set: { settings[keyPath: key] = $0; BrightnessKeyService.shared.updateTapState() })
    }
}
