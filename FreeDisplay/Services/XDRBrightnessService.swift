import AppKit
import CoreGraphics
import Metal
import MetalKit

/// Unlocks the extended (XDR) brightness range of Apple XDR panels for normal SDR
/// content. The technique itself is public knowledge (popularized by BrightIntosh);
/// this is an independent implementation with its own calibration:
///
///  1. A 1×1 pt invisible overlay window per display renders a single EDR pixel
///     (extended-linear-sRGB white > 1.0) through Metal. Its presence makes macOS
///     engage HDR headroom, observable via
///     `NSScreen.maximumExtendedDynamicRangeColorComponentValue` rising above ~1.05.
///  2. Once headroom is engaged, the display's gamma table is scaled by a factor
///     > 1.0 (via GammaService, the sole gamma-table writer) so ordinary SDR white
///     lands in the extended range and the panel drives its full brightness.
///
/// The boost is self-calibrating: it uses the panel's reported potential headroom
/// and the smallest headroom observed while engaged (≈ full backlight) instead of
/// per-model constants. Only public APIs are involved; macOS retains thermal and
/// battery control of the actual headroom, so the OS can always dial the effect back.
@MainActor
final class XDRBrightnessService: ObservableObject, @unchecked Sendable {
    static let shared = XDRBrightnessService()

    /// Headroom value above which the extended range counts as engaged.
    private static let engagedThreshold = 1.05
    /// Maximum extra gain at full backlight, as a fraction of SDR white (our choice;
    /// scaled by `level`). 0.6 → SDR white is driven to 1.6× when fully engaged.
    private static let maxExtraGain = 0.6
    /// Fallback potential headroom when the panel does not report one.
    private static let fallbackPotentialEDR = 16.0

    /// Full-backlight headroom reference for displays whose backlight cannot be
    /// read (externals): the smallest headroom seen after engagement has settled.
    private var referenceHeadroom: [CGDirectDisplayID: Double] = [:]
    /// When each display's extended range first engaged (headroom rises over a
    /// couple of seconds after the trigger appears; readings before it settles
    /// must not become the reference).
    private var engagedSince: [CGDirectDisplayID: Date] = [:]
    private static let settleSeconds: TimeInterval = 3

    @Published var isEnabled: Bool = false {
        didSet {
            guard oldValue != isEnabled else { return }
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            isEnabled ? start() : stop()
        }
    }

    /// Boost strength 0…1 (fraction of the panel's available extra range).
    @Published var level: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(level, forKey: Keys.level)
            if isEnabled { updateBoosts() }
        }
    }

    /// Current EDR headroom of the first boosted display (diagnostic, drives UI).
    @Published private(set) var currentHeadroom: Double = 1.0

    private enum Keys {
        static let enabled = "fd.xdr.enabled"
        static let level   = "fd.xdr.level"
    }

    private var overlays: [CGDirectDisplayID: EDRTriggerWindow] = [:]
    private var appliedBoosts: [CGDirectDisplayID: Double] = [:]
    private var pollTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    private init() {}

    /// Pushes the current XDR state onto the undo stack (⌘Z).
    func pushUndoSnapshot() {
        let wasEnabled = isEnabled
        let previousLevel = level
        UndoService.shared.push {
            Task { @MainActor in
                let service = XDRBrightnessService.shared
                service.level = previousLevel
                service.isEnabled = wasEnabled
            }
        }
    }

    /// Restores the persisted XDR state. Called once at app launch.
    func restoreSavedState() {
        if UserDefaults.standard.object(forKey: Keys.level) != nil {
            level = UserDefaults.standard.double(forKey: Keys.level)
        }
        if UserDefaults.standard.bool(forKey: Keys.enabled) {
            isEnabled = true
        }
    }

    // MARK: - Eligibility

    /// Screens whose panel can exceed SDR (Liquid Retina XDR built-ins, Apple XDR
    /// externals, and other genuinely HDR-capable displays).
    var eligibleScreens: [NSScreen] {
        NSScreen.screens.filter {
            $0.maximumPotentialExtendedDynamicRangeColorComponentValue >= 2.0
        }
    }

    var hasEligibleDisplays: Bool { !eligibleScreens.isEmpty }

    // MARK: - Lifecycle

    private func start() {
        // Enabling with a near-zero level (left over from dragging the quick
        // slider to the bottom) would visibly do nothing — default to full boost.
        if level < 0.05 { level = 1.0 }
        rebuildOverlays()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                XDRBrightnessService.shared.updateBoosts()
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                guard XDRBrightnessService.shared.isEnabled else { return }
                XDRBrightnessService.shared.rebuildOverlays()
                XDRBrightnessService.shared.updateBoosts()
            }
        }
        // WindowServer resets the gamma table on wake, and GammaService's wake
        // reapply is a no-op when no image adjustment is saved — the boost must
        // re-assert itself (project rule: gamma-writing services reapply on wake).
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                let service = XDRBrightnessService.shared
                guard service.isEnabled else { return }
                // Give WindowServer time to stabilize, then force a rewrite by
                // dropping the applied-factor cache.
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                service.appliedBoosts.removeAll()
                service.rebuildOverlays()
                service.updateBoosts()
            }
        }
        updateBoosts()
    }

    private func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            wakeObserver = nil
        }
        for (_, window) in overlays { window.orderOut(nil) }
        overlays.removeAll()
        for (displayID, _) in appliedBoosts {
            GammaService.shared.setXDRBoost(nil, for: displayID)
        }
        appliedBoosts.removeAll()
        referenceHeadroom.removeAll()
        engagedSince.removeAll()
        currentHeadroom = 1.0
    }

    /// Creates trigger overlays for all eligible screens and removes stale ones.
    private func rebuildOverlays() {
        let screens = eligibleScreens
        let wantedIDs = Set(screens.map(\.displayID))

        for (displayID, window) in overlays where !wantedIDs.contains(displayID) {
            window.orderOut(nil)
            overlays.removeValue(forKey: displayID)
            referenceHeadroom.removeValue(forKey: displayID)
            engagedSince.removeValue(forKey: displayID)
            if appliedBoosts.removeValue(forKey: displayID) != nil {
                GammaService.shared.setXDRBoost(nil, for: displayID)
            }
        }
        for screen in screens {
            let displayID = screen.displayID
            guard displayID != 0 else { continue }
            if let existing = overlays[displayID] {
                existing.pin(to: screen)
            } else {
                overlays[displayID] = EDRTriggerWindow(screen: screen)
            }
        }
    }

    // MARK: - Boost computation

    /// Re-reads each screen's headroom and pushes the resulting gamma factor to
    /// GammaService. Factors only change materially with backlight adjustments,
    /// so tiny fluctuations are ignored to avoid needless table rewrites.
    private func updateBoosts() {
        var headroomForUI = 1.0
        for screen in eligibleScreens {
            let displayID = screen.displayID
            guard displayID != 0, overlays[displayID] != nil else { continue }

            let headroom = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
            headroomForUI = max(headroomForUI, headroom)

            if headroom > Self.engagedThreshold {
                if engagedSince[displayID] == nil { engagedSince[displayID] = Date() }
            } else {
                engagedSince.removeValue(forKey: displayID)
                referenceHeadroom.removeValue(forKey: displayID)
            }

            let factor: Double
            if headroom > Self.engagedThreshold && level > 0 {
                factor = boostFactor(headroom: headroom, screen: screen)
            } else {
                factor = 1.0
            }

            let previous = appliedBoosts[displayID] ?? 1.0
            if abs(factor - previous) > 0.01 {
                appliedBoosts[displayID] = factor
                GammaService.shared.setXDRBoost(factor > 1.0 ? factor : nil, for: displayID)
            }
        }
        currentHeadroom = headroomForUI
    }

    /// Boost factor for the current headroom. The panel grants the most extra
    /// range at full backlight (its smallest headroom); as the backlight dims the
    /// reported headroom grows toward the panel's potential maximum, and the
    /// multiplier tapers linearly to 1.0 so dimming keeps working naturally.
    /// `level` scales the effect.
    private func boostFactor(headroom: Double, screen: NSScreen) -> Double {
        let displayID = screen.displayID

        // Full-backlight reference, measured right now (no history, no per-model
        // constants). Headroom scales inversely with emitted light, and the system
        // backlight slider is perceptual — light output goes roughly with the
        // square of the slider value (measured on a Liquid Retina XDR: headroom
        // 11.4 at 50 % vs 3.2 at 100 %; 11.4 × 0.5² ≈ 2.9). Externals (backlight
        // unreadable) use the smallest headroom seen once engagement has settled.
        let reference: Double
        if let backlight = BrightnessService.shared.hardwareBacklight(for: displayID), backlight > 0.02 {
            reference = max(Self.engagedThreshold, headroom * backlight * backlight)
        } else {
            let since = engagedSince[displayID] ?? Date()
            if Date().timeIntervalSince(since) >= Self.settleSeconds {
                referenceHeadroom[displayID] = min(referenceHeadroom[displayID] ?? headroom, headroom)
            }
            reference = referenceHeadroom[displayID] ?? headroom
        }

        var potential = Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
        if potential <= reference + 0.5 { potential = max(Self.fallbackPotentialEDR, reference + 1) }

        // 1.0 at the potential maximum (deep dimming) … full gain at the reference.
        let remaining = max(0.0, min(1.0, (potential - headroom) / (potential - reference)))
        let maxFactor = 1.0 + Self.maxExtraGain * remaining
        let factor = 1.0 + (maxFactor - 1.0) * min(max(level, 0.0), 1.0)
        // Never boost beyond the currently *granted* headroom: a factor above it
        // hard-clips the top of the curve (bright grays merge into white), e.g.
        // in Low Power Mode or under thermal limits.
        return min(factor, max(1.0, headroom * 0.95))
    }
}

// MARK: - EDR Trigger Window

/// Borderless, click-through 1×1 pt window pinned to a screen's top-left corner.
/// Its Metal view keeps a single EDR-white pixel on screen, which is what makes
/// macOS engage the panel's extended dynamic range.
private final class EDRTriggerWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: NSRect(x: screen.frame.minX, y: screen.frame.maxY - 1, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        animationBehavior = .none
        level = .screenSaver
        collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle]
        contentView = EDRTriggerView()
        orderFrontRegardless()
    }

    /// Repositions the trigger pixel to the screen's top-left corner.
    func pin(to screen: NSScreen) {
        setFrameOrigin(NSPoint(x: screen.frame.minX, y: screen.frame.maxY - 1))
    }
}

/// MTKView that clears to extended-range white at a few frames per second.
/// No shaders are needed — the clear color itself is the EDR content.
private final class EDRTriggerView: MTKView, MTKViewDelegate {
    private var commandQueue: MTLCommandQueue?

    init() {
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1), device: device)
        commandQueue = device?.makeCommandQueue()
        delegate = self
        colorPixelFormat = .rgba16Float
        colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        preferredFramesPerSecond = 4
        autoResizeDrawable = false
        drawableSize = CGSize(width: 1, height: 1)
        // Color > 1.0 engages the extended range even at near-zero alpha
        // (verified: headroom rises within ~2 s at alpha 0.01), which makes the
        // 1×1 trigger pixel genuinely invisible — including over dark menu bars
        // and full-screen video. The boost strength itself comes from the gamma
        // table, not from this pixel.
        clearColor = MTLClearColorMake(1.5, 1.5, 1.5, 0.01)
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.wantsExtendedDynamicRangeContent = true
            metalLayer.pixelFormat = .rgba16Float
            metalLayer.isOpaque = false
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
