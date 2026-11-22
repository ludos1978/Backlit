import AppKit
import Combine
import CoreVideo
import ScreenCaptureKit

/// Which statistic of the per-pixel lightness (CIE L*) represents a frame.
enum LightnessMetric: String, CaseIterable, Codable, Identifiable {
    case mean, rms
    var id: String { rawValue }
    var title: String { self == .mean ? "Average" : "RMS (bright-weighted)" }
}

/// Samples one display's content and reports its perceptual lightness
/// (0 = black … 1 = white), stabilized so that cursor blinks and transient redraws
/// do not move the brightness. Frames are analysed in memory and discarded —
/// nothing is stored or sent.
///
/// Cost is independent of the display's resolution: WindowServer captures at the
/// nominal (point) resolution and the GPU scales to a fixed ~64×36 frame, so a 4K/5K
/// HiDPI panel costs the same as a 1080p one. SCStream only delivers frames when the
/// content changed, so a static screen costs ~nothing.
@MainActor
final class ContentLightnessSampler: @unchecked Sendable {
    let displayID: CGDirectDisplayID
    var metric: LightnessMetric
    /// Committed (stabilized) lightness.
    private(set) var lightness: Double = 0.5
    /// Called on the main actor whenever the committed lightness changes.
    var onChange: ((Double) -> Void)?

    private var stream: SCStream?
    private var output: Output?
    private let sampleQueue = DispatchQueue(label: "io.github.ludos1978.backlit.lightness", qos: .utility)
    private var raw: Double = 0.5
    private var pendingFrames = 0
    /// Bumped by every start/stop; a start that was overtaken while awaiting
    /// discards its stream instead of leaving an orphaned capture running.
    private var generation = 0

    private static let sampleWidth = 64

    init(displayID: CGDirectDisplayID, metric: LightnessMetric) {
        self.displayID = displayID
        self.metric = metric
    }

    func start(fps: Int) async throws {
        stop()
        let gen = generation
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard gen == generation else { return }   // stopped meanwhile
        guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "Backlit.Lightness", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "display not available for capture"])
        }
        // Never sample our own windows (stream windows, EDR trigger, notch overlay).
        let own = content.windows.filter { $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: scDisplay, excludingWindows: own)
        let config = SCStreamConfiguration()
        // A mean over the whole screen needs very few pixels: 64 px wide, display aspect.
        let bounds = CGDisplayBounds(displayID)
        let aspect = bounds.width > 0 ? bounds.height / bounds.width : 9.0 / 16.0
        config.width = Self.sampleWidth
        config.height = max(16, Int((Double(Self.sampleWidth) * aspect).rounded()))
        config.captureResolution = .nominal      // points, not the 2× backing store
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
        config.showsCursor = false
        config.queueDepth = 3

        let output = Output(metric: metric) { [weak self] value in
            Task { @MainActor in self?.ingest(value) }
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
        self.output = output
        self.stream = stream
        try await stream.startCapture()
        if gen != generation {                    // stopped while starting
            try? await stream.stopCapture()
        }
    }

    func stop() {
        generation &+= 1
        guard let stream else { return }
        self.stream = nil
        self.output = nil
        Task { try? await stream.stopCapture() }
    }

    /// Stabilizer: a big jump (> 15 %, e.g. switching between a dark and a light
    /// window) commits at once; a smaller move (> 3 %) must be confirmed by the
    /// next frame, which filters cursor blinks and transient redraws.
    private func ingest(_ value: Double) {
        raw = value
        let change = abs(raw - lightness)
        if change > 0.03 {
            pendingFrames += 1
            if change > 0.15 || pendingFrames >= 2 {
                pendingFrames = 0
                lightness = raw
                onChange?(lightness)
            }
        } else {
            pendingFrames = 0
        }
    }
}

// MARK: - Frame analysis (background queue)

private final class Output: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let metric: LightnessMetric
    private let onSample: (Double) -> Void

    /// sRGB byte → linear light, pre-weighted per channel (Rec. 709 luminance).
    private static func weighted(_ w: Float) -> [Float] {
        (0..<256).map { i in
            let c = Float(i) / 255
            return w * (c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4))
        }
    }
    private static let lutB = weighted(0.0722), lutG = weighted(0.7152), lutR = weighted(0.2126)

    /// Relative luminance (quantized to 1/1023) → CIE L* normalized to 0…1.
    private static let lStarSteps = 1023
    private static let lutLStar: [Float] = (0...lStarSteps).map { i in
        let y = Float(i) / Float(lStarSteps)
        let f = y > 0.008856 ? cbrt(y) : 7.787 * y + 16 / 116
        return max(0, min(1, (116 * f - 16) / 100))
    }

    init(metric: LightnessMetric, onSample: @escaping (Double) -> Void) {
        self.metric = metric
        self.onSample = onSample
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let statusRaw = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: statusRaw), status != .complete {
            return   // idle / blank frames carry no new image
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0 else { return }

        var sum: Float = 0
        let rms = metric == .rms
        let steps = Float(Self.lStarSteps)
        Self.lutB.withUnsafeBufferPointer { lb in
        Self.lutG.withUnsafeBufferPointer { lg in
        Self.lutR.withUnsafeBufferPointer { lr in
        Self.lutLStar.withUnsafeBufferPointer { ll in
            for y in 0..<height {
                let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
                var rowSum: Float = 0
                for x in 0..<width {
                    let p = x &* 4                 // BGRA
                    let lin = lb[Int(row[p])] + lg[Int(row[p &+ 1])] + lr[Int(row[p &+ 2])]
                    let lStar = ll[Int(min(lin, 1) * steps + 0.5)]
                    rowSum += rms ? lStar * lStar : lStar
                }
                sum += rowSum
            }
        }}}}
        let n = Float(width * height)
        let value = Double(rms ? (sum / n).squareRoot() : sum / n)
        onSample(value)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        debugLog("[Lightness] stream stopped: \(error.localizedDescription)")
    }
}
