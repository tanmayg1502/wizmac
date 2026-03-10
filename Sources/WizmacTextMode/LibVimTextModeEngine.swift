import Foundation

public actor LibVimTextModeEngine: TextModeEngine {
    private struct AttachmentState: Sendable {
        var context: TextContextSnapshot
        var state: TextModeState
        var shim: EmbeddedLibVimSession
    }

    private var attachmentsByID: [TextAttachmentID: AttachmentState] = [:]

    public init() {}

    public func attach(context: TextContextSnapshot) async throws -> TextAttachment {
        let id = TextAttachmentID()
        let mode: TextInputMode = context.isSecureInput ? .disabled : .normal
        let state = TextModeState(
            attachmentID: id,
            backend: .libvim,
            mode: mode,
            cursor: context.cursor,
            isSecureInput: context.isSecureInput
        )
        let shim = EmbeddedLibVimSession()
        shim.sync(context: context)
        attachmentsByID[id] = AttachmentState(context: context, state: state, shim: shim)
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
        attachment.shim.sync(context: context)

        attachmentsByID[attachmentID] = attachment
        return attachment.state
    }

    public func handle(event: TextKeyEvent, attachmentID: TextAttachmentID) async throws -> TextModeDecision {
        guard var attachment = attachmentsByID[attachmentID] else {
            throw TextModeEngineError.attachmentNotFound(attachmentID)
        }

        let decision = attachment.shim.feed(event, state: &attachment.state)
        attachmentsByID[attachmentID] = attachment
        return decision
    }

    public func state(for attachmentID: TextAttachmentID) async -> TextModeState? {
        attachmentsByID[attachmentID]?.state
    }

    public func attachments() async -> [TextAttachment] {
        attachmentsByID.values.map { attachment in
            TextAttachment(id: attachment.state.attachmentID, context: attachment.context, state: attachment.state)
        }
    }

    public func shimSnapshot(for attachmentID: TextAttachmentID) async -> LibVimShimSnapshot? {
        guard let attachment = attachmentsByID[attachmentID] else { return nil }
        return attachment.shim.snapshot(currentMode: attachment.state.mode)
    }
}
