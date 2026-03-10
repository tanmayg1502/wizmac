import AppKit
import Foundation
import WizmacCore
import WizmacTextMode

final class MacAutomationExecutor: @unchecked Sendable, ActionExecutor {
    private struct ResolvedTargetApplication {
        var pid: pid_t?
        var unresolvedApp: String?
    }

    private let settingsStore: SettingsStore
    private let auditStore: AuditStore
    private let snapshotter: any AccessibilitySnapshotting
    private let permissionInspector: PermissionInspector
    private let windowController: any WindowControlling
    private let scrollController: any ScrollControlling
    private let musicController: any MusicVolumeControlling
    private let airPlayController: any AirPlayControlling
    private let textService: TextModeService
    private let focusedTextBridge: any FocusedTextBridging
    private let pointerPerformer: any PointerAutomationPerforming
    private var activeTextAttachmentID: TextAttachmentID?
    private var activeTextElement: AXUIElement?

    init(
        settingsStore: SettingsStore,
        auditStore: AuditStore,
        snapshotter: any AccessibilitySnapshotting = AccessibilitySnapshotter(),
        permissionInspector: PermissionInspector = PermissionInspector(),
        windowController: any WindowControlling = WindowController(),
        scrollController: any ScrollControlling = ScrollController(),
        musicController: any MusicVolumeControlling = MusicController(),
        airPlayController: any AirPlayControlling = AirPlayController(),
        textService: TextModeService = TextModeService(),
        focusedTextBridge: any FocusedTextBridging = FocusedTextBridge(),
        pointerPerformer: any PointerAutomationPerforming = CGPointerAutomationPerformer()
    ) {
        self.settingsStore = settingsStore
        self.auditStore = auditStore
        self.snapshotter = snapshotter
        self.permissionInspector = permissionInspector
        self.windowController = windowController
        self.scrollController = scrollController
        self.musicController = musicController
        self.airPlayController = airPlayController
        self.textService = textService
        self.focusedTextBridge = focusedTextBridge
        self.pointerPerformer = pointerPerformer
    }

    public func execute(_ request: ActionRequest) async -> ActionResult {
        switch request.action {
        case .uiApps:
            return uiAppsResult(for: request)
        case .systemPermissions:
            return permissionsResult(for: request)
        case .systemPermissionsRequest:
            return await permissionsRequestResult(for: request)
        case .systemAudit:
            return await auditResult(for: request)
        case .uiSearch:
            return await uiSearchResult(for: request)
        case .uiAct:
            return await uiActResult(for: request)
        case .uiCopy:
            return await uiCopyResult(for: request)
        case .uiHints:
            return await uiSearchResult(for: request.with(arguments: ["operation": .string("hints")]))
        case .uiDrag:
            return await uiActResult(for: request.with(arguments: ["interaction": .string("drag")]))
        case .uiSessionEnd:
            return await uiSessionEndResult(for: request)
        case .scrollTargets:
            return await scrollTargetsResult(for: request)
        case .scrollFocus:
            return await scrollFocusResult(for: request)
        case .scrollStep:
            return await scrollStepResult(for: request)
        case .scrollSessionStart:
            return await scrollFocusResult(for: request.with(arguments: ["operation": .string("session_start")]))
        case .scrollSessionEnd:
            return await scrollFocusResult(for: request.with(arguments: ["operation": .string("session_end")]))
        case .windowList:
            return await windowListResult(for: request)
        case .windowFocus:
            return await windowFocusResult(for: request)
        case .windowExclude:
            return await windowFocusResult(for: request.with(arguments: ["operation": .string("exclude")]))
        case .mediaMusicVolume:
            return await musicVolumeResult(for: request)
        case .displayAirPlayDevices:
            return await airPlayDevicesResult(for: request)
        case .displayAirPlayConnect:
            return await airPlayConnectResult(for: request)
        case .displayAirPlayDisconnect:
            return await airPlayConnectResult(for: request.with(arguments: ["action": .string("disconnect")]))
        case .textAttach:
            return await textAttachResult(for: request)
        case .textDetach:
            return await textAttachResult(for: request.with(arguments: ["operation": .string("detach")]))
        case .textInsert:
            return await textInsertResult(for: request)
        case .textSendKeys:
            return await textSendKeysResult(for: request)
        case .textMode:
            return await textModeResult(for: request)
        case .textStatus:
            return await textStatusResult(for: request)
        case .systemHealth, .systemSessions, .systemConfirmationResolve, .systemTrustedSessionStart, .systemTrustedSessionEnd, .remotePair, .remoteClients, .remoteRevoke:
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .unsupported,
                message: "This action is handled by the shared Wizmac service."
            )
        case .systemConfirmationStatus:
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .unsupported,
                message: "Confirmation status is served directly by the command bus."
            )
        }
    }

    private func settings() async -> WizmacSettings {
        (try? await settingsStore.load()) ?? WizmacSettings()
    }

    /// Resolves a target PID from `pid` (integer) or `app` (name / bundle ID) arguments.
    /// Returns a nil pid when neither is provided, meaning "use frontmost app".
    private func resolvePID(from request: ActionRequest) -> ResolvedTargetApplication {
        if let pid = request.int(for: "pid") {
            return ResolvedTargetApplication(pid: pid_t(pid), unresolvedApp: nil)
        }
        if let app = request.string(for: "app") {
            let resolved = NSWorkspace.shared.runningApplications.first {
                $0.localizedName == app || $0.bundleIdentifier == app
            }?.processIdentifier
            return ResolvedTargetApplication(pid: resolved, unresolvedApp: resolved == nil ? app : nil)
        }
        return ResolvedTargetApplication(pid: nil, unresolvedApp: nil)
    }

    private func searchScope(for request: ActionRequest) -> UISearchScope {
        switch request.string(for: "scope")?.lowercased() {
        case "app":
            return .app
        default:
            return .focusedWindow
        }
    }

    private func includeMenus(for request: ActionRequest) -> Bool {
        request.bool(for: "includeMenus") ?? false
    }

    private func debugTimingsRequested(for request: ActionRequest) -> Bool {
        request.bool(for: "debugTimings") ?? false
    }

    private func unresolvedApplicationResult(for request: ActionRequest, app: String) -> ActionResult {
        ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .notFound,
            message: "Could not find a running application matching '\(app)'."
        )
    }

    private func uiAppsResult(for request: ActionRequest) -> ActionResult {
        let apps = snapshotter.listApplications()
        let payload: JSONValue = .array(apps.map { app in
            [
                "pid": .number(Double(app.pid)),
                "name": .string(app.name),
                "bundleIdentifier": app.bundleIdentifier.map(JSONValue.string) ?? .null,
                "isActive": .bool(app.isActive),
            ]
        })
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Found \(apps.count) running application(s).",
            payload: payload
        )
    }

    private func permissionsResult(for request: ActionRequest) -> ActionResult {
        let statuses = permissionInspector.currentStatuses()
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Fetched current permission status.",
            payload: statuses.payload
        )
    }

    private func permissionsRequestResult(for request: ActionRequest) async -> ActionResult {
        let permissionID = request.string(for: "permission") ?? "accessibility"
        let operation = request.string(for: "operation")
        let result = await PermissionOnboardingController.perform(
            permissionID: permissionID,
            operation: operation
        )

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: result.outcome,
            message: result.message,
            payload: [
                "permission": .string(permissionID),
                "operation": .string(operation ?? "prompt"),
            ]
        )
    }

    private func auditResult(for request: ActionRequest) async -> ActionResult {
        let limit = request.int(for: "limit") ?? 20
        let entries = (try? await auditStore.recent(limit: limit)) ?? []
        let payload: JSONValue = .array(entries.map { entry in
            [
                "id": .string(entry.id.uuidString),
                "action": .string(entry.request.action.rawValue),
                "origin": .string(entry.request.origin.kind.rawValue),
                "message": .string(entry.message),
                "outcome": .string(entry.outcome.rawValue),
                "createdAt": .string(ISO8601DateFormatter().string(from: entry.createdAt)),
            ]
        })
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Fetched recent audit entries.",
            payload: payload
        )
    }

    private func uiSearchResult(for request: ActionRequest) async -> ActionResult {
        let currentSettings = await settings()
        let query = request.string(for: "query") ?? ""
        let limit = request.int(for: "limit") ?? 50
        let operation = request.string(for: "operation")?.lowercased()
        let resolvedApplication = resolvePID(from: request)
        if let unresolvedApp = resolvedApplication.unresolvedApp {
            return unresolvedApplicationResult(for: request, app: unresolvedApp)
        }
        let pid = resolvedApplication.pid

        if operation == "hints" {
            let session: UIHintSession?
            if let pid {
                session = snapshotter.hintSession(query: query, pid: pid, labelAlphabet: currentSettings.labelAlphabet, limit: limit)
            } else {
                session = snapshotter.hintSession(query: query, labelAlphabet: currentSettings.labelAlphabet, limit: limit)
            }
            guard let session else {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .permissionRequired,
                    message: "Unable to generate UI hints for the frontmost application."
                )
            }
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .success,
                message: "Generated \(session.snapshot.targets.count) UI hint(s).",
                payload: session.payload
            )
        }

        let scope = searchScope(for: request)
        let includeMenus = includeMenus(for: request)
        let searchResult = snapshotter.search(
            query: query,
            pid: pid,
            labelAlphabet: currentSettings.labelAlphabet,
            limit: limit,
            sessionID: request.string(for: "sessionID"),
            scope: scope,
            includeMenus: includeMenus
        )

        guard let searchResult else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .permissionRequired,
                message: "Unable to inspect the frontmost application."
            )
        }

        let payload = uiSearchPayload(searchResult, includeDebugTimings: debugTimingsRequested(for: request))
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Found \(searchResult.snapshot.targets.count) UI target(s).",
            payload: payload
        )
    }

    private func uiSessionEndResult(for request: ActionRequest) async -> ActionResult {
        let endedSession = snapshotter.endSession(id: request.string(for: "sessionID"))
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: endedSession == nil ? .notFound : .success,
            message: endedSession == nil ? "No active UI session matched the request." : "Ended UI session.",
            payload: endedSession.map(uiSessionPayload)
        )
    }

    private func uiActResult(for request: ActionRequest) async -> ActionResult {
        let currentSettings = await settings()
        let resolvedApplication = resolvePID(from: request)
        if let unresolvedApp = resolvedApplication.unresolvedApp {
            return unresolvedApplicationResult(for: request, app: unresolvedApp)
        }
        let pid = resolvedApplication.pid
        guard let targetID = request.string(for: "targetID"),
              let targetLookup = snapshotter.target(
                id: targetID,
                pid: pid,
                labelAlphabet: currentSettings.labelAlphabet,
                sessionID: request.string(for: "sessionID"),
                snapshotID: request.string(for: "snapshotID"),
                scope: searchScope(for: request),
                includeMenus: includeMenus(for: request)
              )
        else {
            return ActionResult(requestID: request.id, action: request.action, outcome: .notFound, message: "Target not found.")
        }

        let interaction = request.string(for: "interaction") ?? "press"
        let startedAt = Date()
        let success = performInteraction(interaction, on: targetLookup.target, pid: pid, labelAlphabet: currentSettings.labelAlphabet, request: request)
        var result = ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: success ? .success : .failed,
            message: success ? "Performed \(interaction) on \(targetLookup.target.title)." : "Failed to perform \(interaction).",
            payload: debugTimingsRequested(for: request)
                ? [
                    "timings": debugTimingsPayload(
                        searchMetrics: targetLookup.metrics,
                        actionMs: Date().timeIntervalSince(startedAt) * 1_000
                    ),
                ]
                : nil
        )
        if debugTimingsRequested(for: request), let payload = result.payload?.objectValue {
            result.payload = .object(
                payload.merging(
                    [
                        "sessionID": .string(targetLookup.metrics.sessionID),
                        "snapshotID": .string(targetLookup.metrics.snapshotID),
                    ],
                    uniquingKeysWith: { _, new in new }
                )
            )
        }
        return result
    }

    private func uiCopyResult(for request: ActionRequest) async -> ActionResult {
        let currentSettings = await settings()
        let resolvedApplication = resolvePID(from: request)
        if let unresolvedApp = resolvedApplication.unresolvedApp {
            return unresolvedApplicationResult(for: request, app: unresolvedApp)
        }
        let pid = resolvedApplication.pid
        guard let targetID = request.string(for: "targetID"),
              let targetLookup = snapshotter.target(
                id: targetID,
                pid: pid,
                labelAlphabet: currentSettings.labelAlphabet,
                sessionID: request.string(for: "sessionID"),
                snapshotID: request.string(for: "snapshotID"),
                scope: searchScope(for: request),
                includeMenus: includeMenus(for: request)
              )
        else {
            return ActionResult(requestID: request.id, action: request.action, outcome: .notFound, message: "Target not found.")
        }

        let value = targetLookup.target.value ?? targetLookup.target.title
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)

        var payload: JSONValue = ["value": .string(value)]
        if debugTimingsRequested(for: request), let object = payload.objectValue {
            payload = .object(
                object.merging(
                    [
                        "sessionID": .string(targetLookup.metrics.sessionID),
                        "snapshotID": .string(targetLookup.metrics.snapshotID),
                        "timings": debugTimingsPayload(searchMetrics: targetLookup.metrics, actionMs: 0),
                    ],
                    uniquingKeysWith: { _, new in new }
                )
            )
        }

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Copied text from \(targetLookup.target.title).",
            payload: payload
        )
    }

    private func scrollTargetsResult(for request: ActionRequest) async -> ActionResult {
        let currentSettings = await settings()
        let resolvedApplication = resolvePID(from: request)
        if let unresolvedApp = resolvedApplication.unresolvedApp {
            return unresolvedApplicationResult(for: request, app: unresolvedApp)
        }
        let pid = resolvedApplication.pid
        let snapshot = pid != nil
            ? snapshotter.snapshotApplication(pid: pid!, labelAlphabet: currentSettings.labelAlphabet)
            : snapshotter.snapshotFrontmostApplication(labelAlphabet: currentSettings.labelAlphabet)
        guard let snapshot else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .permissionRequired,
                message: "Unable to inspect scrollable targets."
            )
        }

        let targets = scrollController.scrollTargets(from: snapshot)
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Found \(targets.count) scroll target(s).",
            payload: .array(targets.map(\.payload))
        )
    }

    private func scrollFocusResult(for request: ActionRequest) async -> ActionResult {
        let operation = request.string(for: "operation")?.lowercased()
        if operation == "session_end" {
            let ended = scrollController.endSession()
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: ended == nil ? .notFound : .success,
                message: ended == nil ? "No active scroll session." : "Ended scroll session.",
                payload: ended?.payload
            )
        }

        let currentSettings = await settings()
        let scrollFocusApplication = resolvePID(from: request)
        if let unresolvedApp = scrollFocusApplication.unresolvedApp {
            return unresolvedApplicationResult(for: request, app: unresolvedApp)
        }
        let scrollFocusPid = scrollFocusApplication.pid
        let focusSnapshot = scrollFocusPid != nil
            ? snapshotter.snapshotApplication(pid: scrollFocusPid!, labelAlphabet: currentSettings.labelAlphabet)
            : snapshotter.snapshotFrontmostApplication(labelAlphabet: currentSettings.labelAlphabet)
        guard let snapshot = focusSnapshot else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .permissionRequired,
                message: "Unable to inspect scrollable targets."
            )
        }

        let targetID = request.string(for: "targetID")
        if operation == "session_start" {
            guard let session = scrollController.startSession(targetID: targetID, snapshot: snapshot) else {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .notFound,
                    message: "No scroll target is available to start a session."
                )
            }
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .success,
                message: "Started scroll session.",
                payload: session.payload
            )
        }

        guard let targetID else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .invalidRequest,
                message: "Missing targetID."
            )
        }

        scrollController.focus(targetID: targetID)
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Focused scroll target \(targetID)."
        )
    }

    private func scrollStepResult(for request: ActionRequest) async -> ActionResult {
        let currentSettings = await settings()
        let resolvedApplication = resolvePID(from: request)
        if let unresolvedApp = resolvedApplication.unresolvedApp {
            return unresolvedApplicationResult(for: request, app: unresolvedApp)
        }
        let pid = resolvedApplication.pid
        let snapshot = pid != nil
            ? snapshotter.snapshotApplication(pid: pid!, labelAlphabet: currentSettings.labelAlphabet)
            : snapshotter.snapshotFrontmostApplication(labelAlphabet: currentSettings.labelAlphabet)
        guard let snapshot else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .permissionRequired,
                message: "Unable to inspect scrollable targets."
            )
        }

        let direction = request.string(for: "direction") ?? "down"
        let amount = request.int(for: "amount") ?? 3
        let success = scrollController.step(direction: direction, amount: amount, snapshot: snapshot)

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: success ? .success : .failed,
            message: success ? "Scrolled \(direction)." : "Failed to scroll."
        )
    }

    private func windowListResult(for request: ActionRequest) async -> ActionResult {
        let rules = await settings().excludedWindows
        let windows = windowController.visibleWindows(excluding: rules)
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Found \(windows.count) visible window(s).",
            payload: .array(windows.map(\.payload))
        )
    }

    private func windowFocusResult(for request: ActionRequest) async -> ActionResult {
        if request.string(for: "operation")?.lowercased() == "exclude" {
            let currentSettings = await settings()
            guard let rule = windowController.excludeRule(
                windowID: request.int(for: "windowID"),
                title: request.string(for: "title"),
                pid: request.int(for: "pid").map(Int32.init),
                excluding: currentSettings.excludedWindows
            ) else {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .notFound,
                    message: "Unable to derive an exclusion rule for the requested window."
                )
            }

            let updated = try? await settingsStore.update { settings in
                if settings.excludedWindows.contains(rule) == false {
                    settings.excludedWindows.append(rule)
                }
            }

            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: updated == nil ? .failed : .success,
                message: updated == nil ? "Failed to exclude the requested window." : "Excluded \(rule.title) from future window lists.",
                payload: [
                    "appName": .string(rule.appName),
                    "title": .string(rule.title),
                ]
            )
        }

        let didFocus = windowController.focus(
            windowID: request.int(for: "windowID"),
            title: request.string(for: "title"),
            pid: request.int(for: "pid").map(Int32.init)
        )
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: didFocus ? .success : .failed,
            message: didFocus ? "Focused window." : "Unable to focus the requested window."
        )
    }

    private func musicVolumeResult(for request: ActionRequest) async -> ActionResult {
        if let value = request.int(for: "value") {
            let result = await musicController.setVolume(value)
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: result.0 ? .success : .failed,
                message: result.1
            )
        }

        let volume = await musicController.currentVolume()
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: volume == nil ? .failed : .success,
            message: volume == nil ? "Unable to read Music volume." : "Fetched Music volume.",
            payload: volume.map { ["value": .number(Double($0))] }
        )
    }

    private func airPlayDevicesResult(for request: ActionRequest) async -> ActionResult {
        let devices = await airPlayController.listDevices()
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Found \(devices.count) AirPlay device(s).",
            payload: .array(devices.map(JSONValue.string))
        )
    }

    private func airPlayConnectResult(for request: ActionRequest) async -> ActionResult {
        let action = request.string(for: "action")?.lowercased()
        if action == "disconnect" {
            let result = await airPlayController.disconnect()
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: result.0 ? .success : .failed,
                message: result.1
            )
        }

        if action == "menu" || action == "open_menu" || action == "chooser" {
            let result = await airPlayController.openMenu()
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: result.0 ? .success : .failed,
                message: result.1
            )
        }

        guard let device = request.string(for: "device") else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .invalidRequest,
                message: "Missing device."
            )
        }

        let result = await airPlayController.connect(device: device)
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: result.0 ? .success : .failed,
            message: result.1
        )
    }

    private func textAttachResult(for request: ActionRequest) async -> ActionResult {
        if request.string(for: "operation")?.lowercased() == "detach" {
            guard let attachmentID = activeTextAttachmentID else {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .notFound,
                    message: "No active text attachment."
                )
            }

            await textService.detach(attachmentID)
            activeTextAttachmentID = nil
            activeTextElement = nil

            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .success,
                message: "Detached text mode from the focused input.",
                payload: ["attachmentID": .string(attachmentID.rawValue.uuidString)]
            )
        }

        guard let capture = focusedTextBridge.captureFocusedContext() else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .notFound,
                message: "No focused text input is available."
            )
        }

        do {
            let attachment = try await textService.attach(context: capture.context)
            activeTextAttachmentID = attachment.id
            activeTextElement = capture.element

            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .success,
                message: "Attached text mode to the focused input.",
                payload: textAttachmentPayload(attachment)
            )
        } catch {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .failed,
                message: error.localizedDescription
            )
        }
    }

    private func textInsertResult(for request: ActionRequest) async -> ActionResult {
        guard let capture = focusedTextBridge.captureFocusedContext() else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .notFound,
                message: "No focused text input is available."
            )
        }

        let text = request.string(for: "text") ?? request.string(for: "keys") ?? ""
        guard text.isEmpty == false else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .invalidRequest,
                message: "No text was provided."
            )
        }

        let startedAt = Date()
        let replaceSelection = request.bool(for: "replaceSelection") ?? false
        let submit = request.bool(for: "submit") ?? false
        activeTextElement = capture.element
        var context = capture.context
        applyBulkInsert(text, replaceSelection: replaceSelection, context: &context)
        focusedTextBridge.sync(context: context, onto: capture.element)

        if let attachmentID = activeTextAttachmentID {
            _ = try? await textService.sync(context: context, attachmentID: attachmentID)
        }

        let submitResult = submit ? postReturnKey() : true
        let actionMs = Date().timeIntervalSince(startedAt) * 1_000
        var payload: JSONValue = [
            "application": context.applicationName.map(JSONValue.string) ?? .null,
            "elementIdentifier": .string(context.elementIdentifier),
        ]
        if debugTimingsRequested(for: request), let payloadObject = payload.objectValue {
            payload = .object(
                payloadObject.merging(
                    [
                        "timings": debugTimingsPayload(
                            searchMetrics: nil,
                            actionMs: actionMs
                        ),
                    ],
                    uniquingKeysWith: { _, new in new }
                )
            )
        }

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: submitResult ? .success : .failed,
            message: submitResult
                ? "Inserted text into the focused input."
                : "Inserted text, but failed to submit.",
            payload: payload
        )
    }

    private func textModeResult(for request: ActionRequest) async -> ActionResult {
        guard let attachmentID = activeTextAttachmentID else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .notFound,
                message: "No active text attachment."
            )
        }

        guard let state = await textService.state(for: attachmentID) else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .notFound,
                message: "No active text attachment."
            )
        }

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Fetched current text mode state.",
            payload: textStatePayload(state)
        )
    }

    private func textStatusResult(for request: ActionRequest) async -> ActionResult {
        guard let attachmentID = activeTextAttachmentID else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .notFound,
                message: "No active text attachment."
            )
        }

        guard let status = await textService.status(for: attachmentID) else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .notFound,
                message: "No active text attachment."
            )
        }

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Fetched current text session status.",
            payload: textStatusPayload(status)
        )
    }

    private func textSendKeysResult(for request: ActionRequest) async -> ActionResult {
        let rawKeys = request.string(for: "keys") ?? ""
        if isPlainTextKeys(rawKeys) {
            return await textInsertResult(
                for: request.with(arguments: [
                    "text": .string(rawKeys),
                ])
            )
        }

        guard
            let attachmentID = activeTextAttachmentID,
            let capture = focusedTextBridge.captureFocusedContext()
        else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .notFound,
                message: "No active text attachment."
            )
        }

        let element = capture.element
        activeTextElement = element
        var context = capture.context

        do {
            _ = try await textService.sync(context: context, attachmentID: attachmentID)
        } catch {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .failed,
                message: error.localizedDescription
            )
        }

        let events = parseTextEvents(rawKeys)
        guard events.isEmpty == false else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .invalidRequest,
                message: "No keys were provided."
            )
        }

        var decisionPayloads: [JSONValue] = []

        for event in events {
            do {
                let decision = try await textService.handle(event: event, attachmentID: attachmentID)
                focusedTextBridge.apply(commands: decision.commands, for: event, to: element, context: &context)
                _ = try await textService.sync(context: context, attachmentID: attachmentID)
                decisionPayloads.append(textDecisionPayload(decision))
            } catch {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .failed,
                    message: error.localizedDescription
            )
        }
    }

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Processed \(events.count) text-mode event(s).",
            payload: .array(decisionPayloads)
        )
    }

    private func performInteraction(
        _ interaction: String,
        on target: TargetDescriptor,
        pid: pid_t?,
        labelAlphabet: String,
        request: ActionRequest
    ) -> Bool {
        guard let frame = target.frame else { return false }

        switch interaction.lowercased() {
        case "move", "highlight":
            return pointerPerformer.move(to: frame.center)
        case "rightpress", "right_click", "rightclick":
            return pointerPerformer.click(at: frame.center, clickState: 1, button: .right)
        case "doublepress", "double_click", "doubleclick":
            return pointerPerformer.click(at: frame.center, clickState: 2, button: .left)
        case "drag":
            let destination = dragDestination(for: request, pid: pid, labelAlphabet: labelAlphabet)
            guard let destination else { return false }
            return pointerPerformer.drag(from: frame.center, to: destination, steps: request.int(for: "steps") ?? 8)
        default:
            return pointerPerformer.click(at: frame.center, clickState: 1, button: .left)
        }
    }

    private func dragDestination(for request: ActionRequest, pid: pid_t?, labelAlphabet: String) -> CGPoint? {
        if
            let x = request.arguments["x"]?.doubleValue,
            let y = request.arguments["y"]?.doubleValue
        {
            return CGPoint(x: x, y: y)
        }

        if let targetID = request.string(for: "destinationTargetID") ?? request.string(for: "toTargetID") {
            let destination = snapshotter.target(
                id: targetID,
                pid: pid,
                labelAlphabet: labelAlphabet,
                sessionID: request.string(for: "sessionID"),
                snapshotID: request.string(for: "snapshotID"),
                scope: searchScope(for: request),
                includeMenus: includeMenus(for: request)
            )
            if let frame = destination?.target.frame {
                return frame.center
            }
        }

        return nil
    }

    private func uiSearchPayload(_ searchResult: UISearchResult, includeDebugTimings: Bool) -> JSONValue {
        var payload: JSONValue = [
            "appName": .string(searchResult.snapshot.appName),
            "bundleIdentifier": searchResult.snapshot.bundleIdentifier.map(JSONValue.string) ?? .null,
            "windowTitle": searchResult.snapshot.windowTitle.map(JSONValue.string) ?? .null,
            "sessionID": searchResult.snapshot.sessionID.map(JSONValue.string) ?? .null,
            "snapshotID": searchResult.snapshot.snapshotID.map(JSONValue.string) ?? .null,
            "targets": .array(searchResult.snapshot.targets.map(\.payload)),
        ]

        if includeDebugTimings, let object = payload.objectValue {
            payload = .object(
                object.merging(
                    [
                        "timings": debugTimingsPayload(
                            searchMetrics: searchResult.metrics,
                            actionMs: 0
                        ),
                    ],
                    uniquingKeysWith: { _, new in new }
                )
            )
        }

        return payload
    }

    private func uiSessionPayload(_ metrics: UISessionMetrics) -> JSONValue {
        [
            "sessionID": .string(metrics.sessionID),
            "snapshotID": .string(metrics.snapshotID),
            "appName": .string(metrics.appName),
            "windowTitle": metrics.windowTitle.map(JSONValue.string) ?? .null,
            "targetCount": .number(Double(metrics.targetCount)),
            "cacheHitRate": .number(metrics.cacheHitRate),
            "lastRefreshedAt": .string(ISO8601DateFormatter().string(from: metrics.lastRefreshedAt)),
        ]
    }

    private func debugTimingsPayload(searchMetrics: UISessionMetrics?, actionMs: Double) -> JSONValue {
        [
            "transportMs": .number(0),
            "snapshotMs": .number(searchMetrics?.snapshotMs ?? 0),
            "cacheLookupMs": .number(searchMetrics?.cacheLookupMs ?? 0),
            "rankingMs": .number(searchMetrics?.rankingMs ?? 0),
            "actionMs": .number(actionMs),
            "approvalMs": .number(0),
            "cacheHit": .bool(searchMetrics?.cacheHit ?? false),
        ]
    }

    private func isPlainTextKeys(_ raw: String) -> Bool {
        raw.isEmpty == false && raw.contains("<") == false && raw.contains(">") == false
    }

    private func applyBulkInsert(_ text: String, replaceSelection: Bool, context: inout TextContextSnapshot) {
        let nsText = context.text as NSString
        let selectedRange = NSRange(
            location: context.cursor.range.location,
            length: context.cursor.range.length
        )
        let replacementRange: NSRange
        if replaceSelection {
            replacementRange = selectedRange
        } else {
            replacementRange = NSRange(
                location: selectedRange.location + selectedRange.length,
                length: 0
            )
        }

        let safeRange = NSIntersectionRange(
            replacementRange,
            NSRange(location: 0, length: nsText.length)
        )
        context.text = nsText.replacingCharacters(in: safeRange, with: text)
        let cursorLocation = safeRange.location + text.utf16.count
        context.cursor.range = TextRange(location: cursorLocation, length: 0)
    }

    private func postReturnKey() -> Bool {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false)
        else {
            return false
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func parseTextEvents(_ raw: String) -> [TextKeyEvent] {
        guard raw.isEmpty == false else { return [] }

        var events: [TextKeyEvent] = []
        var index = raw.startIndex

        while index < raw.endIndex {
            if raw[index] == "<", let close = raw[index...].firstIndex(of: ">") {
                let token = String(raw[raw.index(after: index)..<close]).lowercased()
                if let special = specialKey(for: token) {
                    events.append(.special(special))
                }
                index = raw.index(after: close)
            } else {
                events.append(.character(String(raw[index])))
                index = raw.index(after: index)
            }
        }

        return events
    }

    private func specialKey(for token: String) -> TextSpecialKey? {
        switch token {
        case "esc", "escape":
            return .escape
        case "cr", "enter", "return":
            return .enter
        case "tab":
            return .tab
        case "bs", "backspace":
            return .backspace
        case "space":
            return .space
        case "left":
            return .leftArrow
        case "right":
            return .rightArrow
        case "up":
            return .upArrow
        case "down":
            return .downArrow
        default:
            return nil
        }
    }

    private func textAttachmentPayload(_ attachment: TextAttachment) -> JSONValue {
        [
            "attachmentID": .string(attachment.id.rawValue.uuidString),
            "backend": .string(attachment.state.backend.rawValue),
            "mode": .string(attachment.state.mode.rawValue),
            "application": attachment.context.applicationName.map(JSONValue.string) ?? .null,
            "elementIdentifier": .string(attachment.context.elementIdentifier),
        ]
    }

    private func textStatePayload(_ state: TextModeState) -> JSONValue {
        [
            "attachmentID": .string(state.attachmentID.rawValue.uuidString),
            "backend": .string(state.backend.rawValue),
            "mode": .string(state.mode.rawValue),
            "lastMode": state.lastMode.map { .string($0.rawValue) } ?? .null,
            "pendingCount": state.pendingCount.map { .number(Double($0)) } ?? .null,
            "pendingOperator": state.pendingOperator.map { .string($0.rawValue) } ?? .null,
            "pendingCommandLine": .string(state.pendingCommandLine),
            "queuedKeys": .array(state.queuedKeys.map(textKeyEventPayload)),
            "handledEventCount": .number(Double(state.handledEventCount)),
            "queuedKeyCount": .number(Double(state.queuedKeys.count)),
            "cursor": [
                "location": .number(Double(state.cursor.range.location)),
                "length": .number(Double(state.cursor.range.length)),
                "preferredColumn": state.cursor.preferredColumn.map { .number(Double($0)) } ?? .null,
            ],
            "isSecureInput": .bool(state.isSecureInput),
            "attachedAt": .string(ISO8601DateFormatter().string(from: state.attachedAt)),
            "lastEventAt": state.lastEventAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
            "lastSyncedAt": .string(ISO8601DateFormatter().string(from: state.lastSyncedAt)),
            "recentCommands": .array(state.recentCommands.map { .string(String(describing: $0)) }),
            "recentEffects": .array(state.recentEffects.map { .string($0.rawValue) }),
        ]
    }

    private func textDecisionPayload(_ decision: TextModeDecision) -> JSONValue {
        [
            "mode": .string(decision.state.mode.rawValue),
            "effects": .array(decision.effects.map { .string($0.rawValue) }),
            "commands": .array(decision.commands.map { .string(String(describing: $0)) }),
        ]
    }

    private func textStatusPayload(_ status: TextSessionStatus) -> JSONValue {
        [
            "attachmentID": .string(status.attachmentID.rawValue.uuidString),
            "backend": .string(status.backend.rawValue),
            "mode": .string(status.mode.rawValue),
            "application": status.applicationName.map(JSONValue.string) ?? .null,
            "windowTitle": status.windowTitle.map(JSONValue.string) ?? .null,
            "elementIdentifier": .string(status.elementIdentifier),
            "queuedKeyCount": .number(Double(status.queuedKeyCount)),
            "handledEventCount": .number(Double(status.handledEventCount)),
            "pendingCommandLine": .string(status.pendingCommandLine),
            "isSecureInput": .bool(status.isSecureInput),
            "attachedAt": .string(ISO8601DateFormatter().string(from: status.attachedAt)),
            "lastEventAt": status.lastEventAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
            "lastSyncedAt": .string(ISO8601DateFormatter().string(from: status.lastSyncedAt)),
            "recentCommands": .array(status.recentCommands.map { .string(String(describing: $0)) }),
            "recentEffects": .array(status.recentEffects.map { .string($0.rawValue) }),
            "cursor": [
                "location": .number(Double(status.cursor.range.location)),
                "length": .number(Double(status.cursor.range.length)),
                "preferredColumn": status.cursor.preferredColumn.map { .number(Double($0)) } ?? .null,
            ],
        ]
    }

    private func textKeyEventPayload(_ event: TextKeyEvent) -> JSONValue {
        let key: JSONValue
        switch event.key {
        case let .character(value):
            key = .string(value)
        case let .special(value):
            key = .string("<\(value.rawValue)>")
        }

        return [
            "key": key,
            "modifiers": .array(event.modifiers.map(\.rawValue).sorted().map(JSONValue.string)),
            "timestamp": .string(ISO8601DateFormatter().string(from: event.timestamp)),
            "source": event.source.map(JSONValue.string) ?? .null,
        ]
    }
}

private extension ActionRequest {
    func with(arguments additions: [String: JSONValue]) -> ActionRequest {
        var merged = arguments
        for (key, value) in additions {
            merged[key] = value
        }
        return ActionRequest(
            id: id,
            action: action,
            arguments: merged,
            origin: origin,
            createdAt: createdAt
        )
    }
}
