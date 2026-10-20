# Lessons Learned — IOKit

> Updated: 2026-03-05

## IOKit / DDC

- In the CF dictionary returned by `IODisplayCreateInfoDictionary`, `DisplayVendorID` and `DisplayProductID` are of type `Int` (not `UInt32`); try a UInt32 cast first, then an Int cast
- `IODisplayCreateInfoDictionary` returns `Unmanaged<CFDictionary>?`; use `.takeRetainedValue()` to get the value (ARC managed)
- The matching parameter of `IOServiceGetMatchingServices` consumes the CFDictionary reference; no manual release needed
- The IOKit I2C submodule is an `explicit module` and is not included by `import IOKit` → need `import IOKit.i2c` (I2C functions) and `import IOKit.graphics` (IODisplay*FloatParameter functions)
- `IOI2CRequest` is inside a `#pragma pack(push, 4)` struct; the `sendTransactionType`/`replyTransactionType` fields are of type `IOOptionBits` (UInt32, not UInt8)
- `kIODisplayBrightnessKey` is a `#define "brightness"`; Swift does not auto-bridge string macros → use `"brightness" as CFString` directly
- Swift's `Array.withUnsafeMutableBytes` holds an exclusive mutable borrow, so the original array cannot be subscripted inside the closure → read data through a raw buffer pointer (`replyRaw.bindMemory(to: UInt8.self)`), or capture `.count` before the closure
- `IOFBCopyI2CInterfaceForBus(framebuffer, busIndex, &interface)` is a cleaner API than manually looking up IOFramebufferI2CInterface child nodes; recommended
- If a `BrightnessService` method accesses `@MainActor`-isolated `DisplayInfo` properties, it must be marked `@MainActor`; the actual DDC I/O runs asynchronously on DDCService's internal ddcQueue and does not block the MainActor

## IOKit / Screen Rotation (Phase 4)

- `CGDisplayIOServicePort` is completely **unavailable** (not just deprecated) in the latest macOS SDK and fails to compile; use IOKit registry traversal instead
- Replacement: iterate `IODisplayConnect` → match by vendor/model → `IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent)` to get the IOFramebuffer (exactly the same pattern as DDCService.framebufferService)
- Screen rotation: `IORegistryEntrySetCFProperty(fb, "IOFBTransform", NSNumber(value: index))` + `IOServiceRequestProbe(fb, 0x00000400)` to trigger; rotation index = 0/1/2/3 corresponds to 0°/90°/180°/270°
- `import IOKit.graphics` is required for the graphics constants needed by `IOServiceRequestProbe`

## IOKit / Ambient Light Sensor (Phase 11)

- `AppleLMUController` is an IOKit service obtained via `IOServiceGetMatchingService`; after opening a connection with `IOServiceOpen`, read the two-channel (left/right) sensor UInt64 values with `IOConnectCallMethod(port, 0, nil, 0, nil, 0, &output, &outputCount, nil, &outputStructSize)`
- The struct size parameter of `IOConnectCallMethod` is `Int` (size_t = Int in Swift) and cannot be `nil` → must pass `0` or a pointer to a variable (`&outputStructSize`)
- After creating a new Swift file, if other files reference types in it, you must first run `xcodegen generate` to regenerate the xcodeproj, otherwise "cannot find in scope"
- When a `@MainActor` class's `init` accesses properties of another `@MainActor` class, the `init` must also be marked `@MainActor`, otherwise Swift 6 strict concurrency reports an error

## IOKit Display Matching (Phase 13-15)

### L-003: vendor+model IOKit matching is unreliable
- **Symptom**: DisplayInfo name shows "Display 2", DDC brightness slider has no effect
- **Cause**: The values returned by CGDisplayVendorNumber/ModelNumber do not always match IOKit DisplayVendorID/DisplayProductID (at least not on the HKC H2435Q), so IODisplayConnect service matching fails
- **Fix**: Use NSScreen.localizedName for the name (system API, most reliable); use CGDisplayIOServicePort for IOKit service lookup (deprecated but still usable)
- **Lesson**: Do not assume different frameworks (CoreGraphics vs IOKit) use the same identifiers for the same hardware. Prefer system-level APIs (NSScreen) over low-level IOKit lookups
- **Date**: 2026-03-03

### L-004: Do not make microsecond-level operations async
- **Symptom**: In Phase 14, DisplayInfo.init's name lookup was made async, so users saw "Display N" flash before updating to the real name (sometimes never updating)
- **Cause**: IOKit name lookup takes only microseconds; making it async introduced a race condition (refreshDisplays may be called multiple times, and a later call overwrites an earlier call's async result)
- **Fix**: Rolled back to a synchronous call
- **Lesson**: async only pays off for genuinely slow operations (>100ms). Making microsecond-level operations async only adds complexity and bugs
- **Date**: 2026-03-03

## Apple Silicon DDC (Phase 17)

### L-005: The IOFramebuffer I2C API does not work at all on Apple Silicon
- **Symptom**: DDC brightness/contrast control has no effect on any external display
- **Cause**: `IOFBCopyI2CInterfaceForBus` / `IOI2CSendRequest` are Intel-era IOFramebuffer APIs; on Apple Silicon (M1/M2/M3/M4) these calls return silently without sending any I2C data
- **Fix**: Use the private IOAVService API (`IOAVServiceCreateWithService` + `IOAVServiceWriteI2C` / `IOAVServiceReadI2C`), finding external displays through the DCPAVServiceProxy IOKit service
- **Lesson**: macOS on different CPU architectures uses completely different display communication APIs. MonitorControl and BetterDisplay both use IOAVService. See alinpanaitiu.com/blog/journey-to-ddc-on-m1-macs/
- **Date**: 2026-03-03

## Built-in brightness on Apple Silicon (2026-09-07)

- `IODisplayGetFloatParameter` / `IODisplaySetFloatParameter` on IODisplayConnect **silently
  fail on Apple Silicon** (no IODisplayConnect services) — same root cause as the DDC B-003
  issue. Built-in brightness must use the DisplayServices private framework via dlsym:
  `DisplayServicesGetBrightness(id, &float)` / `DisplayServicesSetBrightness(id, float)` /
  `DisplayServicesCanChangeBrightness(id)` (rc 0 = success; verified by set+readback).
- `com.apple.universalaccess` is a **TCC-protected preference domain**: CFPreferences writes
  from an app without Full Disk Access fail silently, and even successful writes are not
  applied live by universalaccessd. Use the private SPI instead:
  `UAIncreaseContrastSetEnabled(Bool)` / `UAIncreaseContrastIsEnabled()` (UniversalAccess.framework)
  and `CGSSetDisplayContrast(Float)` (SkyLight, 0 = normal, ~1 = max, global).

## DDC AVService ↔ display mapping on Apple Silicon (2026-09-10)

- **Symptom**: with two identical monitors (2× DELL U3225QE) the log said "index fallback mapped
  AVService[0] to display 2, AVService[1] to display 5" — the assignment was arbitrary, so DDC
  brightness (sliders, adaptive brightness, presets) could land on the wrong monitor.
- **Why the old matching failed**: `DCPAVServiceProxy` and all of its ancestors
  (AFKEPInterface… → DCPEndpoint → RTBuddy → AppleASCWrap → AppleT602xIO) carry no
  `DisplayVendorID`/`DisplayProductID` at all, and vendor/product cannot tell two identical
  monitors apart anyway.
- **Where the identity actually lives**:
  1. The DCP endpoint of the proxy, `RTBuddy(DCPEXTn)` (5 levels up), has a sibling branch
     `AppleDCPDPTXRemotePortUFP(iop-dcpextN-nub)` whose `DisplayHints["EDID UUID"]` names the
     connected monitor (raw EDID header bytes: vendor big-endian, product little-endian, serial,
     week/year, …).
  2. `IOMobileFramebufferShim` under `dispextN` publishes the same `EDID UUID` (also as
     `IOMFBUUID`) plus `DisplayAttributes/ProductAttributes` with `LegacyManufacturerID`,
     `ProductID`, `SerialNumber`, `AlphanumericSerialNumber`, `WeekOfManufacture`, …
  3. `CGDisplaySerialNumber(id)` equals that `SerialNumber`; `CGDisplayVendorNumber` /
     `CGDisplayModelNumber` equal `LegacyManufacturerID` / `ProductID`.
- **Implementation** (`DDCService.buildAVServiceMap`): walk up from the proxy, search each
  ancestor's subtree for `DisplayHints` until exactly one EDID UUID is found (more than one
  means shared plumbing → stop), look up the shim with that UUID, then pick the CG display with
  the same vendor + product + serial. Fallbacks: model-only when unique, legacy ancestor
  vendor/product keys, and finally sorted-index assignment with `mappingWarning`.
- **Not usable**: `CGDisplayCreateUUIDFromDisplayID` returns a CG-generated UUID
  (e.g. `C3C64FBC-…`) that appears nowhere in the IORegistry, so it cannot be used as the link.
