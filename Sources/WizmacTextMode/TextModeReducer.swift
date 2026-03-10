import Foundation

enum TextModeReducer {
    static func ingest(_ event: TextKeyEvent, into state: inout TextModeState) {
        state.queuedKeys.append(event)
        if state.queuedKeys.count > 32 {
            state.queuedKeys = Array(state.queuedKeys.suffix(32))
        }
        state.handledEventCount += 1
        state.lastEventAt = event.timestamp
    }

    static func record(_ decision: TextModeDecision, in state: inout TextModeState) {
        state.recentCommands = Array((state.recentCommands + decision.commands).suffix(8))
        state.recentEffects = Array((state.recentEffects + decision.effects).suffix(8))
    }

    static func reduce(event: TextKeyEvent, state: inout TextModeState) -> TextModeDecision {
        if state.isSecureInput {
            return TextModeDecision(state: state, effects: [.forwardOriginalEvent], commands: [])
        }

        switch state.mode {
        case .disabled:
            return handleDisabledMode(event: event, state: &state)
        case .insert, .replace:
            return handleInsertLikeMode(event: event, state: &state)
        case .normal:
            return handleNormalMode(event: event, state: &state)
        case .operatorPending:
            return handleOperatorPendingMode(event: event, state: &state)
        case .visual, .visualLine:
            return handleVisualMode(event: event, state: &state)
        case .command:
            return handleCommandMode(event: event, state: &state)
        }
    }
}

private extension TextModeReducer {
    static func handleDisabledMode(
        event: TextKeyEvent,
        state: inout TextModeState
    ) -> TextModeDecision {
        if event.specialValue == .escape, state.isSecureInput == false {
            state.lastMode = state.mode
            state.mode = .normal
            return TextModeDecision(state: state, effects: [.consume], commands: [.setMode(.normal)])
        }

        return TextModeDecision(state: state, effects: [.forwardOriginalEvent])
    }

    static func handleInsertLikeMode(
        event: TextKeyEvent,
        state: inout TextModeState
    ) -> TextModeDecision {
        if event.specialValue == .escape {
            state.lastMode = state.mode
            state.mode = .normal
            state.pendingCount = nil
            state.pendingOperator = nil
            return TextModeDecision(
                state: state,
                effects: [.consume],
                commands: [.setMode(.normal)]
            )
        }

        return TextModeDecision(state: state, effects: [.forwardOriginalEvent])
    }

    static func handleNormalMode(
        event: TextKeyEvent,
        state: inout TextModeState
    ) -> TextModeDecision {
        if event.specialValue == .escape {
            state.pendingCount = nil
            state.pendingOperator = nil
            return TextModeDecision(state: state, effects: [.consume])
        }

        if let digit = decimalDigit(from: event), shouldAccumulateCount(digit: digit, state: state) {
            state.pendingCount = ((state.pendingCount ?? 0) * 10) + digit
            return TextModeDecision(state: state, effects: [.consume])
        }

        guard let rawCharacter = event.characterValue else {
            return TextModeDecision(state: state, effects: [.forwardOriginalEvent])
        }

        if rawCharacter == "V" {
            state.lastMode = state.mode
            state.mode = .visualLine
            return TextModeDecision(
                state: state,
                effects: [.consume],
                commands: [.enterVisual(.lineWise), .setMode(.visualLine)]
            )
        }

        if rawCharacter == "G" {
            return TextModeDecision(
                state: state,
                effects: [.consume],
                commands: [.moveCursor(.documentEnd, count: 1, extendSelection: false)]
            )
        }

        let character = rawCharacter.lowercased()
        let count = resolvedCount(for: &state)

        switch character {
        case "i":
            state.lastMode = state.mode
            state.mode = .insert
            return TextModeDecision(
                state: state,
                effects: [.consume],
                commands: [.enterInsert(.currentPosition), .setMode(.insert)]
            )
        case "a":
            state.lastMode = state.mode
            state.mode = .insert
            return TextModeDecision(
                state: state,
                effects: [.consume],
                commands: [.enterInsert(.afterCursor), .setMode(.insert)]
            )
        case "o":
            state.lastMode = state.mode
            state.mode = .insert
            return TextModeDecision(
                state: state,
                effects: [.consume],
                commands: [.enterInsert(.belowLine), .setMode(.insert)]
            )
        case "v":
            state.lastMode = state.mode
            state.mode = .visual
            return TextModeDecision(
                state: state,
                effects: [.consume],
                commands: [.enterVisual(.characterWise), .setMode(.visual)]
            )
        case ":":
            state.lastMode = state.mode
            state.mode = .command
            state.pendingCommandLine = ""
            return TextModeDecision(
                state: state,
                effects: [.consume],
                commands: [.setMode(.command)]
            )
        case "d", "y", "c":
            state.lastMode = state.mode
            state.mode = .operatorPending
            state.pendingOperator = textOperator(for: character)
            state.pendingCount = count == 1 ? nil : count
            return TextModeDecision(state: state, effects: [.consume])
        case "h":
            return decisionForMotion(.left, count: count, state: &state)
        case "j":
            return decisionForMotion(.down, count: count, state: &state)
        case "k":
            return decisionForMotion(.up, count: count, state: &state)
        case "l":
            return decisionForMotion(.right, count: count, state: &state)
        case "w":
            return decisionForMotion(.wordForward, count: count, state: &state)
        case "b":
            return decisionForMotion(.wordBackward, count: count, state: &state)
        case "e":
            return decisionForMotion(.wordEnd, count: count, state: &state)
        case "0":
            return decisionForMotion(.lineStart, count: 1, state: &state)
        case "$":
            return decisionForMotion(.lineEnd, count: 1, state: &state)
        case "g":
            return handleStandaloneG(state: &state)
        case "x":
            return TextModeDecision(
                state: state,
                effects: [.consume],
                commands: [.applyOperator(.delete, motion: .right, count: count)]
            )
        case "p":
            return TextModeDecision(
                state: state,
                effects: [.consume],
                commands: [.paste(afterCursor: true, count: count)]
            )
        default:
            return TextModeDecision(state: state, effects: [.ringBell, .consume])
        }
    }

    static func handleOperatorPendingMode(
        event: TextKeyEvent,
        state: inout TextModeState
    ) -> TextModeDecision {
        if event.specialValue == .escape {
            state.lastMode = state.mode
            state.mode = .normal
            state.pendingOperator = nil
            state.pendingCount = nil
            return TextModeDecision(state: state, effects: [.consume], commands: [.setMode(.normal)])
        }

        guard let op = state.pendingOperator else {
            state.mode = .normal
            return TextModeDecision(state: state, effects: [.ringBell, .consume], commands: [.setMode(.normal)])
        }

        let count = resolvedCount(for: &state)
        let character = event.characterValue?.lowercased()

        state.lastMode = state.mode
        state.mode = .normal
        state.pendingOperator = nil

        let resolvedMotion: TextMotion?
        if let character {
            if character == repeatedOperatorCharacter(for: op) {
                resolvedMotion = .line
            } else {
                resolvedMotion = motion(for: character)
            }
        } else {
            resolvedMotion = nil
        }

        guard let resolvedMotion else {
            return TextModeDecision(state: state, effects: [.ringBell, .consume], commands: [.setMode(.normal)])
        }

        var commands: [TextModeCommand] = [.applyOperator(op, motion: resolvedMotion, count: count), .setMode(.normal)]
        if op == .change {
            state.lastMode = .normal
            state.mode = .insert
            commands.append(.enterInsert(.currentPosition))
            commands.append(.setMode(.insert))
        }

        return TextModeDecision(state: state, effects: [.consume], commands: commands)
    }

    static func handleVisualMode(
        event: TextKeyEvent,
        state: inout TextModeState
    ) -> TextModeDecision {
        if event.specialValue == .escape {
            let priorMode = state.mode
            state.lastMode = priorMode
            state.mode = .normal
            state.pendingCount = nil
            state.pendingOperator = nil
            return TextModeDecision(
                state: state,
                effects: [.consume],
                commands: [.leaveVisual, .setMode(.normal)]
            )
        }

        let count = resolvedCount(for: &state)

        if let character = event.characterValue?.lowercased() {
            switch character {
            case "h":
                return decisionForMotion(.left, count: count, extendSelection: true, state: &state)
            case "j":
                return decisionForMotion(.down, count: count, extendSelection: true, state: &state)
            case "k":
                return decisionForMotion(.up, count: count, extendSelection: true, state: &state)
            case "l":
                return decisionForMotion(.right, count: count, extendSelection: true, state: &state)
            case "w":
                return decisionForMotion(.wordForward, count: count, extendSelection: true, state: &state)
            case "b":
                return decisionForMotion(.wordBackward, count: count, extendSelection: true, state: &state)
            case "y":
                state.lastMode = state.mode
                state.mode = .normal
                return TextModeDecision(
                    state: state,
                    effects: [.consume],
                    commands: [
                        .applyOperator(.yank, motion: nil, count: count),
                        .leaveVisual,
                        .setMode(.normal)
                    ]
                )
            case "d":
                state.lastMode = state.mode
                state.mode = .normal
                return TextModeDecision(
                    state: state,
                    effects: [.consume],
                    commands: [
                        .applyOperator(.delete, motion: nil, count: count),
                        .leaveVisual,
                        .setMode(.normal)
                    ]
                )
            case "c":
                state.lastMode = state.mode
                state.mode = .insert
                return TextModeDecision(
                    state: state,
                    effects: [.consume],
                    commands: [
                        .applyOperator(.change, motion: nil, count: count),
                        .leaveVisual,
                        .enterInsert(.currentPosition),
                        .setMode(.insert)
                    ]
                )
            default:
                return TextModeDecision(state: state, effects: [.ringBell, .consume])
            }
        }

        return TextModeDecision(state: state, effects: [.forwardOriginalEvent])
    }

    static func handleCommandMode(
        event: TextKeyEvent,
        state: inout TextModeState
    ) -> TextModeDecision {
        switch event.specialValue {
        case .escape:
            state.lastMode = state.mode
            state.mode = .normal
            state.pendingCommandLine = ""
            return TextModeDecision(state: state, effects: [.consume], commands: [.setMode(.normal)])
        case .backspace:
            if state.pendingCommandLine.isEmpty == false {
                state.pendingCommandLine.removeLast()
            }
            return TextModeDecision(state: state, effects: [.consume])
        case .enter:
            let commandLine = state.pendingCommandLine
            state.lastMode = state.mode
            state.mode = .normal
            state.pendingCommandLine = ""
            return TextModeDecision(
                state: state,
                effects: [.consume],
                commands: [.submitCommandLine(commandLine), .setMode(.normal)]
            )
        default:
            break
        }

        guard let character = event.characterValue else {
            return TextModeDecision(state: state, effects: [.ringBell, .consume])
        }

        state.pendingCommandLine.append(character)
        return TextModeDecision(state: state, effects: [.consume])
    }

    static func handleStandaloneG(state: inout TextModeState) -> TextModeDecision {
        if let previous = state.queuedKeys.dropLast().last?.characterValue?.lowercased(), previous == "g" {
            return TextModeDecision(
                state: state,
                effects: [.consume],
                commands: [.moveCursor(.documentStart, count: 1, extendSelection: false)]
            )
        }

        return TextModeDecision(state: state, effects: [.consume])
    }

    static func decisionForMotion(
        _ motion: TextMotion,
        count: Int,
        extendSelection: Bool = false,
        state: inout TextModeState
    ) -> TextModeDecision {
        TextModeDecision(
            state: state,
            effects: [.consume],
            commands: [.moveCursor(motion, count: count, extendSelection: extendSelection)]
        )
    }

    static func resolvedCount(for state: inout TextModeState) -> Int {
        defer { state.pendingCount = nil }
        return max(1, state.pendingCount ?? 1)
    }

    static func decimalDigit(from event: TextKeyEvent) -> Int? {
        guard
            let character = event.characterValue,
            character.count == 1,
            let scalar = character.unicodeScalars.first,
            scalar.properties.numericType != nil,
            let value = Int(character)
        else {
            return nil
        }
        return value
    }

    static func shouldAccumulateCount(digit: Int, state: TextModeState) -> Bool {
        digit != 0 || state.pendingCount != nil
    }

    static func textOperator(for character: String) -> TextOperator? {
        switch character {
        case "d": return .delete
        case "y": return .yank
        case "c": return .change
        default: return nil
        }
    }

    static func repeatedOperatorCharacter(for op: TextOperator) -> String {
        switch op {
        case .delete: return "d"
        case .yank: return "y"
        case .change: return "c"
        }
    }

    static func motion(for character: String) -> TextMotion? {
        switch character {
        case "h": return .left
        case "j": return .down
        case "k": return .up
        case "l": return .right
        case "w": return .wordForward
        case "b": return .wordBackward
        case "e": return .wordEnd
        case "0": return .lineStart
        case "$": return .lineEnd
        case "g": return .documentStart
        case "G": return .documentEnd
        default: return nil
        }
    }
}
