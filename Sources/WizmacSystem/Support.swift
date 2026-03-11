import AppKit
import ApplicationServices
import Foundation
import WizmacCore
import WizmacTextMode

struct CommandResult {
    var stdout: String
    var stderr: String
    var terminationStatus: Int32
}

protocol ShellRunning: Sendable {
    func run(
        launchPath: String,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> CommandResult
}

actor ShellCommandRunner: ShellRunning {
    func run(
        launchPath: String,
        arguments: [String] = [],
        timeout: TimeInterval = 1.0
    ) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let queue = DispatchQueue.global(qos: .userInitiated)
            let group = DispatchGroup()
            group.enter()

            queue.asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                }
            }

            process.terminationHandler = { completed in
                defer { group.leave() }

                let stdout = String(
                    data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                let stderr = String(
                    data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""

                continuation.resume(
                    returning: CommandResult(
                        stdout: stdout,
                        stderr: stderr,
                        terminationStatus: completed.terminationStatus
                    )
                )
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                group.leave()
            }
        }
    }
}

protocol PointerAutomationPerforming {
    func move(to point: CGPoint) -> Bool
    func click(at point: CGPoint, clickState: Int64, button: CGMouseButton) -> Bool
    func drag(from start: CGPoint, to end: CGPoint, steps: Int) -> Bool
}

struct CGPointerAutomationPerformer: PointerAutomationPerforming {
    func move(to point: CGPoint) -> Bool {
        CGWarpMouseCursorPosition(point) == .success
    }

    func click(at point: CGPoint, clickState: Int64, button: CGMouseButton) -> Bool {
        let downType: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp

        guard
            let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: point, mouseButton: button),
            let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: point, mouseButton: button)
        else {
            return false
        }

        down.setIntegerValueField(.mouseEventClickState, value: clickState)
        up.setIntegerValueField(.mouseEventClickState, value: clickState)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    func drag(from start: CGPoint, to end: CGPoint, steps: Int = 8) -> Bool {
        let clampedSteps = max(2, steps)
        guard
            let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left),
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)
        else {
            return false
        }

        down.post(tap: .cghidEventTap)
        for index in 1..<(clampedSteps - 1) {
            let progress = Double(index) / Double(clampedSteps - 1)
            let point = CGPoint(
                x: start.x + ((end.x - start.x) * progress),
                y: start.y + ((end.y - start.y) * progress)
            )
            guard let dragged = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: point,
                mouseButton: .left
            ) else {
                return false
            }
            dragged.post(tap: .cghidEventTap)
        }
        up.post(tap: .cghidEventTap)
        return true
    }
}

protocol ScrollEventPerforming {
    func scroll(direction: String, amount: Int, at point: CGPoint) -> Bool
}

struct CGScrollEventPerformer: ScrollEventPerforming {
    func scroll(direction: String, amount: Int, at point: CGPoint) -> Bool {
        let delta = max(1, amount)
        let wheelAmount: Int32
        switch direction.lowercased() {
        case "up", "left":
            wheelAmount = Int32(delta)
        default:
            wheelAmount = Int32(-delta)
        }

        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: wheelAmount,
            wheel2: 0,
            wheel3: 0
        )
        event?.location = point
        event?.post(tap: .cghidEventTap)
        return event != nil
    }
}

public struct FocusedTextCapture: @unchecked Sendable {
    public var element: AXUIElement?
    public var context: TextContextSnapshot

    public init(element: AXUIElement?, context: TextContextSnapshot) {
        self.element = element
        self.context = context
    }
}

public protocol FocusedTextBridging: AnyObject, Sendable {
    func captureFocusedContext() -> FocusedTextCapture?
    func sync(context: TextContextSnapshot, onto element: AXUIElement?)
    func apply(
        commands: [TextModeCommand],
        for event: TextKeyEvent,
        to element: AXUIElement?,
        context: inout TextContextSnapshot
    )
}

public struct RunningAppInfo: Sendable {
    public var pid: pid_t
    public var name: String
    public var bundleIdentifier: String?
    public var isActive: Bool
}

enum UISearchScope: String, Codable, Sendable {
    case focusedWindow = "focused_window"
    case app
}

struct UISessionMetrics: Sendable, Equatable {
    var sessionID: String
    var snapshotID: String
    var appName: String
    var windowTitle: String?
    var targetCount: Int
    var cacheHit: Bool
    var cacheHitRate: Double
    var lastRefreshedAt: Date
    var snapshotMs: Double
    var cacheLookupMs: Double
    var rankingMs: Double
}

struct UISearchResult: Sendable, Equatable {
    var snapshot: TargetSnapshot
    var metrics: UISessionMetrics
}

struct UITargetLookupResult: Sendable, Equatable {
    var target: TargetDescriptor
    var metrics: UISessionMetrics
}

protocol AccessibilitySnapshotting {
    func snapshotFrontmostApplication(labelAlphabet: String) -> TargetSnapshot?
    func snapshotApplication(pid: pid_t, labelAlphabet: String) -> TargetSnapshot?
    func search(query: String, labelAlphabet: String, limit: Int) -> TargetSnapshot?
    func search(query: String, pid: pid_t, labelAlphabet: String, limit: Int) -> TargetSnapshot?
    func target(id: String, labelAlphabet: String) -> TargetDescriptor?
    func target(id: String, pid: pid_t, labelAlphabet: String) -> TargetDescriptor?
    func search(
        query: String,
        pid: pid_t?,
        labelAlphabet: String,
        limit: Int,
        sessionID: String?,
        scope: UISearchScope,
        includeMenus: Bool
    ) -> UISearchResult?
    func target(
        id: String,
        pid: pid_t?,
        labelAlphabet: String,
        sessionID: String?,
        snapshotID: String?,
        scope: UISearchScope,
        includeMenus: Bool
    ) -> UITargetLookupResult?
    func endSession(id: String?) -> UISessionMetrics?
    func currentSession() -> UISessionMetrics?
    func hintSession(query: String?, labelAlphabet: String, limit: Int) -> UIHintSession?
    func hintSession(query: String?, pid: pid_t, labelAlphabet: String, limit: Int) -> UIHintSession?
    func listApplications() -> [RunningAppInfo]
    func debugDump(
        targetID: String,
        pid: pid_t?,
        labelAlphabet: String,
        sessionID: String?,
        snapshotID: String?,
        scope: UISearchScope,
        includeMenus: Bool,
        maxDepth: Int
    ) -> JSONValue?
}

extension AccessibilitySnapshotting {
    func snapshotApplication(pid: pid_t, labelAlphabet: String) -> TargetSnapshot? {
        snapshotFrontmostApplication(labelAlphabet: labelAlphabet)
    }
    func search(query: String, pid: pid_t, labelAlphabet: String, limit: Int) -> TargetSnapshot? {
        search(query: query, labelAlphabet: labelAlphabet, limit: limit)
    }
    func target(id: String, pid: pid_t, labelAlphabet: String) -> TargetDescriptor? {
        target(id: id, labelAlphabet: labelAlphabet)
    }
    func search(
        query: String,
        pid: pid_t?,
        labelAlphabet: String,
        limit: Int,
        sessionID _: String?,
        scope _: UISearchScope,
        includeMenus _: Bool
    ) -> UISearchResult? {
        let startedAt = Date()
        let snapshot = pid.map {
            search(query: query, pid: $0, labelAlphabet: labelAlphabet, limit: limit)
        } ?? search(query: query, labelAlphabet: labelAlphabet, limit: limit)
        guard let snapshot else { return nil }
        return UISearchResult(
            snapshot: snapshot,
            metrics: UISessionMetrics(
                sessionID: snapshot.sessionID ?? UUID().uuidString,
                snapshotID: snapshot.snapshotID ?? UUID().uuidString,
                appName: snapshot.appName,
                windowTitle: snapshot.windowTitle,
                targetCount: snapshot.targets.count,
                cacheHit: false,
                cacheHitRate: 0,
                lastRefreshedAt: snapshot.generatedAt,
                snapshotMs: Date().timeIntervalSince(startedAt) * 1_000,
                cacheLookupMs: 0,
                rankingMs: 0
            )
        )
    }
    func target(
        id: String,
        pid: pid_t?,
        labelAlphabet: String,
        sessionID _: String?,
        snapshotID _: String?,
        scope _: UISearchScope,
        includeMenus _: Bool
    ) -> UITargetLookupResult? {
        let startedAt = Date()
        let resolvedTarget = pid.map {
            self.target(id: id, pid: $0, labelAlphabet: labelAlphabet)
        } ?? self.target(id: id, labelAlphabet: labelAlphabet)
        guard let resolvedTarget else { return nil }
        return UITargetLookupResult(
            target: resolvedTarget,
            metrics: UISessionMetrics(
                sessionID: UUID().uuidString,
                snapshotID: UUID().uuidString,
                appName: resolvedTarget.appName,
                windowTitle: nil,
                targetCount: 1,
                cacheHit: false,
                cacheHitRate: 0,
                lastRefreshedAt: Date(),
                snapshotMs: Date().timeIntervalSince(startedAt) * 1_000,
                cacheLookupMs: 0,
                rankingMs: 0
            )
        )
    }
    func endSession(id _: String?) -> UISessionMetrics? { nil }
    func currentSession() -> UISessionMetrics? { nil }
    func hintSession(query: String?, pid: pid_t, labelAlphabet: String, limit: Int) -> UIHintSession? {
        hintSession(query: query, labelAlphabet: labelAlphabet, limit: limit)
    }
    func listApplications() -> [RunningAppInfo] { [] }
    func debugDump(
        targetID _: String,
        pid _: pid_t?,
        labelAlphabet _: String,
        sessionID _: String?,
        snapshotID _: String?,
        scope _: UISearchScope,
        includeMenus _: Bool,
        maxDepth _: Int
    ) -> JSONValue? {
        nil
    }
}

protocol WindowControlling {
    func visibleWindows(excluding rules: [ExcludedWindowRule]) -> [VisibleWindow]
    func focus(windowID: Int?, title: String?, pid: Int32?) -> Bool
    func excludeRule(windowID: Int?, title: String?, pid: Int32?, excluding rules: [ExcludedWindowRule]) -> ExcludedWindowRule?
}

protocol ScrollControlling: AnyObject {
    func scrollTargets(from snapshot: TargetSnapshot) -> [TargetDescriptor]
    func focus(targetID: String)
    func startSession(targetID: String?, snapshot: TargetSnapshot) -> ScrollSession?
    func endSession() -> ScrollSession?
    func currentSession() -> ScrollSession?
    @discardableResult
    func step(direction: String, amount: Int, snapshot: TargetSnapshot) -> Bool
}

protocol MusicVolumeControlling {
    func currentVolume() async -> Int?
    func setVolume(_ value: Int) async -> (Bool, String)
}

protocol AirPlayControlling {
    func listDevices() async -> [String]
    func connect(device: String) async -> (Bool, String)
    func disconnect() async -> (Bool, String)
    func openMenu() async -> (Bool, String)
}

public struct UIHintSession: Sendable, Equatable, Codable {
    public var id: UUID
    public var query: String?
    public var alphabet: String
    public var generatedAt: Date
    public var snapshot: TargetSnapshot

    public init(
        id: UUID = UUID(),
        query: String?,
        alphabet: String,
        generatedAt: Date = Date(),
        snapshot: TargetSnapshot
    ) {
        self.id = id
        self.query = query
        self.alphabet = alphabet
        self.generatedAt = generatedAt
        self.snapshot = snapshot
    }
}

public struct ScrollSession: Sendable, Equatable, Codable {
    public var id: UUID
    public var targetID: String
    public var startedAt: Date
    public var lastStepAt: Date?
    public var stepCount: Int

    public init(
        id: UUID = UUID(),
        targetID: String,
        startedAt: Date = Date(),
        lastStepAt: Date? = nil,
        stepCount: Int = 0
    ) {
        self.id = id
        self.targetID = targetID
        self.startedAt = startedAt
        self.lastStepAt = lastStepAt
        self.stepCount = stepCount
    }
}

public enum LocalCapabilityAction: String, CaseIterable, Sendable {
    case uiHints = "ui.hints"
    case uiDrag = "ui.drag"
    case scrollSessionStart = "scroll.session_start"
    case scrollSessionEnd = "scroll.session_end"
    case textDetach = "text.detach"
    case textStatus = "text.status"
    case displayAirPlayDisconnect = "display.airplay_disconnect"
    case windowExclude = "window.exclude"
}

public enum LocalCapabilityRequestBridge {
    public static func makeRequest(
        action: LocalCapabilityAction,
        arguments: [String: JSONValue] = [:],
        origin: RequestOrigin = RequestOrigin(kind: .test)
    ) -> ActionRequest {
        var bridged = arguments

        switch action {
        case .uiHints:
            bridged["operation"] = .string("hints")
            return ActionRequest(action: .uiSearch, arguments: bridged, origin: origin)
        case .uiDrag:
            bridged["interaction"] = .string("drag")
            return ActionRequest(action: .uiAct, arguments: bridged, origin: origin)
        case .scrollSessionStart:
            bridged["operation"] = .string("session_start")
            return ActionRequest(action: .scrollFocus, arguments: bridged, origin: origin)
        case .scrollSessionEnd:
            bridged["operation"] = .string("session_end")
            return ActionRequest(action: .scrollFocus, arguments: bridged, origin: origin)
        case .textDetach:
            bridged["operation"] = .string("detach")
            return ActionRequest(action: .textAttach, arguments: bridged, origin: origin)
        case .textStatus:
            bridged["operation"] = .string("status")
            return ActionRequest(action: .textMode, arguments: bridged, origin: origin)
        case .displayAirPlayDisconnect:
            bridged["action"] = .string("disconnect")
            return ActionRequest(action: .displayAirPlayConnect, arguments: bridged, origin: origin)
        case .windowExclude:
            bridged["operation"] = .string("exclude")
            return ActionRequest(action: .windowFocus, arguments: bridged, origin: origin)
        }
    }
}

public struct GlobalKeyCaptureEvent: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        case keyDown
        case keyUp
        case flagsChanged
    }

    public var kind: Kind
    public var keyCode: UInt16
    public var characters: String
    public var modifiers: Set<TextKeyModifier>
    public var timestamp: Date

    public init(
        kind: Kind,
        keyCode: UInt16,
        characters: String,
        modifiers: Set<TextKeyModifier> = [],
        timestamp: Date = Date()
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.characters = characters
        self.modifiers = modifiers
        self.timestamp = timestamp
    }

    public var textEvent: TextKeyEvent {
        if let special = GlobalInputTranslator.specialKey(for: characters.lowercased()) {
            return TextKeyEvent.special(special, modifiers: modifiers)
        }
        return TextKeyEvent.character(characters, modifiers: modifiers)
    }
}

public protocol GlobalInputCapturing: AnyObject, Sendable {
    var isRunning: Bool { get }
    func start(handler: @escaping @Sendable (GlobalKeyCaptureEvent) -> Void)
    func stop()
}

public final class TestableGlobalInputCapture: GlobalInputCapturing, @unchecked Sendable {
    private var handler: (@Sendable (GlobalKeyCaptureEvent) -> Void)?
    public private(set) var isRunning = false

    public init() {}

    public func start(handler: @escaping @Sendable (GlobalKeyCaptureEvent) -> Void) {
        self.handler = handler
        isRunning = true
    }

    public func stop() {
        handler = nil
        isRunning = false
    }

    public func emit(_ event: GlobalKeyCaptureEvent) {
        handler?(event)
    }
}

public final class NSEventGlobalInputCapture: GlobalInputCapturing, @unchecked Sendable {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    public private(set) var isRunning = false

    public init() {}

    public func start(handler: @escaping @Sendable (GlobalKeyCaptureEvent) -> Void) {
        guard isRunning == false else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard let translated = GlobalInputTranslator.translate(event) else { return }
            handler(translated)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if let translated = GlobalInputTranslator.translate(event) {
                handler(translated)
            }
            return event
        }

        isRunning = true
    }

    public func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        isRunning = false
    }
}

public enum GlobalInputTranslator {
    public static func translate(_ event: NSEvent) -> GlobalKeyCaptureEvent? {
        let kind: GlobalKeyCaptureEvent.Kind
        switch event.type {
        case .keyDown:
            kind = .keyDown
        case .keyUp:
            kind = .keyUp
        case .flagsChanged:
            kind = .flagsChanged
        default:
            return nil
        }

        return GlobalKeyCaptureEvent(
            kind: kind,
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers ?? "",
            modifiers: modifiers(from: event.modifierFlags),
            timestamp: Date(timeIntervalSince1970: event.timestamp)
        )
    }

    public static func event(
        kind: GlobalKeyCaptureEvent.Kind,
        keyCode: UInt16,
        characters: String,
        modifiers: Set<TextKeyModifier> = [],
        timestamp: Date = Date()
    ) -> GlobalKeyCaptureEvent {
        GlobalKeyCaptureEvent(
            kind: kind,
            keyCode: keyCode,
            characters: characters,
            modifiers: modifiers,
            timestamp: timestamp
        )
    }

    public static func modifiers(from flags: NSEvent.ModifierFlags) -> Set<TextKeyModifier> {
        var result = Set<TextKeyModifier>()
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.function) { result.insert(.function) }
        return result
    }

    public static func specialKey(for token: String) -> TextSpecialKey? {
        switch token {
        case "\u{1b}", "esc", "escape":
            return .escape
        case "\r", "\n", "enter", "return":
            return .enter
        case "\t", "tab":
            return .tab
        case "\u{8}", "\u{7f}", "backspace", "bs":
            return .backspace
        case "space", " ":
            return .space
        default:
            return nil
        }
    }
}

extension TargetRect {
    init(_ rect: CGRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var center: CGPoint {
        CGPoint(x: x + (width / 2), y: y + (height / 2))
    }
}

extension TargetDescriptor {
    var payload: JSONValue {
        [
            "id": .string(id),
            "appName": .string(appName),
            "role": .string(role),
            "title": .string(title),
            "subtitle": subtitle.map(JSONValue.string) ?? .null,
            "value": value.map(JSONValue.string) ?? .null,
            "hint": hint.map(JSONValue.string) ?? .null,
            "path": .array(path.map(JSONValue.string)),
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

extension Array where Element == CapabilityStatus {
    var payload: JSONValue {
        .array(
            map { status in
                [
                    "name": .string(status.name),
                    "state": .string(status.state.rawValue),
                    "detail": .string(status.detail),
                ]
            }
        )
    }
}

extension UIHintSession {
    var payload: JSONValue {
        [
            "id": .string(id.uuidString),
            "query": query.map(JSONValue.string) ?? .null,
            "alphabet": .string(alphabet),
            "generatedAt": .string(ISO8601DateFormatter().string(from: generatedAt)),
            "appName": .string(snapshot.appName),
            "bundleIdentifier": snapshot.bundleIdentifier.map(JSONValue.string) ?? .null,
            "windowTitle": snapshot.windowTitle.map(JSONValue.string) ?? .null,
            "targets": .array(snapshot.targets.map(\.payload)),
        ]
    }
}

extension ScrollSession {
    var payload: JSONValue {
        [
            "id": .string(id.uuidString),
            "targetID": .string(targetID),
            "startedAt": .string(ISO8601DateFormatter().string(from: startedAt)),
            "lastStepAt": lastStepAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
            "stepCount": .number(Double(stepCount)),
        ]
    }
}

enum LabelGenerator {
    static func labels(count: Int, alphabet: String) -> [String] {
        guard count > 0 else { return [] }

        let symbols = Array(Set(alphabet)).map(String.init).sorted()
        guard symbols.isEmpty == false else {
            return (0..<count).map { "\($0)" }
        }

        var labels: [String] = []
        var index = 0

        while labels.count < count {
            labels.append(label(for: index, symbols: symbols))
            index += 1
        }

        return labels
    }

    private static func label(for index: Int, symbols: [String]) -> String {
        var value = index
        var result: [String] = []

        repeat {
            result.append(symbols[value % symbols.count])
            value = (value / symbols.count) - 1
        } while value >= 0

        return result.reversed().joined()
    }
}

enum AccessibilityTraversalHeuristics {
    static let visibleRowsAttribute = "AXVisibleRows"

    private static let listLikeRoles: Set<String> = [
        kAXTableRole as String,
        kAXListRole as String,
        "AXOutline",
        "AXBrowser",
    ]

    private static let supplementalChildAttributes = [
        kAXTabsAttribute,
        kAXColumnsAttribute,
        kAXContentsAttribute,
        kAXVisibleChildrenAttribute,
    ]

    private static let structuralRoleFragments = [
        "application",
        "window",
        "sheet",
        "scrollarea",
        "scroll",
        "group",
        "list",
        "outline",
        "row",
        "cell",
        "table",
        "column",
        "splitgroup",
        "browser",
    ]

    static func isListLikeRole(_ role: String) -> Bool {
        listLikeRoles.contains(role)
    }

    static func orderedChildAttributes(parentRole: String) -> [String] {
        if isListLikeRole(parentRole) {
            return [visibleRowsAttribute, kAXRowsAttribute, kAXChildrenAttribute] + supplementalChildAttributes
        }
        return [kAXChildrenAttribute] + supplementalChildAttributes
    }

    static func nextDepth(currentDepth: Int, parentRole: String) -> Int {
        let loweredRole = parentRole.lowercased()
        if structuralRoleFragments.contains(where: loweredRole.contains) {
            return currentDepth
        }
        return currentDepth + 1
    }
}

enum AXElementValueParser {
    static func elements(from value: CFTypeRef?) -> [AXUIElement] {
        guard let value else { return [] }
        return elements(fromAny: value)
    }

    private static func elements(fromAny value: Any) -> [AXUIElement] {
        let object = value as AnyObject
        if CFGetTypeID(object) == AXUIElementGetTypeID() {
            return [object as! AXUIElement]
        }

        if let array = value as? [Any] {
            return array.flatMap(elements(fromAny:))
        }

        if let array = value as? NSArray {
            return array.flatMap(elements(fromAny:))
        }

        return []
    }
}

enum AXDebugValueSerializer {
    static func jsonValue(from value: CFTypeRef?) -> JSONValue {
        guard let value else { return .null }

        if let text = value as? String {
            return .string(text)
        }

        if let text = value as? NSAttributedString {
            return .string(text.string)
        }

        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(number.doubleValue)
        }

        if CFGetTypeID(value) == AXValueGetTypeID() {
            return serialize(value as! AXValue)
        }

        if CFGetTypeID(value) == AXUIElementGetTypeID() {
            var pid: pid_t = 0
            AXUIElementGetPid(value as! AXUIElement, &pid)
            return [
                "type": .string("AXUIElement"),
                "pid": .number(Double(pid)),
                "hash": .number(Double(CFHash(value))),
            ]
        }

        if let array = value as? [Any] {
            return .array(array.map(jsonValue(any:)))
        }

        if let array = value as? NSArray {
            return .array(array.map(jsonValue(any:)))
        }

        let typeName = CFCopyTypeIDDescription(CFGetTypeID(value)) as String? ?? String(describing: type(of: value))
        return [
            "type": .string(typeName),
            "description": .string(String(describing: value)),
        ]
    }

    private static func jsonValue(any value: Any) -> JSONValue {
        if value is NSNull {
            return .null
        }
        return jsonValue(from: value as AnyObject)
    }

    private static func serialize(_ axValue: AXValue) -> JSONValue {
        switch AXValueGetType(axValue) {
        case .cgPoint:
            var point = CGPoint.zero
            guard AXValueGetValue(axValue, .cgPoint, &point) else { return axValueFallback(axValue) }
            return [
                "type": .string("CGPoint"),
                "x": .number(point.x),
                "y": .number(point.y),
            ]
        case .cgSize:
            var size = CGSize.zero
            guard AXValueGetValue(axValue, .cgSize, &size) else { return axValueFallback(axValue) }
            return [
                "type": .string("CGSize"),
                "width": .number(size.width),
                "height": .number(size.height),
            ]
        case .cgRect:
            var rect = CGRect.zero
            guard AXValueGetValue(axValue, .cgRect, &rect) else { return axValueFallback(axValue) }
            return [
                "type": .string("CGRect"),
                "x": .number(rect.origin.x),
                "y": .number(rect.origin.y),
                "width": .number(rect.width),
                "height": .number(rect.height),
            ]
        case .cfRange:
            var range = CFRange()
            guard AXValueGetValue(axValue, .cfRange, &range) else { return axValueFallback(axValue) }
            return [
                "type": .string("CFRange"),
                "location": .number(Double(range.location)),
                "length": .number(Double(range.length)),
            ]
        default:
            return axValueFallback(axValue)
        }
    }

    private static func axValueFallback(_ axValue: AXValue) -> JSONValue {
        [
            "type": .string("AXValue"),
            "axValueType": .number(Double(AXValueGetType(axValue).rawValue)),
        ]
    }
}

enum FuzzyMatcher {
    static func score(query: String, in target: TargetDescriptor) -> Int {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return 1 }

        let haystack = [
            target.title,
            target.subtitle ?? "",
            target.value ?? "",
            target.role,
            target.path.joined(separator: " "),
        ]
        .joined(separator: " ")
        .lowercased()

        let tokens = trimmed.lowercased().split(whereSeparator: \.isWhitespace)
        guard tokens.isEmpty == false else { return 0 }

        var score = 0
        for token in tokens {
            if haystack.contains(token) {
                score += 10
            } else if token.allSatisfy({ haystack.contains($0) }) {
                score += 3
            } else {
                return 0
            }
        }

        if haystack.hasPrefix(trimmed.lowercased()) {
            score += 5
        }

        return score
    }
}

enum SemanticTargetRanker {
    private struct RankedTarget {
        let target: TargetDescriptor
        let score: Int
        let directMatch: Bool
        let proximity: Double
    }

    static func rankedTargets(in snapshot: TargetSnapshot, query: String, limit: Int) -> [TargetDescriptor] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            return Array(snapshot.targets.prefix(limit))
        }

        let directScores = snapshot.targets.reduce(into: [String: Int]()) { scores, target in
            let score = FuzzyMatcher.score(query: trimmedQuery, in: target)
            if score > 0 {
                scores[target.id] = score
            }
        }

        let anchors = snapshot.targets.compactMap { target -> (TargetDescriptor, Int)? in
            guard let score = directScores[target.id], isTextualAnchor(target) else { return nil }
            return (target, score)
        }

        let combinedScores = snapshot.targets.reduce(into: directScores) { scores, target in
            for (anchor, anchorScore) in anchors {
                let adjacentScore = adjacentActionScore(candidate: target, anchor: anchor, anchorScore: anchorScore)
                guard adjacentScore > 0 else { continue }
                scores[target.id] = max(scores[target.id] ?? 0, adjacentScore)
            }
        }

        return snapshot.targets
            .compactMap { target -> RankedTarget? in
                guard let score = combinedScores[target.id], score > 0 else { return nil }
                return RankedTarget(
                    target: target,
                    score: score,
                    directMatch: directScores[target.id] != nil,
                    proximity: nearestAnchorDistance(for: target, anchors: anchors.map(\.0))
                )
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                if lhs.directMatch != rhs.directMatch {
                    return lhs.directMatch && !rhs.directMatch
                }
                if lhs.proximity != rhs.proximity {
                    return lhs.proximity < rhs.proximity
                }
                return lhs.target.title.localizedCaseInsensitiveCompare(rhs.target.title) == .orderedAscending
            }
            .prefix(limit)
            .map(\.target)
    }

    private static func adjacentActionScore(candidate: TargetDescriptor, anchor: TargetDescriptor, anchorScore: Int) -> Int {
        guard candidate.id != anchor.id else { return 0 }
        guard isAdjacentActionableCandidate(candidate) else { return 0 }
        guard let candidateFrame = candidate.frame?.cgRect, let anchorFrame = anchor.frame?.cgRect else { return 0 }

        let sharedPrefix = sharedPathPrefixLength(candidate.path, anchor.path)
        guard sharedPrefix >= 4 else { return 0 }

        let centerYDistance = abs(candidateFrame.midY - anchorFrame.midY)
        let maxAllowedCenterYDistance = max(candidateFrame.height, anchorFrame.height) * 0.9
        let verticalOverlap = max(0, min(candidateFrame.maxY, anchorFrame.maxY) - max(candidateFrame.minY, anchorFrame.minY))
        guard verticalOverlap > 0 || centerYDistance <= maxAllowedCenterYDistance else { return 0 }

        let horizontalGap: CGFloat
        if candidateFrame.maxX < anchorFrame.minX {
            horizontalGap = anchorFrame.minX - candidateFrame.maxX
        } else if anchorFrame.maxX < candidateFrame.minX {
            horizontalGap = candidateFrame.minX - anchorFrame.maxX
        } else {
            horizontalGap = 0
        }
        guard horizontalGap <= 120 else { return 0 }

        var score = anchorScore + 40
        score += min(sharedPrefix, 8) * 4
        score += verticalOverlap > 0 ? 35 : 15
        score += max(0, 30 - Int(horizontalGap))

        if candidateFrame.maxX <= anchorFrame.minX || anchorFrame.maxX <= candidateFrame.minX {
            score += 10
        }

        let loweredRole = candidate.role.lowercased()
        if loweredRole.contains("checkbox") {
            score += 15
        } else if loweredRole.contains("button") {
            score += 12
        } else if loweredRole.contains("image") {
            score += 8
        }

        return score
    }

    private static func isTextualAnchor(_ target: TargetDescriptor) -> Bool {
        let loweredRole = target.role.lowercased()
        let searchableText = [target.title, target.subtitle ?? "", target.value ?? ""]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard searchableText.isEmpty == false else { return false }
        return loweredRole.contains("text") || loweredRole.contains("row") || loweredRole.contains("cell")
    }

    private static func isAdjacentActionableCandidate(_ target: TargetDescriptor) -> Bool {
        let loweredRole = target.role.lowercased()
        if loweredRole.contains("button") || loweredRole.contains("checkbox") || loweredRole.contains("link") || loweredRole.contains("radio") {
            return true
        }

        guard loweredRole.contains("image"), let frame = target.frame else { return false }
        return max(frame.width, frame.height) <= 44
    }

    private static func sharedPathPrefixLength(_ lhs: [String], _ rhs: [String]) -> Int {
        zip(lhs, rhs).prefix { $0 == $1 }.count
    }

    private static func nearestAnchorDistance(for target: TargetDescriptor, anchors: [TargetDescriptor]) -> Double {
        guard let targetFrame = target.frame?.center else { return .greatestFiniteMagnitude }
        return anchors.compactMap { anchor -> Double? in
            guard let anchorFrame = anchor.frame?.center else { return nil }
            let dx = targetFrame.x - anchorFrame.x
            let dy = targetFrame.y - anchorFrame.y
            return Double((dx * dx) + (dy * dy)).squareRoot()
        }
        .min() ?? .greatestFiniteMagnitude
    }
}
