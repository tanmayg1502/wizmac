import Foundation
import XCTest
@testable import WizmacControlPlane

final class XPCServiceBridgeTests: XCTestCase {
    func testXPCClientRoundTripsRequestThroughServiceContract() async throws {
        let host = WizmacXPCListenerHost(serviceContract: EchoXPCServiceContract())
        host.start()
        defer { host.stop() }

        let client = WizmacXPCClient(endpoint: host.endpoint)
        let response = try await client.send(
            request: JSONRPCRequest(id: .string("echo"), method: "service.health"),
            source: ControlPlaneSource(
                kind: .menuBar,
                clientID: "menu-bar-client",
                sessionID: "session-1"
            ),
            ensureRunning: false
        )

        XCTAssertEqual(response.result?["method"]?.stringValue, "service.health")
        XCTAssertEqual(response.result?["sourceKind"]?.stringValue, ControlPlaneSourceKind.menuBar.rawValue)
        XCTAssertEqual(response.result?["clientID"]?.stringValue, "menu-bar-client")
        XCTAssertEqual(response.result?["sessionID"]?.stringValue, "session-1")
    }

    func testClientUsesTransportDescriptorFileWhenAvailable() async throws {
        let dispatcher = ControlPlaneDispatcher(router: UnconfiguredControlPlaneRouter())
        let (server, serverURL) = try makeTestServer(dispatcher: dispatcher)
        defer { server.stop() }
        try await Task.sleep(for: .milliseconds(100))

        let descriptor = LocalTransportDescriptor(kind: .http, url: serverURL)
        let endpointFileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wizmac-test-endpoint-\(UUID().uuidString).xpc")
        try JSONEncoder().encode(descriptor).write(to: endpointFileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: endpointFileURL) }

        let client = WizmacXPCClient(
            localURL: URL(string: "http://127.0.0.1:1/rpc")!,
            endpointFileURL: endpointFileURL,
            processManager: nil
        )

        let response = try await client.send(
            request: JSONRPCRequest(id: .string("transport-file"), method: "ping"),
            source: ControlPlaneSource(kind: .cli),
            ensureRunning: false
        )

        XCTAssertEqual(response.id, .string("transport-file"))
        XCTAssertNil(response.error)
        XCTAssertEqual(response.result?.objectValue?.count, 0)
    }
}

private struct EchoXPCServiceContract: WizmacXPCServiceContract {
    func handle(_ request: JSONRPCRequest, source: ControlPlaneSource) async throws -> JSONRPCResponse {
        JSONRPCResponse(
            id: request.id,
            result: .object([
                "method": .string(request.method),
                "sourceKind": .string(source.kind.rawValue),
                "clientID": .string(source.clientID ?? ""),
                "sessionID": .string(source.sessionID ?? ""),
            ])
        )
    }
}

private func makeTestServer(
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
            return (server, URL(string: "http://127.0.0.1:\(port)/rpc")!)
        } catch {
            continue
        }
    }

    throw XCTSkip("Unable to start a local HTTP transport test server.")
}
