import Foundation
import WizmacCore

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

    var isGranted: Bool {
        state == .granted
    }

    var supportsPrompting: Bool {
        switch id {
        case "accessibility", "screen_recording", "automation_music":
            return true
        default:
            return false
        }
    }
}

struct SetupChecklistItem: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var detail: String
    var state: PermissionState
    var actionTitle: String
    var secondaryActionTitle: String?
    var isComplete: Bool
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
    var onboardingState: OnboardingState
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
        onboardingState: OnboardingState = OnboardingState(),
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
        self.onboardingState = onboardingState
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
        onboardingState: OnboardingState(),
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
    var accessibilityPermission: PermissionStatus? {
        permissions.first(where: { $0.id == "accessibility" })
    }

    var screenRecordingPermission: PermissionStatus? {
        permissions.first(where: { $0.id == "screen_recording" })
    }

    var automationPermission: PermissionStatus? {
        permissions.first(where: { $0.id == "automation_music" })
    }

    var missingPromptablePermissions: [PermissionStatus] {
        permissions.filter { $0.isMissing && $0.supportsPrompting }
    }

    var needsPermissionOnboarding: Bool {
        requiredPermissionsGranted == false || onboardingState.automationPrompted == false
    }

    var requiredPermissionsGranted: Bool {
        accessibilityPermission?.isGranted == true && screenRecordingPermission?.isGranted == true
    }

    var shouldPresentSetupWindowOnLaunch: Bool {
        onboardingState.completedAt == nil || requiredPermissionsGranted == false
    }

    var canFinishSetup: Bool {
        requiredPermissionsGranted && onboardingState.automationPrompted
    }

    var setupChecklist: [SetupChecklistItem] {
        [
            SetupChecklistItem(
                id: "accessibility",
                title: "Accessibility",
                detail: accessibilityPermission?.detail ?? "Required for keyboard, clicks, focus, and scroll control.",
                state: accessibilityPermission?.state ?? .missing,
                actionTitle: "Prompt",
                secondaryActionTitle: "Open Settings",
                isComplete: accessibilityPermission?.isGranted == true
            ),
            SetupChecklistItem(
                id: "screen_recording",
                title: "Screen Recording",
                detail: screenRecordingPermission?.detail ?? "Required for richer UI and window inspection. You may need to relaunch Wizmac after enabling it.",
                state: screenRecordingPermission?.state ?? .missing,
                actionTitle: "Prompt",
                secondaryActionTitle: "Open Settings",
                isComplete: screenRecordingPermission?.isGranted == true
            ),
            SetupChecklistItem(
                id: "automation_music",
                title: "Automation",
                detail: onboardingState.automationPrompted
                    ? "Automation settings were opened. macOS will ask again the first time Wizmac controls Music."
                    : "Open Automation settings now so Wizmac is ready when you use Apple Music controls later.",
                state: onboardingState.automationPrompted ? .granted : .unknown,
                actionTitle: "Open Settings",
                secondaryActionTitle: nil,
                isComplete: onboardingState.automationPrompted
            ),
        ]
    }

    var setupSummary: String {
        if canFinishSetup {
            return "Everything important is ready. Finish setup to stop showing this first-run checklist."
        }

        if requiredPermissionsGranted == false {
            return "Grant Accessibility and Screen Recording so Wizmac can search UI, move focus, click, and inspect windows."
        }

        return "Open Automation once so the app can guide you through the last optional permission when you need Music control."
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
