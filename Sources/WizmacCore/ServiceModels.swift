import Foundation

public enum ServiceStatus: String, Codable, Sendable {
    case starting
    case running
    case degraded
    case stopped
}

public enum ServiceEventKind: String, Codable, Sendable {
    case healthChanged
    case approvalsChanged
    case auditAppended
    case sessionsChanged
}

public struct ServiceEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ServiceEventKind
    public var createdAt: Date
    public var payload: JSONValue

    public init(
        id: UUID = UUID(),
        kind: ServiceEventKind,
        createdAt: Date = Date(),
        payload: JSONValue = .null
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.payload = payload
    }
}

public struct ServiceHealth: Codable, Equatable, Sendable {
    public var status: ServiceStatus
    public var startedAt: Date
    public var localControlPlaneURL: String
    public var remoteControlPlaneURL: String?
    public var remoteEnabled: Bool
    public var activeSessionCount: Int
    public var lastError: String?

    public init(
        status: ServiceStatus = .starting,
        startedAt: Date = Date(),
        localControlPlaneURL: String = "xpc://wizmac/service",
        remoteControlPlaneURL: String? = nil,
        remoteEnabled: Bool = false,
        activeSessionCount: Int = 0,
        lastError: String? = nil
    ) {
        self.status = status
        self.startedAt = startedAt
        self.localControlPlaneURL = localControlPlaneURL
        self.remoteControlPlaneURL = remoteControlPlaneURL
        self.remoteEnabled = remoteEnabled
        self.activeSessionCount = activeSessionCount
        self.lastError = lastError
    }
}

public enum ServiceSessionKind: String, Codable, Sendable {
    case hint
    case ui
    case scroll
    case text
    case mediaRecording = "media_recording"
    case mediaStreaming = "media_streaming"
    case trustedAutomation = "trusted_automation"
    case hotkey
    case remote
}

public struct ServiceSessionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ServiceSessionKind
    public var title: String
    public var detail: String
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: ServiceSessionKind,
        title: String,
        detail: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.updatedAt = updatedAt
    }
}

public struct ServiceTextSessionStatus: Codable, Equatable, Sendable {
    public var attachmentID: String?
    public var mode: String
    public var applicationName: String?
    public var elementIdentifier: String?
    public var isSecureInput: Bool

    public init(
        attachmentID: String? = nil,
        mode: String = "disabled",
        applicationName: String? = nil,
        elementIdentifier: String? = nil,
        isSecureInput: Bool = false
    ) {
        self.attachmentID = attachmentID
        self.mode = mode
        self.applicationName = applicationName
        self.elementIdentifier = elementIdentifier
        self.isSecureInput = isSecureInput
    }
}

public struct HintSessionState: Codable, Equatable, Sendable {
    public var isActive: Bool
    public var appName: String?
    public var targetCount: Int
    public var query: String

    public init(isActive: Bool = false, appName: String? = nil, targetCount: Int = 0, query: String = "") {
        self.isActive = isActive
        self.appName = appName
        self.targetCount = targetCount
        self.query = query
    }
}

public struct ScrollSessionState: Codable, Equatable, Sendable {
    public var isActive: Bool
    public var focusedTargetID: String?
    public var targetCount: Int
    public var lastDirection: String?

    public init(
        isActive: Bool = false,
        focusedTargetID: String? = nil,
        targetCount: Int = 0,
        lastDirection: String? = nil
    ) {
        self.isActive = isActive
        self.focusedTargetID = focusedTargetID
        self.targetCount = targetCount
        self.lastDirection = lastDirection
    }
}

public struct UISessionState: Codable, Equatable, Sendable {
    public var isActive: Bool
    public var sessionID: String?
    public var appName: String?
    public var windowTitle: String?
    public var snapshotID: String?
    public var targetCount: Int
    public var cacheHitRate: Double
    public var lastRefreshedAt: Date?

    public init(
        isActive: Bool = false,
        sessionID: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil,
        snapshotID: String? = nil,
        targetCount: Int = 0,
        cacheHitRate: Double = 0,
        lastRefreshedAt: Date? = nil
    ) {
        self.isActive = isActive
        self.sessionID = sessionID
        self.appName = appName
        self.windowTitle = windowTitle
        self.snapshotID = snapshotID
        self.targetCount = targetCount
        self.cacheHitRate = cacheHitRate
        self.lastRefreshedAt = lastRefreshedAt
    }
}

public struct TrustedAutomationSessionState: Codable, Equatable, Sendable {
    public var isActive: Bool
    public var id: String?
    public var appName: String?
    public var bundleIdentifier: String?
    public var startedAt: Date?
    public var expiresAt: Date?

    public init(
        isActive: Bool = false,
        id: String? = nil,
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        startedAt: Date? = nil,
        expiresAt: Date? = nil
    ) {
        self.isActive = isActive
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }
}

public struct MediaRecordingSessionState: Codable, Equatable, Sendable {
    public var isActive: Bool
    public var sessionID: String?
    public var path: String?
    public var codec: String?
    public var fps: Int?
    public var scopeDescription: String?
    public var startedAt: Date?

    public init(
        isActive: Bool = false,
        sessionID: String? = nil,
        path: String? = nil,
        codec: String? = nil,
        fps: Int? = nil,
        scopeDescription: String? = nil,
        startedAt: Date? = nil
    ) {
        self.isActive = isActive
        self.sessionID = sessionID
        self.path = path
        self.codec = codec
        self.fps = fps
        self.scopeDescription = scopeDescription
        self.startedAt = startedAt
    }
}

public struct MediaStreamSessionState: Codable, Equatable, Sendable {
    public var isActive: Bool
    public var sessionID: String?
    public var format: String?
    public var endpoint: String?
    public var scopeDescription: String?
    public var startedAt: Date?

    public init(
        isActive: Bool = false,
        sessionID: String? = nil,
        format: String? = nil,
        endpoint: String? = nil,
        scopeDescription: String? = nil,
        startedAt: Date? = nil
    ) {
        self.isActive = isActive
        self.sessionID = sessionID
        self.format = format
        self.endpoint = endpoint
        self.scopeDescription = scopeDescription
        self.startedAt = startedAt
    }
}

public struct OnboardingState: Codable, Equatable, Sendable {
    public var accessibilityPrompted: Bool
    public var screenRecordingPrompted: Bool
    public var automationPrompted: Bool
    public var inputMonitoringPrompted: Bool
    public var completedAt: Date?

    public init(
        accessibilityPrompted: Bool = false,
        screenRecordingPrompted: Bool = false,
        automationPrompted: Bool = false,
        inputMonitoringPrompted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.accessibilityPrompted = accessibilityPrompted
        self.screenRecordingPrompted = screenRecordingPrompted
        self.automationPrompted = automationPrompted
        self.inputMonitoringPrompted = inputMonitoringPrompted
        self.completedAt = completedAt
    }
}

public struct HotkeyProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var key: String
    public var modifiers: [String]
    public var action: ActionName
    public var enabled: Bool

    public init(
        id: String,
        title: String,
        key: String,
        modifiers: [String],
        action: ActionName,
        enabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.key = key
        self.modifiers = modifiers
        self.action = action
        self.enabled = enabled
    }
}

public extension HotkeyProfile {
    static let defaultProfiles: [HotkeyProfile] = [
        HotkeyProfile(
            id: "ui-hints",
            title: "Show UI Hints",
            key: "space",
            modifiers: ["control", "option"],
            action: .uiHints
        ),
        HotkeyProfile(
            id: "scroll-session",
            title: "Scroll Session",
            key: "s",
            modifiers: ["control", "option"],
            action: .scrollSessionStart
        ),
        HotkeyProfile(
            id: "text-attach",
            title: "Attach Text Mode",
            key: "v",
            modifiers: ["control", "option"],
            action: .textAttach
        ),
    ]
}

public struct RemotePairingToken: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var issuedAt: Date
    public var expiresAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        issuedAt: Date = Date(),
        expiresAt: Date = Date().addingTimeInterval(600)
    ) {
        self.id = id
        self.name = name
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }
}

public struct RemoteEnrollmentBundle: Codable, Equatable, Sendable {
    public var client: RemoteClientRecord
    public var clientCertificatePEM: String
    public var clientPrivateKeyPEM: String
    public var caCertificatePEM: String
    public var serverHost: String
    public var serverPort: Int
    public var serverCertificateFingerprint: String

    public init(
        client: RemoteClientRecord,
        clientCertificatePEM: String,
        clientPrivateKeyPEM: String,
        caCertificatePEM: String,
        serverHost: String,
        serverPort: Int,
        serverCertificateFingerprint: String
    ) {
        self.client = client
        self.clientCertificatePEM = clientCertificatePEM
        self.clientPrivateKeyPEM = clientPrivateKeyPEM
        self.caCertificatePEM = caCertificatePEM
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.serverCertificateFingerprint = serverCertificateFingerprint
    }
}

public struct RemoteClientCredential: Codable, Equatable, Sendable {
    public var client: RemoteClientRecord
    public var certificatePEM: String
    public var privateKeyPEM: String
    public var caCertificatePEM: String
    public var bearerToken: String?
    public var serverHost: String
    public var serverPort: Int

    public init(
        client: RemoteClientRecord,
        certificatePEM: String,
        privateKeyPEM: String,
        caCertificatePEM: String,
        bearerToken: String? = nil,
        serverHost: String,
        serverPort: Int
    ) {
        self.client = client
        self.certificatePEM = certificatePEM
        self.privateKeyPEM = privateKeyPEM
        self.caCertificatePEM = caCertificatePEM
        self.bearerToken = bearerToken
        self.serverHost = serverHost
        self.serverPort = serverPort
    }

    public init(from enrollmentBundle: RemoteEnrollmentBundle) {
        self.client = enrollmentBundle.client
        self.certificatePEM = enrollmentBundle.clientCertificatePEM
        self.privateKeyPEM = enrollmentBundle.clientPrivateKeyPEM
        self.caCertificatePEM = enrollmentBundle.caCertificatePEM
        self.bearerToken = nil
        self.serverHost = enrollmentBundle.serverHost
        self.serverPort = enrollmentBundle.serverPort
    }

    public var enrollmentBundle: RemoteEnrollmentBundle {
        RemoteEnrollmentBundle(
            client: client,
            clientCertificatePEM: certificatePEM,
            clientPrivateKeyPEM: privateKeyPEM,
            caCertificatePEM: caCertificatePEM,
            serverHost: serverHost,
            serverPort: serverPort,
            serverCertificateFingerprint: client.fingerprint
        )
    }
}

public struct RemoteServerSettingsPatch: Codable, Equatable, Sendable {
    public var enabled: Bool?
    public var host: String?
    public var port: Int?
    public var bindMode: RemoteBindMode?
    public var certificateDirectory: String?

    public init(
        enabled: Bool? = nil,
        host: String? = nil,
        port: Int? = nil,
        bindMode: RemoteBindMode? = nil,
        certificateDirectory: String? = nil
    ) {
        self.enabled = enabled
        self.host = host
        self.port = port
        self.bindMode = bindMode
        self.certificateDirectory = certificateDirectory
    }
}

public struct WizmacSettingsPatch: Codable, Equatable, Sendable {
    public var interfaces: [String: Bool]?
    public var labelAlphabet: String?
    public var launchAtLogin: Bool?
    public var onboardingState: OnboardingState?
    public var remoteServer: RemoteServerSettingsPatch?
    public var hotkeys: [String: String]?
    public var hotkeyProfiles: [HotkeyProfile]?
    public var gridFallbackEnabled: Bool?

    public init(
        interfaces: [String: Bool]? = nil,
        labelAlphabet: String? = nil,
        launchAtLogin: Bool? = nil,
        onboardingState: OnboardingState? = nil,
        remoteServer: RemoteServerSettingsPatch? = nil,
        hotkeys: [String: String]? = nil,
        hotkeyProfiles: [HotkeyProfile]? = nil,
        gridFallbackEnabled: Bool? = nil
    ) {
        self.interfaces = interfaces
        self.labelAlphabet = labelAlphabet
        self.launchAtLogin = launchAtLogin
        self.onboardingState = onboardingState
        self.remoteServer = remoteServer
        self.hotkeys = hotkeys
        self.hotkeyProfiles = hotkeyProfiles
        self.gridFallbackEnabled = gridFallbackEnabled
    }
}

public struct WizmacServiceSnapshot: Codable, Equatable, Sendable {
    public var health: ServiceHealth
    public var permissions: [CapabilityStatus]
    public var recentAudit: [AuditEntry]
    public var pendingApprovals: [PendingApprovalRecord]
    public var settings: WizmacSettings
    public var remoteClients: [RemoteClientRecord]
    public var activeSessions: [ServiceSessionRecord]
    public var textSession: ServiceTextSessionStatus
    public var uiSession: UISessionState
    public var hintSession: HintSessionState
    public var scrollSession: ScrollSessionState
    public var mediaRecordingSession: MediaRecordingSessionState
    public var mediaStreamSession: MediaStreamSessionState
    public var trustedAutomationSession: TrustedAutomationSessionState

    public init(
        health: ServiceHealth,
        permissions: [CapabilityStatus],
        recentAudit: [AuditEntry],
        pendingApprovals: [PendingApprovalRecord],
        settings: WizmacSettings,
        remoteClients: [RemoteClientRecord],
        activeSessions: [ServiceSessionRecord],
        textSession: ServiceTextSessionStatus = ServiceTextSessionStatus(),
        uiSession: UISessionState = UISessionState(),
        hintSession: HintSessionState = HintSessionState(),
        scrollSession: ScrollSessionState = ScrollSessionState(),
        mediaRecordingSession: MediaRecordingSessionState = MediaRecordingSessionState(),
        mediaStreamSession: MediaStreamSessionState = MediaStreamSessionState(),
        trustedAutomationSession: TrustedAutomationSessionState = TrustedAutomationSessionState()
    ) {
        self.health = health
        self.permissions = permissions
        self.recentAudit = recentAudit
        self.pendingApprovals = pendingApprovals
        self.settings = settings
        self.remoteClients = remoteClients
        self.activeSessions = activeSessions
        self.textSession = textSession
        self.uiSession = uiSession
        self.hintSession = hintSession
        self.scrollSession = scrollSession
        self.mediaRecordingSession = mediaRecordingSession
        self.mediaStreamSession = mediaStreamSession
        self.trustedAutomationSession = trustedAutomationSession
    }
}
