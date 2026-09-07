import SwiftUI

@main
struct FreeDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // All launch-time work lives in AppDelegate.applicationDidFinishLaunching:
    // with `.menuBarExtraStyle(.window)` this content view is only built when
    // the menu is FIRST OPENED, so nothing that must run at launch (wake
    // handling, display arrangement, service warm-up) may be attached here.
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(DisplayManager.shared)
        } label: {
            Image(systemName: "display")
        }
        .menuBarExtraStyle(.window)
    }
}
