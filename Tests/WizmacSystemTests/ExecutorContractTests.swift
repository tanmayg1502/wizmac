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

    func testTimedMutationPathTimesOutWhenPreDelayExceedsTimeout() async throws {
        let target = sampleTarget(id: "button-1", title: "Primary Action", role: "AXButton")
        let snapshotter = SnapshotterStub(snapshot: sampleSnapshot(targets: [target]), hintSession: nil)
        snapshotter.targetsByID[target.id] = target
        let sleeper = RecordingSleeperStub()
        let dependencies = try makeDependencies(
            snapshotter: snapshotter,
            pointerPerformer: PointerStub(),
            sleeper: sleeper
        )

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .uiAct,
                arguments: [
                    "targetID": .string(target.id),
                    "interaction": .string("press"),
                    "preDelayMs": .number(200),
                    "timeoutMs": .number(50),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        let recordedSleeps = await sleeper.recordedSleeps()

        XCTAssertEqual(result.outcome, .failed)
        XCTAssertEqual(result.message, "Timed out after 50 ms.")
        XCTAssertTrue(recordedSleeps.contains(50))
        XCTAssertTrue(recordedSleeps.contains(200))
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

    func testMediaScreenshotNormalizesFormatAndScopeAtExecutorBoundary() async throws {
        let window = VisibleWindow(id: 88, appName: "FixtureHost", title: "Primary Panel", pid: 42, frame: TargetRect(x: 4, y: 8, width: 120, height: 80))
        let windowController = WindowControllerStub()
        windowController.visibleWindowsValue = [window]
        let mediaController = ScreenMediaControllerStub(
            screenshotResult: ScreenMediaOperationResult(
                outcome: .success,
                message: "Captured screenshot.",
                payload: [
                    "path": .string("/tmp/capture.jpg"),
                    "format": .string("jpg"),
                    "scope": .string("window:FixtureHost/Primary Panel"),
                ]
            )
        )
        let dependencies = try makeDependencies(
            windowController: windowController,
            screenMediaController: mediaController
        )

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .mediaScreenshot,
                arguments: [
                    "windowID": .number(Double(window.id)),
                    "path": .string("/tmp/capture.jpg"),
                    "format": .string("JPEG"),
                    "includeCursor": .bool(true),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        let screenshotRequests = await mediaController.screenshotRequests()

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.payload?.objectValue?["format"]?.stringValue, "jpg")
        XCTAssertEqual(result.payload?.objectValue?["scope"]?.stringValue, "window:FixtureHost/Primary Panel")
        XCTAssertEqual(screenshotRequests.count, 1)
        XCTAssertEqual(screenshotRequests.first?.format, "jpg")
        XCTAssertEqual(screenshotRequests.first?.scope.windowID, window.id)
        XCTAssertEqual(screenshotRequests.first?.includeCursor, true)
    }

    func testMediaRecordAndStreamRouteNormalizedSessionPayloads() async throws {
        let window = VisibleWindow(id: 21, appName: "FixtureHost", title: "Inspector", pid: 99, frame: TargetRect(x: 10, y: 10, width: 300, height: 240))
        let windowController = WindowControllerStub()
        windowController.visibleWindowsValue = [window]
        let mediaController = ScreenMediaControllerStub(
            screenshotResult: ScreenMediaOperationResult(outcome: .success, message: "ok", payload: nil),
            recordingResult: ScreenMediaOperationResult(
                outcome: .success,
                message: "Started screen recording.",
                payload: [
                    "sessionID": .string("rec-1"),
                    "status": .string("recording"),
                    "path": .string("/tmp/recording.mov"),
                    "codec": .string("hevc"),
                    "fps": .number(30),
                    "scope": .string("full_screen"),
                    "startedAt": .string("2026-03-19T00:00:00Z"),
                ]
            ),
            recordingStatusResult: ScreenMediaOperationResult(
                outcome: .success,
                message: "Recording is active.",
                payload: [
                    "sessionID": .string("rec-1"),
                    "status": .string("recording"),
                    "path": .string("/tmp/recording.mov"),
                    "codec": .string("hevc"),
                    "fps": .number(30),
                    "scope": .string("full_screen"),
                    "startedAt": .string("2026-03-19T00:00:00Z"),
                ]
            ),
            recordingStopResult: ScreenMediaOperationResult(
                outcome: .success,
                message: "Stopped screen recording.",
                payload: [
                    "sessionID": .string("rec-1"),
                    "status": .string("stopped"),
                    "path": .string("/tmp/recording.mov"),
                    "codec": .string("hevc"),
                    "fps": .number(30),
                    "scope": .string("full_screen"),
                    "startedAt": .string("2026-03-19T00:00:00Z"),
                ]
            ),
            streamStartResult: ScreenMediaOperationResult(
                outcome: .success,
                message: "Started local screen stream.",
                payload: [
                    "sessionID": .string("stream-1"),
                    "status": .string("streaming"),
                    "format": .string("mjpeg"),
                    "endpoint": .string("tcp://127.0.0.1:5000"),
                    "scope": .string("full_screen"),
                    "startedAt": .string("2026-03-19T00:00:00Z"),
                ]
            ),
            streamStatusResult: ScreenMediaOperationResult(
                outcome: .success,
                message: "Stream is active.",
                payload: [
                    "sessionID": .string("stream-1"),
                    "status": .string("streaming"),
                    "format": .string("mjpeg"),
                    "endpoint": .string("tcp://127.0.0.1:5000"),
                    "scope": .string("full_screen"),
                    "startedAt": .string("2026-03-19T00:00:00Z"),
                ]
            ),
            streamStopResult: ScreenMediaOperationResult(
                outcome: .success,
                message: "Stopped local screen stream.",
                payload: [
                    "sessionID": .string("stream-1"),
                    "status": .string("stopped"),
                    "format": .string("mjpeg"),
                    "endpoint": .string("tcp://127.0.0.1:5000"),
                    "scope": .string("full_screen"),
                    "startedAt": .string("2026-03-19T00:00:00Z"),
                ]
            )
        )
        let dependencies = try makeDependencies(
            windowController: windowController,
            screenMediaController: mediaController
        )

        let recordStart = await dependencies.executor.execute(
            ActionRequest(
                action: .mediaRecord,
                arguments: [
                    "operation": .string("start"),
                    "sessionID": .string("rec-1"),
                    "path": .string("/tmp/recording.mov"),
                    "codec": .string("HEVC"),
                    "fps": .number(30),
                    "maxDurationSeconds": .number(9),
                    "includeCursor": .bool(true),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )
        let recordStatus = await dependencies.executor.execute(
            ActionRequest(
                action: .mediaRecord,
                arguments: [
                    "operation": .string("status"),
                    "sessionID": .string("rec-1"),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )
        let recordStop = await dependencies.executor.execute(
            ActionRequest(
                action: .mediaRecord,
                arguments: [
                    "operation": .string("stop"),
                    "sessionID": .string("rec-1"),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )
        let streamStart = await dependencies.executor.execute(
            ActionRequest(
                action: .mediaStream,
                arguments: [
                    "operation": .string("start"),
                    "format": .string("MJPEG"),
                    "endpoint": .string("tcp://127.0.0.1:5000"),
                    "sessionID": .string("stream-1"),
                    "fps": .number(15),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )
        let streamStatus = await dependencies.executor.execute(
            ActionRequest(
                action: .mediaStream,
                arguments: [
                    "operation": .string("status"),
                    "sessionID": .string("stream-1"),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )
        let streamStop = await dependencies.executor.execute(
            ActionRequest(
                action: .mediaStream,
                arguments: [
                    "operation": .string("stop"),
                    "sessionID": .string("stream-1"),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        let recordRequests = await mediaController.recordingRequests()
        let streamRequests = await mediaController.streamRequests()

        XCTAssertEqual(recordStart.outcome, .success)
        XCTAssertEqual(recordStart.payload?.objectValue?["sessionID"]?.stringValue, "rec-1")
        XCTAssertEqual(recordStart.payload?.objectValue?["codec"]?.stringValue, "hevc")
        XCTAssertEqual(recordStatus.outcome, .success)
        XCTAssertEqual(recordStatus.payload?.objectValue?["status"]?.stringValue, "recording")
        XCTAssertEqual(recordStop.outcome, .success)
        XCTAssertEqual(recordStop.payload?.objectValue?["status"]?.stringValue, "stopped")
        XCTAssertEqual(streamStart.outcome, .success)
        XCTAssertEqual(streamStart.payload?.objectValue?["format"]?.stringValue, "mjpeg")
        XCTAssertEqual(streamStatus.outcome, .success)
        XCTAssertEqual(streamStatus.payload?.objectValue?["endpoint"]?.stringValue, "tcp://127.0.0.1:5000")
        XCTAssertEqual(streamStop.outcome, .success)
        XCTAssertEqual(streamStop.payload?.objectValue?["status"]?.stringValue, "stopped")
        XCTAssertEqual(recordRequests.count, 1)
        XCTAssertEqual(recordRequests.first?.codec, "hevc")
        XCTAssertEqual(recordRequests.first?.fps, 30)
        XCTAssertEqual(recordRequests.first?.maxDurationSeconds, 9)
        XCTAssertEqual(recordRequests.first?.includeCursor, true)
        XCTAssertNil(recordRequests.first?.scope.windowID)
        XCTAssertEqual(recordRequests.first?.scope.description, "full_screen")
        XCTAssertEqual(streamRequests.count, 1)
        XCTAssertEqual(streamRequests.first?.format, "mjpeg")
        XCTAssertEqual(streamRequests.first?.fps, 15)
        XCTAssertEqual(streamRequests.first?.endpoint, "tcp://127.0.0.1:5000")
        XCTAssertNil(streamRequests.first?.scope.windowID)
        XCTAssertEqual(streamRequests.first?.scope.description, "full_screen")
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

    func testUISearchResolvesExplicitTargetIDThroughTargetLookup() async throws {
        let target = sampleTarget(id: "button-1", title: "Primary Action", role: "AXButton")
        let snapshot = sampleSnapshot(targets: [target])
        let snapshotter = SnapshotterStub(snapshot: snapshot, hintSession: nil, targetsByID: [target.id: target])
        let dependencies = try makeDependencies(snapshotter: snapshotter)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .uiSearch,
                arguments: [
                    "targetID": .string(target.id),
                    "sessionID": .string("session-1"),
                    "snapshotID": .string("snapshot-1"),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(snapshotter.searchInvocations.count, 0)
        XCTAssertEqual(snapshotter.targetLookupInvocations.first?.id, target.id)
        XCTAssertEqual(snapshotter.targetLookupInvocations.first?.sessionID, "session-1")
        XCTAssertEqual(snapshotter.targetLookupInvocations.first?.snapshotID, "snapshot-1")
        XCTAssertEqual(result.payload?.objectValue?["targets"]?.arrayValue?.first?.objectValue?["id"]?.stringValue, target.id)
    }

    func testUISearchTreatsTargetIDShapedQueryAsExactLookup() async throws {
        let target = sampleTarget(
            id: "VGVzdHxBWEJ1dHRvbnxQcmltYXJ5IEFjdGlvbnx8QVhXaW5kb3cvQVhCdXR0b25bMF0=",
            title: "Primary Action",
            role: "AXButton"
        )
        let snapshot = sampleSnapshot(targets: [target])
        let snapshotter = SnapshotterStub(snapshot: snapshot, hintSession: nil, targetsByID: [target.id: target])
        let dependencies = try makeDependencies(snapshotter: snapshotter)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .uiSearch,
                arguments: [
                    "query": .string(target.id),
                    "sessionID": .string("session-1"),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(snapshotter.searchInvocations.count, 0)
        XCTAssertEqual(snapshotter.targetLookupInvocations.first?.id, target.id)
        XCTAssertEqual(result.payload?.objectValue?["targets"]?.arrayValue?.first?.objectValue?["id"]?.stringValue, target.id)
    }

    func testUISearchTargetIDShapedQueryReturnsNotFoundInsteadOfFuzzyFallback() async throws {
        let missingTargetID = "VGVzdHxBWEJ1dHRvbnxNaXNzaW5nfHxBWFdpbmRvdy9BWEJ1dHRvblswXXwxMDA6MTAwOjYwOjMw"
        let snapshot = sampleSnapshot(targets: [sampleTarget(id: "button-1", title: "Compose", role: "AXButton")])
        let snapshotter = SnapshotterStub(snapshot: snapshot, hintSession: nil, targetsByID: [:])
        let dependencies = try makeDependencies(snapshotter: snapshotter)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .uiSearch,
                arguments: [
                    "query": .string(missingTargetID),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .notFound)
        XCTAssertEqual(snapshotter.searchInvocations.count, 0)
        XCTAssertEqual(snapshotter.targetLookupInvocations.first?.id, missingTargetID)
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

    func testUIActReturnsPostStateAndSessionMetadata() async throws {
        let target = sampleTarget(
            id: "chat-row",
            title: "Family",
            role: "AXButton",
            rect: TargetRect(x: 10, y: 20, width: 80, height: 24)
        )
        let snapshotter = SnapshotterStub(snapshot: sampleSnapshot(targets: [target]), hintSession: nil)
        snapshotter.targetsByID[target.id] = target
        let pointer = PointerStub()
        let dependencies = try makeDependencies(snapshotter: snapshotter, pointerPerformer: pointer)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .uiAct,
                arguments: [
                    "targetID": .string(target.id),
                    "nextQuery": .string("Compose message"),
                    "debugTimings": .bool(true),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.payload?.objectValue?["targetID"]?.stringValue, target.id)
        XCTAssertEqual(result.payload?.objectValue?["sessionID"]?.stringValue, "session-1")
        XCTAssertEqual(result.payload?.objectValue?["snapshotID"]?.stringValue, "snapshot-1")
        XCTAssertEqual(result.payload?.objectValue?["postState"]?.objectValue?["targets"]?.arrayValue?.count, 1)
        XCTAssertEqual(snapshotter.endSessionCalls, ["session-1"])
        XCTAssertEqual(snapshotter.searchInvocations.last?.query, "Compose message")
        XCTAssertEqual(pointer.clicks.count, 1)
    }

    func testUIActCanResolveQueryWithoutTargetID() async throws {
        let target = sampleTarget(
            id: "chat-row",
            title: "Family",
            role: "AXButton",
            rect: TargetRect(x: 10, y: 20, width: 80, height: 24)
        )
        let snapshotter = SnapshotterStub(snapshot: sampleSnapshot(targets: [target]), hintSession: nil)
        let pointer = PointerStub()
        let dependencies = try makeDependencies(snapshotter: snapshotter, pointerPerformer: pointer)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .uiAct,
                arguments: [
                    "query": .string("Family"),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.payload?.objectValue?["targetID"]?.stringValue, target.id)
        XCTAssertEqual(result.payload?.objectValue?["sessionID"]?.stringValue, "session-1")
        XCTAssertEqual(result.payload?.objectValue?["snapshotID"]?.stringValue, "snapshot-1")
        XCTAssertEqual(snapshotter.searchInvocations.map(\.query), ["Family"])
        XCTAssertTrue(snapshotter.targetLookupInvocations.isEmpty)
        XCTAssertEqual(pointer.clicks.count, 1)
    }

    func testUIActPrefersExplicitTargetIDOverQuery() async throws {
        let exactTarget = sampleTarget(
            id: "exact-row",
            title: "Family",
            role: "AXButton",
            rect: TargetRect(x: 10, y: 20, width: 80, height: 24)
        )
        let searchTarget = sampleTarget(
            id: "search-row",
            title: "Family Search Result",
            role: "AXButton",
            rect: TargetRect(x: 40, y: 50, width: 80, height: 24)
        )
        let snapshotter = SnapshotterStub(snapshot: sampleSnapshot(targets: [searchTarget]), hintSession: nil)
        snapshotter.targetsByID[exactTarget.id] = exactTarget
        let pointer = PointerStub()
        let dependencies = try makeDependencies(snapshotter: snapshotter, pointerPerformer: pointer)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .uiAct,
                arguments: [
                    "targetID": .string(exactTarget.id),
                    "query": .string("Family Search Result"),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.payload?.objectValue?["targetID"]?.stringValue, exactTarget.id)
        XCTAssertEqual(snapshotter.searchInvocations.count, 0)
        XCTAssertEqual(snapshotter.targetLookupInvocations.first?.id, exactTarget.id)
        XCTAssertEqual(pointer.clicks.count, 1)
    }

    func testUIActTreatsTargetIDShapedQueryAsExactLookup() async throws {
        let target = sampleTarget(
            id: "VGVzdHxBWEJ1dHRvbnxGYW1pbHl8fEFYV2luZG93L0FYQnV0dG9uWzBd",
            title: "Family",
            role: "AXButton",
            rect: TargetRect(x: 10, y: 20, width: 80, height: 24)
        )
        let snapshotter = SnapshotterStub(snapshot: sampleSnapshot(targets: [target]), hintSession: nil, targetsByID: [target.id: target])
        let pointer = PointerStub()
        let dependencies = try makeDependencies(snapshotter: snapshotter, pointerPerformer: pointer)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .uiAct,
                arguments: [
                    "query": .string(target.id),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.payload?.objectValue?["targetID"]?.stringValue, target.id)
        XCTAssertEqual(snapshotter.searchInvocations.count, 0)
        XCTAssertEqual(snapshotter.targetLookupInvocations.first?.id, target.id)
        XCTAssertEqual(pointer.clicks.count, 1)
    }

    func testUICopyCanResolveQueryWithoutTargetID() async throws {
        let target = sampleTarget(
            id: "compose-field",
            title: "Compose message",
            role: "AXTextField",
            rect: TargetRect(x: 10, y: 20, width: 160, height: 30)
        )
        let snapshotter = SnapshotterStub(snapshot: sampleSnapshot(targets: [target]), hintSession: nil)
        let dependencies = try makeDependencies(snapshotter: snapshotter)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .uiCopy,
                arguments: [
                    "query": .string("Compose message"),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.payload?.objectValue?["targetID"]?.stringValue, target.id)
        XCTAssertEqual(result.payload?.objectValue?["value"]?.stringValue, "Compose message")
        XCTAssertEqual(snapshotter.searchInvocations.map(\.query), ["Compose message"])
        XCTAssertTrue(snapshotter.targetLookupInvocations.isEmpty)
    }

    func testUIActQueryReturnsHelpfulNotFoundWhenNoTargetMatches() async throws {
        let snapshotter = SnapshotterStub(snapshot: sampleSnapshot(targets: []), hintSession: nil)
        let dependencies = try makeDependencies(snapshotter: snapshotter)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .uiAct,
                arguments: [
                    "query": .string("Missing target"),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .notFound)
        XCTAssertEqual(result.message, "No UI target matched 'Missing target'.")
        XCTAssertEqual(snapshotter.searchInvocations.map(\.query), ["Missing target"])
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

    func testTextInsertCanResolveQueryTargetAndReturnPostState() async throws {
        let target = sampleTarget(
            id: "composer",
            title: "Compose message",
            role: "AXTextField",
            rect: TargetRect(x: 50, y: 100, width: 200, height: 36)
        )
        let snapshotter = SnapshotterStub(snapshot: sampleSnapshot(targets: [target]), hintSession: nil)
        let bridge = FocusedTextBridgeStub(
            capture: FocusedTextCapture(
                element: nil,
                context: sampleTextContext()
            )
        )
        let pointer = PointerStub()
        let dependencies = try makeDependencies(
            snapshotter: snapshotter,
            focusedTextBridge: bridge,
            pointerPerformer: pointer
        )

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .textInsert,
                arguments: [
                    "query": .string("Compose message"),
                    "text": .string("hello"),
                    "submit": .bool(true),
                    "nextQuery": .string("Sent"),
                    "debugTimings": .bool(true),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.payload?.objectValue?["targetID"]?.stringValue, target.id)
        XCTAssertEqual(result.payload?.objectValue?["postState"]?.objectValue?["targets"]?.arrayValue?.count, 1)
        XCTAssertEqual(snapshotter.searchInvocations.map(\.query), ["Compose message", "Sent"])
        XCTAssertEqual(pointer.clicks.count, 1)
        XCTAssertEqual(bridge.syncedContexts.last?.text, "hellohello world")
    }

    func testUIOpenAndUISelectResolveHumanFriendlySelectors() async throws {
        let target = sampleTarget(
            id: "family-row",
            title: "Family",
            role: "AXButton",
            rect: TargetRect(x: 20, y: 40, width: 120, height: 28)
        )
        let snapshotter = SnapshotterStub(snapshot: sampleSnapshot(targets: [target]), hintSession: nil)
        let pointer = PointerStub()
        let dependencies = try makeDependencies(snapshotter: snapshotter, pointerPerformer: pointer)

        let openResult = await dependencies.executor.execute(
            ActionRequest(
                action: .uiOpen,
                arguments: ["query": .string("Family")],
                origin: RequestOrigin(kind: .test)
            )
        )
        let selectResult = await dependencies.executor.execute(
            ActionRequest(
                action: .uiSelect,
                arguments: ["option": .string("Family")],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(openResult.outcome, .success)
        XCTAssertEqual(selectResult.outcome, .success)
        XCTAssertEqual(snapshotter.searchInvocations.map(\.query), ["Family", "Family"])
        XCTAssertEqual(pointer.clicks.count, 2)
    }

    func testUIToggleSkipsClickWhenRequestedStateAlreadyMatches() async throws {
        let target = sampleTarget(
            id: "notifications-toggle",
            title: "Notifications",
            role: "AXCheckBox"
        )
        var selectedTarget = target
        selectedTarget.value = "1"
        let snapshotter = SnapshotterStub(
            snapshot: sampleSnapshot(targets: [selectedTarget]),
            hintSession: nil,
            targetsByID: [selectedTarget.id: selectedTarget]
        )
        let pointer = PointerStub()
        let dependencies = try makeDependencies(snapshotter: snapshotter, pointerPerformer: pointer)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .uiToggle,
                arguments: [
                    "targetID": .string(selectedTarget.id),
                    "state": .string("on"),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.payload?.objectValue?["changed"]?.boolValue, false)
        XCTAssertEqual(pointer.clicks.count, 0)
    }

    func testUIReadAndUIWaitExposeResolvedContentWithoutManualTreeParsing() async throws {
        let target = sampleTarget(
            id: "status-label",
            title: "Status",
            role: "AXStaticText"
        )
        var detailTarget = target
        detailTarget.value = "Ready"
        let snapshotter = SnapshotterStub(snapshot: sampleSnapshot(targets: [detailTarget]), hintSession: nil)
        let dependencies = try makeDependencies(snapshotter: snapshotter)

        let readResult = await dependencies.executor.execute(
            ActionRequest(
                action: .uiRead,
                arguments: ["query": .string("Status")],
                origin: RequestOrigin(kind: .test)
            )
        )
        let waitResult = await dependencies.executor.execute(
            ActionRequest(
                action: .uiWait,
                arguments: [
                    "query": .string("Status"),
                    "text": .string("Ready"),
                    "timeoutMs": .number(50),
                    "pollIntervalMs": .number(20),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(readResult.outcome, .success)
        XCTAssertEqual(readResult.payload?.objectValue?["targetID"]?.stringValue, detailTarget.id)
        XCTAssertEqual(readResult.payload?.objectValue?["text"]?.stringValue, "Ready")
        XCTAssertEqual(waitResult.outcome, .success)
        XCTAssertEqual(waitResult.payload?.objectValue?["matchedCount"]?.intValue, 1)
    }

    func testUIDiffReportsFreshChangesAgainstCachedBaseline() async throws {
        let baseline = sampleSnapshot(targets: [sampleTarget(id: "one", title: "One", role: "AXButton")])
        let fresh = sampleSnapshot(targets: [
            sampleTarget(id: "one", title: "One", role: "AXButton"),
            sampleTarget(id: "two", title: "Two", role: "AXButton"),
        ])
        let snapshotter = SnapshotterStub(snapshot: baseline, hintSession: nil)
        snapshotter.sessionSnapshotValue = baseline
        snapshotter.queuedSearchSnapshots = [fresh]
        let dependencies = try makeDependencies(snapshotter: snapshotter)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .uiDiff,
                arguments: ["sessionID": .string("session-1")],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.payload?.objectValue?["changed"]?.boolValue, true)
        XCTAssertEqual(result.payload?.objectValue?["addedTargets"]?.arrayValue?.count, 1)
        XCTAssertEqual(snapshotter.endSessionCalls, ["session-1"])
    }

    func testScrollToFindsTargetAfterSteppingActiveContainer() async throws {
        let scrollArea = sampleTarget(
            id: "message-list",
            title: "Messages",
            role: "AXScrollArea",
            rect: TargetRect(x: 10, y: 20, width: 120, height: 180)
        )
        let target = sampleTarget(
            id: "target-row",
            title: "Weekly Update",
            role: "AXStaticText",
            rect: TargetRect(x: 20, y: 160, width: 120, height: 24)
        )
        let snapshotter = SnapshotterStub(snapshot: sampleSnapshot(targets: [scrollArea]), hintSession: nil)
        snapshotter.queuedSearchSnapshots = [
            sampleSnapshot(targets: [scrollArea]),
            sampleSnapshot(targets: [scrollArea, target]),
        ]
        let performer = RecordingScrollPerformer()
        let scrollController = ScrollController(performer: performer)
        let dependencies = try makeDependencies(snapshotter: snapshotter, scrollController: scrollController)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .scrollTo,
                arguments: [
                    "query": .string("Weekly Update"),
                    "timeoutMs": .number(150),
                    "pollIntervalMs": .number(20),
                    "maxSteps": .number(3),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.payload?.objectValue?["targetID"]?.stringValue, target.id)
        XCTAssertEqual(result.payload?.objectValue?["stepCount"]?.intValue, 1)
        XCTAssertEqual(performer.calls.count, 1)
    }

    func testScrollToIgnoresWeakSemanticMatchesUntilExactTextAppears() async throws {
        let scrollArea = sampleTarget(
            id: "message-list",
            title: "Messages",
            role: "AXScrollArea",
            rect: TargetRect(x: 10, y: 20, width: 120, height: 180)
        )
        let misleadingMessage = sampleTarget(
            id: "jim-announcement",
            title: "jim: All, the next two weeks are final-exam week and spring break. So, our next meeting will be in three weeks.",
            role: "AXStaticText",
            rect: TargetRect(x: 20, y: 40, width: 220, height: 24)
        )
        let targetMessage = sampleTarget(
            id: "target-row",
            title: "Hi guys! I'm so sorry i wasn't able to show up to meeting today. Can i demo the project next week?",
            role: "AXStaticText",
            rect: TargetRect(x: 20, y: 140, width: 260, height: 24)
        )
        let snapshotter = SnapshotterStub(snapshot: sampleSnapshot(targets: [scrollArea, misleadingMessage]), hintSession: nil)
        snapshotter.queuedSearchSnapshots = [
            sampleSnapshot(targets: [scrollArea, misleadingMessage]),
            sampleSnapshot(targets: [scrollArea, misleadingMessage, targetMessage]),
        ]
        let performer = RecordingScrollPerformer()
        let scrollController = ScrollController(performer: performer)
        let dependencies = try makeDependencies(snapshotter: snapshotter, scrollController: scrollController)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .scrollTo,
                arguments: [
                    "query": .string("Hi guys! I'm so sorry i wasn't able to show up to meeting today. Can i demo the project next week?"),
                    "timeoutMs": .number(150),
                    "pollIntervalMs": .number(20),
                    "maxSteps": .number(3),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.payload?.objectValue?["targetID"]?.stringValue, targetMessage.id)
        XCTAssertEqual(result.payload?.objectValue?["stepCount"]?.intValue, 1)
        XCTAssertEqual(performer.calls.count, 1)
    }

    func testScrollToPrefersLargestContentListOverSidebarOutline() async throws {
        let sidebar = TargetDescriptor(
            id: "sidebar-outline",
            appName: "FixtureHost",
            role: "AXOutline",
            title: "Sidebar",
            value: "",
            frame: TargetRect(x: 0, y: 0, width: 180, height: 620),
            hint: "aa",
            path: ["AXWindow", "AXOutline[0]"]
        )
        let contentPane = TargetDescriptor(
            id: "content-pane",
            appName: "FixtureHost",
            role: "AXGroup",
            title: "Content Pane",
            value: "",
            frame: TargetRect(x: 300, y: 120, width: 900, height: 420),
            hint: "ab",
            path: ["AXWindow", "AXGroup[0]", "AXList[4]", "AXGroup[0]"]
        )
        let target = sampleTarget(
            id: "target-row",
            title: "Hi guys! I'm so sorry i wasn't able to show up to meeting today. Can i demo the project next week?",
            role: "AXStaticText",
            rect: TargetRect(x: 340, y: 220, width: 260, height: 24)
        )
        let snapshotter = SnapshotterStub(snapshot: sampleSnapshot(targets: [sidebar, contentPane]), hintSession: nil)
        snapshotter.queuedSearchSnapshots = [
            sampleSnapshot(targets: [sidebar, contentPane]),
            sampleSnapshot(targets: [sidebar, contentPane, target]),
        ]
        let performer = RecordingScrollPerformer()
        let scrollController = ScrollController(performer: performer)
        let dependencies = try makeDependencies(snapshotter: snapshotter, scrollController: scrollController)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .scrollTo,
                arguments: [
                    "query": .string("Hi guys! I'm so sorry i wasn't able to show up to meeting today. Can i demo the project next week?"),
                    "timeoutMs": .number(150),
                    "pollIntervalMs": .number(20),
                    "maxSteps": .number(3),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.payload?.objectValue?["targetID"]?.stringValue, target.id)
        XCTAssertEqual(result.payload?.objectValue?["stepCount"]?.intValue, 1)
        XCTAssertEqual(performer.calls.count, 1)
        XCTAssertEqual(performer.calls.first?.point, CGPoint(x: 750, y: 330))
    }

    func testScrollToUsesFreshFullSnapshots() async throws {
        let scrollArea = sampleTarget(
            id: "message-list",
            title: "Messages",
            role: "AXScrollArea",
            rect: TargetRect(x: 10, y: 20, width: 320, height: 180)
        )
        let target = sampleTarget(
            id: "target-row",
            title: "Weekly Update",
            role: "AXStaticText",
            rect: TargetRect(x: 24, y: 72, width: 180, height: 24)
        )
        let snapshotter = SnapshotterStub(snapshot: sampleSnapshot(targets: [scrollArea, target]), hintSession: nil)
        let performer = RecordingScrollPerformer()
        let scrollController = ScrollController(performer: performer)
        let dependencies = try makeDependencies(snapshotter: snapshotter, scrollController: scrollController)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .scrollTo,
                arguments: [
                    "query": .string("Weekly Update"),
                    "timeoutMs": .number(150),
                    "pollIntervalMs": .number(20),
                    "maxSteps": .number(2),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.payload?.objectValue?["targetID"]?.stringValue, target.id)
        XCTAssertEqual(result.payload?.objectValue?["stepCount"]?.intValue, 0)
        XCTAssertEqual(performer.calls.count, 0)
        XCTAssertEqual(snapshotter.searchInvocations.first?.limit, 250)
        XCTAssertEqual(snapshotter.searchInvocations.first?.bypassCache, true)
    }

    func testScrollToStabilizesClippedEdgeMatches() async throws {
        let query = "Hi guys! I'm so sorry i wasn't able to show up to meeting today. Can i demo the project next week?"
        let scrollArea = sampleTarget(
            id: "message-list",
            title: "Messages",
            role: "AXScrollArea",
            rect: TargetRect(x: 10, y: 20, width: 320, height: 180)
        )
        let clippedText = TargetDescriptor(
            id: "target-fragment",
            appName: "FixtureHost",
            role: "AXStaticText",
            title: "AXStaticText",
            subtitle: nil,
            value: query,
            frame: TargetRect(x: 24, y: 20, width: 220, height: 6),
            hint: "aa",
            path: ["AXWindow", "AXScrollArea[0]", "AXGroup[0]", "AXStaticText[0]"]
        )
        let stabilizedRow = TargetDescriptor(
            id: "target-row",
            appName: "FixtureHost",
            role: "AXGroup",
            title: "Tanmay: \(query) 3:28 PM.",
            subtitle: nil,
            value: "",
            frame: TargetRect(x: 18, y: 36, width: 280, height: 52),
            hint: "ab",
            path: ["AXWindow", "AXScrollArea[0]", "AXGroup[0]"]
        )
        let snapshotter = SnapshotterStub(snapshot: sampleSnapshot(targets: [scrollArea, clippedText]), hintSession: nil)
        snapshotter.queuedSearchSnapshots = [
            sampleSnapshot(targets: [scrollArea, clippedText]),
            sampleSnapshot(targets: [scrollArea, stabilizedRow]),
        ]
        let performer = RecordingScrollPerformer()
        let scrollController = ScrollController(performer: performer)
        let dependencies = try makeDependencies(snapshotter: snapshotter, scrollController: scrollController)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .scrollTo,
                arguments: [
                    "query": .string(query),
                    "direction": .string("up"),
                    "timeoutMs": .number(200),
                    "pollIntervalMs": .number(20),
                    "maxSteps": .number(3),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.payload?.objectValue?["targetID"]?.stringValue, stabilizedRow.id)
        XCTAssertEqual(result.payload?.objectValue?["stepCount"]?.intValue, 1)
        XCTAssertEqual(performer.calls.map(\.direction), ["down"])
        XCTAssertEqual(performer.calls.map(\.amount), [1])
    }

    func testScrollToDoesNotReturnGenericAncestorForStableTextMatch() async throws {
        let query = "Hi guys! I'm so sorry i wasn't able to show up to meeting today. Can i demo the project next week?"
        let scrollArea = sampleTarget(
            id: "message-list",
            title: "Messages",
            role: "AXScrollArea",
            rect: TargetRect(x: 10, y: 20, width: 320, height: 180)
        )
        let genericAncestor = TargetDescriptor(
            id: "generic-row",
            appName: "FixtureHost",
            role: "AXGroup",
            title: "AXGroup",
            subtitle: nil,
            value: "",
            frame: TargetRect(x: 16, y: 50, width: 280, height: 40),
            hint: "aa",
            path: ["AXWindow", "AXScrollArea[0]", "AXGroup[0]"]
        )
        let exactText = TargetDescriptor(
            id: "target-text",
            appName: "FixtureHost",
            role: "AXStaticText",
            title: "AXStaticText",
            subtitle: nil,
            value: query,
            frame: TargetRect(x: 24, y: 58, width: 220, height: 18),
            hint: "ab",
            path: ["AXWindow", "AXScrollArea[0]", "AXGroup[0]", "AXStaticText[0]"]
        )
        let snapshotter = SnapshotterStub(
            snapshot: sampleSnapshot(targets: [scrollArea, genericAncestor, exactText]),
            hintSession: nil
        )
        let performer = RecordingScrollPerformer()
        let scrollController = ScrollController(performer: performer)
        let dependencies = try makeDependencies(snapshotter: snapshotter, scrollController: scrollController)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .scrollTo,
                arguments: [
                    "query": .string(query),
                    "direction": .string("up"),
                    "timeoutMs": .number(150),
                    "pollIntervalMs": .number(20),
                    "maxSteps": .number(2),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.payload?.objectValue?["targetID"]?.stringValue, exactText.id)
        XCTAssertEqual(result.payload?.objectValue?["stepCount"]?.intValue, 0)
        XCTAssertEqual(performer.calls.count, 0)
    }

    func testWindowAssertUsesResolvedWindowMatch() async throws {
        let windowController = WindowControllerStub()
        windowController.matchedWindow = VisibleWindow(
            id: 77,
            appName: "Slack",
            title: "lab-meeting (Channel) - Slack",
            pid: 123,
            frame: nil
        )
        let dependencies = try makeDependencies(windowController: windowController)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .windowAssert,
                arguments: ["query": .string("lab meeting")],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.payload?.objectValue?["title"]?.stringValue, "lab-meeting (Channel) - Slack")
    }

    func testTextReadReturnsFocusedContext() async throws {
        let bridge = FocusedTextBridgeStub(
            capture: FocusedTextCapture(
                element: nil,
                context: sampleTextContext()
            )
        )
        let dependencies = try makeDependencies(focusedTextBridge: bridge)

        let result = await dependencies.executor.execute(
            ActionRequest(action: .textRead, origin: RequestOrigin(kind: .test))
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.payload?.objectValue?["text"]?.stringValue, "hello world")
        XCTAssertEqual(result.payload?.objectValue?["elementIdentifier"]?.stringValue, "editor-1")
    }

    func testUIChooseFileChainsInsertAndConfirmClick() async throws {
        let confirmTarget = sampleTarget(
            id: "confirm-open",
            title: "Open",
            role: "AXButton",
            rect: TargetRect(x: 80, y: 140, width: 90, height: 30)
        )
        let snapshotter = SnapshotterStub(snapshot: sampleSnapshot(targets: [confirmTarget]), hintSession: nil)
        let bridge = FocusedTextBridgeStub(
            capture: FocusedTextCapture(
                element: nil,
                context: sampleTextContext()
            )
        )
        let pointer = PointerStub()
        let dependencies = try makeDependencies(
            snapshotter: snapshotter,
            focusedTextBridge: bridge,
            pointerPerformer: pointer
        )

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .uiChooseFile,
                arguments: [
                    "path": .string("/tmp/report.pdf"),
                    "confirmQuery": .string("Open"),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertTrue(bridge.syncedContexts.last?.text.contains("/tmp/report.pdf") ?? false)
        XCTAssertEqual(pointer.clicks.count, 1)
        XCTAssertEqual(snapshotter.searchInvocations.last?.query, "Open")
    }

    func testMenuSelectRunsAppleScriptAgainstRequestedAppAndPath() async throws {
        let shellRunner = ShellRunnerStub()
        let dependencies = try makeDependencies(shellRunner: shellRunner)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .menuSelect,
                arguments: [
                    "app": .string("Preview"),
                    "path": .string("File > Export > PDF"),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        let invocations = await shellRunner.recordedInvocations()

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(invocations.first?.launchPath, "/usr/bin/osascript")
        XCTAssertEqual(result.payload?.objectValue?["app"]?.stringValue, "Preview")
        XCTAssertTrue(invocations.first?.arguments.last?.contains("\"File\", \"Export\", \"PDF\"") ?? false)
    }

    func testUIExecuteInterpolatesBindingsAndCarriesAmbientSessionIdentifiers() async throws {
        let target = sampleTarget(
            id: "family-row",
            title: "Family",
            role: "AXButton",
            rect: TargetRect(x: 20, y: 40, width: 120, height: 28)
        )
        let snapshotter = SnapshotterStub(snapshot: sampleSnapshot(targets: [target]), hintSession: nil)
        snapshotter.targetsByID[target.id] = target
        let pointer = PointerStub()
        let dependencies = try makeDependencies(snapshotter: snapshotter, pointerPerformer: pointer)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .uiExecute,
                arguments: [
                    "actions": .array([
                        .object([
                            "tool": .string("ui.search"),
                            "bind": .string("family"),
                            "arguments": .object([
                                "query": .string("Family"),
                            ]),
                        ]),
                        .object([
                            "tool": .string("ui.act"),
                            "arguments": .object([
                                "targetID": .string("{{family.payload.targets[0].id}}"),
                            ]),
                        ]),
                    ]),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(pointer.clicks.count, 1)
        XCTAssertEqual(snapshotter.targetLookupInvocations.first?.sessionID, "session-1")
        XCTAssertEqual(result.payload?.objectValue?["sessionID"]?.stringValue, "session-1")
        XCTAssertEqual(
            result.payload?.objectValue?["results"]?.arrayValue?.last?.objectValue?["payload"]?.objectValue?["targetID"]?.stringValue,
            target.id
        )
    }

    func testUIExecuteAcceptsBareHighLevelStepNames() async throws {
        let target = sampleTarget(
            id: "family-row",
            title: "Family",
            role: "AXButton",
            rect: TargetRect(x: 20, y: 40, width: 120, height: 28)
        )
        let snapshotter = SnapshotterStub(snapshot: sampleSnapshot(targets: [target]), hintSession: nil)
        snapshotter.targetsByID[target.id] = target
        let pointer = PointerStub()
        let dependencies = try makeDependencies(snapshotter: snapshotter, pointerPerformer: pointer)

        let result = await dependencies.executor.execute(
            ActionRequest(
                action: .uiExecute,
                arguments: [
                    "actions": .array([
                        .object([
                            "tool": .string("open"),
                            "arguments": .object([
                                "query": .string("Family"),
                            ]),
                        ]),
                        .object([
                            "tool": .string("assert"),
                            "arguments": .object([
                                "query": .string("Family"),
                            ]),
                        ]),
                    ]),
                ],
                origin: RequestOrigin(kind: .test)
            )
        )

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(pointer.clicks.count, 1)
        XCTAssertEqual(
            result.payload?.objectValue?["results"]?.arrayValue?.map { $0.objectValue?["tool"]?.stringValue ?? "" },
            ["open", "assert"]
        )
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
        pointerPerformer: PointerStub = PointerStub(),
        screenMediaController: any ScreenMediaControlling = ScreenMediaControllerStub(),
        shellRunner: any ShellRunning = ShellRunnerStub(),
        sleeper: any AutomationSleeping = TaskAutomationSleeper()
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
            screenMediaController: screenMediaController,
            textService: TextModeService(engine: FallbackTextModeEngine()),
            focusedTextBridge: focusedTextBridge,
            pointerPerformer: pointerPerformer,
            shellRunner: shellRunner,
            sleeper: sleeper
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
    struct SearchInvocation: Equatable {
        var query: String
        var sessionID: String?
        var pid: pid_t?
        var scope: UISearchScope
        var includeMenus: Bool
        var limit: Int
        var bypassCache: Bool
    }

    struct TargetLookupInvocation: Equatable {
        var id: String
        var sessionID: String?
        var snapshotID: String?
        var pid: pid_t?
        var scope: UISearchScope
        var includeMenus: Bool
    }

    var snapshot: TargetSnapshot?
    var hintSessionValue: UIHintSession?
    var targetsByID: [String: TargetDescriptor]
    var debugDumpPayloadValue: JSONValue?
    var sessionSnapshotValue: TargetSnapshot?
    var queuedSearchSnapshots: [TargetSnapshot] = []
    var searchInvocations: [SearchInvocation] = []
    var targetLookupInvocations: [TargetLookupInvocation] = []
    var endSessionCalls: [String?] = []
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
        query: String,
        pid: pid_t?,
        labelAlphabet _: String,
        limit: Int,
        sessionID: String?,
        scope: UISearchScope,
        includeMenus: Bool,
        bypassCache: Bool
    ) -> UISearchResult? {
        searchInvocations.append(
            SearchInvocation(
                query: query,
                sessionID: sessionID,
                pid: pid,
                scope: scope,
                includeMenus: includeMenus,
                limit: limit,
                bypassCache: bypassCache
            )
        )
        let nextSnapshot = queuedSearchSnapshots.isEmpty ? snapshot : queuedSearchSnapshots.removeFirst()
        guard var snapshot = nextSnapshot else { return nil }
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
        pid: pid_t?,
        labelAlphabet _: String,
        sessionID: String?,
        snapshotID: String?,
        scope: UISearchScope,
        includeMenus: Bool
    ) -> UITargetLookupResult? {
        targetLookupInvocations.append(
            TargetLookupInvocation(
                id: id,
                sessionID: sessionID,
                snapshotID: snapshotID,
                pid: pid,
                scope: scope,
                includeMenus: includeMenus
            )
        )
        guard let resolvedTarget = targetsByID[id] ?? snapshot?.targets.first(where: { $0.id == id }) else {
            return nil
        }
        return UITargetLookupResult(target: resolvedTarget, metrics: sessionMetrics)
    }

    func endSession(id: String?) -> UISessionMetrics? {
        endSessionCalls.append(id)
        return sessionMetrics
    }

    func sessionSnapshot(id: String?) -> TargetSnapshot? {
        guard id != nil else { return nil }
        guard var snapshot = sessionSnapshotValue ?? snapshot else { return nil }
        snapshot.sessionID = sessionMetrics.sessionID
        snapshot.snapshotID = sessionMetrics.snapshotID
        return snapshot
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
        var matchedWindow: VisibleWindow?
        var visibleWindowsValue: [VisibleWindow] = []

        init(excludeRule: ExcludedWindowRule? = nil) {
            self.excludeRuleValue = excludeRule
        }

        func visibleWindows(excluding _: [ExcludedWindowRule]) -> [VisibleWindow] {
            visibleWindowsValue
        }

    func focus(windowID: Int?, title: String?, pid: Int32?) -> Bool {
        focusCalls.append((windowID, title, pid))
        return true
    }

    func excludeRule(windowID _: Int?, title _: String?, pid _: Int32?, excluding _: [ExcludedWindowRule]) -> ExcludedWindowRule? {
        excludeRuleValue
    }

    func matchingWindow(windowID _: Int?, title _: String?, query _: String?, pid _: Int32?, excluding _: [ExcludedWindowRule]) -> VisibleWindow? {
        matchedWindow
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
        if var capture {
            capture.context = context
            self.capture = capture
        }
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

private actor RecordingSleeperStub: AutomationSleeping {
    private(set) var sleeps: [Int] = []

    func sleep(milliseconds: Int) async {
        sleeps.append(milliseconds)
        guard milliseconds > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }

    func recordedSleeps() -> [Int] {
        sleeps
    }
}

private actor ScreenMediaControllerStub: ScreenMediaControlling {
    private(set) var screenshotInvocationPayloads: [ScreenshotCaptureRequest] = []
    private(set) var recordingInvocationPayloads: [ScreenRecordingRequest] = []
    private(set) var streamInvocationPayloads: [ScreenStreamRequest] = []

    var screenshotResult: ScreenMediaOperationResult
    var recordingResult: ScreenMediaOperationResult
    var recordingStatusResult: ScreenMediaOperationResult
    var recordingStopResult: ScreenMediaOperationResult
    var streamStartResult: ScreenMediaOperationResult
    var streamStatusResult: ScreenMediaOperationResult
    var streamStopResult: ScreenMediaOperationResult

    init(
        screenshotResult: ScreenMediaOperationResult = ScreenMediaOperationResult(
            outcome: .success,
            message: "Captured screenshot.",
            payload: nil
        ),
        recordingResult: ScreenMediaOperationResult = ScreenMediaOperationResult(
            outcome: .success,
            message: "Started screen recording.",
            payload: nil
        ),
        recordingStatusResult: ScreenMediaOperationResult = ScreenMediaOperationResult(
            outcome: .success,
            message: "Recording is active.",
            payload: nil
        ),
        recordingStopResult: ScreenMediaOperationResult = ScreenMediaOperationResult(
            outcome: .success,
            message: "Stopped screen recording.",
            payload: nil
        ),
        streamStartResult: ScreenMediaOperationResult = ScreenMediaOperationResult(
            outcome: .success,
            message: "Started local screen stream.",
            payload: nil
        ),
        streamStatusResult: ScreenMediaOperationResult = ScreenMediaOperationResult(
            outcome: .success,
            message: "Stream is active.",
            payload: nil
        ),
        streamStopResult: ScreenMediaOperationResult = ScreenMediaOperationResult(
            outcome: .success,
            message: "Stopped local screen stream.",
            payload: nil
        )
    ) {
        self.screenshotResult = screenshotResult
        self.recordingResult = recordingResult
        self.recordingStatusResult = recordingStatusResult
        self.recordingStopResult = recordingStopResult
        self.streamStartResult = streamStartResult
        self.streamStatusResult = streamStatusResult
        self.streamStopResult = streamStopResult
    }

    func screenshot(_ request: ScreenshotCaptureRequest) async -> ScreenMediaOperationResult {
        screenshotInvocationPayloads.append(request)
        return screenshotResult
    }

    func startRecording(_ request: ScreenRecordingRequest) async -> ScreenMediaOperationResult {
        recordingInvocationPayloads.append(request)
        return recordingResult
    }

    func stopRecording(sessionID _: String?) async -> ScreenMediaOperationResult {
        recordingStopResult
    }

    func recordingStatus(sessionID _: String?) async -> ScreenMediaOperationResult {
        recordingStatusResult
    }

    func startStream(_ request: ScreenStreamRequest) async -> ScreenMediaOperationResult {
        streamInvocationPayloads.append(request)
        return streamStartResult
    }

    func stopStream(sessionID _: String?) async -> ScreenMediaOperationResult {
        streamStopResult
    }

    func streamStatus(sessionID _: String?) async -> ScreenMediaOperationResult {
        streamStatusResult
    }

    func screenshotRequests() -> [ScreenshotCaptureRequest] {
        screenshotInvocationPayloads
    }

    func recordingRequests() -> [ScreenRecordingRequest] {
        recordingInvocationPayloads
    }

    func streamRequests() -> [ScreenStreamRequest] {
        streamInvocationPayloads
    }
}

private actor ShellRunnerStub: ShellRunning {
    struct Invocation: Equatable {
        var launchPath: String
        var arguments: [String]
        var timeout: TimeInterval
    }

    var result = CommandResult(stdout: "true\n", stderr: "", terminationStatus: 0)
    private var invocations: [Invocation] = []

    func run(launchPath: String, arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        invocations.append(Invocation(launchPath: launchPath, arguments: arguments, timeout: timeout))
        return result
    }

    func recordedInvocations() -> [Invocation] {
        invocations
    }
}

private final class RecordingScrollPerformer: ScrollEventPerforming {
    private(set) var calls: [(direction: String, amount: Int, point: CGPoint)] = []

    func scroll(direction: String, amount: Int, at point: CGPoint) -> Bool {
        calls.append((direction, amount, point))
        return true
    }
}
