# Phase 17: Core Feature Fixes - DDC/HiDPI/Notch

> Goal: fix three technical issues affecting the core experience: Apple Silicon DDC brightness control unavailable, HiDPI virtual display creation failing on external 2K displays, and the notch overlay NSWindow crash

## Prerequisites

This Phase involves a private API bridging header and the rewrite of two low-level services, so tasks have a dependency order:
**Task 1 (bridging header) must precede Tasks 2 and 3**; Task 4 (notch crash) is independent and can start in parallel with Task 1; Task 5 (integration test) comes last.

---

## Task List

- [x] **Task 1**: Create the Objective-C Bridging Header (shared prerequisite for DDC + virtual display private APIs)
  - Implementation hints:
    1. Create `Backlit/Backlit-Bridging-Header.h` in the project root, declaring the following:

       ```objc
       // ── CGVirtualDisplay private classes (macOS 14+ virtual displays) ──────────────────────
       #import <Foundation/Foundation.h>
       #import <CoreGraphics/CoreGraphics.h>

       @interface CGVirtualDisplayDescriptor : NSObject
       @property (nonatomic) uint32_t sizeInMillimeters;   // Diagonal size (millimeters)
       @property (nonatomic) CGSize   maxPixelSize;        // Maximum pixel resolution
       @property (nonatomic) CGColorSpaceRef colorSpace;
       @property (nonatomic) NSPoint  whitePoint;
       @property (nonatomic) NSPoint  redPrimary;
       @property (nonatomic) NSPoint  greenPrimary;
       @property (nonatomic) NSPoint  bluePrimary;
       @end

       @interface CGVirtualDisplaySettings : NSObject
       @property (nonatomic) BOOL hiDPI;
       - (void)addMode:(CGSize)size refreshRate:(double)hz;
       @end

       @interface CGVirtualDisplayMode : NSObject
       @property (nonatomic, readonly) CGSize  size;
       @property (nonatomic, readonly) double  refreshRate;
       @property (nonatomic, readonly) BOOL    hiDPI;
       @end

       @interface CGVirtualDisplay : NSObject
       - (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
       - (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
       @property (nonatomic, readonly) CGDirectDisplayID displayID;
       @end

       // ── CGSDisplayMode (advanced resolution switching) ──────────────────────────────────────
       typedef struct {
           uint32_t modeID;
           uint32_t width;
           uint32_t height;
           uint32_t depth;
           double   refreshRate;
           uint32_t flags;        // bit 0x20000 = HiDPI
       } CGSDisplayMode;

       extern CGError CGSConfigureDisplayMode(CGSConnectionID connection, CGDirectDisplayID display, uint32_t modeID);
       extern CGSConnectionID CGSMainConnectionID(void);

       // ── CoreDisplay (optional, for future reference) ────────────────────────────────────────
       // extern CFDictionaryRef CoreDisplay_DisplayCreateInfoDictionary(CGDirectDisplayID display);

       // ── IOAVService (Apple Silicon DDC) ──────────────────────────────────────
       typedef void * IOAVServiceRef;
       extern IOAVServiceRef IOAVServiceCreate(CFAllocatorRef allocator);
       extern IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
       extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service,
                                          uint32_t chipAddress,
                                          uint32_t offset,
                                          void *outputBuffer,
                                          uint32_t outputBufferSize);
       extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service,
                                           uint32_t chipAddress,
                                           uint32_t dataAddress,
                                           void *inputBuffer,
                                           uint32_t inputBufferSize);
       ```

    2. Open `project.yml` and add under `targets.Backlit.settings.base`:
       ```yaml
       SWIFT_OBJC_BRIDGING_HEADER: Backlit/Backlit-Bridging-Header.h
       ```
    3. Run `cd ~/Desktop/Backlit && xcodegen generate`
    4. Run the verification chain to confirm it builds (an unused bridging header should not cause errors)
  - Verify: `xcodebuild -scheme Backlit -configuration Debug build 2>&1 | tail -5` shows `BUILD SUCCEEDED`

---

- [x] **Task 2**: Rewrite DDCService to support Apple Silicon (IOAVService path)
  - Background: the existing `IOFBCopyI2CInterfaceForBus` + `IOI2CSendRequest` are Intel-era APIs and do not work at all on Apple Silicon. An ARM64 path needs to be added, keeping the Intel path as a fallback (Hackintosh/VM users).
  - Implementation hints:
    1. **Add the ARM64 DDC write method** (`DDCService.swift`):
       ```swift
       // At the top of DDCService, ARM64-only path
       #if arch(arm64)
       private func findAVService(for displayID: CGDirectDisplayID) -> IOAVServiceRef? {
           // 1. Get the IOService for the display via CGDisplayIOServicePort
           let port = CGDisplayIOServicePort(displayID)
           guard port != IO_OBJECT_NULL else { return nil }

           // 2. Walk up the IORegistry parent nodes to find DCPAVServiceProxy
           var iterator: io_iterator_t = 0
           let matchDict = IOServiceMatching("DCPAVServiceProxy")
           IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator)
           defer { IOObjectRelease(iterator) }

           var service = IOIteratorNext(iterator)
           while service != IO_OBJECT_NULL {
               defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
               let avService = IOAVServiceCreateWithService(kCFAllocatorDefault, service)
               // Use a harmless read test to confirm it is the right AVService
               var testBuf = [UInt8](repeating: 0, count: 12)
               let ret = IOAVServiceReadI2C(avService, 0x37, 0x51, &testBuf, 12)
               if ret == kIOReturnSuccess { return avService }
           }
           return nil
       }

       /// ARM64 DDC write: Write a VCP value to the external display (e.g. brightness VCP=0x10)
       private func arm64Write(displayID: CGDirectDisplayID, command: UInt8, value: UInt16) -> Bool {
           guard let avService = findAVService(for: displayID) else { return false }
           // DDC/CI write packet format (note: dataAddress=0x51 is passed as a parameter, not placed in the buffer)
           // buffer: [0x84, 0x03, vcpCode, valueHigh, valueLow, checksum]
           let valueHigh = UInt8((value >> 8) & 0xFF)
           let valueLow  = UInt8(value & 0xFF)
           var checksum  = UInt8(0x50 ^ 0x03 ^ command ^ valueHigh ^ valueLow)
           // 0x50 = 0x51 XOR'd with 0x01 (reply flag) — see the DDC/CI spec
           var buf: [UInt8] = [0x84, 0x03, command, valueHigh, valueLow, checksum]
           let ret = IOAVServiceWriteI2C(avService, 0x37, 0x51, &buf, UInt32(buf.count))
           return ret == kIOReturnSuccess
       }

       /// ARM64 DDC read: Read the current VCP value
       private func arm64Read(displayID: CGDirectDisplayID, command: UInt8) -> (current: UInt16, max: UInt16)? {
           guard let avService = findAVService(for: displayID) else { return nil }
           // First send the VCP request packet (similar to write, opcode=0x01)
           var requestChecksum = UInt8(0x51 ^ 0x82 ^ 0x01 ^ command)
           var requestBuf: [UInt8] = [0x82, 0x01, command, requestChecksum]
           IOAVServiceWriteI2C(avService, 0x37, 0x51, &requestBuf, UInt32(requestBuf.count))
           // Wait for DDC processing
           Thread.sleep(forTimeInterval: 0.04)
           // Read the response
           var replyBuf = [UInt8](repeating: 0, count: 12)
           let ret = IOAVServiceReadI2C(avService, 0x37, 0x51, &replyBuf, 12)
           guard ret == kIOReturnSuccess else { return nil }
           // replyBuf format:[len, 0x02, vcpCode, 0x00, maxHigh, maxLow, curHigh, curLow, ...]
           let maxVal  = UInt16(replyBuf[4]) << 8 | UInt16(replyBuf[5])
           let curVal  = UInt16(replyBuf[6]) << 8 | UInt16(replyBuf[7])
           return (curVal, maxVal)
       }
       #endif
       ```

    2. **Modify the `write(displayID:command:value:)` dispatch logic**:
       ```swift
       func write(displayID: CGDirectDisplayID, command: UInt8, value: UInt16) -> Bool {
           #if arch(arm64)
           if arm64Write(displayID: displayID, command: command, value: value) {
               return true
           }
           // On arm64 failure, optionally fall back to the software path
           return false
           #else
           return intelWrite(displayID: displayID, command: command, value: value)
           #endif
       }
       ```
       Rename the existing Intel-path methods to `intelWrite` / `intelRead` (function signatures unchanged, rename only).

    3. **Add a software brightness fallback in `BrightnessService.swift`**:
       - Add a `var isDDCAvailable: [CGDirectDisplayID: Bool] = [:]` cache
       - In `setBrightness(for:value:)`: try a DDC write first; if it fails and the display is external, call `applyGammaFallback(displayID:brightness:)` to simulate brightness using `CGSetDisplayTransferByTable`
       - `applyGammaFallback` implementation: build a linear ramp from 0 to `brightness` (0.0-1.0) and write it to the gamma table, visually equivalent to lowering brightness (black level unchanged, white level reduced)
       - Record `isDDCAvailable[displayID] = false` so later calls go straight to the software path without trying DDC

    4. **Add a mode indicator in `BrightnessSliderView.swift`** (optional but recommended):
       - Add a small label next to the slider title: show "DDC" (blue) when DDC is available, "Software" (gray) in software mode
       - Implementation: read the state from `BrightnessService.shared.isDDCAvailable[display.id]`

  - File: `Backlit/Services/DDCService.swift` (add an `#if arch(arm64)` block, rename the existing Intel code)
  - File: `Backlit/Services/BrightnessService.swift` (add software fallback logic)
  - File: `Backlit/Views/BrightnessSliderView.swift` (optional: mode indicator label)
  - Reference: MonitorControl `Arm64DDC.swift`, the `m1ddc` project, alinpanaitiu.com/blog/journey-to-ddc-on-m1-macs/
  - Verify: drag the external display brightness slider -> the display's brightness actually changes (DDC succeeds); a display that does not support DDC -> automatically falls back to software dimming, the slider remains usable, and the label shows "Software"

---

- [x] **Task 3**: Implement real virtual display creation (CGVirtualDisplay API)
  - Background: `create(config:)` and `destroy(id:)` in `VirtualDisplayService.swift` currently only have placeholders returning `false`, making the HiDPI virtual display feature completely unusable. The implementation must use the `CGVirtualDisplay` private classes exposed by the bridging header.
  - Implementation hints:
    1. **Implement `create(config:)` in `VirtualDisplayService.swift`**:
       ```swift
       // Keep strong references; releasing = the virtual display disappears
       private var activeDisplayObjects: [CGDirectDisplayID: CGVirtualDisplay] = [:]

       func create(config: VirtualDisplayConfig) -> CGDirectDisplayID? {
           let descriptor = CGVirtualDisplayDescriptor()
           descriptor.sizeInMillimeters = 527  // 24-inch diagonal is about 527mm (adjustable per config)
           descriptor.maxPixelSize = CGSize(width: CGFloat(config.width), height: CGFloat(config.height))
           descriptor.colorSpace   = CGColorSpace(name: CGColorSpace.sRGB)!
           // sRGB gamut reference values
           descriptor.whitePoint   = NSPoint(x: 0.3127, y: 0.3290)
           descriptor.redPrimary   = NSPoint(x: 0.6400, y: 0.3300)
           descriptor.greenPrimary = NSPoint(x: 0.3000, y: 0.6000)
           descriptor.bluePrimary  = NSPoint(x: 0.1500, y: 0.0600)

           let settings = CGVirtualDisplaySettings()
           settings.hiDPI = config.hiDPI
           // Add the main mode (actual pixel size)
           settings.addMode(CGSize(width: CGFloat(config.width), height: CGFloat(config.height)),
                            refreshRate: Double(config.refreshRate))
           // If hiDPI, also add the logical resolution mode (half of physical)
           if config.hiDPI {
               settings.addMode(CGSize(width: CGFloat(config.width / 2),
                                       height: CGFloat(config.height / 2)),
                                refreshRate: Double(config.refreshRate))
           }

           let virtualDisplay = CGVirtualDisplay(descriptor: descriptor)
           guard virtualDisplay.applySettings(settings) else { return nil }
           let displayID = virtualDisplay.displayID
           guard displayID != kCGNullDirectDisplay else { return nil }
           activeDisplayObjects[displayID] = virtualDisplay  // Keep the strong reference
           return displayID
       }

       func destroy(id: CGDirectDisplayID) {
           activeDisplayObjects.removeValue(forKey: id)  // Release -> the virtual display disappears
       }
       ```

    2. **Implement `enableHiDPIVirtual(for:physicalWidth:physicalHeight:)`**:
       ```swift
       /// Create a 2x virtual display for the physical external display and mirror it, to achieve HiDPI scaling
       func enableHiDPIVirtual(for displayID: CGDirectDisplayID,
                                physicalWidth: Int,
                                physicalHeight: Int) -> CGDirectDisplayID? {
           let config = VirtualDisplayConfig(
               name: "HiDPI Virtual",
               width: physicalWidth * 2,   // 2x the physical resolution, e.g. 2K->4K
               height: physicalHeight * 2,
               refreshRate: 60,
               hiDPI: true
           )
           guard let virtualID = create(config: config) else { return nil }
           // Mirror the physical display to the virtual display (physical as mirror source, virtual as mirror target)
           MirrorService.shared.startMirror(source: displayID, target: virtualID)
           return virtualID
       }
       ```

    3. **Implement `disableHiDPIVirtual(for:)`**:
       ```swift
       func disableHiDPIVirtual(for physicalDisplayID: CGDirectDisplayID) {
           // Find the virtual display associated with this physical display
           guard let virtualID = hiDPIVirtualMap[physicalDisplayID] else { return }
           MirrorService.shared.stopMirror(for: virtualID)
           destroy(id: virtualID)
           hiDPIVirtualMap.removeValue(forKey: physicalDisplayID)
       }
       // Need to add to VirtualDisplayService: private var hiDPIVirtualMap: [CGDirectDisplayID: CGDirectDisplayID] = [:]
       // After enableHiDPIVirtual returns virtualID, record: hiDPIVirtualMap[displayID] = virtualID
       ```

    4. **Update `HiDPIService.swift`**:
       - Change `enableHiDPI(for:)` to try the virtual display path first (`VirtualDisplayService.shared.enableHiDPIVirtual`)
       - If it fails (e.g. insufficient permissions), fall back to the plist override path
       - Distinguish the two paths in the UI: the virtual display path takes effect immediately, the plist path requires reconnecting the display

  - File: `Backlit/Services/VirtualDisplayService.swift` (main implementation, replacing the placeholder false)
  - File: `Backlit/Services/HiDPIService.swift` (switch the primary/fallback paths)
  - Note: `CGVirtualDisplay` objects must be kept strongly referenced (stored in the `activeDisplayObjects` dictionary); once ARC releases them, the virtual display disappears immediately
  - Note: `CGVirtualDisplayDescriptor.colorSpace` is a `CGColorSpaceRef` (Core Foundation); in Swift, create it with `CGColorSpace(name:)` and assign it directly, no manual retain needed
  - Reference: BetterDummy project bridging header, KhaosT/CGVirtualDisplay example
  - Verify: turn on the HiDPI toggle -> a new "HiDPI Virtual" display appears in the system display list -> scaled modes such as `1920×1080 (HiDPI)` appear in the resolution list -> turn off the toggle -> the virtual display disappears

---

- [x] **Task 4**: Fix the notch overlay window crash (NSWindow lifecycle)
  - Background: the `NSWindow` created by `NotchOverlayManager` lacks `isReleasedWhenClosed = false`, so Swift holds a dangling pointer on close; `@State isHidingNotch` is out of sync with the manager state; the new window is created before the old one is closed, causing ordering problems; `onChange` uses the deprecated single-parameter form.
  - Implementation hints:
    1. **`NotchOverlayManager.swift`** - window creation fix:
       ```swift
       // In the showOverlay(for:) method, add right after the window is initialized:
       window.isReleasedWhenClosed = false  // <- Key: prevents a dangling pointer after close()
       ```

    2. **`NotchOverlayManager.swift`** - close order fix:
       ```swift
       func showOverlay(for screen: NSScreen) {
           // Close the old window first, then create the new one
           if let existing = overlayWindows[screen.displayID] {
               existing.close()
               overlayWindows.removeValue(forKey: screen.displayID)
           }
           // ... then create the new window
       }
       ```

    3. **`NotchOverlayManager.swift`** - add a query method:
       ```swift
       public func isShowingOverlay(for screen: NSScreen) -> Bool {
           return overlayWindows[screen.displayID] != nil
       }
       ```

    4. **`NotchView.swift`** - state sync fix:
       ```swift
       // Sync the initial state from the manager in body or .onAppear:
       .onAppear {
           isHidingNotch = NotchOverlayManager.shared.isShowingOverlay(for: screen)
       }
       ```

    5. **`NotchView.swift`** - onChange deprecated API fix:
       ```swift
       // Old (deprecated single-parameter form):
       // .onChange(of: isHidingNotch) { newValue in ... }
       // Change to the two-parameter form:
       .onChange(of: isHidingNotch) { _, newValue in
           // Handler logic unchanged
       }
       ```

  - File: `Backlit/Services/NotchOverlayManager.swift`
  - File: `Backlit/Views/NotchView.swift` (if it exists; otherwise modify the View file containing the notch Toggle)
  - Verify: toggle the notch switch ON/OFF ten times -> no crash; close and reopen the menu -> the notch switch state matches the actual overlay state; no EXC_BAD_ACCESS or objc over-release logs in Console.app

---

- [x] **Task 5**: Integration Testing and UI Updates
  - Implementation hints:
    1. **DDC verification**: connect the external HKC H2435Q -> open Backlit -> drag the brightness slider -> observe whether the display's physical brightness changes (judge by eye or check whether the DDC read value in IntegratedControlView echoes back)
    2. **HiDPI verification**: external 2K display -> turn on the HiDPI toggle -> check whether a new virtual display appears in System Preferences "Displays" -> check whether `1920×1080 (Retina)` appears in the resolution list -> select that resolution -> check whether text is noticeably sharper
    3. **Notch verification**: built-in MacBook screen -> notch switch ON -> overlay appears -> OFF -> overlay disappears -> repeat 10 times -> no crash; close and reopen the menu -> state is consistent
    4. **Update `DisplayDetailView.swift` / `MenuBarView.swift`** (as needed):
       - If DDC falls back to software, show a software mode hint in the brightness control area
       - If the HiDPI virtual display is active, show the status "HiDPI enabled (virtual display)"
    5. **Update `docs/BLOCKING.md`**:
       - Mark B-002 (DDC unavailable on Apple Silicon) as resolved and move it to the "Resolved" section
       - Mark B-003 (HiDPI virtual display creation failure) as resolved and move it to the "Resolved" section
  - File: `Backlit/Views/DisplayDetailView.swift` (minor changes as needed)
  - File: `Backlit/Views/MenuBarView.swift` (minor changes as needed)
  - File: `docs/BLOCKING.md` (move resolved items)
  - Verify: see the three manual tests above; builds with no warnings or errors

---

## Phase Acceptance

```bash
# 1. Build check
cd ~/Desktop/Backlit && xcodebuild -scheme Backlit -configuration Debug build 2>&1 | tail -5

# 2. Manual test checklist:
# [ ] DDC: external display brightness slider -> screen brightness actually changes (or the software mode label shows correctly)
# [ ] HiDPI: HiDPI toggle ON -> virtual display appears -> 1920x1080@2x selectable -> OFF -> virtual display disappears
# [ ] Notch: notch switch ON/OFF × 10 times -> no crash -> state matches the overlay
# [ ] Menu reopen: all of the above toggle states remain correct after closing and reopening the menu
```

**Phase acceptance criteria**: builds successfully + all four manual tests above are satisfied
