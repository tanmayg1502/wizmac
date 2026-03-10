import Foundation
import WizmacControlPlane
import WizmacCore

actor LiveMenuBarBackend: MenuBarBackend {
    private let client: WizmacServiceClient
    private var lastPairing: RemotePairingSummary?

    init() throws {
        self.client = WizmacServiceClient(sourceKind: .menuBar)
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

    func requestMissingPermissions() async -> MenuBarSnapshot {
        let snapshot = await loadSnapshot()
        for permission in snapshot.missingPromptablePermissions {
            _ = try? await client.callTool(
                named: "system.permissions_request",
                arguments: [
                    "permission": .string(permission.id),
                    "operation": .string("prompt"),
                ],
                source: ControlPlaneSource(kind: .menuBar)
            )
        }
        return await loadSnapshot()
    }

    func requestPermission(id: String) async -> MenuBarSnapshot {
        _ = try? await client.callTool(
            named: "system.permissions_request",
            arguments: [
                "permission": .string(id),
                "operation": .string("prompt"),
            ],
            source: ControlPlaneSource(kind: .menuBar)
        )
        return await loadSnapshot()
    }

    func openPermissionSettings(id: String) async -> MenuBarSnapshot {
        _ = try? await client.callTool(
            named: "system.permissions_request",
            arguments: [
                "permission": .string(id),
                "operation": .string("open_settings"),
            ],
            source: ControlPlaneSource(kind: .menuBar)
        )
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
