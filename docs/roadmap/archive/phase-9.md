# Phase 9: Screen Streaming and Picture-in-Picture ✅

> Core value: BetterDisplay's most advanced feature - stream the screen to a window + floating picture-in-picture window

## Task List

- [x] Implement the screen capture engine (`Backlit/Services/ScreenCaptureService.swift`)
  - Implementation hints:
    Use ScreenCaptureKit (macOS 12.3+):
    ```swift
    import ScreenCaptureKit

    // 1. Get shareable content
    let content = try await SCShareableContent.current
    let display = content.displays.first { $0.displayID == targetDisplayID }

    // 2. Create the filter and configuration
    let filter = SCContentFilter(display: display!, excludingWindows: [])
    let config = SCStreamConfiguration()
    config.width = Int(display!.width)
    config.height = Int(display!.height)
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60) // 60fps
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.showsCursor = true

    // 3. Create and start the stream
    let stream = SCStream(filter: filter, configuration: config, delegate: self)
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
    try await stream.startCapture()
    ```
    Output `CMSampleBuffer` -> convert to `CIImage` -> pass to the view layer for rendering.
    Requires screen recording permission: an authorization dialog pops up on first use.
  - Verify: after starting capture, display frames can be obtained

- [x] Implement the stream window (`Backlit/Views/StreamWindow.swift`)
  - Implementation hints:
    Create a standalone NSWindow to show the captured frames:
    - `NSWindow(contentRect:, styleMask: [.titled, .closable, .resizable], ...)`
    - Content uses `MetalView` (MTKView) or `CAMetalLayer` for high-performance rendering of CMSampleBuffer
    - Or use SwiftUI `Image` converted from CIImage (lower performance, but simple)
    Recommended Metal rendering path:
    ```swift
    class MetalStreamView: MTKView {
        // CMSampleBuffer -> CVPixelBuffer -> MTLTexture -> render
    }
    ```
    Window support: scale content proportionally when resized.
  - Verify: the stream window shows the target display's frames in real time

- [x] Implement stream options (`Backlit/ViewModels/StreamViewModel.swift`)
  - Implementation hints: following the screen streaming area of the BetterDisplay screenshot, implement these options:
    - Show mouse cursor: `config.showsCursor = true/false`
    - 1:1 pixel mapping: window size = capture resolution
    - Integer scaling: window width/height can only be integer multiples/fractions of the capture resolution
    - Free aspect ratio: allow non-proportional scaling
    - Video filters: process frames with CIFilter (grayscale, blur, sharpen, etc.)
    - Enable cropping: show only part of the captured frame in the window (user can drag the crop box)
    - Flip (horizontal/vertical): CIFilter `CIAffineTransform`
    - Rotate (0°/90°/180°/270°): CIFilter `CIAffineTransform`
    - Zoom slider (0.1x~4.0x)
    - Underscan slider (percentage of edge cropping)
    - Opacity slider (`window.alphaValue`)
    - "Restore stream on connect": persisted via UserDefaults
  - Verify: the stream output actually changes after toggling each option

- [x] Implement picture-in-picture (`Backlit/Views/PiPWindow.swift`)
  - Implementation hints:
    Picture-in-picture = a smaller floating stream window + extra control options.
    Extend StreamWindow, adding:
    - Window level: normal / above other windows / above the menu bar
      `window.level = .normal / .floating / .statusBar + 1`
    - Show/hide title bar: `window.styleMask.insert/remove(.titled)`
    - Not movable: `window.isMovable = false`
    - Disable resizing: `window.styleMask.remove(.resizable)`
    - Snap to 25% increments: after dragging ends, snap to the nearest 25% screen-width position
    - Mouse click-through: `window.ignoresMouseEvents = true`
    - Window shadow: `window.hasShadow = true/false`
    - Exclude the PiP window (not captured by itself): the `excludingWindows` parameter of ScreenCaptureKit
  - Verify: the PiP window floats above other windows, and each option works

- [x] Implement the stream/PiP menu UI (`Backlit/Views/StreamControlView.swift`, `PiPControlView.swift`)
  - Implementation hints:
    Two expandable sections: "Screen Streaming" and "Picture-in-Picture", following the BetterDisplay screenshot.
    Streaming area: target selection list + stop button + all option toggles/sliders
    PiP area: enable/auto-start + level selection + all option toggles/sliders + flip/rotate button group
    Bottom buttons: "Add Stream Configuration"/"Add PiP Settings" (supports multiple simultaneous streams/PiPs)
  - Verify: the UI matches the BetterDisplay screenshot exactly

## Phase Acceptance

- Screen streaming shows the target display in real time with a smooth frame rate
- All stream options (cursor, zoom, rotation, crop, filter, opacity) work
- The PiP floating window is topmost, and all PiP options work
- Multiple streams/PiPs can run simultaneously
- The UI matches the BetterDisplay screenshot

**After completion**: running project-optimize for reflection is recommended
