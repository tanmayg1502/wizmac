import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import WizmacCore

public struct VisibleWindow: Identifiable, Equatable, Sendable {
    public var id: Int
    public var appName: String
    public var title: String
    public var pid: Int32
    public var frame: TargetRect?

    public init(id: Int, appName: String, title: String, pid: Int32, frame: TargetRect?) {
        self.id = id
        self.appName = appName
        self.title = title
        self.pid = pid
        self.frame = frame
    }

    public var payload: JSONValue {
        [
            "id": .number(Double(id)),
            "appName": .string(appName),
            "title": .string(title),
            "pid": .number(Double(pid)),
            "frame": frame.map {
                [
                    "x": .number($0.x),
                    "y": .number($0.y),
                    "width": .number($0.width),
                    "height": .number($0.height),
                ]
            } ?? .null,
        ]
    }
}

public final class WindowController: WindowControlling {
    typealias VisibleWindowProvider = ([ExcludedWindowRule]) -> [VisibleWindow]
    typealias WindowFocusPerformer = (VisibleWindow) -> Bool

    private let visibleWindowProvider: VisibleWindowProvider
    private let focusPerformer: WindowFocusPerformer

    init(
        visibleWindowProvider: VisibleWindowProvider? = nil,
        focusPerformer: WindowFocusPerformer? = nil
    ) {
        self.visibleWindowProvider = visibleWindowProvider ?? Self.defaultVisibleWindows(excluding:)
        self.focusPerformer = focusPerformer ?? Self.defaultFocus(window:)
    }

    public func visibleWindows(excluding rules: [ExcludedWindowRule]) -> [VisibleWindow] {
        visibleWindowProvider(rules)
    }

    public func excludeRule(windowID: Int?, title: String?, pid: Int32?, excluding rules: [ExcludedWindowRule]) -> ExcludedWindowRule? {
        guard let match = matchingWindow(windowID: windowID, title: title, query: nil, pid: pid, excluding: rules) else {
            return nil
        }
        return ExcludedWindowRule(appName: match.appName, title: match.title)
    }

    public func focus(windowID: Int?, title: String?, pid: Int32?) -> Bool {
        guard let match = matchingWindow(windowID: windowID, title: title, query: nil, pid: pid, excluding: []) else {
            return false
        }
        return focusPerformer(match)
    }

    public func matchingWindow(
        windowID: Int?,
        title: String?,
        query: String?,
        pid: Int32?,
        excluding rules: [ExcludedWindowRule]
    ) -> VisibleWindow? {
        let visible = visibleWindows(excluding: rules)
        let selectionQuery = title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? title : query
        return matchWindow(windowID: windowID, title: selectionQuery, pid: pid, in: visible)
    }
}

private extension WindowController {
    static func defaultVisibleWindows(excluding rules: [ExcludedWindowRule]) -> [VisibleWindow] {
        guard
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else {
            return []
        }

        return list.compactMap { window in
            guard
                let layer = window[kCGWindowLayer as String] as? Int,
                layer == 0,
                let id = window[kCGWindowNumber as String] as? Int,
                let appName = window[kCGWindowOwnerName as String] as? String,
                let pid = window[kCGWindowOwnerPID as String] as? Int32
            else {
                return nil
            }

            let title = (window[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard title.isEmpty == false else { return nil }
            guard rules.contains(where: { $0.appName == appName && $0.title == title }) == false else { return nil }

            let bounds = (window[kCGWindowBounds as String] as? [String: Any]).flatMap { dictionary -> TargetRect? in
                guard
                    let x = dictionary["X"] as? Double,
                    let y = dictionary["Y"] as? Double,
                    let width = dictionary["Width"] as? Double,
                    let height = dictionary["Height"] as? Double
                else {
                    return nil
                }
                return TargetRect(x: x, y: y, width: width, height: height)
            }

            return VisibleWindow(id: id, appName: appName, title: title, pid: pid, frame: bounds)
        }
    }

    func matchWindow(windowID: Int?, title: String?, pid: Int32?, in visible: [VisibleWindow]) -> VisibleWindow? {
        if let windowID, let match = visible.first(where: { $0.id == windowID }) {
            return match
        }

        if let pid, let title, let match = visible.first(where: { $0.pid == pid && $0.title == title }) {
            return match
        }

        if let title, let match = visible.first(where: { $0.title == title }) {
            return match
        }

        guard let fuzzyQuery = title?.trimmingCharacters(in: .whitespacesAndNewlines), fuzzyQuery.isEmpty == false else {
            return nil
        }

        return fuzzyMatchWindow(query: fuzzyQuery, pid: pid, in: visible)
    }

    func fuzzyMatchWindow(query: String, pid: Int32?, in visible: [VisibleWindow]) -> VisibleWindow? {
        let components = WindowSearchComponents(query)
        guard components.normalized.isEmpty == false else { return nil }

        let pools: [[VisibleWindow]]
        if let pid = pid {
            let pidMatches = visible.filter { $0.pid == pid }
            pools = pidMatches.isEmpty ? [visible] : [pidMatches, visible]
        } else {
            pools = [visible]
        }

        for pool in pools {
            if let best = bestFuzzyMatch(for: components, in: pool) {
                return best
            }
        }

        return nil
    }

    func bestFuzzyMatch(for query: WindowSearchComponents, in windows: [VisibleWindow]) -> VisibleWindow? {
        let scored = windows
            .compactMap { window -> (VisibleWindow, Int)? in
                guard let score = fuzzyScore(query: query, window: window) else { return nil }
                return (window, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                if lhs.0.title != rhs.0.title {
                    return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
                }
                return lhs.0.id < rhs.0.id
            }

        return scored.first?.0
    }

    func fuzzyScore(query: WindowSearchComponents, window: VisibleWindow) -> Int? {
        let titleScore = fieldScore(query: query, field: window.title)
        let appScore = fieldScore(query: query, field: window.appName)
        guard titleScore > 0 || appScore > 0 else { return nil }

        var total = titleScore + appScore
        if titleScore > 0 && appScore > 0 {
            total += 10
        }
        return total
    }

    func fieldScore(query: WindowSearchComponents, field: String) -> Int {
        let components = WindowSearchComponents(field)
        guard components.normalized.isEmpty == false else { return 0 }

        if components.raw == query.raw {
            return 80
        }
        if query.normalized.isEmpty == false && components.normalized == query.normalized {
            return 74
        }

        var score = 0
        if query.normalized.isEmpty == false, components.normalized.contains(query.normalized) {
            score = max(score, 60)
        }

        let tokenScore = tokenCoverageScore(queryTokens: query.tokens, fieldTokens: components.tokens)
        if tokenScore > 0 {
            score = max(score, tokenScore)
        }

        return score
    }

    func tokenCoverageScore(queryTokens: [String], fieldTokens: [String]) -> Int {
        guard queryTokens.isEmpty == false, fieldTokens.isEmpty == false else { return 0 }

        var exactMatches = 0
        var prefixMatches = 0

        for token in queryTokens {
            if fieldTokens.contains(token) {
                exactMatches += 1
            } else if token.count >= 3,
                      fieldTokens.contains(where: { fieldToken in
                          fieldToken.count >= 3 && (fieldToken.hasPrefix(token) || token.hasPrefix(fieldToken))
                      }) {
                prefixMatches += 1
            }
        }

        guard exactMatches > 0 || prefixMatches > 0 else { return 0 }

        var score = (exactMatches * 18) + (prefixMatches * 10)
        if exactMatches + prefixMatches == queryTokens.count {
            score += 14
        }
        if exactMatches == queryTokens.count {
            score += 10
        }
        return score
    }

    struct WindowSearchComponents {
        let raw: String
        let normalized: String
        let tokens: [String]

        init(_ text: String) {
            raw = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            normalized = Self.normalizedText(from: raw)
            tokens = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
        }

        private static func normalizedText(from text: String) -> String {
            var scalars: [UnicodeScalar] = []
            var previousWasSpace = false

            for scalar in text.unicodeScalars {
                if CharacterSet.alphanumerics.contains(scalar) {
                    scalars.append(scalar)
                    previousWasSpace = false
                } else if previousWasSpace == false {
                    scalars.append(" ")
                    previousWasSpace = true
                }
            }

            return String(String.UnicodeScalarView(scalars))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static func defaultFocus(window match: VisibleWindow) -> Bool {
        NSRunningApplication(processIdentifier: match.pid)?.activate(options: [.activateIgnoringOtherApps])

        let appElement = AXUIElementCreateApplication(match.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else {
            return true
        }

        for window in windows {
            var titleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
               let axTitle = titleValue as? String,
               axTitle == match.title {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                return true
            }
        }

        return true
    }
}
