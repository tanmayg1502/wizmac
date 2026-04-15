import Foundation
import WizmacCore

public protocol ControlPlaneRouting: Sendable {
    func handle(_ request: ControlPlaneActionRequest) async throws -> ControlPlaneActionResponse
    func health() async throws -> ServiceHealth
    func snapshot() async throws -> WizmacServiceSnapshot
    func updateSettings(_ patch: WizmacSettingsPatch) async throws -> WizmacSettings
    func listResources() async throws -> [ControlPlaneResourceDefinition]
    func readResource(uri: String) async throws -> StructuredValue
}

public extension ControlPlaneRouting {
    func health() async throws -> ServiceHealth {
        ServiceHealth(status: .stopped)
    }

    func snapshot() async throws -> WizmacServiceSnapshot {
        WizmacServiceSnapshot(
            health: ServiceHealth(status: .stopped),
            permissions: [],
            recentAudit: [],
            pendingApprovals: [],
            settings: WizmacSettings(),
            remoteClients: [],
            activeSessions: []
        )
    }

    func updateSettings(_ patch: WizmacSettingsPatch) async throws -> WizmacSettings {
        var settings = WizmacSettings()
        if let interfaces = patch.interfaces {
            settings.interfaces = interfaces
        }
        return settings
    }

    func listResources() async throws -> [ControlPlaneResourceDefinition] {
        [
            ControlPlaneResourceDefinition(
                uri: "wizmac://permissions",
                name: "Permissions",
                description: "Current Wizmac permission capabilities."
            ),
            ControlPlaneResourceDefinition(
                uri: "wizmac://audit",
                name: "Audit Trail",
                description: "Recent audit entries from the shared service."
            ),
            ControlPlaneResourceDefinition(
                uri: "wizmac://approvals",
                name: "Pending Approvals",
                description: "Pending approval queue for risky actions."
            ),
            ControlPlaneResourceDefinition(
                uri: "wizmac://sessions",
                name: "Active Sessions",
                description: "Current text, hint, and scroll sessions."
            ),
        ]
    }

    func readResource(uri: String) async throws -> StructuredValue {
        let snapshot = try await snapshot()
        switch uri {
        case "wizmac://permissions":
            return encode(snapshot.permissions)
        case "wizmac://audit":
            return encode(snapshot.recentAudit)
        case "wizmac://approvals":
            return encode(snapshot.pendingApprovals)
        case "wizmac://sessions":
            return encode(snapshot.activeSessions)
        default:
            throw ControlPlaneError.unsupported("Unknown resource '\(uri)'.")
        }
    }
}

public struct ClosureControlPlaneRouter: ControlPlaneRouting {
    private let handler: @Sendable (ControlPlaneActionRequest) async throws -> ControlPlaneActionResponse

    public init(
        _ handler: @escaping @Sendable (ControlPlaneActionRequest) async throws -> ControlPlaneActionResponse
    ) {
        self.handler = handler
    }

    public func handle(_ request: ControlPlaneActionRequest) async throws -> ControlPlaneActionResponse {
        try await handler(request)
    }
}

public struct UnconfiguredControlPlaneRouter: ControlPlaneRouting {
    public init() {}

    public func handle(_ request: ControlPlaneActionRequest) async throws -> ControlPlaneActionResponse {
        ControlPlaneActionResponse(
            status: .unsupported,
            payload: .object([
                "namespace": .string(request.namespace),
                "action": .string(request.action),
                "arguments": .object(request.arguments),
            ]),
            message: "No WizmacCore router has been attached to the control plane yet."
        )
    }
}

public actor ControlPlaneDispatcher {
    public let registry: ControlPlaneToolRegistry
    private let router: any ControlPlaneRouting

    public init(
        registry: ControlPlaneToolRegistry = .default,
        router: any ControlPlaneRouting
    ) {
        self.registry = registry
        self.router = router
    }

    public func callTool(
        named toolName: String,
        arguments: [String: StructuredValue],
        source: ControlPlaneSource
    ) async -> ControlPlaneActionResponse {
        if let syntheticResponse = await syntheticToolResponse(
            named: toolName,
            arguments: arguments,
            source: source
        ) {
            return syntheticResponse
        }

        return await dispatchConcreteTool(
            named: toolName,
            arguments: arguments,
            source: source
        )
    }

    private func dispatchConcreteTool(
        named toolName: String,
        arguments: [String: StructuredValue],
        source: ControlPlaneSource
    ) async -> ControlPlaneActionResponse {
        guard let request = registry.request(for: toolName, arguments: arguments, source: source) else {
            return ControlPlaneActionResponse(
                status: .invalidRequest,
                message: "Unknown tool '\(toolName)'."
            )
        }

        let preparedRequest = await requestWithAutoTrustIfNeeded(request)
        do {
            return try await router.handle(preparedRequest)
        } catch {
            return ControlPlaneActionResponse(
                status: .failed,
                message: error.localizedDescription
            )
        }
    }

    private func requestWithAutoTrustIfNeeded(
        _ request: ControlPlaneActionRequest
    ) async -> ControlPlaneActionRequest {
        guard request.toolName != ActionName.systemTrustedSessionStart.rawValue else {
            return request
        }
        guard request.arguments["autoTrust"]?.boolValue == true else {
            return request
        }
        guard request.arguments["trustedSessionID"] == nil else {
            return request
        }
        guard isTrustedLocalSource(request.source) else {
            return request
        }
        guard let action = ActionName(rawValue: request.toolName),
              TrustedAutomationPolicy.defaultAllowedActions.contains(action)
        else {
            return request
        }
        guard let trustedSessionRequest = registry.request(
            for: ActionName.systemTrustedSessionStart.rawValue,
            arguments: trustedSessionStartArguments(from: request.arguments),
            source: request.source
        ) else {
            return request
        }
        guard let trustedSessionID = try? await router.handle(trustedSessionRequest)
            .payload?["trustedSessionID"]?.stringValue
        else {
            return request
        }

        var arguments = request.arguments
        arguments["trustedSessionID"] = .string(trustedSessionID)
        return ControlPlaneActionRequest(
            correlationID: request.correlationID,
            namespace: request.namespace,
            action: request.action,
            arguments: arguments,
            source: request.source
        )
    }

    private func trustedSessionStartArguments(
        from arguments: [String: StructuredValue]
    ) -> [String: StructuredValue] {
        let keys = ["app", "pid", "launchIfNeeded", "activate"]
        return keys.reduce(into: [:]) { partialResult, key in
            if let value = arguments[key] {
                partialResult[key] = value
            }
        }
    }

    private func isTrustedLocalSource(_ source: ControlPlaneSource) -> Bool {
        switch source.kind {
        case .cli, .mcp, .menuBar:
            return true
        case .http, .automation:
            return false
        }
    }

    public func handleJSONRPC(
        _ request: JSONRPCRequest,
        source: ControlPlaneSource
    ) async -> JSONRPCResponse? {
        switch request.method {
        case "initialize":
            return JSONRPCResponse(
                id: request.id,
                result: MCPProtocol.initializeResult(requestParams: request.params)
            )
        case "notifications/initialized":
            return nil
        case "ping":
            return JSONRPCResponse(id: request.id, result: .object([:]))
        case "tools/list":
            let tools = registry.allTools().map { definition in
                StructuredValue.object([
                    "name": .string(definition.name),
                    "title": .string(definition.title),
                    "description": .string(definition.description),
                    "inputSchema": definition.inputSchema,
                ])
            }
            return JSONRPCResponse(
                id: request.id,
                result: .object(["tools": .array(tools)])
            )
        case "resources/list":
            do {
                let resources = try await router.listResources().map { definition in
                    StructuredValue.object([
                        "uri": .string(definition.uri),
                        "name": .string(definition.name),
                        "description": .string(definition.description),
                    ])
                }
                return JSONRPCResponse(id: request.id, result: .object(["resources": .array(resources)]))
            } catch {
                return JSONRPCResponse(id: request.id, error: JSONRPCStandardError.internalError)
            }
        case "resources/read":
            guard let params = request.params?.objectValue, let uri = params["uri"]?.stringValue else {
                return JSONRPCResponse(id: request.id, error: JSONRPCStandardError.invalidParams)
            }
            do {
                let resource = try await router.readResource(uri: uri)
                return JSONRPCResponse(
                    id: request.id,
                    result: .object([
                        "contents": .array([
                            .object([
                                "uri": .string(uri),
                                "mimeType": .string("application/json"),
                                "text": .string(resource.jsonString(prettyPrinted: true)),
                            ]),
                        ]),
                    ])
                )
            } catch {
                return JSONRPCResponse(id: request.id, error: JSONRPCStandardError.internalError)
            }
        case "tools/call":
            guard let params = request.params?.objectValue else {
                return JSONRPCResponse(id: request.id, error: JSONRPCStandardError.invalidParams)
            }
            guard let toolName = params["name"]?.stringValue else {
                return JSONRPCResponse(id: request.id, error: JSONRPCStandardError.invalidParams)
            }
            let arguments = params["arguments"]?.objectValue ?? [:]
            let result = await callTool(named: toolName, arguments: arguments, source: source)
            return JSONRPCResponse(
                id: request.id,
                result: .object([
                    "content": .array([
                        .object([
                            "type": .string("text"),
                            "text": .string(result.payload?.jsonString(prettyPrinted: true) ?? "{}"),
                        ]),
                    ]),
                    "structuredContent": encoded(result),
                    "isError": .bool(result.status != .success),
                ])
            )
        case "wizmac/health", "service.health":
            do {
                return JSONRPCResponse(id: request.id, result: encode(try await router.health()))
            } catch {
                return JSONRPCResponse(id: request.id, error: JSONRPCStandardError.internalError)
            }
        case "wizmac/snapshot", "service.snapshot":
            do {
                return JSONRPCResponse(id: request.id, result: encode(try await router.snapshot()))
            } catch {
                return JSONRPCResponse(id: request.id, error: JSONRPCStandardError.internalError)
            }
        case "service.settings.get":
            do {
                let snapshot = try await router.snapshot()
                return JSONRPCResponse(id: request.id, result: encode(snapshot.settings))
            } catch {
                return JSONRPCResponse(id: request.id, error: JSONRPCStandardError.internalError)
            }
        case "wizmac/settings/update", "service.settings.update":
            guard let params = request.params else {
                return JSONRPCResponse(id: request.id, error: JSONRPCStandardError.invalidParams)
            }
            do {
                let patchValue = params["patch"] ?? params
                let patch = try decode(WizmacSettingsPatch.self, from: patchValue)
                let settings = try await router.updateSettings(patch)
                return JSONRPCResponse(id: request.id, result: encode(settings))
            } catch is DecodingError {
                return JSONRPCResponse(id: request.id, error: JSONRPCStandardError.invalidParams)
            } catch {
                return JSONRPCResponse(id: request.id, error: JSONRPCStandardError.internalError)
            }
        default:
            return JSONRPCResponse(id: request.id, error: JSONRPCStandardError.methodNotFound)
        }
    }

    private func syntheticToolResponse(
        named toolName: String,
        arguments: [String: StructuredValue],
        source: ControlPlaneSource
    ) async -> ControlPlaneActionResponse? {
        switch toolName {
        case "batch.run":
            return await runBatch(arguments: arguments, source: source)
        case "wait.ui.exists":
            return await waitUIExists(arguments: arguments, source: source)
        case "wait.window.focused":
            return await waitWindowFocused(arguments: arguments, source: source)
        case "wait.condition":
            return await waitCondition(arguments: arguments, source: source)
        default:
            return nil
        }
    }

    private func runBatch(
        arguments: [String: StructuredValue],
        source: ControlPlaneSource
    ) async -> ControlPlaneActionResponse {
        guard let stepValues = arguments["steps"]?.arrayValue, stepValues.isEmpty == false else {
            return ControlPlaneActionResponse(
                status: .invalidRequest,
                message: "batch.run requires a non-empty steps array."
            )
        }

        // Accept any maxParallel value but currently execute sequentially (future-proofing)
        let maxParallel = max(arguments["maxParallel"]?.intValue ?? 1, 1)
        _ = maxParallel  // Reserved for future parallel execution

        let failFast = arguments["continueOnError"]?.boolValue == true
            ? false
            : (arguments["failFast"]?.boolValue ?? true)
        let cachePolicy = (arguments["cachePolicy"]?.stringValue ?? "batch").lowercased()
        let snapshotReuse = (arguments["snapshotReuse"]?.stringValue ?? "best_effort").lowercased()
        let invalidateOn = Set(
            (arguments["invalidateOn"]?.arrayValue?.compactMap(\.stringValue) ?? defaultBatchInvalidationActions)
                .map { $0.lowercased() }
        )

        var batchAmbient = ambientBatchArguments(from: arguments)
        var nextStepAmbient: [String: StructuredValue] = [:]
        var results: [StructuredValue] = []
        let encoder = ISO8601DateFormatter()
        var overallSucceeded = true

        for (index, rawStep) in stepValues.enumerated() {
            guard let step = batchStep(from: rawStep) else {
                overallSucceeded = false
                results.append(
                    .object([
                        "index": .number(Double(index)),
                        "outcome": .string(ControlPlaneStatus.invalidRequest.rawValue),
                        "error": .string("Each batch step must include an action/tool and arguments."),
                        "retryCount": .number(0),
                    ])
                )
                if failFast { break }
                continue
            }

            if step.action == "batch.run" {
                overallSucceeded = false
                results.append(
                    .object([
                        "index": .number(Double(index)),
                        "action": .string(step.action),
                        "outcome": .string(ControlPlaneStatus.invalidRequest.rawValue),
                        "error": .string("Nested batch.run steps are not supported."),
                        "retryCount": .number(0),
                    ])
                )
                if failFast { break }
                continue
            }

            let inheritedContext = inheritedBatchContext(
                cachePolicy: cachePolicy,
                batchAmbient: batchAmbient,
                nextStepAmbient: nextStepAmbient
            )
            var resolvedArguments = mergedBatchArguments(
                inheritedContext: inheritedContext,
                explicitArguments: step.arguments,
                snapshotReuse: snapshotReuse
            )
            if snapshotReuse == "strict",
               resolvedArguments["sessionID"] != nil,
               resolvedArguments["snapshotID"] == nil
            {
                overallSucceeded = false
                results.append(
                    .object([
                        "index": .number(Double(index)),
                        "action": .string(step.action),
                        "request": .object([
                            "action": .string(step.action),
                            "arguments": .object(resolvedArguments),
                        ]),
                        "outcome": .string(ControlPlaneStatus.invalidRequest.rawValue),
                        "error": .string("snapshotReuse=strict requires a reusable snapshotID before the step runs."),
                        "retryCount": .number(0),
                    ])
                )
                if failFast { break }
                continue
            }

            // Determine if this step should get fast-path optimization
            let isFastPathStep: Bool = {
                let isMutation = BatchPlanRunner.isMutation(step.action)
                guard isMutation else { return false }
                // Check if next step is also a mutation
                let nextIndex = index + 1
                guard nextIndex < stepValues.count else { return false }
                guard let nextStep = batchStep(from: stepValues[nextIndex]) else { return false }
                return BatchPlanRunner.isMutation(nextStep.action)
            }()

            if isFastPathStep {
                resolvedArguments["_batchFastPath"] = .bool(true)
                if resolvedArguments["postState"] == nil {
                    resolvedArguments["postState"] = .string("none")
                }
                if resolvedArguments["preDelayMs"] == nil {
                    resolvedArguments["preDelayMs"] = .number(0)
                }
                if resolvedArguments["postDelayMs"] == nil {
                    resolvedArguments["postDelayMs"] = .number(0)
                }
            }

            let startedAt = Date()
            let response = await callTool(
                named: step.action,
                arguments: resolvedArguments,
                source: source
            )
            let endedAt = Date()
            let durationMs = max(endedAt.timeIntervalSince(startedAt) * 1_000, 0)

            let extractedContext = batchContext(from: response.payload)
            let invalidatedContext = invalidateOn.contains(step.action.lowercased()) ? [:] : extractedContext
            switch cachePolicy {
            case "none":
                nextStepAmbient = [:]
            case "step":
                nextStepAmbient = invalidatedContext
            default:
                for (key, value) in invalidatedContext {
                    batchAmbient[key] = value
                }
                nextStepAmbient = invalidatedContext
            }

            let succeeded = response.status == .success
            overallSucceeded = overallSucceeded && succeeded
            results.append(
                .object([
                    "index": .number(Double(index)),
                    "action": .string(step.action),
                    "start": .string(encoder.string(from: startedAt)),
                    "end": .string(encoder.string(from: endedAt)),
                    "durationMs": .number(durationMs),
                    "fastPath": .bool(isFastPathStep),
                    "request": .object([
                        "action": .string(step.action),
                        "arguments": .object(resolvedArguments),
                    ]),
                    "result": encoded(response),
                    "error": response.status == .success ? .null : .string(response.message ?? "Step failed."),
                    "retryCount": .number(0),
                ])
            )

            if succeeded == false, failFast {
                break
            }
        }

        return ControlPlaneActionResponse(
            status: overallSucceeded ? .success : .failed,
            payload: .object([
                "cachePolicy": .string(cachePolicy),
                "snapshotReuse": .string(snapshotReuse),
                "stepCount": .number(Double(results.count)),
                "results": .array(results),
                "sessionID": batchAmbient["sessionID"] ?? .null,
                "snapshotID": batchAmbient["snapshotID"] ?? .null,
                "graphID": batchAmbient["graphID"] ?? .null,
                "trustedSessionID": batchAmbient["trustedSessionID"] ?? .null,
            ]),
            message: overallSucceeded ? "Batch completed." : "Batch completed with step failures."
        )
    }

    private func waitUIExists(
        arguments: [String: StructuredValue],
        source: ControlPlaneSource
    ) async -> ControlPlaneActionResponse {
        let timeoutMs = max(arguments["timeoutMs"]?.intValue ?? 2_500, 50)
        let intervalMs = max(arguments["intervalMs"]?.intValue ?? 120, 20)
        let stableForMs = max(arguments["stableForMs"]?.intValue ?? 0, 0)
        let startedAt = Date()
        var stableStartedAt: Date?
        var lastPayload: StructuredValue?

        while elapsedMs(since: startedAt) <= timeoutMs {
            var searchArguments = forwardedArguments(
                from: arguments,
                keys: [
                    "query",
                    "targetID",
                    "limit",
                    "app",
                    "pid",
                    "sessionID",
                    "snapshotID",
                    "scope",
                    "includeMenus",
                    "launchIfNeeded",
                    "activate",
                    "adapter",
                ]
            )
            if searchArguments["limit"] == nil {
                searchArguments["limit"] = .number(1)
            }
            let response = await dispatchConcreteTool(
                named: "ui.search",
                arguments: searchArguments,
                source: source
            )
            if response.status == .success,
               let targets = response.payload?["targets"]?.arrayValue,
               targets.isEmpty == false
            {
                if stableForMs == 0 {
                    return withWaitMetadata(
                        response,
                        elapsedMs: elapsedMs(since: startedAt),
                        stableForMs: 0
                    )
                }
                if stableStartedAt == nil {
                    stableStartedAt = Date()
                }
                if let stableStartedAt, elapsedMs(since: stableStartedAt) >= stableForMs {
                    return withWaitMetadata(
                        response,
                        elapsedMs: elapsedMs(since: startedAt),
                        stableForMs: stableForMs
                    )
                }
            } else {
                stableStartedAt = nil
                lastPayload = response.payload
                if response.status == .permissionRequired {
                    return response
                }
            }
            await sleep(milliseconds: intervalMs)
        }

        return ControlPlaneActionResponse(
            status: .failed,
            payload: lastPayload,
            message: "Timed out waiting for a matching UI target."
        )
    }

    private func waitWindowFocused(
        arguments: [String: StructuredValue],
        source: ControlPlaneSource
    ) async -> ControlPlaneActionResponse {
        let timeoutMs = max(arguments["timeoutMs"]?.intValue ?? 2_500, 50)
        let intervalMs = max(arguments["intervalMs"]?.intValue ?? 120, 20)
        let stableForMs = max(arguments["stableForMs"]?.intValue ?? 0, 0)
        let startedAt = Date()
        var stableStartedAt: Date?
        var lastFrontmost: StructuredValue?

        while elapsedMs(since: startedAt) <= timeoutMs {
            let response = await dispatchConcreteTool(
                named: "window.list",
                arguments: [:],
                source: source
            )
            if response.status != .success {
                return response
            }

            let windows = response.payload?.arrayValue ?? []
            let frontmost = windows.first
            lastFrontmost = frontmost
            if let frontmost, focusedWindowMatches(frontmost, arguments: arguments) {
                if stableForMs == 0 {
                    return ControlPlaneActionResponse(
                        status: .success,
                        payload: .object([
                            "window": frontmost,
                            "matched": .bool(true),
                            "elapsedMs": .number(Double(elapsedMs(since: startedAt))),
                            "stableForMs": .number(0),
                        ]),
                        message: "Focused window matched."
                    )
                }
                if stableStartedAt == nil {
                    stableStartedAt = Date()
                }
                if let stableStartedAt, elapsedMs(since: stableStartedAt) >= stableForMs {
                    return ControlPlaneActionResponse(
                        status: .success,
                        payload: .object([
                            "window": frontmost,
                            "matched": .bool(true),
                            "elapsedMs": .number(Double(elapsedMs(since: startedAt))),
                            "stableForMs": .number(Double(stableForMs)),
                        ]),
                        message: "Focused window matched."
                    )
                }
            } else {
                stableStartedAt = nil
            }

            await sleep(milliseconds: intervalMs)
        }

        return ControlPlaneActionResponse(
            status: .failed,
            payload: .object([
                "window": lastFrontmost ?? .null,
                "matched": .bool(false),
            ]),
            message: "Timed out waiting for the requested focused window."
        )
    }

    private func waitCondition(
        arguments: [String: StructuredValue],
        source: ControlPlaneSource
    ) async -> ControlPlaneActionResponse {
        switch (arguments["predicate"]?.stringValue ?? "").lowercased() {
        case "ui.exists", "ui_exists", "exists":
            return await waitUIExists(arguments: arguments, source: source)
        case "window.focused", "window_focused", "focused_window":
            return await waitWindowFocused(arguments: arguments, source: source)
        default:
            return ControlPlaneActionResponse(
                status: .invalidRequest,
                message: "wait.condition supports predicates 'ui.exists' and 'window.focused'."
            )
        }
    }

    private func batchStep(from value: StructuredValue) -> (action: String, arguments: [String: StructuredValue])? {
        guard let object = value.objectValue else { return nil }
        guard let action = object["action"]?.stringValue ?? object["tool"]?.stringValue else {
            return nil
        }
        let arguments = object["args"]?.objectValue ?? object["arguments"]?.objectValue ?? [:]
        return (action, arguments)
    }

    private func ambientBatchArguments(from arguments: [String: StructuredValue]) -> [String: StructuredValue] {
        let keys = [
            "app",
            "pid",
            "sessionID",
            "snapshotID",
            "graphID",
            "scope",
            "includeMenus",
            "launchIfNeeded",
            "activate",
            "adapter",
            "autoTrust",
            "trustedSessionID",
        ]
        return forwardedArguments(from: arguments, keys: keys)
    }

    private func inheritedBatchContext(
        cachePolicy: String,
        batchAmbient: [String: StructuredValue],
        nextStepAmbient: [String: StructuredValue]
    ) -> [String: StructuredValue] {
        switch cachePolicy {
        case "none":
            return [:]
        case "step":
            return nextStepAmbient
        default:
            return batchAmbient
        }
    }

    private func mergedBatchArguments(
        inheritedContext: [String: StructuredValue],
        explicitArguments: [String: StructuredValue],
        snapshotReuse: String
    ) -> [String: StructuredValue] {
        var merged = inheritedContext
        for (key, value) in explicitArguments {
            merged[key] = value
        }
        if snapshotReuse == "off" {
            if explicitArguments["snapshotID"] == nil {
                merged.removeValue(forKey: "snapshotID")
            }
            if explicitArguments["graphID"] == nil {
                merged.removeValue(forKey: "graphID")
            }
        }
        return merged
    }

    private func batchContext(from payload: StructuredValue?) -> [String: StructuredValue] {
        guard let object = payload?.objectValue else { return [:] }
        let keys = ["sessionID", "snapshotID", "graphID", "trustedSessionID", "targetID"]
        return keys.reduce(into: [:]) { result, key in
            if let value = object[key], value != .null {
                result[key] = value
            }
        }
    }

    private func withWaitMetadata(
        _ response: ControlPlaneActionResponse,
        elapsedMs: Int,
        stableForMs: Int
    ) -> ControlPlaneActionResponse {
        guard let payload = response.payload?.objectValue else {
            return response
        }
        var updated = payload
        updated["elapsedMs"] = .number(Double(elapsedMs))
        updated["stableForMs"] = .number(Double(stableForMs))
        return ControlPlaneActionResponse(
            status: response.status,
            payload: .object(updated),
            message: response.message,
            auditID: response.auditID,
            confirmationToken: response.confirmationToken
        )
    }

    private func focusedWindowMatches(
        _ value: StructuredValue,
        arguments: [String: StructuredValue]
    ) -> Bool {
        guard let window = value.objectValue else { return false }
        if let requestedWindowID = arguments["windowID"]?.intValue,
           window["id"]?.intValue != requestedWindowID {
            return false
        }

        let requestedTitle = arguments["windowTitle"]?.stringValue ?? arguments["title"]?.stringValue
        if let requestedTitle,
           window["title"]?.stringValue != requestedTitle
            && localizedCaseInsensitiveContains(window["title"]?.stringValue, requestedTitle) == false {
            return false
        }

        if let requestedQuery = arguments["query"]?.stringValue {
            let haystack = [
                window["title"]?.stringValue ?? "",
                window["appName"]?.stringValue ?? "",
            ].joined(separator: " ")
            if localizedCaseInsensitiveContains(haystack, requestedQuery) == false {
                return false
            }
        }

        if let requestedPID = arguments["pid"]?.intValue,
           window["pid"]?.intValue != requestedPID {
            return false
        }

        if let requestedApp = arguments["app"]?.stringValue,
           localizedCaseInsensitiveContains(window["appName"]?.stringValue, requestedApp) == false {
            return false
        }

        return true
    }

    private func forwardedArguments(
        from arguments: [String: StructuredValue],
        keys: [String]
    ) -> [String: StructuredValue] {
        keys.reduce(into: [:]) { result, key in
            if let value = arguments[key] {
                result[key] = value
            }
        }
    }

    private func elapsedMs(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1_000)
    }

    private func sleep(milliseconds: Int) async {
        guard milliseconds > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }

    private func localizedCaseInsensitiveContains(_ lhs: String?, _ rhs: String) -> Bool {
        guard let lhs else { return false }
        return lhs.range(of: rhs, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private var defaultBatchInvalidationActions: [String] {
        [
            "ui.act",
            "ui.copy",
            "ui.open",
            "ui.select",
            "ui.toggle",
            "ui.focus",
            "ui.submit",
            "ui.choose_file",
            "ui.drag",
            "ui.gesture",
            "input.key_combo",
            "input.key_sequence",
            "text.insert",
            "text.send_keys",
            "window.focus",
            "scroll.step",
            "scroll.to",
            "scroll.until",
            "scroll.into_view",
        ]
    }

    private func encoded(_ response: ControlPlaneActionResponse) -> StructuredValue {
        let encoder = JSONEncoder()
        guard
            let data = try? encoder.encode(response),
            let structured = try? JSONDecoder().decode(StructuredValue.self, from: data)
        else {
            return .object([
                "status": .string(response.status.rawValue),
                "message": .string(response.message ?? ""),
            ])
        }
        return structured
    }
}

public enum ControlPlaneError: Error, LocalizedError {
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupported(message):
            return message
        }
    }
}

private func encode<T: Encodable>(_ value: T) -> StructuredValue {
    let encoder = JSONEncoder()
    guard
        let data = try? encoder.encode(value),
        let structured = try? JSONDecoder().decode(StructuredValue.self, from: data)
    else {
        return .null
    }
    return structured
}

private func decode<T: Decodable>(_ type: T.Type, from value: StructuredValue) throws -> T {
    let encoder = JSONEncoder()
    let data = try encoder.encode(value)
    return try JSONDecoder().decode(type, from: data)
}

public enum ControlPlaneEnvironment {
    public static let fixtureEnvironmentKey = "WIZMAC_CONTROL_PLANE_FIXTURE"

    public static func makeDispatcher(
        registry: ControlPlaneToolRegistry = .default,
        router: (any ControlPlaneRouting)? = nil
    ) -> ControlPlaneDispatcher {
        if let router {
            return ControlPlaneDispatcher(registry: registry, router: router)
        }
        if let fixtureRouter = fixtureRouterFromEnvironment() {
            return ControlPlaneDispatcher(registry: registry, router: fixtureRouter)
        }
        return ControlPlaneDispatcher(registry: registry, router: ServiceClientControlPlaneRouter())
    }

    static func fixtureRouterFromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> (any ControlPlaneRouting)? {
        guard let rawConfiguration = environment[fixtureEnvironmentKey],
              let data = rawConfiguration.data(using: .utf8),
              let configuration = try? JSONDecoder().decode(
                  FixtureControlPlaneEnvironmentConfiguration.self,
                  from: data
              )
        else {
            return nil
        }

        return FixtureControlPlaneRouter(configuration: configuration)
    }
}
