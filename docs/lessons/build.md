# Lessons Learned — Xcode / Build

> Updated: 2026-03-05

## Xcode / Build

- xcodegen does not auto-generate Info.plist → must set in project.yml: `GENERATE_INFOPLIST_FILE: YES`
- ScreenCaptureKit (`SCShareableContent.current`)called in a `@MainActor` context reports a non-Sendable error (even with `SWIFT_STRICT_CONCURRENCY: minimal`) → fix: `@preconcurrency import ScreenCaptureKit`
- Swift 6 strict concurrency a singleton reports a Sendable error → mark the class `@unchecked Sendable` + set in project: `SWIFT_STRICT_CONCURRENCY: minimal`

## Phase 12 / Wrap-up

- After adding Service/View files, you must run `xcodegen generate` to regenerate the xcodeproj, otherwise other files referencing the new types report "cannot find in scope"
- If a Services file uses `CGDirectDisplayID`, it needs `import CoreGraphics` (`import Foundation` alone is not enough)
- `NSWorkspace.shared` needs `import AppKit` (Foundation alone is not enough)
- `NSObject` subclass as a singleton: Swift 6 reports a non-Sendable warning → fix by marking `@unchecked Sendable`
- `SMAppService`(launch at login) is available on macOS 13+, needs `import ServiceManagement`
