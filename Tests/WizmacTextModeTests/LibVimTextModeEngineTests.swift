import Foundation
import Testing
@testable import WizmacTextMode

@Suite(.serialized)
struct LibVimTextModeEngineTests {
    @Test
    func availabilityReportsEmbeddedLibVimBackend() {
        let availability = LibVimEngineFactory.availability()

        #expect(availability.backend == .libvim)
        #expect(availability.isAvailable)
    }

    @Test
    func libVimEngineAttachStartsInNormalMode() async throws {
        let engine = LibVimTextModeEngine()
        let attachment = try await engine.attach(context: sampleContext())

        #expect(attachment.state.backend == .libvim)
        #expect(attachment.state.mode == .normal)
    }

    @Test
    func defaultServiceUsesLibVimBackend() async throws {
        unsetenv("WIZMAC_TEXTMODE_ENGINE")
        unsetenv("WIZMAC_TEXTMODE_EMERGENCY_FALLBACK")

        let service = TextModeService()
        let attachment = try await service.attach(context: sampleContext())

        #expect(attachment.state.backend == .libvim)
    }

    @Test
    func emergencyFallbackEnvironmentSwitchUsesFallbackEngine() async throws {
        setenv("WIZMAC_TEXTMODE_EMERGENCY_FALLBACK", "1", 1)
        defer { unsetenv("WIZMAC_TEXTMODE_EMERGENCY_FALLBACK") }

        let service = TextModeService()
        let attachment = try await service.attach(context: sampleContext())

        #expect(attachment.state.backend == .fallback)
    }

    @Test
    func libVimEngineTracksModeTransitionsAndShimFeed() async throws {
        let engine = LibVimTextModeEngine()
        let attachment = try await engine.attach(context: sampleContext())

        _ = try await engine.handle(event: .character("i"), attachmentID: attachment.id)
        let decision = try await engine.handle(event: .special(.escape), attachmentID: attachment.id)
        let shimSnapshot = await engine.shimSnapshot(for: attachment.id)

        #expect(decision.state.backend == .libvim)
        #expect(decision.state.mode == .normal)
        #expect(shimSnapshot?.fedKeyCount == 2)
        #expect(shimSnapshot?.bufferedKeys == ["i", "<escape>"])
    }
}

private func sampleContext() -> TextContextSnapshot {
    TextContextSnapshot(
        applicationBundleID: "com.example.fixture",
        applicationName: "FixtureHost",
        processIdentifier: 42,
        elementIdentifier: "editor-1",
        windowTitle: "Fixture",
        text: "hello world",
        cursor: TextCursorSnapshot(range: TextRange(location: 0, length: 0))
    )
}
