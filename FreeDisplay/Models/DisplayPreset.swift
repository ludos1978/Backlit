import Foundation
import CoreGraphics

struct DisplayPresetEntry: Codable, Identifiable {
    var id = UUID()
    var displayUUID: String       // matches physical display
    var width: Int
    var height: Int
    var isHiDPI: Bool
    var brightness: Double?       // optional brightness 0.0-1.0
    var arrangementX: Double?     // optional position
    var arrangementY: Double?
    // Optional (nil in presets saved by older versions → left untouched on apply)
    var gammaAdjustment: GammaAdjustment?  // full image-adjustment snapshot
}

struct DisplayPreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var icon: String              // SF Symbol name
    var isBuiltin: Bool = false
    var displays: [DisplayPresetEntry]
    // App-level state, optional for backward compatibility with older presets
    var xdrEnabled: Bool?          // XDR brightness mode on/off
    var xdrLevel: Double?          // XDR boost strength 0-1
    var increaseContrast: Bool?    // accessibility "Increase contrast"
    var displayContrast: Double?   // accessibility "Display Contrast" 0-1
}
