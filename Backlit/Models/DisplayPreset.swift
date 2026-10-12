import Foundation
import CoreGraphics

struct DisplayPresetEntry: Codable, Identifiable {
    var id = UUID()
    var displayUUID: String       // matches physical display
    // Resolution stored by presets saved before 0.5.3 — decoded for compatibility but
    // never applied: only the Display Modes list may change a screen's resolution.
    var width: Int?
    var height: Int?
    var isHiDPI: Bool?
    var brightness: Double?       // optional brightness 0.0-1.0
    // Display position stored by older presets — decoded for compatibility, never applied.
    var arrangementX: Double?
    var arrangementY: Double?
    // Optional (nil in presets saved by older versions → left untouched on apply)
    var gammaAdjustment: GammaAdjustment?  // full image-adjustment snapshot
    var softwareDimming: Double?           // extra dimming below the hardware minimum, 0-95 %
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
    var restoresArrangement: Bool? // legacy (older presets) — ignored: presets never change the layout
    var adaptiveBrightnessEnabled: Bool? // adaptive brightness on/off at save time (nil = older preset)
}
