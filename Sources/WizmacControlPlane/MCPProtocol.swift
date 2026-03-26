import Foundation

enum MCPProtocol {
    static let latestVersion = "2025-11-25"
    static let fallbackHTTPVersion = "2025-03-26"
    static let supportedVersions: [String] = [
        latestVersion,
        fallbackHTTPVersion,
    ]

    static let serverName = "wizmac"
    static let serverTitle = "Wizmac MCP"
    static let serverDescription = "Control the local Mac through shared Wizmac tools, approvals, and session-aware automation."
    static let serverInstructions = "Use Wizmac tools when a task requires interacting with the local Mac UI, windows, clipboard, focused text, or media. Prefer read-only discovery tools before state-changing tools."

    static func negotiatedVersion(from params: StructuredValue?) -> String {
        guard let requestedVersion = params?["protocolVersion"]?.stringValue else {
            return latestVersion
        }
        if supportedVersions.contains(requestedVersion) {
            return requestedVersion
        }
        return latestVersion
    }

    static func supportsVersionHeader(_ value: String?) -> Bool {
        guard let value, value.isEmpty == false else {
            return true
        }
        return supportedVersions.contains(value)
    }

    static func initializeResult(
        requestParams: StructuredValue?,
        serverVersion: String = "0.1.0"
    ) -> StructuredValue {
        let protocolVersion = negotiatedVersion(from: requestParams)
        return .object([
            "protocolVersion": .string(protocolVersion),
            "capabilities": .object([
                "resources": .object([:]),
                "tools": .object([:]),
            ]),
            "serverInfo": .object([
                "name": .string(serverName),
                "title": .string(serverTitle),
                "version": .string(serverVersion),
                "description": .string(serverDescription),
            ]),
            "instructions": .string(serverInstructions),
        ])
    }
}
