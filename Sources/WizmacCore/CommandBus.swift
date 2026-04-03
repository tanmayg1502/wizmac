import Foundation

public protocol ActionExecutor: Sendable {
    func execute(_ request: ActionRequest) async -> ActionResult
}

public protocol ApprovalPreparingActionExecutor: ActionExecutor {
    func prepareForApproval(_ request: ActionRequest) async -> ActionRequest
}

public extension ApprovalPreparingActionExecutor {
    func prepareForApproval(_ request: ActionRequest) async -> ActionRequest {
        request
    }
}

public actor CommandBus {
    private let executor: ActionExecutor
    private let auditStore: AuditStore
    private let approvalStore: ApprovalStore
    private let approvalPolicy: ApprovalPolicy

    public init(
        executor: ActionExecutor,
        auditStore: AuditStore,
        approvalStore: ApprovalStore,
        approvalPolicy: ApprovalPolicy
    ) {
        self.executor = executor
        self.auditStore = auditStore
        self.approvalStore = approvalStore
        self.approvalPolicy = approvalPolicy
    }

    public func dispatch(_ request: ActionRequest) async -> ActionResult {
        do {
            let preparedRequest: ActionRequest
            if let approvalPreparingExecutor = executor as? ApprovalPreparingActionExecutor {
                preparedRequest = await approvalPreparingExecutor.prepareForApproval(request)
            } else {
                preparedRequest = request
            }

            if preparedRequest.action == .systemConfirmationStatus {
                if
                    let approvalID = preparedRequest.string(for: "approvalID"),
                    let decisionRaw = preparedRequest.string(for: "decision"),
                    let id = UUID(uuidString: approvalID),
                    let decision = ApprovalDecision(rawValue: decisionRaw)
                {
                    return await resolveApproval(id: id, decision: decision)
                }

                let records = try await approvalStore.list()
                return ActionResult(
                    requestID: preparedRequest.id,
                    action: preparedRequest.action,
                    outcome: .success,
                    message: "Fetched pending approvals.",
                    payload: .array(records.map { record in
                        [
                            "approvalID": .string(record.approval.id.uuidString),
                            "requestID": .string(record.request.id.uuidString),
                            "action": .string(record.request.action.rawValue),
                            "summary": .string(record.approval.summary),
                            "reason": .string(record.approval.reason),
                            "createdAt": .string(ISO8601DateFormatter().string(from: record.approval.createdAt)),
                        ]
                    })
                )
            }

            if let approval = try await approvalPolicy.evaluate(preparedRequest) {
                try await approvalStore.enqueue(PendingApprovalRecord(approval: approval, request: preparedRequest))
                let result = ActionResult.confirmationRequired(for: preparedRequest, approval: approval)
                try await auditStore.append(
                    AuditEntry(
                        request: preparedRequest,
                        outcome: result.outcome,
                        message: "Queued for approval: \(approval.summary)"
                    )
                )
                return result
            }

            let result = await executor.execute(preparedRequest)
            try await auditStore.append(
                AuditEntry(request: preparedRequest, outcome: result.outcome, message: result.message)
            )
            return result
        } catch {
            let result = ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .failed,
                message: error.localizedDescription
            )
            try? await auditStore.append(
                AuditEntry(request: request, outcome: result.outcome, message: result.message)
            )
            return result
        }
    }

    public func pendingApprovals() async -> [PendingApprovalRecord] {
        (try? await approvalStore.list()) ?? []
    }

    public func resolveApproval(id: UUID, decision: ApprovalDecision) async -> ActionResult {
        do {
            guard let record = try await approvalStore.resolve(id: id) else {
                return ActionResult(
                    requestID: UUID(),
                    action: .systemConfirmationStatus,
                    outcome: .notFound,
                    message: "No pending approval found for \(id.uuidString)."
                )
            }

            return await finalizeResolvedApproval(record, decision: decision)
        } catch {
            return ActionResult(
                requestID: UUID(),
                action: .systemConfirmationStatus,
                outcome: .failed,
                message: error.localizedDescription
            )
        }
    }

    public func finalizeResolvedApproval(
        _ record: PendingApprovalRecord,
        decision: ApprovalDecision
    ) async -> ActionResult {
        do {
            if decision == .reject {
                let result = ActionResult(
                    requestID: record.request.id,
                    action: record.request.action,
                    outcome: .failed,
                    message: "Action rejected."
                )
                try await auditStore.append(
                    AuditEntry(request: record.request, outcome: result.outcome, message: result.message)
                )
                return result
            }

            let result = await executor.execute(record.request)
            try await auditStore.append(
                AuditEntry(request: record.request, outcome: result.outcome, message: result.message)
            )
            return result
        } catch {
            let result = ActionResult(
                requestID: record.request.id,
                action: record.request.action,
                outcome: .failed,
                message: error.localizedDescription
            )
            try? await auditStore.append(
                AuditEntry(request: record.request, outcome: result.outcome, message: result.message)
            )
            return result
        }
    }
}
