import Foundation

public enum TextInputMode: String, Sendable, CaseIterable, Codable {
    case disabled
    case normal
    case insert
    case visual
    case visualLine
    case command
    case replace
    case operatorPending
}

public enum TextKeyModifier: String, Sendable, CaseIterable, Codable, Hashable {
    case control
    case option
    case shift
    case command
    case function
}

public enum TextSpecialKey: String, Sendable, CaseIterable, Codable {
    case escape
    case enter
    case tab
    case backspace
    case deleteForward
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case home
    case end
    case pageUp
    case pageDown
    case space
}

public struct TextKeyEvent: Sendable, Equatable, Codable {
    public enum Key: Sendable, Equatable, Codable {
        case character(String)
        case special(TextSpecialKey)
    }

    public var key: Key
    public var modifiers: Set<TextKeyModifier>
    public var timestamp: Date
    public var source: String?

    public init(
        key: Key,
        modifiers: Set<TextKeyModifier> = [],
        timestamp: Date = Date(),
        source: String? = nil
    ) {
        self.key = key
        self.modifiers = modifiers
        self.timestamp = timestamp
        self.source = source
    }

    public static func character(_ value: String, modifiers: Set<TextKeyModifier> = []) -> TextKeyEvent {
        TextKeyEvent(key: .character(value), modifiers: modifiers)
    }

    public static func special(_ value: TextSpecialKey, modifiers: Set<TextKeyModifier> = []) -> TextKeyEvent {
        TextKeyEvent(key: .special(value), modifiers: modifiers)
    }

    public var characterValue: String? {
        guard case let .character(value) = key else { return nil }
        return value
    }

    public var specialValue: TextSpecialKey? {
        guard case let .special(value) = key else { return nil }
        return value
    }
}

public struct TextRange: Sendable, Equatable, Codable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = max(0, location)
        self.length = max(0, length)
    }
}

public struct TextCursorSnapshot: Sendable, Equatable, Codable {
    public var range: TextRange
    public var preferredColumn: Int?

    public init(range: TextRange, preferredColumn: Int? = nil) {
        self.range = range
        self.preferredColumn = preferredColumn
    }
}

public struct TextAttachmentID: Sendable, Equatable, Hashable, Codable {
    public var rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct TextContextSnapshot: Sendable, Equatable, Codable {
    public var applicationBundleID: String?
    public var applicationName: String?
    public var processIdentifier: Int?
    public var elementIdentifier: String
    public var windowTitle: String?
    public var text: String
    public var cursor: TextCursorSnapshot
    public var isSecureInput: Bool
    public var updatedAt: Date

    public init(
        applicationBundleID: String? = nil,
        applicationName: String? = nil,
        processIdentifier: Int? = nil,
        elementIdentifier: String,
        windowTitle: String? = nil,
        text: String,
        cursor: TextCursorSnapshot,
        isSecureInput: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.applicationBundleID = applicationBundleID
        self.applicationName = applicationName
        self.processIdentifier = processIdentifier
        self.elementIdentifier = elementIdentifier
        self.windowTitle = windowTitle
        self.text = text
        self.cursor = cursor
        self.isSecureInput = isSecureInput
        self.updatedAt = updatedAt
    }
}

public enum TextOperator: String, Sendable, Equatable, Codable {
    case delete
    case yank
    case change
}

public enum TextMotion: String, Sendable, Equatable, Codable {
    case left
    case right
    case up
    case down
    case wordForward
    case wordBackward
    case wordEnd
    case lineStart
    case lineEnd
    case documentStart
    case documentEnd
    case line
}

public enum InsertAnchor: String, Sendable, Equatable, Codable {
    case currentPosition
    case afterCursor
    case lineStart
    case lineEnd
    case aboveLine
    case belowLine
}

public enum VisualSelectionKind: String, Sendable, Equatable, Codable {
    case characterWise
    case lineWise
}

public enum TextModeCommand: Sendable, Equatable, Codable {
    case moveCursor(TextMotion, count: Int, extendSelection: Bool)
    case applyOperator(TextOperator, motion: TextMotion?, count: Int)
    case enterInsert(InsertAnchor)
    case enterVisual(VisualSelectionKind)
    case leaveVisual
    case submitCommandLine(String)
    case paste(afterCursor: Bool, count: Int)
    case synchronizeContext
    case setMode(TextInputMode)
}

public enum TextModeEffect: String, Sendable, Equatable, Codable {
    case consume
    case forwardOriginalEvent
    case requestContextSync
    case ringBell
}

public struct TextModeState: Sendable, Equatable, Codable {
    public var attachmentID: TextAttachmentID
    public var backend: TextModeEngineAvailability.Backend
    public var mode: TextInputMode
    public var lastMode: TextInputMode?
    public var pendingCount: Int?
    public var pendingOperator: TextOperator?
    public var pendingCommandLine: String
    public var queuedKeys: [TextKeyEvent]
    public var handledEventCount: Int
    public var lastEventAt: Date?
    public var recentCommands: [TextModeCommand]
    public var recentEffects: [TextModeEffect]
    public var cursor: TextCursorSnapshot
    public var isSecureInput: Bool
    public var attachedAt: Date
    public var lastSyncedAt: Date

    public init(
        attachmentID: TextAttachmentID,
        backend: TextModeEngineAvailability.Backend = .fallback,
        mode: TextInputMode = .normal,
        lastMode: TextInputMode? = nil,
        pendingCount: Int? = nil,
        pendingOperator: TextOperator? = nil,
        pendingCommandLine: String = "",
        queuedKeys: [TextKeyEvent] = [],
        handledEventCount: Int = 0,
        lastEventAt: Date? = nil,
        recentCommands: [TextModeCommand] = [],
        recentEffects: [TextModeEffect] = [],
        cursor: TextCursorSnapshot,
        isSecureInput: Bool = false,
        attachedAt: Date = Date(),
        lastSyncedAt: Date = Date()
    ) {
        self.attachmentID = attachmentID
        self.backend = backend
        self.mode = mode
        self.lastMode = lastMode
        self.pendingCount = pendingCount
        self.pendingOperator = pendingOperator
        self.pendingCommandLine = pendingCommandLine
        self.queuedKeys = queuedKeys
        self.handledEventCount = handledEventCount
        self.lastEventAt = lastEventAt
        self.recentCommands = recentCommands
        self.recentEffects = recentEffects
        self.cursor = cursor
        self.isSecureInput = isSecureInput
        self.attachedAt = attachedAt
        self.lastSyncedAt = lastSyncedAt
    }
}

public struct TextModeDecision: Sendable, Equatable, Codable {
    public var state: TextModeState
    public var effects: [TextModeEffect]
    public var commands: [TextModeCommand]

    public init(state: TextModeState, effects: [TextModeEffect], commands: [TextModeCommand] = []) {
        self.state = state
        self.effects = effects
        self.commands = commands
    }

    public var shouldForwardEvent: Bool {
        effects.contains(.forwardOriginalEvent)
    }
}

public struct TextAttachment: Sendable, Equatable, Codable {
    public var id: TextAttachmentID
    public var context: TextContextSnapshot
    public var state: TextModeState

    public init(id: TextAttachmentID, context: TextContextSnapshot, state: TextModeState) {
        self.id = id
        self.context = context
        self.state = state
    }

    public var status: TextSessionStatus {
        TextSessionStatus(attachment: self)
    }
}

public struct TextSessionStatus: Sendable, Equatable, Codable {
    public var attachmentID: TextAttachmentID
    public var backend: TextModeEngineAvailability.Backend
    public var mode: TextInputMode
    public var applicationName: String?
    public var windowTitle: String?
    public var elementIdentifier: String
    public var queuedKeyCount: Int
    public var handledEventCount: Int
    public var pendingCommandLine: String
    public var recentCommands: [TextModeCommand]
    public var recentEffects: [TextModeEffect]
    public var cursor: TextCursorSnapshot
    public var isSecureInput: Bool
    public var attachedAt: Date
    public var lastEventAt: Date?
    public var lastSyncedAt: Date

    public init(attachment: TextAttachment) {
        self.attachmentID = attachment.id
        self.backend = attachment.state.backend
        self.mode = attachment.state.mode
        self.applicationName = attachment.context.applicationName
        self.windowTitle = attachment.context.windowTitle
        self.elementIdentifier = attachment.context.elementIdentifier
        self.queuedKeyCount = attachment.state.queuedKeys.count
        self.handledEventCount = attachment.state.handledEventCount
        self.pendingCommandLine = attachment.state.pendingCommandLine
        self.recentCommands = attachment.state.recentCommands
        self.recentEffects = attachment.state.recentEffects
        self.cursor = attachment.state.cursor
        self.isSecureInput = attachment.state.isSecureInput
        self.attachedAt = attachment.state.attachedAt
        self.lastEventAt = attachment.state.lastEventAt
        self.lastSyncedAt = attachment.state.lastSyncedAt
    }
}

public enum TextRuntimeCaptureState: String, Sendable, Equatable, Codable {
    case idle
    case attached
    case bypassed
}

public enum TextRuntimeBypassReason: String, Sendable, Equatable, Codable {
    case secureInput
    case manualBypass
    case unavailableContext
}

public struct TextRuntimeConfiguration: Sendable, Equatable, Codable {
    public var bypassKey: TextSpecialKey
    public var bypassModifiers: Set<TextKeyModifier>
    public var synchronizeOnEveryEvent: Bool
    public var emergencyFallbackEnabled: Bool

    public init(
        bypassKey: TextSpecialKey = .escape,
        bypassModifiers: Set<TextKeyModifier> = [.control],
        synchronizeOnEveryEvent: Bool = true,
        emergencyFallbackEnabled: Bool = false
    ) {
        self.bypassKey = bypassKey
        self.bypassModifiers = bypassModifiers
        self.synchronizeOnEveryEvent = synchronizeOnEveryEvent
        self.emergencyFallbackEnabled = emergencyFallbackEnabled
    }
}

public struct TextRuntimeSnapshot: Sendable, Equatable, Codable {
    public var backend: TextModeEngineAvailability.Backend
    public var captureState: TextRuntimeCaptureState
    public var bypassReason: TextRuntimeBypassReason?
    public var attachmentID: TextAttachmentID?
    public var applicationName: String?
    public var elementIdentifier: String?
    public var lastCapturedEventAt: Date?
    public var isSecureInput: Bool

    public init(
        backend: TextModeEngineAvailability.Backend = .libvim,
        captureState: TextRuntimeCaptureState = .idle,
        bypassReason: TextRuntimeBypassReason? = nil,
        attachmentID: TextAttachmentID? = nil,
        applicationName: String? = nil,
        elementIdentifier: String? = nil,
        lastCapturedEventAt: Date? = nil,
        isSecureInput: Bool = false
    ) {
        self.backend = backend
        self.captureState = captureState
        self.bypassReason = bypassReason
        self.attachmentID = attachmentID
        self.applicationName = applicationName
        self.elementIdentifier = elementIdentifier
        self.lastCapturedEventAt = lastCapturedEventAt
        self.isSecureInput = isSecureInput
    }
}
