#!/usr/bin/env swift
// Gamma diagnostics: run with a problem display (e.g. a projector) attached.
//
//     swift scripts/gamma-check.swift
//
// For every online display it prints the mirror state and gamma-table capacity, then
// dims that display to 50 % through its gamma table for 2 seconds and restores the
// table it found. Watch which screen goes darker: if a display reports "write OK" but
// never dims, macOS accepts the gamma table for it but does not use it.

import ColorSync
import CoreGraphics
import Foundation

func uuid(_ id: CGDirectDisplayID) -> String {
    guard let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "?" }
    return CFUUIDCreateString(nil, u) as String
}

var count: UInt32 = 0
CGGetOnlineDisplayList(0, nil, &count)
var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
CGGetOnlineDisplayList(count, &ids, &count)

for id in ids {
    let mode = CGDisplayCopyDisplayMode(id)
    let mirrorOf = CGDisplayMirrorsDisplay(id)
    print("""
    Display \(id)  \(uuid(id))
      built-in: \(CGDisplayIsBuiltin(id) != 0)  active: \(CGDisplayIsActive(id) != 0)  \
    \(mode.map { "\($0.width)x\($0.height) @ \(Int($0.refreshRate)) Hz" } ?? "no mode")
      vendor/model: \(String(CGDisplayVendorNumber(id), radix: 16))/\(String(CGDisplayModelNumber(id), radix: 16))
      mirror: \(CGDisplayIsInMirrorSet(id) != 0 ? (mirrorOf != kCGNullDirectDisplay ? "mirrors display \(mirrorOf)" : "mirror source") : "none")  \
    hardware mirror: \(CGDisplayIsInHWMirrorSet(id) != 0)
      gamma table capacity: \(CGDisplayGammaTableCapacity(id))
    """)

    // Save the current table so it can be put back exactly.
    let cap = max(256, Int(CGDisplayGammaTableCapacity(id)))
    var r = [CGGammaValue](repeating: 0, count: cap), g = r, b = r
    var sampleCount: UInt32 = 0
    let readErr = CGGetDisplayTransferByTable(id, UInt32(cap), &r, &g, &b, &sampleCount)

    var dr = (0..<256).map { CGGammaValue($0) / 255 * 0.5 }, dg = dr, db = dr
    let writeErr = CGSetDisplayTransferByTable(id, 256, &dr, &dg, &db)
    print("  read: \(readErr == .success ? "OK (\(sampleCount) samples)" : "error \(readErr.rawValue)")  " +
          "write: \(writeErr == .success ? "OK" : "error \(writeErr.rawValue)")  → watch display \(id) for 2 s…")
    Thread.sleep(forTimeInterval: 2)

    if readErr == .success, sampleCount > 0 {
        CGSetDisplayTransferByTable(id, sampleCount, &r, &g, &b)
    } else {
        var lr = (0..<256).map { CGGammaValue($0) / 255 }, lg = lr, lb = lr
        CGSetDisplayTransferByTable(id, 256, &lr, &lg, &lb)
    }
    print("")
}
