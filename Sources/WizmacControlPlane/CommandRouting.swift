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
                result: .object([
                    "protocolVersion": .string("2026-03-10"),
                    "serverInfo": .object([
                        "name": .string("wizmac-control-plane"),
                        "version": .string("0.1.0"),
                    ]),
                    "capabilities": .object([
                        "tools": .object([:]),
                    ]),
                ])
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
    public static func makeDispatcher(
        registry: ControlPlaneToolRegistry = .default,
        router: (any ControlPlaneRouting)? = nil
    ) -> ControlPlaneDispatcher {
        if let router {
            return ControlPlaneDispatcher(registry: registry, router: router)
        }
        return ControlPlaneDispatcher(registry: registry, router: ServiceClientControlPlaneRouter())
    }
}
