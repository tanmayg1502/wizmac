import Foundation
import WizmacCore

public enum WizmacRuntimeFactory {
    public static func makeCommandBus(
        trustedSessionStore: TrustedAutomationSessionStore? = nil
    ) throws -> CommandBus {
        let settingsStore = try SettingsStore()
        let auditStore = try AuditStore()
        let approvalStore = try ApprovalStore()
        let executor = MacAutomationExecutor(settingsStore: settingsStore, auditStore: auditStore)
        let approvalPolicy = ApprovalPolicy(
            settingsStore: settingsStore,
            trustedSessionStore: trustedSessionStore
        )

        return CommandBus(
            executor: executor,
            auditStore: auditStore,
            approvalStore: approvalStore,
            approvalPolicy: approvalPolicy
        )
    }
}
