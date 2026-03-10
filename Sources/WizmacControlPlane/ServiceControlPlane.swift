import AppKit
import Foundation
import WizmacCore
import WizmacSystem

public enum LocalWizmacServiceConfiguration {
    public static let endpoint = "xpc://wizmac/service"

    public static var endpointURL: URL {
        URL(string: endpoint)!
    }

    public static var endpointFileURL: URL {
        (try? WizmacPaths.serviceEndpointURL()) ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wizmac-service-endpoint.xpc")
    }
}

public actor WizmacServiceRuntime {
    private let settingsStore: SettingsStore
    private let auditStore: AuditStore
    private let approvalStore: ApprovalStore
    private let stateStore: ServiceStateStore
    private let identityStore: RemoteIdentityStore
    private let permissionInspector: PermissionInspector
    private let approvalPolicy: ApprovalPolicy
    private let trustedSessionStore: TrustedAutomationSessionStore
    private let bus: CommandBus

    private var health: ServiceHealth
    private var textSession = ServiceTextSessionStatus()
    private var uiSession = UISessionState()
    private var hintSession = HintSessionState()
    private var scrollSession = ScrollSessionState()
    private var trustedAutomationSession = TrustedAutomationSessionState()

    public init() throws {
        let settingsStore = try SettingsStore()
        let auditStore = try AuditStore()
        let approvalStore = try ApprovalStore()
        let trustedSessionStore = TrustedAutomationSessionStore()

        self.settingsStore = settingsStore
        self.auditStore = auditStore
        self.approvalStore = approvalStore
        self.stateStore = try ServiceStateStore()
        self.identityStore = try RemoteIdentityStore()
        self.permissionInspector = PermissionInspector()
        self.trustedSessionStore = trustedSessionStore
        self.approvalPolicy = ApprovalPolicy(
            settingsStore: settingsStore,
            trustedSessionStore: trustedSessionStore
        )
        self.bus = try WizmacRuntimeFactory.makeCommandBus(
            trustedSessionStore: trustedSessionStore
        )
        self.health = ServiceHealth(
            status: .starting,
            localControlPlaneURL: LocalWizmacServiceConfiguration.endpointURL.absoluteString
        )
    }

    public func bootstrap() async {
        let settings = (try? await settingsStore.load()) ?? WizmacSettings()
        await pruneRemoteIdentities(allowedClientIDs: Set(settings.remoteServer.issuedClients.map(\.id)))
        health.status = .running
        health.remoteEnabled = settings.remoteServer.enabled
        health.remoteControlPlaneURL = settings.remoteServer.enabled
            ? "http://\(settings.remoteServer.host):\(settings.remoteServer.port)/rpc"
            : nil
        await persistHealth()
    }

    public func recordRemoteServer(enabled: Bool, url: String?, lastError: String?) async {
        health.remoteEnabled = enabled
        health.remoteControlPlaneURL = url
        health.lastError = lastError
        health.status = lastError == nil ? .running : .degraded
        await persistHealth()
    }

    public func currentHealth() async -> ServiceHealth {
        trustedAutomationSession = await trustedSessionStore.status()
        health.activeSessionCount = activeSessions().count
        return health
    }

    public func currentSettings() async -> WizmacSettings {
        (try? await settingsStore.load()) ?? WizmacSettings()
    }

    public func snapshot() async -> WizmacServiceSnapshot {
        trustedAutomationSession = await trustedSessionStore.status()
        let settings = (try? await settingsStore.load()) ?? WizmacSettings()
        let audit = (try? await auditStore.recent(limit: 12)) ?? []
        let approvals = await bus.pendingApprovals()
        let permissions = permissionInspector.currentStatuses()
        let remoteClients = settings.remoteServer.issuedClients
        return WizmacServiceSnapshot(
            health: await currentHealth(),
            permissions: permissions,
            recentAudit: audit.reversed(),
            pendingApprovals: approvals,
            settings: settings,
            remoteClients: remoteClients,
            activeSessions: activeSessions(),
            textSession: textSession,
            uiSession: uiSession,
            hintSession: hintSession,
            scrollSession: scrollSession,
            trustedAutomationSession: trustedAutomationSession
        )
    }

    public func updateSettings(_ patch: WizmacSettingsPatch) async throws -> WizmacSettings {
        let settings = try await settingsStore.update { settings in
            if let interfaces = patch.interfaces {
                for (key, value) in interfaces {
                    settings.interfaces[key] = value
                }
            }
            if let labelAlphabet = patch.labelAlphabet {
                settings.labelAlphabet = labelAlphabet
            }
            if let launchAtLogin = patch.launchAtLogin {
                settings.launchAtLogin = launchAtLogin
            }
            if let onboardingState = patch.onboardingState {
                settings.onboardingState = onboardingState
            }
            if let hotkeys = patch.hotkeys {
                settings.hotkeys = hotkeys
            }
            if let hotkeyProfiles = patch.hotkeyProfiles {
                settings.hotkeyProfiles = hotkeyProfiles
            }
            if let gridFallbackEnabled = patch.gridFallbackEnabled {
                settings.gridFallbackEnabled = gridFallbackEnabled
            }
            if let remote = patch.remoteServer {
                if let enabled = remote.enabled {
                    settings.remoteServer.enabled = enabled
                }
                if let host = remote.host {
                    settings.remoteServer.host = host
                }
                if let port = remote.port {
                    settings.remoteServer.port = port
                }
                if let bindMode = remote.bindMode {
                    settings.remoteServer.bindMode = bindMode
                }
                if let certificateDirectory = remote.certificateDirectory {
                    settings.remoteServer.certificateDirectory = certificateDirectory
                }
            }
        }

        health.remoteEnabled = settings.remoteServer.enabled
        health.remoteControlPlaneURL = settings.remoteServer.enabled
            ? "http://\(settings.remoteServer.host):\(settings.remoteServer.port)/rpc"
            : nil
        await pruneRemoteIdentities(allowedClientIDs: Set(settings.remoteServer.issuedClients.map(\.id)))
        await persistHealth()
        return settings
    }

    public func handle(_ request: ActionRequest) async -> ActionResult {
        switch request.action {
        case .systemHealth:
            return await performServiceAction(request) {
                ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .success,
                    message: "Fetched service health.",
                    payload: encodeJSON(await currentHealth())
                )
            }
        case .systemSessions:
            return await performServiceAction(request) {
                ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .success,
                    message: "Fetched active sessions.",
                    payload: encodeJSON(activeSessions())
                )
            }
        case .systemTrustedSessionStart:
            return await performServiceAction(request) {
                await handleTrustedSessionStart(request)
            }
        case .systemTrustedSessionEnd:
            return await performServiceAction(request) {
                await handleTrustedSessionEnd(request)
            }
        case .systemConfirmationResolve:
            guard
                let approvalID = request.string(for: "approvalID"),
                let decisionRaw = request.string(for: "decision"),
                let id = UUID(uuidString: approvalID),
                let decision = ApprovalDecision(rawValue: decisionRaw)
            else {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .invalidRequest,
                    message: "Missing approvalID or decision."
                )
            }
            do {
                guard let record = try await approvalStore.resolve(id: id) else {
                    return ActionResult(
                        requestID: UUID(),
                        action: .systemConfirmationResolve,
                        outcome: .notFound,
                        message: "No pending approval found for \(id.uuidString)."
                    )
                }
                if isServiceOwnedAction(record.request.action) {
                    return await finalizeServiceApproval(record, decision: decision)
                }
                return await bus.finalizeResolvedApproval(record, decision: decision)
            } catch {
                return ActionResult(
                    requestID: UUID(),
                    action: .systemConfirmationResolve,
                    outcome: .failed,
                    message: error.localizedDescription
                )
            }
        case .windowExclude:
            return await performServiceAction(request) {
                await handleWindowExclude(request)
            }
        case .remoteClients:
            return await performServiceAction(request) {
                await handleRemoteClients(request)
            }
        case .remotePair:
            return await performServiceAction(request) {
                await handleRemotePair(request)
            }
        case .remoteRevoke:
            return await performServiceAction(request) {
                await handleRemoteRevoke(request)
            }
        default:
            let result = await bus.dispatch(request)
            applySessionState(for: request, result: result)
            return result
        }
    }

    public func listResources() async -> [ControlPlaneResourceDefinition] {
        [
            ControlPlaneResourceDefinition(
                uri: "wizmac://permissions",
                name: "Permissions",
                description: "Current accessibility and automation permissions."
            ),
            ControlPlaneResourceDefinition(
                uri: "wizmac://audit",
                name: "Audit Trail",
                description: "Recent audit entries from the shared service."
            ),
            ControlPlaneResourceDefinition(
                uri: "wizmac://approvals",
                name: "Pending Approvals",
                description: "Pending confirmations for risky actions."
            ),
            ControlPlaneResourceDefinition(
                uri: "wizmac://sessions",
                name: "Sessions",
                description: "Current text, hint, and scroll session state."
            ),
            ControlPlaneResourceDefinition(
                uri: "wizmac://health",
                name: "Service Health",
                description: "Status of the shared Wizmac service."
            ),
        ]
    }

    public func readResource(uri: String) async throws -> StructuredValue {
        let snapshot = await snapshot()
        switch uri {
        case "wizmac://permissions":
            return encodeStructured(snapshot.permissions)
        case "wizmac://audit":
            return encodeStructured(snapshot.recentAudit)
        case "wizmac://approvals":
            return encodeStructured(snapshot.pendingApprovals)
        case "wizmac://sessions":
            return encodeStructured(snapshot.activeSessions)
        case "wizmac://health":
            return encodeStructured(snapshot.health)
        default:
            throw ControlPlaneError.unsupported("Unknown resource '\(uri)'.")
        }
    }

    public func registeredRemoteHTTPIdentities() async -> [String: HTTPRemoteIdentityRecord] {
        let settings = (try? await settingsStore.load()) ?? WizmacSettings()
        let allowedClientIDs = Set(settings.remoteServer.issuedClients.map { $0.id.uuidString })
        let allIdentities = (try? await identityStore.httpIdentityRecordsByClientID()) ?? [:]
        return allIdentities.filter { allowedClientIDs.contains($0.key) }
    }
}

private extension WizmacServiceRuntime {
    func performServiceAction(
        _ request: ActionRequest,
        execute: () async -> ActionResult
    ) async -> ActionResult {
        do {
            if let approval = try await approvalPolicy.evaluate(request) {
                try await approvalStore.enqueue(PendingApprovalRecord(approval: approval, request: request))
                let result = ActionResult.confirmationRequired(for: request, approval: approval)
                try await auditStore.append(
                    AuditEntry(
                        request: request,
                        outcome: result.outcome,
                        message: "Queued for approval: \(approval.summary)"
                    )
                )
                return result
            }

            let result = await execute()
            try await auditStore.append(
                AuditEntry(request: request, outcome: result.outcome, message: result.message)
            )
            return result
        } catch {
            let result = ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .failed,
                message: error.localizedDescription
            )
            try? await auditStore.append(
                AuditEntry(request: request, outcome: result.outcome, message: result.message)
            )
            return result
        }
    }

    func executeServiceOwnedAction(_ request: ActionRequest) async -> ActionResult {
        switch request.action {
        case .systemHealth:
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .success,
                message: "Fetched service health.",
                payload: encodeJSON(await currentHealth())
            )
        case .systemSessions:
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .success,
                message: "Fetched active sessions.",
                payload: encodeJSON(activeSessions())
            )
        case .systemTrustedSessionStart:
            return await handleTrustedSessionStart(request)
        case .systemTrustedSessionEnd:
            return await handleTrustedSessionEnd(request)
        case .windowExclude:
            return await handleWindowExclude(request)
        case .remoteClients:
            return await handleRemoteClients(request)
        case .remotePair:
            return await handleRemotePair(request)
        case .remoteRevoke:
            return await handleRemoteRevoke(request)
        default:
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .unsupported,
                message: "This action is not owned by the shared service runtime."
            )
        }
    }

    func finalizeServiceApproval(
        _ record: PendingApprovalRecord,
        decision: ApprovalDecision
    ) async -> ActionResult {
        if decision == .reject {
            let result = ActionResult(
                requestID: record.request.id,
                action: record.request.action,
                outcome: .failed,
                message: "Action rejected."
            )
            try? await auditStore.append(
                AuditEntry(request: record.request, outcome: result.outcome, message: result.message)
            )
            return result
        }

        let result = await executeServiceOwnedAction(record.request)
        try? await auditStore.append(
            AuditEntry(request: record.request, outcome: result.outcome, message: result.message)
        )
        return result
    }

    func isServiceOwnedAction(_ action: ActionName) -> Bool {
        switch action {
        case .systemHealth, .systemSessions, .systemTrustedSessionStart, .systemTrustedSessionEnd, .windowExclude, .remoteClients, .remotePair, .remoteRevoke:
            return true
        default:
            return false
        }
    }

    func pruneRemoteIdentities(allowedClientIDs: Set<UUID>) async {
        try? await identityStore.retainOnly(clientIDs: allowedClientIDs)
    }

    func handleWindowExclude(_ request: ActionRequest) async -> ActionResult {
        guard let appName = request.string(for: "appName"), let title = request.string(for: "title") else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .invalidRequest,
                message: "Missing appName or title."
            )
        }

        let shouldExclude = request.bool(for: "excluded") ?? true
        let settings = try? await settingsStore.update { settings in
            let rule = ExcludedWindowRule(appName: appName, title: title)
            settings.excludedWindows.removeAll { $0.id == rule.id }
            if shouldExclude {
                settings.excludedWindows.append(rule)
            }
        }

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: settings == nil ? .failed : .success,
            message: shouldExclude ? "Window exclusion added." : "Window exclusion removed.",
            payload: settings.map { encodeJSON($0.excludedWindows) }
        )
    }

    func handleRemoteClients(_ request: ActionRequest) async -> ActionResult {
        let settings = (try? await settingsStore.load()) ?? WizmacSettings()
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Fetched remote clients.",
            payload: encodeJSON(settings.remoteServer.issuedClients)
        )
    }

    func handleRemotePair(_ request: ActionRequest) async -> ActionResult {
        let name = request.string(for: "name") ?? "Unnamed Client"
        let recordID = UUID()
        let currentSettings = (try? await settingsStore.load()) ?? WizmacSettings()
        guard let enrollmentBundle = try? await identityStore.enroll(
            clientID: recordID,
            name: name,
            serverHost: currentSettings.remoteServer.host,
            serverPort: currentSettings.remoteServer.port
        ) else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .failed,
                message: "Unable to generate a remote enrollment bundle."
            )
        }

        let record = RemoteClientRecord(
            id: recordID,
            name: name,
            fingerprint: enrollmentBundle.identity.fingerprint.value
        )
        let certificateDirectory = try? WizmacPaths.certificateDirectory().path

        let updatedSettings = try? await settingsStore.update { settings in
            settings.remoteServer.issuedClients.removeAll { $0.id == recordID }
            settings.remoteServer.issuedClients.append(record)
            if settings.remoteServer.certificateDirectory == nil {
                settings.remoteServer.certificateDirectory = certificateDirectory
            }
        }
        guard let settings = updatedSettings else {
            try? await identityStore.revoke(clientID: recordID)
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .failed,
                message: "Unable to persist the paired remote client."
            )
        }
        await pruneRemoteIdentities(allowedClientIDs: Set(settings.remoteServer.issuedClients.map(\.id)))

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Paired remote client '\(name)'.",
            payload: encodeJSON(
                RemoteEnrollmentBundle(
                    identity: enrollmentBundle.identity,
                    clientCertificatePEM: enrollmentBundle.clientCertificatePEM,
                    clientPrivateKeyPEM: enrollmentBundle.clientPrivateKeyPEM,
                    certificateAuthorityPEM: enrollmentBundle.certificateAuthorityPEM,
                    serverHost: settings.remoteServer.host,
                    serverPort: settings.remoteServer.port,
                    serverCertificateFingerprint: enrollmentBundle.serverCertificateFingerprint
                )
            )
        )
    }

    func handleRemoteRevoke(_ request: ActionRequest) async -> ActionResult {
        let fingerprint = request.string(for: "fingerprint")
        let clientID = request.string(for: "clientID").flatMap(UUID.init(uuidString:))
        let currentSettings = (try? await settingsStore.load()) ?? WizmacSettings()
        let revokedClient = currentSettings.remoteServer.issuedClients.first { client in
            if let fingerprint, client.fingerprint == fingerprint {
                return true
            }
            if let clientID, client.id == clientID {
                return true
            }
            return false
        }

        let updated = try? await settingsStore.update { settings in
            settings.remoteServer.issuedClients.removeAll { client in
                if let fingerprint, client.fingerprint == fingerprint {
                    return true
                }
                if let clientID, client.id == clientID {
                    return true
                }
                return false
            }
        }

        if let clientID {
            try? await identityStore.revoke(clientID: clientID)
        } else if let revokedClient {
            try? await identityStore.revoke(clientID: revokedClient.id)
        }
        if let updated {
            await pruneRemoteIdentities(allowedClientIDs: Set(updated.remoteServer.issuedClients.map(\.id)))
        }

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: updated == nil ? .failed : .success,
            message: "Revoked remote client.",
            payload: updated.map { encodeJSON($0.remoteServer.issuedClients) }
        )
    }

    func handleTrustedSessionStart(_ request: ActionRequest) async -> ActionResult {
        if request.origin.kind == .remote {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .failed,
                message: "Trusted local sessions are only available to local Wizmac clients."
            )
        }

        let requestedPID = request.int(for: "pid").map(pid_t.init)
        let requestedApp = request.string(for: "app")
        let runningApp = requestedPID.flatMap(NSRunningApplication.init(processIdentifier:))
            ?? NSWorkspace.shared.runningApplications.first {
                guard let requestedApp else { return false }
                return $0.localizedName == requestedApp || $0.bundleIdentifier == requestedApp
            }
            ?? NSWorkspace.shared.frontmostApplication

        let duration = TimeInterval(request.int(for: "durationSeconds") ?? 600)
        let allowedActions: [ActionName] = [
            .uiAct,
            .uiCopy,
            .uiDrag,
            .textInsert,
            .textAttach,
            .textSendKeys,
            .textDetach,
            .windowFocus,
            .scrollStep,
        ]
        let session = await trustedSessionStore.start(
            appName: runningApp?.localizedName,
            bundleIdentifier: runningApp?.bundleIdentifier,
            processIdentifier: runningApp.map { Int($0.processIdentifier) },
            allowedActions: allowedActions,
            duration: duration
        )
        trustedAutomationSession = await trustedSessionStore.status()

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Started trusted automation session.",
            payload: [
                "trustedSessionID": .string(session.id.uuidString),
                "appName": session.appName.map(JSONValue.string) ?? .null,
                "bundleIdentifier": session.bundleIdentifier.map(JSONValue.string) ?? .null,
                "processIdentifier": session.processIdentifier.map { .number(Double($0)) } ?? .null,
                "startedAt": .string(ISO8601DateFormatter().string(from: session.startedAt)),
                "expiresAt": .string(ISO8601DateFormatter().string(from: session.expiresAt)),
            ]
        )
    }

    func handleTrustedSessionEnd(_ request: ActionRequest) async -> ActionResult {
        let requestedID = request.string(for: "trustedSessionID").flatMap(UUID.init(uuidString:))
        let ended = await trustedSessionStore.end(id: requestedID)
        trustedAutomationSession = await trustedSessionStore.status()

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: ended == nil ? .notFound : .success,
            message: ended == nil ? "No trusted automation session matched the request." : "Ended trusted automation session.",
            payload: ended.map {
                [
                    "trustedSessionID": .string($0.id.uuidString),
                    "appName": $0.appName.map(JSONValue.string) ?? .null,
                    "bundleIdentifier": $0.bundleIdentifier.map(JSONValue.string) ?? .null,
                ]
            }
        )
    }

    func applySessionState(for request: ActionRequest, result: ActionResult) {
        guard result.outcome == .success, let payload = result.payload else { return }

        switch request.action {
        case .uiSearch:
            let targetCount = payload.objectValue?["targets"]?.arrayValue?.count ?? 0
            let timings = payload.objectValue?["timings"]?.objectValue
            uiSession = UISessionState(
                isActive: targetCount > 0,
                sessionID: payload.objectValue?["sessionID"]?.stringValue,
                appName: payload.objectValue?["appName"]?.stringValue,
                windowTitle: payload.objectValue?["windowTitle"]?.stringValue,
                snapshotID: payload.objectValue?["snapshotID"]?.stringValue,
                targetCount: targetCount,
                cacheHitRate: timings?["cacheHit"]?.boolValue == true ? 1 : uiSession.cacheHitRate,
                lastRefreshedAt: .now
            )
        case .uiSessionEnd:
            uiSession = UISessionState()
        case .uiHints:
            let targetCount = payload.objectValue?["targets"]?.arrayValue?.count ?? payload.arrayValue?.count ?? 0
            let appName = payload.objectValue?["appName"]?.stringValue
            hintSession = HintSessionState(
                isActive: targetCount > 0,
                appName: appName,
                targetCount: targetCount,
                query: request.string(for: "query") ?? ""
            )
        case .scrollSessionStart:
            let targetCount = payload.objectValue?["targets"]?.arrayValue?.count ?? 0
            scrollSession = ScrollSessionState(
                isActive: true,
                focusedTargetID: payload.objectValue?["focusedTargetID"]?.stringValue,
                targetCount: targetCount,
                lastDirection: nil
            )
        case .scrollStep:
            scrollSession.isActive = true
            scrollSession.lastDirection = request.string(for: "direction") ?? "down"
        case .scrollSessionEnd:
            scrollSession = ScrollSessionState()
        case .textAttach, .textStatus, .textMode:
            textSession = ServiceTextSessionStatus(
                attachmentID: payload.objectValue?["attachmentID"]?.stringValue,
                mode: payload.objectValue?["mode"]?.stringValue ?? "normal",
                applicationName: payload.objectValue?["application"]?.stringValue,
                elementIdentifier: payload.objectValue?["elementIdentifier"]?.stringValue,
                isSecureInput: payload.objectValue?["isSecureInput"]?.boolValue ?? false
            )
        case .textInsert:
            textSession = ServiceTextSessionStatus(
                attachmentID: activeTextSessionIdentifier(from: payload),
                mode: "insert",
                applicationName: payload.objectValue?["application"]?.stringValue,
                elementIdentifier: payload.objectValue?["elementIdentifier"]?.stringValue,
                isSecureInput: false
            )
        case .textDetach:
            textSession = ServiceTextSessionStatus()
        default:
            break
        }
    }

    func activeSessions() -> [ServiceSessionRecord] {
        var sessions: [ServiceSessionRecord] = []

        if uiSession.isActive {
            sessions.append(
                ServiceSessionRecord(
                    kind: .ui,
                    title: "UI Cache",
                    detail: "\(uiSession.targetCount) targets in \(uiSession.appName ?? "frontmost app"), hit rate \(Int(uiSession.cacheHitRate * 100))%"
                )
            )
        }

        if hintSession.isActive {
            sessions.append(
                ServiceSessionRecord(
                    kind: .hint,
                    title: "UI Hints",
                    detail: "\(hintSession.targetCount) targets in \(hintSession.appName ?? "frontmost app")"
                )
            )
        }

        if scrollSession.isActive {
            sessions.append(
                ServiceSessionRecord(
                    kind: .scroll,
                    title: "Scroll Session",
                    detail: scrollSession.focusedTargetID ?? "Active scroll target"
                )
            )
        }

        if textSession.attachmentID != nil {
            sessions.append(
                ServiceSessionRecord(
                    kind: .text,
                    title: "Text Mode",
                    detail: "\(textSession.mode) in \(textSession.applicationName ?? "focused input")"
                )
            )
        }

        if trustedAutomationSession.isActive {
            sessions.append(
                ServiceSessionRecord(
                    kind: .trustedAutomation,
                    title: "Trusted Automation",
                    detail: trustedAutomationSession.appName ?? trustedAutomationSession.bundleIdentifier ?? "Local trusted session"
                )
            )
        }

        return sessions
    }

    func activeTextSessionIdentifier(from payload: JSONValue) -> String? {
        payload.objectValue?["attachmentID"]?.stringValue
    }

    func persistHealth() async {
        try? await stateStore.save(health)
    }
}

public struct ServiceBackedControlPlaneRouter: ControlPlaneRouting {
    private let runtime: WizmacServiceRuntime

    public init(runtime: WizmacServiceRuntime) {
        self.runtime = runtime
    }

    public func handle(_ request: ControlPlaneActionRequest) async throws -> ControlPlaneActionResponse {
        let rawAction = "\(request.namespace).\(request.action)"
        guard let action = ActionName(rawValue: rawAction) else {
            return ControlPlaneActionResponse(
                status: .invalidRequest,
                message: "Unsupported action '\(rawAction)'."
            )
        }

        var arguments = request.arguments.mapValues(\.jsonValue)
        if let operation = request.arguments["operation"], arguments["interaction"] == nil {
            arguments["interaction"] = operation.jsonValue
        }
        if let token = request.arguments["token"], arguments["approvalID"] == nil {
            arguments["approvalID"] = token.jsonValue
        }

        let origin = RequestOrigin(
            kind: request.source.requestOriginKind,
            sessionID: request.source.sessionID,
            remoteAddress: request.source.clientID
        )

        let result = await runtime.handle(
            ActionRequest(action: action, arguments: arguments, origin: origin)
        )

        return ControlPlaneActionResponse(
            status: result.outcome.controlPlaneStatus,
            payload: result.payload?.structuredValue,
            message: result.message,
            auditID: result.requestID.uuidString,
            confirmationToken: result.payload?.objectValue?["approvalID"]?.stringValue
        )
    }

    public func health() async throws -> ServiceHealth {
        await runtime.currentHealth()
    }

    public func snapshot() async throws -> WizmacServiceSnapshot {
        await runtime.snapshot()
    }

    public func updateSettings(_ patch: WizmacSettingsPatch) async throws -> WizmacSettings {
        try await runtime.updateSettings(patch)
    }

    public func listResources() async throws -> [ControlPlaneResourceDefinition] {
        await runtime.listResources()
    }

    public func readResource(uri: String) async throws -> StructuredValue {
        try await runtime.readResource(uri: uri)
    }
}

public actor WizmacServiceProcessManager {
    public static let shared = WizmacServiceProcessManager()
    private let xpcClient: WizmacXPCClient

    public init() {
        self.xpcClient = WizmacXPCClient()
    }

    public func ensureRunning() async throws {
        if await isRunning() {
            return
        }

        try launchServiceProcess()
        for _ in 0..<20 {
            if await isRunning() {
                return
            }
            try await Task.sleep(for: .milliseconds(250))
        }

        throw ControlPlaneError.unsupported("Unable to start the Wizmac service process.")
    }

    public func isRunning() async -> Bool {
        do {
            let response = try await xpcClient.send(
                request: JSONRPCRequest(id: .string("health"), method: "ping"),
                source: ControlPlaneSource(kind: .cli),
                ensureRunning: false
            )
            return response.error == nil
        } catch {
            return false
        }
    }

    private func launchServiceProcess() throws {
        let process = Process()
        let command = try resolveServiceLaunchCommand()
        process.executableURL = command.url
        process.arguments = command.arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["WIZMAC_SERVICE_PROCESS"] = "1"
        process.environment = environment
        try process.run()
    }

    private func resolveServiceLaunchCommand() throws -> (url: URL, arguments: [String]) {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["WIZMAC_SERVICE_BIN"], FileManager.default.isExecutableFile(atPath: override) {
            return (URL(fileURLWithPath: override), [])
        }

        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let candidates = [
            (executable.deletingLastPathComponent().appendingPathComponent("WizmacService"), [String]()),
            (URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug/WizmacService"), [String]()),
            (URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/arm64-apple-macosx/debug/WizmacService"), [String]()),
            (executable.deletingLastPathComponent().appendingPathComponent("wizmac"), ["service", "start"]),
            (URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug/wizmac"), ["service", "start"]),
            (URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/arm64-apple-macosx/debug/wizmac"), ["service", "start"]),
        ]

        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.0.path) }) {
            return match
        }

        throw ControlPlaneError.unsupported("Unable to find a Wizmac service executable or `wizmac service start` command.")
    }
}

public actor WizmacServiceClient {
    private let manager: WizmacServiceProcessManager
    private let xpcClient: WizmacXPCClient
    private let sourceKind: ControlPlaneSourceKind

    public init(
        manager: WizmacServiceProcessManager = .shared,
        sourceKind: ControlPlaneSourceKind = .cli
    ) {
        self.manager = manager
        self.xpcClient = WizmacXPCClient(processManager: manager)
        self.sourceKind = sourceKind
    }

    public func callTool(
        named toolName: String,
        arguments: [String: StructuredValue],
        source: ControlPlaneSource
    ) async throws -> ControlPlaneActionResponse {
        let response = try await request(
            JSONRPCRequest(
                id: .string(UUID().uuidString),
                method: "tools/call",
                params: .object([
                    "name": .string(toolName),
                    "arguments": .object(arguments),
                    "source": encodeStructured(source),
                ])
            ),
            source: source
        )

        guard let result = response.result?["structuredContent"] else {
            throw ControlPlaneError.unsupported("Service did not return a structured response.")
        }
        return try decode(result, as: ControlPlaneActionResponse.self)
    }

    public func health() async throws -> ServiceHealth {
        try decodeResult(
            try await request(
                JSONRPCRequest(id: .string("health"), method: "service.health"),
                source: ControlPlaneSource(kind: sourceKind)
            )
        )
    }

    public func snapshot() async throws -> WizmacServiceSnapshot {
        try decodeResult(
            try await request(
                JSONRPCRequest(id: .string("snapshot"), method: "service.snapshot"),
                source: ControlPlaneSource(kind: sourceKind)
            )
        )
    }

    public func settings() async throws -> WizmacSettings {
        try decodeResult(
            try await request(
                JSONRPCRequest(id: .string("settings.get"), method: "service.settings.get"),
                source: ControlPlaneSource(kind: sourceKind)
            )
        )
    }

    public func updateSettings(_ patch: WizmacSettingsPatch) async throws -> WizmacSettings {
        try decodeResult(
            try await request(
                JSONRPCRequest(
                    id: .string("settings"),
                    method: "service.settings.update",
                    params: .object(["patch": encodeStructured(patch)])
                ),
                source: ControlPlaneSource(kind: sourceKind)
            )
        )
    }

    public func listRemoteClients() async throws -> [RemoteClientRecord] {
        let response = try await callTool(
            named: "remote.clients",
            arguments: [:],
            source: ControlPlaneSource(kind: sourceKind)
        )
        guard let payload = response.payload else { return [] }
        return try decode(payload, as: [RemoteClientRecord].self)
    }

    public func pairRemoteClient(name: String) async throws -> RemoteEnrollmentBundle {
        let response = try await callTool(
            named: "remote.pair",
            arguments: ["name": .string(name)],
            source: ControlPlaneSource(kind: sourceKind)
        )
        guard let payload = response.payload else {
            throw ControlPlaneError.unsupported("Service did not return pairing data.")
        }
        return try decode(payload, as: RemoteEnrollmentBundle.self)
    }

    public func revokeRemoteClient(id: UUID) async throws -> [RemoteClientRecord] {
        let response = try await callTool(
            named: "remote.revoke",
            arguments: ["clientID": .string(id.uuidString)],
            source: ControlPlaneSource(kind: sourceKind)
        )
        guard let payload = response.payload else { return [] }
        return try decode(payload, as: [RemoteClientRecord].self)
    }

    public func resolveApproval(id: UUID, decision: ApprovalDecision) async throws -> ControlPlaneActionResponse {
        try await callTool(
            named: "system.confirmation_resolve",
            arguments: [
                "approvalID": .string(id.uuidString),
                "decision": .string(decision.rawValue),
            ],
            source: ControlPlaneSource(kind: sourceKind)
        )
    }

    public func readResource(_ uri: String) async throws -> StructuredValue {
        let response = try await request(
            JSONRPCRequest(
                id: .string(UUID().uuidString),
                method: "resources/read",
                params: .object(["uri": .string(uri)])
            ),
            source: ControlPlaneSource(kind: sourceKind)
        )
        guard let text = response.result?["contents"]?.arrayValue?.first?["text"]?.stringValue else {
            return .null
        }
        guard let data = text.data(using: .utf8) else {
            return .string(text)
        }
        return (try? JSONDecoder().decode(StructuredValue.self, from: data)) ?? .string(text)
    }

    public func readResources() async throws -> [ControlPlaneResourceDefinition] {
        let response = try await request(
            JSONRPCRequest(
                id: .string(UUID().uuidString),
                method: "resources/list"
            ),
            source: ControlPlaneSource(kind: sourceKind)
        )
        let resources = response.result?["resources"] ?? .array([])
        return try decode(resources, as: [ControlPlaneResourceDefinition].self)
    }

    private func request(
        _ rpcRequest: JSONRPCRequest,
        source: ControlPlaneSource? = nil
    ) async throws -> JSONRPCResponse {
        try await manager.ensureRunning()
        return try await xpcClient.send(
            request: rpcRequest,
            source: source ?? ControlPlaneSource(kind: sourceKind),
            ensureRunning: false
        )
    }

    private func decodeResult<T: Decodable>(_ response: JSONRPCResponse) throws -> T {
        guard let result = response.result else {
            throw ControlPlaneError.unsupported(response.error?.message ?? "No result returned from service.")
        }
        return try decode(result, as: T.self)
    }
}

public struct ServiceClientControlPlaneRouter: ControlPlaneRouting {
    private let client: WizmacServiceClient

    public init(client: WizmacServiceClient = WizmacServiceClient()) {
        self.client = client
    }

    public func handle(_ request: ControlPlaneActionRequest) async throws -> ControlPlaneActionResponse {
        try await client.callTool(
            named: request.toolName,
            arguments: request.arguments,
            source: request.source
        )
    }

    public func health() async throws -> ServiceHealth {
        try await client.health()
    }

    public func snapshot() async throws -> WizmacServiceSnapshot {
        try await client.snapshot()
    }

    public func updateSettings(_ patch: WizmacSettingsPatch) async throws -> WizmacSettings {
        try await client.updateSettings(patch)
    }

    public func listResources() async throws -> [ControlPlaneResourceDefinition] {
        try await client.readResources()
    }

    public func readResource(uri: String) async throws -> StructuredValue {
        try await client.readResource(uri)
    }
}

public final class WizmacServiceHost: @unchecked Sendable {
    private let runtime: WizmacServiceRuntime
    private let dispatcher: ControlPlaneDispatcher
    private var localServer: HTTPJSONRPCServer?
    private var remoteServer: HTTPJSONRPCServer?
    private var remoteServerSignature: RemoteServerSignature?

    public init() throws {
        let runtime = try WizmacServiceRuntime()
        self.runtime = runtime
        self.dispatcher = ControlPlaneDispatcher(router: ServiceBackedControlPlaneRouter(runtime: runtime))
    }

    public func start() async throws {
        let localConfig = HTTPJSONRPCServerConfiguration(
            host: "127.0.0.1",
            port: WizmacLocalService.port,
            path: "/rpc",
            allowedRemoteIdentities: [:]
        )
        let server = HTTPJSONRPCServer(dispatcher: dispatcher, configuration: localConfig)
        try server.start()
        localServer = server
        await runtime.bootstrap()
        do {
            try await syncRemoteServer()
        } catch {
            await runtime.recordRemoteServer(
                enabled: false,
                url: nil,
                lastError: error.localizedDescription
            )
        }
    }

    public func runUntilCancelled() async throws {
        while true {
            do {
                try await syncRemoteServer()
            } catch {
                await runtime.recordRemoteServer(
                    enabled: false,
                    url: nil,
                    lastError: error.localizedDescription
                )
            }
            try await Task.sleep(for: .seconds(2))
        }
    }

    private func syncRemoteServer() async throws {
        let snapshot = await runtime.snapshot()
        let settings = snapshot.settings.remoteServer

        if settings.enabled == false {
            remoteServer?.stop()
            remoteServer = nil
            remoteServerSignature = nil
            await runtime.recordRemoteServer(enabled: false, url: nil, lastError: nil)
            return
        }

        let bindHost = resolvedRemoteBindHost(from: settings)
        let advertisedHost = advertisedRemoteHost(from: settings)
        let allowedRemoteIdentities = await runtime.registeredRemoteHTTPIdentities()
        let signature = RemoteServerSignature(
            host: bindHost,
            port: UInt16(settings.port),
            path: "/rpc",
            allowedRemoteIdentityFingerprints: allowedRemoteIdentities.mapValues(\.fingerprint)
        )

        if remoteServer != nil, remoteServerSignature == signature {
            await runtime.recordRemoteServer(
                enabled: true,
                url: "http://\(advertisedHost):\(settings.port)/rpc",
                lastError: nil
            )
            return
        }

        let configuration = HTTPJSONRPCServerConfiguration(
            host: bindHost,
            port: UInt16(settings.port),
            path: "/rpc",
            allowedRemoteIdentities: allowedRemoteIdentities
        )

        remoteServer?.stop()
        let server = HTTPJSONRPCServer(dispatcher: dispatcher, configuration: configuration)
        try server.start()
        remoteServer = server
        remoteServerSignature = signature
        await runtime.recordRemoteServer(
            enabled: true,
            url: "http://\(advertisedHost):\(settings.port)/rpc",
            lastError: nil
        )
    }

    private func resolvedRemoteBindHost(from settings: RemoteServerSettings) -> String {
        switch settings.bindMode {
        case .localhost:
            return "127.0.0.1"
        case .lan:
            return "0.0.0.0"
        case .custom:
            return settings.host
        }
    }

    private func advertisedRemoteHost(from settings: RemoteServerSettings) -> String {
        switch settings.bindMode {
        case .localhost:
            return "127.0.0.1"
        case .lan, .custom:
            return settings.host
        }
    }
}

private func encodeJSON<T: Encodable>(_ value: T) -> JSONValue {
    let encoder = JSONEncoder()
    guard
        let data = try? encoder.encode(value),
        let json = try? JSONDecoder().decode(JSONValue.self, from: data)
    else {
        return .null
    }
    return json
}

private func encodeStructured<T: Encodable>(_ value: T) -> StructuredValue {
    let encoder = JSONEncoder()
    guard
        let data = try? encoder.encode(value),
        let structured = try? JSONDecoder().decode(StructuredValue.self, from: data)
    else {
        return .null
    }
    return structured
}

private func decode<T: Decodable>(_ value: StructuredValue, as type: T.Type) throws -> T {
    let encoder = JSONEncoder()
    let data = try encoder.encode(value)
    return try JSONDecoder().decode(type, from: data)
}

private struct RemoteServerSignature: Equatable {
    let host: String
    let port: UInt16
    let path: String
    let allowedRemoteIdentityFingerprints: [String: String]
}
