# Phase 2: Brightness Control (DDC + Built-in) ✅

> Core value: the most commonly used feature, a brightness slider controlling external and built-in displays

## Task List

- [x] Implement low-level DDC/CI I2C communication (`Backlit/Services/DDCService.swift`)
  - Implementation hint:
    1. Find the I2C port via `IOServiceGetMatchingServices` + `IOFramebufferI2CInterface`
    2. Map `CGDirectDisplayID` → `IOServicePortFromCGDisplayID` to the I2C service
       (requires walking the IOKit registry to match display vendorID/productID)
    3. Open the I2C connection: `IOI2CInterfaceOpen`
    4. Build DDC/CI read/write requests:
       - Write: address 0x37, prefix 0x51 0x80+len, VCP opcode 0x03 (set) + VCP code + value
       - Read: first write the request (opcode 0x01 get + VCP code), then read the response and parse the current/max value
    5. Close the connection: `IOI2CInterfaceClose`
    6. Key function signatures:
       `func read(displayID: CGDirectDisplayID, command: UInt8) -> (current: UInt16, max: UInt16)?`
       `func write(displayID: CGDirectDisplayID, command: UInt8, value: UInt16) -> Bool`
    7. Add error handling and a retry mechanism (DDC communication is unstable, retry 3 times with a 50ms interval)
    Note: DDC communication must run on a background thread to avoid blocking the UI.
    Refer to the DDC implementation approach of the open-source MonitorControl project.
  - Verify: `DDCService.shared.read(displayID: externalID, command: 0x10)` returns the current brightness value

- [x] Implement built-in display brightness control (`Backlit/Services/BrightnessService.swift`)
  - Implementation hint:
    Built-in displays do not use DDC. Use `IODisplaySetFloatParameter` + `kIODisplayBrightnessKey`.
    Get: `IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey, &brightness)`
    Set: `IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey, brightness)`
    Obtain the service via `IOServiceGetMatchingService` + `IODisplayConnect`.
    The value range is 0.0-1.0 and must be converted to a percentage for display.
  - Verify: after changing the brightness value in code, the built-in screen brightness actually changes

- [x] Implement the brightness slider UI (`Backlit/Views/BrightnessSliderView.swift`)
  - Implementation hint:
    Horizontal Slider, sun icon (☀) on the left, percentage value on the right.
    Modeled on the layout of the "Brightness (Combined)" area in the BetterDisplay screenshot.
    `@Binding var brightness: Double` (0-100).
    Call DDCService/BrightnessService in the Slider's `onEditingChanged` callback.
    Add a debounce (200ms) to avoid frequent DDC communication.
    Support a "combined brightness" mode: one slider controls the brightness of all displays at once (proportional mapping).
  - Verify: dragging the slider actually changes the external display brightness

- [x] Integrate brightness control into the menu (`Backlit/Views/MenuBarView.swift`)
  - Implementation hint:
    Add a "Brightness (Combined)" area below the display list, containing a combined brightness slider.
    Each display also has its own brightness slider when expanded.
    Add a `brightness: Double` property to `DisplayInfo`, initialized at startup via DDC read.
  - Verify: the menu shows the brightness slider and dragging it changes the display brightness

## Phase Acceptance

- External display DDC brightness read and set work correctly
- Built-in display brightness read and set work correctly
- UI slider dragging is smooth with no noticeable lag
- Combined brightness mode can control multiple displays at once

**After completion**: running project-optimize for reflection is recommended
