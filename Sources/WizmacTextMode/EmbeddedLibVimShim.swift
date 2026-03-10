import Foundation

public struct LibVimShimSnapshot: Sendable, Equatable, Codable {
    public var sessionID: UUID
    public var fedKeyCount: Int
    public var bufferedKeys: [String]
    public var lastSyncedTextLength: Int
    public var currentMode: TextInputMode

    public init(
        sessionID: UUID,
        fedKeyCount: Int,
        bufferedKeys: [String],
        lastSyncedTextLength: Int,
        currentMode: TextInputMode
    ) {
        self.sessionID = sessionID
        self.fedKeyCount = fedKeyCount
        self.bufferedKeys = bufferedKeys
        self.lastSyncedTextLength = lastSyncedTextLength
        self.currentMode = currentMode
    }
}

final class EmbeddedLibVimSession: @unchecked Sendable {
    private let sessionID = UUID()
    private(set) var fedKeyCount = 0
    private(set) var bufferedKeys: [String] = []
    private(set) var lastSyncedTextLength = 0

    func sync(context: TextContextSnapshot) {
        lastSyncedTextLength = context.text.utf16.count
    }

    func feed(_ event: TextKeyEvent, state: inout TextModeState) -> TextModeDecision {
        fedKeyCount += 1
        bufferedKeys.append(Self.debugToken(for: event))
        if bufferedKeys.count > 32 {
            bufferedKeys = Array(bufferedKeys.suffix(32))
        }

        TextModeReducer.ingest(event, into: &state)
        let decision = TextModeReducer.reduce(event: event, state: &state)
        TextModeReducer.record(decision, in: &state)
        return TextModeDecision(state: state, effects: decision.effects, commands: decision.commands)
    }

    func snapshot(currentMode: TextInputMode) -> LibVimShimSnapshot {
        LibVimShimSnapshot(
            sessionID: sessionID,
            fedKeyCount: fedKeyCount,
            bufferedKeys: bufferedKeys,
            lastSyncedTextLength: lastSyncedTextLength,
            currentMode: currentMode
        )
    }
}

private extension EmbeddedLibVimSession {
    static func debugToken(for event: TextKeyEvent) -> String {
        switch event.key {
        case let .character(value):
            return value
        case let .special(value):
            return "<\(value.rawValue)>"
        }
    }
}
