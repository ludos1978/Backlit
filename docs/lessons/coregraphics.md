# Lessons Learned — CoreGraphics

> Updated: 2026-03-05

## CoreGraphics / Displays

- In a Swift 6 class init, if some `@Published` properties are not yet initialized, you cannot use `self.anyProperty` before initialization completes (even if that property is assigned) → fix: store the value in a local variable and reference that
- `CGDisplayRegisterReconfigurationCallback` requires the callback to be a C function pointer (global func), not a closure → pass `Unmanaged.passUnretained(self).toOpaque()` via `userInfo`
- `deinit` is nonisolated in Swift 6 and cannot access `@MainActor`-isolated properties → fix: mark properties needed in deinit as `nonisolated(unsafe)`
- If compilation reports "cannot find symbol" after adding a Swift source file, re-run `xcodegen generate` to regenerate the xcodeproj (even if project.yml uses a glob, an old xcodeproj may not include the new file)
- The macOS 26.2 SDK replaces C functions such as `CGDisplayModeGetWidth/Height/PixelWidth/PixelHeight/RefreshRate/IODisplayModeID` with Swift properties (`mode.width`, `mode.pixelWidth`, `mode.ioDisplayModeID`, etc.) and methods (`mode.isUsableForDesktopGUI()`) → with the new SDK use property syntax directly and avoid deprecated functions
- `kCGDisplayShowDuplicateLowResolutionModes: true` is the correct key name; passing it in the options dictionary of `CGDisplayCopyAllDisplayModes` shows HiDPI scaled modes
- `CGDisplayCopyColorSpace` returns a non-Optional `CGColorSpace` in the macOS 26 SDK (the old SDK returned Optional) → guard let must become a direct call, and use `colorSpace.name` to get the name (`CGColorSpaceCopyName` was replaced by a property)
- `CGDisplayMode.pixelEncoding` is `CFString?` (not `String`) and must be bridged manually: `if let cfEnc = mode.pixelEncoding { encoding = cfEnc as String }`
- ColorSync global constants (`kColorSyncDisplayDeviceClass`, `kColorSyncDeviceDefaultProfileID`) are of type `Unmanaged<CFString>?` in Swift 6, and global var access gives concurrency-safety warnings → suppress concurrency errors with `@preconcurrency import ColorSync`; borrow the reference with `.takeUnretainedValue()` when accessing (do not use `takeRetainedValue`, to avoid a double release)
- `kColorSyncProfileUseSystemSequence` does not exist in the public ColorSync headers → resetting to the system default profile cannot be done through public interfaces, so skip resetProfile
- After adding a Swift source file you must re-run `xcodegen generate` to regenerate the xcodeproj, otherwise the compiler does not know the new file ("cannot find in scope" error)

## HiDPI / Resolution

- After `HiDPIService` writes the display override plist, macOS does not load the new modes immediately → need to trigger display re-enumeration (`CGDisplayForceToMirror` or `IOServiceRequestProbe`)
- `isUsableForDesktopGUI()` filters out some resolution modes, making certain resolutions "invisible" → may need to bypass this filter

### L-006: Plist injection on macOS 14+ cannot enable HiDPI dynamically
- **Symptom**: After writing the display override plist + IOServiceRequestProbe, the HiDPI mode does not appear on a 2K external display
- **Cause**: macOS Ventura/Sonoma does not dynamically re-enumerate plist-injected modes for already connected displays. The plist approach only works when the display is first connected
- **Fix**: Use the private CGVirtualDisplay API to create a 3840x2160 virtual display (hiDPI=1), then mirror the physical display to the virtual display; macOS then automatically offers HiDPI modes such as 1920x1080@2x
- **Lesson**: The core of BetterDisplay's HiDPI approach is "virtual display + mirroring", not plist injection
- **Date**: 2026-03-03

### L-007: NSWindow.isReleasedWhenClosed defaults to true
- **Symptom**: The app crashes/hangs when the notch overlay is closed
- **Cause**: NSWindow defaults to `isReleasedWhenClosed = true`; after close() the window is released immediately by ARC and the reference in the dictionary becomes a dangling pointer
- **Fix**: Set `isReleasedWhenClosed = false` immediately after creating the NSWindow
- **Lesson**: The other windows in the project (PiPWindow, StreamWindow, VideoFilterWindow) all set this property correctly; only NotchOverlayManager missed it
- **Date**: 2026-03-03

## CGVirtualDisplay / Virtual Displays

- `CGVirtualDisplay`, `CGVirtualDisplayDescriptor`, `CGVirtualDisplaySettings`, `CGVirtualDisplayMode` are private CoreGraphics SPI. Although the symbols are exported in the TBD file (`grep CGVirtualDisplay CoreGraphics.tbd`), they are not declared in the public C/ObjC headers or Swift interface files of the macOS 26 SDK → referencing them directly from Swift reports a "cannot find type in scope" error
- BetterDisplay/BetterDummy use these classes by declaring the private interface headers themselves (bridging header) → this is private API usage, and the project must explicitly decide whether to accept this risk
- If asked to resolve this before continuing, read BLOCKING.md B-002 first

### L-020: CGVirtualDisplay vendorID must be non-zero
- **Symptom**: `CGVirtualDisplay(descriptor:)` always returns nil with no error
- **Cause**: `vendorID = 0` is rejected by WindowServer; the node-mac-virtual-display project uses `0xEEEE`
- **Fix**: Set `vendorID = 0xEEEE`, `productID = 0x0001`, `serialNum = 0x0001`
- **Lesson**: Implicit constraints of private APIs are undocumented; refer to known working open-source implementations
- **Date**: 2026-03-04

### L-021: CGVirtualDisplay(descriptor:) must be on the main thread
- **Symptom**: Calling from a background DispatchQueue returns nil; calling from the main thread succeeds
- **Cause**: WindowServer IPC requires CGVirtualDisplay initialization on the main thread
- **Fix**: Descriptor construction + init on @MainActor; `apply(settings)` and `enableMirror` run in the background via `runWithTimeout`
- **Lesson**: Different methods of the same API may have different threading requirements
- **Date**: 2026-03-04

### L-022: Bridging header property names must exactly match the runtime API
- **Symptom**: `-[CGVirtualDisplayDescriptor setMaxPixelSize:]: unrecognized selector` causes a crash
- **Cause**: The bridging header declared `maxPixelSize` (CGSize), but the actual properties are `maxPixelsWide`/`maxPixelsHigh` (uint32_t)
- **Fix**: Use Chromium's `virtual_display_mac_util.mm` as the authoritative reference and verify property names one by one
- **Lesson**: Do not guess property names in private API bridging headers; refer to reverse engineering or known working implementations
- **Date**: 2026-03-04

### L-023: HiDPI virtual display configs must not autoCreate
- **Symptom**: Stale virtual displays pile up on every app restart (displayID=7,8,9,10...) and creation eventually fails
- **Cause**: The HiDPI config was stored in the configs array with `autoCreate: true`, but autoCreate only creates the virtual display without mirroring, leaving useless virtual displays piling up
- **Fix**: Make HiDPI config purely runtime (`autoCreate: false`, not stored in configs) and clean up leftovers at startup
- **Lesson**: Configs that depend on runtime state (such as mirror relationships) should not be rebuilt automatically, because key context is missing after rebuilding
- **Date**: 2026-03-04

### L-024: CGDisplayMirrorsDisplay() detection is unreliable
- **Symptom**: Switching resolution in HiDPI mode fails; `CGDisplayMirrorsDisplay(physicalID)` returns `kCGNullDirectDisplay`
- **Cause**: macOS's mirror detection API does not always recognize mirror relationships set via `CGConfigureDisplayMirrorOfDisplay`
- **Fix**: Add `VirtualDisplayService.virtualDisplayID(for:)` as a fallback in `resolvedTargetDisplayID()`
- **Lesson**: System API behavior may differ from the documentation; have a fallback
- **Date**: 2026-03-04

### L-025: HiDPI approach choice — mirroring is a dead end, plist override is the way
- **Symptom**: Using CGConfigureDisplayMirrorOfDisplay to create a virtual display → mirror it to the external display to get HiDPI modes triggered the system "screen mirroring" UI + mouse stutter across displays + pure mirror mode
- **Cause**: Apple Silicon's WindowServer strictly manages hardware mirroring, and CGConfigureDisplayMirrorOfDisplay triggers the full mirroring reconfiguration flow
- **Fix**: Switch to a plist override (write to /Library/Displays/Contents/Resources/Overrides/), which is BetterDisplay's approach. Requires administrator privileges (NSAppleScript "with administrator privileges"); takes effect after reconnecting the display
- **Lesson**: Do not use CGConfigureDisplayMirrorOfDisplay for HiDPI; it is a dead end on Apple Silicon

### L-026: Loading private framework symbols — dlsym, not @_silgen_name
- **Symptom**: Declaring a private function with @_silgen_name("CoreDisplay_Display_GetUserBrightness") compiles but fails to link (undefined symbol)
- **Cause**: @_silgen_name requires the symbol to be visible at link time, and CoreDisplay is a private framework not on the default link path
- **Fix**: Load at runtime with dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY) + dlsym
- **Lesson**: Always use dlopen+dlsym for private framework symbols; do not use @_silgen_name

### L-027: display.pixelWidth is the current resolution, not the native resolution
- **Symptom**: The scale-resolutions of the HiDPI plist override is an empty array
- **Cause**: display.pixelWidth/pixelHeight (from CGDisplayPixelsWide/High) were passed as the native resolution, but the display may currently be at a non-native resolution
- **Fix**: Use display.availableModes.max(by: width*height) to get the largest available mode as the native resolution
- **Lesson**: CGDisplayPixelsWide/High return the pixel size of the current mode, not the panel's physical resolution

### L-028: Gamma ramp lost on projectors (mode change / display ID / unsupported outputs)
- **Symptom**: image adjustments (gamma, contrast…) not applied on some projectors
- **Causes**: (1) a mode change (`setModeFlag`, common right after a projector connects) makes ColorSync reload the profile and reset the gamma ramp, and only *added* displays were re-applied; (2) ColorSync loads the profile asynchronously, so a single write 300 ms after connect can be overwritten; (3) saved adjustments were keyed by `CGDirectDisplayID`, which is not stable per screen (port / connection order); (4) AirPlay / Sidecar / DisplayLink outputs have no gamma ramp at all — `CGSetDisplayTransfer*` fails there
- **Fix**: `DisplayManager.scheduleImageStateReapply` re-applies at 0.3 s and 2 s after connect *and* after mode changes; gamma state keyed by display UUID (legacy ID key migrated); GammaService checks the `CGError` + `CGDisplayGammaTableCapacity` and the Image Adjustment panel shows a warning when writes fail
- **Lesson**: never assume a gamma write sticks — re-apply after every reconfiguration, key per-display state by UUID, and check the return value

### L-029: Never auto-create virtual displays (launch / first menu open)
- **Symptom**: "starting Backlit changes the resolution"
- **Cause**: saved virtual displays with `autoCreate: true` were re-created when VirtualDisplayService first loaded (the first menu open after launch). Adding a display makes macOS re-fit the physical screens; it can apply a remembered mirror set (built-in mirroring the 1920×1080 virtual display at 1920×1080) or pick new modes
- **Fix**: auto-create removed; `autoCreate` is decoded but ignored, virtual displays are only created by an explicit click
- **Lesson**: anything that adds or removes a display is a resolution/layout change — only on direct user action
