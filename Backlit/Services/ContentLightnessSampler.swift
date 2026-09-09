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

/// Samples one display's content at 1/16 resolution a few times per second and
/// reports its perceptual lightness (0 = black … 1 = white), stabilized so that
/// cursor blinks and transient redraws do not move the brightness.
/// Frames are analysed in memory and discarded — nothing is stored or sent.
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

    init(displayID: CGDirectDisplayID, metric: LightnessMetric) {
        self.displayID = displayID
        self.metric = metric
    }

    func start(fps: Int) async throws {
        stop()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "Backlit.Lightness", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "display not available for capture"])
        }
        // Never sample our own windows (stream windows, EDR trigger, notch overlay).
        let own = content.windows.filter { $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: scDisplay, excludingWindows: own)
        let config = SCStreamConfiguration()
        config.width = max(32, CGDisplayPixelsWide(displayID) / 16)
        config.height = max(20, CGDisplayPixelsHigh(displayID) / 16)
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
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        self.output = nil
        Task { try? await stream.stopCapture() }
    }

    /// Stabilizer: commit a new lightness only after it has moved by more than
    /// 3 % and stayed there for two consecutive frames.
    private func ingest(_ value: Double) {
        raw = value
        if abs(raw - lightness) > 0.03 {
            pendingFrames += 1
            if pendingFrames >= 2 {
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

    /// sRGB byte → linear light.
    private static let linear: [Double] = (0..<256).map { i in
        let c = Double(i) / 255.0
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
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

        var sum = 0.0
        let lut = Self.linear
        for y in 0..<height {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let p = x * 4                      // BGRA
                let lin = 0.0722 * lut[Int(row[p])] + 0.7152 * lut[Int(row[p + 1])] + 0.2126 * lut[Int(row[p + 2])]
                // CIE L* from relative luminance, normalized to 0…1
                let f = lin > 0.008856 ? cbrt(lin) : 7.787 * lin + 16.0 / 116.0
                let lStar = max(0.0, min(1.0, (116.0 * f - 16.0) / 100.0))
                sum += metric == .rms ? lStar * lStar : lStar
            }
        }
        let n = Double(width * height)
        let value = metric == .rms ? sqrt(sum / n) : sum / n
        onSample(value)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {}
}
