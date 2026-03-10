import ApplicationServices
import Foundation
import XCTest
@testable import WizmacSystem
import WizmacTextMode

final class TextModeRuntimeCoordinatorTests: XCTestCase {
    func testRuntimeCoordinatorProcessesCapturedEventsWithLibVimBackend() async throws {
        let capture = TestableGlobalInputCapture()
        let bridge = RuntimeFocusedTextBridgeStub(
            capture: FocusedTextCapture(element: nil, context: sampleContext())
        )
        let sink = RuntimeDecisionRecorder()
        let coordinator = TextModeRuntimeCoordinator(
            capture: capture,
            textService: TextModeService(engine: LibVimTextModeEngine()),
            focusedTextBridge: bridge,
            decisionSink: { decision, _ in
                Task { await sink.record(decision) }
            }
        )

        _ = try await coordinator.attachToFocusedContext()
        await coordinator.start()
        capture.emit(GlobalInputTranslator.event(kind: .keyDown, keyCode: 34, characters: "i"))
        capture.emit(GlobalInputTranslator.event(kind: .keyDown, keyCode: 53, characters: "\u{1b}"))
        try await Task.sleep(for: .milliseconds(60))

        let snapshot = await coordinator.snapshot()
        let decisions = await sink.decisions()

        XCTAssertEqual(snapshot.backend, .libvim)
        XCTAssertEqual(snapshot.captureState, .attached)
        XCTAssertNil(snapshot.bypassReason)
        XCTAssertEqual(decisions.count, 2)
    }

    func testRuntimeCoordinatorBypassesSecureInputContexts() async throws {
        let capture = TestableGlobalInputCapture()
        let bridge = RuntimeFocusedTextBridgeStub(
            capture: FocusedTextCapture(element: nil, context: sampleContext(isSecureInput: true))
        )
        let coordinator = TextModeRuntimeCoordinator(
            capture: capture,
            textService: TextModeService(engine: LibVimTextModeEngine()),
            focusedTextBridge: bridge
        )

        _ = try await coordinator.attachToFocusedContext()
        await coordinator.start()
        capture.emit(GlobalInputTranslator.event(kind: .keyDown, keyCode: 34, characters: "i"))
        try await Task.sleep(for: .milliseconds(30))

        let snapshot = await coordinator.snapshot()

        XCTAssertEqual(snapshot.captureState, .bypassed)
        XCTAssertEqual(snapshot.bypassReason, .secureInput)
        XCTAssertTrue(snapshot.isSecureInput)
    }

    func testRuntimeCoordinatorManualBypassToggleCanBeCleared() async throws {
        let capture = TestableGlobalInputCapture()
        let bridge = RuntimeFocusedTextBridgeStub(
            capture: FocusedTextCapture(element: nil, context: sampleContext())
        )
        let coordinator = TextModeRuntimeCoordinator(
            capture: capture,
            textService: TextModeService(engine: LibVimTextModeEngine()),
            focusedTextBridge: bridge
        )

        _ = try await coordinator.attachToFocusedContext()
        await coordinator.start()
        let bypassEvent = GlobalInputTranslator.event(
            kind: .keyDown,
            keyCode: 53,
            characters: "\u{1b}",
            modifiers: [.control]
        )

        capture.emit(bypassEvent)
        try await Task.sleep(for: .milliseconds(20))
        let bypassed = await coordinator.snapshot()

        capture.emit(bypassEvent)
        try await Task.sleep(for: .milliseconds(20))
        let restored = await coordinator.snapshot()

        XCTAssertEqual(bypassed.captureState, .bypassed)
        XCTAssertEqual(bypassed.bypassReason, .manualBypass)
        XCTAssertEqual(restored.captureState, .attached)
        XCTAssertNil(restored.bypassReason)
    }
}

private final class RuntimeFocusedTextBridgeStub: FocusedTextBridging, @unchecked Sendable {
    var currentCapture: FocusedTextCapture?

    init(capture: FocusedTextCapture?) {
        self.currentCapture = capture
    }

    func captureFocusedContext() -> FocusedTextCapture? {
        currentCapture
    }

    func sync(context: TextContextSnapshot, onto _: AXUIElement?) {
        if var currentCapture {
            currentCapture.context = context
            self.currentCapture = currentCapture
        }
    }

    func apply(
        commands _: [TextModeCommand],
        for _: TextKeyEvent,
        to _: AXUIElement?,
        context _: inout TextContextSnapshot
    ) {}
}

private actor RuntimeDecisionRecorder {
    private var recorded: [TextModeDecision] = []

    func record(_ decision: TextModeDecision) {
        recorded.append(decision)
    }

    func decisions() -> [TextModeDecision] {
        recorded
    }
}

private func sampleContext(isSecureInput: Bool = false) -> TextContextSnapshot {
    TextContextSnapshot(
        applicationBundleID: "com.example.fixture",
        applicationName: "FixtureHost",
        processIdentifier: 42,
        elementIdentifier: "runtime-editor",
        windowTitle: "Fixture",
        text: "hello world",
        cursor: TextCursorSnapshot(range: TextRange(location: 0, length: 0)),
        isSecureInput: isSecureInput
    )
}
