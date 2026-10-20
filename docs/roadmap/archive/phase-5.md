# Phase 5: Color Management ✅

> Core value: ICC color profile switching, color mode management

## Task List

- [x] Implement ICC Profile enumeration (`Backlit/Services/ColorProfileService.swift`)
  - Implementation hint:
    Use the ColorSync framework to enumerate system ICC profiles:
    ```swift
    import ColorSync
    // Get all ICC profiles
    let profileIterator = ColorSyncProfileIterateInstalledProfiles()
    ```
    Or scan the ICC profile directories in the file system:
    - `/Library/ColorSync/Profiles/`
    - `/System/Library/ColorSync/Profiles/`
    - `~/Library/ColorSync/Profiles/`
    Get the current display's profile: `CGDisplayCopyColorSpace(displayID)` →
    `CGColorSpace.name` gives the name.
    Profile model: `name: String`, `path: URL`, `colorSpace: String` (RGB/CMYK, etc.).
  - Verify: can list all system ICC profiles, including Display P3, sRGB, Adobe RGB, etc.

- [x] Implement ICC Profile switching (`ColorProfileService` extension)
  - Implementation hint:
    Use the ColorSync API to set a profile for the specified display:
    ```swift
    ColorSyncDeviceSetCustomProfiles(
      kColorSyncDisplayDeviceClass,
      deviceID,  // CGDirectDisplayID converted to CFUUIDRef
      profileInfo  // [kColorSyncDeviceDefaultProfileID: profileURL]
    )
    ```
    Note: the display UUID must be obtained via `CGDisplayCreateUUIDFromDisplayID`.
  - Verify: the display colors visibly change after switching profile

- [x] Implement the color profile UI (`Backlit/Views/ColorProfileView.swift`)
  - Implementation hint:
    An expandable "Color Profiles" section.
    The top shows the current profile (e.g. "Color LCD"), with a blue icon.
    Below is a categorized list:
    1. Profiles specific to the current display
    2. "Generic RGB Profiles" group (white text on a blue background label)
    3. List of all system profiles (AAA, ACES CG Linear, Adobe RGB, Apple RGB...)
    Each row: circular icon on the left (⊙/⊕) + profile name.
    Click to switch.
    Modeled on the color profile area layout of the BetterDisplay screenshot.
  - Verify: the profile list is fully shown and clicking switches the profile

- [x] Implement the color mode UI (`Backlit/Views/ColorModeView.swift`)
  - Implementation hint:
    An expandable "Color Mode" section.
    Shows current mode info (e.g. "Internal (8-bit)") + tags (SDR/RGB/Full Range).
    Lists the available options:
    - Uniformity Calibration
    - GPU Dithering
    Framebuffer type selection:
    - Standard framebuffer, inverted framebuffer, grayscale framebuffer, inverted grayscale framebuffer
    Use `CGDisplayCopyDisplayMode` to get current color information.
    The framebuffer type is obtained via `CGDisplayModeCopyPixelEncoding`.
    Modeled on the color mode area of the BetterDisplay screenshot.
  - Verify: color mode info is displayed correctly

## Phase Acceptance

- The ICC profile list is complete (including all profiles in the screenshot)
- Profile switching works and the colors actually change
- Color mode info is displayed correctly
- UI layout matches the BetterDisplay screenshot

**After completion**: running project-optimize for reflection is recommended
