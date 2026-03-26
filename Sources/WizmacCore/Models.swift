import Foundation

public enum ActionName: String, Codable, CaseIterable, Sendable {
    case uiApps = "ui.apps"
    case uiSearch = "ui.search"
    case uiAct = "ui.act"
    case uiCopy = "ui.copy"
    case uiOpen = "ui.open"
    case uiSelect = "ui.select"
    case uiToggle = "ui.toggle"
    case uiFocus = "ui.focus"
    case uiRead = "ui.read"
    case uiWait = "ui.wait"
    case uiUntil = "ui.until"
    case uiAssert = "ui.assert"
    case uiDiff = "ui.diff"
    case uiWatch = "ui.watch"
    case uiSubmit = "ui.submit"
    case uiChooseFile = "ui.choose_file"
    case uiCapture = "ui.capture"
    case uiPrefetch = "ui.prefetch"
    case uiExecute = "ui.execute"
    case uiHints = "ui.hints"
    case uiDrag = "ui.drag"
    case inputKeyCombo = "input.key_combo"
    case inputKeySequence = "input.key_sequence"
    case uiGesture = "ui.gesture"
    case uiSessionEnd = "ui.session_end"
    case scrollTargets = "scroll.targets"
    case scrollFocus = "scroll.focus"
    case scrollStep = "scroll.step"
    case scrollSessionStart = "scroll.session_start"
    case scrollSessionEnd = "scroll.session_end"
    case scrollTo = "scroll.to"
    case scrollUntil = "scroll.until"
    case scrollIntoView = "scroll.into_view"
    case windowList = "window.list"
    case windowFocus = "window.focus"
    case windowAssert = "window.assert"
    case windowExclude = "window.exclude"
    case textAttach = "text.attach"
    case textDetach = "text.detach"
    case textInsert = "text.insert"
    case textRead = "text.read"
    case textSendKeys = "text.send_keys"
    case textMode = "text.mode"
    case textStatus = "text.status"
    case menuSelect = "menu.select"
    case mediaScreenshot = "media.screenshot"
    case mediaRecord = "media.record"
    case mediaStream = "media.stream"
    case mediaMusicVolume = "media.music_volume"
    case displayAirPlayDevices = "display.airplay_devices"
    case displayAirPlayConnect = "display.airplay_connect"
    case displayAirPlayDisconnect = "display.airplay_disconnect"
    case systemPermissions = "system.permissions"
    case systemPermissionsRequest = "system.permissions_request"
    case systemAudit = "system.audit"
    case systemHealth = "system.health"
    case systemSessions = "system.sessions"
    case systemConfirmationStatus = "system.confirmation_status"
    case systemConfirmationResolve = "system.confirmation_resolve"
    case systemTrustedSessionStart = "system.trusted_session_start"
    case systemTrustedSessionEnd = "system.trusted_session_end"
    case remotePair = "remote.pair"
    case remoteClients = "remote.clients"
    case remoteRevoke = "remote.revoke"
}

public enum ActionOutcome: String, Codable, Sendable {
    case success
    case unsupported
    case permissionRequired
    case confirmationRequired
    case notFound
    case invalidRequest
    case failed
}

public enum RequestOriginKind: String, Codable, Sendable {
    case cli
    case mcp
    case remote
    case menuBar
    case hotkey
    case test
}

public struct RequestOrigin: Codable, Equatable, Sendable {
    public var kind: RequestOriginKind
    public var sessionID: String?
    public var remoteAddress: String?

    public init(kind: RequestOriginKind, sessionID: String? = nil, remoteAddress: String? = nil) {
        self.kind = kind
        self.sessionID = sessionID
        self.remoteAddress = remoteAddress
    }
}

public struct ActionRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var action: ActionName
    public var arguments: [String: JSONValue]
    public var origin: RequestOrigin
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        action: ActionName,
        arguments: [String: JSONValue] = [:],
        origin: RequestOrigin = RequestOrigin(kind: .cli),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.action = action
        self.arguments = arguments
        self.origin = origin
        self.createdAt = createdAt
    }

    public func string(for key: String) -> String? {
        arguments[key]?.stringValue
    }

    public func bool(for key: String) -> Bool? {
        arguments[key]?.boolValue
    }

    public func int(for key: String) -> Int? {
        arguments[key]?.intValue
    }

    public func object(for key: String) -> [String: JSONValue]? {
        arguments[key]?.objectValue
    }

    public func array(for key: String) -> [JSONValue]? {
        arguments[key]?.arrayValue
    }
}

public struct ActionResult: Codable, Equatable, Sendable {
    public var requestID: UUID
    public var action: ActionName
    public var outcome: ActionOutcome
    public var message: String
    public var payload: JSONValue?
    public var generatedAt: Date

    public init(
        requestID: UUID,
        action: ActionName,
        outcome: ActionOutcome,
        message: String,
        payload: JSONValue? = nil,
        generatedAt: Date = Date()
    ) {
        self.requestID = requestID
        self.action = action
        self.outcome = outcome
        self.message = message
        self.payload = payload
        self.generatedAt = generatedAt
    }
}

public enum CapabilityState: String, Codable, Sendable {
    case available
    case permissionRequired
    case unavailable
    case unsupported
}

public struct CapabilityStatus: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var state: CapabilityState
    public var detail: String

    public init(name: String, state: CapabilityState, detail: String) {
        self.name = name
        self.state = state
        self.detail = detail
    }
}

public struct TargetRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct TargetDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var appName: String
    public var role: String
    public var title: String
    public var subtitle: String?
    public var value: String?
    public var frame: TargetRect?
    public var hint: String?
    public var path: [String]

    public init(
        id: String,
        appName: String,
        role: String,
        title: String,
        subtitle: String? = nil,
        value: String? = nil,
        frame: TargetRect? = nil,
        hint: String? = nil,
        path: [String] = []
    ) {
        self.id = id
        self.appName = appName
        self.role = role
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.frame = frame
        self.hint = hint
        self.path = path
    }
}

public struct TargetSnapshot: Codable, Equatable, Sendable {
    public var appName: String
    public var bundleIdentifier: String?
    public var windowTitle: String?
    public var sessionID: String?
    public var snapshotID: String?
    public var generatedAt: Date
    public var targets: [TargetDescriptor]

    public init(
        appName: String,
        bundleIdentifier: String?,
        windowTitle: String?,
        sessionID: String? = nil,
        snapshotID: String? = nil,
        generatedAt: Date = Date(),
        targets: [TargetDescriptor]
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.sessionID = sessionID
        self.snapshotID = snapshotID
        self.generatedAt = generatedAt
        self.targets = targets
    }
}

public enum ApprovalDecision: String, Codable, Sendable {
    case approve
    case reject
}

public struct ApprovalRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var actionRequestID: UUID
    public var action: ActionName
    public var reason: String
    public var createdAt: Date
    public var summary: String

    public init(
        id: UUID = UUID(),
        actionRequestID: UUID,
        action: ActionName,
        reason: String,
        createdAt: Date = Date(),
        summary: String
    ) {
        self.id = id
        self.actionRequestID = actionRequestID
        self.action = action
        self.reason = reason
        self.createdAt = createdAt
        self.summary = summary
    }
}

public struct PendingApprovalRecord: Codable, Equatable, Sendable {
    public var approval: ApprovalRequest
    public var request: ActionRequest

    public init(approval: ApprovalRequest, request: ActionRequest) {
        self.approval = approval
        self.request = request
    }
}

public struct AuditEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var request: ActionRequest
    public var outcome: ActionOutcome
    public var message: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        request: ActionRequest,
        outcome: ActionOutcome,
        message: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.request = request
        self.outcome = outcome
        self.message = message
        self.createdAt = createdAt
    }
}

public struct ExcludedWindowRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(appName)::\(title)" }
    public var appName: String
    public var title: String

    public init(appName: String, title: String) {
        self.appName = appName
        self.title = title
    }
}

public struct RemoteClientRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var fingerprint: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, fingerprint: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.fingerprint = fingerprint
        self.createdAt = createdAt
    }
}

public typealias RemoteClient = RemoteClientRecord

public enum RemoteBindMode: String, Codable, Sendable {
    case localhost
    case lan
    case custom
}

public struct RemoteServerSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var host: String
    public var port: Int
    public var bindMode: RemoteBindMode
    public var certificateDirectory: String?
    public var issuedClients: [RemoteClientRecord]

    public init(
        enabled: Bool = false,
        host: String = "127.0.0.1",
        port: Int = 47242,
        bindMode: RemoteBindMode = .localhost,
        certificateDirectory: String? = nil,
        issuedClients: [RemoteClientRecord] = []
    ) {
        self.enabled = enabled
        self.host = host
        self.port = port
        self.bindMode = bindMode
        self.certificateDirectory = certificateDirectory
        self.issuedClients = issuedClients
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case host
        case port
        case bindMode
        case certificateDirectory
        case issuedClients
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.host = try container.decodeIfPresent(String.self, forKey: .host) ?? "127.0.0.1"
        self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 47242
        self.bindMode = try container.decodeIfPresent(RemoteBindMode.self, forKey: .bindMode) ?? .localhost
        self.certificateDirectory = try container.decodeIfPresent(String.self, forKey: .certificateDirectory)
        self.issuedClients = try container.decodeIfPresent([RemoteClientRecord].self, forKey: .issuedClients) ?? []
    }
}

public struct WizmacSettings: Codable, Equatable, Sendable {
    public var hotkeys: [String: String]
    public var hotkeyProfiles: [HotkeyProfile]
    public var labelAlphabet: String
    public var vimConfigPath: String?
    public var allowlistedApplications: [String]
    public var allowlistedBundleIdentifiers: [String]
    public var blacklistedApplications: [String]
    public var blacklistedBundleIdentifiers: [String]
    public var excludedWindows: [ExcludedWindowRule]
    public var riskyActions: [ActionName]
    public var autoApprovedActions: [ActionName]
    public var remoteServer: RemoteServerSettings
    public var launchAtLogin: Bool
    public var onboardingState: OnboardingState
    public var gridFallbackEnabled: Bool
    public var interfaces: [String: Bool]

    public init(
        hotkeys: [String: String] = [:],
        hotkeyProfiles: [HotkeyProfile] = HotkeyProfile.defaultProfiles,
        labelAlphabet: String = "asdfjkl;",
        vimConfigPath: String? = nil,
        allowlistedApplications: [String] = [],
        allowlistedBundleIdentifiers: [String] = [],
        blacklistedApplications: [String] = [],
        blacklistedBundleIdentifiers: [String] = [],
        excludedWindows: [ExcludedWindowRule] = [],
        riskyActions: [ActionName] = ActionName.defaultRiskyActions,
        autoApprovedActions: [ActionName] = ActionName.defaultAutoApprovedActions,
        remoteServer: RemoteServerSettings = RemoteServerSettings(),
        launchAtLogin: Bool = false,
        onboardingState: OnboardingState = OnboardingState(),
        gridFallbackEnabled: Bool = true,
        interfaces: [String: Bool] = [
            "cli": true,
            "mcp": true,
            "remote": true,
            "menuBar": true,
        ]
    ) {
        self.hotkeys = hotkeys
        self.hotkeyProfiles = hotkeyProfiles
        self.labelAlphabet = labelAlphabet
        self.vimConfigPath = vimConfigPath
        self.allowlistedApplications = allowlistedApplications
        self.allowlistedBundleIdentifiers = allowlistedBundleIdentifiers
        self.blacklistedApplications = blacklistedApplications
        self.blacklistedBundleIdentifiers = blacklistedBundleIdentifiers
        self.excludedWindows = excludedWindows
        self.riskyActions = riskyActions
        self.autoApprovedActions = autoApprovedActions
        self.remoteServer = remoteServer
        self.launchAtLogin = launchAtLogin
        self.onboardingState = onboardingState
        self.gridFallbackEnabled = gridFallbackEnabled
        self.interfaces = interfaces
    }

    enum CodingKeys: String, CodingKey {
        case hotkeys
        case hotkeyProfiles
        case labelAlphabet
        case vimConfigPath
        case allowlistedApplications
        case allowlistedBundleIdentifiers
        case blacklistedApplications
        case blacklistedBundleIdentifiers
        case excludedWindows
        case riskyActions
        case autoApprovedActions
        case remoteServer
        case launchAtLogin
        case onboardingState
        case gridFallbackEnabled
        case interfaces
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.hotkeys = try container.decodeIfPresent([String: String].self, forKey: .hotkeys) ?? [:]
        self.hotkeyProfiles = try container.decodeIfPresent([HotkeyProfile].self, forKey: .hotkeyProfiles) ?? HotkeyProfile.defaultProfiles
        self.labelAlphabet = try container.decodeIfPresent(String.self, forKey: .labelAlphabet) ?? "asdfjkl;"
        self.vimConfigPath = try container.decodeIfPresent(String.self, forKey: .vimConfigPath)
        self.allowlistedApplications = try container.decodeIfPresent([String].self, forKey: .allowlistedApplications) ?? []
        self.allowlistedBundleIdentifiers = try container.decodeIfPresent([String].self, forKey: .allowlistedBundleIdentifiers) ?? []
        self.blacklistedApplications = try container.decodeIfPresent([String].self, forKey: .blacklistedApplications) ?? []
        self.blacklistedBundleIdentifiers = try container.decodeIfPresent([String].self, forKey: .blacklistedBundleIdentifiers) ?? []
        self.excludedWindows = try container.decodeIfPresent([ExcludedWindowRule].self, forKey: .excludedWindows) ?? []
        let decodedRiskyActions = try container.decodeIfPresent([ActionName].self, forKey: .riskyActions) ?? []
        let decodedAutoApprovedActions = try container.decodeIfPresent([ActionName].self, forKey: .autoApprovedActions) ?? []
        self.riskyActions = Self.mergedActions(decodedRiskyActions, defaults: ActionName.defaultRiskyActions)
        self.autoApprovedActions = Self.mergedActions(decodedAutoApprovedActions, defaults: ActionName.defaultAutoApprovedActions)
        self.remoteServer = try container.decodeIfPresent(RemoteServerSettings.self, forKey: .remoteServer) ?? RemoteServerSettings()
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.onboardingState = try container.decodeIfPresent(OnboardingState.self, forKey: .onboardingState) ?? OnboardingState()
        self.gridFallbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .gridFallbackEnabled) ?? true
        self.interfaces = try container.decodeIfPresent([String: Bool].self, forKey: .interfaces) ?? [
            "cli": true,
            "mcp": true,
            "remote": true,
            "menuBar": true,
        ]
    }

    private static func mergedActions(_ decoded: [ActionName], defaults: [ActionName]) -> [ActionName] {
        guard decoded.isEmpty == false else {
            return defaults
        }

        var merged = decoded
        for action in defaults where merged.contains(action) == false {
            merged.append(action)
        }
        return merged
    }
}

public extension ActionName {
    static let defaultAutoApprovedActions: [ActionName] = [
        .uiApps,
        .uiSearch,
        .uiRead,
        .uiWait,
        .uiUntil,
        .uiAssert,
        .uiDiff,
        .uiWatch,
        .uiHints,
        .uiSessionEnd,
        .scrollTargets,
        .scrollFocus,
        .scrollStep,
        .scrollSessionStart,
        .scrollSessionEnd,
        .windowAssert,
        .windowList,
        .textRead,
        .textStatus,
        .systemPermissions,
        .systemPermissionsRequest,
        .systemAudit,
        .systemHealth,
        .systemSessions,
        .systemConfirmationStatus,
        .systemTrustedSessionStart,
        .systemTrustedSessionEnd,
        .mediaRecord,
        .mediaStream,
        .displayAirPlayDevices,
        .remoteClients,
        .textMode,
    ]

    static let defaultRiskyActions: [ActionName] = [
        .uiAct,
        .uiCopy,
        .uiOpen,
        .uiSelect,
        .uiToggle,
        .uiFocus,
        .uiSubmit,
        .uiChooseFile,
        .uiDrag,
        .inputKeyCombo,
        .inputKeySequence,
        .uiGesture,
        .menuSelect,
        .windowFocus,
        .windowExclude,
        .textAttach,
        .textDetach,
        .textInsert,
        .textSendKeys,
        .mediaScreenshot,
        .scrollTo,
        .scrollUntil,
        .scrollIntoView,
        .mediaMusicVolume,
        .displayAirPlayConnect,
        .displayAirPlayDisconnect,
        .systemConfirmationResolve,
        .remotePair,
        .remoteRevoke,
    ]
}

public extension ActionResult {
    static func confirmationRequired(for request: ActionRequest, approval: ApprovalRequest) -> ActionResult {
        ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .confirmationRequired,
            message: approval.reason,
            payload: [
                "approvalID": .string(approval.id.uuidString),
                "summary": .string(approval.summary),
            ]
        )
    }
}
