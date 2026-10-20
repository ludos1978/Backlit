# Lessons Learned — SwiftUI / UI

> Updated: 2026-03-05

## SwiftUI / MenuBarExtra

- MenuBarExtra needs `.menuBarExtraStyle(.window)` to show custom SwiftUI views (the default menu style only supports Button/Toggle)
- Hide the Dock icon: set `INFOPLIST_KEY_LSUIElement: true` in project.yml; no need to set it manually in AppDelegate

## UI Animation / SwiftUI (Phase 12)

- `withAnimation(.easeInOut(duration: 0.2)) { state.toggle() }` is the simplest way to trigger expand/collapse animations; no need to apply `.animation(_, value:)` to the whole container
- `.transition(.opacity.combined(with: .move(edge: .top)))` gives expanded content its enter/exit effect, visually sliding out from below the button
- The shared icon helper `MenuItemIcon` (defined in MenuBarView.swift) can be used directly by all Views in the same Module without extra declarations
- Semantic colors in SwiftUI (green = protection/safety, red = streaming, orange = brightness, gray = settings, purple = color management) convey feature semantics effectively without extra text

## DDC Performance Cache (Phase 12)

- DDC I2C reads have 50ms+ latency, and repeated UI-triggered reads noticeably hurt the experience → solved with `NSLock` + dictionary cache + 5 second TTL; invalidate the matching cache entry immediately after a write
- The cache key is a two-level dictionary `[CGDirectDisplayID: [UInt8: VCPCacheEntry]]`, allowing precise invalidation per display and VCP code
- `NSLock.lock()` / `unlock()` must be paired; `defer { lock.unlock() }` is recommended, noting that defer runs correctly on early return

## SwiftUI Performance

- A `@Published` property change redraws all Views observing that ObservableObject → split state into several small ObservableObjects or localize it with `@State`
- Do not put synchronous IOKit/CG calls (such as `CGDisplayCopyColorSpace`) in a View `body` → fetch asynchronously with `@State` + `onAppear`/`task {}`
- The `isSwitching = true; syncCall(); isSwitching = false` pattern does not work: SwiftUI does not render in the middle of synchronous code → must use async/await so SwiftUI gets a chance to redraw
- Wrapping a shared singleton (`XXX.shared`) in `@StateObject` is an anti-pattern: each View rebuild may create a new subscription → use `@ObservedObject` for shared singletons
- The gamma table set by `CGSetDisplayTransferByFormula` is persistent at the kernel level and is not restored automatically when the View is destroyed → must call `CGDisplayRestoreColorSyncSettings()` manually in `onDisappear` and on app exit

## MenuBarExtra `.window` — ScrollView collapse & per-open `.task` (2026-09-07)

- **ScrollView inside a MenuBarExtra `.window` panel collapses to zero height** — the
  panel sizes itself to the view's *ideal* size, and a ScrollView's ideal height is ~0.
  Result: the menu "opens" as a sliver showing only fixed-height siblings (footer).
  `.frame(maxHeight:)` does NOT fix it (max ≠ ideal). Fix: measure the content with a
  GeometryReader + PreferenceKey and set `.frame(height: min(contentHeight, cap))`
  on the ScrollView (see `MenuContentHeightKey` in MenuBarView.swift).
- **`.task` on MenuBarExtra `.window` content re-runs on every menu open** — the content
  view is recreated per open. Launch-time work (defaults registration, wake-handler
  wiring, delayed display arrangement) must be guarded by a once-per-process flag or
  live in AppDelegate. A delayed display-config transaction fired from that task closes
  the just-opened menu (any CGCompleteDisplayConfiguration dismisses the panel).
- **Skip no-op display moves**: compare current bounds against the target before calling
  `CGConfigureDisplayOrigin` — every completed transaction re-fires the reconfiguration
  callback and dismisses open menu panels, even if nothing changed.
- **Cross-view state sync**: when two controls edit the same persisted state (combined
  gamma slider ↔ per-display ImageAdjustment panel), emit a `PassthroughSubject` from
  the service on save/clear and `.onReceive` it in views to re-sync local `@State`
  (guard with `isDragging` to not fight an active gesture).

## Swift 6 concurrency: closures in `@MainActor` functions on background queues (2026-09-07)

- **Crash signature**: `EXC_BREAKPOINT` / `SIGTRAP` in `_dispatch_assert_queue_fail` ←
  `swift_task_checkIsolatedSwift`, faulting thread = a background dispatch queue
  (e.g. `io.github.ludos1978.backlit.ddc`). It only appears when the background path actually runs —
  for BrightnessService that meant a DDC external display; a MacBook alone never hit it.
- **Cause**: a non-Sendable closure created inside a `@MainActor` function (here
  `ddcAvailableLock.withLock { … }` inside a DDC write completion) is inferred
  main-actor isolated; when the completion invokes it on the DDC queue the runtime asserts.
  `SWIFT_STRICT_CONCURRENCY: minimal` only silences compile-time diagnostics — the
  runtime check still fires.
- **Fix**: never form closures on the background side of a `@MainActor` function. Move the
  work into a plain (nonisolated) method with explicit `lock()`/`unlock()` and call that
  from the completion (see `BrightnessService.setDDCAvailable`). `Task { @MainActor in … }`
  or `DispatchQueue.main.async` hops are fine because they run on main.
