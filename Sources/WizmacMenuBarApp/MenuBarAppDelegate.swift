import AppKit

final class WizmacMenuBarAppDelegate: NSObject, NSApplicationDelegate {
    private var didAttemptSetupWindowPresentation = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            await presentSetupWindowIfNeeded()
        }
    }

    @MainActor
    func showSetupWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let selector = Selector(("showSettingsWindow:"))
        if NSApp.sendAction(selector, to: nil, from: nil) == false {
            _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @MainActor
    private func presentSetupWindowIfNeeded() async {
        guard didAttemptSetupWindowPresentation == false else {
            return
        }

        didAttemptSetupWindowPresentation = true
        let backend = LiveMenuBarBackend.makeDefault()
        let snapshot = await backend.snapshot()
        guard snapshot.shouldPresentSetupWindowOnLaunch else {
            return
        }

        showSetupWindow()
    }
}
