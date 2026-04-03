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
        let executedRequests = await harness.recorder.executedRequests()

        XCTAssertEqual(result.outcome, .confirmationRequired)
        XCTAssertEqual(pendingApprovals.count, 1)
        XCTAssertEqual(auditEntries.count, 1)
        XCTAssertEqual(auditEntries.first?.outcome, .confirmationRequired)
        XCTAssertTrue(auditEntries.first?.message.contains("Queued for approval") == true)
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
        let executedRequests = await harness.recorder.executedRequests()

        XCTAssertEqual(approved.outcome, .success)
        XCTAssertEqual(executedRequests, [request])
        XCTAssertEqual(auditEntries.count, 2)
        XCTAssertEqual(auditEntries.first?.outcome, .confirmationRequired)
        XCTAssertEqual(auditEntries.last?.outcome, .success)
    }

    func testApprovalPreparingExecutorFreezesRequestBeforeQueueingAndReplay() async throws {
        let recorder = RequestRecorder()
        let executor = RecordingExecutor(
            recorder: recorder,
            preparedArguments: [
                "targetID": .string("frozen-target-id"),
                "sessionID": .string("session-frozen"),
                "snapshotID": .string("snapshot-frozen"),
            ]
        )
        let harness = try TestHarness(executor: executor, recorder: recorder)
        let request = ActionRequest(
            action: .uiAct,
            arguments: [
                "app": .string("WhatsApp"),
                "query": .string("iOS Dump"),
            ],
            origin: RequestOrigin(kind: .cli)
        )

        let queued = await harness.bus.dispatch(request)
        let approvalID = try XCTUnwrap(queued.payload?.objectValue?["approvalID"]?.stringValue)
        let pendingApprovals = await harness.bus.pendingApprovals()
        let preparedRequest = try XCTUnwrap(pendingApprovals.first?.request)

        let approved = await harness.bus.resolveApproval(
            id: try XCTUnwrap(UUID(uuidString: approvalID)),
            decision: .approve
        )
        let executedRequests = await harness.recorder.executedRequests()
        let replayedRequest = try XCTUnwrap(executedRequests.first)

        XCTAssertEqual(approved.outcome, .success)
        XCTAssertEqual(executedRequests.count, 1)
        XCTAssertEqual(preparedRequest.arguments["query"]?.stringValue, "iOS Dump")
        XCTAssertEqual(preparedRequest.arguments["targetID"]?.stringValue, "frozen-target-id")
        XCTAssertEqual(preparedRequest.arguments["sessionID"]?.stringValue, "session-frozen")
        XCTAssertEqual(preparedRequest.arguments["snapshotID"]?.stringValue, "snapshot-frozen")
        XCTAssertEqual(replayedRequest.arguments, preparedRequest.arguments)
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
        let executedRequests = await harness.recorder.executedRequests()

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(executedRequests, [request])
    }

    func testTrustedAutomationSessionNormalizesRequestedAppNames() async throws {
        let store = TrustedAutomationSessionStore()
        let session = await store.start(
            appName: "WhatsApp",
            bundleIdentifier: "net.whatsapp.WhatsApp",
            processIdentifier: 42,
            allowedActions: TrustedAutomationPolicy.defaultAllowedActions
        )

        let request = ActionRequest(
            action: .uiAct,
            arguments: [
                "app": .string("\u{2068}WhatsApp\u{2069}"),
                "trustedSessionID": .string(session.id.uuidString),
            ],
            origin: RequestOrigin(kind: .cli)
        )

        let allowed = await store.allows(request)

        XCTAssertTrue(allowed)
    }
}

private struct TestHarness {
    let bus: CommandBus
    let auditStore: AuditStore
    let recorder: RequestRecorder
    let trustedSessionStore: TrustedAutomationSessionStore

    init(
        executor: (any ActionExecutor)? = nil,
        recorder: RequestRecorder? = nil
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wizmac-core-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let resolvedRecorder = recorder ?? RequestRecorder()
        let resolvedExecutor = executor ?? RecordingExecutor(recorder: resolvedRecorder)

        let settingsStore = try SettingsStore(url: directory.appendingPathComponent("settings.json"))
        self.auditStore = try AuditStore(url: directory.appendingPathComponent("audit.jsonl"))
        let approvalStore = try ApprovalStore(url: directory.appendingPathComponent("approvals.json"))
        self.recorder = resolvedRecorder
        self.trustedSessionStore = TrustedAutomationSessionStore()
        let policy = ApprovalPolicy(
            settingsStore: settingsStore,
            trustedSessionStore: trustedSessionStore
        )
        self.bus = CommandBus(
            executor: resolvedExecutor,
            auditStore: auditStore,
            approvalStore: approvalStore,
            approvalPolicy: policy
        )
    }
}

private actor RequestRecorder {
    private var requests: [ActionRequest] = []

    func append(_ request: ActionRequest) {
        requests.append(request)
    }

    func executedRequests() -> [ActionRequest] {
        requests
    }
}

private actor RecordingExecutor: ApprovalPreparingActionExecutor {
    private let recorder: RequestRecorder
    private let preparedArguments: [String: JSONValue]

    init(recorder: RequestRecorder, preparedArguments: [String: JSONValue] = [:]) {
        self.recorder = recorder
        self.preparedArguments = preparedArguments
    }

    func prepareForApproval(_ request: ActionRequest) async -> ActionRequest {
        guard preparedArguments.isEmpty == false else { return request }

        var mergedArguments = request.arguments
        for (key, value) in preparedArguments {
            mergedArguments[key] = value
        }

        return ActionRequest(
            id: request.id,
            action: request.action,
            arguments: mergedArguments,
            origin: request.origin,
            createdAt: request.createdAt
        )
    }

    func execute(_ request: ActionRequest) async -> ActionResult {
        await recorder.append(request)
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Executed \(request.action.rawValue)."
        )
    }
}
