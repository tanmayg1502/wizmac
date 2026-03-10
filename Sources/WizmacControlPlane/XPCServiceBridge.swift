import Foundation
import WizmacCore

public protocol WizmacXPCServiceContract: Sendable {
    func handle(_ request: JSONRPCRequest, source: ControlPlaneSource) async throws -> JSONRPCResponse
}

public struct DispatcherBackedXPCServiceContract: WizmacXPCServiceContract {
    private let dispatcher: ControlPlaneDispatcher

    public init(dispatcher: ControlPlaneDispatcher) {
        self.dispatcher = dispatcher
    }

    public func handle(_ request: JSONRPCRequest, source: ControlPlaneSource) async throws -> JSONRPCResponse {
        await dispatcher.handleJSONRPC(request, source: source)
            ?? JSONRPCResponse(id: request.id, result: .object([:]))
    }
}

@objc public protocol WizmacXPCServiceProtocol {
    func handle(
        _ requestData: Data,
        sourceData: Data?,
        withReply reply: @escaping (Data?, NSError?) -> Void
    )
}

final class WizmacXPCExportedService: NSObject, WizmacXPCServiceProtocol {
    private let serviceContract: any WizmacXPCServiceContract

    init(serviceContract: any WizmacXPCServiceContract) {
        self.serviceContract = serviceContract
    }

    func handle(
        _ requestData: Data,
        sourceData: Data?,
        withReply reply: @escaping (Data?, NSError?) -> Void
    ) {
        let serviceContract = self.serviceContract
        let replyBox = XPCReplyBox(reply: reply)
        Task { [serviceContract, requestData, sourceData, replyBox] in
            do {
                let request = try JSONDecoder().decode(JSONRPCRequest.self, from: requestData)
                let source = try sourceData.map {
                    try JSONDecoder().decode(ControlPlaneSource.self, from: $0)
                } ?? ControlPlaneSource(kind: .cli)
                let response = try await serviceContract.handle(request, source: source)
                let data = try JSONEncoder().encode(response)
                replyBox.reply(data, nil)
            } catch {
                replyBox.reply(nil, error as NSError)
            }
        }
    }
}

private final class XPCReplyBox: @unchecked Sendable {
    let reply: (Data?, NSError?) -> Void

    init(reply: @escaping (Data?, NSError?) -> Void) {
        self.reply = reply
    }
}

/// Hosts an anonymous XPC listener. Used for in-process communication (e.g., tests).
/// The `endpoint` can be passed directly to `WizmacXPCClient(endpoint:)`.
public final class WizmacXPCListenerHost: NSObject, @unchecked Sendable {
    private let listener: NSXPCListener
    private let exportedService: WizmacXPCExportedService

    public var endpoint: NSXPCListenerEndpoint { listener.endpoint }

    public init(serviceContract: any WizmacXPCServiceContract) {
        self.listener = NSXPCListener.anonymous()
        self.exportedService = WizmacXPCExportedService(serviceContract: serviceContract)
        super.init()
        self.listener.delegate = self
    }

    public func start() {
        listener.resume()
    }

    public func stop() {
        listener.invalidate()
    }
}

extension WizmacXPCListenerHost: NSXPCListenerDelegate {
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: WizmacXPCServiceProtocol.self)
        newConnection.exportedObject = exportedService
        newConnection.resume()
        return true
    }
}

/// The fixed localhost port for the internal service HTTP server.
public enum WizmacLocalService {
    public static let port: UInt16 = 7877
    public static let url = URL(string: "http://127.0.0.1:\(port)/rpc")!
}

/// Sends JSON-RPC requests to the Wizmac service.
/// - Production: uses HTTP to `WizmacLocalService.url`
/// - Tests: uses a directly provided `NSXPCListenerEndpoint`
public actor WizmacXPCClient {
    private let localURL: URL?
    private let directEndpoint: NSXPCListenerEndpoint?
    private let processManager: WizmacServiceProcessManager?

    /// Production init: connects via local HTTP.
    public init(
        localURL: URL = WizmacLocalService.url,
        processManager: WizmacServiceProcessManager? = nil
    ) {
        self.localURL = localURL
        self.directEndpoint = nil
        self.processManager = processManager
    }

    /// Test init: connects using a directly provided in-process XPC endpoint.
    public init(endpoint: NSXPCListenerEndpoint) {
        self.localURL = nil
        self.directEndpoint = endpoint
        self.processManager = nil
    }

    public func send(
        request: JSONRPCRequest,
        source: ControlPlaneSource
    ) async throws -> JSONRPCResponse {
        try await processManager?.ensureRunning()
        return try await send(request: request, source: source, ensureRunning: false)
    }

    func send(
        request: JSONRPCRequest,
        source: ControlPlaneSource,
        ensureRunning: Bool
    ) async throws -> JSONRPCResponse {
        if ensureRunning {
            try await processManager?.ensureRunning()
        }

        if let direct = directEndpoint {
            return try await sendXPC(request: request, source: source, endpoint: direct)
        }

        guard let url = localURL else {
            throw ControlPlaneError.unsupported("No Wizmac service transport configured.")
        }
        return try await sendHTTP(request: request, source: source, to: url)
    }

    private func sendXPC(
        request: JSONRPCRequest,
        source: ControlPlaneSource,
        endpoint: NSXPCListenerEndpoint
    ) async throws -> JSONRPCResponse {
        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: WizmacXPCServiceProtocol.self)
        connection.resume()
        defer { connection.invalidate() }

        let requestData = try JSONEncoder().encode(request)
        let sourceData = try JSONEncoder().encode(source)

        return try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            }

            guard let service = proxy as? WizmacXPCServiceProtocol else {
                continuation.resume(throwing: ControlPlaneError.unsupported("Unable to connect to the Wizmac XPC service."))
                return
            }

            service.handle(requestData, sourceData: sourceData) { responseData, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let responseData else {
                    continuation.resume(throwing: ControlPlaneError.unsupported("Wizmac XPC service returned no response."))
                    return
                }
                do {
                    let response = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)
                    continuation.resume(returning: response)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func sendHTTP(
        request: JSONRPCRequest,
        source: ControlPlaneSource,
        to url: URL
    ) async throws -> JSONRPCResponse {
        let body = try JSONEncoder().encode(request)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(source.kind.rawValue, forHTTPHeaderField: "x-wizmac-source")
        if let clientID = source.clientID {
            urlRequest.setValue(clientID, forHTTPHeaderField: "x-client-id")
        }
        if let sessionID = source.sessionID {
            urlRequest.setValue(sessionID, forHTTPHeaderField: "x-session-id")
        }
        let (data, _) = try await URLSession.shared.data(for: urlRequest)
        return try JSONDecoder().decode(JSONRPCResponse.self, from: data)
    }
}
