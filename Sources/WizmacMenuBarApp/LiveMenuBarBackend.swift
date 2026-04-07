import Foundation
import ServiceManagement
import WizmacControlPlane
import WizmacCore
import WizmacSystem

protocol LaunchAtLoginControlling {
    var isSupported: Bool { get }
    var isEnabled: Bool { get }
    var state: LaunchAtLoginState { get }
    func setEnabled(_ enabled: Bool) throws
}

private struct SystemLaunchAtLoginController: LaunchAtLoginControlling {
    let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var isSupported: Bool {
        true
    }

    var isEnabled: Bool {
        service.status == .enabled
    }

    var state: LaunchAtLoginState {
        switch service.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}

private struct UnavailableLaunchAtLoginController: LaunchAtLoginControlling {
    var isSupported: Bool {
        false
    }

    var isEnabled: Bool {
        false
    }

    var state: LaunchAtLoginState {
        .unsupported
    }

    func setEnabled(_ enabled: Bool) throws {}
}

private enum LaunchAtLoginControllerFactory {
    static func makeDefault() -> any LaunchAtLoginControlling {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return UnavailableLaunchAtLoginController()
        }

        return SystemLaunchAtLoginController()
    }
}

protocol PermissionOnboardingHandling: Sendable {
    func perform(permissionID: String, operation: String?) async -> PermissionOnboardingOutcome
}

private struct LocalPermissionOnboardingHandler: PermissionOnboardingHandling {
    func perform(permissionID: String, operation: String?) async -> PermissionOnboardingOutcome {
        await PermissionOnboardingController.perform(permissionID: permissionID, operation: operation)
    }
}

actor LiveMenuBarBackend: MenuBarBackend {
    private let client: WizmacServiceClient
    private let launchAtLoginController: any LaunchAtLoginControlling
    private let permissionOnboardingHandler: any PermissionOnboardingHandling
    private var lastPairing: RemotePairingSummary?
    private var launchAtLoginLastError: String?

    init(
        client: WizmacServiceClient = WizmacServiceClient(sourceKind: .menuBar),
        launchAtLoginController: any LaunchAtLoginControlling = LaunchAtLoginControllerFactory.makeDefault(),
        permissionOnboardingHandler: any PermissionOnboardingHandling = LocalPermissionOnboardingHandler()
    ) throws {
        self.client = client
        self.launchAtLoginController = launchAtLoginController
        self.permissionOnboardingHandler = permissionOnboardingHandler
    }

    static func makeDefault() -> any MenuBarBackend {
        (try? LiveMenuBarBackend()) ?? PreviewMenuBarBackend()
    }

    func snapshot() async -> MenuBarSnapshot {
        await loadSnapshot()
    }

    func refresh() async -> MenuBarSnapshot {
        await loadSnapshot()
    }

    func setLocalControlPlaneRunning(_ isRunning: Bool) async -> MenuBarSnapshot {
        _ = try? await client.updateSettings(
            WizmacSettingsPatch(
                interfaces: [
                    "cli": isRunning,
                    "mcp": isRunning,
                ]
            )
        )
        return await loadSnapshot()
    }

    func setRemoteHTTPRunning(_ isRunning: Bool) async -> MenuBarSnapshot {
        _ = try? await client.updateSettings(
            WizmacSettingsPatch(
                interfaces: ["remote": isRunning],
                remoteServer: RemoteServerSettingsPatch(enabled: isRunning)
            )
        )

        return await loadSnapshot()
    }

    func setLaunchAtLogin(_ isRunning: Bool) async -> MenuBarSnapshot {
        guard launchAtLoginController.isSupported else {
            return await loadSnapshot()
        }

        do {
            try launchAtLoginController.setEnabled(isRunning)
            launchAtLoginLastError = nil

            if launchAtLoginController.state == .enabled || launchAtLoginController.state == .disabled {
                _ = try? await client.updateSettings(
                    WizmacSettingsPatch(
                        launchAtLogin: launchAtLoginController.isEnabled
                    )
                )
            }
        } catch {
            launchAtLoginLastError = error.localizedDescription
        }

        return await loadSnapshot()
    }

    func requestMissingPermissions() async -> MenuBarSnapshot {
        let snapshot = await loadSnapshot()
        for permission in snapshot.missingPromptablePermissions {
            _ = await permissionOnboardingHandler.perform(permissionID: permission.id, operation: "prompt")
        }
        return await loadSnapshot()
    }

    func requestPermission(id: String) async -> MenuBarSnapshot {
        _ = await permissionOnboardingHandler.perform(permissionID: id, operation: "prompt")
        return await loadSnapshot()
    }

    func openPermissionSettings(id: String) async -> MenuBarSnapshot {
        _ = await permissionOnboardingHandler.perform(permissionID: id, operation: "open_settings")
        return await loadSnapshot()
    }

    func startTrustedAutomationSession() async -> MenuBarSnapshot {
        _ = try? await client.callTool(
            named: "system.trusted_session_start",
            arguments: [:],
            source: ControlPlaneSource(kind: .menuBar)
        )
        return await loadSnapshot()
    }

    func endTrustedAutomationSession() async -> MenuBarSnapshot {
        let snapshot = await loadSnapshot()
        var arguments: [String: StructuredValue] = [:]
        if let trustedAutomationSessionID = snapshot.trustedAutomationSessionID {
            arguments["trustedSessionID"] = .string(trustedAutomationSessionID)
        }
        _ = try? await client.callTool(
            named: "system.trusted_session_end",
            arguments: arguments,
            source: ControlPlaneSource(kind: .menuBar)
        )
        return await loadSnapshot()
    }

    func pairRemoteClient(named name: String?) async -> MenuBarSnapshot {
        let resolvedName = makeClientName(from: name)
        if let enrollmentBundle = try? await client.pairRemoteClient(name: resolvedName) {
            lastPairing = pairingSummary(from: enrollmentBundle)
        }
        return await loadSnapshot()
    }

    func revokeRemoteClient(id: UUID) async -> MenuBarSnapshot {
        _ = try? await client.revokeRemoteClient(id: id)
        if lastPairing?.client.id == id {
            lastPairing = nil
        }
        return await loadSnapshot()
    }

    func approveRequest(id: UUID) async -> MenuBarSnapshot {
        _ = try? await client.resolveApproval(id: id, decision: .approve)
        return await loadSnapshot()
    }

    func rejectRequest(id: UUID) async -> MenuBarSnapshot {
        _ = try? await client.resolveApproval(id: id, decision: .reject)
        return await loadSnapshot()
    }

    private func loadSnapshot() async -> MenuBarSnapshot {
        guard let serviceSnapshot = try? await client.snapshot() else {
            return .empty
        }

        let launchState = launchAtLoginController.state
        let launchEnabled = launchAtLoginController.isSupported
            ? launchState == .enabled
            : serviceSnapshot.settings.launchAtLogin

        return MenuBarSnapshot(
            permissions: loadPermissions(from: serviceSnapshot.permissions),
            serverState: ServerControlState(
                localControlPlaneRunning: serviceSnapshot.settings.interfaces["cli"] ?? true,
                remoteHTTPRunning: serviceSnapshot.health.remoteEnabled,
                serviceStatus: serviceSnapshot.health.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized,
                localControlPlaneURL: serviceSnapshot.health.localControlPlaneURL,
                remoteControlPlaneURL: serviceSnapshot.health.remoteControlPlaneURL,
                lastError: serviceSnapshot.health.lastError
            ),
            launchAtLoginEnabled: launchEnabled,
            launchAtLoginSupported: launchAtLoginController.isSupported,
            launchAtLoginState: launchState,
            launchAtLoginError: launchAtLoginLastError,
            remoteClients: serviceSnapshot.remoteClients.map { loadRemoteClient(from: $0) },
            lastPairing: lastPairing,
            trustedAutomationSessionID: serviceSnapshot.trustedAutomationSession.id,
            trustedAutomationAppName: serviceSnapshot.trustedAutomationSession.appName,
            trustedAutomationExpiresAt: serviceSnapshot.trustedAutomationSession.expiresAt,
            activeSessions: serviceSnapshot.activeSessions.map { loadSession(from: $0) },
            recentAudit: loadAudit(from: serviceSnapshot.recentAudit),
            pendingApprovals: serviceSnapshot.pendingApprovals.map {
                ApprovalRequestSummary(
                    id: $0.approval.id,
                    title: $0.request.action.rawValue,
                    detail: $0.approval.summary,
                    requestedAt: $0.approval.createdAt,
                    requiresConfirmation: true
                )
            }
        )
    }

    private func loadPermissions(from entries: [CapabilityStatus]) -> [PermissionStatus] {
        entries.map { entry in
            return PermissionStatus(
                id: entry.name,
                title: entry.name.replacingOccurrences(of: "_", with: " ").capitalized,
                detail: entry.detail,
                state: PermissionState(coreState: entry.state.rawValue)
            )
        }
    }

    private func loadAudit(from entries: [AuditEntry]) -> [AuditEntrySummary] {
        entries.map { entry in
            return AuditEntrySummary(
                id: entry.id,
                title: entry.request.action.rawValue,
                detail: entry.message,
                createdAt: entry.createdAt
            )
        }
    }

    private func loadRemoteClient(from client: RemoteClientRecord) -> RemoteClientSummary {
        RemoteClientSummary(
            id: client.id,
            name: client.name,
            fingerprint: client.fingerprint,
            createdAt: client.createdAt
        )
    }

    private func loadSession(from session: ServiceSessionRecord) -> ServiceSessionSummary {
        ServiceSessionSummary(
            id: session.id,
            kind: session.kind.rawValue,
            title: session.title,
            detail: session.detail,
            updatedAt: session.updatedAt
        )
    }

    private func pairingSummary(from enrollmentBundle: WizmacControlPlane.RemoteEnrollmentBundle) -> RemotePairingSummary {
        RemotePairingSummary(
            client: RemoteClientSummary(
                id: enrollmentBundle.identity.id,
                name: enrollmentBundle.identity.name,
                fingerprint: enrollmentBundle.identity.fingerprint.value,
                createdAt: enrollmentBundle.identity.issuedAt
            ),
            endpoint: "https://\(enrollmentBundle.serverHost):\(enrollmentBundle.serverPort)/rpc",
            serverCertificateFingerprint: enrollmentBundle.serverCertificateFingerprint
        )
    }

    private func makeClientName(from providedName: String?) -> String {
        let trimmed = providedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty == false {
            return trimmed
        }

        let deviceName = Host.current().localizedName ?? "Mac"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return "\(deviceName) Agent \(formatter.string(from: .now))"
    }
}

private extension PermissionState {
    init(coreState: String?) {
        switch coreState {
        case "available":
            self = .granted
        case "permissionRequired":
            self = .missing
        case "unavailable":
            self = .limited
        default:
            self = .unknown
        }
    }
}
