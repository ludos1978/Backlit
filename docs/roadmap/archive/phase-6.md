# Phase 6: Image Adjustment ✅

> Core value: software-level color adjustment: contrast, gamma, gain, color temperature, independent RGB channels

## Task List

- [x] Implement the Gamma Table adjustment engine (`Backlit/Services/GammaService.swift`)
  - Implementation hint:
    macOS implements software-level color adjustment through gamma tables. Core APIs:
    ```swift
    // Get the current gamma table
    CGGetDisplayTransferByTable(displayID, capacity, &redTable, &greenTable, &blueTable, &sampleCount)
    // Set a custom gamma table
    CGSetDisplayTransferByTable(displayID, sampleCount, redTable, greenTable, blueTable)
    // Or use formula mode (more common)
    CGSetDisplayTransferByFormula(displayID,
      redMin, redMax, redGamma,
      greenMin, greenMax, greenGamma,
      blueMin, blueMax, blueGamma)
    ```
    Wrap into a high-level interface:
    - `setGamma(displayID, value: Double)` — overall gamma (0.1~3.0, default 1.0)
    - `setGain(displayID, value: Double)` — overall gain (mapped to the max parameter)
    - `setColorTemperature(displayID, kelvin: Int)` — color temperature (converted to RGB ratios)
    - `setRGBGamma(displayID, r/g/b: Double)` — independent RGB gamma
    - `setRGBGain(displayID, r/g/b: Double)` — independent RGB gain
    - `resetGamma(displayID)` — reset via `CGDisplayRestoreColorSyncSettings()`
    Color temperature to RGB conversion: use the Planckian locus approximation formula (Tanner Helland algorithm),
    taking a color temperature K value as input and outputting RGB ratio coefficients.
  - Verify: after `setGamma(displayID, 0.5)` the screen is visibly brighter/darker

- [x] Implement software contrast adjustment (`GammaService` extension)
  - Implementation hint:
    Contrast is achieved by adjusting the min/max range of the gamma table:
    - Increase contrast: widen the max - min gap
    - Decrease contrast: narrow the max - min gap
    Formula: `min = 0.5 - contrast/2`, `max = 0.5 + contrast/2`, contrast range 0~1.
    Note: external displays can also set hardware contrast via DDC VCP 0x12 (the DDC foundation already exists from Phase 2).
  - Verify: the image contrast visibly changes after adjusting contrast

- [x] Implement color inversion (`GammaService` extension)
  - Implementation hint:
    Color inversion = swap min and max in the gamma table:
    `CGSetDisplayTransferByFormula(displayID, 1,0,1, 1,0,1, 1,0,1)` achieves full inversion.
    Or use the accessibility API `CGDisplaySetInvertedPolarity(true)` if available.
  - Verify: after enabling inversion, all screen colors are inverted

- [x] Implement the image adjustment UI (`Backlit/Views/ImageAdjustmentView.swift`)
  - Implementation hint:
    An expandable "Image Adjustment" section, modeled on the BetterDisplay screenshot:
    several slider groups arranged vertically:
    1. Contrast — Slider (⊙ icon) 0%
    2. Gamma — Slider (✦ icon) 0%
    3. Gain — Slider (⚡ icon) 0%
    4. Color temperature — Slider (🔥 icon) 0%
    5. Quantization — Slider (📊 icon) Infinite
    ---divider---
    6. Gamma (red) R — Slider 0%
    7. Gamma (green) G — Slider 0%
    8. Gamma (blue) B — Slider 0%
    ---divider---
    9. Gain (red) R — Slider 0%
    10. Gain (green) G — Slider 0%
    11. Gain (blue) B — Slider 0%
    ---
    ⚠️ "Adjustments may affect HDR content!" warning text
    Bottom buttons: Invert Colors / Pause Color Adjustment / Reset Image Adjustment
    Each Slider has an icon and label on the left and a percentage value on the right.
  - Verify: the UI is identical to the BetterDisplay screenshot

- [x] Implement the quantization feature (`GammaService` extension)
  - Implementation hint:
    Quantization = a visual simulation of reduced color bit depth. Implemented by modifying the gamma table to create steps:
    map 256 gray levels to N levels (N = quantization level), producing a banding effect.
    "Infinite" = no quantization (original 256 levels).
  - Verify: with quantization set to a low value the image shows obvious banding

## Phase Acceptance

- All 11 sliders work correctly
- Adjusting gamma/gain/color temperature actually changes the screen colors
- Independent RGB channel adjustment works
- The invert colors / pause / reset buttons work
- UI matches the BetterDisplay image adjustment screenshot

**After completion**: running project-optimize for reflection is recommended
