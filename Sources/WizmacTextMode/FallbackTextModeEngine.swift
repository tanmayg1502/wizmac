import Foundation

public actor FallbackTextModeEngine: TextModeEngine {
    fileprivate struct AttachmentState: Sendable {
        var context: TextContextSnapshot
        var state: TextModeState
    }

    private var attachmentsByID: [TextAttachmentID: AttachmentState] = [:]

    public init() {}

    public func attach(context: TextContextSnapshot) async throws -> TextAttachment {
        let id = TextAttachmentID()
        let mode: TextInputMode = context.isSecureInput ? .disabled : .normal
        let state = TextModeState(
            attachmentID: id,
            backend: .fallback,
            mode: mode,
            cursor: context.cursor,
            isSecureInput: context.isSecureInput
        )
        attachmentsByID[id] = AttachmentState(context: context, state: state)
        return TextAttachment(id: id, context: context, state: state)
    }

    public func detach(attachmentID: TextAttachmentID) async {
        attachmentsByID.removeValue(forKey: attachmentID)
    }

    public func sync(context: TextContextSnapshot, attachmentID: TextAttachmentID) async throws -> TextModeState {
        guard var attachment = attachmentsByID[attachmentID] else {
            throw TextModeEngineError.attachmentNotFound(attachmentID)
        }

        attachment.context = context
        attachment.state.cursor = context.cursor
        attachment.state.isSecureInput = context.isSecureInput
        attachment.state.lastSyncedAt = context.updatedAt
        if attachment.state.mode == .disabled && context.isSecureInput == false {
            attachment.state.lastMode = attachment.state.mode
            attachment.state.mode = .normal
        } else if context.isSecureInput {
            attachment.state.lastMode = attachment.state.mode
            attachment.state.mode = .disabled
        }

        attachmentsByID[attachmentID] = attachment
        return attachment.state
    }

    public func handle(event: TextKeyEvent, attachmentID: TextAttachmentID) async throws -> TextModeDecision {
        guard var attachment = attachmentsByID[attachmentID] else {
            throw TextModeEngineError.attachmentNotFound(attachmentID)
        }

        TextModeReducer.ingest(event, into: &attachment.state)
        let decision = TextModeReducer.reduce(event: event, state: &attachment.state)
        TextModeReducer.record(decision, in: &attachment.state)
        attachmentsByID[attachmentID] = attachment
        return TextModeDecision(state: attachment.state, effects: decision.effects, commands: decision.commands)
    }

    public func state(for attachmentID: TextAttachmentID) async -> TextModeState? {
        attachmentsByID[attachmentID]?.state
    }

    public func attachments() async -> [TextAttachment] {
        attachmentsByID.values.map { attachment in
            TextAttachment(id: attachment.state.attachmentID, context: attachment.context, state: attachment.state)
        }
    }
}
