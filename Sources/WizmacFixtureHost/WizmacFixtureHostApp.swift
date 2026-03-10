import SwiftUI

@main
struct WizmacFixtureHostApp: App {
    @StateObject private var store = FixtureStore()

    var body: some Scene {
        WindowGroup {
            FixtureContentView(store: store)
                .frame(minWidth: 960, minHeight: 680)
        }

        WindowGroup("Secondary Window", id: "secondary") {
            FixtureSecondaryWindowView(store: store, descriptor: "Primary")
        }

        WindowGroup("Secondary Window", id: "secondary-duplicate") {
            FixtureSecondaryWindowView(store: store, descriptor: "Duplicate")
        }

        WindowGroup("Inspector", id: "inspector") {
            FixtureInspectorView(store: store)
        }
    }
}
