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
        XCTAssertEqual(tools.first?["name"]?.stringValue, "display.airplay_connect")
        XCTAssertTrue(tools.contains { $0["name"]?.stringValue == "system.permissions_request" })
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
        let resolver = HTTPControlPlaneSourceResolver(trustForwardedSourceHeaders: true)
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
        let resolver = HTTPControlPlaneSourceResolver(trustForwardedSourceHeaders: false)
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
