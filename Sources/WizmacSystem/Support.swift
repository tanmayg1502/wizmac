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

protocol AutomationSleeping {
    func sleep(milliseconds: Int) async
}

struct TaskAutomationSleeper: AutomationSleeping {
    func sleep(milliseconds: Int) async {
        guard milliseconds > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }
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

struct SynthesizedKeyEvent: Sendable, Equatable {
    enum Kind: String, Sendable, Equatable {
        case keyDown
        case keyUp
    }

    var kind: Kind
    var keyCode: CGKeyCode
    var characters: String
    var modifiers: Set<TextKeyModifier>

    init(
        kind: Kind,
        keyCode: CGKeyCode,
        characters: String = "",
        modifiers: Set<TextKeyModifier> = []
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.characters = characters
        self.modifiers = modifiers
    }
}

protocol KeyboardAutomationPerforming {
    @discardableResult
    func post(events: [SynthesizedKeyEvent]) -> Bool
}

struct CGKeyboardAutomationPerformer: KeyboardAutomationPerforming {
    @discardableResult
    func post(events: [SynthesizedKeyEvent]) -> Bool {
        for event in events {
            guard let cgEvent = CGEvent(
                keyboardEventSource: nil,
                virtualKey: event.keyCode,
                keyDown: event.kind == .keyDown
            ) else {
                return false
            }

            cgEvent.flags = event.modifiers.cgEventFlags
            if event.characters.isEmpty == false {
                let unicodeScalars = Array(event.characters.utf16)
                cgEvent.keyboardSetUnicodeString(
                    stringLength: unicodeScalars.count,
                    unicodeString: unicodeScalars
                )
            }
            cgEvent.post(tap: .cghidEventTap)
        }

        return true
    }
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
        includeMenus: Bool,
        bypassCache: Bool
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
    func sessionSnapshot(id: String?) -> TargetSnapshot?
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
        includeMenus _: Bool,
        bypassCache _: Bool
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
    func search(
        query: String,
        pid: pid_t?,
        labelAlphabet: String,
        limit: Int,
        sessionID: String?,
        scope: UISearchScope,
        includeMenus: Bool
    ) -> UISearchResult? {
        search(
            query: query,
            pid: pid,
            labelAlphabet: labelAlphabet,
            limit: limit,
            sessionID: sessionID,
            scope: scope,
            includeMenus: includeMenus,
            bypassCache: false
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
    func sessionSnapshot(id _: String?) -> TargetSnapshot? { nil }
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
    func matchingWindow(windowID: Int?, title: String?, query: String?, pid: Int32?, excluding rules: [ExcludedWindowRule]) -> VisibleWindow?
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

extension Set where Element == TextKeyModifier {
    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }
}

struct KeyboardResolvedKey: Sendable, Equatable {
    var keyCode: CGKeyCode
    var characters: String
    var implicitModifiers: Set<TextKeyModifier>
}

enum KeyboardKeyResolver {
    private static let baseKeyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
        "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50
    ]

    private static let shiftedCharacters: [String: (String, CGKeyCode)] = [
        "!": ("!", 18), "@": ("@", 19), "#": ("#", 20), "$": ("$", 21),
        "^": ("^", 22), "%": ("%", 23), "+": ("+", 24), "(": ("(", 25),
        "&": ("&", 26), "_": ("_", 27), "*": ("*", 28), ")": (")", 29),
        "}": ("}", 30), "{": ("{", 33), ":": (":", 41), "\"": ("\"", 39),
        "|": ("|", 42), "<": ("<", 43), "?": ("?", 44), ">": (">", 47),
        "~": ("~", 50)
    ]

    private static let namedKeys: [String: KeyboardResolvedKey] = [
        "return": KeyboardResolvedKey(keyCode: 36, characters: "\r", implicitModifiers: []),
        "enter": KeyboardResolvedKey(keyCode: 36, characters: "\r", implicitModifiers: []),
        "tab": KeyboardResolvedKey(keyCode: 48, characters: "\t", implicitModifiers: []),
        "space": KeyboardResolvedKey(keyCode: 49, characters: " ", implicitModifiers: []),
        "backspace": KeyboardResolvedKey(keyCode: 51, characters: "\u{8}", implicitModifiers: []),
        "delete": KeyboardResolvedKey(keyCode: 51, characters: "\u{8}", implicitModifiers: []),
        "escape": KeyboardResolvedKey(keyCode: 53, characters: "\u{1b}", implicitModifiers: []),
        "esc": KeyboardResolvedKey(keyCode: 53, characters: "\u{1b}", implicitModifiers: []),
        "command": KeyboardResolvedKey(keyCode: 55, characters: "", implicitModifiers: []),
        "cmd": KeyboardResolvedKey(keyCode: 55, characters: "", implicitModifiers: []),
        "shift": KeyboardResolvedKey(keyCode: 56, characters: "", implicitModifiers: []),
        "option": KeyboardResolvedKey(keyCode: 58, characters: "", implicitModifiers: []),
        "alt": KeyboardResolvedKey(keyCode: 58, characters: "", implicitModifiers: []),
        "control": KeyboardResolvedKey(keyCode: 59, characters: "", implicitModifiers: []),
        "ctrl": KeyboardResolvedKey(keyCode: 59, characters: "", implicitModifiers: []),
        "function": KeyboardResolvedKey(keyCode: 63, characters: "", implicitModifiers: []),
        "fn": KeyboardResolvedKey(keyCode: 63, characters: "", implicitModifiers: []),
        "home": KeyboardResolvedKey(keyCode: 115, characters: "", implicitModifiers: []),
        "pageup": KeyboardResolvedKey(keyCode: 116, characters: "", implicitModifiers: []),
        "forwarddelete": KeyboardResolvedKey(keyCode: 117, characters: "", implicitModifiers: []),
        "deleteforward": KeyboardResolvedKey(keyCode: 117, characters: "", implicitModifiers: []),
        "end": KeyboardResolvedKey(keyCode: 119, characters: "", implicitModifiers: []),
        "pagedown": KeyboardResolvedKey(keyCode: 121, characters: "", implicitModifiers: []),
        "left": KeyboardResolvedKey(keyCode: 123, characters: "", implicitModifiers: []),
        "leftarrow": KeyboardResolvedKey(keyCode: 123, characters: "", implicitModifiers: []),
        "right": KeyboardResolvedKey(keyCode: 124, characters: "", implicitModifiers: []),
        "rightarrow": KeyboardResolvedKey(keyCode: 124, characters: "", implicitModifiers: []),
        "down": KeyboardResolvedKey(keyCode: 125, characters: "", implicitModifiers: []),
        "downarrow": KeyboardResolvedKey(keyCode: 125, characters: "", implicitModifiers: []),
        "up": KeyboardResolvedKey(keyCode: 126, characters: "", implicitModifiers: []),
        "uparrow": KeyboardResolvedKey(keyCode: 126, characters: "", implicitModifiers: [])
    ]

    static func resolve(_ rawKey: String) -> KeyboardResolvedKey? {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let normalized = trimmed
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        if let named = namedKeys[normalized] {
            return named
        }

        if trimmed.count == 1, let scalar = trimmed.unicodeScalars.first {
            let character = String(scalar)
            if let shifted = shiftedCharacters[character] {
                return KeyboardResolvedKey(
                    keyCode: shifted.1,
                    characters: shifted.0,
                    implicitModifiers: [.shift]
                )
            }

            let lowered = character.lowercased()
            if let keyCode = baseKeyCodes[lowered] {
                var modifiers: Set<TextKeyModifier> = []
                if character != lowered {
                    modifiers.insert(.shift)
                }
                return KeyboardResolvedKey(
                    keyCode: keyCode,
                    characters: character,
                    implicitModifiers: modifiers
                )
            }
        }

        if normalized.count >= 2,
           normalized.first == "f",
           let number = Int(normalized.dropFirst()),
           let keyCode = functionKeyCode(for: number) {
            return KeyboardResolvedKey(keyCode: keyCode, characters: "", implicitModifiers: [])
        }

        return nil
    }

    private static func functionKeyCode(for number: Int) -> CGKeyCode? {
        switch number {
        case 1: return 122
        case 2: return 120
        case 3: return 99
        case 4: return 118
        case 5: return 96
        case 6: return 97
        case 7: return 98
        case 8: return 100
        case 9: return 101
        case 10: return 109
        case 11: return 103
        case 12: return 111
        case 13: return 105
        case 14: return 107
        case 15: return 113
        case 16: return 106
        case 17: return 64
        case 18: return 79
        case 19: return 80
        case 20: return 90
        default: return nil
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
    private struct SearchTextComponents {
        let raw: String
        let normalized: String
        let mentionAgnosticNormalized: String
        let tokens: [String]
        let mentionAgnosticTokens: [String]

        init(_ text: String) {
            raw = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            normalized = Self.normalizedText(from: raw)
            mentionAgnosticNormalized = Self.mentionAgnosticText(from: normalized)
            tokens = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
            mentionAgnosticTokens = mentionAgnosticNormalized.split(whereSeparator: \.isWhitespace).map(String.init)
        }

        private static func normalizedText(from text: String) -> String {
            var scalars: [UnicodeScalar] = []
            var previousWasSpace = false

            for scalar in text.unicodeScalars {
                if CharacterSet.alphanumerics.contains(scalar) || scalar == "@" || scalar == "#" {
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

        private static func mentionAgnosticText(from normalizedText: String) -> String {
            normalizedText
                .split(whereSeparator: \.isWhitespace)
                .map { token -> String in
                    var next = String(token)
                    while next.hasPrefix("@") || next.hasPrefix("#") {
                        next.removeFirst()
                    }
                    return next
                }
                .joined(separator: " ")
        }
    }

    static func score(query: String, in target: TargetDescriptor) -> Int {
        let directScore = directTextScore(query: query, in: target)
        if directScore > 0 {
            return directScore + directMatchPriority(for: target)
        }

        return structuralScore(query: query, in: target)
    }

    static func directTextScore(query: String, in target: TargetDescriptor) -> Int {
        let queryComponents = SearchTextComponents(query)
        guard queryComponents.raw.isEmpty == false else { return 0 }

        let fields = searchableFields(for: target)
        let fieldBiases = [20, 18, 14]

        return zip(fields, fieldBiases)
            .map { field, fieldBias in
                fieldMatchScore(field: field, query: queryComponents, fieldBias: fieldBias)
            }
            .max() ?? 0
    }

    static func strictTextScore(query: String, in target: TargetDescriptor) -> Int {
        let queryComponents = SearchTextComponents(query)
        guard queryComponents.raw.isEmpty == false else { return 0 }

        let fields = searchableFields(for: target)
        let fieldBiases = [20, 18, 14]

        return zip(fields, fieldBiases)
            .map { field, fieldBias in
                strictFieldMatchScore(field: field, query: queryComponents, fieldBias: fieldBias)
            }
            .max() ?? 0
    }

    static func structuralScore(query: String, in target: TargetDescriptor) -> Int {
        let queryComponents = SearchTextComponents(query)
        guard queryComponents.raw.isEmpty == false else { return 0 }

        let roleComponents = SearchTextComponents(target.role)
        var bestScore = 0

        if roleComponents.raw == queryComponents.raw || roleComponents.normalized == queryComponents.normalized {
            bestScore = 36
        } else if queryComponents.raw.count >= 3,
                  roleComponents.raw.contains(queryComponents.raw) ||
                    (queryComponents.normalized.isEmpty == false && roleComponents.normalized.contains(queryComponents.normalized)) {
            bestScore = 24
        }

        let pathComponents = SearchTextComponents(target.path.joined(separator: " "))
        let pathTokenScore = min(tokenCoverageScore(queryTokens: queryComponents.tokens, fieldTokens: pathComponents.tokens), 18)
        bestScore = max(bestScore, pathTokenScore)

        return bestScore
    }

    static func exactMatchScore(query: String, in target: TargetDescriptor) -> Int {
        let queryComponents = SearchTextComponents(query)
        guard queryComponents.raw.isEmpty == false else { return 0 }

        let bestFieldScore = searchableFields(for: target)
            .map { exactFieldScore(field: $0, query: queryComponents) }
            .max() ?? 0
        guard bestFieldScore > 0 else { return 0 }

        return bestFieldScore + directMatchPriority(for: target)
    }

    static func isExactMatch(query: String, in target: TargetDescriptor) -> Bool {
        exactMatchScore(query: query, in: target) > 0
    }

    static func searchableFields(for target: TargetDescriptor) -> [String] {
        [
            meaningfulTitle(for: target),
            target.value ?? "",
            target.subtitle ?? "",
        ]
    }

    private static func fieldMatchScore(field: String, query: SearchTextComponents, fieldBias: Int) -> Int {
        let fieldComponents = SearchTextComponents(field)
        guard fieldComponents.raw.isEmpty == false else { return 0 }

        var score = 0

        if fieldComponents.raw == query.raw {
            score = max(score, 180)
        } else if fieldComponents.normalized == query.normalized, query.normalized.isEmpty == false {
            score = max(score, 175)
        }

        if query.raw.count >= 2 {
            if fieldComponents.raw.hasPrefix(query.raw) {
                score = max(score, 145)
            } else if query.normalized.isEmpty == false, fieldComponents.normalized.hasPrefix(query.normalized) {
                score = max(score, 140)
            }

            if fieldComponents.raw.contains(query.raw) {
                score = max(score, 130)
            } else if query.normalized.isEmpty == false, fieldComponents.normalized.contains(query.normalized) {
                score = max(score, 125)
            }
        }

        if query.mentionAgnosticNormalized.isEmpty == false,
           fieldComponents.mentionAgnosticNormalized.isEmpty == false {
            if fieldComponents.mentionAgnosticNormalized == query.mentionAgnosticNormalized {
                score = max(score, 116)
            } else if fieldComponents.mentionAgnosticNormalized.hasPrefix(query.mentionAgnosticNormalized) {
                score = max(score, 104)
            } else if fieldComponents.mentionAgnosticNormalized.contains(query.mentionAgnosticNormalized) {
                score = max(score, 96)
            }
        }

        let tokenScore = tokenCoverageScore(queryTokens: query.tokens, fieldTokens: fieldComponents.tokens)
        if tokenScore > 0 {
            score = max(score, tokenScore)
        }

        let mentionAgnosticTokenScore = tokenCoverageScore(
            queryTokens: query.mentionAgnosticTokens,
            fieldTokens: fieldComponents.mentionAgnosticTokens
        )
        if mentionAgnosticTokenScore > 0 {
            score = max(score, max(mentionAgnosticTokenScore - 8, 0))
        }

        return score > 0 ? score + fieldBias : 0
    }

    private static func strictFieldMatchScore(field: String, query: SearchTextComponents, fieldBias: Int) -> Int {
        let fieldComponents = SearchTextComponents(field)
        guard fieldComponents.raw.isEmpty == false else { return 0 }

        var score = 0

        if fieldComponents.raw == query.raw {
            score = max(score, 180)
        } else if fieldComponents.normalized == query.normalized, query.normalized.isEmpty == false {
            score = max(score, 175)
        }

        if query.raw.count >= 2 {
            if fieldComponents.raw.hasPrefix(query.raw) {
                score = max(score, 145)
            } else if query.normalized.isEmpty == false, fieldComponents.normalized.hasPrefix(query.normalized) {
                score = max(score, 140)
            }

            if fieldComponents.raw.contains(query.raw) {
                score = max(score, 130)
            } else if query.normalized.isEmpty == false, fieldComponents.normalized.contains(query.normalized) {
                score = max(score, 125)
            }
        }

        if query.mentionAgnosticNormalized.isEmpty == false,
           fieldComponents.mentionAgnosticNormalized.isEmpty == false {
            if fieldComponents.mentionAgnosticNormalized == query.mentionAgnosticNormalized {
                score = max(score, 116)
            } else if fieldComponents.mentionAgnosticNormalized.hasPrefix(query.mentionAgnosticNormalized) {
                score = max(score, 104)
            } else if fieldComponents.mentionAgnosticNormalized.contains(query.mentionAgnosticNormalized) {
                score = max(score, 96)
            }
        }

        return score > 0 ? score + fieldBias : 0
    }

    private static func tokenCoverageScore(queryTokens: [String], fieldTokens: [String]) -> Int {
        guard queryTokens.isEmpty == false, fieldTokens.isEmpty == false else { return 0 }

        var exactMatches = 0
        var prefixMatches = 0

        for token in queryTokens {
            if fieldTokens.contains(token) {
                exactMatches += 1
                continue
            }

            if token.count >= 4,
               fieldTokens.contains(where: { fieldToken in
                   fieldToken.count >= 4 && (fieldToken.hasPrefix(token) || token.hasPrefix(fieldToken))
               }) {
                prefixMatches += 1
            }
        }

        let totalMatches = exactMatches + prefixMatches
        guard totalMatches > 0 else { return 0 }

        var score = (exactMatches * 14) + (prefixMatches * 6)
        if totalMatches == queryTokens.count {
            score += 28
        }
        if exactMatches == queryTokens.count {
            score += 20
        }
        if tokensAppearInOrder(queryTokens: queryTokens, fieldTokens: fieldTokens) {
            score += 10
        }
        if queryTokens.count == 1, exactMatches == 1 {
            score += 16
        }
        return score
    }

    private static func tokensAppearInOrder(queryTokens: [String], fieldTokens: [String]) -> Bool {
        guard queryTokens.isEmpty == false, fieldTokens.isEmpty == false else { return false }

        var cursor = 0
        for fieldToken in fieldTokens {
            guard cursor < queryTokens.count else { break }
            let queryToken = queryTokens[cursor]
            let orderedMatch = fieldToken == queryToken ||
                (queryToken.count >= 4 && fieldToken.count >= 4 && (fieldToken.hasPrefix(queryToken) || queryToken.hasPrefix(fieldToken)))
            if orderedMatch {
                cursor += 1
            }
        }
        return cursor == queryTokens.count
    }

    private static func exactFieldScore(field: String, query: SearchTextComponents) -> Int {
        let fieldComponents = SearchTextComponents(field)
        guard fieldComponents.raw.isEmpty == false else { return 0 }

        if fieldComponents.raw == query.raw || (query.normalized.isEmpty == false && fieldComponents.normalized == query.normalized) {
            return 160
        }

        if query.mentionAgnosticNormalized.isEmpty == false,
           fieldComponents.mentionAgnosticNormalized == query.mentionAgnosticNormalized {
            return 108
        }

        if query.raw.count >= 3 {
            if fieldComponents.raw.hasPrefix(query.raw) {
                return 120
            }
            if query.normalized.isEmpty == false, fieldComponents.normalized.hasPrefix(query.normalized) {
                return 115
            }
            if query.mentionAgnosticNormalized.isEmpty == false,
               fieldComponents.mentionAgnosticNormalized.hasPrefix(query.mentionAgnosticNormalized) {
                return 92
            }
        }

        if query.raw.count >= 4,
           (fieldComponents.raw.contains(query.raw) ||
                (query.normalized.isEmpty == false && fieldComponents.normalized.contains(query.normalized))),
           fieldComponents.raw.count <= query.raw.count + 8 {
            return 100
        }

        if query.mentionAgnosticNormalized.count >= 3,
           fieldComponents.mentionAgnosticNormalized.contains(query.mentionAgnosticNormalized),
           fieldComponents.mentionAgnosticNormalized.count <= query.mentionAgnosticNormalized.count + 8 {
            return 84
        }

        return 0
    }

    private static func meaningfulTitle(for target: TargetDescriptor) -> String {
        let trimmedTitle = target.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty == false else { return "" }
        if trimmedTitle.caseInsensitiveCompare(target.role) == .orderedSame {
            return ""
        }
        return trimmedTitle
    }

    private static func directMatchPriority(for target: TargetDescriptor) -> Int {
        let loweredRole = target.role.lowercased()
        if loweredRole.contains("radio") || loweredRole.contains("checkbox") || loweredRole.contains("button") || loweredRole.contains("popup") {
            return 20
        }
        if loweredRole.contains("link") {
            return 16
        }
        if loweredRole.contains("text") || loweredRole.contains("heading") || loweredRole.contains("row") || loweredRole.contains("cell") {
            return 12
        }
        return 0
    }
}

enum SemanticTargetRanker {
    private struct RankedTarget {
        let target: TargetDescriptor
        let score: Int
        let directMatch: Bool
        let proximity: Double
    }

    private static let exactMatchBonus = 1000
    private static let directMatchBonus = 700
    private static let strongAnchorMinimum = 100
    private static let siblingBoostMinimum = 100

    static func rankedTargets(in snapshot: TargetSnapshot, query: String, limit: Int) -> [TargetDescriptor] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            return Array(snapshot.targets.prefix(limit))
        }

        let exactMatches = snapshot.targets
            .filter { FuzzyMatcher.isExactMatch(query: trimmedQuery, in: $0) }
            .sorted { lhs, rhs in
                let leftScore = FuzzyMatcher.exactMatchScore(query: trimmedQuery, in: lhs)
                let rightScore = FuzzyMatcher.exactMatchScore(query: trimmedQuery, in: rhs)
                if leftScore != rightScore {
                    return leftScore > rightScore
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        let exactMatchIDs = Set(exactMatches.map(\.id))

        let directTextScores = snapshot.targets.reduce(into: [String: Int]()) { scores, target in
            let score = FuzzyMatcher.directTextScore(query: trimmedQuery, in: target)
            if score > 0 {
                scores[target.id] = score
            }
        }

        let structuralScores = snapshot.targets.reduce(into: [String: Int]()) { scores, target in
            guard directTextScores[target.id] == nil else { return }
            let score = FuzzyMatcher.structuralScore(query: trimmedQuery, in: target)
            if score > 0 {
                scores[target.id] = score
            }
        }

        let directScores = snapshot.targets.reduce(into: structuralScores) { scores, target in
            guard let directTextScore = directTextScores[target.id] else { return }
            if FuzzyMatcher.isExactMatch(query: trimmedQuery, in: target) {
                scores[target.id] = directTextScore + exactMatchBonus
            } else {
                scores[target.id] = directTextScore + directMatchBonus
            }
        }

        let anchors = snapshot.targets.compactMap { target -> (TargetDescriptor, Int)? in
            guard let score = directTextScores[target.id], score >= strongAnchorMinimum, isTextualAnchor(target) else { return nil }
            return (target, score)
        }

        let directMatchTargets = snapshot.targets.compactMap { target -> (TargetDescriptor, Int)? in
            guard let score = directTextScores[target.id], score >= siblingBoostMinimum else { return nil }
            return (target, score)
        }

        let combinedScores = snapshot.targets.reduce(into: directScores) { scores, target in
            for (anchor, anchorScore) in anchors {
                let adjacentScore = adjacentActionScore(candidate: target, anchor: anchor, anchorScore: anchorScore)
                guard adjacentScore > 0 else { continue }
                scores[target.id] = max(scores[target.id] ?? 0, adjacentScore)
            }
            if scores[target.id] == nil {
                let siblingScore = containerSiblingScore(candidate: target, directMatches: directMatchTargets)
                if siblingScore > 0 {
                    scores[target.id] = siblingScore
                }
            }
        }

        let rankedTargets = snapshot.targets
            .compactMap { target -> RankedTarget? in
                guard let score = combinedScores[target.id], score > 0 else { return nil }
                return RankedTarget(
                    target: target,
                    score: score,
                    directMatch: directTextScores[target.id] != nil,
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
            .map(\.target)

        return Array((exactMatches + rankedTargets.filter { exactMatchIDs.contains($0.id) == false }).prefix(limit))
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

    private static func containerSiblingScore(candidate: TargetDescriptor, directMatches: [(TargetDescriptor, Int)]) -> Int {
        for (match, matchScore) in directMatches {
            guard candidate.id != match.id else { continue }
            let candidateParent = candidate.path.dropLast()
            let matchParent = match.path.dropLast()
            guard candidateParent.count >= 3,
                  Array(candidateParent) == Array(matchParent) else { continue }
            return min(matchScore, 15) + 50
        }
        return 0
    }

    private static func isTextualAnchor(_ target: TargetDescriptor) -> Bool {
        let loweredRole = target.role.lowercased()
        let searchableText = FuzzyMatcher.searchableFields(for: target)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard searchableText.isEmpty == false else { return false }

        if loweredRole.contains("text") || loweredRole.contains("row") || loweredRole.contains("cell") {
            return true
        }
        if loweredRole.contains("button") || loweredRole.contains("link") {
            return searchableText.count >= 2
        }
        return false
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

struct StableTargetIdentity: Sendable, Equatable {
    var appName: String
    var role: String
    var title: String
    var value: String?
    var path: [String]
    var frame: TargetRect?

    static func decode(from targetID: String) -> StableTargetIdentity? {
        guard let data = Data(base64Encoded: targetID),
              let raw = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let parts = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 6 else { return nil }

        let appName = parts[0]
        let role = parts[1]
        let path = parts[parts.count - 2].split(separator: "/").map(String.init)
        let frame = decodeFrame(parts[parts.count - 1])
        let middleComponents = Array(parts[2..<(parts.count - 2)])

        let title: String
        let value: String?
        switch middleComponents.count {
        case 0:
            title = ""
            value = nil
        case 1:
            title = middleComponents[0]
            value = nil
        default:
            title = middleComponents.dropLast().joined(separator: "|")
            let resolvedValue = middleComponents.last ?? ""
            value = resolvedValue.isEmpty ? nil : resolvedValue
        }

        return StableTargetIdentity(
            appName: appName,
            role: role,
            title: title,
            value: value,
            path: path,
            frame: frame
        )
    }

    private static func decodeFrame(_ raw: String) -> TargetRect? {
        guard raw != "noframe" else { return nil }
        let values = raw.split(separator: ":").compactMap { Double($0) }
        guard values.count == 4 else { return nil }
        return TargetRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }
}

enum StableTargetResolver {
    private static let minimumResolutionScore = 170

    static func resolve(targetID: String, in snapshot: TargetSnapshot) -> TargetDescriptor? {
        guard let identity = StableTargetIdentity.decode(from: targetID) else { return nil }

        let candidates = snapshot.targets.compactMap { target -> (TargetDescriptor, Int)? in
            guard let score = resolutionScore(for: target, identity: identity) else { return nil }
            return (target, score)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 {
                return lhs.1 > rhs.1
            }
            return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
        }

        guard let best = candidates.first, best.1 >= minimumResolutionScore else { return nil }
        return best.0
    }

    private static func resolutionScore(for target: TargetDescriptor, identity: StableTargetIdentity) -> Int? {
        guard normalized(target.role) == normalized(identity.role) else { return nil }

        var score = 90

        if identity.appName.isEmpty == false, normalized(target.appName) == normalized(identity.appName) {
            score += 15
        }

        let textScore = textResolutionScore(for: target, identity: identity)
        let pathScore = pathResolutionScore(target.path, identity.path)
        let frameScore = frameResolutionScore(target.frame, identity.frame)

        guard textScore > 0 || pathScore >= 40 || frameScore >= 20 else { return nil }
        return score + textScore + pathScore + frameScore
    }

    private static func textResolutionScore(for target: TargetDescriptor, identity: StableTargetIdentity) -> Int {
        let candidateFields = FuzzyMatcher.searchableFields(for: target)
        var score = 0

        if identity.title.isEmpty == false {
            score += bestFieldResolutionScore(identity.title, candidateFields)
        }

        if let value = identity.value, value.isEmpty == false {
            score += bestFieldResolutionScore(value, candidateFields)
        }

        return score
    }

    private static func bestFieldResolutionScore(_ query: String, _ fields: [String]) -> Int {
        fields.map { fieldResolutionScore(query: query, field: $0) }.max() ?? 0
    }

    private static func fieldResolutionScore(query: String, field: String) -> Int {
        let queryComponents = SearchComponents(query)
        let fieldComponents = SearchComponents(field)
        guard queryComponents.raw.isEmpty == false, fieldComponents.raw.isEmpty == false else { return 0 }

        if fieldComponents.raw == queryComponents.raw || fieldComponents.normalized == queryComponents.normalized {
            return 90
        }
        if fieldComponents.raw.hasPrefix(queryComponents.raw) ||
            (queryComponents.normalized.isEmpty == false && fieldComponents.normalized.hasPrefix(queryComponents.normalized)) {
            return 68
        }
        if fieldComponents.raw.contains(queryComponents.raw) ||
            (queryComponents.normalized.isEmpty == false && fieldComponents.normalized.contains(queryComponents.normalized)) {
            return 52
        }

        let tokenScore = tokenResolutionScore(queryTokens: queryComponents.tokens, fieldTokens: fieldComponents.tokens)
        return tokenScore
    }

    private static func tokenResolutionScore(queryTokens: [String], fieldTokens: [String]) -> Int {
        guard queryTokens.isEmpty == false, fieldTokens.isEmpty == false else { return 0 }

        var exactMatches = 0
        var prefixMatches = 0
        for token in queryTokens {
            if fieldTokens.contains(token) {
                exactMatches += 1
            } else if token.count >= 4,
                      fieldTokens.contains(where: { fieldToken in
                          fieldToken.count >= 4 && (fieldToken.hasPrefix(token) || token.hasPrefix(fieldToken))
                      }) {
                prefixMatches += 1
            }
        }

        let totalMatches = exactMatches + prefixMatches
        guard totalMatches > 0 else { return 0 }

        var score = (exactMatches * 20) + (prefixMatches * 10)
        if totalMatches == queryTokens.count {
            score += 20
        }
        return score
    }

    private static func pathResolutionScore(_ candidatePath: [String], _ identityPath: [String]) -> Int {
        guard candidatePath.isEmpty == false, identityPath.isEmpty == false else { return 0 }

        let normalizedCandidate = candidatePath.map(normalizedPathSegment)
        let normalizedIdentity = identityPath.map(normalizedPathSegment)

        let sharedSuffix = sharedSuffixLength(normalizedCandidate, normalizedIdentity)
        let sharedPrefix = zip(normalizedCandidate, normalizedIdentity).prefix { $0 == $1 }.count
        var score = (sharedSuffix * 18) + (sharedPrefix * 4)

        if normalizedCandidate.last == normalizedIdentity.last {
            score += 12
        }

        return score
    }

    private static func frameResolutionScore(_ candidateFrame: TargetRect?, _ identityFrame: TargetRect?) -> Int {
        guard let candidateRect = candidateFrame?.cgRect, let identityRect = identityFrame?.cgRect else { return 0 }

        let centerDistance = hypot(candidateRect.midX - identityRect.midX, candidateRect.midY - identityRect.midY)
        let sizeDistance = abs(candidateRect.width - identityRect.width) + abs(candidateRect.height - identityRect.height)

        var score = 0
        switch centerDistance {
        case ...40:
            score += 44
        case ...90:
            score += 30
        case ...180:
            score += 16
        default:
            break
        }

        switch sizeDistance {
        case ...8:
            score += 18
        case ...20:
            score += 10
        default:
            break
        }

        return score
    }

    private static func normalized(_ value: String) -> String {
        SearchComponents(value).normalized
    }

    private static func normalizedPathSegment(_ segment: String) -> String {
        let withoutIndex = segment.replacingOccurrences(of: "\\[\\d+\\]", with: "", options: .regularExpression)
        return normalized(withoutIndex)
    }

    private static func sharedSuffixLength(_ lhs: [String], _ rhs: [String]) -> Int {
        let reversedPairs = zip(lhs.reversed(), rhs.reversed())
        return reversedPairs.prefix { $0 == $1 }.count
    }

    private struct SearchComponents {
        let raw: String
        let normalized: String
        let tokens: [String]

        init(_ text: String) {
            raw = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            normalized = Self.normalizedText(from: raw)
            tokens = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
        }

        private static func normalizedText(from text: String) -> String {
            var scalars: [UnicodeScalar] = []
            var previousWasSpace = false

            for scalar in text.unicodeScalars {
                if CharacterSet.alphanumerics.contains(scalar) || scalar == "@" || scalar == "#" {
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
}
