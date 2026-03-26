import Foundation

public extension WizmacAgentSetupTarget {
    var documentationURLs: [URL] {
        switch self {
        case .claudeCode:
            return [
                URL(string: "https://docs.anthropic.com/en/docs/claude-code/mcp")!,
                URL(string: "https://docs.anthropic.com/en/docs/claude-code/memory")!,
            ]
        case .geminiCLI:
            return [
                URL(string: "https://geminicli.com/docs/tools/mcp-server/")!,
                URL(string: "https://geminicli.com/docs/cli/tutorials/memory-management/")!,
            ]
        case .codex:
            return [
                URL(string: "https://platform.openai.com/docs/docs-mcp")!,
            ]
        case .openClaw:
            return [
                URL(string: "https://docs.openclaw.ai/tools/skills")!,
                URL(string: "https://docs.openclaw.ai/tools/acp-agents")!,
            ]
        }
    }

    var recommendedVerificationNotes: [String] {
        switch self {
        case .claudeCode:
            return [
                "Verify the server with `claude mcp get wizmac` or `claude mcp list`.",
            ]
        case .geminiCLI:
            return [
                "Verify the server with `gemini mcp list`.",
            ]
        case .codex:
            return [
                "Use `codex mcp list` to confirm the server is registered.",
                "Pass `--workspace-root` if you also want Wizmac to update a repo-local `AGENTS.md` file.",
            ]
        case .openClaw:
            return [
                "Restart or refresh OpenClaw after installing the shared skill at `~/.openclaw/skills/wizmac/SKILL.md`.",
            ]
        }
    }
}
