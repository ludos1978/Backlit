import AppKit
import Combine
import CoreGraphics

/// What drives the automatic brightness.
enum AdaptiveMode: String, CaseIterable, Codable, Identifiable {
    case content, ambient, both, followBuiltin
    var id: String { rawValue }
    var title: String {
        switch self {
        case .content:       return "Screen content"
        case .ambient:       return "Ambient light"
        case .both:          return "Both"
        case .followBuiltin: return "Follow built-in"
        }
    }
    var usesContent: Bool { self == .content || self == .both }
    var usesAmbient: Bool { self == .ambient || self == .both }
}

enum ResponseSpeed: String, CaseIterable, Codable, Identifiable {
    case slow, normal, fast
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    /// Maximum brightness change (percentage points) per 1 s tick.
    var maxStep: Double {
        switch self { case .slow: return 4; case .normal: return 12; case .fast: return 100 }
    }
}

/// Learned brightness surface for one display over content lightness (11 bins,
/// 0…1) × ambient light (6 bins over log10(lux+1) mapped to 0…1). Values are
/// brightness 0…1 before the sensitivity multiplier.
struct AdaptiveCurve: Codable {
    static let lBins = 11
    static let luxBins = 6
    static let maxLog = log10(30_000.0 + 1)   // 30k lux ≈ direct sunlight
    var grid: [[Double]]   // [luxBin][lBin]

    /// Ambient coordinate 0…1 for a lux value; ≈0.55 (typical office) when unknown.
    static func ambientCoordinate(lux: Double?) -> Double {
        guard let lux else { return 0.55 }
        return max(0, min(1, log10(max(0, lux) + 1) / maxLog))
    }

    /// Cold start: dark content → brighter, bright content → dimmer (constant
    /// perceived luminance), scaled down in dark rooms and up in daylight.
    static func coldStart(min: Double, max: Double) -> AdaptiveCurve {
        var g = [[Double]](repeating: [Double](repeating: 0, count: lBins), count: luxBins)
        for i in 0..<luxBins {
            let u = Double(i) / Double(luxBins - 1)
            for j in 0..<lBins {
                let l = Double(j) / Double(lBins - 1)
                let base = max - (max - min) * pow(l, 0.7)
                g[i][j] = Swift.max(0, Swift.min(1, base * (0.55 + 0.45 * u)))
            }
        }
        return AdaptiveCurve(grid: g)
    }

    /// Bilinear lookup.
    func value(l: Double, u: Double) -> Double {
        let x = max(0, min(1, l)) * Double(Self.lBins - 1)
        let y = max(0, min(1, u)) * Double(Self.luxBins - 1)
        let j0 = Int(x), i0 = Int(y)
        let j1 = min(j0 + 1, Self.lBins - 1), i1 = min(i0 + 1, Self.luxBins - 1)
        let fx = x - Double(j0), fy = y - Double(i0)
        let a = grid[i0][j0] * (1 - fx) + grid[i0][j1] * fx
        let b = grid[i1][j0] * (1 - fx) + grid[i1][j1] * fx
        return a * (1 - fy) + b * fy
    }

    /// Learn from a manual adjustment: pull the surface toward the user's value
    /// with a Gaussian footprint, then restore monotonicity (non-increasing in
    /// content lightness, non-decreasing in ambient light).
    mutating func learn(l: Double, u: Double, brightness: Double) {
        let sigmaL = 0.15, sigmaU = 0.25
        for i in 0..<Self.luxBins {
            let ui = Double(i) / Double(Self.luxBins - 1)
            for j in 0..<Self.lBins {
                let lj = Double(j) / Double(Self.lBins - 1)
                let w = exp(-pow(lj - l, 2) / (2 * sigmaL * sigmaL)) * exp(-pow(ui - u, 2) / (2 * sigmaU * sigmaU))
                grid[i][j] += w * (brightness - grid[i][j])
            }
        }
        enforceMonotone()
    }

    mutating func enforceMonotone() {
        for i in 0..<Self.luxBins {
            for j in 1..<Self.lBins where grid[i][j] > grid[i][j - 1] { grid[i][j] = grid[i][j - 1] }
        }
        for j in 0..<Self.lBins {
            for i in 1..<Self.luxBins where grid[i][j] < grid[i - 1][j] { grid[i][j] = grid[i - 1][j] }
        }
        for i in 0..<Self.luxBins { for j in 0..<Self.lBins { grid[i][j] = max(0, min(1, grid[i][j])) } }
    }
}

/// Adaptive brightness engine: screen-content and/or ambient-light driven,
/// per display, learning from the user's manual adjustments. Built-in panels
/// are driven through DisplayServices, externals through DDC (or the gamma
/// ramp fallback) — always via BrightnessService.
@MainActor
final class AdaptiveBrightnessService: ObservableObject, @unchecked Sendable {
    static let shared = AdaptiveBrightnessService()

    // MARK: Settings (fd.adaptive.*)
    private let d = UserDefaults.standard
    private enum K {
        static let enabled = "fd.adaptive.enabled", mode = "fd.adaptive.mode", sensitivity = "fd.adaptive.sensitivity"
        static let minB = "fd.adaptive.min", maxB = "fd.adaptive.max", speed = "fd.adaptive.speed"
        static let learning = "fd.adaptive.learning", fps = "fd.adaptive.fps", metric = "fd.adaptive.metric"
        static let ignored = "fd.adaptive.ignoredApps", appBrightness = "fd.adaptive.appBrightness"
        static let disabledDisplays = "fd.adaptive.disabledDisplays"
        static let legacyEnabled = "fd.AutoBrightnessEnabled", legacySensitivity = "fd.AutoBrightnessSensitivity"
    }

    @Published var isEnabled: Bool = false { didSet { d.set(isEnabled, forKey: K.enabled); isEnabled ? start() : stop() } }
    @Published var mode: AdaptiveMode = .both { didSet { d.set(mode.rawValue, forKey: K.mode); if isEnabled { rebuildSamplers() } } }
    /// 0.5 … 1.5 multiplier on the learned brightness.
    @Published var sensitivity: Double = 1.0 { didSet { d.set(sensitivity, forKey: K.sensitivity) } }
    @Published var minBrightness: Double = 25 { didSet { d.set(minBrightness, forKey: K.minB) } }
    @Published var maxBrightness: Double = 100 { didSet { d.set(maxBrightness, forKey: K.maxB) } }
    @Published var speed: ResponseSpeed = .normal { didSet { d.set(speed.rawValue, forKey: K.speed) } }
    @Published var learningEnabled: Bool = true { didSet { d.set(learningEnabled, forKey: K.learning) } }
    @Published var captureFPS: Int = 4 { didSet { d.set(captureFPS, forKey: K.fps); if isEnabled { rebuildSamplers() } } }
    @Published var metric: LightnessMetric = .rms { didSet { d.set(metric.rawValue, forKey: K.metric); if isEnabled { rebuildSamplers() } } }
    /// Bundle identifiers of apps that pause adaptive brightness while frontmost.
    @Published var ignoredApps: [String] = [] { didSet { d.set(ignoredApps, forKey: K.ignored) } }
    /// Remembered brightness (0…100) per ignored app, learned from manual changes while it is frontmost.
    @Published var appBrightness: [String: Double] = [:] { didSet { d.set(appBrightness, forKey: K.appBrightness) } }
    @Published var disabledDisplayUUIDs: Set<String> = [] { didSet { d.set(Array(disabledDisplayUUIDs).sorted(), forKey: K.disabledDisplays) } }

    // MARK: Live state
    @Published private(set) var lightness: [String: Double] = [:]      // by display UUID
    @Published private(set) var target: [String: Double] = [:]         // by display UUID, 0…100
    @Published private(set) var frontmostBundleID: String?
    @Published private(set) var frontmostName: String?
    @Published private(set) var screenRecordingGranted: Bool = CGPreflightScreenCaptureAccess()
    @Published private(set) var contentError: String?
    @Published private(set) var systemAutoBrightnessOn: Bool = false

    var isPausedForApp: Bool { frontmostBundleID.map { ignoredApps.contains($0) } ?? false }
    var lux: Double? { AmbientLightService.shared.lux }
    var ambientAvailable: Bool { AmbientLightService.shared.isAvailable }

    // MARK: Engine
    private var samplers: [CGDirectDisplayID: ContentLightnessSampler] = [:]
    private var curves: [String: AdaptiveCurve] = [:]
    private var lastApplied: [CGDirectDisplayID: Double] = [:]
    private var lastWriteAt: [CGDirectDisplayID: Date] = [:]
    private var holdUntil: [CGDirectDisplayID: Date] = [:]
    private var lastLearnedManualAt: [CGDirectDisplayID: Date] = [:]
    private var tickTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    private init() {
        load()
        if d.bool(forKey: K.enabled) { isEnabled = true }
    }

    private func load() {
        // Migrate the former "Auto Brightness" (follow built-in) settings.
        if d.object(forKey: K.enabled) == nil, d.object(forKey: K.legacyEnabled) != nil {
            d.set(d.bool(forKey: K.legacyEnabled), forKey: K.enabled)
            d.set(AdaptiveMode.followBuiltin.rawValue, forKey: K.mode)
            if d.object(forKey: K.legacySensitivity) != nil { d.set(d.double(forKey: K.legacySensitivity), forKey: K.sensitivity) }
        }
        mode = AdaptiveMode(rawValue: d.string(forKey: K.mode) ?? "") ?? .both
        if d.object(forKey: K.sensitivity) != nil { sensitivity = d.double(forKey: K.sensitivity) }
        if d.object(forKey: K.minB) != nil { minBrightness = d.double(forKey: K.minB) }
        if d.object(forKey: K.maxB) != nil { maxBrightness = d.double(forKey: K.maxB) }
        speed = ResponseSpeed(rawValue: d.string(forKey: K.speed) ?? "") ?? .normal
        if d.object(forKey: K.learning) != nil { learningEnabled = d.bool(forKey: K.learning) }
        if d.object(forKey: K.fps) != nil { captureFPS = d.integer(forKey: K.fps) }
        metric = LightnessMetric(rawValue: d.string(forKey: K.metric) ?? "") ?? .rms
        ignoredApps = d.stringArray(forKey: K.ignored) ?? []
        appBrightness = (d.dictionary(forKey: K.appBrightness) as? [String: Double]) ?? [:]
        disabledDisplayUUIDs = Set(d.stringArray(forKey: K.disabledDisplays) ?? [])
    }

    // MARK: Lifecycle

    private func start() {
        AmbientLightService.shared.start()
        updateFrontmost(NSWorkspace.shared.frontmostApplication)
        rebuildSamplers()
        refreshSystemAutoBrightnessHint()
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in AdaptiveBrightnessService.shared.tick() }
        }
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in AdaptiveBrightnessService.shared.updateFrontmost(app) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AdaptiveBrightnessService.shared.rebuildSamplers() }
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                AdaptiveBrightnessService.shared.rebuildSamplers()
            }
        })
    }

    private func stop() {
        tickTimer?.invalidate(); tickTimer = nil
        for obs in observers { NSWorkspace.shared.notificationCenter.removeObserver(obs); NotificationCenter.default.removeObserver(obs) }
        observers.removeAll()
        for (_, s) in samplers { s.stop() }
        samplers.removeAll()
        AmbientLightService.shared.stop()
        lightness.removeAll(); target.removeAll()
        lastApplied.removeAll(); holdUntil.removeAll()
    }

    /// (Re)creates content samplers for the enabled displays when content is an input.
    func rebuildSamplers() {
        for (_, s) in samplers { s.stop() }
        samplers.removeAll()
        contentError = nil
        guard isEnabled, mode.usesContent else { return }
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        if !screenRecordingGranted {
            _ = CGRequestScreenCaptureAccess()
            contentError = "Screen Recording permission is needed to read screen content (System Settings → Privacy & Security → Screen Recording)."
            return
        }
        for display in enabledDisplays() {
            let sampler = ContentLightnessSampler(displayID: display.displayID, metric: metric)
            let uuid = display.displayUUID
            sampler.onChange = { [weak self] value in self?.lightness[uuid] = value }
            samplers[display.displayID] = sampler
            Task { @MainActor in
                do { try await sampler.start(fps: self.captureFPS) }
                catch { self.contentError = "Could not sample \(display.name): \(error.localizedDescription)" }
            }
        }
    }

    private func enabledDisplays() -> [DisplayInfo] {
        DisplayManagerAccessor.shared.displays.filter {
            $0.isOnline && !disabledDisplayUUIDs.contains($0.displayUUID)
                && !VirtualDisplayService.shared.isVirtualDisplay($0.displayID)
        }
    }

    private func refreshSystemAutoBrightnessHint() {
        if let builtin = DisplayManagerAccessor.shared.displays.first(where: { $0.isBuiltin }) {
            systemAutoBrightnessOn = AmbientLightService.systemAutoBrightnessEnabled(for: builtin.displayID) == true
        }
    }

    private func updateFrontmost(_ app: NSRunningApplication?) {
        frontmostBundleID = app?.bundleIdentifier
        frontmostName = app?.localizedName
        // Remembered per-app brightness: apply once when an ignored app comes to the front.
        if let id = frontmostBundleID, ignoredApps.contains(id), let remembered = appBrightness[id] {
            for display in enabledDisplays() {
                BrightnessService.shared.setBrightnessSmooth(remembered, for: display, isAutoAdjust: true)
                lastApplied[display.displayID] = remembered
            }
        }
    }

    // MARK: Ignore list

    func ignoreFrontmostApp() {
        guard let id = frontmostBundleID, !ignoredApps.contains(id) else { return }
        ignoredApps.append(id)
    }

    func unignore(_ bundleID: String) {
        ignoredApps.removeAll { $0 == bundleID }
        appBrightness.removeValue(forKey: bundleID)
    }

    func appName(for bundleID: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { FileManager.default.displayName(atPath: $0.path) }
            ?? bundleID
    }

    // MARK: Curves (learned surface per display)

    private var curvesDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Backlit/curves", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func curve(for uuid: String) -> AdaptiveCurve {
        if let c = curves[uuid] { return c }
        let url = curvesDir.appendingPathComponent("\(uuid).json")
        if let data = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(AdaptiveCurve.self, from: data) {
            curves[uuid] = c; return c
        }
        let c = AdaptiveCurve.coldStart(min: minBrightness / 100, max: maxBrightness / 100)
        curves[uuid] = c; return c
    }

    private func save(_ c: AdaptiveCurve, for uuid: String) {
        curves[uuid] = c
        if let data = try? JSONEncoder().encode(c) {
            try? data.write(to: curvesDir.appendingPathComponent("\(uuid).json"), options: .atomic)
        }
    }

    /// Forgets what was learned for a display (or all displays).
    func resetCurve(uuid: String? = nil) {
        let targets = uuid.map { [$0] } ?? Array(Set(curves.keys).union(DisplayManagerAccessor.shared.displays.map(\.displayUUID)))
        for u in targets {
            curves.removeValue(forKey: u)
            try? FileManager.default.removeItem(at: curvesDir.appendingPathComponent("\(u).json"))
        }
    }

    // MARK: Tick

    private func tick() {
        guard isEnabled, SettingsService.shared.isAuthoritative(.brightness) else { return }
        refreshSystemAutoBrightnessHint()
        let now = Date()
        let u = AdaptiveCurve.ambientCoordinate(lux: mode.usesAmbient ? lux : nil)
        let builtin = DisplayManagerAccessor.shared.displays.first(where: { $0.isBuiltin })

        for display in enabledDisplays() {
            let id = display.displayID
            let uuid = display.displayUUID
            let l = mode.usesContent ? (lightness[uuid] ?? samplers[id]?.lightness ?? 0.5) : 0.5

            // 1. Manual change detection → learn, then hold for a few seconds.
            var manual: Double?
            if let t = BrightnessService.shared.lastManualAdjust(for: id), t > (lastLearnedManualAt[id] ?? .distantPast),
               now.timeIntervalSince(t) >= 1.0 {
                manual = display.brightness
                lastLearnedManualAt[id] = t
            } else if display.isBuiltin, let hw = BrightnessService.shared.hardwareBacklight(for: id),
                      let applied = lastApplied[id],
                      now.timeIntervalSince(lastWriteAt[id] ?? .distantPast) > 1.0,
                      abs(hw * 100 - applied) > 4 {
                // Keys / Control Center changed the built-in backlight behind our back.
                manual = hw * 100
                display.brightness = hw * 100
                lastLearnedManualAt[id] = now
            }
            if let manual {
                lastApplied[id] = manual
                holdUntil[id] = now.addingTimeInterval(5)
                if let front = frontmostBundleID, ignoredApps.contains(front) {
                    appBrightness[front] = manual            // per-app preference, not the curve
                } else if learningEnabled, mode != .followBuiltin {
                    var c = curve(for: uuid)
                    c.learn(l: l, u: u, brightness: max(0, min(1, (manual / 100) / sensitivity)))
                    save(c, for: uuid)
                }
                continue
            }
            if isPausedForApp || now < (holdUntil[id] ?? .distantPast) { continue }

            // 2. Target.
            var t: Double
            if mode == .followBuiltin {
                guard !display.isBuiltin, let b = builtin else { continue }
                t = b.brightness * sensitivity
            } else {
                t = curve(for: uuid).value(l: l, u: u) * 100 * sensitivity
            }
            t = max(minBrightness, min(maxBrightness, t))
            target[uuid] = t

            // 3. Rate-limited move.
            let current = lastApplied[id] ?? display.brightness
            let delta = t - current
            guard abs(delta) >= 2 else { continue }
            let step = max(-speed.maxStep, min(speed.maxStep, delta))
            let next = current + step
            lastApplied[id] = next
            lastWriteAt[id] = now
            BrightnessService.shared.setBrightnessSmooth(next, for: display, isAutoAdjust: true)
        }
    }
}
