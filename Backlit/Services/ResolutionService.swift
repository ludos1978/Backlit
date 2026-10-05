import Foundation
@preconcurrency import CoreGraphics

/// Service responsible for reading and changing display resolution modes.
/// Policy: a mode is only ever changed by an explicit user pick in the Display Modes
/// list (and its ⌘Z undo) — never by presets, wake handling or display connects.
@MainActor
final class ResolutionService: @unchecked Sendable {
    static let shared = ResolutionService()
    private init() {}

    // MARK: - Query

    func availableModes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        DisplayMode.availableModes(for: displayID)
    }

    func currentMode(for displayID: CGDirectDisplayID) -> DisplayMode? {
        DisplayMode.currentMode(for: displayID)
    }

    // MARK: - Apply

    /// Sets a display mode on `displayID`.
    ///
    /// Mirror-aware: when the target display is a mirror target (e.g. the physical display
    /// is mirroring a CGVirtualDisplay for HiDPI), the mode must be applied to the mirror
    /// SOURCE (the virtual display), not to the mirror target itself.
    /// CGConfigureDisplayWithDisplayMode silently hangs or fails on mirror targets because
    /// their mode is driven by the source.
    ///
    /// Strategy:
    ///   1. If displayID is a mirror target, resolve to the mirror source (virtualDisplayID).
    ///   2. Find the matching CGDisplayMode on the source by logical size + HiDPI attributes.
    ///   3. Apply via CGConfigureDisplayWithDisplayMode on the source display.
    ///   4. Fallback: try CGSConfigureDisplayMode (private API) on the source.
    func setDisplayMode(_ mode: DisplayMode, for displayID: CGDirectDisplayID) async -> Bool {
        // Resolve mirror source — the physical display may mirror a virtual display
        let (targetID, isMirrorRedirect) = resolvedTargetDisplayID(for: displayID)
        #if DEBUG
        if isMirrorRedirect {
            print("[ResolutionService] Mirror redirect: applying mode on source=\(targetID) instead of mirror target=\(displayID)")
        }
        #endif

        let options: CFDictionary = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary

        // Enumerate modes off the main thread to avoid blocking the UI
        let cgMode: CGDisplayMode? = await Task.detached(priority: .userInitiated) {
            guard let allRaw = CGDisplayCopyAllDisplayModes(targetID, options) as? [CGDisplayMode] else {
                #if DEBUG
                print("[ResolutionService] CGDisplayCopyAllDisplayModes returned nil for displayID=\(targetID)")
                #endif
                return nil
            }

            // First try: exact modeID match (works when targetID == displayID)
            if let exact = allRaw.first(where: { $0.ioDisplayModeID == mode.ioDisplayModeID }) {
                return exact
            }

            // Second try: match by logical size + HiDPI when we routed to the mirror source
            // (the source has different modeIDs than the mirror target)
            return ResolutionService.bestMatchingMode(in: allRaw, for: mode)
        }.value

        guard let cgMode else {
            if isMirrorRedirect {
                // Last resort: try CGS private API with the mode's raw modeID on the source
                #if DEBUG
                print("[ResolutionService] No matching mode on mirror source=\(targetID), trying CGS fallback")
                #endif
                return await cgsFallback(modeID: UInt32(bitPattern: mode.ioDisplayModeID), on: targetID)
            }
            #if DEBUG
            print("[ResolutionService] No matching CGDisplayMode for \(mode.width)×\(mode.height) hiDPI=\(mode.isHiDPI) on displayID=\(targetID)")
            #endif
            return false
        }

        #if DEBUG
        print("[ResolutionService] Applying modeID=\(cgMode.ioDisplayModeID) (\(cgMode.width)×\(cgMode.height) pixW=\(cgMode.pixelWidth)) on displayID=\(targetID)")
        #endif

        // Apply via standard public CG API (off main thread to avoid blocking the UI)
        let success = await Task.detached(priority: .userInitiated) {
            await ResolutionService.applyModeSync(cgMode, on: targetID)
        }.value

        if success { return true }

        // Fallback: CGSConfigureDisplayMode
        #if DEBUG
        print("[ResolutionService] Standard API failed, trying CGS fallback modeID=\(cgMode.ioDisplayModeID)")
        #endif
        return await cgsFallback(modeID: UInt32(bitPattern: cgMode.ioDisplayModeID), on: targetID)
    }

    // MARK: - Mirror resolution

    /// Returns the display ID that should receive the mode change, plus a flag indicating
    /// whether a mirror redirect occurred.
    private func resolvedTargetDisplayID(for displayID: CGDirectDisplayID) -> (CGDirectDisplayID, Bool) {
        let mirrorSource = CGDisplayMirrorsDisplay(displayID)
        guard mirrorSource != kCGNullDirectDisplay else {
            return (displayID, false)
        }

        // Verify the source exists and has modes
        let options: CFDictionary = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        guard let sourceModes = CGDisplayCopyAllDisplayModes(mirrorSource, options) as? [CGDisplayMode],
              !sourceModes.isEmpty else {
            #if DEBUG
            print("[ResolutionService] Mirror source=\(mirrorSource) has no modes; using original displayID=\(displayID)")
            #endif
            return (displayID, false)
        }

        return (mirrorSource, true)
    }

    // MARK: - Mode attribute matching

    /// Find the best CGDisplayMode in `rawModes` matching `mode`'s logical properties.
    ///
    /// Matching priority:
    ///   1. Exact logical size + HiDPI flag (pixel > logical)
    ///   2. Exact logical size (any HiDPI)
    nonisolated static func bestMatchingMode(in rawModes: [CGDisplayMode], for mode: DisplayMode) -> CGDisplayMode? {
        // Exact logical size + HiDPI
        let exact = rawModes.first(where: {
            $0.width == mode.width &&
            $0.height == mode.height &&
            ($0.pixelWidth > $0.width) == mode.isHiDPI &&
            $0.isUsableForDesktopGUI()
        })
        if let m = exact { return m }

        // Relax HiDPI constraint
        return rawModes.first(where: {
            $0.width == mode.width &&
            $0.height == mode.height &&
            $0.isUsableForDesktopGUI()
        })
    }

    // MARK: - Commit via public CG API (async, call off main thread)

    /// Applies a display mode change off the calling thread.
    /// The entire Begin→Configure→Complete transaction runs inside `CGHelpers.runWithTimeout`
    /// so `CGCompleteDisplayConfiguration` cannot block indefinitely on WindowServer IPC.
    nonisolated static func applyModeSync(_ cgMode: CGDisplayMode, on displayID: CGDirectDisplayID) async -> Bool {
        await CGHelpers.runWithTimeout(seconds: 10, fallback: false) {
            var config: CGDisplayConfigRef?
            guard CGBeginDisplayConfiguration(&config) == .success,
                  let cfg = config else {
                #if DEBUG
                print("[ResolutionService] CGBeginDisplayConfiguration failed")
                #endif
                return false
            }

            let result = CGConfigureDisplayWithDisplayMode(cfg, displayID, cgMode, nil)
            guard result == .success else {
                CGCancelDisplayConfiguration(cfg)
                #if DEBUG
                print("[ResolutionService] CGConfigureDisplayWithDisplayMode failed (\(result.rawValue)) displayID=\(displayID) modeID=\(cgMode.ioDisplayModeID)")
                #endif
                return false
            }

            let complete = CGCompleteDisplayConfiguration(cfg, .forSession)
            #if DEBUG
            if complete != .success {
                print("[ResolutionService] CGCompleteDisplayConfiguration failed (\(complete.rawValue))")
            }
            #endif
            return complete == .success
        }
    }

    // MARK: - CGSConfigureDisplayMode fallback (private API)

    /// Applies a mode by its raw modeID using the CGS private API.
    /// CGSConfigureDisplayMode(connection, displayID, modeID) bypasses some of the
    /// restrictions that CGConfigureDisplayWithDisplayMode has on certain display configs.
    /// Does NOT wrap in a CGBeginDisplayConfiguration transaction — CGSConfigureDisplayMode
    /// manages its own transaction internally; an empty outer transaction would always succeed
    /// regardless of whether the mode change actually took effect.
    private func cgsFallback(modeID: UInt32, on displayID: CGDirectDisplayID) async -> Bool {
        return await Task.detached(priority: .userInitiated) {
            let connection = CGSMainConnectionID()
            CGSConfigureDisplayMode(connection, displayID, modeID)

            // Wait for the mode change to propagate before reading back
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms

            // Verify success by checking whether the active modeID changed
            let newModeID = CGDisplayCopyDisplayMode(displayID)?.ioDisplayModeID
            let success = newModeID == Int32(bitPattern: modeID)
            #if DEBUG
            print("[ResolutionService] CGS fallback: success=\(success) modeID=\(modeID) displayID=\(displayID) activeModeID=\(newModeID as Any)")
            #endif
            return success
        }.value
    }
}
