import XCTest
@testable import WizmacMenuBarApp

@MainActor
final class MenuBarViewModelTests: XCTestCase {
    func testLoadUsesBackendSnapshot() async {
        let backend = PreviewMenuBarBackend()
        let viewModel = MenuBarViewModel(backend: backend)

        await viewModel.load()

        XCTAssertFalse(viewModel.snapshot.permissions.isEmpty)
        XCTAssertTrue(viewModel.snapshot.serverState.localControlPlaneRunning)
    }

    func testTogglingLocalServerUpdatesState() async throws {
        let backend = PreviewMenuBarBackend()
        let viewModel = MenuBarViewModel(backend: backend)

        await viewModel.load()
        viewModel.setLocalControlPlaneRunning(false)

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(viewModel.snapshot.serverState.localControlPlaneRunning)
        XCTAssertEqual(viewModel.snapshot.recentAudit.first?.title, "Local control plane stopped")
    }

    func testPairAndRevokeRemoteClientUpdatesSnapshot() async throws {
        let backend = PreviewMenuBarBackend()
        let viewModel = MenuBarViewModel(backend: backend)

        await viewModel.load()
        let initialCount = viewModel.snapshot.remoteClients.count

        viewModel.pairRemoteClient(named: "Regression Agent")
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.snapshot.remoteClients.count, initialCount + 1)
        XCTAssertEqual(viewModel.snapshot.remoteClients.first?.name, "Regression Agent")
        XCTAssertEqual(viewModel.snapshot.lastPairing?.client.name, "Regression Agent")

        let pairedID = try XCTUnwrap(viewModel.snapshot.remoteClients.first?.id)
        viewModel.revokeRemoteClient(pairedID)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.snapshot.remoteClients.count, initialCount)
        XCTAssertEqual(viewModel.snapshot.recentAudit.first?.title, "Revoked remote client")
    }

    func testRequestMissingPermissionsAddsAuditEntry() async throws {
        let backend = PreviewMenuBarBackend(
            snapshot: MenuBarSnapshot(
                permissions: [
                    PermissionStatus(
                        id: "accessibility",
                        title: "Accessibility",
                        detail: "Required for control.",
                        state: .missing
                    ),
                    PermissionStatus(
                        id: "screen_recording",
                        title: "Screen Recording",
                        detail: "Required for inspection.",
                        state: .missing
                    )
                ],
                serverState: ServerControlState(
                    localControlPlaneRunning: true,
                    remoteHTTPRunning: false
                ),
                recentAudit: [],
                pendingApprovals: []
            )
        )
        let viewModel = MenuBarViewModel(backend: backend)

        await viewModel.load()
        viewModel.requestMissingPermissions()

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.snapshot.recentAudit.first?.title, "Requested missing permissions")
    }

    func testOpenPermissionSettingsAddsAuditEntry() async throws {
        let backend = PreviewMenuBarBackend()
        let viewModel = MenuBarViewModel(backend: backend)

        await viewModel.load()
        viewModel.openPermissionSettings("accessibility")

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.snapshot.recentAudit.first?.title, "Opened Settings")
    }

    func testTrustedAutomationSessionCanStartAndEnd() async throws {
        let backend = PreviewMenuBarBackend()
        let viewModel = MenuBarViewModel(backend: backend)

        await viewModel.load()
        viewModel.startTrustedAutomationSession()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(viewModel.snapshot.hasTrustedAutomationSession)
        XCTAssertEqual(viewModel.snapshot.recentAudit.first?.title, "Started trusted automation")

        viewModel.endTrustedAutomationSession()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(viewModel.snapshot.hasTrustedAutomationSession)
        XCTAssertEqual(viewModel.snapshot.recentAudit.first?.title, "Ended trusted automation")
    }
}
