import Foundation

public struct MCPStdioServer {
    private let dispatcher: ControlPlaneDispatcher
    private let source: ControlPlaneSource

    public init(
        dispatcher: ControlPlaneDispatcher,
        source: ControlPlaneSource = ControlPlaneSource(kind: .mcp)
    ) {
        self.dispatcher = dispatcher
        self.source = source
    }

    public func run(
        input: FileHandle = .standardInput,
        output: FileHandle = .standardOutput
    ) async throws {
        for try await line in input.bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let response: JSONRPCResponse
            do {
                let request = try JSONDecoder().decode(JSONRPCRequest.self, from: Data(trimmed.utf8))
                guard let handled = await dispatcher.handleJSONRPC(request, source: source) else {
                    continue
                }
                response = handled
            } catch {
                response = JSONRPCResponse(id: nil, error: JSONRPCStandardError.parseError)
            }

            try write(response, to: output)
        }
    }

    private func write(_ response: JSONRPCResponse, to output: FileHandle) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(response)
        output.write(data)
        output.write(Data("\n".utf8))
    }
}
