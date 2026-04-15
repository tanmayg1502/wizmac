import Foundation
import WizmacCore

/// Executes batch steps with optimizations:
/// 1. Suppresses post-action state refresh for consecutive mutation steps
/// 2. Skips inter-step delays for mutation sequences
/// 3. Tracks primitive/merge counts for observability
public final class BatchPlanRunner: @unchecked Sendable {

    /// Actions that are pure mutations and don't need post-state refresh mid-batch.
    private static let mutationActions: Set<String> = [
        "ui.act", "ui.open", "ui.select", "ui.toggle", "ui.focus", "ui.submit",
        "ui.choose_file", "ui.drag", "ui.gesture",
        "input.key_combo", "input.key_sequence",
        "text.insert", "text.send_keys",
        "scroll.step", "scroll.to",
    ]

    /// Actions that are read-only and safe to parallelize (future use).
    private static let readOnlyActions: Set<String> = [
        "ui.search", "ui.read", "ui.capture", "ui.hints", "ui.apps",
        "ui.assert", "ui.diff", "ui.prefetch",
        "window.list", "window.assert",
        "scroll.targets",
        "system.permissions", "system.audit", "system.health",
        "media.screenshot",
    ]

    private let callTool: @Sendable (
        String, [String: StructuredValue], ControlPlaneSource
    ) async -> ControlPlaneActionResponse

    public init(
        callTool: @escaping @Sendable (
            String, [String: StructuredValue], ControlPlaneSource
        ) async -> ControlPlaneActionResponse
    ) {
        self.callTool = callTool
    }

    // MARK: - Step I/O

    public struct StepInput: Sendable {
        public var index: Int
        public var action: String
        public var arguments: [String: StructuredValue]

        public init(index: Int, action: String, arguments: [String: StructuredValue]) {
            self.index = index
            self.action = action
            self.arguments = arguments
        }
    }

    public struct StepOutput: Sendable {
        public var index: Int
        public var action: String
        public var startedAt: Date
        public var endedAt: Date
        public var response: ControlPlaneActionResponse
        /// Whether this step was optimized with fast-path arguments.
        public var fastPath: Bool

        public init(
            index: Int,
            action: String,
            startedAt: Date,
            endedAt: Date,
            response: ControlPlaneActionResponse,
            fastPath: Bool
        ) {
            self.index = index
            self.action = action
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.response = response
            self.fastPath = fastPath
        }
    }

    // MARK: - Execution

    /// Execute a sequence of batch steps with optimizations.
    ///
    /// Consecutive mutation steps get `_batchFastPath=true` injected (except the last
    /// in a run) to signal the executor to skip post-state refresh and reduce delays.
    public func execute(
        steps: [StepInput],
        source: ControlPlaneSource,
        failFast: Bool
    ) async -> (outputs: [StepOutput], overallSucceeded: Bool) {
        var outputs: [StepOutput] = []
        var overallSucceeded = true

        // Pre-compute which steps are in a mutation run and should get fast-path
        let fastPathFlags = computeFastPathFlags(steps: steps)

        for step in steps {
            let isFastPath = fastPathFlags[step.index] ?? false
            var arguments = step.arguments

            if isFastPath {
                // Tell executor to skip post-state refresh and minimize delays
                arguments["_batchFastPath"] = .bool(true)
                arguments["postState"] = .string("none")
                // Zero out pre/post delays for mid-sequence steps
                if arguments["preDelayMs"] == nil {
                    arguments["preDelayMs"] = .number(0)
                }
                if arguments["postDelayMs"] == nil {
                    arguments["postDelayMs"] = .number(0)
                }
            }

            let startedAt = Date()
            let response = await callTool(step.action, arguments, source)
            let endedAt = Date()

            let output = StepOutput(
                index: step.index,
                action: step.action,
                startedAt: startedAt,
                endedAt: endedAt,
                response: response,
                fastPath: isFastPath
            )
            outputs.append(output)

            if response.status != .success {
                overallSucceeded = false
                if failFast { break }
            }
        }

        return (outputs, overallSucceeded)
    }

    // MARK: - Classification

    /// Returns whether a given action name is a mutation action.
    public static func isMutation(_ action: String) -> Bool {
        mutationActions.contains(action)
    }

    /// Returns whether a given action name is a read-only action.
    public static func isReadOnly(_ action: String) -> Bool {
        readOnlyActions.contains(action)
    }

    // MARK: - Fast-path computation

    /// For a sequence like [mutation, mutation, mutation, read, mutation, mutation]:
    /// Mark indices 0, 1 as fast-path (but NOT 2, since it's the last mutation before a read).
    /// Mark index 4 as fast-path (but NOT 5, last in sequence).
    private func computeFastPathFlags(steps: [StepInput]) -> [Int: Bool] {
        var flags: [Int: Bool] = [:]
        let count = steps.count

        for i in 0..<count {
            let isMutation = Self.mutationActions.contains(steps[i].action)
            if !isMutation {
                flags[steps[i].index] = false
                continue
            }

            // Check if the next step is also a mutation
            let nextIsMutation = (i + 1 < count)
                && Self.mutationActions.contains(steps[i + 1].action)

            // Fast-path if this is a mutation AND the next step is also a mutation
            // (i.e., we're not the last mutation in a consecutive run)
            flags[steps[i].index] = nextIsMutation
        }

        return flags
    }
}
