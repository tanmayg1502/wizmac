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
