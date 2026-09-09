import SwiftUI

/// Makes a control read-only when its preference area is macOS-controlled:
/// the current value stays visible, interaction is disabled, and a click opens
/// the matching macOS System Settings panel instead.
struct OSControlledModifier: ViewModifier {
    let area: PreferenceArea
    @ObservedObject private var settings = SettingsService.shared

    init(area: PreferenceArea) { self.area = area }

    func body(content: Content) -> some View {
        if settings.isAuthoritative(area) {
            content
        } else {
            content
                .disabled(true)
                .opacity(0.55)
                .overlay(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { PreferenceArea.openOSPanel(area) }
                )
                .help("Controlled by macOS — click to open System Settings → \(area.osPanelName). Change this under Settings → “\(area.title)”.")
        }
    }
}

extension View {
    /// Read-only + opens the macOS panel on click while `area` is macOS-controlled.
    func osControlled(_ area: PreferenceArea) -> some View {
        modifier(OSControlledModifier(area: area))
    }
}
