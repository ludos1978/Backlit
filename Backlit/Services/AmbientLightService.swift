import AppKit
import Foundation
import IOKit
import Combine

// MARK: - IOHIDEventSystemClient SPI (IOKit.framework, exported, private)
//
// The Intel-era AppleLMUController does not exist on Apple Silicon. The ambient
// light sensor (ST VD6286 behind AppleSPUHIDDevice) is reachable through the HID
// event system: create a "monitor" client, match Apple's vendor usage page
// (0xFF00) / usage 4 (ALS), and read event type 12 (ambient light) field
// 0xC0000 (level, in lux). No entitlement or TCC prompt is needed. Verified on
// this hardware; fallback via BezelServices' ALCALSCopyALSServiceClient.

private let _IOHIDEventSystemClientCreateWithType: (@convention(c) (CFAllocator?, Int32, CFDictionary?) -> UnsafeMutableRawPointer?)? = {
    guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
          let sym = dlsym(h, "IOHIDEventSystemClientCreateWithType") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (CFAllocator?, Int32, CFDictionary?) -> UnsafeMutableRawPointer?).self)
}()

private let _IOHIDEventSystemClientSetMatching: (@convention(c) (UnsafeMutableRawPointer, CFDictionary) -> Void)? = {
    guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
          let sym = dlsym(h, "IOHIDEventSystemClientSetMatching") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (UnsafeMutableRawPointer, CFDictionary) -> Void).self)
}()

private let _IOHIDEventSystemClientCopyServices: (@convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFArray>?)? = {
    guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
          let sym = dlsym(h, "IOHIDEventSystemClientCopyServices") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFArray>?).self)
}()

private let _IOHIDServiceClientCopyEvent: (@convention(c) (UnsafeMutableRawPointer, Int64, Int32, Int64) -> UnsafeMutableRawPointer?)? = {
    guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
          let sym = dlsym(h, "IOHIDServiceClientCopyEvent") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (UnsafeMutableRawPointer, Int64, Int32, Int64) -> UnsafeMutableRawPointer?).self)
}()

private let _IOHIDEventGetFloatValue: (@convention(c) (UnsafeMutableRawPointer, Int32) -> Double)? = {
    guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
          let sym = dlsym(h, "IOHIDEventGetFloatValue") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (UnsafeMutableRawPointer, Int32) -> Double).self)
}()

private let _ALCALSCopyALSServiceClient: (@convention(c) () -> UnsafeMutableRawPointer?)? = {
    guard let h = dlopen("/System/Library/PrivateFrameworks/BezelServices.framework/BezelServices", RTLD_LAZY),
          let sym = dlsym(h, "ALCALSCopyALSServiceClient") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) () -> UnsafeMutableRawPointer?).self)
}()

/// Reads the Mac's ambient light sensor (lux). Smoothed with a short median so
/// the ±1 lux jitter and passing shadows do not drive brightness changes.
@MainActor
final class AmbientLightService: ObservableObject, @unchecked Sendable {
    static let shared = AmbientLightService()

    /// Smoothed ambient light in lux; nil when no sensor is available.
    @Published private(set) var lux: Double?
    /// True once a reading succeeded (sensor present and readable).
    @Published private(set) var isAvailable: Bool = false

    private static let eventTypeAmbientLight: Int64 = 12
    private static let fieldAmbientLightLevel: Int32 = 12 << 16   // kIOHIDEventFieldAmbientLightSensorLevel

    private var client: UnsafeMutableRawPointer?          // +1 from CreateWithType
    private var service: UnsafeMutableRawPointer?         // borrowed from `services`, or +1 from BezelServices
    private var services: CFArray?                        // keeps the borrowed service alive
    private var serviceIsOwned = false
    private var timer: Timer?
    private var samples: [Double] = []
    private var wakeObserver: NSObjectProtocol?

    private init() {}

    func start(interval: TimeInterval = 1.0) {
        guard timer == nil else { return }
        openSensor()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in AmbientLightService.shared.poll() }
        }
        poll()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            // The HID client can go stale across sleep — re-create it.
            Task { @MainActor in
                let s = AmbientLightService.shared
                s.closeSensor(); s.samples.removeAll(); s.openSensor()
            }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let obs = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs); wakeObserver = nil }
        closeSensor()
        samples.removeAll()
        lux = nil
    }

    /// One raw reading in lux, or nil.
    func readOnce() -> Double? {
        if service == nil { openSensor() }
        guard let service, let copyEvent = _IOHIDServiceClientCopyEvent, let getFloat = _IOHIDEventGetFloatValue,
              let event = copyEvent(service, Self.eventTypeAmbientLight, 0, 0) else { return nil }
        defer { Unmanaged<AnyObject>.fromOpaque(event).release() }   // CopyEvent returns +1
        let value = getFloat(event, Self.fieldAmbientLightLevel)
        return value.isFinite && value >= 0 ? value : nil
    }

    private func poll() {
        guard let value = readOnce() else {
            isAvailable = false
            lux = nil
            return
        }
        isAvailable = true
        samples.append(value)
        if samples.count > 5 { samples.removeFirst(samples.count - 5) }
        let sorted = samples.sorted()
        lux = sorted[sorted.count / 2]
    }

    private func openSensor() {
        // Primary: HID event-system monitor client matched to the ALS usage pair.
        if let create = _IOHIDEventSystemClientCreateWithType,
           let setMatching = _IOHIDEventSystemClientSetMatching,
           let copyServices = _IOHIDEventSystemClientCopyServices,
           let c = create(kCFAllocatorDefault, 1 /* monitor */, nil) {
            let matching: [String: Any] = ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 4]
            setMatching(c, matching as CFDictionary)
            if let array = copyServices(c)?.takeRetainedValue(),
               CFArrayGetCount(array) > 0,
               let first = CFArrayGetValueAtIndex(array, 0) {
                client = c
                services = array                     // owns the service client
                service = UnsafeMutableRawPointer(mutating: first)
                serviceIsOwned = false
                return
            }
            Unmanaged<AnyObject>.fromOpaque(c).release()
        }
        // Fallback: BezelServices hands out the same service client (+1).
        if let alc = _ALCALSCopyALSServiceClient, let s = alc() {
            service = s
            serviceIsOwned = true
        }
    }

    private func closeSensor() {
        if let service, serviceIsOwned { Unmanaged<AnyObject>.fromOpaque(service).release() }
        if let client { Unmanaged<AnyObject>.fromOpaque(client).release() }
        service = nil; client = nil; services = nil; serviceIsOwned = false
    }
}

// MARK: - macOS's own ambient-light compensation ("Automatically adjust brightness")

private let _DSAmbientLightCompensationEnabled: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Bool>) -> Int32)? = {
    guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
          let sym = dlsym(h, "DisplayServicesAmbientLightCompensationEnabled") else { return nil }
    return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Bool>) -> Int32).self)
}()

extension AmbientLightService {
    /// True when macOS's own "Automatically adjust brightness" is on for the
    /// display — our loop would then fight the system; the UI shows a hint.
    nonisolated static func systemAutoBrightnessEnabled(for displayID: CGDirectDisplayID) -> Bool? {
        guard let fn = _DSAmbientLightCompensationEnabled else { return nil }
        var enabled = false
        guard fn(displayID, &enabled) == 0 else { return nil }
        return enabled
    }
}
