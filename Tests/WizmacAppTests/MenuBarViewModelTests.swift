import XCTest
@testable import WizmacMenuBarApp
import WizmacCore

@MainActor
final class MenuBarViewModelTests: XCTestCase {
    func testLoadUsesBackendSnapshot() async {
        let backend = PreviewMenuBarBackend()
        let viewModel = MenuBarViewModel(backend: backend)

        await viewModel.load()

        XCTAssertFalse(viewModel.snapshot.permissions.isEmpty)
        XCTAssertTrue(viewModel.snapshot.serverState.localControlPlaneRunning)
        XCTAssertTrue(viewModel.snapshot.launchAtLoginSupported)
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

    func testLaunchAtLoginToggleUpdatesSnapshotAndAudit() async throws {
        let backend = PreviewMenuBarBackend(
            snapshot: MenuBarSnapshot(
                permissions: [],
                serverState: ServerControlState(
                    localControlPlaneRunning: true,
                    remoteHTTPRunning: false
                ),
                launchAtLoginEnabled: false,
                launchAtLoginSupported: true,
                launchAtLoginState: .disabled,
                recentAudit: [],
                pendingApprovals: []
            )
        )
        let viewModel = MenuBarViewModel(backend: backend)

        await viewModel.load()
        viewModel.setLaunchAtLogin(true)

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(viewModel.snapshot.launchAtLoginEnabled)
        XCTAssertEqual(viewModel.snapshot.recentAudit.first?.title, "Launch at login enabled")
    }

    func testLaunchAtLoginToggleIsIgnoredWhenUnsupported() async throws {
        let backend = PreviewMenuBarBackend(
            snapshot: MenuBarSnapshot(
                permissions: [],
                serverState: ServerControlState(
                    localControlPlaneRunning: true,
                    remoteHTTPRunning: false
                ),
                launchAtLoginEnabled: false,
                launchAtLoginSupported: false,
                launchAtLoginState: .unsupported,
                recentAudit: [],
                pendingApprovals: []
            )
        )
        let viewModel = MenuBarViewModel(backend: backend)

        await viewModel.load()
        viewModel.setLaunchAtLogin(true)

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(viewModel.snapshot.launchAtLoginEnabled)
        XCTAssertEqual(viewModel.snapshot.recentAudit.first?.title, "Launch at login unavailable")
        XCTAssertFalse(viewModel.snapshot.canToggleLaunchAtLogin)
        XCTAssertEqual(viewModel.snapshot.launchAtLoginMessage, "Launch-at-login is only available in a packaged app.")
    }

    func testLaunchAtLoginStateMessagingReflectsApprovalAndPackagingState() {
        let approvalSnapshot = MenuBarSnapshot(
            permissions: [],
            serverState: ServerControlState(
                localControlPlaneRunning: true,
                remoteHTTPRunning: false
            ),
            launchAtLoginEnabled: false,
            launchAtLoginSupported: true,
            launchAtLoginState: .requiresApproval,
            recentAudit: [],
            pendingApprovals: []
        )
        let missingBundleSnapshot = MenuBarSnapshot(
            permissions: [],
            serverState: ServerControlState(
                localControlPlaneRunning: true,
                remoteHTTPRunning: false
            ),
            launchAtLoginEnabled: false,
            launchAtLoginSupported: true,
            launchAtLoginState: .notFound,
            recentAudit: [],
            pendingApprovals: []
        )

        XCTAssertTrue(approvalSnapshot.canToggleLaunchAtLogin)
        XCTAssertTrue(approvalSnapshot.launchAtLoginMessage.contains("approve the login item"))
        XCTAssertFalse(missingBundleSnapshot.canToggleLaunchAtLogin)
        XCTAssertTrue(missingBundleSnapshot.launchAtLoginMessage.contains("missing the packaged login-item registration"))
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

    func testCompleteSetupMarksOnboardingFinished() async throws {
        let backend = PreviewMenuBarBackend(
            snapshot: MenuBarSnapshot(
                permissions: [
                    PermissionStatus(
                        id: "accessibility",
                        title: "Accessibility",
                        detail: "Required for control.",
                        state: .granted
                    ),
                    PermissionStatus(
                        id: "screen_recording",
                        title: "Screen Recording",
                        detail: "Required for inspection.",
                        state: .granted
                    ),
                    PermissionStatus(
                        id: "automation_music",
                        title: "Automation",
                        detail: "Needed for Apple Music.",
                        state: .limited
                    ),
                ],
                onboardingState: OnboardingState(
                    accessibilityPrompted: true,
                    screenRecordingPrompted: true,
                    automationPrompted: true,
                    completedAt: nil
                ),
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
        XCTAssertTrue(viewModel.snapshot.canFinishSetup)

        viewModel.completeSetup()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNotNil(viewModel.snapshot.onboardingState.completedAt)
        XCTAssertEqual(viewModel.snapshot.recentAudit.first?.title, "Completed setup")
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
