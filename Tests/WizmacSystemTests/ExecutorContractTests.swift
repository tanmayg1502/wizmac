import AppKit
import ApplicationServices
import Foundation
import XCTest
@testable import WizmacSystem
import WizmacCore
import WizmacTextMode

final class ExecutorContractTests: XCTestCase {
    func testUIHintsReturnsHintPayloadUsingContractAction() async throws {
        let target = sampleTarget(id: "button-1", title: "Primary Action", role: "AXButton")
        let snapshot = sampleSnapshot(targets: [target])
        let hintSession = UIHintSession(query: "primary", alphabet: "asdf", snapshot: snapshot)
        let dependencies = try makeDependencies(snapshotter: SnapshotterStub(snapshot: snapshot, hintSession: hintSession))
        let executor = dependencies.executor
        let request = ActionRequest(
            action: .uiHints,
            arguments: ["query": .string("primary")],
            origin: RequestOrigin(kind: .test)
        )

        let result = await executor.execute(request)
        let payload = try XCTUnwrap(result.payload?.objectValue)

        XCTAssertEqual(result.requestID, request.id)
        XCTAssertEqual(result.action, .uiHints)
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(payload["query"]?.stringValue, "primary")
        XCTAssertEqual(payload["targets"]?.arrayValue?.count, 1)
    }

    func testUIDragPerformsPointerDragAndPreservesActionName() async throws {
        let source = sampleTarget(id: "source", title: "Source", role: "AXButton", rect: TargetRect(x: 10, y: 20, width: 40, height: 30))
        let destination = sampleTarget(id: "destination", title: "Destination", role: "AXButton", rect: TargetRect(x: 200, y: 100, width: 60, height: 40))
        let snapshotter = SnapshotterStub(snapshot: sampleSnapshot(targets: [source, destination]), hintSession: nil)
        snapshotter.targetsByID = [source.id: source, destination.id: destination]
        let pointer = PointerStub()
        let dependencies = try makeDependencies(snapshotter: snapshotter, pointerPerformer: pointer)
        let request = ActionRequest(
            action: .uiDrag,
            arguments: [
                "targetID": .string(source.id),
                "destinationTargetID": .string(destination.id),
                "steps": .number(5),
            ],
            origin: RequestOrigin(kind: .test)
        )

        let result = await dependencies.executor.execute(request)

        XCTAssertEqual(result.action, .uiDrag)
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(pointer.drags.count, 1)
        XCTAssertEqual(pointer.drags.first?.start, CGPoint(x: 30, y: 35))
        XCTAssertEqual(pointer.drags.first?.end, CGPoint(x: 230, y: 120))
        XCTAssertEqual(pointer.drags.first?.steps, 5)
    }

    func testScrollSessionStartStepAndEndShareExecutorState() async throws {
        let scrollTarget = sampleTarget(
            id: "scroll-area",
            title: "Messages",
            role: "AXScrollArea",
            rect: TargetRect(x: 20, y: 40, width: 120, height: 90)
        )
        let snapshot = sampleSnapshot(targets: [scrollTarget])
        let snapshotter = SnapshotterStub(snapshot: snapshot, hintSession: nil)
        let performer = RecordingScrollPerformer()
        let scrollController = ScrollController(performer: performer)
        let dependencies = try makeDependencies(snapshotter: snapshotter, scrollController: scrollController)

        let start = await dependencies.executor.execute(ActionRequest(action: .scrollSessionStart, origin: RequestOrigin(kind: .test)))
        let step = await dependencies.executor.execute(
            ActionRequest(
                action: .scrollStep,
                arguments: ["direction": .string("down"), "amount": .number(4)],
                origin: RequestOrigin(kind: .test)
            )
        )
        let end = await dependencies.executor.execute(ActionRequest(action: .scrollSessionEnd, origin: RequestOrigin(kind: .test)))

        XCTAssertEqual(start.action, .scrollSessionStart)
        XCTAssertEqual(start.outcome, .success)
        XCTAssertEqual(start.payload?.objectValue?["targetID"]?.stringValue, scrollTarget.id)
        XCTAssertEqual(step.outcome, .success)
        XCTAssertEqual(performer.calls.count, 1)
        XCTAssertEqual(end.action, .scrollSessionEnd)
        XCTAssertEqual(end.outcome, .success)
        XCTAssertEqual(end.payload?.objectValue?["stepCount"]?.intValue, 1)
    }

    func testTextStatusAndDetachUseRicherSessionState() async throws {
        let bridge = FocusedTextBridgeStub(
            capture: FocusedTextCapture(
                element: nil,
                context: sampleTextContext()
            )
        )
        let dependencies = try makeDependencies(focusedTextBridge: bridge)

        let attach = await dependencies.executor.execute(ActionRequest(action: .textAttach, origin: RequestOrigin(kind: .test)))
        let sendKeys = await dependencies.executor.execute(
            ActionRequest(
                action: .textSendKeys,
                arguments: ["keys": .string("iabc<esc>")],
                origin: RequestOrigin(kind: .test)
            )
        )
        let status = await dependencies.executor.execute(ActionRequest(action: .textStatus, origin: RequestOrigin(kind: .test)))
        let mode = await dependencies.executor.execute(ActionRequest(action: .textMode, origin: RequestOrigin(kind: .test)))
        let detach = await dependencies.executor.execute(ActionRequest(action: .textDetach, origin: RequestOrigin(kind: .test)))
        let statusAfterDetach = await dependencies.executor.execute(ActionRequest(action: .textStatus, origin: RequestOrigin(kind: .test)))

        let statusPayload = try XCTUnwrap(status.payload?.objectValue)
        let modePayload = try XCTUnwrap(mode.payload?.objectValue)

        XCTAssertEqual(attach.outcome, .success)
        XCTAssertEqual(sendKeys.outcome, .success)
        XCTAssertEqual(status.action, .textStatus)
        XCTAssertEqual(status.outcome, .success)
        XCTAssertEqual(statusPayload["handledEventCount"]?.intValue, 5)
        XCTAssertEqual(statusPayload["queuedKeyCount"]?.intValue, 5)
        XCTAssertEqual(statusPayload["mode"]?.stringValue, TextInputMode.normal.rawValue)
        XCTAssertEqual(mode.action, .textMode)
        XCTAssertEqual(modePayload["recentCommands"]?.arrayValue?.isEmpty, false)
        XCTAssertEqual(modePayload["queuedKeys"]?.arrayValue?.count, 5)
        XCTAssertEqual(detach.action, .textDetach)
        XCTAssertEqual(detach.outcome, .success)
        XCTAssertEqual(statusAfterDetach.outcome, .notFound)
    }

    func testUITextSendKeysCoalescesPlainTextIntoBulkInsert() async throws {
        let bridge = FocusedTextBridgeStub(
            capture: FocusedTextCapture(
                element: nil,
                context: sampleTextContext()
            )
        )
        let dependencies = try makeDependencies(focusedTextBridge: bridge)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .textSendKeys,
                arguments: ["keys": .string(" world")],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(bridge.syncedContexts.last?.text, " worldhello world")
        XCTAssertTrue(bridge.appliedCommands.isEmpty)
    }

    func testUISearchReturnsSessionMetadataAndDebugTimings() async throws {
        let target = sampleTarget(id: "button-1", title: "Primary Action", role: "AXButton")
        let snapshot = sampleSnapshot(targets: [target])
        let snapshotter = SnapshotterStub(snapshot: snapshot, hintSession: nil)
        let dependencies = try makeDependencies(snapshotter: snapshotter)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .uiSearch,
                arguments: [
                    "query": .string("primary"),
                    "debugTimings": .bool(true),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertNotNil(result.payload?.objectValue?["sessionID"]?.stringValue)
        XCTAssertNotNil(result.payload?.objectValue?["snapshotID"]?.stringValue)
        XCTAssertNotNil(result.payload?.objectValue?["timings"]?.objectValue?["snapshotMs"])
    }

    func testUISearchReturnsNotFoundWhenRequestedAppIsMissing() async throws {
        let dependencies = try makeDependencies()

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .uiSearch,
                arguments: ["app": .string("definitely-not-running-wizmac-app")],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .notFound)
    }

    func testUICaptureRawReturnsDebugPayloadForTarget() async throws {
        let target = sampleTarget(id: "button-1", title: "Primary Action", role: "AXButton")
        let snapshot = sampleSnapshot(targets: [target])
        let snapshotter = SnapshotterStub(snapshot: snapshot, hintSession: nil)
        snapshotter.debugDumpPayloadValue = [
            "target": target.payload,
            "tree": [
                "role": .string("AXButton"),
                "title": .string("Primary Action"),
            ],
        ]
        let dependencies = try makeDependencies(snapshotter: snapshotter)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .uiCapture,
                arguments: [
                    "detail": .string("raw"),
                    "targetID": .string(target.id),
                    "sessionID": .string("session-1"),
                    "snapshotID": .string("snapshot-1"),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.payload?.objectValue?["target"]?.objectValue?["id"]?.stringValue, target.id)
        XCTAssertEqual(result.payload?.objectValue?["tree"]?.objectValue?["role"]?.stringValue, "AXButton")
    }

    func testAirPlayDisconnectUsesDisconnectPath() async throws {
        let airPlay = AirPlayControllerStub()
        let dependencies = try makeDependencies(airPlayController: airPlay)

        let result = await dependencies.executor.execute(
            ActionRequest(action: .displayAirPlayDisconnect, origin: RequestOrigin(kind: .test))
        )

        XCTAssertEqual(result.action, .displayAirPlayDisconnect)
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(airPlay.disconnectCalls, 1)
        XCTAssertEqual(airPlay.connectCalls, 0)
    }

    func testWindowExcludePersistsDerivedRule() async throws {
        let windowRule = ExcludedWindowRule(appName: "FixtureHost", title: "Secondary Window")
        let windowController = WindowControllerStub(excludeRule: windowRule)
        let dependencies = try makeDependencies(windowController: windowController)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .windowExclude,
                arguments: ["windowID": .number(77)],
                origin: RequestOrigin(kind: .test)
            )
        )
        let settings = try await dependencies.settingsStore.load()

        XCTAssertEqual(result.action, .windowExclude)
        XCTAssertEqual(result.outcome, .success)
        XCTAssertTrue(settings.excludedWindows.contains(windowRule))
    }
}

private extension ExecutorContractTests {
    struct Dependencies {
        var executor: MacAutomationExecutor
        var settingsStore: SettingsStore
    }

    func makeDependencies(
        snapshotter: SnapshotterStub = SnapshotterStub(snapshot: nil, hintSession: nil),
        windowController: WindowControllerStub = WindowControllerStub(),
        scrollController: any ScrollControlling = ScrollController(performer: RecordingScrollPerformer()),
        musicController: MusicControllerStub = MusicControllerStub(),
        airPlayController: AirPlayControllerStub = AirPlayControllerStub(),
        focusedTextBridge: FocusedTextBridgeStub = FocusedTextBridgeStub(capture: nil),
        pointerPerformer: PointerStub = PointerStub()
    ) throws -> Dependencies {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settingsStore = try SettingsStore(url: directory.appendingPathComponent("settings.json"))
        let auditStore = try AuditStore(url: directory.appendingPathComponent("audit.jsonl"))
        let executor = MacAutomationExecutor(
            settingsStore: settingsStore,
            auditStore: auditStore,
            snapshotter: snapshotter,
            permissionInspector: PermissionInspector(),
            windowController: windowController,
            scrollController: scrollController,
            musicController: musicController,
            airPlayController: airPlayController,
            textService: TextModeService(engine: FallbackTextModeEngine()),
            focusedTextBridge: focusedTextBridge,
            pointerPerformer: pointerPerformer
        )
        return Dependencies(executor: executor, settingsStore: settingsStore)
    }

    func sampleTarget(
        id: String,
        title: String,
        role: String,
        rect: TargetRect = TargetRect(x: 0, y: 0, width: 80, height: 30)
    ) -> TargetDescriptor {
        TargetDescriptor(
            id: id,
            appName: "FixtureHost",
            role: role,
            title: title,
            value: title,
            frame: rect,
            hint: "aa",
            path: ["root", title]
        )
    }

    func sampleSnapshot(targets: [TargetDescriptor]) -> TargetSnapshot {
        TargetSnapshot(
            appName: "FixtureHost",
            bundleIdentifier: "com.example.fixture",
            windowTitle: "Fixture Host",
            targets: targets
        )
    }

    func sampleTextContext() -> TextContextSnapshot {
        TextContextSnapshot(
            applicationBundleID: "com.example.fixture",
            applicationName: "FixtureHost",
            processIdentifier: 42,
            elementIdentifier: "editor-1",
            windowTitle: "Fixture Host",
            text: "hello world",
            cursor: TextCursorSnapshot(range: TextRange(location: 0, length: 0))
        )
    }
}

private final class SnapshotterStub: AccessibilitySnapshotting {
    var snapshot: TargetSnapshot?
    var hintSessionValue: UIHintSession?
    var targetsByID: [String: TargetDescriptor]
    var debugDumpPayloadValue: JSONValue?
    var sessionMetrics = UISessionMetrics(
        sessionID: "session-1",
        snapshotID: "snapshot-1",
        appName: "FixtureHost",
        windowTitle: "Fixture Host",
        targetCount: 0,
        cacheHit: true,
        cacheHitRate: 1,
        lastRefreshedAt: .now,
        snapshotMs: 1,
        cacheLookupMs: 0.5,
        rankingMs: 0.25
    )

    init(snapshot: TargetSnapshot?, hintSession: UIHintSession?, targetsByID: [String: TargetDescriptor] = [:]) {
        self.snapshot = snapshot
        self.hintSessionValue = hintSession
        self.targetsByID = targetsByID
    }

    func snapshotFrontmostApplication(labelAlphabet _: String) -> TargetSnapshot? {
        snapshot
    }

    func search(query _: String, labelAlphabet _: String, limit _: Int) -> TargetSnapshot? {
        snapshot
    }

    func search(
        query _: String,
        pid _: pid_t?,
        labelAlphabet _: String,
        limit _: Int,
        sessionID _: String?,
        scope _: UISearchScope,
        includeMenus _: Bool
    ) -> UISearchResult? {
        guard var snapshot else { return nil }
        snapshot.sessionID = sessionMetrics.sessionID
        snapshot.snapshotID = sessionMetrics.snapshotID
        sessionMetrics.targetCount = snapshot.targets.count
        return UISearchResult(snapshot: snapshot, metrics: sessionMetrics)
    }

    func target(id: String, labelAlphabet _: String) -> TargetDescriptor? {
        targetsByID[id] ?? snapshot?.targets.first(where: { $0.id == id })
    }

    func target(
        id: String,
        pid _: pid_t?,
        labelAlphabet _: String,
        sessionID _: String?,
        snapshotID _: String?,
        scope _: UISearchScope,
        includeMenus _: Bool
    ) -> UITargetLookupResult? {
        guard let resolvedTarget = targetsByID[id] ?? snapshot?.targets.first(where: { $0.id == id }) else {
            return nil
        }
        return UITargetLookupResult(target: resolvedTarget, metrics: sessionMetrics)
    }

    func endSession(id _: String?) -> UISessionMetrics? {
        sessionMetrics
    }

    func hintSession(query _: String?, labelAlphabet _: String, limit _: Int) -> UIHintSession? {
        hintSessionValue
    }

    func debugDump(
        targetID _: String,
        pid _: pid_t?,
        labelAlphabet _: String,
        sessionID _: String?,
        snapshotID _: String?,
        scope _: UISearchScope,
        includeMenus _: Bool,
        maxDepth _: Int
    ) -> JSONValue? {
        debugDumpPayloadValue
    }
}

private final class WindowControllerStub: WindowControlling {
    let excludeRuleValue: ExcludedWindowRule?
    var focusCalls: [(windowID: Int?, title: String?, pid: Int32?)] = []

    init(excludeRule: ExcludedWindowRule? = nil) {
        self.excludeRuleValue = excludeRule
    }

    func visibleWindows(excluding _: [ExcludedWindowRule]) -> [VisibleWindow] {
        []
    }

    func focus(windowID: Int?, title: String?, pid: Int32?) -> Bool {
        focusCalls.append((windowID, title, pid))
        return true
    }

    func excludeRule(windowID _: Int?, title _: String?, pid _: Int32?, excluding _: [ExcludedWindowRule]) -> ExcludedWindowRule? {
        excludeRuleValue
    }
}

private final class MusicControllerStub: MusicVolumeControlling {
    func currentVolume() async -> Int? { 42 }
    func setVolume(_ value: Int) async -> (Bool, String) { (true, "Set \(value)") }
}

private final class AirPlayControllerStub: AirPlayControlling {
    private(set) var connectCalls = 0
    private(set) var disconnectCalls = 0

    func listDevices() async -> [String] { ["Studio Display"] }

    func connect(device _: String) async -> (Bool, String) {
        connectCalls += 1
        return (true, "Connected")
    }

    func disconnect() async -> (Bool, String) {
        disconnectCalls += 1
        return (true, "Disconnected")
    }

    func openMenu() async -> (Bool, String) {
        (true, "Opened")
    }
}

private final class FocusedTextBridgeStub: FocusedTextBridging, @unchecked Sendable {
    var capture: FocusedTextCapture?
    private(set) var appliedCommands: [[TextModeCommand]] = []
    private(set) var syncedContexts: [TextContextSnapshot] = []

    init(capture: FocusedTextCapture?) {
        self.capture = capture
    }

    func captureFocusedContext() -> FocusedTextCapture? {
        capture
    }

    func sync(context: TextContextSnapshot, onto _: AXUIElement?) {
        syncedContexts.append(context)
    }

    func apply(
        commands: [TextModeCommand],
        for _: TextKeyEvent,
        to _: AXUIElement?,
        context _: inout TextContextSnapshot
    ) {
        appliedCommands.append(commands)
    }
}

private final class PointerStub: PointerAutomationPerforming {
    private(set) var moves: [CGPoint] = []
    private(set) var clicks: [(point: CGPoint, clickState: Int64, button: CGMouseButton)] = []
    private(set) var drags: [(start: CGPoint, end: CGPoint, steps: Int)] = []

    func move(to point: CGPoint) -> Bool {
        moves.append(point)
        return true
    }

    func click(at point: CGPoint, clickState: Int64, button: CGMouseButton) -> Bool {
        clicks.append((point, clickState, button))
        return true
    }

    func drag(from start: CGPoint, to end: CGPoint, steps: Int) -> Bool {
        drags.append((start, end, steps))
        return true
    }
}

private final class RecordingScrollPerformer: ScrollEventPerforming {
    private(set) var calls: [(direction: String, amount: Int, point: CGPoint)] = []

    func scroll(direction: String, amount: Int, at point: CGPoint) -> Bool {
        calls.append((direction, amount, point))
        return true
    }
}
