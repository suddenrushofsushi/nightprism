import SwiftUI

@main
struct NightprismApp: App {
    @State private var store = OverlayStore()

    var body: some Scene {
        Window("Nightprism Controls", id: "controls") {
            MenuBarContent(store: store, showsOpenControls: false)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContent(store: store)
        } label: {
            Image(systemName: "moon.stars.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
