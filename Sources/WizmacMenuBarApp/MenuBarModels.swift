import Foundation

enum PermissionState: String, CaseIterable, Codable, Sendable {
    case granted
    case missing
    case limited
    case unknown
}

struct PermissionStatus: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var detail: String
    var state: PermissionState
}

extension PermissionStatus {
    var isMissing: Bool {
        state == .missing
    }

    var supportsPrompting: Bool {
        switch id {
        case "accessibility", "screen_recording":
            return true
        default:
            return false
        }
    }
}

struct ServerControlState: Codable, Hashable, Sendable {
    var localControlPlaneRunning: Bool
    var remoteHTTPRunning: Bool
    var serviceStatus: String
    var localControlPlaneURL: String?
    var remoteControlPlaneURL: String?
    var lastError: String?

    init(
        localControlPlaneRunning: Bool,
        remoteHTTPRunning: Bool,
        serviceStatus: String = "Stopped",
        localControlPlaneURL: String? = nil,
        remoteControlPlaneURL: String? = nil,
        lastError: String? = nil
    ) {
        self.localControlPlaneRunning = localControlPlaneRunning
        self.remoteHTTPRunning = remoteHTTPRunning
        self.serviceStatus = serviceStatus
        self.localControlPlaneURL = localControlPlaneURL
        self.remoteControlPlaneURL = remoteControlPlaneURL
        self.lastError = lastError
    }
}

struct AuditEntrySummary: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var detail: String
    var createdAt: Date
}

struct ApprovalRequestSummary: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var detail: String
    var requestedAt: Date
    var requiresConfirmation: Bool
}

struct RemoteClientSummary: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var fingerprint: String
    var createdAt: Date
}

struct RemotePairingSummary: Codable, Hashable, Sendable {
    var client: RemoteClientSummary
    var endpoint: String
    var serverCertificateFingerprint: String
}

struct ServiceSessionSummary: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var kind: String
    var title: String
    var detail: String
    var updatedAt: Date
}

enum LaunchAtLoginState: String, Codable, Hashable, Sendable {
    case enabled
    case disabled
    case requiresApproval = "requires_approval"
    case notFound = "not_found"
    case unsupported
}

struct MenuBarSnapshot: Codable, Hashable, Sendable {
    var permissions: [PermissionStatus]
    var serverState: ServerControlState
    var launchAtLoginEnabled: Bool
    var launchAtLoginSupported: Bool
    var launchAtLoginState: LaunchAtLoginState
    var launchAtLoginError: String?
    var remoteClients: [RemoteClientSummary]
    var lastPairing: RemotePairingSummary?
    var trustedAutomationSessionID: String?
    var trustedAutomationAppName: String?
    var trustedAutomationExpiresAt: Date?
    var activeSessions: [ServiceSessionSummary]
    var recentAudit: [AuditEntrySummary]
    var pendingApprovals: [ApprovalRequestSummary]

    init(
        permissions: [PermissionStatus],
        serverState: ServerControlState,
        launchAtLoginEnabled: Bool = false,
        launchAtLoginSupported: Bool = false,
        launchAtLoginState: LaunchAtLoginState = .unsupported,
        launchAtLoginError: String? = nil,
        remoteClients: [RemoteClientSummary] = [],
        lastPairing: RemotePairingSummary? = nil,
        trustedAutomationSessionID: String? = nil,
        trustedAutomationAppName: String? = nil,
        trustedAutomationExpiresAt: Date? = nil,
        activeSessions: [ServiceSessionSummary] = [],
        recentAudit: [AuditEntrySummary],
        pendingApprovals: [ApprovalRequestSummary]
    ) {
        self.permissions = permissions
        self.serverState = serverState
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.launchAtLoginSupported = launchAtLoginSupported
        self.launchAtLoginState = launchAtLoginState
        self.launchAtLoginError = launchAtLoginError
        self.remoteClients = remoteClients
        self.lastPairing = lastPairing
        self.trustedAutomationSessionID = trustedAutomationSessionID
        self.trustedAutomationAppName = trustedAutomationAppName
        self.trustedAutomationExpiresAt = trustedAutomationExpiresAt
        self.activeSessions = activeSessions
        self.recentAudit = recentAudit
        self.pendingApprovals = pendingApprovals
    }

    static let empty = MenuBarSnapshot(
        permissions: [],
        serverState: ServerControlState(
            localControlPlaneRunning: false,
            remoteHTTPRunning: false
        ),
        launchAtLoginEnabled: false,
        launchAtLoginSupported: false,
        launchAtLoginState: .unsupported,
        launchAtLoginError: nil,
        remoteClients: [],
        lastPairing: nil,
        activeSessions: [],
        recentAudit: [],
        pendingApprovals: []
    )
}

extension MenuBarSnapshot {
    var missingPromptablePermissions: [PermissionStatus] {
        permissions.filter { $0.isMissing && $0.supportsPrompting }
    }

    var needsPermissionOnboarding: Bool {
        missingPromptablePermissions.isEmpty == false
    }

    var hasTrustedAutomationSession: Bool {
        trustedAutomationSessionID != nil
    }

    var launchAtLoginMessage: String {
        switch launchAtLoginState {
        case .enabled:
            return "Wizmac will open automatically when you sign in."
        case .disabled:
            return "Wizmac stays off until you open it."
        case .requiresApproval:
            return "macOS is waiting for you to approve the login item in System Settings."
        case .notFound:
            return "This build is missing the packaged login-item registration that macOS expects."
        case .unsupported:
            return "Launch-at-login is only available in a packaged app."
        }
    }

    var canToggleLaunchAtLogin: Bool {
        switch launchAtLoginState {
        case .unsupported, .notFound:
            return false
        case .enabled, .disabled, .requiresApproval:
            return true
        }
    }
}
