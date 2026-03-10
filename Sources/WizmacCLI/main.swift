import Foundation
import WizmacControlPlane
import WizmacCore

@main
enum WizmacCLI {
    static func main() async {
        let dispatcher = ControlPlaneEnvironment.makeDispatcher()
        let arguments = Array(CommandLine.arguments.dropFirst())

        guard let command = arguments.first else {
            print(usage)
            return
        }

        do {
            switch command {
            case "help", "--help", "-h":
                print(usage)
            case "json":
                let payload = try loadJSONArgument(from: Array(arguments.dropFirst()))
                let request = try JSONDecoder().decode(JSONRPCRequest.self, from: payload)
                let source = ControlPlaneSource(kind: .cli)
                let response = await dispatcher.handleJSONRPC(request, source: source)
                    ?? JSONRPCResponse(id: request.id, result: .object([:]))
                try writeJSON(response)
            case "call":
                guard arguments.count >= 2 else {
                    throw CLIError("Expected a tool name after 'call'.")
                }
                let toolName = arguments[1]
                let parsed = try parseArguments(Array(arguments.dropFirst(2)))
                let response = await dispatcher.callTool(
                    named: toolName,
                    arguments: parsed,
                    source: ControlPlaneSource(kind: .cli)
                )
                try writeJSON(response)
            case "mcp":
                let server = MCPStdioServer(dispatcher: dispatcher)
                try await server.run()
            case "service":
                try await handleServiceCommand(Array(arguments.dropFirst()))
            case "serve":
                let patch = try parseServeSettingsPatch(Array(arguments.dropFirst()))
                try await runSharedService(configurationPatch: patch)
            default:
                if arguments.count >= 2 {
                    let toolName = "\(arguments[0]).\(arguments[1])"
                    let parsed = try parseArguments(Array(arguments.dropFirst(2)))
                    let response = await dispatcher.callTool(
                        named: toolName,
                        arguments: parsed,
                        source: ControlPlaneSource(kind: .cli)
                    )
                    try writeJSON(response)
                } else {
                    throw CLIError("Unknown command '\(command)'.")
                }
            }
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func loadJSONArgument(from arguments: [String]) throws -> Data {
        guard let first = arguments.first else {
            throw CLIError("Expected inline JSON or @path after 'json'.")
        }

        if first.hasPrefix("@") {
            return try Data(contentsOf: URL(fileURLWithPath: String(first.dropFirst())))
        }

        return Data(first.utf8)
    }

    private static func parseArguments(_ arguments: [String]) throws -> [String: StructuredValue] {
        var parsed: [String: StructuredValue] = [:]
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--") {
                let key = String(argument.dropFirst(2))
                let nextIndex = index + 1
                guard nextIndex < arguments.count else {
                    throw CLIError("Missing value for option '\(argument)'.")
                }
                parsed[key] = inferValue(arguments[nextIndex])
                index += 2
            } else if let separator = argument.firstIndex(of: "=") {
                let key = String(argument[..<separator])
                let value = String(argument[argument.index(after: separator)...])
                parsed[key] = inferValue(value)
                index += 1
            } else {
                throw CLIError("Could not parse argument '\(argument)'. Use --key value or key=value.")
            }
        }

        return parsed
    }

    private static func handleServiceCommand(_ arguments: [String]) async throws {
        let client = WizmacServiceClient(sourceKind: .cli)
        let subcommand = arguments.first ?? "start"

        switch subcommand {
        case "start":
            try await runSharedService(configurationPatch: nil)
        case "health":
            try writeJSON(try await client.health())
        case "snapshot":
            try writeJSON(try await client.snapshot())
        case "settings":
            try writeJSON(try await client.settings())
        default:
            throw CLIError("Unknown service command '\(subcommand)'.")
        }
    }

    private static func inferValue(_ raw: String) -> StructuredValue {
        if raw == "true" { return .bool(true) }
        if raw == "false" { return .bool(false) }
        if let intValue = Int(raw) { return .number(Double(intValue)) }
        if let doubleValue = Double(raw) { return .number(doubleValue) }
        if raw.hasPrefix("{") || raw.hasPrefix("[") {
            if let data = raw.data(using: .utf8), let value = try? JSONDecoder().decode(StructuredValue.self, from: data) {
                return value
            }
        }
        return .string(raw)
    }

    private static func runSharedService(configurationPatch: WizmacSettingsPatch?) async throws {
        let host = try WizmacServiceHost()
        try await host.start()

        if let configurationPatch {
            let client = WizmacServiceClient(sourceKind: .cli)
            _ = try await client.updateSettings(configurationPatch)
        }

        let client = WizmacServiceClient(sourceKind: .cli)
        let health = try? await client.health()
        let localURL = health?.localControlPlaneURL ?? LocalWizmacServiceConfiguration.endpointURL.absoluteString
        print("wizmac shared service listening on \(localURL)")
        if let remoteURL = health?.remoteControlPlaneURL {
            print("remote control plane available at \(remoteURL)")
        }

        try await host.runUntilCancelled()
    }

    private static func parseServeSettingsPatch(_ arguments: [String]) throws -> WizmacSettingsPatch? {
        var host = "127.0.0.1"
        var port = 47242
        var path = "/rpc"
        var enableRemote = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "serve":
                index += 1
            case "--host":
                host = try nextValue(arguments, currentIndex: &index)
            case "--port":
                let value = try nextValue(arguments, currentIndex: &index)
                guard let parsed = Int(value), parsed > 0, parsed < 65_536 else {
                    throw CLIError("Invalid port '\(value)'.")
                }
                port = parsed
            case "--path":
                path = try nextValue(arguments, currentIndex: &index)
            default:
                throw CLIError("Unknown serve option '\(argument)'.")
            }
        }

        guard arguments.isEmpty == false else {
            return nil
        }

        guard path == "/rpc" else {
            throw CLIError("Only /rpc is supported for the shared service listener.")
        }

        enableRemote = true

        let bindMode: RemoteBindMode
        if host == "127.0.0.1" {
            bindMode = .localhost
        } else if host == "0.0.0.0" {
            bindMode = .lan
        } else {
            bindMode = .custom
        }

        return WizmacSettingsPatch(
            interfaces: ["remote": enableRemote],
            remoteServer: RemoteServerSettingsPatch(
                enabled: enableRemote,
                host: host,
                port: port,
                bindMode: bindMode
            )
        )
    }

    private static func nextValue(_ arguments: [String], currentIndex: inout Int) throws -> String {
        let valueIndex = currentIndex + 1
        guard valueIndex < arguments.count else {
            throw CLIError("Missing value for option '\(arguments[currentIndex])'.")
        }
        currentIndex += 2
        return arguments[valueIndex]
    }

    private static func writeJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func runUntilCancelled() async throws {
        while true {
            try await Task.sleep(for: .seconds(60))
        }
    }

    private static let usage = """
    wizmac control-plane CLI

    Usage:
      wizmac help
      wizmac json '{...json-rpc request...}'
      wizmac call <tool.name> [--key value|key=value ...]
      wizmac <namespace> <action> [--key value|key=value ...]
      wizmac mcp
      wizmac service [start|health|snapshot|settings]
      wizmac serve [--host 127.0.0.1|0.0.0.0|custom] [--port 47242] [--path /rpc]
    """
}

private struct CLIError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
