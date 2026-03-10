import Foundation

public actor TextModeService {
    private let engine: any TextModeEngine

    public init(engine: any TextModeEngine) {
        self.engine = engine
    }

    public init(
        engine: (any TextModeEngine)? = nil,
        configuration: TextRuntimeConfiguration = TextRuntimeConfiguration()
    ) {
        self.engine = engine ?? LibVimEngineFactory.makeDefaultEngine(configuration: configuration)
    }

    public func attach(context: TextContextSnapshot) async throws -> TextAttachment {
        try await engine.attach(context: context)
    }

    public func detach(_ attachmentID: TextAttachmentID) async {
        await engine.detach(attachmentID: attachmentID)
    }

    public func detachAll() async {
        let attachments = await engine.attachments()
        for attachment in attachments {
            await engine.detach(attachmentID: attachment.id)
        }
    }

    public func sync(context: TextContextSnapshot, attachmentID: TextAttachmentID) async throws -> TextModeState {
        try await engine.sync(context: context, attachmentID: attachmentID)
    }

    public func handle(event: TextKeyEvent, attachmentID: TextAttachmentID) async throws -> TextModeDecision {
        try await engine.handle(event: event, attachmentID: attachmentID)
    }

    public func state(for attachmentID: TextAttachmentID) async -> TextModeState? {
        await engine.state(for: attachmentID)
    }

    public func attachments() async -> [TextAttachment] {
        await engine.attachments()
    }

    public func status(for attachmentID: TextAttachmentID) async -> TextSessionStatus? {
        guard let attachment = await engine.attachments().first(where: { $0.id == attachmentID }) else {
            return nil
        }
        return attachment.status
    }

    public func statuses() async -> [TextSessionStatus] {
        await engine.attachments().map(\.status)
    }

    public func engineAvailability() -> TextModeEngineAvailability {
        LibVimEngineFactory.availability()
    }
}
