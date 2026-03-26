import Foundation
import XCTest
@testable import WizmacControlPlane

final class CLITimingTests: XCTestCase {
    func testTimingFlagsRoundTripThroughCallSyntax() throws {
        let sample = try runCLI(
            arguments: [
                "call",
                "ui.act",
                "query=Primary",
                "--pre-delay-ms",
                "17",
                "--post-delay-ms",
                "29",
                "--timeout-ms",
                "41",
            ],
            fixture: fixtureConfiguration(delayMs: 15, toolNames: ["ui.act"])
        )
        let response = try decode(sample.standardOutput, as: ControlPlaneActionResponse.self)

        XCTAssertEqual(sample.terminationStatus, 0, sample.combinedOutput)
        XCTAssertEqual(response.status, .success)
        XCTAssertGreaterThan(sample.durationMs, 0, sample.combinedOutput)
    }

    func testTimingFlagsRoundTripThroughNamespacedSyntax() throws {
        let sample = try runCLI(
            arguments: [
                "ui",
                "act",
                "--query",
                "Primary",
                "--pre-delay-ms",
                "17",
                "--post-delay-ms",
                "29",
                "--timeout-ms",
                "41",
            ],
            fixture: fixtureConfiguration(delayMs: 15, toolNames: ["ui.act"])
        )
        let response = try decode(sample.standardOutput, as: ControlPlaneActionResponse.self)

        XCTAssertEqual(sample.terminationStatus, 0, sample.combinedOutput)
        XCTAssertEqual(response.status, .success)
        XCTAssertGreaterThan(sample.durationMs, 0, sample.combinedOutput)
    }

    func testKeyCommandFamilyDispatchesCanonicalToolNames() throws {
        let comboSample = try runCLI(
            arguments: ["key", "combo", "--mods", "cmd,shift", "--key", "z"],
            fixture: fixtureConfiguration(delayMs: 10, toolNames: ["input.key_combo"])
        )
        let sequenceSample = try runCLI(
            arguments: ["key", "sequence", "cmd+a,delete,cmd+v"],
            fixture: fixtureConfiguration(delayMs: 10, toolNames: ["input.key_sequence"])
        )
        let typeSample = try runCLI(
            arguments: ["key", "type", "hello"],
            fixture: fixtureConfiguration(delayMs: 10, toolNames: ["text.insert"])
        )

        XCTAssertEqual(try decode(comboSample.standardOutput, as: ControlPlaneActionResponse.self).status, .success)
        XCTAssertEqual(try decode(sequenceSample.standardOutput, as: ControlPlaneActionResponse.self).status, .success)
        XCTAssertEqual(try decode(typeSample.standardOutput, as: ControlPlaneActionResponse.self).status, .success)
    }

    func testConcreteRegisteredToolCallsEmitLatencySamples() throws {
        let excludedSyntheticTools = Set([
            "batch.run",
            "wait.ui.exists",
            "wait.window.focused",
            "wait.condition",
        ])
        let toolNames = ControlPlaneToolRegistry.default.allTools()
            .map(\.name)
            .filter { excludedSyntheticTools.contains($0) == false }
        let fixture = fixtureConfiguration(delayMs: 12, toolNames: toolNames)

        var reportLines: [String] = []
        for toolName in toolNames {
            let sample = try runCLI(arguments: ["call", toolName], fixture: fixture)
            let response = try decode(sample.standardOutput, as: ControlPlaneActionResponse.self)

            XCTAssertEqual(sample.terminationStatus, 0, sample.combinedOutput)
            XCTAssertEqual(response.status, .success)
            XCTAssertGreaterThan(sample.durationMs, 0, sample.combinedOutput)
            reportLines.append("\(toolName): \(sample.formattedDuration)")
        }

        print("CLI latency samples by tool:\n" + reportLines.joined(separator: "\n"))
    }

    func testBatchAndWaitToolCallsEmitLatencySamples() throws {
        let fixture = fixtureConfiguration(
            delayMs: 12,
            toolResponses: [
                "ui.search": FixtureToolResponse(
                    delayMs: 12,
                    response: ControlPlaneActionResponse(
                        status: .success,
                        payload: .object([
                            "tool": .string("ui.search"),
                            "targets": .array([
                                .object([
                                    "id": .string("button-1"),
                                    "title": .string("Primary Action"),
                                ]),
                            ]),
                        ]),
                        message: "Fixture response."
                    )
                ),
                "window.list": FixtureToolResponse(
                    delayMs: 12,
                    response: ControlPlaneActionResponse(
                        status: .success,
                        payload: .array([
                            .object([
                                "id": .number(1),
                                "title": .string("Fixture Primary"),
                                "appName": .string("WizmacFixtureHost"),
                                "pid": .number(4242),
                            ]),
                        ]),
                        message: "Fixture response."
                    )
                ),
            ]
        )

        let batchSample = try runCLI(
            arguments: [
                "batch",
                "--step",
                "ui.search query=Primary",
                "--step",
                "wait.ui.exists query=Primary timeoutMs=250 intervalMs=20",
                "--cache-policy",
                "step",
                "--snapshot-reuse",
                "best-effort",
                "--invalidate-on",
                "ui.act,ui.gesture",
            ],
            fixture: fixture
        )
        let waitWindowSample = try runCLI(
            arguments: [
                "call",
                "wait.window.focused",
                "query=Fixture",
                "timeoutMs=250",
                "intervalMs=20",
            ],
            fixture: fixture
        )
        let waitConditionSample = try runCLI(
            arguments: [
                "call",
                "wait.condition",
                "predicate=ui.exists",
                "query=Primary",
                "timeoutMs=250",
                "intervalMs=20",
            ],
            fixture: fixture
        )

        let batchResponse = try decode(batchSample.standardOutput, as: ControlPlaneActionResponse.self)
        let waitWindowResponse = try decode(waitWindowSample.standardOutput, as: ControlPlaneActionResponse.self)
        let waitConditionResponse = try decode(waitConditionSample.standardOutput, as: ControlPlaneActionResponse.self)

        XCTAssertEqual(batchSample.terminationStatus, 0, batchSample.combinedOutput)
        XCTAssertEqual(waitWindowSample.terminationStatus, 0, waitWindowSample.combinedOutput)
        XCTAssertEqual(waitConditionSample.terminationStatus, 0, waitConditionSample.combinedOutput)
        XCTAssertEqual(batchResponse.status, .success)
        XCTAssertEqual(batchResponse.payload?["cachePolicy"]?.stringValue, "step")
        XCTAssertEqual(batchResponse.payload?["snapshotReuse"]?.stringValue, "best_effort")
        XCTAssertEqual(batchResponse.payload?["stepCount"]?.intValue, 2)
        XCTAssertEqual(waitWindowResponse.status, .success)
        XCTAssertEqual(waitConditionResponse.status, .success)
    }

    func testInitBootstrapWritesSampleBatchAndReadinessSummary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let batchPath = directory.appendingPathComponent("wizmac.sample.wzb")
        let fixture = fixtureConfiguration(
            delayMs: 8,
            toolResponses: [
                "system.health": FixtureToolResponse(
                    delayMs: 8,
                    response: ControlPlaneActionResponse(
                        status: .success,
                        payload: .object([:]),
                        message: "Shared service is reachable."
                    )
                ),
                "system.permissions": FixtureToolResponse(
                    delayMs: 8,
                    response: ControlPlaneActionResponse(
                        status: .success,
                        payload: .array([
                            .object([
                                "name": .string("accessibility"),
                                "state": .string("available"),
                                "detail": .string("Accessibility access is available."),
                            ]),
                            .object([
                                "name": .string("screen_recording"),
                                "state": .string("permissionRequired"),
                                "detail": .string("Screen recording access improves window and non-AX inspection."),
                            ]),
                        ]),
                        message: "Permissions checked."
                    )
                ),
                "remote.clients": FixtureToolResponse(
                    delayMs: 8,
                    response: ControlPlaneActionResponse(
                        status: .success,
                        payload: .array([]),
                        message: "No paired clients."
                    )
                ),
            ]
        )

        let sample = try runCLI(
            arguments: [
                "init",
                "--sample-batch-file",
                batchPath.path,
            ],
            fixture: fixture
        )

        let stdout = String(decoding: sample.standardOutput, as: UTF8.self)
        let batchContents = try String(contentsOf: batchPath, encoding: .utf8)

        XCTAssertEqual(sample.terminationStatus, 0, sample.combinedOutput)
        XCTAssertTrue(FileManager.default.fileExists(atPath: batchPath.path))
        XCTAssertTrue(stdout.contains("Service is healthy."))
        XCTAssertTrue(stdout.contains("Missing or incomplete permissions: screen_recording"))
        XCTAssertTrue(stdout.contains("wizmac remote pair --name"))
        XCTAssertTrue(batchContents.contains("wait.ui.exists"))
    }

    func testCallSyntaxMeasuresEndToEndLatency() throws {
        let expectedDelayMs = 40.0
        let sample = try runCLI(
            arguments: ["call", "ui.search", "query=Primary"],
            fixture: fixtureConfiguration(delayMs: expectedDelayMs, toolNames: ["ui.search"])
        )
        let response = try decode(sample.standardOutput, as: ControlPlaneActionResponse.self)

        XCTAssertEqual(sample.terminationStatus, 0, sample.combinedOutput)
        XCTAssertEqual(response.status, .success)
        XCTAssertGreaterThanOrEqual(sample.durationMs, expectedDelayMs * 0.6, sample.combinedOutput)
        print("CLI latency [call ui.search]: \(sample.formattedDuration)")
    }

    func testNamespacedSyntaxMeasuresEndToEndLatency() throws {
        let expectedDelayMs = 55.0
        let sample = try runCLI(
            arguments: ["ui", "search", "query=Primary"],
            fixture: fixtureConfiguration(delayMs: expectedDelayMs, toolNames: ["ui.search"])
        )
        let response = try decode(sample.standardOutput, as: ControlPlaneActionResponse.self)

        XCTAssertEqual(sample.terminationStatus, 0, sample.combinedOutput)
        XCTAssertEqual(response.status, .success)
        XCTAssertGreaterThanOrEqual(sample.durationMs, expectedDelayMs * 0.6, sample.combinedOutput)
        print("CLI latency [ui search]: \(sample.formattedDuration)")
    }

    func testJSONRPCToolCallMeasuresEndToEndLatency() throws {
        let expectedDelayMs = 70.0
        let request = JSONRPCRequest(
            id: .string("latency"),
            method: "tools/call",
            params: .object([
                "name": .string("ui.search"),
                "arguments": .object(["query": .string("Primary")]),
            ])
        )
        let requestData = try JSONEncoder().encode(request)
        let requestString = try XCTUnwrap(String(data: requestData, encoding: .utf8))
        let sample = try runCLI(
            arguments: ["json", requestString],
            fixture: fixtureConfiguration(delayMs: expectedDelayMs, toolNames: ["ui.search"])
        )
        let response = try decode(sample.standardOutput, as: JSONRPCResponse.self)

        XCTAssertEqual(sample.terminationStatus, 0, sample.combinedOutput)
        XCTAssertNil(response.error)
        XCTAssertEqual(
            response.result?["structuredContent"]?["status"]?.stringValue,
            ControlPlaneStatus.success.rawValue
        )
        XCTAssertGreaterThanOrEqual(sample.durationMs, expectedDelayMs * 0.6, sample.combinedOutput)
        print("CLI latency [json tools/call]: \(sample.formattedDuration)")
    }
}

private extension CLITimingTests {
    struct CLISample {
        let terminationStatus: Int32
        let standardOutput: Data
        let standardError: Data
        let durationMs: Double

        var combinedOutput: String {
            let stdout = String(decoding: standardOutput, as: UTF8.self)
            let stderr = String(decoding: standardError, as: UTF8.self)
            return [stdout, stderr]
                .filter { $0.isEmpty == false }
                .joined(separator: "\n")
        }

        var formattedDuration: String {
            String(format: "%.2f ms", durationMs)
        }
    }

    func runCLI(
        arguments: [String],
        fixture: FixtureControlPlaneEnvironmentConfiguration
    ) throws -> CLISample {
        let executableURL = try ensureCLIBinary()
        let stdout = Pipe()
        let stderr = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = packageRootURL
        process.standardOutput = stdout
        process.standardError = stderr

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        var environment = ProcessInfo.processInfo.environment
        environment[ControlPlaneEnvironment.fixtureEnvironmentKey] = try XCTUnwrap(
            String(data: encoder.encode(fixture), encoding: .utf8)
        )
        process.environment = environment

        let clock = ContinuousClock()
        let startedAt = clock.now
        try process.run()
        process.waitUntilExit()
        let elapsed = startedAt.duration(to: clock.now).magnitudeMs

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        return CLISample(
            terminationStatus: process.terminationStatus,
            standardOutput: stdoutData,
            standardError: stderrData,
            durationMs: elapsed
        )
    }

    func fixtureConfiguration(
        delayMs: Double,
        toolNames: [String]
    ) -> FixtureControlPlaneEnvironmentConfiguration {
        fixtureConfiguration(
            delayMs: delayMs,
            toolResponses: Dictionary(uniqueKeysWithValues: toolNames.map { toolName in
                (
                    toolName,
                    FixtureToolResponse(
                        delayMs: delayMs,
                        response: ControlPlaneActionResponse(
                            status: .success,
                            payload: .object([
                                "tool": .string(toolName),
                                "targets": .array([
                                    .object([
                                        "id": .string("button-1"),
                                        "title": .string("Primary Action"),
                                    ]),
                                ]),
                            ]),
                            message: "Fixture response."
                        )
                    )
                )
            })
        )
    }

    func fixtureConfiguration(
        delayMs: Double,
        toolResponses: [String: FixtureToolResponse]
    ) -> FixtureControlPlaneEnvironmentConfiguration {
        FixtureControlPlaneEnvironmentConfiguration(
            defaultDelayMs: nil,
            toolResponses: toolResponses
        )
    }

    func ensureCLIBinary() throws -> URL {
        let candidates = [
            packageRootURL.appendingPathComponent(".build/debug/wizmac"),
            packageRootURL.appendingPathComponent(".build/arm64-apple-macosx/debug/wizmac"),
        ]

        if let existing = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return existing
        }

        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "build", "--product", "wizmac"]
        process.currentDirectoryURL = packageRootURL
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTFail(text)
            throw CLIHarnessError("Failed to build wizmac for CLI timing tests.")
        }

        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw CLIHarnessError("Unable to locate the wizmac executable after building.")
        }
        return executable
    }

    func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    var packageRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct CLIHarnessError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

private extension Duration {
    var magnitudeMs: Double {
        let parts = self.components
        let seconds = Double(parts.seconds) * 1_000
        let attoseconds = Double(parts.attoseconds) / 1_000_000_000_000_000
        return seconds + attoseconds
    }
}
