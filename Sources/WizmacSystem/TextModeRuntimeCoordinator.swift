import ApplicationServices
import Foundation
import WizmacTextMode

public typealias TextModeDecisionSink = @Sendable (TextModeDecision, TextContextSnapshot) -> Void

public actor TextModeRuntimeCoordinator {
    private let capture: any GlobalInputCapturing
    private let textService: TextModeService
    private let focusedTextBridge: any FocusedTextBridging
    private let configuration: TextRuntimeConfiguration
    private let decisionSink: TextModeDecisionSink?

    private var runtimeSnapshot: TextRuntimeSnapshot
    private var isRunning = false
    private var activeAttachmentID: TextAttachmentID?
    private var activeElement: AXUIElement?

    public init(
        capture: any GlobalInputCapturing = NSEventGlobalInputCapture(),
        textService: TextModeService = TextModeService(),
        focusedTextBridge: any FocusedTextBridging = FocusedTextBridge(),
        configuration: TextRuntimeConfiguration = TextRuntimeConfiguration(),
        decisionSink: TextModeDecisionSink? = nil
    ) {
        self.capture = capture
        self.textService = textService
        self.focusedTextBridge = focusedTextBridge
        self.configuration = configuration
        self.decisionSink = decisionSink
        self.runtimeSnapshot = TextRuntimeSnapshot(
            backend: configuration.emergencyFallbackEnabled ? .fallback : .libvim
        )
    }

    public func start() {
        guard isRunning == false else { return }
        let coordinator = self
        capture.start { event in
            Task {
                await coordinator.handleCapturedEvent(event)
            }
        }
        isRunning = true
    }

    public func stop() async {
        capture.stop()
        if let activeAttachmentID {
            await textService.detach(activeAttachmentID)
        }
        activeAttachmentID = nil
        activeElement = nil
        runtimeSnapshot.captureState = .idle
        runtimeSnapshot.bypassReason = nil
        runtimeSnapshot.attachmentID = nil
        runtimeSnapshot.applicationName = nil
        runtimeSnapshot.elementIdentifier = nil
        runtimeSnapshot.isSecureInput = false
        isRunning = false
    }

    @discardableResult
    public func attachToFocusedContext() async throws -> TextAttachment? {
        guard let capture = focusedTextBridge.captureFocusedContext() else {
            runtimeSnapshot.captureState = .bypassed
            runtimeSnapshot.bypassReason = .unavailableContext
            runtimeSnapshot.applicationName = nil
            runtimeSnapshot.elementIdentifier = nil
            return nil
        }

        let attachment = try await textService.attach(context: capture.context)
        activeAttachmentID = attachment.id
        activeElement = capture.element
        runtimeSnapshot.attachmentID = attachment.id
        runtimeSnapshot.applicationName = capture.context.applicationName
        runtimeSnapshot.elementIdentifier = capture.context.elementIdentifier
        runtimeSnapshot.isSecureInput = capture.context.isSecureInput
        runtimeSnapshot.captureState = capture.context.isSecureInput ? .bypassed : .attached
        runtimeSnapshot.bypassReason = capture.context.isSecureInput ? .secureInput : nil
        runtimeSnapshot.backend = attachment.state.backend
        return attachment
    }

    public func detach() async {
        guard let activeAttachmentID else { return }
        await textService.detach(activeAttachmentID)
        self.activeAttachmentID = nil
        self.activeElement = nil
        runtimeSnapshot.captureState = .idle
        runtimeSnapshot.bypassReason = nil
        runtimeSnapshot.attachmentID = nil
    }

    public func syncFocusedContext() async throws -> TextRuntimeSnapshot {
        guard let activeAttachmentID, let capture = focusedTextBridge.captureFocusedContext() else {
            runtimeSnapshot.captureState = .bypassed
            runtimeSnapshot.bypassReason = .unavailableContext
            return runtimeSnapshot
        }

        activeElement = capture.element
        let state = try await textService.sync(context: capture.context, attachmentID: activeAttachmentID)
        runtimeSnapshot.backend = state.backend
        runtimeSnapshot.applicationName = capture.context.applicationName
        runtimeSnapshot.elementIdentifier = capture.context.elementIdentifier
        runtimeSnapshot.isSecureInput = capture.context.isSecureInput
        runtimeSnapshot.captureState = capture.context.isSecureInput ? .bypassed : .attached
        runtimeSnapshot.bypassReason = capture.context.isSecureInput ? .secureInput : nil
        return runtimeSnapshot
    }

    public func snapshot() -> TextRuntimeSnapshot {
        runtimeSnapshot
    }

    public func handleCapturedEvent(_ event: GlobalKeyCaptureEvent) async {
        guard event.kind == .keyDown else { return }
        runtimeSnapshot.lastCapturedEventAt = event.timestamp

        if isBypassToggle(event.textEvent) {
            toggleManualBypass()
            return
        }

        if runtimeSnapshot.captureState == .bypassed, runtimeSnapshot.bypassReason == .manualBypass {
            return
        }

        do {
            let attachment = try await ensureAttachment()
            guard let attachment else { return }
            guard let capture = focusedTextBridge.captureFocusedContext() else {
                runtimeSnapshot.captureState = .bypassed
                runtimeSnapshot.bypassReason = .unavailableContext
                return
            }

            activeElement = capture.element
            var context = capture.context
            runtimeSnapshot.applicationName = context.applicationName
            runtimeSnapshot.elementIdentifier = context.elementIdentifier
            runtimeSnapshot.isSecureInput = context.isSecureInput
            runtimeSnapshot.attachmentID = attachment.id

            if configuration.synchronizeOnEveryEvent {
                _ = try await textService.sync(context: context, attachmentID: attachment.id)
            }

            if context.isSecureInput {
                runtimeSnapshot.captureState = .bypassed
                runtimeSnapshot.bypassReason = .secureInput
                return
            }

            let decision = try await textService.handle(event: event.textEvent, attachmentID: attachment.id)
            focusedTextBridge.apply(commands: decision.commands, for: event.textEvent, to: activeElement, context: &context)

            if configuration.synchronizeOnEveryEvent {
                _ = try await textService.sync(context: context, attachmentID: attachment.id)
            }

            if let status = await textService.status(for: attachment.id) {
                runtimeSnapshot.backend = status.backend
            }
            runtimeSnapshot.captureState = .attached
            runtimeSnapshot.bypassReason = nil
            decisionSink?(decision, context)
        } catch {
            runtimeSnapshot.captureState = .bypassed
            runtimeSnapshot.bypassReason = .unavailableContext
        }
    }
}

private extension TextModeRuntimeCoordinator {
    func ensureAttachment() async throws -> TextAttachment? {
        if let activeAttachmentID,
           let attachment = await textService.attachments().first(where: { $0.id == activeAttachmentID }) {
            return attachment
        }

        return try await attachToFocusedContext()
    }

    func isBypassToggle(_ event: TextKeyEvent) -> Bool {
        event.specialValue == configuration.bypassKey && event.modifiers == configuration.bypassModifiers
    }

    func toggleManualBypass() {
        if runtimeSnapshot.captureState == .bypassed, runtimeSnapshot.bypassReason == .manualBypass {
            runtimeSnapshot.captureState = activeAttachmentID == nil ? .idle : .attached
            runtimeSnapshot.bypassReason = nil
            return
        }

        runtimeSnapshot.captureState = .bypassed
        runtimeSnapshot.bypassReason = .manualBypass
    }
}
