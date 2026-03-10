import Foundation

public actor ApprovalPolicy {
    private let settingsStore: SettingsStore
    private let trustedSessionStore: TrustedAutomationSessionStore?

    public init(
        settingsStore: SettingsStore,
        trustedSessionStore: TrustedAutomationSessionStore? = nil
    ) {
        self.settingsStore = settingsStore
        self.trustedSessionStore = trustedSessionStore
    }

    public func evaluate(_ request: ActionRequest) async throws -> ApprovalRequest? {
        if request.origin.kind == .menuBar || request.origin.kind == .hotkey || request.origin.kind == .test {
            return nil
        }

        let settings = try await settingsStore.load()

        if settings.autoApprovedActions.contains(request.action) {
            return nil
        }

        if await trustedSessionStore?.allows(request) == true {
            return nil
        }

        guard settings.riskyActions.contains(request.action) else {
            return nil
        }

        let summary = [
            request.action.rawValue,
            request.arguments["targetID"]?.stringValue,
            request.arguments["device"]?.stringValue,
            request.arguments["trustedSessionID"]?.stringValue.map { _ in "<trusted-session>" },
            request.arguments["text"]?.stringValue.map { _ in "<text>" },
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        return ApprovalRequest(
            actionRequestID: request.id,
            action: request.action,
            reason: "This action changes system state and requires explicit approval.",
            summary: summary.isEmpty ? request.action.rawValue : summary
        )
    }
}
