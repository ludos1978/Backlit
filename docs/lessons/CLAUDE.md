# Lessons Learned Index — Backlit

> Updated: 2026-03-05

## Topic Index

| Topic | File | Entries |
|------|------|------|
| IOKit / DDC / Rotation / Ambient Light / Display Matching / Apple Silicon | [iokit.md](iokit.md) | L-003, L-004, L-005 + general entries |
| CoreGraphics / HiDPI / CGVirtualDisplay / Gamma | [coregraphics.md](coregraphics.md) | L-006, L-007, L-020 ~ L-028 + general entries |
| SwiftUI / MenuBarExtra / UI Animation / DDC Cache / Performance | [swiftui.md](swiftui.md) | general entries |
| Cross-Service Coordination / Concurrency / Resource Management | [services.md](services.md) | L-008 ~ L-019 |
| Xcode Build / Phase Wrap-up | [build.md](build.md) | general entries |

## Permanent Rules (Frequent Pitfalls)

1. **After adding a Swift source file you must run `xcodegen generate`** — otherwise the compiler does not know the new file ("cannot find in scope")
2. **Two Services must not each write the same CoreGraphics resource** — designate a single writer; others influence it through its interface (see services.md L-008)
3. **Always pass self to C callbacks with `Unmanaged.passRetained`, and pair it with release on unregister** — passUnretained is a dangling-pointer time bomb
4. **❌ CGConfigureDisplayMirrorOfDisplay for HiDPI** — triggers hardware mirroring + mouse stutter on Apple Silicon, ✅ use plist override (/Library/Displays/)
