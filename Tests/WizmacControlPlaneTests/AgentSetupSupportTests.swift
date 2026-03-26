import Foundation
import XCTest

final class AgentSetupSupportTests: XCTestCase {
    func testPlannerCoversAllTargetsWithExpectedRegistrationAndMemoryFiles() throws {
        let snapshots = try runPlannerHarness()

        let claude = try XCTUnwrap(snapshots.first(where: { $0.target == "claudeCode" }))
        let gemini = try XCTUnwrap(snapshots.first(where: { $0.target == "geminiCLI" }))
        let codex = try XCTUnwrap(snapshots.first(where: { $0.target == "codex" }))
        let openClaw = try XCTUnwrap(snapshots.first(where: { $0.target == "openClaw" }))

        XCTAssertTrue(claude.commandLines.contains { $0.contains("claude mcp add --transport http wizmac http://127.0.0.1:7877/mcp --scope user") })
        XCTAssertTrue(claude.filePaths.contains("~/.claude/CLAUDE.md"))
        XCTAssertTrue(claude.fileModes.contains("append"))
        XCTAssertTrue(claude.managedBlockIDs.contains("claude_memory"))
        XCTAssertTrue(claude.notes.contains { $0.contains("claude mcp list") })

        XCTAssertTrue(gemini.filePaths.contains("~/.gemini/GEMINI.md"))
        XCTAssertTrue(gemini.commandLines.contains { $0.contains("gemini mcp add --transport http --scope user wizmac http://127.0.0.1:7877/mcp") })
        XCTAssertTrue(gemini.fileModes.contains("append"))
        XCTAssertTrue(gemini.managedBlockIDs.contains("gemini_memory"))
        XCTAssertTrue(gemini.notes.contains { $0.contains("gemini mcp list") })

        XCTAssertTrue(codex.commandLines.contains { $0.contains("codex mcp add wizmac --url http://127.0.0.1:7877/mcp") })
        XCTAssertTrue(codex.filePaths.contains(where: { $0.hasSuffix("/AGENTS.md") }))
        XCTAssertTrue(codex.managedBlockIDs.contains("codex_agents"))
        XCTAssertTrue(codex.notes.contains { $0.contains("codex mcp list") })

        XCTAssertTrue(openClaw.filePaths.contains("~/.openclaw/skills/wizmac/SKILL.md"))
        XCTAssertTrue(openClaw.fileModes.contains("create"))
        XCTAssertTrue(openClaw.notes.contains { $0.contains("OpenClaw") })
    }

    func testRenderedPlanPreviewIncludesTargetSummaryAndCommands() throws {
        let snapshots = try runPlannerHarness()
        let preview = snapshots.map(\.bulletList).joined(separator: "\n\n")

        XCTAssertTrue(preview.contains("Claude Code"))
        XCTAssertTrue(preview.contains("Gemini CLI"))
        XCTAssertTrue(preview.contains("Codex"))
        XCTAssertTrue(preview.contains("OpenClaw"))
        XCTAssertTrue(preview.contains("http://127.0.0.1:7877/mcp"))
    }

    func testShellPreviewQuotesUnsafeArgumentsAndWorkspaceRootDetectionUsesNearestRepoRoot() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repositoryRoot = temporaryDirectory.appendingPathComponent("repo", isDirectory: true)
        let nestedDirectory = repositoryRoot.appendingPathComponent("Sources/WizmacCLI", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try Data().write(to: repositoryRoot.appendingPathComponent("Package.swift"))

        let snapshots = try runPlannerHarness(
            workspaceRoot: nestedDirectory,
            serverURL: "http://127.0.0.1:7877/mcp?channel=codex&target=window|clipboard"
        )
        let codex = try XCTUnwrap(snapshots.first(where: { $0.target == "codex" }))
        let claude = try XCTUnwrap(snapshots.first(where: { $0.target == "claudeCode" }))

        XCTAssertTrue(codex.filePaths.contains(repositoryRoot.appendingPathComponent("AGENTS.md").path))
        XCTAssertTrue(claude.commandLines.contains { $0.contains("'http://127.0.0.1:7877/mcp?channel=codex&target=window|clipboard'") })
    }

    func testCodexPlanSkipsRepoSnippetWhenNoWorkspaceRootIsDetected() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let snapshots = try runPlannerHarness(workspaceRoot: temporaryDirectory)
        let codex = try XCTUnwrap(snapshots.first(where: { $0.target == "codex" }))

        XCTAssertFalse(codex.filePaths.contains(where: { $0.hasSuffix("/AGENTS.md") }))
        XCTAssertTrue(codex.notes.contains { $0.contains("--workspace-root") })
    }
}

private extension AgentSetupSupportTests {
    struct PlanSnapshot: Codable {
        let target: String
        let summary: String
        let filePaths: [String]
        let fileModes: [String]
        let managedBlockIDs: [String]
        let commandLines: [String]
        let notes: [String]
        let bulletList: String
    }

    func runPlannerHarness(
        workspaceRoot: URL? = nil,
        serverURL: String = "http://127.0.0.1:7877/mcp"
    ) throws -> [PlanSnapshot] {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let executableURL = temporaryDirectory.appendingPathComponent("agent-setup-harness")
        let harnessURL = temporaryDirectory.appendingPathComponent("Harness.swift")
        let workspaceRootLiteral = swiftStringLiteral(workspaceRoot?.path ?? "")
        let serverURLLiteral = swiftStringLiteral(serverURL)

        let harnessSource = """
        import Foundation

        struct Snapshot: Codable {
            var target: String
            var summary: String
            var filePaths: [String]
            var fileModes: [String]
            var managedBlockIDs: [String]
            var commandLines: [String]
            var notes: [String]
            var bulletList: String
        }

        @main
        struct Harness {
            static func main() throws {
                let server = WizmacAgentSetupServerReference(mcpURL: "\(serverURLLiteral)")
                let requestedRoot = "\(workspaceRootLiteral)"
                let workspaceProbe = requestedRoot.isEmpty
                    ? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    : URL(fileURLWithPath: requestedRoot)
                let workspaceRoot = WizmacAgentSetupPlanner.suggestedWorkspaceRoot(startingAt: workspaceProbe)

                let snapshots = WizmacAgentSetupTarget.allCases.map { target -> Snapshot in
                    let plan = WizmacAgentSetupPlanner.plan(
                        for: target,
                        server: server,
                        workspaceRoot: workspaceRoot
                    )
                    return Snapshot(
                        target: target.rawValue,
                        summary: plan.summary,
                        filePaths: plan.fileWrites.map(\\.path),
                        fileModes: plan.fileWrites.map { $0.mode.rawValue },
                        managedBlockIDs: plan.fileWrites.compactMap(\\.managedBlockID),
                        commandLines: plan.shellCommands.map(\\.displayCommandLine),
                        notes: plan.notes,
                        bulletList: plan.renderedBulletList()
                    )
                }

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(snapshots)
                FileHandle.standardOutput.write(data)
            }
        }
        """
        try harnessSource.write(to: harnessURL, atomically: true, encoding: .utf8)

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swiftc",
            "-o",
            executableURL.path,
            sourcePath("Sources/WizmacCLI/AgentSetupSupport.swift"),
            sourcePath("Sources/WizmacCLI/AgentSetupReferences.swift"),
            harnessURL.path,
        ]
        process.currentDirectoryURL = packageRootURL
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stdout = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stderr = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let message = [stdout, stderr].filter { $0.isEmpty == false }.joined(separator: "\n")
            XCTFail(message)
            throw HarnessError(message: "Planner harness compilation failed.")
        }

        let runProcess = Process()
        let runOutput = Pipe()
        let runError = Pipe()
        runProcess.executableURL = executableURL
        runProcess.currentDirectoryURL = packageRootURL
        runProcess.standardOutput = runOutput
        runProcess.standardError = runError

        try runProcess.run()
        runProcess.waitUntilExit()

        guard runProcess.terminationStatus == 0 else {
            let stdout = String(decoding: runOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stderr = String(decoding: runError.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let message = [stdout, stderr].filter { $0.isEmpty == false }.joined(separator: "\n")
            XCTFail(message)
            throw HarnessError(message: "Planner harness execution failed.")
        }

        let data = runOutput.fileHandleForReading.readDataToEndOfFile()
        return try JSONDecoder().decode([PlanSnapshot].self, from: data)
    }

    func sourcePath(_ relativePath: String) -> String {
        packageRootURL.appendingPathComponent(relativePath).path
    }

    func swiftStringLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    var packageRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct HarnessError: Error {
    var message: String
}
