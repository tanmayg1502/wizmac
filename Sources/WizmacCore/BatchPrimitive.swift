import CoreGraphics
import Foundation

/// A low-level primitive representing a single automatable operation.
/// Consecutive `.cgEventMergeable` primitives can be coalesced into a single
/// burst submission, dramatically reducing per-event overhead.
public enum BatchPrimitive: Sendable {
    /// A CG event that can be merged with adjacent mergeable events into a burst.
    case cgEventMergeable(CGEventSpec)
    /// A CG event that forces a flush of any pending mergeable buffer before executing.
    case cgEventBarrier(CGEventSpec)
    /// A host-side sleep (e.g., inter-step delay).
    case hostSleep(TimeInterval)
    /// An accessibility query or read-only action that doesn't produce CG events.
    /// These are dispatched through the normal tool routing path.
    case toolDispatch(ToolDispatchSpec)
}

/// Specification for a CG event to be posted.
public struct CGEventSpec: Sendable, Equatable {
    public enum Kind: String, Sendable, Codable, Equatable {
        case pointerMove
        case pointerClick
        case pointerDoubleClick
        case pointerRightClick
        case pointerDrag
        case keyDown
        case keyUp
        case scrollWheel
    }

    public var kind: Kind
    public var point: CGPoint?
    public var endPoint: CGPoint? // for drag
    public var dragSteps: Int?
    public var clickState: Int64?
    public var button: CGMouseButton?
    public var keyCode: CGKeyCode?
    public var characters: String?
    public var modifiers: CGEventFlags?
    public var scrollDirection: String?
    public var scrollAmount: Int?

    public init(kind: Kind) {
        self.kind = kind
    }

    // MARK: - Convenience constructors

    public static func click(
        at point: CGPoint,
        clickState: Int64 = 1,
        button: CGMouseButton = .left
    ) -> CGEventSpec {
        var spec = CGEventSpec(kind: .pointerClick)
        spec.point = point
        spec.clickState = clickState
        spec.button = button
        return spec
    }

    public static func doubleClick(at point: CGPoint) -> CGEventSpec {
        var spec = CGEventSpec(kind: .pointerDoubleClick)
        spec.point = point
        spec.clickState = 2
        spec.button = .left
        return spec
    }

    public static func rightClick(at point: CGPoint) -> CGEventSpec {
        var spec = CGEventSpec(kind: .pointerRightClick)
        spec.point = point
        spec.clickState = 1
        spec.button = .right
        return spec
    }

    public static func move(to point: CGPoint) -> CGEventSpec {
        var spec = CGEventSpec(kind: .pointerMove)
        spec.point = point
        return spec
    }

    public static func drag(from start: CGPoint, to end: CGPoint, steps: Int = 8) -> CGEventSpec {
        var spec = CGEventSpec(kind: .pointerDrag)
        spec.point = start
        spec.endPoint = end
        spec.dragSteps = steps
        return spec
    }

    public static func keyPress(
        keyCode: CGKeyCode,
        characters: String = "",
        modifiers: CGEventFlags = []
    ) -> CGEventSpec {
        var spec = CGEventSpec(kind: .keyDown)
        spec.keyCode = keyCode
        spec.characters = characters
        spec.modifiers = modifiers
        return spec
    }

    public static func scroll(direction: String, amount: Int, at point: CGPoint) -> CGEventSpec {
        var spec = CGEventSpec(kind: .scrollWheel)
        spec.scrollDirection = direction
        spec.scrollAmount = amount
        spec.point = point
        return spec
    }
}

/// Specification for a tool dispatch (non-CG-event action like ui.search).
public struct ToolDispatchSpec: Sendable {
    public var toolName: String
    public var arguments: [String: JSONValue]

    public init(toolName: String, arguments: [String: JSONValue]) {
        self.toolName = toolName
        self.arguments = arguments
    }
}

/// Result of executing a batch plan.
public struct BatchPlanResult: Sendable {
    public struct StepResult: Sendable {
        public var index: Int
        public var action: String
        public var startedAt: Date
        public var endedAt: Date
        public var succeeded: Bool
        public var actionResult: ActionResult?
        public var error: String?
        public var primitiveCount: Int
        public var mergedCount: Int // how many were coalesced in bursts

        public init(
            index: Int,
            action: String,
            startedAt: Date,
            endedAt: Date,
            succeeded: Bool,
            actionResult: ActionResult? = nil,
            error: String? = nil,
            primitiveCount: Int = 0,
            mergedCount: Int = 0
        ) {
            self.index = index
            self.action = action
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.succeeded = succeeded
            self.actionResult = actionResult
            self.error = error
            self.primitiveCount = primitiveCount
            self.mergedCount = mergedCount
        }
    }

    public var stepResults: [StepResult]
    public var totalPrimitives: Int
    public var totalMerged: Int
    public var overallSucceeded: Bool

    public init(
        stepResults: [StepResult],
        totalPrimitives: Int = 0,
        totalMerged: Int = 0,
        overallSucceeded: Bool = true
    ) {
        self.stepResults = stepResults
        self.totalPrimitives = totalPrimitives
        self.totalMerged = totalMerged
        self.overallSucceeded = overallSucceeded
    }
}
