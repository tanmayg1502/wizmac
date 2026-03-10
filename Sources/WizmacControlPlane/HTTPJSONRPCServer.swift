import CryptoKit
import Foundation
import Network

public struct HTTPJSONRPCServerConfiguration: Sendable {
    public var host: NWEndpoint.Host
    public var port: NWEndpoint.Port
    public var path: String
    public var allowedRemoteIdentities: [String: HTTPRemoteIdentityRecord]

    public init(
        host: String = "127.0.0.1",
        port: UInt16 = 7878,
        path: String = "/rpc",
        allowedRemoteIdentities: [String: HTTPRemoteIdentityRecord] = [:]
    ) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port) ?? 7878
        self.path = path
        self.allowedRemoteIdentities = allowedRemoteIdentities
    }
}

public final class HTTPJSONRPCServer: @unchecked Sendable {
    private let dispatcher: ControlPlaneDispatcher
    private let configuration: HTTPJSONRPCServerConfiguration
    private var listener: NWListener?

    public init(
        dispatcher: ControlPlaneDispatcher,
        configuration: HTTPJSONRPCServerConfiguration = HTTPJSONRPCServerConfiguration()
    ) {
        self.dispatcher = dispatcher
        self.configuration = configuration
    }

    public func start() throws {
        guard listener == nil else { return }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: configuration.host, port: configuration.port)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.stateUpdateHandler = { state in
            if case let .failed(error) = state {
                fputs("HTTP server failed: \(error)\n", stderr)
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receive(on: connection, accumulatedData: Data())
    }

    private func receive(on connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                fputs("HTTP connection receive error: \(error)\n", stderr)
                connection.cancel()
                return
            }

            var buffer = accumulatedData
            if let data {
                buffer.append(data)
            }

            if isComplete || self.requestLooksComplete(buffer) {
                Task {
                    let response = await self.response(for: buffer)
                    connection.send(content: response, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            } else {
                self.receive(on: connection, accumulatedData: buffer)
            }
        }
    }

    private func requestLooksComplete(_ data: Data) -> Bool {
        guard
            let request = String(data: data, encoding: .utf8),
            let headerRange = request.range(of: "\r\n\r\n")
        else {
            return false
        }

        let headerText = String(request[..<headerRange.lowerBound])
        let bodyText = String(request[headerRange.upperBound...])
        let contentLength = headerText
            .components(separatedBy: "\r\n")
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                guard parts[0].caseInsensitiveCompare("Content-Length") == .orderedSame else { return nil }
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
            .first ?? 0

        return bodyText.utf8.count >= contentLength
    }

    private func response(for data: Data) async -> Data {
        guard let request = HTTPRequest(data: data) else {
            return HTTPResponse.badRequest(body: #"{"error":"invalid_request"}"#).data
        }

        guard request.method == "POST" else {
            return HTTPResponse.methodNotAllowed.data
        }

        guard request.path == configuration.path || request.path == "/mcp" else {
            return HTTPResponse.notFound.data
        }

        if configuration.allowedRemoteIdentities.isEmpty == false {
            guard authorizeRemoteRequest(request) else {
                return HTTPResponse.unauthorized.data
            }
        }

        let rpcResponse: JSONRPCResponse
        do {
            let rpcRequest = try JSONDecoder().decode(JSONRPCRequest.self, from: request.body)
            let source = HTTPControlPlaneSourceResolver(
                trustForwardedSourceHeaders: trustsForwardedSourceHeaders
            )
            .resolve(request: request, rpcRequest: rpcRequest)
            rpcResponse = await dispatcher.handleJSONRPC(rpcRequest, source: source)
                ?? JSONRPCResponse(id: rpcRequest.id, result: .object([:]))
        } catch {
            rpcResponse = JSONRPCResponse(id: nil, error: JSONRPCStandardError.parseError)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = (try? encoder.encode(rpcResponse)) ?? Data(#"{"jsonrpc":"2.0","error":{"code":-32603,"message":"Internal error"}}"#.utf8)
        return HTTPResponse.ok(json: body).data
    }

    private var trustsForwardedSourceHeaders: Bool {
        configuration.allowedRemoteIdentities.isEmpty
    }

    private func authorizeRemoteRequest(_ request: HTTPRequest) -> Bool {
        guard let clientID = request.headers["x-client-id"],
              let identity = configuration.allowedRemoteIdentities[clientID]
        else {
            return false
        }

        if let signatureHeader = request.headers["x-wizmac-signature"],
           verifySignature(signatureHeader, for: request.body, identity: identity) {
            return true
        }

        if let legacyAccessToken = identity.legacyAccessToken,
           let providedToken = request.headers["authorization"]?.replacingOccurrences(of: "Bearer ", with: ""),
           providedToken == legacyAccessToken {
            return true
        }

        return false
    }

    private func verifySignature(
        _ headerValue: String,
        for body: Data,
        identity: HTTPRemoteIdentityRecord
    ) -> Bool {
        guard let publicKeyData = identity.publicKeyRawRepresentation else {
            return false
        }
        guard let signatureData = Data(base64Encoded: headerValue) else {
            return false
        }

        do {
            let publicKey = try P256.Signing.PublicKey(rawRepresentation: publicKeyData)
            let signature = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
            return publicKey.isValidSignature(signature, for: body)
        } catch {
            return false
        }
    }
}

struct HTTPControlPlaneSourceResolver: Sendable {
    let trustForwardedSourceHeaders: Bool

    func resolve(request: HTTPRequest, rpcRequest: JSONRPCRequest) -> ControlPlaneSource {
        let headerClientID = request.headers["x-client-id"]
        let headerSessionID = request.headers["x-session-id"]
        let headerConfirmationDefault = request.headers["x-wizmac-confirmation-default"]
            .flatMap(Bool.init(_:))
            ?? false

        if trustForwardedSourceHeaders {
            let headerKind = request.headers["x-wizmac-source"]
                .flatMap(ControlPlaneSourceKind.init(rawValue:))
            var source = bodySource(from: rpcRequest)
                ?? ControlPlaneSource(kind: headerKind ?? .http)

            if let headerKind {
                source.kind = headerKind
            }
            if source.clientID == nil {
                source.clientID = headerClientID
            }
            if source.sessionID == nil {
                source.sessionID = headerSessionID
            }
            source.requiresConfirmationByDefault = source.requiresConfirmationByDefault || headerConfirmationDefault
            return source
        }

        return ControlPlaneSource(
            kind: .http,
            clientID: headerClientID,
            sessionID: headerSessionID,
            requiresConfirmationByDefault: headerConfirmationDefault || (bodySource(from: rpcRequest)?.requiresConfirmationByDefault ?? false)
        )
    }

    private func bodySource(from rpcRequest: JSONRPCRequest) -> ControlPlaneSource? {
        guard rpcRequest.method == "tools/call" else {
            return nil
        }
        guard let sourceValue = rpcRequest.params?.objectValue?["source"] else {
            return nil
        }
        return try? sourceValue.decode(ControlPlaneSource.self)
    }
}

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    init(method: String, path: String, headers: [String: String], body: Data) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    init?(data: Data) {
        guard
            let requestText = String(data: data, encoding: .utf8),
            let headerRange = requestText.range(of: "\r\n\r\n")
        else {
            return nil
        }

        let headerText = String(requestText[..<headerRange.lowerBound])
        let bodyText = String(requestText[headerRange.upperBound...])
        let headerLines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = headerLines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count >= 2 else { return nil }

        self.method = String(requestParts[0])
        self.path = String(requestParts[1])

        var headers: [String: String] = [:]
        for line in headerLines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            headers[String(parts[0]).lowercased()] = String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
        self.headers = headers
        self.body = Data(bodyText.utf8)
    }

}

private struct HTTPResponse {
    let statusCode: Int
    let statusText: String
    let headers: [String: String]
    let body: Data

    var data: Data {
        var response = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        for (name, value) in headers {
            response += "\(name): \(value)\r\n"
        }
        response += "Content-Length: \(body.count)\r\n\r\n"

        var data = Data(response.utf8)
        data.append(body)
        return data
    }

    static func ok(json body: Data) -> HTTPResponse {
        HTTPResponse(statusCode: 200, statusText: "OK", headers: ["Content-Type": "application/json"], body: body)
    }

    static func badRequest(body: String) -> HTTPResponse {
        HTTPResponse(statusCode: 400, statusText: "Bad Request", headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }

    static let unauthorized = HTTPResponse(
        statusCode: 401,
        statusText: "Unauthorized",
        headers: ["Content-Type": "application/json"],
        body: Data(#"{"error":"unauthorized"}"#.utf8)
    )

    static let notFound = HTTPResponse(
        statusCode: 404,
        statusText: "Not Found",
        headers: ["Content-Type": "application/json"],
        body: Data(#"{"error":"not_found"}"#.utf8)
    )

    static let methodNotAllowed = HTTPResponse(
        statusCode: 405,
        statusText: "Method Not Allowed",
        headers: ["Allow": "POST", "Content-Type": "application/json"],
        body: Data(#"{"error":"method_not_allowed"}"#.utf8)
    )
}
