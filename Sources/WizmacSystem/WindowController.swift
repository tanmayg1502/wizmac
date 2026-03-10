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
        let visible = visibleWindows(excluding: rules)
        guard let match = matchWindow(windowID: windowID, title: title, pid: pid, in: visible) else {
            return nil
        }
        return ExcludedWindowRule(appName: match.appName, title: match.title)
    }

    public func focus(windowID: Int?, title: String?, pid: Int32?) -> Bool {
        let visible = visibleWindows(excluding: [])
        guard let match = matchWindow(windowID: windowID, title: title, pid: pid, in: visible) else {
            return false
        }
        return focusPerformer(match)
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
        visible.first { item in
            if let windowID, item.id == windowID { return true }
            if let pid, item.pid == pid, let title, item.title == title { return true }
            if let title, item.title == title { return true }
            return false
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
