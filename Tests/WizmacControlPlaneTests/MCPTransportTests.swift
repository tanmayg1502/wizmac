import Foundation
import XCTest
@testable import WizmacControlPlane

final class MCPTransportTests: XCTestCase {
    func testHTTPMCPNotificationReturnsAcceptedWithoutBody() async throws {
        let dispatcher = ControlPlaneDispatcher(registry: .default, router: UnconfiguredControlPlaneRouter())
        let (server, url) = try makeMCPTestServer(dispatcher: dispatcher)
        defer { server.stop() }
        try await Task.sleep(for: .milliseconds(100))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            JSONRPCRequest(method: "notifications/initialized")
        )

        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 202)
    }

    func testHTTPMCPRejectsUnsupportedProtocolVersionHeader() async throws {
        let dispatcher = ControlPlaneDispatcher(registry: .default, router: UnconfiguredControlPlaneRouter())
        let (server, url) = try makeMCPTestServer(dispatcher: dispatcher)
        defer { server.stop() }
        try await Task.sleep(for: .milliseconds(100))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("1999-01-01", forHTTPHeaderField: "MCP-Protocol-Version")
        request.httpBody = try JSONEncoder().encode(
            JSONRPCRequest(id: .string("init"), method: "initialize")
        )

        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 400)
    }

    func testHTTPMCPRejectsUnexpectedOriginHeader() async throws {
        let dispatcher = ControlPlaneDispatcher(registry: .default, router: UnconfiguredControlPlaneRouter())
        let (server, url) = try makeMCPTestServer(dispatcher: dispatcher)
        defer { server.stop() }
        try await Task.sleep(for: .milliseconds(100))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("http://evil.example", forHTTPHeaderField: "Origin")
        request.httpBody = try JSONEncoder().encode(
            JSONRPCRequest(id: .string("init"), method: "initialize")
        )

        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 403)
    }

    func testHTTPMCPTreatsLoopbackRequestsAsMCPSource() async throws {
        let router = ClosureControlPlaneRouter { request in
            ControlPlaneActionResponse(
                status: .success,
                payload: .object([
                    "kind": .string(request.source.kind.rawValue),
                ])
            )
        }
        let dispatcher = ControlPlaneDispatcher(registry: .default, router: router)
        let (server, url) = try makeMCPTestServer(dispatcher: dispatcher)
        defer { server.stop() }
        try await Task.sleep(for: .milliseconds(100))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            JSONRPCRequest(
                id: .string("tool"),
                method: "tools/call",
                params: .object([
                    "name": .string("system.health"),
                    "arguments": .object([:]),
                ])
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200)

        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        XCTAssertEqual(decoded.result?["structuredContent"]?["payload"]?["kind"]?.stringValue, "mcp")
    }
}

private func makeMCPTestServer(
    dispatcher: ControlPlaneDispatcher
) throws -> (server: HTTPJSONRPCServer, url: URL) {
    for _ in 0..<10 {
        let port = UInt16.random(in: 20_000...60_000)
        let server = HTTPJSONRPCServer(
            dispatcher: dispatcher,
            configuration: HTTPJSONRPCServerConfiguration(
                host: "127.0.0.1",
                port: port,
                path: "/rpc"
            )
        )
        do {
            try server.start()
            return (server, URL(string: "http://127.0.0.1:\(port)/mcp")!)
        } catch {
            continue
        }
    }

    throw XCTSkip("Unable to start a local MCP HTTP test server.")
}
