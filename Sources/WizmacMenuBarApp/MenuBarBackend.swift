import Foundation
import Combine

protocol MenuBarBackend: Sendable {
    func snapshot() async -> MenuBarSnapshot
    func refresh() async -> MenuBarSnapshot
    func setLocalControlPlaneRunning(_ isRunning: Bool) async -> MenuBarSnapshot
    func setRemoteHTTPRunning(_ isRunning: Bool) async -> MenuBarSnapshot
    func requestMissingPermissions() async -> MenuBarSnapshot
    func requestPermission(id: String) async -> MenuBarSnapshot
    func openPermissionSettings(id: String) async -> MenuBarSnapshot
    func startTrustedAutomationSession() async -> MenuBarSnapshot
    func endTrustedAutomationSession() async -> MenuBarSnapshot
    func pairRemoteClient(named name: String?) async -> MenuBarSnapshot
    func revokeRemoteClient(id: UUID) async -> MenuBarSnapshot
    func approveRequest(id: UUID) async -> MenuBarSnapshot
    func rejectRequest(id: UUID) async -> MenuBarSnapshot
}

actor PreviewMenuBarBackend: MenuBarBackend {
    private var snapshotValue: MenuBarSnapshot

    init(snapshot: MenuBarSnapshot = PreviewMenuBarBackend.defaultSnapshot) {
        self.snapshotValue = snapshot
    }

    func snapshot() async -> MenuBarSnapshot {
        snapshotValue
    }

    func refresh() async -> MenuBarSnapshot {
        snapshotValue.permissions = snapshotValue.permissions.enumerated().map { index, permission in
            var next = permission
            if permission.state == .unknown, index == 0 {
                next.state = .granted
                next.detail = "Verified during the latest refresh."
            }
            return next
        }

        if snapshotValue.recentAudit.isEmpty {
            snapshotValue.recentAudit = Self.defaultSnapshot.recentAudit
        }

        return snapshotValue
    }

    func setLocalControlPlaneRunning(_ isRunning: Bool) async -> MenuBarSnapshot {
        snapshotValue.serverState.localControlPlaneRunning = isRunning
        appendAudit(
            title: isRunning ? "Local control plane started" : "Local control plane stopped",
            detail: "Menu bar toggle changed the local command surface."
        )
        return snapshotValue
    }

    func setRemoteHTTPRunning(_ isRunning: Bool) async -> MenuBarSnapshot {
        snapshotValue.serverState.remoteHTTPRunning = isRunning
        appendAudit(
            title: isRunning ? "Remote HTTP enabled" : "Remote HTTP disabled",
            detail: "Menu bar toggle changed remote access availability."
        )
        return snapshotValue
    }

    func requestMissingPermissions() async -> MenuBarSnapshot {
        let missingTitles = snapshotValue.missingPromptablePermissions.map(\.title)
        appendAudit(
            title: "Requested missing permissions",
            detail: missingTitles.isEmpty
                ? "Preview onboarding found no missing permissions to request."
                : "Prompted for \(missingTitles.joined(separator: ", "))."
        )
        return snapshotValue
    }

    func requestPermission(id: String) async -> MenuBarSnapshot {
        let permission = snapshotValue.permissions.first(where: { $0.id == id })
        appendAudit(
            title: "Requested permission",
            detail: permission.map { "Prompted for \($0.title) in preview mode." }
                ?? "Prompted for \(id) in preview mode."
        )
        return snapshotValue
    }

    func openPermissionSettings(id: String) async -> MenuBarSnapshot {
        let permission = snapshotValue.permissions.first(where: { $0.id == id })
        appendAudit(
            title: "Opened Settings",
            detail: permission.map { "Opened \($0.title) settings in preview mode." }
                ?? "Opened settings for \(id) in preview mode."
        )
        return snapshotValue
    }

    func startTrustedAutomationSession() async -> MenuBarSnapshot {
        snapshotValue.trustedAutomationSessionID = UUID().uuidString
        snapshotValue.trustedAutomationAppName = "Frontmost App"
        snapshotValue.trustedAutomationExpiresAt = .now.addingTimeInterval(600)
        appendAudit(
            title: "Started trusted automation",
            detail: "Preview mode started a fast local automation session."
        )
        return snapshotValue
    }

    func endTrustedAutomationSession() async -> MenuBarSnapshot {
        snapshotValue.trustedAutomationSessionID = nil
        snapshotValue.trustedAutomationAppName = nil
        snapshotValue.trustedAutomationExpiresAt = nil
        appendAudit(
            title: "Ended trusted automation",
            detail: "Preview mode ended the trusted local automation session."
        )
        return snapshotValue
    }

    func pairRemoteClient(named name: String?) async -> MenuBarSnapshot {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedName = trimmedName.isEmpty
            ? "Preview Client \(snapshotValue.remoteClients.count + 1)"
            : trimmedName
        let client = RemoteClientSummary(
            id: UUID(),
            name: resolvedName,
            fingerprint: Self.previewFingerprint(index: snapshotValue.remoteClients.count + 1),
            createdAt: .now
        )
        snapshotValue.remoteClients.insert(client, at: 0)
        snapshotValue.lastPairing = RemotePairingSummary(
            client: client,
            endpoint: "https://127.0.0.1:47242/rpc",
            serverCertificateFingerprint: "PREVIEW-SERVER-\(snapshotValue.remoteClients.count)"
        )
        appendAudit(
            title: "Paired remote client",
            detail: "Created preview access for \(resolvedName)."
        )
        return snapshotValue
    }

    func revokeRemoteClient(id: UUID) async -> MenuBarSnapshot {
        guard let client = snapshotValue.remoteClients.first(where: { $0.id == id }) else {
            return snapshotValue
        }
        snapshotValue.remoteClients.removeAll { $0.id == id }
        if snapshotValue.lastPairing?.client.id == id {
            snapshotValue.lastPairing = nil
        }
        appendAudit(
            title: "Revoked remote client",
            detail: "Removed \(client.name) from the preview remote access list."
        )
        return snapshotValue
    }

    func approveRequest(id: UUID) async -> MenuBarSnapshot {
        guard let request = snapshotValue.pendingApprovals.first(where: { $0.id == id }) else {
            return snapshotValue
        }

        snapshotValue.pendingApprovals.removeAll { $0.id == id }
        appendAudit(
            title: "Approved: \(request.title)",
            detail: request.detail
        )
        return snapshotValue
    }

    func rejectRequest(id: UUID) async -> MenuBarSnapshot {
        guard let request = snapshotValue.pendingApprovals.first(where: { $0.id == id }) else {
            return snapshotValue
        }

        snapshotValue.pendingApprovals.removeAll { $0.id == id }
        appendAudit(
            title: "Rejected: \(request.title)",
            detail: request.detail
        )
        return snapshotValue
    }

    private func appendAudit(title: String, detail: String) {
        snapshotValue.recentAudit.insert(
            AuditEntrySummary(id: UUID(), title: title, detail: detail, createdAt: .now),
            at: 0
        )
        snapshotValue.recentAudit = Array(snapshotValue.recentAudit.prefix(8))
    }

    private static let defaultSnapshot = MenuBarSnapshot(
        permissions: [
            PermissionStatus(
                id: "accessibility",
                title: "Accessibility",
                detail: "Required for input, clicks, focus, and scroll control.",
                state: .granted
            ),
            PermissionStatus(
                id: "screen_recording",
                title: "Screen Recording",
                detail: "Required for richer UI and window inspection.",
                state: .limited
            ),
            PermissionStatus(
                id: "automation_music",
                title: "Automation",
                detail: "Needed for Apple Music and SystemUIServer scripting.",
                state: .missing
            )
        ],
        serverState: ServerControlState(
            localControlPlaneRunning: true,
            remoteHTTPRunning: false,
            serviceStatus: "Running",
            localControlPlaneURL: "xpc://wizmac/service"
        ),
        remoteClients: [
            RemoteClientSummary(
                id: UUID(),
                name: "Preview Agent",
                fingerprint: previewFingerprint(index: 1),
                createdAt: .now.addingTimeInterval(-600)
            )
        ],
        lastPairing: nil,
        recentAudit: [
            AuditEntrySummary(
                id: UUID(),
                title: "Window focus request completed",
                detail: "Focused the frontmost Finder window through the local command bus.",
                createdAt: .now.addingTimeInterval(-45)
            ),
            AuditEntrySummary(
                id: UUID(),
                title: "Permissions refreshed",
                detail: "Re-read accessibility, screen capture, and automation capability states.",
                createdAt: .now.addingTimeInterval(-180)
            )
        ],
        pendingApprovals: [
            ApprovalRequestSummary(
                id: UUID(),
                title: "Copy selected UI text",
                detail: "Agent requested to copy text from the frontmost application.",
                requestedAt: .now.addingTimeInterval(-20),
                requiresConfirmation: true
            ),
            ApprovalRequestSummary(
                id: UUID(),
                title: "Connect to Living Room TV",
                detail: "Remote request wants to enable AirPlay display output.",
                requestedAt: .now.addingTimeInterval(-120),
                requiresConfirmation: true
            )
        ]
    )

    private static func previewFingerprint(index: Int) -> String {
        String(format: "PREV:%04d:%04d:%04d", index, index + 1, index + 2)
    }
}

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published private(set) var snapshot: MenuBarSnapshot
    @Published private(set) var isRefreshing = false

    private let backend: any MenuBarBackend

    init(
        backend: any MenuBarBackend = PreviewMenuBarBackend(),
        initialSnapshot: MenuBarSnapshot = .empty
    ) {
        self.backend = backend
        self.snapshot = initialSnapshot
    }

    func load() async {
        snapshot = await backend.snapshot()
    }

    func refresh() async {
        isRefreshing = true
        snapshot = await backend.refresh()
        isRefreshing = false
    }

    func setLocalControlPlaneRunning(_ isRunning: Bool) {
        Task {
            snapshot = await backend.setLocalControlPlaneRunning(isRunning)
        }
    }

    func setRemoteHTTPRunning(_ isRunning: Bool) {
        Task {
            snapshot = await backend.setRemoteHTTPRunning(isRunning)
        }
    }

    func requestMissingPermissions() {
        Task {
            snapshot = await backend.requestMissingPermissions()
        }
    }

    func requestPermission(_ id: String) {
        Task {
            snapshot = await backend.requestPermission(id: id)
        }
    }

    func openPermissionSettings(_ id: String) {
        Task {
            snapshot = await backend.openPermissionSettings(id: id)
        }
    }

    func startTrustedAutomationSession() {
        Task {
            snapshot = await backend.startTrustedAutomationSession()
        }
    }

    func endTrustedAutomationSession() {
        Task {
            snapshot = await backend.endTrustedAutomationSession()
        }
    }

    func pairRemoteClient(named name: String? = nil) {
        Task {
            snapshot = await backend.pairRemoteClient(named: name)
        }
    }

    func revokeRemoteClient(_ id: UUID) {
        Task {
            snapshot = await backend.revokeRemoteClient(id: id)
        }
    }

    func approve(_ id: UUID) {
        Task {
            snapshot = await backend.approveRequest(id: id)
        }
    }

    func reject(_ id: UUID) {
        Task {
            snapshot = await backend.rejectRequest(id: id)
        }
    }
}
