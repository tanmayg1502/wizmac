import Foundation

struct FixtureControlPlaneEnvironmentConfiguration: Codable, Sendable {
    var defaultDelayMs: Double?
    var toolResponses: [String: FixtureToolResponse]
}

struct FixtureToolResponse: Codable, Sendable {
    var delayMs: Double?
    var response: ControlPlaneActionResponse
}

actor FixtureControlPlaneRouter: ControlPlaneRouting {
    private let configuration: FixtureControlPlaneEnvironmentConfiguration

    init(configuration: FixtureControlPlaneEnvironmentConfiguration) {
        self.configuration = configuration
    }

    func handle(_ request: ControlPlaneActionRequest) async throws -> ControlPlaneActionResponse {
        guard let fixture = configuration.toolResponses[request.toolName] else {
            return ControlPlaneActionResponse(
                status: .unsupported,
                message: "No fixture response registered for '\(request.toolName)'."
            )
        }

        let delayMs = fixture.delayMs ?? configuration.defaultDelayMs ?? 0
        if delayMs > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delayMs * 1_000_000))
        }

        return fixture.response
    }
}
