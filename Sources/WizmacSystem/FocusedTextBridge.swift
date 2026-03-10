import AppKit
import ApplicationServices
import Foundation
import WizmacTextMode

public final class FocusedTextBridge: FocusedTextBridging {
    public init() {}

    public func captureFocusedContext() -> FocusedTextCapture? {
        let system = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue
        else {
            return nil
        }
        let element = focusedValue as! AXUIElement

        let role = stringValue(for: element, attribute: kAXRoleAttribute) ?? ""
        let subrole = stringValue(for: element, attribute: kAXSubroleAttribute) ?? ""
        guard role.lowercased().contains("text") || subrole.lowercased().contains("text") || role.lowercased().contains("combo") else {
            return nil
        }

        let text = stringValue(for: element, attribute: kAXValueAttribute) ?? ""
        let selectedRange = rangeValue(for: element, attribute: kAXSelectedTextRangeAttribute) ?? NSRange(location: 0, length: 0)
        let app = NSWorkspace.shared.frontmostApplication
        let windowTitle = focusedWindowTitle(for: app?.processIdentifier)
        let identifier = stringValue(for: element, attribute: kAXIdentifierAttribute) ?? UUID().uuidString
        let isSecureInput = role.lowercased().contains("secure") || subrole.lowercased().contains("secure")

        return FocusedTextCapture(
            element: element,
            context: TextContextSnapshot(
                applicationBundleID: app?.bundleIdentifier,
                applicationName: app?.localizedName,
                processIdentifier: app.map { Int($0.processIdentifier) },
                elementIdentifier: identifier,
                windowTitle: windowTitle,
                text: text,
                cursor: TextCursorSnapshot(range: TextRange(location: selectedRange.location, length: selectedRange.length)),
                isSecureInput: isSecureInput
            )
        )
    }

    public func sync(context: TextContextSnapshot, onto element: AXUIElement?) {
        guard let element else { return }
        let value = context.text as NSString
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value)

        var range = CFRange(location: context.cursor.range.location, length: context.cursor.range.length)
        if let axRange = AXValueCreate(.cfRange, &range) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
        }
    }

    public func apply(
        commands: [TextModeCommand],
        for event: TextKeyEvent,
        to element: AXUIElement?,
        context: inout TextContextSnapshot
    ) {
        if commands.isEmpty, context.isSecureInput == false {
            applyForwardedEvent(event, context: &context)
            sync(context: context, onto: element)
            return
        }

        for command in commands {
            switch command {
            case let .moveCursor(motion, count, _):
                applyMotion(motion, count: count, context: &context)
            case let .applyOperator(operatorKind, motion, count):
                applyOperator(operatorKind, motion: motion, count: count, context: &context)
            case .enterInsert:
                break
            case .enterVisual:
                break
            case .leaveVisual:
                context.cursor.range.length = 0
            case let .submitCommandLine(command):
                if command == "normal" {
                    context.cursor.range.length = 0
                }
            case let .paste(afterCursor, count):
                applyPaste(afterCursor: afterCursor, count: count, context: &context)
            case .synchronizeContext:
                break
            case .setMode:
                break
            }
        }

        sync(context: context, onto: element)
    }

    private func applyForwardedEvent(_ event: TextKeyEvent, context: inout TextContextSnapshot) {
        if let character = event.characterValue {
            replaceSelection(in: &context, with: character)
            return
        }

        switch event.specialValue {
        case .backspace:
            if context.cursor.range.length > 0 {
                replaceSelection(in: &context, with: "")
            } else if context.cursor.range.location > 0 {
                let target = NSRange(location: context.cursor.range.location - 1, length: 1)
                replace(range: target, in: &context, with: "")
            }
        case .enter:
            replaceSelection(in: &context, with: "\n")
        case .tab:
            replaceSelection(in: &context, with: "\t")
        default:
            break
        }
    }

    private func applyMotion(_ motion: TextMotion, count: Int, context: inout TextContextSnapshot) {
        let maxCount = max(1, count)
        let location = context.cursor.range.location
        let text = context.text

        switch motion {
        case .left:
            context.cursor.range = TextRange(location: max(0, location - maxCount), length: 0)
        case .right:
            context.cursor.range = TextRange(location: min(text.utf16.count, location + maxCount), length: 0)
        case .lineStart:
            context.cursor.range = TextRange(location: lineStart(in: text, from: location), length: 0)
        case .lineEnd:
            context.cursor.range = TextRange(location: lineEnd(in: text, from: location), length: 0)
        case .documentStart:
            context.cursor.range = TextRange(location: 0, length: 0)
        case .documentEnd:
            context.cursor.range = TextRange(location: text.utf16.count, length: 0)
        case .wordForward:
            context.cursor.range = TextRange(location: wordForward(in: text, from: location, count: maxCount), length: 0)
        case .wordBackward:
            context.cursor.range = TextRange(location: wordBackward(in: text, from: location, count: maxCount), length: 0)
        case .wordEnd:
            context.cursor.range = TextRange(location: wordEnd(in: text, from: location, count: maxCount), length: 0)
        case .up, .down, .line:
            break
        }
    }

    private func applyOperator(_ operatorKind: TextOperator, motion: TextMotion?, count: Int, context: inout TextContextSnapshot) {
        let maxCount = max(1, count)
        let location = context.cursor.range.location
        let text = context.text
        let targetRange: NSRange

        switch motion {
        case .line:
            let start = lineStart(in: text, from: location)
            let end = lineEnd(in: text, from: location)
            targetRange = NSRange(location: start, length: max(0, end - start))
        case .left:
            let start = max(0, location - maxCount)
            targetRange = NSRange(location: start, length: location - start)
        case .wordForward:
            let end = wordForward(in: text, from: location, count: maxCount)
            targetRange = NSRange(location: location, length: max(0, end - location))
        case .wordBackward:
            let start = wordBackward(in: text, from: location, count: maxCount)
            targetRange = NSRange(location: start, length: max(0, location - start))
        case .lineEnd:
            let end = lineEnd(in: text, from: location)
            targetRange = NSRange(location: location, length: max(0, end - location))
        case .documentEnd:
            targetRange = NSRange(location: location, length: max(0, text.utf16.count - location))
        case .documentStart:
            targetRange = NSRange(location: 0, length: location)
        default:
            let end = min(text.utf16.count, location + maxCount)
            targetRange = NSRange(location: location, length: max(0, end - location))
        }

        let targetText = substring(in: text, range: targetRange)

        switch operatorKind {
        case .delete, .change:
            replace(range: targetRange, in: &context, with: "")
        case .yank:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(targetText, forType: .string)
        }
    }

    private func applyPaste(afterCursor: Bool, count: Int, context: inout TextContextSnapshot) {
        guard let paste = NSPasteboard.general.string(forType: .string), paste.isEmpty == false else { return }
        let repeated = Array(repeating: paste, count: max(1, count)).joined()
        let insertionLocation = afterCursor ? min(context.text.utf16.count, context.cursor.range.location + 1) : context.cursor.range.location
        replace(range: NSRange(location: insertionLocation, length: 0), in: &context, with: repeated)
    }

    private func replaceSelection(in context: inout TextContextSnapshot, with replacement: String) {
        replace(range: NSRange(location: context.cursor.range.location, length: context.cursor.range.length), in: &context, with: replacement)
    }

    private func replace(range: NSRange, in context: inout TextContextSnapshot, with replacement: String) {
        let nsString = context.text as NSString
        let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: nsString.length))
        let newText = nsString.replacingCharacters(in: safeRange, with: replacement)
        let cursorLocation = safeRange.location + replacement.utf16.count

        context.text = newText
        context.cursor.range = TextRange(location: cursorLocation, length: 0)
    }

    private func substring(in text: String, range: NSRange) -> String {
        let nsString = text as NSString
        let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: nsString.length))
        return nsString.substring(with: safeRange)
    }

    private func lineStart(in text: String, from location: Int) -> Int {
        let nsString = text as NSString
        let safeLocation = min(max(0, location), nsString.length)
        let prefix = nsString.substring(to: safeLocation)
        return (prefix as NSString).range(of: "\n", options: .backwards).location == NSNotFound
            ? 0
            : ((prefix as NSString).range(of: "\n", options: .backwards).location + 1)
    }

    private func lineEnd(in text: String, from location: Int) -> Int {
        let nsString = text as NSString
        let safeLocation = min(max(0, location), nsString.length)
        let suffixRange = NSRange(location: safeLocation, length: nsString.length - safeLocation)
        let suffix = nsString.substring(with: suffixRange)
        let nextNewline = (suffix as NSString).range(of: "\n")
        return nextNewline.location == NSNotFound ? nsString.length : safeLocation + nextNewline.location
    }

    private func wordForward(in text: String, from location: Int, count: Int) -> Int {
        var current = min(max(0, location), text.utf16.count)
        let characters = Array(text)
        for _ in 0..<count {
            while current < characters.count, characters[current].isLetter || characters[current].isNumber {
                current += 1
            }
            while current < characters.count, !(characters[current].isLetter || characters[current].isNumber) {
                current += 1
            }
        }
        return min(current, text.utf16.count)
    }

    private func wordBackward(in text: String, from location: Int, count: Int) -> Int {
        var current = min(max(0, location), text.utf16.count)
        let characters = Array(text)
        for _ in 0..<count {
            if current > 0 { current -= 1 }
            while current > 0, !(characters[current].isLetter || characters[current].isNumber) {
                current -= 1
            }
            while current > 0, characters[current - 1].isLetter || characters[current - 1].isNumber {
                current -= 1
            }
        }
        return current
    }

    private func wordEnd(in text: String, from location: Int, count: Int) -> Int {
        var current = min(max(0, location), text.utf16.count)
        let characters = Array(text)
        for _ in 0..<count {
            while current < characters.count, !(characters[current].isLetter || characters[current].isNumber) {
                current += 1
            }
            while current < characters.count, characters[current].isLetter || characters[current].isNumber {
                current += 1
            }
        }
        return max(0, current - 1)
    }

    private func stringValue(for element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        switch value {
        case let string as String:
            return string
        case let attributed as NSAttributedString:
            return attributed.string
        default:
            return nil
        }
    }

    private func rangeValue(for element: AXUIElement, attribute: String) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else {
            return nil
        }
        let axValue = value as! AXValue
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private func focusedWindowTitle(for pid: pid_t?) -> String? {
        guard let pid else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value
        else {
            return nil
        }
        let window = value as! AXUIElement
        return stringValue(for: window, attribute: kAXTitleAttribute)
    }
}
