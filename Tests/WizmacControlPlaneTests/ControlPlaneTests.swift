import Foundation
import XCTest
@testable import WizmacControlPlane
import WizmacCore

final class ControlPlaneTests: XCTestCase {
    func testRegistryCreatesNamespacedRequests() throws {
        let request = try XCTUnwrap(
            ControlPlaneToolRegistry.default.request(
                for: "window.list",
                arguments: [:],
                source: ControlPlaneSource(kind: .cli)
            )
        )

        XCTAssertEqual(request.namespace, "window")
        XCTAssertEqual(request.action, "list")
    }

    func testJSONRPCRoundTrip() throws {
        let request = JSONRPCRequest(
            id: .int(1),
            method: "tools/call",
            params: .object([
                "name": .string("system.permissions"),
                "arguments": .object([:]),
            ])
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
        XCTAssertEqual(decoded.method, "tools/call")
        XCTAssertEqual(decoded.id, .int(1))
        XCTAssertEqual(decoded.params?["name"]?.stringValue, "system.permissions")
    }

    func testDispatcherListsDefaultTools() async throws {
        let dispatcher = ControlPlaneDispatcher(registry: .default, router: UnconfiguredControlPlaneRouter())
        let response = await dispatcher.handleJSONRPC(
            JSONRPCRequest(id: .string("1"), method: "tools/list"),
            source: ControlPlaneSource(kind: .mcp)
        )

        let tools = try XCTUnwrap(response?.result?["tools"]?.arrayValue)
        XCTAssertFalse(tools.isEmpty)
        XCTAssertEqual(tools.first?["name"]?.stringValue, "batch.run")
        XCTAssertTrue(tools.contains { $0["name"]?.stringValue == "input.key_combo" })
        XCTAssertTrue(tools.contains { $0["name"]?.stringValue == "input.key_sequence" })
        XCTAssertTrue(tools.contains { $0["name"]?.stringValue == "ui.gesture" })
        XCTAssertTrue(tools.contains { $0["name"]?.stringValue == "system.permissions_request" })
    }

    func testInitializeNegotiatesSupportedProtocolVersionAndCapabilities() async throws {
        let dispatcher = ControlPlaneDispatcher(registry: .default, router: UnconfiguredControlPlaneRouter())
        let response = await dispatcher.handleJSONRPC(
            JSONRPCRequest(
                id: .string("init"),
                method: "initialize",
                params: .object([
                    "protocolVersion": .string("2025-11-25"),
                    "capabilities": .object([:]),
                    "clientInfo": .object([
                        "name": .string("Test Client"),
                    ]),
                ])
            ),
            source: ControlPlaneSource(kind: .mcp)
        )

        XCTAssertEqual(response?.result?["protocolVersion"]?.stringValue, "2025-11-25")
        XCTAssertEqual(response?.result?["serverInfo"]?["name"]?.stringValue, "wizmac")
        XCTAssertEqual(response?.result?["capabilities"]?["tools"]?.objectValue?.count, 0)
        XCTAssertEqual(response?.result?["capabilities"]?["resources"]?.objectValue?.count, 0)
        XCTAssertNotNil(response?.result?["instructions"]?.stringValue)
    }

    func testInitializeFallsBackToLatestSupportedProtocolVersion() async throws {
        let dispatcher = ControlPlaneDispatcher(registry: .default, router: UnconfiguredControlPlaneRouter())
        let response = await dispatcher.handleJSONRPC(
            JSONRPCRequest(
                id: .string("init"),
                method: "initialize",
                params: .object([
                    "protocolVersion": .string("2099-01-01"),
                ])
            ),
            source: ControlPlaneSource(kind: .mcp)
        )

        XCTAssertEqual(response?.result?["protocolVersion"]?.stringValue, "2025-11-25")
    }

    func testUIActAndUICopySchemasExposeQueryBasedResolution() throws {
        let uiAct = try XCTUnwrap(ControlPlaneToolRegistry.default.tool(named: "ui.act"))
        let uiCopy = try XCTUnwrap(ControlPlaneToolRegistry.default.tool(named: "ui.copy"))

        let actProperties = try XCTUnwrap(uiAct.inputSchema.objectValue?["properties"]?.objectValue)
        let copyProperties = try XCTUnwrap(uiCopy.inputSchema.objectValue?["properties"]?.objectValue)

        XCTAssertEqual(actProperties["query"]?.stringValue, "string")
        XCTAssertEqual(actProperties["limit"]?.stringValue, "number")
        XCTAssertEqual(copyProperties["query"]?.stringValue, "string")
        XCTAssertEqual(copyProperties["limit"]?.stringValue, "number")
    }

    func testExpandedToolSchemasExposeHighLevelSelectorsAndVerificationArguments() throws {
        let uiOpen = try XCTUnwrap(ControlPlaneToolRegistry.default.tool(named: "ui.open"))
        let scrollTo = try XCTUnwrap(ControlPlaneToolRegistry.default.tool(named: "scroll.to"))
        let windowAssert = try XCTUnwrap(ControlPlaneToolRegistry.default.tool(named: "window.assert"))
        let textRead = try XCTUnwrap(ControlPlaneToolRegistry.default.tool(named: "text.read"))
        let menuSelect = try XCTUnwrap(ControlPlaneToolRegistry.default.tool(named: "menu.select"))
        let textInsert = try XCTUnwrap(ControlPlaneToolRegistry.default.tool(named: "text.insert"))

        let uiOpenProperties = try XCTUnwrap(uiOpen.inputSchema.objectValue?["properties"]?.objectValue)
        let scrollToProperties = try XCTUnwrap(scrollTo.inputSchema.objectValue?["properties"]?.objectValue)
        let windowAssertProperties = try XCTUnwrap(windowAssert.inputSchema.objectValue?["properties"]?.objectValue)
        let textReadProperties = try XCTUnwrap(textRead.inputSchema.objectValue?["properties"]?.objectValue)
        let menuSelectProperties = try XCTUnwrap(menuSelect.inputSchema.objectValue?["properties"]?.objectValue)
        let textInsertProperties = try XCTUnwrap(textInsert.inputSchema.objectValue?["properties"]?.objectValue)

        XCTAssertEqual(uiOpenProperties["query"]?.stringValue, "string")
        XCTAssertEqual(scrollToProperties["query"]?.stringValue, "string")
        XCTAssertEqual(windowAssertProperties["query"]?.stringValue, "string")
        XCTAssertEqual(textReadProperties["query"]?.stringValue, "string")
        XCTAssertEqual(menuSelectProperties["path"]?.stringValue, "string")
        XCTAssertEqual(textInsertProperties["expectText"]?.stringValue, "string")
        XCTAssertEqual(textInsertProperties["expectSent"]?.stringValue, "boolean")
    }

    func testPhase1ErgonomicToolSchemasExposeCanonicalArgumentsAndTimingControls() throws {
        let inputKeyCombo = try XCTUnwrap(ControlPlaneToolRegistry.default.tool(named: "input.key_combo"))
        let inputKeySequence = try XCTUnwrap(ControlPlaneToolRegistry.default.tool(named: "input.key_sequence"))
        let uiGesture = try XCTUnwrap(ControlPlaneToolRegistry.default.tool(named: "ui.gesture"))
        let uiAct = try XCTUnwrap(ControlPlaneToolRegistry.default.tool(named: "ui.act"))
        let textSendKeys = try XCTUnwrap(ControlPlaneToolRegistry.default.tool(named: "text.send_keys"))

        let comboProperties = try XCTUnwrap(inputKeyCombo.inputSchema.objectValue?["properties"]?.objectValue)
        let sequenceProperties = try XCTUnwrap(inputKeySequence.inputSchema.objectValue?["properties"]?.objectValue)
        let gestureProperties = try XCTUnwrap(uiGesture.inputSchema.objectValue?["properties"]?.objectValue)
        let actProperties = try XCTUnwrap(uiAct.inputSchema.objectValue?["properties"]?.objectValue)
        let sendKeysProperties = try XCTUnwrap(textSendKeys.inputSchema.objectValue?["properties"]?.objectValue)

        XCTAssertEqual(comboProperties["mods"]?.stringValue, "array")
        XCTAssertEqual(comboProperties["modifiers"]?.stringValue, "array")
        XCTAssertEqual(comboProperties["key"]?.stringValue, "string")
        XCTAssertEqual(comboProperties["app"]?.stringValue, "string")
        XCTAssertEqual(comboProperties["pid"]?.stringValue, "number")
        XCTAssertEqual(comboProperties["activate"]?.stringValue, "boolean")
        XCTAssertEqual(comboProperties["launchIfNeeded"]?.stringValue, "boolean")
        XCTAssertEqual(comboProperties["autoTrust"]?.stringValue, "boolean")
        XCTAssertEqual(comboProperties["trustedSessionID"]?.stringValue, "string")
        XCTAssertEqual(comboProperties["preDelayMs"]?.stringValue, "number")
        XCTAssertEqual(comboProperties["postDelayMs"]?.stringValue, "number")
        XCTAssertEqual(comboProperties["debugTimings"]?.stringValue, "boolean")

        XCTAssertEqual(sequenceProperties["sequence"]?.stringValue, "string")
        XCTAssertEqual(sequenceProperties["steps"]?.stringValue, "array")
        XCTAssertEqual(sequenceProperties["app"]?.stringValue, "string")
        XCTAssertEqual(sequenceProperties["pid"]?.stringValue, "number")
        XCTAssertEqual(sequenceProperties["activate"]?.stringValue, "boolean")
        XCTAssertEqual(sequenceProperties["launchIfNeeded"]?.stringValue, "boolean")
        XCTAssertEqual(sequenceProperties["autoTrust"]?.stringValue, "boolean")
        XCTAssertEqual(sequenceProperties["trustedSessionID"]?.stringValue, "string")
        XCTAssertEqual(sequenceProperties["preDelayMs"]?.stringValue, "number")
        XCTAssertEqual(sequenceProperties["postDelayMs"]?.stringValue, "number")
        XCTAssertEqual(sequenceProperties["debugTimings"]?.stringValue, "boolean")

        XCTAssertEqual(gestureProperties["preset"]?.stringValue, "string")
        XCTAssertEqual(gestureProperties["targetID"]?.stringValue, "string")
        XCTAssertEqual(gestureProperties["query"]?.stringValue, "string")
        XCTAssertEqual(gestureProperties["app"]?.stringValue, "string")
        XCTAssertEqual(gestureProperties["pid"]?.stringValue, "number")
        XCTAssertEqual(gestureProperties["distance"]?.stringValue, "number")
        XCTAssertEqual(gestureProperties["durationMs"]?.stringValue, "number")
        XCTAssertEqual(gestureProperties["preDelayMs"]?.stringValue, "number")
        XCTAssertEqual(gestureProperties["postDelayMs"]?.stringValue, "number")
        XCTAssertEqual(gestureProperties["autoTrust"]?.stringValue, "boolean")
        XCTAssertEqual(gestureProperties["trustedSessionID"]?.stringValue, "string")
        XCTAssertEqual(gestureProperties["debugTimings"]?.stringValue, "boolean")

        XCTAssertEqual(actProperties["preDelayMs"]?.stringValue, "number")
        XCTAssertEqual(actProperties["postDelayMs"]?.stringValue, "number")
        XCTAssertEqual(sendKeysProperties["preDelayMs"]?.stringValue, "number")
        XCTAssertEqual(sendKeysProperties["postDelayMs"]?.stringValue, "number")
    }

    func testDispatcherCallsSharedRouter() async throws {
        let router = ClosureControlPlaneRouter { request in
            ControlPlaneActionResponse(
                status: .success,
                payload: .object([
                    "tool": .string(request.toolName),
                    "echo": .object(request.arguments),
                ])
            )
        }
        let dispatcher = ControlPlaneDispatcher(registry: .default, router: router)
        let response = await dispatcher.callTool(
            named: "ui.search",
            arguments: ["query": .string("Safari")],
            source: ControlPlaneSource(kind: .cli)
        )

        XCTAssertEqual(response.status, .success)
        XCTAssertEqual(response.payload?["tool"]?.stringValue, "ui.search")
        XCTAssertEqual(response.payload?["echo"]?["query"]?.stringValue, "Safari")
    }

    func testDispatcherAutoTrustStartsTrustedSessionForAllowedLocalTool() async throws {
        let router = RecordingControlPlaneRouter()
        let dispatcher = ControlPlaneDispatcher(registry: .default, router: router)

        let response = await dispatcher.callTool(
            named: "ui.act",
            arguments: [
                "targetID": .string("button-1"),
                "autoTrust": .bool(true),
            ],
            source: ControlPlaneSource(kind: .cli)
        )

        let requests = await router.recordedRequests()

        XCTAssertEqual(response.status, .success)
        XCTAssertEqual(requests.map(\.toolName), ["system.trusted_session_start", "ui.act"])
        XCTAssertEqual(requests.last?.arguments["trustedSessionID"]?.stringValue, "trusted-1")
    }

    func testDispatcherImplicitlyAutoTrustsLocalAppScopedMutation() async throws {
        let router = RecordingControlPlaneRouter()
        let dispatcher = ControlPlaneDispatcher(registry: .default, router: router)

        let response = await dispatcher.callTool(
            named: "ui.act",
            arguments: [
                "targetID": .string("button-1"),
                "pid": .number(3255),
            ],
            source: ControlPlaneSource(kind: .cli)
        )

        let requests = await router.recordedRequests()

        XCTAssertEqual(response.status, .success)
        XCTAssertEqual(requests.map(\.toolName), ["system.trusted_session_start", "ui.act"])
        XCTAssertEqual(requests.first?.arguments["pid"]?.intValue, 3255)
        XCTAssertEqual(requests.last?.arguments["trustedSessionID"]?.stringValue, "trusted-1")
    }

    func testDispatcherImplicitlyAutoTrustsLocalWindowScopedMutation() async throws {
        let router = RecordingControlPlaneRouter()
        let dispatcher = ControlPlaneDispatcher(registry: .default, router: router)

        let response = await dispatcher.callTool(
            named: "window.focus",
            arguments: [
                "targetID": .string("window-1"),
                "windowID": .number(78),
            ],
            source: ControlPlaneSource(kind: .cli)
        )

        let requests = await router.recordedRequests()

        XCTAssertEqual(response.status, .success)
        XCTAssertEqual(requests.map(\.toolName), ["system.trusted_session_start", "window.focus"])
        XCTAssertEqual(requests.last?.arguments["trustedSessionID"]?.stringValue, "trusted-1")
    }

    func testDispatcherDoesNotImplicitlyAutoTrustFrontmostMutation() async throws {
        let router = RecordingControlPlaneRouter()
        let dispatcher = ControlPlaneDispatcher(registry: .default, router: router)

        let response = await dispatcher.callTool(
            named: "ui.act",
            arguments: [
                "targetID": .string("button-1"),
            ],
            source: ControlPlaneSource(kind: .cli)
        )

        let requests = await router.recordedRequests()

        XCTAssertEqual(response.status, .success)
        XCTAssertEqual(requests.map(\.toolName), ["ui.act"])
        XCTAssertNil(requests.last?.arguments["trustedSessionID"]?.stringValue)
    }

    func testDispatcherRespectsExplicitAutoTrustOptOutForAppScopedMutation() async throws {
        let router = RecordingControlPlaneRouter()
        let dispatcher = ControlPlaneDispatcher(registry: .default, router: router)

        let response = await dispatcher.callTool(
            named: "ui.act",
            arguments: [
                "targetID": .string("button-1"),
                "app": .string("Arc"),
                "autoTrust": .bool(false),
            ],
            source: ControlPlaneSource(kind: .cli)
        )

        let requests = await router.recordedRequests()

        XCTAssertEqual(response.status, .success)
        XCTAssertEqual(requests.map(\.toolName), ["ui.act"])
        XCTAssertNil(requests.last?.arguments["trustedSessionID"]?.stringValue)
    }

    func testCoreBackedRouterPropagatesRemoteSourceIntoCoreRequest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let settingsStore = try SettingsStore(url: directory.appendingPathComponent("settings.json"))
        let auditStore = try AuditStore(url: directory.appendingPathComponent("audit.jsonl"))
        let approvalStore = try ApprovalStore(url: directory.appendingPathComponent("approvals.json"))
        let executor = OriginEchoExecutor()
        let bus = CommandBus(
            executor: executor,
            auditStore: auditStore,
            approvalStore: approvalStore,
            approvalPolicy: ApprovalPolicy(settingsStore: settingsStore)
        )
        let router = CoreBackedControlPlaneRouter(bus: bus)

        let response = try await router.handle(
            ControlPlaneActionRequest(
                namespace: "window",
                action: "list",
                source: ControlPlaneSource(
                    kind: .http,
                    clientID: "203.0.113.8",
                    sessionID: "remote-session"
                )
            )
        )
        let recordedOrigins = await executor.recordedOrigins()

        XCTAssertEqual(response.status, .success)
        XCTAssertEqual(response.payload?["originKind"]?.stringValue, "remote")
        XCTAssertEqual(response.payload?["sessionID"]?.stringValue, "remote-session")
        XCTAssertEqual(response.payload?["remoteAddress"]?.stringValue, "203.0.113.8")
        XCTAssertEqual(response.payload?["action"]?.stringValue, "window.list")
        XCTAssertEqual(recordedOrigins.count, 1)
    }

    func testToolsCallUsesTransportSourceInsteadOfEmbeddedOverride() async throws {
        let router = ClosureControlPlaneRouter { request in
            ControlPlaneActionResponse(
                status: .success,
                payload: .object([
                    "kind": .string(request.source.kind.rawValue),
                    "clientID": .string(request.source.clientID ?? ""),
                    "sessionID": .string(request.source.sessionID ?? ""),
                ])
            )
        }
        let dispatcher = ControlPlaneDispatcher(registry: .default, router: router)
        let request = JSONRPCRequest(
            id: .string("source-override"),
            method: "tools/call",
            params: .object([
                "name": .string("system.health"),
                "arguments": .object([:]),
                "source": .object([
                    "kind": .string(ControlPlaneSourceKind.menuBar.rawValue),
                    "clientID": .string("menu-bar"),
                    "sessionID": .string("mb-1"),
                    "requiresConfirmationByDefault": .bool(false),
                ]),
            ])
        )

        let response = await dispatcher.handleJSONRPC(
            request,
            source: ControlPlaneSource(kind: .http, clientID: "outer-client", sessionID: "outer-session")
        )

        let payload = response?.result?["structuredContent"]?["payload"]
        XCTAssertEqual(payload?["kind"]?.stringValue, ControlPlaneSourceKind.http.rawValue)
        XCTAssertEqual(payload?["clientID"]?.stringValue, "outer-client")
        XCTAssertEqual(payload?["sessionID"]?.stringValue, "outer-session")
    }

    func testHTTPSourceResolverTrustsForwardedHeadersForLocalService() throws {
        let resolver = HTTPControlPlaneSourceResolver(
            trustForwardedSourceHeaders: true,
            defaultLocalSourceKind: .http
        )
        let rpcRequest = JSONRPCRequest(
            id: .string("1"),
            method: "tools/call",
            params: .object([
                "name": .string("ui.search"),
                "arguments": .object([:]),
                "source": .object([
                    "kind": .string(ControlPlaneSourceKind.menuBar.rawValue),
                    "clientID": .string("menu-bar-client"),
                    "sessionID": .string("menu-session"),
                    "requiresConfirmationByDefault": .bool(false),
                ]),
            ])
        )
        let request = try XCTUnwrap(
            HTTPRequest(
                data: Data([
                    "POST /rpc HTTP/1.1",
                    "Host: localhost",
                    "X-Wizmac-Source: \(ControlPlaneSourceKind.cli.rawValue)",
                    "X-Client-ID: header-client",
                    "X-Session-ID: header-session",
                    "Content-Length: 0",
                    "",
                    "",
                ].joined(separator: "\r\n").utf8)
            )
        )

        let source = resolver.resolve(request: request, rpcRequest: rpcRequest)

        XCTAssertEqual(source.kind, ControlPlaneSourceKind.cli)
        XCTAssertEqual(source.clientID, "menu-bar-client")
        XCTAssertEqual(source.sessionID, "menu-session")
    }

    func testHTTPSourceResolverForAuthenticatedRemoteRequestsStaysHTTP() throws {
        let resolver = HTTPControlPlaneSourceResolver(
            trustForwardedSourceHeaders: false,
            defaultLocalSourceKind: .http
        )
        let rpcRequest = JSONRPCRequest(
            id: .string("1"),
            method: "tools/call",
            params: .object([
                "name": .string("ui.search"),
                "arguments": .object([:]),
                "source": .object([
                    "kind": .string(ControlPlaneSourceKind.cli.rawValue),
                    "clientID": .string("spoofed-client"),
                    "sessionID": .string("spoofed-session"),
                    "requiresConfirmationByDefault": .bool(true),
                ]),
            ])
        )
        let request = try XCTUnwrap(
            HTTPRequest(
                data: Data([
                    "POST /rpc HTTP/1.1",
                    "Host: localhost",
                    "X-Wizmac-Source: \(ControlPlaneSourceKind.cli.rawValue)",
                    "X-Client-ID: paired-client",
                    "X-Session-ID: remote-session",
                    "Content-Length: 0",
                    "",
                    "",
                ].joined(separator: "\r\n").utf8)
            )
        )

        let source = resolver.resolve(request: request, rpcRequest: rpcRequest)

        XCTAssertEqual(source.kind, ControlPlaneSourceKind.http)
        XCTAssertEqual(source.clientID, "paired-client")
        XCTAssertEqual(source.sessionID, "remote-session")
        XCTAssertTrue(source.requiresConfirmationByDefault)
    }
}

private actor OriginEchoExecutor: ActionExecutor {
    private var origins: [RequestOrigin] = []

    func execute(_ request: ActionRequest) async -> ActionResult {
        origins.append(request.origin)
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "ok",
            payload: [
                "originKind": .string(request.origin.kind.rawValue),
                "sessionID": request.origin.sessionID.map(JSONValue.string) ?? .null,
                "remoteAddress": request.origin.remoteAddress.map(JSONValue.string) ?? .null,
                "action": .string(request.action.rawValue),
            ]
        )
    }

    func recordedOrigins() -> [RequestOrigin] {
        origins
    }
}

private actor RecordingControlPlaneRouter: ControlPlaneRouting {
    private var requests: [ControlPlaneActionRequest] = []

    func handle(_ request: ControlPlaneActionRequest) async throws -> ControlPlaneActionResponse {
        requests.append(request)
        if request.toolName == "system.trusted_session_start" {
            return ControlPlaneActionResponse(
                status: .success,
                payload: .object([
                    "trustedSessionID": .string("trusted-1"),
                ])
            )
        }

        return ControlPlaneActionResponse(
            status: .success,
            payload: .object([
                "tool": .string(request.toolName),
                "trustedSessionID": request.arguments["trustedSessionID"] ?? .null,
            ])
        )
    }

    func recordedRequests() -> [ControlPlaneActionRequest] {
        requests
    }
}
