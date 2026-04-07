import AppKit
import SwiftUI

@main
struct WizmacMenuBarApp: App {
    @NSApplicationDelegateAdaptor(WizmacMenuBarAppDelegate.self) private var appDelegate
    @StateObject private var viewModel: MenuBarViewModel

    init() {
        let backend = LiveMenuBarBackend.makeDefault()
        _viewModel = StateObject(wrappedValue: MenuBarViewModel(backend: backend))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarDashboardView(viewModel: viewModel)
        } label: {
            Label(
                "Wizmac",
                systemImage: viewModel.snapshot.serverState.remoteHTTPRunning
                    ? "bolt.horizontal.circle.fill"
                    : "bolt.horizontal.circle"
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            MenuBarDashboardView(viewModel: viewModel)
                .frame(minWidth: 420, minHeight: 620)
                .task {
                    await viewModel.load()
                }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Setup Wizmac") {
                    appDelegate.showSetupWindow()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
