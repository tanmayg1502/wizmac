import Foundation

public struct WizmacAgentSetupServerReference: Sendable, Codable, Equatable {
    public var mcpURL: String
    public var launchPath: String
    public var arguments: [String]

    public init(
        mcpURL: String = "http://127.0.0.1:7877/mcp",
        launchPath: String = "wizmac",
        arguments: [String] = ["mcp"]
    ) {
        self.mcpURL = mcpURL
        self.launchPath = launchPath
        self.arguments = arguments
    }
}

public enum WizmacAgentSetupTarget: String, CaseIterable, Sendable, Codable {
    case claudeCode
    case geminiCLI
    case codex
    case openClaw

    public var displayName: String {
        switch self {
        case .claudeCode:
            return "Claude Code"
        case .geminiCLI:
            return "Gemini CLI"
        case .codex:
            return "Codex"
        case .openClaw:
            return "OpenClaw"
        }
    }

    public var summary: String {
        switch self {
        case .claudeCode:
            return "Register Wizmac as a user-scoped Claude Code MCP server and seed user memory."
        case .geminiCLI:
            return "Register Wizmac in user-scoped Gemini CLI config and seed global Gemini context."
        case .codex:
            return "Register Wizmac in Codex config and optionally add a repo AGENTS snippet."
        case .openClaw:
            return "Install a shared OpenClaw skill that teaches the agent to use Wizmac."
        }
    }
}

public enum WizmacAgentSetupWriteMode: String, Sendable, Codable {
    case create
    case append
    case replace
}

public struct WizmacAgentSetupFileWrite: Sendable, Codable, Equatable {
    public var path: String
    public var contents: String
    public var mode: WizmacAgentSetupWriteMode
    public var managedBlockID: String?

    public init(
        path: String,
        contents: String,
        mode: WizmacAgentSetupWriteMode,
        managedBlockID: String? = nil
    ) {
        self.path = path
        self.contents = contents
        self.mode = mode
        self.managedBlockID = managedBlockID
    }
}

public struct WizmacAgentSetupShellCommand: Sendable, Codable, Equatable {
    public var launchPath: String
    public var arguments: [String]
    public var purpose: String

    public init(launchPath: String, arguments: [String], purpose: String) {
        self.launchPath = launchPath
        self.arguments = arguments
        self.purpose = purpose
    }

    public var displayCommandLine: String {
        ([launchPath] + arguments).map(Self.shellQuote).joined(separator: " ")
    }

    private static func shellQuote(_ raw: String) -> String {
        guard raw.isEmpty == false else { return "''" }
        let safeCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@%_+=:,./-"))
        if raw.rangeOfCharacter(from: safeCharacters.inverted) == nil {
            return raw
        }
        return "'" + raw.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

public enum WizmacAgentSetupStep: Sendable, Codable, Equatable {
    case shell(WizmacAgentSetupShellCommand)
    case file(WizmacAgentSetupFileWrite)
    case note(String)
}

public struct WizmacAgentSetupPlan: Sendable, Codable, Equatable {
    public var target: WizmacAgentSetupTarget
    public var summary: String
    public var steps: [WizmacAgentSetupStep]

    public init(target: WizmacAgentSetupTarget, summary: String, steps: [WizmacAgentSetupStep]) {
        self.target = target
        self.summary = summary
        self.steps = steps
    }

    public var shellCommands: [WizmacAgentSetupShellCommand] {
        steps.compactMap { step in
            guard case let .shell(command) = step else { return nil }
            return command
        }
    }

    public var fileWrites: [WizmacAgentSetupFileWrite] {
        steps.compactMap { step in
            guard case let .file(file) = step else { return nil }
            return file
        }
    }

    public var notes: [String] {
        steps.compactMap { step in
            guard case let .note(note) = step else { return nil }
            return note
        }
    }

    public func renderedBulletList() -> String {
        var lines = [
            "\(target.displayName): \(summary)",
        ]

        for step in steps {
            switch step {
            case let .shell(command):
                lines.append("  shell: \(command.displayCommandLine)")
            case let .file(file):
                lines.append("  file: \(file.path) [\(file.mode.rawValue)]")
            case let .note(note):
                lines.append("  note: \(note)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

public enum WizmacAgentSetupPlanner {
    public static func plan(
        for target: WizmacAgentSetupTarget,
        server: WizmacAgentSetupServerReference = .init(),
        workspaceRoot: URL? = nil
    ) -> WizmacAgentSetupPlan {
        switch target {
        case .claudeCode:
            return claudeCodePlan(server: server)
        case .geminiCLI:
            return geminiCLIPlan(server: server)
        case .codex:
            return codexPlan(server: server, workspaceRoot: workspaceRoot)
        case .openClaw:
            return openClawPlan(server: server)
        }
    }

    public static func suggestedWorkspaceRoot(
        startingAt location: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> URL? {
        let fileManager = FileManager.default
        var candidate = location.standardizedFileURL
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue == false {
            candidate.deleteLastPathComponent()
        }

        while true {
            if fileManager.fileExists(atPath: candidate.appendingPathComponent("AGENTS.md").path) ||
                fileManager.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path) ||
                fileManager.fileExists(atPath: candidate.appendingPathComponent(".git").path)
            {
                return candidate
            }

            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                return nil
            }
            candidate = parent
        }
    }

    private static func claudeCodePlan(server: WizmacAgentSetupServerReference) -> WizmacAgentSetupPlan {
        WizmacAgentSetupPlan(
            target: .claudeCode,
            summary: "Register Wizmac as a user-scoped HTTP MCP server for Claude Code and seed `~/.claude/CLAUDE.md`.",
            steps: [
                .file(
                    WizmacAgentSetupFileWrite(
                        path: "~/.claude/CLAUDE.md",
                        contents: """
                        ## Wizmac

                        When a task requires interacting with the user's local Mac UI, windows, clipboard, focused text, or media, use the `wizmac` MCP server first.
                        Prefer read-only inspection tools before state-changing tools, and respect Wizmac approval requests.
                        """,
                        mode: .append,
                        managedBlockID: "claude_memory"
                    )
                ),
                .shell(
                    WizmacAgentSetupShellCommand(
                        launchPath: "claude",
                        arguments: [
                            "mcp",
                            "add",
                            "--transport",
                            "http",
                            "wizmac",
                            server.mcpURL,
                            "--scope",
                            "user",
                        ],
                        purpose: "Register Wizmac as a user-scoped Claude Code MCP server."
                    )
                ),
                .note("Verify with `claude mcp get wizmac` or `claude mcp list`."),
            ]
        )
    }

    private static func geminiCLIPlan(server: WizmacAgentSetupServerReference) -> WizmacAgentSetupPlan {
        WizmacAgentSetupPlan(
            target: .geminiCLI,
            summary: "Register Wizmac as a user-scoped HTTP MCP server for Gemini CLI and seed `~/.gemini/GEMINI.md`.",
            steps: [
                .file(
                    WizmacAgentSetupFileWrite(
                        path: "~/.gemini/GEMINI.md",
                        contents: """
                        ## Wizmac

                        When a task requires interacting with the user's local Mac UI, windows, clipboard, focused text, or media, use the `wizmac` MCP server first.
                        Prefer read-only inspection tools before state-changing tools, and respect Wizmac approval requests.
                        """,
                        mode: .append,
                        managedBlockID: "gemini_memory"
                    )
                ),
                .shell(
                    WizmacAgentSetupShellCommand(
                        launchPath: "gemini",
                        arguments: [
                            "mcp",
                            "add",
                            "--transport",
                            "http",
                            "--scope",
                            "user",
                            "wizmac",
                            server.mcpURL,
                        ],
                        purpose: "Register Wizmac as a user-scoped Gemini CLI MCP server."
                    )
                ),
                .note("Verify with `gemini mcp list`."),
            ]
        )
    }

    private static func codexPlan(
        server: WizmacAgentSetupServerReference,
        workspaceRoot: URL?
    ) -> WizmacAgentSetupPlan {
        var steps: [WizmacAgentSetupStep] = [
            .shell(
                WizmacAgentSetupShellCommand(
                    launchPath: "codex",
                    arguments: [
                        "mcp",
                        "add",
                        "wizmac",
                        "--url",
                        server.mcpURL,
                    ],
                    purpose: "Register Wizmac as a Codex MCP server."
                )
            ),
        ]

        if let workspaceRoot {
            steps.append(
                .file(
                    WizmacAgentSetupFileWrite(
                        path: workspaceRoot.appendingPathComponent("AGENTS.md").path,
                        contents: """
                        ## Wizmac

                        When a task requires interacting with the user's local Mac UI, windows, clipboard, focused text, or media, use the `wizmac` MCP server first.
                        Prefer read-only inspection tools before state-changing tools, and respect Wizmac approval requests.
                        """,
                        mode: .append,
                        managedBlockID: "codex_agents"
                    )
                )
            )
        } else {
            steps.append(.note("Pass `--workspace-root /path/to/repo` if you want Wizmac to seed a repo-local `AGENTS.md` snippet for Codex."))
        }

        steps.append(.note("Verify with `codex mcp list`."))

        return WizmacAgentSetupPlan(
            target: .codex,
            summary: workspaceRoot == nil
                ? "Register Wizmac in Codex and optionally seed a repo-level `AGENTS.md` snippet when you pass a workspace root."
                : "Register Wizmac in Codex and seed a repo-level `AGENTS.md` snippet for the detected workspace.",
            steps: steps
        )
    }

    private static func openClawPlan(server: WizmacAgentSetupServerReference) -> WizmacAgentSetupPlan {
        let skillContents = """
        ---
        name: wizmac
        description: Use when you need to inspect or control the local Mac UI, windows, clipboard, focused text, or media through Wizmac.
        ---

        # Wizmac

        Use Wizmac whenever a task requires interacting with the local Mac UI, windows, clipboard, focused text, or media.
        Prefer the shared Wizmac MCP server at \(server.mcpURL) when the runtime can connect to MCP.
        If MCP is unavailable, fall back to the `\(server.launchPath) \(server.arguments.joined(separator: " "))` CLI entrypoint.
        Prefer read-only inspection tools before state-changing tools, and respect Wizmac approval requests.
        """

        return WizmacAgentSetupPlan(
            target: .openClaw,
            summary: "Install a shared OpenClaw skill in `~/.openclaw/skills/wizmac`.",
            steps: [
                .file(
                    WizmacAgentSetupFileWrite(
                        path: "~/.openclaw/skills/wizmac/SKILL.md",
                        contents: skillContents,
                        mode: .create
                    )
                ),
                .note("OpenClaw loads shared skills from `~/.openclaw/skills`; restart or refresh skills after installation."),
                .note("If `~/.openclaw/skills/wizmac/SKILL.md` already exists, Wizmac leaves it in place so custom edits are not overwritten."),
            ]
        )
    }
}
