import Foundation
import Testing
@testable import WizmacTextMode

struct FallbackTextModeEngineTests {
    @Test
    func attachStartsInNormalMode() async throws {
        let engine = FallbackTextModeEngine()
        let attachment = try await engine.attach(context: sampleContext())

        #expect(attachment.state.backend == .fallback)
        #expect(attachment.state.mode == .normal)
        #expect(attachment.state.queuedKeys.isEmpty)
    }

    @Test
    func escapeLeavesInsertMode() async throws {
        let engine = FallbackTextModeEngine()
        let attachment = try await engine.attach(context: sampleContext())

        _ = try await engine.handle(event: .character("i"), attachmentID: attachment.id)
        let decision = try await engine.handle(event: .special(.escape), attachmentID: attachment.id)

        #expect(decision.state.mode == .normal)
        #expect(decision.commands.contains(.setMode(.normal)))
        #expect(decision.shouldForwardEvent == false)
    }

    @Test
    func motionCountIsAppliedToNormalModeMoves() async throws {
        let engine = FallbackTextModeEngine()
        let attachment = try await engine.attach(context: sampleContext())

        _ = try await engine.handle(event: .character("3"), attachmentID: attachment.id)
        let decision = try await engine.handle(event: .character("w"), attachmentID: attachment.id)

        #expect(decision.commands == [.moveCursor(.wordForward, count: 3, extendSelection: false)])
        #expect(decision.state.pendingCount == nil)
    }

    @Test
    func operatorPendingProducesCombinedCommand() async throws {
        let engine = FallbackTextModeEngine()
        let attachment = try await engine.attach(context: sampleContext())

        _ = try await engine.handle(event: .character("d"), attachmentID: attachment.id)
        let decision = try await engine.handle(event: .character("w"), attachmentID: attachment.id)

        #expect(decision.commands.contains(.applyOperator(.delete, motion: .wordForward, count: 1)))
        #expect(decision.state.mode == .normal)
    }

    @Test
    func commandModeBuffersUntilEnter() async throws {
        let engine = FallbackTextModeEngine()
        let attachment = try await engine.attach(context: sampleContext())

        _ = try await engine.handle(event: .character(":"), attachmentID: attachment.id)
        _ = try await engine.handle(event: .character("w"), attachmentID: attachment.id)
        _ = try await engine.handle(event: .character("q"), attachmentID: attachment.id)
        let decision = try await engine.handle(event: .special(.enter), attachmentID: attachment.id)

        #expect(decision.commands.contains(.submitCommandLine("wq")))
        #expect(decision.state.mode == .normal)
    }

    @Test
    func secureInputPassesThroughEvenWhenAttached() async throws {
        let engine = FallbackTextModeEngine()
        let attachment = try await engine.attach(context: sampleContext(isSecureInput: true))

        let decision = try await engine.handle(event: .character("i"), attachmentID: attachment.id)

        #expect(decision.shouldForwardEvent)
        #expect(decision.commands.isEmpty)
        #expect(decision.state.mode == .disabled)
    }

    @Test
    func serviceDelegatesToEngine() async throws {
        let service = TextModeService(engine: FallbackTextModeEngine())
        let attachment = try await service.attach(context: sampleContext())
        let decision = try await service.handle(event: .character("v"), attachmentID: attachment.id)
        let state = await service.state(for: attachment.id)

        #expect(decision.state.mode == .visual)
        #expect(state?.mode == .visual)
    }
}

private func sampleContext(isSecureInput: Bool = false) -> TextContextSnapshot {
    TextContextSnapshot(
        applicationBundleID: "com.example.fixture",
        applicationName: "FixtureHost",
        processIdentifier: 42,
        elementIdentifier: "editor-1",
        windowTitle: "Fixture",
        text: "hello world",
        cursor: TextCursorSnapshot(range: TextRange(location: 0, length: 0)),
        isSecureInput: isSecureInput
    )
}
