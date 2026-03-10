import Foundation

public enum ControlPlaneSourceKind: String, Codable, Sendable {
    case cli
    case mcp
    case http
    case menuBar
    case automation
}

public struct ControlPlaneSource: Codable, Sendable, Equatable {
    public var kind: ControlPlaneSourceKind
    public var clientID: String?
    public var sessionID: String?
    public var requiresConfirmationByDefault: Bool

    public init(
        kind: ControlPlaneSourceKind,
        clientID: String? = nil,
        sessionID: String? = nil,
        requiresConfirmationByDefault: Bool = false
    ) {
        self.kind = kind
        self.clientID = clientID
        self.sessionID = sessionID
        self.requiresConfirmationByDefault = requiresConfirmationByDefault
    }
}

public enum ControlPlaneStatus: String, Codable, Sendable {
    case success
    case unsupported
    case permissionRequired = "permission_required"
    case confirmationRequired = "confirmation_required"
    case invalidRequest = "invalid_request"
    case failed
}

public struct ControlPlaneActionRequest: Codable, Sendable, Equatable {
    public var correlationID: String
    public var namespace: String
    public var action: String
    public var arguments: [String: StructuredValue]
    public var source: ControlPlaneSource

    public init(
        correlationID: String = UUID().uuidString,
        namespace: String,
        action: String,
        arguments: [String: StructuredValue] = [:],
        source: ControlPlaneSource
    ) {
        self.correlationID = correlationID
        self.namespace = namespace
        self.action = action
        self.arguments = arguments
        self.source = source
    }

    public var toolName: String {
        "\(namespace).\(action)"
    }
}

public struct ControlPlaneActionResponse: Codable, Sendable, Equatable {
    public var status: ControlPlaneStatus
    public var payload: StructuredValue?
    public var message: String?
    public var auditID: String?
    public var confirmationToken: String?

    public init(
        status: ControlPlaneStatus,
        payload: StructuredValue? = nil,
        message: String? = nil,
        auditID: String? = nil,
        confirmationToken: String? = nil
    ) {
        self.status = status
        self.payload = payload
        self.message = message
        self.auditID = auditID
        self.confirmationToken = confirmationToken
    }
}

public enum RemoteIdentityFingerprintAlgorithm: String, Codable, Sendable {
    case sha256
}

public enum RemoteIdentityAuthenticationMethod: String, Codable, Sendable {
    case signature
    case legacyBearerMigration = "legacy_bearer_migration"
}

public struct RemoteIdentityFingerprint: Codable, Sendable, Equatable, Hashable {
    public var algorithm: RemoteIdentityFingerprintAlgorithm
    public var value: String

    public init(
        algorithm: RemoteIdentityFingerprintAlgorithm = .sha256,
        value: String
    ) {
        self.algorithm = algorithm
        self.value = value
    }
}

public struct RemoteIdentityMetadata: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var fingerprint: RemoteIdentityFingerprint
    public var issuedAt: Date
    public var authenticationMethod: RemoteIdentityAuthenticationMethod

    public init(
        id: UUID,
        name: String,
        fingerprint: RemoteIdentityFingerprint,
        issuedAt: Date = Date(),
        authenticationMethod: RemoteIdentityAuthenticationMethod = .signature
    ) {
        self.id = id
        self.name = name
        self.fingerprint = fingerprint
        self.issuedAt = issuedAt
        self.authenticationMethod = authenticationMethod
    }
}

public struct RemoteEnrollmentBundle: Codable, Sendable, Equatable {
    public var identity: RemoteIdentityMetadata
    public var clientCertificatePEM: String
    public var clientPrivateKeyPEM: String
    public var certificateAuthorityPEM: String
    public var serverHost: String
    public var serverPort: Int
    public var serverCertificateFingerprint: String

    public init(
        identity: RemoteIdentityMetadata,
        clientCertificatePEM: String,
        clientPrivateKeyPEM: String,
        certificateAuthorityPEM: String,
        serverHost: String,
        serverPort: Int,
        serverCertificateFingerprint: String
    ) {
        self.identity = identity
        self.clientCertificatePEM = clientCertificatePEM
        self.clientPrivateKeyPEM = clientPrivateKeyPEM
        self.certificateAuthorityPEM = certificateAuthorityPEM
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.serverCertificateFingerprint = serverCertificateFingerprint
    }
}

public struct ControlPlaneToolDefinition: Codable, Sendable, Equatable {
    public var name: String
    public var title: String
    public var description: String
    public var inputSchema: StructuredValue
    public var requiresConfirmation: Bool

    public init(
        name: String,
        title: String,
        description: String,
        inputSchema: StructuredValue,
        requiresConfirmation: Bool = false
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.requiresConfirmation = requiresConfirmation
    }
}

public struct ControlPlaneResourceDefinition: Codable, Sendable, Equatable {
    public var uri: String
    public var name: String
    public var description: String

    public init(uri: String, name: String, description: String) {
        self.uri = uri
        self.name = name
        self.description = description
    }
}

public enum JSONRPCID: Codable, Sendable, Equatable, Hashable {
    case string(String)
    case int(Int)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON-RPC id")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public struct JSONRPCRequest: Codable, Sendable, Equatable {
    public var jsonrpc: String
    public var id: JSONRPCID?
    public var method: String
    public var params: StructuredValue?

    public init(
        jsonrpc: String = "2.0",
        id: JSONRPCID? = nil,
        method: String,
        params: StructuredValue? = nil
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCError: Codable, Sendable, Equatable {
    public var code: Int
    public var message: String
    public var data: StructuredValue?

    public init(code: Int, message: String, data: StructuredValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public struct JSONRPCResponse: Codable, Sendable, Equatable {
    public var jsonrpc: String
    public var id: JSONRPCID?
    public var result: StructuredValue?
    public var error: JSONRPCError?

    public init(
        jsonrpc: String = "2.0",
        id: JSONRPCID?,
        result: StructuredValue? = nil,
        error: JSONRPCError? = nil
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
        self.error = error
    }
}

public enum JSONRPCStandardError {
    public static let parseError = JSONRPCError(code: -32700, message: "Parse error")
    public static let invalidRequest = JSONRPCError(code: -32600, message: "Invalid Request")
    public static let methodNotFound = JSONRPCError(code: -32601, message: "Method not found")
    public static let invalidParams = JSONRPCError(code: -32602, message: "Invalid params")
    public static let internalError = JSONRPCError(code: -32603, message: "Internal error")
}
