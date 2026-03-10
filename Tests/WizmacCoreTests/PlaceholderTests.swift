import XCTest
@testable import WizmacCore

final class CoreDefaultsTests: XCTestCase {
    func testDefaultSettingsCarryRiskPolicyAndInterfaceDefaults() {
        let settings = WizmacSettings()

        XCTAssertTrue(settings.riskyActions.contains(.uiAct))
        XCTAssertTrue(settings.autoApprovedActions.contains(.systemPermissions))
        XCTAssertEqual(settings.labelAlphabet, "asdfjkl;")
        XCTAssertEqual(settings.hotkeyProfiles.map(\.id), ["ui-hints", "scroll-session", "text-attach"])
        XCTAssertEqual(settings.interfaces["cli"], true)
        XCTAssertEqual(settings.interfaces["mcp"], true)
        XCTAssertTrue(settings.gridFallbackEnabled)
    }

    func testServiceSnapshotDefaultsKeepSessionStateDisabledOrInactive() {
        let snapshot = WizmacServiceSnapshot(
            health: ServiceHealth(status: .running),
            permissions: [],
            recentAudit: [],
            pendingApprovals: [],
            settings: WizmacSettings(),
            remoteClients: [],
            activeSessions: []
        )

        XCTAssertEqual(snapshot.textSession.mode, "disabled")
        XCTAssertFalse(snapshot.textSession.isSecureInput)
        XCTAssertFalse(snapshot.hintSession.isActive)
        XCTAssertEqual(snapshot.hintSession.targetCount, 0)
        XCTAssertFalse(snapshot.scrollSession.isActive)
        XCTAssertNil(snapshot.scrollSession.focusedTargetID)
    }

    func testLegacySettingsDecodeFillsServiceDefaults() throws {
        let json = """
        {
          "interfaces": {
            "cli": true
          },
          "labelAlphabet": "arstneio",
          "remoteServer": {
            "enabled": true,
            "host": "127.0.0.1",
            "port": 47242
          }
        }
        """

        let settings = try JSONDecoder().decode(WizmacSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.labelAlphabet, "arstneio")
        XCTAssertTrue(settings.remoteServer.enabled)
        XCTAssertEqual(settings.remoteServer.bindMode, .localhost)
        XCTAssertTrue(settings.gridFallbackEnabled)
        XCTAssertEqual(settings.hotkeyProfiles, HotkeyProfile.defaultProfiles)
        XCTAssertEqual(settings.onboardingState, OnboardingState())
        XCTAssertTrue(settings.riskyActions.contains(.remotePair))
        XCTAssertTrue(settings.autoApprovedActions.contains(.systemHealth))
    }
}
