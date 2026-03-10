import Foundation
import WizmacCore
import WizmacSystem

public struct CoreBackedControlPlaneRouter: ControlPlaneRouting {
    private let bus: CommandBus

    public init(bus: CommandBus) {
        self.bus = bus
    }

    public func handle(_ request: ControlPlaneActionRequest) async throws -> ControlPlaneActionResponse {
        let rawAction = "\(request.namespace).\(request.action)"
        guard let action = ActionName(rawValue: rawAction) else {
            return ControlPlaneActionResponse(
                status: .invalidRequest,
                message: "Unsupported action '\(rawAction)'."
            )
        }

        var arguments = request.arguments.mapValues(\.jsonValue)
        if let operation = request.arguments["operation"], arguments["interaction"] == nil {
            arguments["interaction"] = operation.jsonValue
        }
        if let token = request.arguments["token"], arguments["approvalID"] == nil {
            arguments["approvalID"] = token.jsonValue
        }

        let origin = RequestOrigin(
            kind: request.source.requestOriginKind,
            sessionID: request.source.sessionID,
            remoteAddress: request.source.clientID
        )

        let coreRequest = ActionRequest(
            action: action,
            arguments: arguments,
            origin: origin
        )
        let result = await bus.dispatch(coreRequest)

        let confirmationID = result.payload?.objectValue?["approvalID"]?.stringValue
        return ControlPlaneActionResponse(
            status: result.outcome.controlPlaneStatus,
            payload: result.payload?.structuredValue,
            message: result.message,
            auditID: result.requestID.uuidString,
            confirmationToken: confirmationID
        )
    }
}

public enum LiveControlPlaneFactory {
    public static func makeDispatcher() throws -> ControlPlaneDispatcher {
        ControlPlaneDispatcher(
            router: ServiceClientControlPlaneRouter(
                client: WizmacServiceClient()
            )
        )
    }

    public static func makeInProcessDispatcher() throws -> ControlPlaneDispatcher {
        let bus = try WizmacRuntimeFactory.makeCommandBus()
        return ControlPlaneDispatcher(router: CoreBackedControlPlaneRouter(bus: bus))
    }
}

extension StructuredValue {
    var jsonValue: JSONValue {
        switch self {
        case .null:
            return .null
        case let .bool(value):
            return .bool(value)
        case let .number(value):
            return .number(value)
        case let .string(value):
            return .string(value)
        case let .array(value):
            return .array(value.map(\.jsonValue))
        case let .object(value):
            return .object(value.mapValues(\.jsonValue))
        }
    }
}

extension JSONValue {
    var structuredValue: StructuredValue {
        switch self {
        case .null:
            return .null
        case let .bool(value):
            return .bool(value)
        case let .number(value):
            return .number(value)
        case let .string(value):
            return .string(value)
        case let .array(value):
            return .array(value.map(\.structuredValue))
        case let .object(value):
            return .object(value.mapValues(\.structuredValue))
        }
    }
}

extension ActionOutcome {
    var controlPlaneStatus: ControlPlaneStatus {
        switch self {
        case .success:
            return .success
        case .unsupported:
            return .unsupported
        case .permissionRequired:
            return .permissionRequired
        case .confirmationRequired:
            return .confirmationRequired
        case .invalidRequest:
            return .invalidRequest
        case .notFound, .failed:
            return .failed
        }
    }
}

extension ControlPlaneSource {
    var requestOriginKind: RequestOriginKind {
        switch kind {
        case .cli:
            return .cli
        case .mcp:
            return .mcp
        case .http, .automation:
            return .remote
        case .menuBar:
            return .menuBar
        }
    }
}
