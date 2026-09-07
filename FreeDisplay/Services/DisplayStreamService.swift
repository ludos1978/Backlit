import AppKit
import AVFoundation
import CoreGraphics
import ScreenCaptureKit

/// Shows a display's live content in a floating window on another screen —
/// the way to actually see a (headless) virtual display. Uses ScreenCaptureKit
/// (needs the Screen Recording permission; nothing leaves the machine) and
/// renders frames through an AVSampleBufferDisplayLayer.
@MainActor
final class DisplayStreamService: ObservableObject, @unchecked Sendable {
    static let shared = DisplayStreamService()

    /// Display IDs that currently have a stream window open.
    @Published private(set) var openDisplayIDs: Set<CGDirectDisplayID> = []
    /// Last error (permission missing, display gone, …) for the UI to show.
    @Published var lastError: String?

    private var windows: [CGDirectDisplayID: DisplayStreamWindow] = [:]

    private init() {}

    func isShowing(_ displayID: CGDirectDisplayID) -> Bool {
        openDisplayIDs.contains(displayID)
    }

    /// Opens (or closes, if already open) the stream window for a display.
    func toggleWindow(for displayID: CGDirectDisplayID, title: String) {
        if isShowing(displayID) {
            close(displayID)
        } else {
            open(displayID, title: title)
        }
    }

    func open(_ displayID: CGDirectDisplayID, title: String) {
        guard windows[displayID] == nil else { return }
        lastError = nil
        let window = DisplayStreamWindow(displayID: displayID, title: title) { [weak self] in
            Task { @MainActor in self?.windowDidClose(displayID) }
        }
        windows[displayID] = window
        openDisplayIDs.insert(displayID)
        window.show()
        Task { @MainActor in
            do {
                try await window.startStreaming()
            } catch {
                self.lastError = Self.describe(error)
                self.close(displayID)
            }
        }
    }

    func close(_ displayID: CGDirectDisplayID) {
        guard let window = windows[displayID] else { return }
        window.stopStreaming()
        window.close()          // triggers windowDidClose via the callback
        windowDidClose(displayID)
    }

    private func windowDidClose(_ displayID: CGDirectDisplayID) {
        windows[displayID]?.stopStreaming()
        windows.removeValue(forKey: displayID)
        openDisplayIDs.remove(displayID)
    }

    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        // SCStreamErrorUserDeclined / TCC denial
        if ns.domain == SCStreamError.errorDomain && ns.code == SCStreamError.userDeclined.rawValue
            || ns.localizedDescription.localizedCaseInsensitiveContains("permission") {
            return "Screen Recording permission is required (System Settings → Privacy & Security → Screen Recording)."
        }
        return "Could not stream this display: \(ns.localizedDescription)"
    }
}

// MARK: - Stream window

/// Resizable, aspect-locked window that renders a ScreenCaptureKit stream of
/// one display. Placed on a physical screen (never on the streamed display
/// itself, which would show an infinite mirror).
final class DisplayStreamWindow: NSWindow, NSWindowDelegate, @unchecked Sendable {
    private let displayID: CGDirectDisplayID
    private let onClose: () -> Void
    private let videoLayer = AVSampleBufferDisplayLayer()
    private var stream: SCStream?
    private var output: StreamOutput?
    private let sampleQueue = DispatchQueue(label: "com.freedisplay.displaystream", qos: .userInteractive)

    init(displayID: CGDirectDisplayID, title: String, onClose: @escaping () -> Void) {
        self.displayID = displayID
        self.onClose = onClose

        let pixelW = max(1, CGDisplayPixelsWide(displayID))
        let pixelH = max(1, CGDisplayPixelsHigh(displayID))
        // Initial window: ~40% of the host screen width, keeping the display's aspect ratio.
        let host = Self.hostScreen(excluding: displayID)
        let hostFrame = host?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(hostFrame.width * 0.4, 960)
        let height = width * CGFloat(pixelH) / CGFloat(pixelW)
        let origin = NSPoint(x: hostFrame.midX - width / 2, y: hostFrame.midY - height / 2)

        super.init(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.title = "Virtual Display — \(title)"
        isReleasedWhenClosed = false
        contentAspectRatio = NSSize(width: pixelW, height: pixelH)
        minSize = NSSize(width: 240, height: 240 * CGFloat(pixelH) / CGFloat(pixelW))
        level = .floating
        collectionBehavior = [.fullScreenAuxiliary, .managed]
        setFrameAutosaveName("fd.displayStream.\(displayID)")
        delegate = self

        let content = NSView(frame: contentRect(forFrameRect: frame))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        videoLayer.videoGravity = .resizeAspect
        videoLayer.backgroundColor = NSColor.black.cgColor
        videoLayer.frame = content.bounds
        videoLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        content.layer?.addSublayer(videoLayer)
        contentView = content
    }

    /// A physical screen to host the window — never the streamed display.
    private static func hostScreen(excluding displayID: CGDirectDisplayID) -> NSScreen? {
        let others = NSScreen.screens.filter { $0.displayID != displayID }
        return others.first(where: { $0 == NSScreen.main }) ?? others.first
    }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Streaming

    func startStreaming() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "FreeDisplay.DisplayStream", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "the display is no longer available"])
        }
        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = max(1, CGDisplayPixelsWide(displayID))
        config.height = max(1, CGDisplayPixelsHigh(displayID))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.queueDepth = 5

        let output = StreamOutput(layer: videoLayer) { [weak self] in
            // Stream stopped on its own (display removed, permission revoked…): close the window.
            Task { @MainActor in self?.close() }
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
        self.output = output
        self.stream = stream
        try await stream.startCapture()
    }

    func stopStreaming() {
        guard let stream else { return }
        self.stream = nil
        self.output = nil
        Task { try? await stream.stopCapture() }
        videoLayer.flushAndRemoveImage()
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        stopStreaming()
        onClose()
    }
}

/// Receives ScreenCaptureKit frames on a background queue and hands them to the
/// display layer (whose enqueue is thread-safe).
private final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let layer: AVSampleBufferDisplayLayer
    private let onStopped: () -> Void

    init(layer: AVSampleBufferDisplayLayer, onStopped: @escaping () -> Void) {
        self.layer = layer
        self.onStopped = onStopped
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        // Only complete frames carry image data; skip idle/blank status frames.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let statusRaw = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: statusRaw), status != .complete {
            return
        }
        if layer.status == .failed {
            layer.flush()
        }
        layer.enqueue(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStopped()
    }
}
