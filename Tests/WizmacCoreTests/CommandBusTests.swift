import Foundation
import XCTest
@testable import WizmacCore

final class CommandBusTests: XCTestCase {
    func testRiskyRequestQueuesApprovalAndWritesAuditEntryImmediately() async throws {
        let harness = try TestHarness()
        let request = ActionRequest(
            action: .uiAct,
            arguments: ["targetID": .string("button-1")],
            origin: RequestOrigin(kind: .cli)
        )

        let result = await harness.bus.dispatch(request)
        let auditEntries = try await harness.auditStore.recent(limit: 10)
        let pendingApprovals = await harness.bus.pendingApprovals()

        XCTAssertEqual(result.outcome, .confirmationRequired)
        XCTAssertEqual(pendingApprovals.count, 1)
        XCTAssertEqual(auditEntries.count, 1)
        XCTAssertEqual(auditEntries.first?.outcome, .confirmationRequired)
        XCTAssertTrue(auditEntries.first?.message.contains("Queued for approval") == true)
        let executedRequests = await harness.executor.executedRequests()
        XCTAssertTrue(executedRequests.isEmpty)
    }

    func testResolvingApprovedRequestExecutesAndAppendsSecondAuditEntry() async throws {
        let harness = try TestHarness()
        let request = ActionRequest(
            action: .remotePair,
            arguments: ["name": .string("Test Agent")],
            origin: RequestOrigin(kind: .mcp)
        )

        let queued = await harness.bus.dispatch(request)
        let approvalID = try XCTUnwrap(queued.payload?.objectValue?["approvalID"]?.stringValue)
        let approved = await harness.bus.resolveApproval(
            id: try XCTUnwrap(UUID(uuidString: approvalID)),
            decision: .approve
        )

        let auditEntries = try await harness.auditStore.recent(limit: 10)
        let executedRequests = await harness.executor.executedRequests()

        XCTAssertEqual(approved.outcome, ActionOutcome.success)
        XCTAssertEqual(executedRequests, [request])
        XCTAssertEqual(auditEntries.count, 2)
        XCTAssertEqual(auditEntries.first?.outcome, .confirmationRequired)
        XCTAssertEqual(auditEntries.last?.outcome, .success)
    }

    func testTrustedAutomationSessionBypassesApprovalForAllowedAction() async throws {
        let harness = try TestHarness()
        let trustedSession = await harness.trustedSessionStore.start(
            appName: "FixtureHost",
            bundleIdentifier: "com.example.fixture",
            processIdentifier: 42,
            allowedActions: [.uiAct]
        )
        let request = ActionRequest(
            action: .uiAct,
            arguments: [
                "targetID": .string("button-1"),
                "trustedSessionID": .string(trustedSession.id.uuidString),
            ],
            origin: RequestOrigin(kind: .cli)
        )

        let result = await harness.bus.dispatch(request)
        let executedRequests = await harness.executor.executedRequests()

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(executedRequests, [request])
    }
}

private struct TestHarness {
    let bus: CommandBus
    let auditStore: AuditStore
    let executor: RecordingExecutor
    let trustedSessionStore: TrustedAutomationSessionStore

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wizmac-core-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let settingsStore = try SettingsStore(url: directory.appendingPathComponent("settings.json"))
        self.auditStore = try AuditStore(url: directory.appendingPathComponent("audit.jsonl"))
        let approvalStore = try ApprovalStore(url: directory.appendingPathComponent("approvals.json"))
        self.executor = RecordingExecutor()
        self.trustedSessionStore = TrustedAutomationSessionStore()
        let policy = ApprovalPolicy(
            settingsStore: settingsStore,
            trustedSessionStore: trustedSessionStore
        )
        self.bus = CommandBus(
            executor: executor,
            auditStore: auditStore,
            approvalStore: approvalStore,
            approvalPolicy: policy
        )
    }
}

private actor RecordingExecutor: ActionExecutor {
    private var requests: [ActionRequest] = []

    func execute(_ request: ActionRequest) async -> ActionResult {
        requests.append(request)
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Executed \(request.action.rawValue)."
        )
    }

    func executedRequests() -> [ActionRequest] {
        requests
    }
}
