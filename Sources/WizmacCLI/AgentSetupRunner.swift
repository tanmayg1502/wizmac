import Foundation

enum WizmacAgentSetupExecutionStatus: String, Codable, Equatable {
    case planned
    case applied
    case skipped
    case failed
}

struct WizmacAgentSetupStepResult: Codable, Equatable {
    var kind: String
    var label: String
    var status: WizmacAgentSetupExecutionStatus
    var detail: String?
}

struct WizmacAgentSetupExecutionResult: Codable, Equatable {
    var target: String
    var summary: String
    var status: WizmacAgentSetupExecutionStatus
    var steps: [WizmacAgentSetupStepResult]
    var notes: [String]
}

struct WizmacAgentSetupExecutionOptions {
    var dryRun: Bool = false
}

protocol WizmacShellRunning {
    func run(_ command: WizmacAgentSetupShellCommand) throws -> WizmacShellRunResult
}

struct WizmacShellRunResult {
    var status: Int32
    var stdout: String
    var stderr: String
}

struct ProcessShellRunner: WizmacShellRunning {
    func run(_ command: WizmacAgentSetupShellCommand) throws -> WizmacShellRunResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command.launchPath] + command.arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return WizmacShellRunResult(
            status: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }
}

struct WizmacAgentSetupExecutor {
    private let fileManager: FileManager
    private let shellRunner: any WizmacShellRunning
    private let homeDirectoryURL: URL

    init(
        fileManager: FileManager = .default,
        shellRunner: any WizmacShellRunning = ProcessShellRunner(),
        homeDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.shellRunner = shellRunner
        self.homeDirectoryURL = homeDirectoryURL ?? fileManager.homeDirectoryForCurrentUser
    }

    func execute(
        _ plan: WizmacAgentSetupPlan,
        options: WizmacAgentSetupExecutionOptions = .init()
    ) -> WizmacAgentSetupExecutionResult {
        var stepResults: [WizmacAgentSetupStepResult] = []
        var overallStatus: WizmacAgentSetupExecutionStatus = .applied

        for step in plan.steps {
            switch step {
            case let .note(note):
                stepResults.append(
                    WizmacAgentSetupStepResult(
                        kind: "note",
                        label: note,
                        status: options.dryRun ? .planned : .skipped,
                        detail: nil
                    )
                )
            case let .file(file):
                do {
                    let result = try apply(fileWrite: file, dryRun: options.dryRun)
                    stepResults.append(result)
                } catch {
                    overallStatus = .failed
                    stepResults.append(
                        WizmacAgentSetupStepResult(
                            kind: "file",
                            label: file.path,
                            status: .failed,
                            detail: error.localizedDescription
                        )
                    )
                }
            case let .shell(command):
                do {
                    let result = try run(command: command, dryRun: options.dryRun)
                    stepResults.append(result)
                    if result.status == .failed {
                        overallStatus = .failed
                    }
                } catch {
                    overallStatus = .failed
                    stepResults.append(
                        WizmacAgentSetupStepResult(
                            kind: "shell",
                            label: command.displayCommandLine,
                            status: .failed,
                            detail: error.localizedDescription
                        )
                    )
                }
            }
        }

        if overallStatus != .failed,
           stepResults.allSatisfy({ $0.status == .planned || $0.status == .skipped }) {
            overallStatus = options.dryRun ? .planned : .skipped
        }

        return WizmacAgentSetupExecutionResult(
            target: plan.target.rawValue,
            summary: plan.summary,
            status: overallStatus,
            steps: stepResults,
            notes: deduplicated(plan.target.recommendedVerificationNotes)
        )
    }

    private func apply(
        fileWrite: WizmacAgentSetupFileWrite,
        dryRun: Bool
    ) throws -> WizmacAgentSetupStepResult {
        let url = resolvePath(fileWrite.path)
        if dryRun {
            return WizmacAgentSetupStepResult(
                kind: "file",
                label: url.path,
                status: .planned,
                detail: "Would \(fileWrite.mode.rawValue) managed Wizmac instructions."
            )
        }

        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        switch fileWrite.mode {
        case .replace:
            try fileWrite.contents.write(to: url, atomically: true, encoding: .utf8)
            return WizmacAgentSetupStepResult(kind: "file", label: url.path, status: .applied, detail: "Wrote file.")
        case .create:
            if fileManager.fileExists(atPath: url.path) {
                return WizmacAgentSetupStepResult(kind: "file", label: url.path, status: .skipped, detail: "File already exists.")
            }
            try fileWrite.contents.write(to: url, atomically: true, encoding: .utf8)
            return WizmacAgentSetupStepResult(kind: "file", label: url.path, status: .applied, detail: "Created file.")
        case .append:
            let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let merged = mergeManagedContents(
                existing: existing,
                contents: fileWrite.contents,
                managedBlockID: fileWrite.managedBlockID
            )
            if merged == existing {
                return WizmacAgentSetupStepResult(kind: "file", label: url.path, status: .skipped, detail: "Managed block already up to date.")
            }
            try merged.write(to: url, atomically: true, encoding: .utf8)
            return WizmacAgentSetupStepResult(kind: "file", label: url.path, status: .applied, detail: "Updated managed block.")
        }
    }

    private func run(
        command: WizmacAgentSetupShellCommand,
        dryRun: Bool
    ) throws -> WizmacAgentSetupStepResult {
        if dryRun {
            return WizmacAgentSetupStepResult(
                kind: "shell",
                label: command.displayCommandLine,
                status: .planned,
                detail: command.purpose
            )
        }

        guard commandIsAvailable(command.launchPath) else {
            return WizmacAgentSetupStepResult(
                kind: "shell",
                label: command.displayCommandLine,
                status: .skipped,
                detail: "\(command.launchPath) is not installed on this machine."
            )
        }

        let result = try shellRunner.run(command)
        if result.status == 0 {
            return WizmacAgentSetupStepResult(
                kind: "shell",
                label: command.displayCommandLine,
                status: .applied,
                detail: command.purpose
            )
        }

        return WizmacAgentSetupStepResult(
            kind: "shell",
            label: command.displayCommandLine,
            status: .failed,
            detail: [
                "\(command.launchPath) exited with status \(result.status).",
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines),
            ]
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        )
    }

    private func resolvePath(_ rawPath: String) -> URL {
        if rawPath == "~" {
            return homeDirectoryURL
        }
        if rawPath.hasPrefix("~/") {
            return homeDirectoryURL.appendingPathComponent(String(rawPath.dropFirst(2)))
        }
        if rawPath.hasPrefix("/") {
            return URL(fileURLWithPath: rawPath)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(rawPath)
    }

    private func mergeManagedContents(
        existing: String,
        contents: String,
        managedBlockID: String?
    ) -> String {
        let trimmedContents = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let managedBlockID else {
            if existing.contains(trimmedContents) {
                return existing
            }
            if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return trimmedContents + "\n"
            }
            return existing.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + trimmedContents + "\n"
        }

        let startMarker = "<!-- WIZMAC:\(managedBlockID):BEGIN -->"
        let endMarker = "<!-- WIZMAC:\(managedBlockID):END -->"
        let block = "\(startMarker)\n\(trimmedContents)\n\(endMarker)"

        if let startRange = existing.range(of: startMarker),
           let endRange = existing.range(of: endMarker) {
            let range = startRange.lowerBound..<endRange.upperBound
            var merged = existing
            merged.replaceSubrange(range, with: block)
            return merged.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        }

        if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return block + "\n"
        }

        return existing.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + block + "\n"
    }

    private func commandIsAvailable(_ executable: String) -> Bool {
        if executable.contains("/") {
            return fileManager.isExecutableFile(atPath: executable)
        }

        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for directory in pathDirectories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(executable)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return true
            }
        }
        return false
    }

    private func deduplicated(_ notes: [String]) -> [String] {
        var seen = Set<String>()
        return notes.filter { note in
            seen.insert(note).inserted
        }
    }
}
