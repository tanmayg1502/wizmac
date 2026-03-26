import Foundation
import WizmacControlPlane
import WizmacCore

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
            case "batch":
                if let result = try await handleBatchCommand(
                    Array(arguments.dropFirst()),
                    dispatcher: dispatcher
                ) {
                    try writeJSON(result.response, pretty: result.prettyOutput)
                }
            case "media":
                try await handleMediaCommand(
                    Array(arguments.dropFirst()),
                    dispatcher: dispatcher
                )
            case "init":
                try await handleInitCommand(
                    Array(arguments.dropFirst()),
                    dispatcher: dispatcher
                )
            case "key":
                let response = try await handleKeyCommand(
                    Array(arguments.dropFirst()),
                    dispatcher: dispatcher
                )
                try writeJSON(response)
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
                try writeJSON(await dispatchToolCall(toolName: toolName, arguments: parsed, dispatcher: dispatcher))
            case "mcp":
                let server = MCPStdioServer(dispatcher: dispatcher)
                try await server.run()
            case "service":
                try await handleServiceCommand(Array(arguments.dropFirst()))
            case "setup":
                try await handleSetupCommand(Array(arguments.dropFirst()))
            case "serve":
                let patch = try parseServeSettingsPatch(Array(arguments.dropFirst()))
                try await runSharedService(configurationPatch: patch)
            default:
                if command.contains(".") {
                    // Tool name already fully qualified (e.g. "scroll.to")
                    let parsed = try parseArguments(Array(arguments.dropFirst()))
                    try writeJSON(await dispatchToolCall(toolName: command, arguments: parsed, dispatcher: dispatcher))
                } else if arguments.count >= 2 {
                    let toolName = "\(arguments[0]).\(arguments[1])"
                    let parsed = try parseArguments(Array(arguments.dropFirst(2)))
                    try writeJSON(await dispatchToolCall(toolName: toolName, arguments: parsed, dispatcher: dispatcher))
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

    private static func parseArguments(
        _ arguments: [String],
        positionalKeys: [String] = []
    ) throws -> [String: StructuredValue] {
        var parsed: [String: StructuredValue] = [:]
        var index = 0
        var positionalIndex = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--") {
                let key = normalizeArgumentKey(String(argument.dropFirst(2)))
                let nextIndex = index + 1
                if nextIndex >= arguments.count || arguments[nextIndex].hasPrefix("--") {
                    parsed[key] = .bool(true)
                    index += 1
                    continue
                }
                parsed[key] = inferValue(arguments[nextIndex])
                index += 2
            } else if let separator = argument.firstIndex(of: "=") {
                let key = normalizeArgumentKey(String(argument[..<separator]))
                let value = String(argument[argument.index(after: separator)...])
                parsed[key] = inferValue(value)
                index += 1
            } else if positionalIndex < positionalKeys.count {
                parsed[positionalKeys[positionalIndex]] = inferValue(argument)
                positionalIndex += 1
                index += 1
            } else {
                throw CLIError("Could not parse argument '\(argument)'. Use --key value or key=value.")
            }
        }

        return parsed
    }

    private static func handleKeyCommand(
        _ arguments: [String],
        dispatcher: ControlPlaneDispatcher
    ) async throws -> ControlPlaneActionResponse {
        guard let subcommand = arguments.first else {
            throw CLIError("Expected a key subcommand: combo, sequence, or type.")
        }

        switch subcommand {
        case "combo":
            let parsed = try parseArguments(Array(arguments.dropFirst()))
            let normalized = try normalizeKeyComboArguments(parsed)
            return await dispatchToolCall(
                toolName: "input.key_combo",
                arguments: normalized,
                dispatcher: dispatcher
            )
        case "sequence":
            let parsed = try parseArguments(
                Array(arguments.dropFirst()),
                positionalKeys: ["sequence"]
            )
            let normalized = normalizeKeySequenceArguments(parsed)
            return await dispatchToolCall(
                toolName: "input.key_sequence",
                arguments: normalized,
                dispatcher: dispatcher
            )
        case "type":
            let parsed = try parseArguments(
                Array(arguments.dropFirst()),
                positionalKeys: ["text"]
            )
            return await dispatchToolCall(
                toolName: "text.insert",
                arguments: parsed,
                dispatcher: dispatcher
            )
        default:
            throw CLIError("Unknown key subcommand '\(subcommand)'.")
        }
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

    private static func handleSetupCommand(_ arguments: [String]) async throws {
        guard let subcommand = arguments.first else {
            print(setupUsage)
            return
        }

        if subcommand == "--help" || subcommand == "-h" || subcommand == "help" {
            print(setupUsage)
            return
        }

        switch subcommand {
        case "agents":
            let options = try parseAgentSetupCommandOptions(Array(arguments.dropFirst()))
            let targets = options.includeAll || options.targets.isEmpty
                ? WizmacAgentSetupTarget.allCases
                : options.targets
            let server = WizmacAgentSetupServerReference(mcpURL: options.mcpURL)
            let executor = WizmacAgentSetupExecutor()
            let results = targets.map { target in
                executor.execute(
                    WizmacAgentSetupPlanner.plan(
                        for: target,
                        server: server,
                        workspaceRoot: options.workspaceRoot
                    ),
                    options: WizmacAgentSetupExecutionOptions(dryRun: options.dryRun)
                )
            }
            try writeJSON(results)
        default:
            throw CLIError("Unknown setup command '\(subcommand)'.")
        }
    }

    private static func dispatchToolCall(
        toolName: String,
        arguments: [String: StructuredValue],
        dispatcher: ControlPlaneDispatcher
    ) async -> ControlPlaneActionResponse {
        let source = ControlPlaneSource(kind: .cli)
        let environment = ProcessInfo.processInfo.environment

        // Fixture-backed CLI tests inject a local dispatcher configuration and
        // should not tunnel through any ambient shared service state.
        if environment[ControlPlaneEnvironment.fixtureEnvironmentKey] != nil {
            return await dispatcher.callTool(named: toolName, arguments: arguments, source: source)
        }

        // Try dispatching through the running service (which has AX permissions)
        if let serviceResponse = try? await WizmacServiceClient(sourceKind: .cli).callTool(
            named: toolName,
            arguments: arguments,
            source: source
        ) {
            return serviceResponse
        }
        // Fall back to local dispatch
        return await dispatcher.callTool(named: toolName, arguments: arguments, source: source)
    }

    private static func inferValue(_ raw: String) -> StructuredValue {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "true" { return .bool(true) }
        if trimmed == "false" { return .bool(false) }
        if let intValue = Int(trimmed) { return .number(Double(intValue)) }
        if let doubleValue = Double(trimmed) { return .number(doubleValue) }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let data = trimmed.data(using: .utf8), let value = try? JSONDecoder().decode(StructuredValue.self, from: data) {
                return value
            }
        }
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            return .string(String(trimmed.dropFirst().dropLast()))
        }
        if trimmed.hasPrefix("'"), trimmed.hasSuffix("'"), trimmed.count >= 2 {
            return .string(String(trimmed.dropFirst().dropLast()))
        }
        return .string(trimmed)
    }

    private static func normalizeArgumentKey(_ raw: String) -> String {
        guard raw.contains("-") else { return raw }

        let segments = raw.split(separator: "-").map(String.init)
        guard let first = segments.first else { return raw }

        return segments.dropFirst().reduce(first) { partial, segment in
            partial + segment.prefix(1).uppercased() + segment.dropFirst()
        }
    }

    private static func normalizeKeyComboArguments(
        _ arguments: [String: StructuredValue]
    ) throws -> [String: StructuredValue] {
        guard
            let key = arguments["key"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            key.isEmpty == false
        else {
            throw CLIError("Key combos require a non-empty --key value.")
        }

        var normalized = arguments
        normalized["key"] = .string(key)

        let rawModifiers = arguments["modifiers"] ?? arguments["mods"]
        let modifiers = parseModifierList(rawModifiers)
        if modifiers.isEmpty == false {
            normalized["modifiers"] = .array(modifiers.map(StructuredValue.string))
        }
        normalized.removeValue(forKey: "mods")
        return normalized
    }

    private static func normalizeKeySequenceArguments(
        _ arguments: [String: StructuredValue]
    ) -> [String: StructuredValue] {
        var normalized = arguments

        if normalized["steps"] == nil,
           let sequence = arguments["sequence"]?.stringValue
        {
            let steps = sequence
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
            if steps.isEmpty == false {
                normalized["steps"] = .array(steps.map(StructuredValue.string))
            }
        }

        return normalized
    }

    private static func handleBatchCommand(
        _ arguments: [String],
        dispatcher: ControlPlaneDispatcher
    ) async throws -> BatchCLIResult? {
        if arguments.isEmpty || arguments.contains(where: { $0 == "--help" || $0 == "-h" }) {
            print(batchUsage)
            return nil
        }

        let options = try parseBatchCommandOptions(arguments)
        let steps = try loadBatchSteps(from: options)
        guard steps.isEmpty == false else {
            throw CLIError("Batch requires at least one step.")
        }

        var batchArguments: [String: StructuredValue] = [
            "steps": .array(steps.map { step in
                .object([
                    "action": .string(step.action),
                    "args": .object(step.arguments),
                ])
            }),
            "failFast": .bool(options.failFast),
            "maxParallel": .number(Double(options.maxParallel)),
            "output": .string(options.outputFormat.rawValue),
        ]

        for (key, value) in options.ambientArguments {
            batchArguments[key] = value
        }

        if let inputFormat = options.inputFormat {
            batchArguments["format"] = .string(inputFormat.rawValue)
        }
        if let filePath = options.filePath {
            batchArguments["file"] = .string(filePath)
        }
        if let cachePolicy = options.cachePolicy {
            batchArguments["cachePolicy"] = .string(cachePolicy)
        }
        if let snapshotReuse = options.snapshotReuse {
            batchArguments["snapshotReuse"] = .string(snapshotReuse)
        }
        if options.invalidateOn.isEmpty == false {
            batchArguments["invalidateOn"] = .array(options.invalidateOn.map(StructuredValue.string))
        }

        let response = await dispatchToolCall(
            toolName: "batch.run",
            arguments: batchArguments,
            dispatcher: dispatcher
        )
        return BatchCLIResult(response: response, prettyOutput: options.outputFormat == .pretty)
    }

    private static func handleMediaCommand(
        _ arguments: [String],
        dispatcher: ControlPlaneDispatcher
    ) async throws {
        guard let subcommand = arguments.first else {
            print(mediaUsage)
            return
        }

        if subcommand == "--help" || subcommand == "-h" || subcommand == "help" {
            print(mediaUsage)
            return
        }

        switch subcommand {
        case "screenshot":
            let parsed = try parseArguments(Array(arguments.dropFirst()))
            let normalized = normalizeMediaScreenshotArguments(parsed)
            try writeJSON(await dispatchToolCall(
                toolName: "media.screenshot",
                arguments: normalized,
                dispatcher: dispatcher
            ))
        case "record", "stream":
            let lifecycleResult = try parseMediaLifecycleCommand(
                arguments: Array(arguments.dropFirst())
            )
            try writeJSON(await dispatchToolCall(
                toolName: "media.\(subcommand)",
                arguments: lifecycleResult.arguments,
                dispatcher: dispatcher
            ))
        default:
            throw CLIError("Unknown media subcommand '\(subcommand)'.")
        }
    }

    private static func handleInitCommand(
        _ arguments: [String],
        dispatcher: ControlPlaneDispatcher
    ) async throws {
        if arguments.contains(where: { $0 == "--help" || $0 == "-h" }) {
            print(initUsage)
            return
        }

        let options = try parseInitCommandOptions(arguments)

        let healthResponse = await dispatchToolCall(
            toolName: "system.health",
            arguments: [:],
            dispatcher: dispatcher
        )
        guard healthResponse.status == .success else {
            throw CLIError("Unable to confirm service health: \(healthResponse.message ?? "unknown error").")
        }

        let permissionsResponse = await dispatchToolCall(
            toolName: "system.permissions",
            arguments: [:],
            dispatcher: dispatcher
        )
        guard permissionsResponse.status == .success else {
            throw CLIError("Unable to inspect permissions: \(permissionsResponse.message ?? "unknown error").")
        }

        let sampleBatchURL = URL(fileURLWithPath: options.sampleBatchPath)
        try writeSampleBatchFile(at: sampleBatchURL, overwrite: options.overwrite)

        print("Service is healthy.")
        if let message = healthResponse.message {
            print(message)
        }
        print(permissionSummary(from: permissionsResponse))
        for detail in permissionDetails(from: permissionsResponse) {
            print(detail)
        }
        print("Wrote sample batch file at \(sampleBatchURL.path).")

        let remoteClientsResponse = await dispatchToolCall(
            toolName: "remote.clients",
            arguments: [:],
            dispatcher: dispatcher
        )
        if let summary = remotePairingSummary(from: remoteClientsResponse) {
            print(summary)
        }

        if options.fixtureSmokeEnabled {
            try await runFixtureSmokeFlow(
                fixtureApp: options.fixtureApp,
                fixtureQuery: options.fixtureQuery,
                dispatcher: dispatcher
            )
        }
    }

    private static func parseBatchCommandOptions(_ arguments: [String]) throws -> BatchCommandOptions {
        var options = BatchCommandOptions()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--step":
                options.stepStrings.append(try nextValue(arguments, currentIndex: &index))
            case let raw where raw.hasPrefix("--step="):
                options.stepStrings.append(String(raw.dropFirst("--step=".count)))
                index += 1
            case "--file":
                options.filePath = try nextValue(arguments, currentIndex: &index)
            case let raw where raw.hasPrefix("--file="):
                options.filePath = String(raw.dropFirst("--file=".count))
                index += 1
            case "--format":
                options.inputFormat = try parseBatchInputFormat(nextValue(arguments, currentIndex: &index))
            case let raw where raw.hasPrefix("--format="):
                options.inputFormat = try parseBatchInputFormat(String(raw.dropFirst("--format=".count)))
                index += 1
            case "--output":
                options.outputFormat = try parseBatchOutputFormat(nextValue(arguments, currentIndex: &index))
            case let raw where raw.hasPrefix("--output="):
                options.outputFormat = try parseBatchOutputFormat(String(raw.dropFirst("--output=".count)))
                index += 1
            case "--fail-fast":
                options.failFast = try parseOptionalBool(arguments, index: &index) ?? true
            case let raw where raw.hasPrefix("--fail-fast="):
                options.failFast = try parseBoolValue(String(raw.dropFirst("--fail-fast=".count)))
                index += 1
            case "--continue-on-error":
                let enabled = try parseOptionalBool(arguments, index: &index) ?? true
                options.failFast = enabled ? false : true
            case let raw where raw.hasPrefix("--continue-on-error="):
                let enabled = try parseBoolValue(String(raw.dropFirst("--continue-on-error=".count)))
                options.failFast = enabled ? false : true
                index += 1
            case "--max-parallel":
                let value = try nextValue(arguments, currentIndex: &index)
                guard let parsed = Int(value), parsed == 1 else {
                    throw CLIError("Batch v1 supports `--max-parallel 1` only.")
                }
                options.maxParallel = parsed
            case let raw where raw.hasPrefix("--max-parallel="):
                let value = String(raw.dropFirst("--max-parallel=".count))
                guard let parsed = Int(value), parsed == 1 else {
                    throw CLIError("Batch v1 supports `--max-parallel 1` only.")
                }
                options.maxParallel = parsed
                index += 1
            case "--cache-policy":
                options.cachePolicy = try parseBatchCachePolicy(nextValue(arguments, currentIndex: &index))
            case let raw where raw.hasPrefix("--cache-policy="):
                options.cachePolicy = try parseBatchCachePolicy(String(raw.dropFirst("--cache-policy=".count)))
                index += 1
            case "--snapshot-reuse":
                options.snapshotReuse = try parseBatchSnapshotReuse(nextValue(arguments, currentIndex: &index))
            case let raw where raw.hasPrefix("--snapshot-reuse="):
                options.snapshotReuse = try parseBatchSnapshotReuse(String(raw.dropFirst("--snapshot-reuse=".count)))
                index += 1
            case "--invalidate-on":
                options.invalidateOn.append(contentsOf: parseCSVList(try nextValue(arguments, currentIndex: &index)))
            case let raw where raw.hasPrefix("--invalidate-on="):
                options.invalidateOn.append(contentsOf: parseCSVList(String(raw.dropFirst("--invalidate-on=".count))))
                index += 1
            case "--app":
                options.ambientArguments["app"] = .string(try nextValue(arguments, currentIndex: &index))
            case let raw where raw.hasPrefix("--app="):
                options.ambientArguments["app"] = .string(String(raw.dropFirst("--app=".count)))
                index += 1
            case "--pid":
                let value = try nextValue(arguments, currentIndex: &index)
                guard let pid = Int(value) else {
                    throw CLIError("Invalid pid '\(value)'.")
                }
                options.ambientArguments["pid"] = .number(Double(pid))
            case let raw where raw.hasPrefix("--pid="):
                let value = String(raw.dropFirst("--pid=".count))
                guard let pid = Int(value) else {
                    throw CLIError("Invalid pid '\(value)'.")
                }
                options.ambientArguments["pid"] = .number(Double(pid))
                index += 1
            case "--scope":
                options.ambientArguments["scope"] = .string(try nextValue(arguments, currentIndex: &index))
            case let raw where raw.hasPrefix("--scope="):
                options.ambientArguments["scope"] = .string(String(raw.dropFirst("--scope=".count)))
                index += 1
            case "--adapter":
                options.ambientArguments["adapter"] = .string(try nextValue(arguments, currentIndex: &index))
            case let raw where raw.hasPrefix("--adapter="):
                options.ambientArguments["adapter"] = .string(String(raw.dropFirst("--adapter=".count)))
                index += 1
            case "--include-menus":
                options.ambientArguments["includeMenus"] = .bool(try parseOptionalBool(arguments, index: &index) ?? true)
            case let raw where raw.hasPrefix("--include-menus="):
                options.ambientArguments["includeMenus"] = .bool(try parseBoolValue(String(raw.dropFirst("--include-menus=".count))))
                index += 1
            case "--launch-if-needed":
                options.ambientArguments["launchIfNeeded"] = .bool(try parseOptionalBool(arguments, index: &index) ?? true)
            case let raw where raw.hasPrefix("--launch-if-needed="):
                options.ambientArguments["launchIfNeeded"] = .bool(try parseBoolValue(String(raw.dropFirst("--launch-if-needed=".count))))
                index += 1
            case "--activate":
                options.ambientArguments["activate"] = .bool(try parseOptionalBool(arguments, index: &index) ?? true)
            case let raw where raw.hasPrefix("--activate="):
                options.ambientArguments["activate"] = .bool(try parseBoolValue(String(raw.dropFirst("--activate=".count))))
                index += 1
            case "--auto-trust":
                options.ambientArguments["autoTrust"] = .bool(try parseOptionalBool(arguments, index: &index) ?? true)
            case let raw where raw.hasPrefix("--auto-trust="):
                options.ambientArguments["autoTrust"] = .bool(try parseBoolValue(String(raw.dropFirst("--auto-trust=".count))))
                index += 1
            case "--trusted-session-id":
                options.ambientArguments["trustedSessionID"] = .string(try nextValue(arguments, currentIndex: &index))
            case let raw where raw.hasPrefix("--trusted-session-id="):
                options.ambientArguments["trustedSessionID"] = .string(String(raw.dropFirst("--trusted-session-id=".count)))
                index += 1
            default:
                throw CLIError("Unknown batch option '\(argument)'.")
            }
        }

        if options.filePath == nil, options.stepStrings.isEmpty {
            throw CLIError("Batch requires at least one `--step` or `--file`.")
        }

        if options.inputFormat == nil, let filePath = options.filePath {
            options.inputFormat = inferBatchInputFormat(from: filePath)
        }

        return options
    }

    private static func loadBatchSteps(from options: BatchCommandOptions) throws -> [BatchStepSpecification] {
        var steps: [BatchStepSpecification] = []

        for rawStep in options.stepStrings {
            steps.append(contentsOf: try parseBatchStepSource(rawStep))
        }

        if let filePath = options.filePath {
            let url = URL(fileURLWithPath: filePath)
            let text = try String(contentsOf: url, encoding: .utf8)
            let inputFormat = options.inputFormat ?? inferBatchInputFormat(from: filePath) ?? .json
            steps.append(contentsOf: try parseBatchFileSteps(text: text, format: inputFormat))
        }

        return steps
    }

    private static func parseBatchFileSteps(text: String, format: BatchInputFormat) throws -> [BatchStepSpecification] {
        switch format {
        case .json:
            return try parseBatchJSONSteps(text: text)
        case .line:
            return try parseBatchLineSteps(text: text)
        case .yaml:
            return try parseBatchYAMLSteps(text: text)
        }
    }

    private static func parseBatchJSONSteps(text: String) throws -> [BatchStepSpecification] {
        let data = Data(text.utf8)
        let value = try JSONDecoder().decode(StructuredValue.self, from: data)
        return try parseBatchStructuredSteps(value)
    }

    private static func parseBatchLineSteps(text: String) throws -> [BatchStepSpecification] {
        var steps: [BatchStepSpecification] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            steps.append(contentsOf: try parseBatchStepSource(trimmed))
        }
        return steps
    }

    private static func parseBatchYAMLSteps(text: String) throws -> [BatchStepSpecification] {
        var steps: [BatchStepSpecification] = []
        var currentAction: String?
        var currentArguments: [String: StructuredValue] = [:]
        var parsingArgsBlock = false
        var currentIndent = 0

        func commitCurrentStep() {
            guard let action = currentAction else { return }
            steps.append(BatchStepSpecification(action: action, arguments: currentArguments))
            currentAction = nil
            currentArguments = [:]
            parsingArgsBlock = false
            currentIndent = 0
        }

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            let indentation = line.prefix { $0 == " " || $0 == "\t" }.count
            if trimmed.hasPrefix("-") {
                commitCurrentStep()
                let content = trimmed.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                let fields = try parseInlineKeyValuePairs(content)
                currentAction = fields["action"]?.stringValue ?? fields["tool"]?.stringValue ?? fields["name"]?.stringValue
                if currentAction == nil, content.contains(":") == false {
                    currentAction = content
                }
                for (key, value) in fields where key != "action" && key != "tool" && key != "name" && key != "args" {
                    currentArguments[key] = value
                }
                if let argsValue = fields["args"] {
                    let parsed = try parseBatchInlineArguments(from: argsValue)
                    for (key, value) in parsed {
                        currentArguments[key] = value
                    }
                }
                parsingArgsBlock = false
                currentIndent = indentation
                continue
            }

            guard currentAction != nil else { continue }

            if trimmed.hasPrefix("args:") {
                let remainder = trimmed.dropFirst("args:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                if remainder.isEmpty {
                    parsingArgsBlock = true
                } else {
                    let parsed = try parseBatchInlineArguments(from: .string(remainder))
                    for (key, value) in parsed {
                        currentArguments[key] = value
                    }
                    parsingArgsBlock = false
                }
                currentIndent = indentation
                continue
            }

            if parsingArgsBlock || indentation > currentIndent {
                let pair = try parseInlineKeyValuePair(trimmed)
                currentArguments[pair.key] = pair.value
            }
        }

        commitCurrentStep()
        return steps
    }

    private static func parseBatchStructuredSteps(_ value: StructuredValue) throws -> [BatchStepSpecification] {
        switch value {
        case let .array(items):
            return try items.map(parseBatchStructuredStep(_:))
        case let .object(object):
            if let steps = object["steps"]?.arrayValue {
                return try steps.map(parseBatchStructuredStep(_:))
            }
            return [try parseBatchStructuredStep(value)]
        default:
            throw CLIError("Batch file must contain a step array or object.")
        }
    }

    private static func parseBatchStructuredStep(_ value: StructuredValue) throws -> BatchStepSpecification {
        if let raw = value.stringValue {
            return try parseBatchStepSource(raw).first ?? BatchStepSpecification(action: raw, arguments: [:])
        }

        guard let object = value.objectValue else {
            throw CLIError("Each batch step must be an object or string.")
        }

        guard let action = object["action"]?.stringValue ?? object["tool"]?.stringValue ?? object["name"]?.stringValue else {
            throw CLIError("Each batch step must include `action`.")
        }

        let argsValue = object["args"] ?? .object([:])
        let arguments = try parseBatchStructuredArguments(argsValue)
        return BatchStepSpecification(action: action, arguments: arguments)
    }

    private static func parseBatchStructuredArguments(_ value: StructuredValue) throws -> [String: StructuredValue] {
        guard let object = value.objectValue else {
            if value == .null { return [:] }
            throw CLIError("Batch step args must be an object.")
        }
        return object
    }

    private static func parseBatchInlineArguments(from value: StructuredValue) throws -> [String: StructuredValue] {
        if let object = value.objectValue {
            return object
        }
        if let string = value.stringValue {
            if string.hasPrefix("{"), let data = string.data(using: .utf8), let parsed = try? JSONDecoder().decode(StructuredValue.self, from: data), let object = parsed.objectValue {
                return object
            }
            return try parseInlineDictionary(string)
        }
        throw CLIError("Batch args must be an object.")
    }

    private static func parseBatchStepSource(_ raw: String) throws -> [BatchStepSpecification] {
        let tokens = shellSplit(raw)
        guard tokens.isEmpty == false else { return [] }

        if tokens.count >= 2, tokens[0].contains(".") == false, tokens[1].contains("=") == false, tokens[0].hasPrefix("-") == false {
            let action = "\(tokens[0]).\(tokens[1])"
            let arguments = try parseArguments(Array(tokens.dropFirst(2)))
            return [BatchStepSpecification(action: action, arguments: arguments)]
        }

        let action = tokens[0]
        let arguments = try parseArguments(Array(tokens.dropFirst()))
        return [BatchStepSpecification(action: action, arguments: arguments)]
    }

    private static func parseInlineDictionary(_ raw: String) throws -> [String: StructuredValue] {
        var dictionary: [String: StructuredValue] = [:]
        for part in splitTopLevelCSV(stripBraces(raw)) {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let pair = try parseInlineKeyValuePair(trimmed)
            dictionary[pair.key] = pair.value
        }
        return dictionary
    }

    private static func parseInlineKeyValuePairs(_ raw: String) throws -> [String: StructuredValue] {
        var dictionary: [String: StructuredValue] = [:]
        for part in splitTopLevelCSV(raw) {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let pair = try parseInlineKeyValuePair(trimmed)
            dictionary[pair.key] = pair.value
        }
        return dictionary
    }

    private static func parseInlineKeyValuePair(_ raw: String) throws -> (key: String, value: StructuredValue) {
        guard let separator = raw.firstIndex(of: ":") ?? raw.firstIndex(of: "=") else {
            throw CLIError("Could not parse batch item '\(raw)'.")
        }
        let key = normalizeArgumentKey(String(raw[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines))
        let value = String(raw[raw.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (key: key, value: inferValue(value))
    }

    private static func splitTopLevelCSV(_ raw: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var braceDepth = 0
        var quote: Character?
        var escapeNext = false

        for character in raw {
            if escapeNext {
                current.append(character)
                escapeNext = false
                continue
            }
            if character == "\\" {
                current.append(character)
                escapeNext = true
                continue
            }
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote {
                    quote = nil
                }
                continue
            }
            switch character {
            case "\"", "'":
                quote = character
                current.append(character)
            case "{", "[", "(":
                braceDepth += 1
                current.append(character)
            case "}", "]", ")":
                braceDepth = max(braceDepth - 1, 0)
                current.append(character)
            case "," where braceDepth == 0:
                parts.append(current)
                current = ""
            default:
                current.append(character)
            }
            if quote != nil, current.last == quote {
                quote = nil
            }
        }

        if current.isEmpty == false {
            parts.append(current)
        }
        return parts
    }

    private static func stripBraces(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    private static func shellSplit(_ raw: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escapeNext = false

        for character in raw {
            if escapeNext {
                current.append(character)
                escapeNext = false
                continue
            }
            if character == "\\" {
                escapeNext = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            if character.isWhitespace {
                if current.isEmpty == false {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }

        if current.isEmpty == false {
            tokens.append(current)
        }
        return tokens
    }

    private static func parseBatchInputFormat(_ raw: String) throws -> BatchInputFormat {
        guard let format = BatchInputFormat(rawValue: raw.lowercased()) else {
            throw CLIError("Unsupported batch input format '\(raw)'.")
        }
        return format
    }

    private static func parseBatchOutputFormat(_ raw: String) throws -> BatchOutputFormat {
        guard let format = BatchOutputFormat(rawValue: raw.lowercased()) else {
            throw CLIError("Unsupported batch output format '\(raw)'.")
        }
        return format
    }

    private static func parseBatchCachePolicy(_ raw: String) throws -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["none", "step", "batch"].contains(normalized) else {
            throw CLIError("Unsupported batch cache policy '\(raw)'.")
        }
        return normalized
    }

    private static func parseBatchSnapshotReuse(_ raw: String) throws -> String {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        guard ["off", "best_effort", "strict"].contains(normalized) else {
            throw CLIError("Unsupported batch snapshot reuse mode '\(raw)'.")
        }
        return normalized
    }

    private static func parseCSVList(_ raw: String) -> [String] {
        raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private static func inferBatchInputFormat(from path: String) -> BatchInputFormat? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "yaml", "yml", "wzb":
            return .yaml
        case "line", "txt":
            return .line
        case "json":
            return .json
        default:
            return nil
        }
    }

    private static func parseBoolValue(_ raw: String) throws -> Bool {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1", "on":
            return true
        case "false", "no", "0", "off":
            return false
        default:
            throw CLIError("Could not parse boolean value '\(raw)'.")
        }
    }

    private static func parseOptionalBool(_ arguments: [String], index: inout Int) throws -> Bool? {
        let nextIndex = index + 1
        guard nextIndex < arguments.count else {
            index += 1
            return nil
        }
        let next = arguments[nextIndex]
        if next.hasPrefix("--") {
            index += 1
            return nil
        }
        index += 2
        return try parseBoolValue(next)
    }

    private static func parseMediaLifecycleCommand(arguments: [String]) throws -> MediaLifecycleCommandResult {
        let parsed = try parseArguments(arguments, positionalKeys: ["action"])
        guard let action = parsed["action"]?.stringValue else {
            throw CLIError("Expected a media lifecycle action: start, stop, or status.")
        }
        guard ["start", "stop", "status"].contains(action) else {
            throw CLIError("Unknown media lifecycle action '\(action)'.")
        }

        var normalized = parsed
        normalized["action"] = .string(action)
        return MediaLifecycleCommandResult(arguments: normalized)
    }

    private static func normalizeMediaScreenshotArguments(_ arguments: [String: StructuredValue]) -> [String: StructuredValue] {
        var normalized = arguments
        if normalized["format"] == nil {
            normalized["format"] = .string("png")
        }
        return normalized
    }

    private static func parseAgentSetupCommandOptions(_ arguments: [String]) throws -> AgentSetupCommandOptions {
        var options = AgentSetupCommandOptions()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--all":
                options.includeAll = true
                index += 1
            case "--dry-run":
                options.dryRun = true
                index += 1
            case "--mcp-url":
                options.mcpURL = try nextValue(arguments, currentIndex: &index)
            case let raw where raw.hasPrefix("--mcp-url="):
                options.mcpURL = String(raw.dropFirst("--mcp-url=".count))
                index += 1
            case "--workspace-root":
                options.workspaceRoot = URL(fileURLWithPath: try nextValue(arguments, currentIndex: &index))
            case let raw where raw.hasPrefix("--workspace-root="):
                options.workspaceRoot = URL(fileURLWithPath: String(raw.dropFirst("--workspace-root=".count)))
                index += 1
            case "--help", "-h":
                index += 1
            default:
                if argument.hasPrefix("--") {
                    throw CLIError("Unknown setup option '\(argument)'.")
                }
                options.targets.append(try parseAgentSetupTarget(argument))
                index += 1
            }
        }

        return options
    }

    private static func parseAgentSetupTarget(_ raw: String) throws -> WizmacAgentSetupTarget {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "claude", "claude-code", "claudecode":
            return .claudeCode
        case "gemini", "gemini-cli", "geminicli":
            return .geminiCLI
        case "codex":
            return .codex
        case "openclaw", "open-claw":
            return .openClaw
        default:
            throw CLIError("Unknown setup target '\(raw)'.")
        }
    }

    private static func parseInitCommandOptions(_ arguments: [String]) throws -> InitCommandOptions {
        var options = InitCommandOptions()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--sample-batch-file":
                options.sampleBatchPath = try nextValue(arguments, currentIndex: &index)
            case let raw where raw.hasPrefix("--sample-batch-file="):
                options.sampleBatchPath = String(raw.dropFirst("--sample-batch-file=".count))
                index += 1
            case "--sample-batch-path":
                options.sampleBatchPath = try nextValue(arguments, currentIndex: &index)
            case let raw where raw.hasPrefix("--sample-batch-path="):
                options.sampleBatchPath = String(raw.dropFirst("--sample-batch-path=".count))
                index += 1
            case "--force", "--overwrite":
                options.overwrite = try parseOptionalBool(arguments, index: &index) ?? true
            case let raw where raw.hasPrefix("--force="):
                options.overwrite = try parseBoolValue(String(raw.dropFirst("--force=".count)))
                index += 1
            case let raw where raw.hasPrefix("--overwrite="):
                options.overwrite = try parseBoolValue(String(raw.dropFirst("--overwrite=".count)))
                index += 1
            case "--fixture-smoke", "--smoke", "--smoke-fixture":
                options.fixtureSmokeEnabled = try parseOptionalBool(arguments, index: &index) ?? true
            case let raw where raw.hasPrefix("--fixture-smoke="):
                options.fixtureSmokeEnabled = try parseBoolValue(String(raw.dropFirst("--fixture-smoke=".count)))
                index += 1
            case let raw where raw.hasPrefix("--smoke="):
                options.fixtureSmokeEnabled = try parseBoolValue(String(raw.dropFirst("--smoke=".count)))
                index += 1
            case let raw where raw.hasPrefix("--smoke-fixture="):
                options.fixtureSmokeEnabled = try parseBoolValue(String(raw.dropFirst("--smoke-fixture=".count)))
                index += 1
            case "--fixture-app":
                options.fixtureApp = try nextValue(arguments, currentIndex: &index)
            case let raw where raw.hasPrefix("--fixture-app="):
                options.fixtureApp = String(raw.dropFirst("--fixture-app=".count))
                index += 1
            case "--fixture-query":
                options.fixtureQuery = try nextValue(arguments, currentIndex: &index)
            case let raw where raw.hasPrefix("--fixture-query="):
                options.fixtureQuery = String(raw.dropFirst("--fixture-query=".count))
                index += 1
            case "--help", "-h":
                index += 1
            default:
                throw CLIError("Unknown init option '\(argument)'.")
            }
        }

        return options
    }

    private static func writeSampleBatchFile(at url: URL, overwrite: Bool) throws {
        let sample = """
        - action: ui.search
          args:
            query: Primary
        - action: wait.ui.exists
          args:
            query: Primary
            timeoutMs: 5000
            intervalMs: 200
        - action: ui.act
          args:
            query: Primary
            activate: true
        """

        let fm = FileManager.default
        if fm.fileExists(atPath: url.path), overwrite == false {
            print("Sample batch file already exists at \(url.path); leaving it untouched.")
            return
        }
        try sample.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func permissionSummary(from response: ControlPlaneActionResponse) -> String {
        let missing = missingPermissions(from: response)
        if missing.isEmpty {
            return "Permissions checked. Required permissions currently look available."
        }
        return "Permissions checked. Missing or incomplete permissions: \(missing.joined(separator: ", "))."
    }

    private static func permissionDetails(from response: ControlPlaneActionResponse) -> [String] {
        response.payload?.arrayValue?.compactMap { value in
            guard let object = value.objectValue else { return nil }
            guard let detail = object["detail"]?.stringValue, detail.isEmpty == false else { return nil }
            return "- \(object["name"]?.stringValue ?? "permission"): \(detail)"
        } ?? []
    }

    private static func missingPermissions(from response: ControlPlaneActionResponse) -> [String] {
        response.payload?.arrayValue?.compactMap { value in
            guard let object = value.objectValue else { return nil }
            guard object["state"]?.stringValue == "permissionRequired" else { return nil }
            return object["name"]?.stringValue
        } ?? []
    }

    private static func remotePairingSummary(from response: ControlPlaneActionResponse) -> String? {
        guard response.status == .success else { return nil }
        let count = response.payload?.arrayValue?.count ?? 0
        if count == 0 {
            return #"Remote pairing: no paired clients yet. Run `wizmac remote pair --name "QA Agent"` when you want remote access."#
        }
        return "Remote pairing: \(count) paired client(s) available."
    }

    private static func runFixtureSmokeFlow(
        fixtureApp: String,
        fixtureQuery: String,
        dispatcher: ControlPlaneDispatcher
    ) async throws {
        let response = await dispatchToolCall(
            toolName: "ui.search",
            arguments: [
                "app": .string(fixtureApp),
                "query": .string(fixtureQuery),
                "limit": .number(1),
            ],
            dispatcher: dispatcher
        )

        if response.status == .success {
            print("Fixture smoke flow succeeded for \(fixtureApp) with query '\(fixtureQuery)'.")
        } else {
            print("Fixture smoke flow did not complete cleanly: \(response.message ?? "unknown error").")
        }
    }

    private static func parseModifierList(_ value: StructuredValue?) -> [String] {
        let rawTokens: [String]
        switch value {
        case let .string(raw):
            rawTokens = raw.split(separator: ",").map(String.init)
        case let .array(values):
            rawTokens = values.compactMap(\.stringValue)
        default:
            rawTokens = []
        }

        return rawTokens
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.isEmpty == false }
            .map(normalizeModifierName(_:))
    }

    private static func normalizeModifierName(_ raw: String) -> String {
        switch raw {
        case "cmd", "command":
            return "command"
        case "ctrl", "control":
            return "control"
        case "opt", "alt", "option":
            return "option"
        case "fn", "function":
            return "function"
        default:
            return raw
        }
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
        try writeJSON(value, pretty: true)
    }

    private static func writeJSON<T: Encodable>(_ value: T, pretty: Bool) throws {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys]
        if pretty {
            formatting.insert(.prettyPrinted)
        }
        encoder.outputFormatting = formatting
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
      wizmac key combo --mods cmd,shift --key z [--pre-delay-ms 50] [--post-delay-ms 50]
      wizmac key sequence "cmd+a,delete,cmd+v" [--pre-delay-ms 50] [--post-delay-ms 50]
      wizmac key type "hello" [--pre-delay-ms 50] [--post-delay-ms 50]
      wizmac batch --step "ui.search query=Primary" --output pretty
      wizmac batch --file flow.wzb --format yaml --continue-on-error
      wizmac media screenshot --app "Safari" --path /tmp/s.png
      wizmac media record start --sessionID abc --codec h264 --fps 30
      wizmac media stream start --format mjpeg
      wizmac init [--sample-batch-file wizmac.sample.wzb] [--fixture-smoke]
      wizmac setup agents --all [--dry-run] [--mcp-url http://127.0.0.1:7877/mcp]
      wizmac mcp
      wizmac service [start|health|snapshot|settings]
      wizmac serve [--host 127.0.0.1|0.0.0.0|custom] [--port 47242] [--path /rpc]

    Timing flags:
      --pre-delay-ms <ms>
      --post-delay-ms <ms>
      --timeout-ms <ms>
      --poll-interval-ms <ms>
    """

    private static let batchUsage = """
    wizmac batch

    Usage:
      wizmac batch --step "ui.search query=Primary" --step "ui.act query=Primary" --output pretty
      wizmac batch --file flow.wzb --format yaml --continue-on-error --cache-policy batch

    Flags:
      --step <step>                 Add a batch step. Can be repeated.
      --file <path>                 Load batch steps from a file.
      --format yaml|json|line       Batch file input format.
      --fail-fast                   Stop on the first failing step.
      --continue-on-error           Keep going after failures.
      --output json|pretty          CLI output formatting.
      --max-parallel 1              Batch v1 is sequential only.
      --cache-policy <mode>         none | step | batch
      --snapshot-reuse <mode>       off | best_effort | strict
      --invalidate-on <actions>     Comma-separated mutating action names.
      --app <name>                  Set ambient app context for all steps.
      --pid <pid>                   Set ambient process context for all steps.
      --scope <scope>               Carry a shared UI search scope.
      --include-menus               Reuse menu-inclusive captures across steps.
      --launch-if-needed            Launch the ambient app if it is not running.
      --activate                    Activate the ambient app before batch steps.
      --adapter <name>              Select a specific search/capture adapter.
      --auto-trust                  Request local trusted-session bootstrap.
      --trusted-session-id <id>     Reuse an existing trusted session.
    """

    private static let mediaUsage = """
    wizmac media

    Usage:
      wizmac media screenshot --app "Safari" --path /tmp/s.png
      wizmac media record start --sessionID abc --codec h264 --fps 30
      wizmac media record status --sessionID abc
      wizmac media stream start --format mjpeg

    Commands:
      screenshot                    Capture a screenshot to a path.
      record start|stop|status      Control a recording session.
      stream start|stop|status      Control a streaming session.
    """

    private static let initUsage = """
    wizmac init

    Usage:
      wizmac init [--sample-batch-file wizmac.sample.wzb] [--fixture-smoke]

    Flags:
      --sample-batch-file <path>    Where to write the sample batch file.
      --force                       Overwrite the sample batch file if it exists.
      --fixture-smoke               Run a lightweight fixture search smoke flow.
      --fixture-app <name>          App to target for the fixture smoke flow.
      --fixture-query <query>       Query to use for the fixture smoke flow.
    """

    private static let setupUsage = """
    wizmac setup

    Usage:
      wizmac setup agents --all
      wizmac setup agents claude gemini codex openclaw
      wizmac setup agents --all --dry-run
      wizmac setup agents codex --workspace-root /path/to/repo

    Flags:
      --all                         Install/setup all supported agent targets.
      --dry-run                     Print the planned changes without writing files or running commands.
      --mcp-url <url>               Override the Wizmac MCP endpoint. Default: http://127.0.0.1:7877/mcp
      --workspace-root <path>       Workspace root used for repo-local AGENTS.md updates. Defaults to the nearest detected repo root.

    Targets:
      claude | claude-code
      gemini | gemini-cli
      codex
      openclaw | open-claw
    """
}

private struct CLIError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

private struct BatchCLIResult {
    var response: ControlPlaneActionResponse
    var prettyOutput: Bool
}

private struct BatchCommandOptions {
    var stepStrings: [String] = []
    var filePath: String?
    var inputFormat: BatchInputFormat?
    var outputFormat: BatchOutputFormat = .pretty
    var failFast: Bool = true
    var maxParallel: Int = 1
    var cachePolicy: String?
    var snapshotReuse: String?
    var invalidateOn: [String] = []
    var ambientArguments: [String: StructuredValue] = [:]
}

private struct BatchStepSpecification {
    var action: String
    var arguments: [String: StructuredValue]
}

private struct MediaLifecycleCommandResult {
    var arguments: [String: StructuredValue]
}

private struct InitCommandOptions {
    var sampleBatchPath: String = "wizmac.sample.wzb"
    var overwrite: Bool = false
    var fixtureSmokeEnabled: Bool = false
    var fixtureApp: String = "WizmacFixtureHost"
    var fixtureQuery: String = "Primary"
}

private struct AgentSetupCommandOptions {
    var includeAll = false
    var dryRun = false
    var mcpURL = "http://127.0.0.1:7877/mcp"
    var workspaceRoot = WizmacAgentSetupPlanner.suggestedWorkspaceRoot()
    var targets: [WizmacAgentSetupTarget] = []
}

private enum BatchInputFormat: String {
    case yaml
    case json
    case line
}

private enum BatchOutputFormat: String {
    case json
    case pretty
}

await WizmacCLI.main()
