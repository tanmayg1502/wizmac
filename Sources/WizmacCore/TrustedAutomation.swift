import Foundation

public struct TrustedAutomationSession: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var appName: String?
    public var bundleIdentifier: String?
    public var processIdentifier: Int?
    public var allowedActions: [ActionName]
    public var startedAt: Date
    public var expiresAt: Date

    public init(
        id: UUID = UUID(),
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        processIdentifier: Int? = nil,
        allowedActions: [ActionName],
        startedAt: Date = Date(),
        expiresAt: Date
    ) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.allowedActions = allowedActions
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool {
        expiresAt <= Date()
    }
}

public actor TrustedAutomationSessionStore {
    private var activeSession: TrustedAutomationSession?

    public init() {}

    public func start(
        appName: String?,
        bundleIdentifier: String?,
        processIdentifier: Int?,
        allowedActions: [ActionName],
        duration: TimeInterval = 600
    ) -> TrustedAutomationSession {
        let session = TrustedAutomationSession(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            allowedActions: allowedActions,
            expiresAt: Date().addingTimeInterval(duration)
        )
        activeSession = session
        return session
    }

    @discardableResult
    public func end(id: UUID? = nil) -> TrustedAutomationSession? {
        pruneIfExpired()
        guard let activeSession else { return nil }
        guard id == nil || activeSession.id == id else { return nil }
        self.activeSession = nil
        return activeSession
    }

    public func currentSession() -> TrustedAutomationSession? {
        pruneIfExpired()
        return activeSession
    }

    public func status() -> TrustedAutomationSessionState {
        pruneIfExpired()
        guard let activeSession else { return TrustedAutomationSessionState() }
        return TrustedAutomationSessionState(
            isActive: true,
            id: activeSession.id.uuidString,
            appName: activeSession.appName,
            bundleIdentifier: activeSession.bundleIdentifier,
            startedAt: activeSession.startedAt,
            expiresAt: activeSession.expiresAt
        )
    }

    public func allows(_ request: ActionRequest) -> Bool {
        pruneIfExpired()
        guard let activeSession else { return false }
        guard Self.localOrigins.contains(request.origin.kind) else { return false }

        let sessionToken = request.string(for: "trustedSessionID") ?? request.origin.sessionID
        guard sessionToken == activeSession.id.uuidString else { return false }
        guard activeSession.allowedActions.contains(request.action) else { return false }

        if let requestedPID = request.int(for: "pid"), requestedPID != activeSession.processIdentifier {
            return false
        }

        if let requestedApp = request.string(for: "app") {
            let normalizedApp = requestedApp.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedApp.isEmpty == false,
               normalizedApp != activeSession.appName,
               normalizedApp != activeSession.bundleIdentifier
            {
                return false
            }
        }

        return true
    }

    private func pruneIfExpired() {
        guard let activeSession, activeSession.isExpired else { return }
        self.activeSession = nil
    }

    private static let localOrigins: Set<RequestOriginKind> = [
        .cli,
        .mcp,
        .menuBar,
        .hotkey,
        .test,
    ]
}
