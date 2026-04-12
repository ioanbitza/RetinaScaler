import SwiftUI

@main
struct RetinaScalerApp: App {
    var body: some Scene {
        MenuBarExtra("RetinaScaler", systemImage: "display.2") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
