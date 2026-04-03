import AppKit
import Foundation
import WizmacCore
import WizmacTextMode

final class MacAutomationExecutor: @unchecked Sendable, ApprovalPreparingActionExecutor {
    private struct ResolvedTargetApplication {
        var pid: pid_t?
        var appName: String?
        var bundleIdentifier: String?
        var launched: Bool
        var unresolvedApp: String?
    }

    private struct ParsedKeySequenceStep {
        var events: [SynthesizedKeyEvent]
        var delayAfterMs: Int
    }

    private let settingsStore: SettingsStore
    private let auditStore: AuditStore
    private let snapshotter: any AccessibilitySnapshotting
    private let permissionInspector: PermissionInspector
    private let windowController: any WindowControlling
    private let scrollController: any ScrollControlling
    private let gestureScrollPerformer: any ScrollEventPerforming
    private let musicController: any MusicVolumeControlling
    private let airPlayController: any AirPlayControlling
    private let screenMediaController: any ScreenMediaControlling
    private let textService: TextModeService
    private let focusedTextBridge: any FocusedTextBridging
    private let pointerPerformer: any PointerAutomationPerforming
    private let keyboardPerformer: any KeyboardAutomationPerforming
    private let shellRunner: any ShellRunning
    private let sleeper: any AutomationSleeping
    private var activeTextAttachmentID: TextAttachmentID?
    private var activeTextElement: AXUIElement?

    init(
        settingsStore: SettingsStore,
        auditStore: AuditStore,
        snapshotter: any AccessibilitySnapshotting = AccessibilitySnapshotter(),
        permissionInspector: PermissionInspector = PermissionInspector(),
        windowController: any WindowControlling = WindowController(),
        scrollController: any ScrollControlling = ScrollController(),
        gestureScrollPerformer: any ScrollEventPerforming = CGScrollEventPerformer(),
        musicController: any MusicVolumeControlling = MusicController(),
        airPlayController: any AirPlayControlling = AirPlayController(),
        screenMediaController: any ScreenMediaControlling = ScreenMediaController(),
        textService: TextModeService = TextModeService(),
        focusedTextBridge: any FocusedTextBridging = FocusedTextBridge(),
        pointerPerformer: any PointerAutomationPerforming = CGPointerAutomationPerformer(),
        keyboardPerformer: any KeyboardAutomationPerforming = CGKeyboardAutomationPerformer(),
        shellRunner: any ShellRunning = ShellCommandRunner(),
        sleeper: any AutomationSleeping = TaskAutomationSleeper()
    ) {
        self.settingsStore = settingsStore
        self.auditStore = auditStore
        self.snapshotter = snapshotter
        self.permissionInspector = permissionInspector
        self.windowController = windowController
        self.scrollController = scrollController
        self.gestureScrollPerformer = gestureScrollPerformer
        self.musicController = musicController
        self.airPlayController = airPlayController
        self.screenMediaController = screenMediaController
        self.textService = textService
        self.focusedTextBridge = focusedTextBridge
        self.pointerPerformer = pointerPerformer
        self.keyboardPerformer = keyboardPerformer
        self.shellRunner = shellRunner
        self.sleeper = sleeper
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
            return await timedMutationResult(for: request) {
                await self.uiActResult(for: request)
            }
        case .uiCopy:
            return await uiCopyResult(for: request)
        case .uiOpen:
            return await uiOpenResult(for: request)
        case .uiSelect:
            return await uiSelectResult(for: request)
        case .uiToggle:
            return await uiToggleResult(for: request)
        case .uiFocus:
            return await uiFocusResult(for: request)
        case .uiRead:
            return await uiReadResult(for: request)
        case .uiWait, .uiUntil:
            return await uiWaitResult(for: request)
        case .uiAssert:
            return await uiAssertResult(for: request)
        case .uiDiff:
            return await uiDiffResult(for: request)
        case .uiWatch:
            return await uiWatchResult(for: request)
        case .uiSubmit:
            return await uiSubmitResult(for: request)
        case .uiChooseFile:
            return await uiChooseFileResult(for: request)
        case .uiCapture:
            return await uiCaptureResult(for: request)
        case .uiPrefetch:
            return await uiPrefetchResult(for: request)
        case .uiExecute:
            return await uiExecuteResult(for: request)
        case .uiHints:
            return await uiSearchResult(for: request.with(arguments: ["operation": .string("hints")]))
        case .uiDrag:
            return await timedMutationResult(for: request) {
                await self.uiActResult(for: request.with(arguments: self.dragArguments(for: request)))
            }
        case .inputKeyCombo:
            return await timedMutationResult(for: request) {
                await self.inputKeyComboResult(for: request)
            }
        case .inputKeySequence:
            return await timedMutationResult(for: request) {
                await self.inputKeySequenceResult(for: request)
            }
        case .uiGesture:
            return await timedMutationResult(for: request) {
                await self.uiGestureResult(for: request)
            }
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
        case .scrollTo, .scrollUntil, .scrollIntoView:
            return await scrollToResult(for: request)
        case .windowList:
            return await windowListResult(for: request)
        case .windowFocus:
            return await windowFocusResult(for: request)
        case .windowAssert:
            return await windowAssertResult(for: request)
        case .windowExclude:
            return await windowFocusResult(for: request.with(arguments: ["operation": .string("exclude")]))
        case .mediaScreenshot:
            return await mediaScreenshotResult(for: request)
        case .mediaRecord:
            return await mediaRecordResult(for: request)
        case .mediaStream:
            return await mediaStreamResult(for: request)
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
        case .textRead:
            return await textReadResult(for: request)
        case .textSendKeys:
            return await timedMutationResult(for: request) {
                await self.textSendKeysResult(for: request)
            }
        case .textMode:
            return await textModeResult(for: request)
        case .textStatus:
            return await textStatusResult(for: request)
        case .menuSelect:
            return await menuSelectResult(for: request)
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

    public func prepareForApproval(_ request: ActionRequest) async -> ActionRequest {
        guard approvalFreezableActions.contains(request.action) else { return request }
        guard request.string(for: "targetID") == nil else { return request }
        guard request.string(for: "query")?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return request
        }

        let currentSettings = await settings()
        let resolvedApplication = resolvePID(from: request)
        if resolvedApplication.unresolvedApp != nil {
            return request
        }

        let targetResolution = resolveUITarget(
            for: request,
            resolvedApplication: resolvedApplication,
            currentSettings: currentSettings
        )
        guard let targetLookup = targetResolution.targetLookup else {
            return request
        }

        var additions: [String: JSONValue] = [
            "targetID": .string(targetLookup.target.id),
        ]
        if request.string(for: "sessionID") == nil {
            additions["sessionID"] = .string(targetLookup.metrics.sessionID)
        }
        if request.string(for: "snapshotID") == nil {
            additions["snapshotID"] = .string(targetLookup.metrics.snapshotID)
        }
        return request.with(arguments: additions)
    }

    private func settings() async -> WizmacSettings {
        (try? await settingsStore.load()) ?? WizmacSettings()
    }

    private func resolvePID(from request: ActionRequest) -> ResolvedTargetApplication {
        let resolution = RunningApplicationResolver.resolve(
            pid: request.int(for: "pid").map(pid_t.init),
            app: request.string(for: "app"),
            launchIfNeeded: request.bool(for: "launchIfNeeded") ?? false,
            activate: request.bool(for: "activate") ?? false
        )
        return ResolvedTargetApplication(
            pid: resolution.pid,
            appName: resolution.appName,
            bundleIdentifier: resolution.bundleIdentifier,
            launched: resolution.launched,
            unresolvedApp: resolution.unresolvedApp
        )
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

    private func requestedDelayMs(for key: String, in request: ActionRequest) -> Int {
        max(request.int(for: key) ?? 0, 0)
    }

    private func applyPreMutationDelay(for request: ActionRequest) async {
        await sleeper.sleep(milliseconds: requestedDelayMs(for: "preDelayMs", in: request))
    }

    private func applyPostMutationDelay(for request: ActionRequest) async {
        await sleeper.sleep(milliseconds: requestedDelayMs(for: "postDelayMs", in: request))
    }

    private func timedMutationResult(
        for request: ActionRequest,
        operation: @escaping @Sendable () async -> ActionResult
    ) async -> ActionResult {
        let timeoutMs = max(request.int(for: "timeoutMs") ?? 0, 0)
        guard timeoutMs > 0 else {
            return await operation()
        }

        return await withTaskGroup(of: ActionResult.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                await self.sleeper.sleep(milliseconds: timeoutMs)
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .failed,
                    message: "Timed out after \(timeoutMs) ms."
                )
            }
            let result = await group.next() ?? ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .failed,
                message: "Timed out after \(timeoutMs) ms."
            )
            group.cancelAll()
            return result
        }
    }

    private func unresolvedApplicationResult(for request: ActionRequest, app: String) -> ActionResult {
        ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .notFound,
            message: "Could not find or launch an application matching '\(app)'."
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
        let requestedTargetID = request.string(for: "targetID")

        if let requestedTargetID {
            guard let exactSearchResult = exactUISearchResult(
                targetID: requestedTargetID,
                resolvedApplication: resolvedApplication,
                currentSettings: currentSettings,
                request: request,
                scope: scope,
                includeMenus: includeMenus
            ) else {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .notFound,
                    message: "Could not find a UI target matching the requested targetID."
                )
            }

            let payload = uiSearchPayload(exactSearchResult, includeDebugTimings: debugTimingsRequested(for: request))
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .success,
                message: "Found \(exactSearchResult.snapshot.targets.count) UI target(s).",
                payload: payload
            )
        }

        if let exactTargetID = inferredTargetID(from: query) {
            guard let exactSearchResult = exactUISearchResult(
                targetID: exactTargetID,
                resolvedApplication: resolvedApplication,
                currentSettings: currentSettings,
                request: request,
                scope: scope,
                includeMenus: includeMenus
            ) else {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .notFound,
                    message: "Could not find a UI target matching the requested targetID."
                )
            }

            let payload = uiSearchPayload(exactSearchResult, includeDebugTimings: debugTimingsRequested(for: request))
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .success,
                message: "Found \(exactSearchResult.snapshot.targets.count) UI target(s).",
                payload: payload
            )
        }

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

    private func exactUISearchResult(
        targetID: String,
        resolvedApplication: ResolvedTargetApplication,
        currentSettings: WizmacSettings,
        request: ActionRequest,
        scope: UISearchScope,
        includeMenus: Bool
    ) -> UISearchResult? {
        guard let targetLookup = snapshotter.target(
            id: targetID,
            pid: resolvedApplication.pid,
            labelAlphabet: currentSettings.labelAlphabet,
            sessionID: request.string(for: "sessionID"),
            snapshotID: request.string(for: "snapshotID"),
            scope: scope,
            includeMenus: includeMenus
        ) else {
            return nil
        }

        let snapshot = TargetSnapshot(
            appName: targetLookup.metrics.appName,
            bundleIdentifier: resolvedApplication.bundleIdentifier,
            windowTitle: targetLookup.metrics.windowTitle,
            sessionID: targetLookup.metrics.sessionID,
            snapshotID: targetLookup.metrics.snapshotID,
            generatedAt: targetLookup.metrics.lastRefreshedAt,
            targets: [targetLookup.target]
        )
        return UISearchResult(snapshot: snapshot, metrics: targetLookup.metrics)
    }

    private func exactUITargetLookup(
        targetID: String,
        resolvedApplication: ResolvedTargetApplication,
        currentSettings: WizmacSettings,
        request: ActionRequest,
        scope: UISearchScope,
        includeMenus: Bool
    ) -> UITargetLookupResult? {
        snapshotter.target(
            id: targetID,
            pid: resolvedApplication.pid,
            labelAlphabet: currentSettings.labelAlphabet,
            sessionID: request.string(for: "sessionID"),
            snapshotID: request.string(for: "snapshotID"),
            scope: scope,
            includeMenus: includeMenus
        )
    }

    private func resolveUITarget(
        for request: ActionRequest,
        resolvedApplication: ResolvedTargetApplication,
        currentSettings: WizmacSettings,
        defaultLimit: Int = 1
    ) -> UITargetResolution {
        let scope = searchScope(for: request)
        let includeMenus = includeMenus(for: request)

        if let requestedTargetID = request.string(for: "targetID") {
            guard let targetLookup = exactUITargetLookup(
                targetID: requestedTargetID,
                resolvedApplication: resolvedApplication,
                currentSettings: currentSettings,
                request: request,
                scope: scope,
                includeMenus: includeMenus
            ) else {
                return UITargetResolution(
                    targetLookup: nil,
                    failure: ActionResult(
                        requestID: request.id,
                        action: request.action,
                        outcome: .notFound,
                        message: "Could not find a UI target matching the requested targetID."
                    )
                )
            }

            return UITargetResolution(targetLookup: targetLookup, failure: nil)
        }

        guard let query = request.string(for: "query")?.trimmingCharacters(in: .whitespacesAndNewlines),
              query.isEmpty == false
        else {
            return UITargetResolution(
                targetLookup: nil,
                failure: ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .invalidRequest,
                    message: "Missing targetID or query."
                )
            )
        }

        if let exactTargetID = inferredTargetID(from: query) {
            guard let targetLookup = exactUITargetLookup(
                targetID: exactTargetID,
                resolvedApplication: resolvedApplication,
                currentSettings: currentSettings,
                request: request,
                scope: scope,
                includeMenus: includeMenus
            ) else {
                return UITargetResolution(
                    targetLookup: nil,
                    failure: ActionResult(
                        requestID: request.id,
                        action: request.action,
                        outcome: .notFound,
                        message: "Could not find a UI target matching the requested targetID."
                    )
                )
            }

            return UITargetResolution(targetLookup: targetLookup, failure: nil)
        }

        guard let searchResult = snapshotter.search(
            query: query,
            pid: resolvedApplication.pid,
            labelAlphabet: currentSettings.labelAlphabet,
            limit: max(request.int(for: "limit") ?? defaultLimit, 1),
            sessionID: request.string(for: "sessionID"),
            scope: scope,
            includeMenus: includeMenus
        ) else {
            return UITargetResolution(
                targetLookup: nil,
                failure: ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .permissionRequired,
                    message: "Unable to inspect the requested application."
                )
            )
        }

        guard let firstTarget = searchResult.snapshot.targets.first else {
            return UITargetResolution(
                targetLookup: nil,
                failure: ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .notFound,
                    message: "No UI target matched '\(query)'."
                )
            )
        }

        return UITargetResolution(
            targetLookup: UITargetLookupResult(target: firstTarget, metrics: searchResult.metrics),
            failure: nil
        )
    }

    private func inferredTargetID(from query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              let data = Data(base64Encoded: trimmed),
              let decoded = String(data: data, encoding: .utf8),
              decoded.contains("|AX")
        else {
            return nil
        }
        return trimmed
    }

    private var approvalFreezableActions: Set<ActionName> {
        [
            .uiAct,
            .uiCopy,
            .uiOpen,
            .uiSelect,
            .uiToggle,
            .uiFocus,
            .uiSubmit,
            .uiChooseFile,
            .uiDrag,
        ]
    }

    private func uiCaptureResult(for request: ActionRequest) async -> ActionResult {
        let currentSettings = await settings()
        let resolvedApplication = resolvePID(from: request)
        if let unresolvedApp = resolvedApplication.unresolvedApp {
            return unresolvedApplicationResult(for: request, app: unresolvedApp)
        }

        let detail = request.string(for: "detail")?.lowercased() ?? "compact"
        if detail == "raw" || detail == "raw_ax" || detail == "diagnostic" {
            guard let targetID = request.string(for: "targetID") else {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .invalidRequest,
                    message: "Missing targetID for raw AX capture."
                )
            }

            let payload = snapshotter.debugDump(
                targetID: targetID,
                pid: resolvedApplication.pid,
                labelAlphabet: currentSettings.labelAlphabet,
                sessionID: request.string(for: "sessionID"),
                snapshotID: request.string(for: "snapshotID"),
                scope: searchScope(for: request),
                includeMenus: includeMenus(for: request),
                maxDepth: request.int(for: "maxDepth") ?? 2
            )

            guard let payload else {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .notFound,
                    message: "Unable to dump AX attributes for the requested target."
                )
            }

            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .success,
                message: "Captured raw AX diagnostics for \(targetID).",
                payload: payload
            )
        }

        let captureRequest = request.with(arguments: [
            "query": .string(""),
            "limit": .number(250),
            "scope": .string(request.string(for: "scope") ?? "focusedWindow"),
            "includeMenus": .bool(false),
            "adapter": .string(request.string(for: "adapter") ?? "auto"),
        ])
        let search = await uiSearchResult(for: captureRequest)
        guard search.outcome == .success else { return search }
        guard var payload = search.payload?.objectValue else { return search }
        payload["graphID"] = payload["sessionID"] ?? .null
        payload["stale"] = .bool(false)
        payload["engine"] = .string("ax")
        if detail != "full" {
            payload["targets"] = .array((payload["targets"]?.arrayValue ?? []).prefix(25).map { $0 })
        }
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Captured UI state for \(payload["appName"]?.stringValue ?? "frontmost app").",
            payload: .object(payload)
        )
    }

    private func uiPrefetchResult(for request: ActionRequest) async -> ActionResult {
        let capture = await uiCaptureResult(for: request)
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: capture.outcome,
            message: capture.outcome == .success ? "Prefetched UI graph cache." : capture.message,
            payload: capture.payload
        )
    }

    private func uiExecuteResult(for request: ActionRequest) async -> ActionResult {
        guard let actions = request.array(for: "actions"), actions.isEmpty == false else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .invalidRequest,
                message: "Missing actions array."
            )
        }

        if request.string(for: "trustedSessionID") != nil {
            for step in actions {
                guard let object = step.objectValue,
                      let rawTool = object["tool"]?.stringValue,
                      let action = batchedActionName(from: rawTool)
                else {
                    return ActionResult(
                        requestID: request.id,
                        action: request.action,
                        outcome: .invalidRequest,
                        message: "Each action must include a valid tool name."
                    )
                }
                guard TrustedAutomationPolicy.trustedBatchAllowedActions.contains(action) else {
                    return ActionResult(
                        requestID: request.id,
                        action: request.action,
                        outcome: .invalidRequest,
                        message: "\(rawTool) is not allowed inside a trusted ui.execute batch."
                    )
                }
            }
        }

        var results: [JSONValue] = []
        var bindings: [String: JSONValue] = [:]
        var ambientArguments = ambientBatchArguments(from: request.arguments)
        for step in actions {
            guard let object = step.objectValue,
                  let rawTool = object["tool"]?.stringValue,
                  let action = batchedActionName(from: rawTool)
            else {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .invalidRequest,
                    message: "Each action must include a valid tool name."
                )
            }

            let alias = object["bind"]?.stringValue ?? object["id"]?.stringValue ?? object["name"]?.stringValue
            let rawArguments = object["arguments"]?.objectValue ?? [:]
            let args = interpolateBatchArguments(
                rawArguments,
                bindings: bindings,
                ambientArguments: ambientArguments,
                lastResult: results.last
            )
            let subRequest = ActionRequest(action: action, arguments: args, origin: request.origin)
            let subResult = await execute(subRequest)
            let stepResult: JSONValue = [
                "tool": .string(rawTool),
                "alias": alias.map(JSONValue.string) ?? .null,
                "outcome": .string(subResult.outcome.rawValue),
                "message": .string(subResult.message),
                "payload": subResult.payload ?? .null,
            ]
            results.append(stepResult)
            if let alias, alias.isEmpty == false {
                bindings[alias] = stepResult
            }
            ambientArguments = updatedAmbientBatchArguments(
                from: subResult.payload,
                existing: ambientArguments
            )
            if request.bool(for: "stopOnFailure") ?? true, subResult.outcome != .success {
                break
            }
        }

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Executed \(results.count) batched action(s).",
            payload: [
                "graphID": ambientArguments["graphID"] ?? .null,
                "sessionID": ambientArguments["sessionID"] ?? .null,
                "snapshotID": ambientArguments["snapshotID"] ?? .null,
                "trustedSessionID": ambientArguments["trustedSessionID"] ?? .null,
                "results": .array(results),
                "engine": .string("ax"),
            ]
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
        let targetResolution = resolveUITarget(
            for: request,
            resolvedApplication: resolvedApplication,
            currentSettings: currentSettings
        )
        if let failure = targetResolution.failure {
            return failure
        }
        guard let targetLookup = targetResolution.targetLookup else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .failed,
                message: "Unable to resolve the requested UI target."
            )
        }

        let interaction = request.string(for: "interaction") ?? "press"
        let startedAt = Date()
        await applyPreMutationDelay(for: request)
        let success = performInteraction(
            interaction,
            on: targetLookup.target,
            pid: pid,
            labelAlphabet: currentSettings.labelAlphabet,
            request: request
        )
        await applyPostMutationDelay(for: request)
        let actionMs = Date().timeIntervalSince(startedAt) * 1_000
        let postStateStartedAt = Date()
        let postState = success
            ? await postActionStatePayload(
                for: request,
                pid: pid,
                labelAlphabet: currentSettings.labelAlphabet,
                currentSessionID: targetLookup.metrics.sessionID
            )
            : nil
        let postActionRefreshMs = postState == nil ? 0 : Date().timeIntervalSince(postStateStartedAt) * 1_000
        var payload = baseTargetPayload(
            targetLookup: targetLookup,
            interaction: interaction,
            extra: postState.map { ["postState": $0] } ?? [:]
        )
        if debugTimingsRequested(for: request), let payloadObject = payload.objectValue {
            payload = .object(
                payloadObject.merging(
                    [
                        "timings": debugTimingsPayload(
                            searchMetrics: targetLookup.metrics,
                            actionMs: actionMs,
                            postActionRefreshMs: postActionRefreshMs
                        ),
                    ],
                    uniquingKeysWith: { _, new in new }
                )
            )
        }

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: success ? .success : .failed,
            message: success ? "Performed \(interaction) on \(targetLookup.target.title)." : "Failed to perform \(interaction).",
            payload: payload
        )
    }

    private func uiCopyResult(for request: ActionRequest) async -> ActionResult {
        let currentSettings = await settings()
        let resolvedApplication = resolvePID(from: request)
        if let unresolvedApp = resolvedApplication.unresolvedApp {
            return unresolvedApplicationResult(for: request, app: unresolvedApp)
        }
        let targetResolution = resolveUITarget(
            for: request,
            resolvedApplication: resolvedApplication,
            currentSettings: currentSettings
        )
        if let failure = targetResolution.failure {
            return failure
        }
        guard let targetLookup = targetResolution.targetLookup else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .failed,
                message: "Unable to resolve the requested UI target."
            )
        }

        let value = preferredReadableText(for: targetLookup.target) ?? targetLookup.target.value ?? targetLookup.target.title
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)

        var payload = baseTargetPayload(
            targetLookup: targetLookup,
            interaction: request.string(for: "mode") ?? "copy",
            extra: ["value": .string(value)]
        )
        if debugTimingsRequested(for: request), let object = payload.objectValue {
            payload = .object(
                object.merging(
                    [
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

    private func uiOpenResult(for request: ActionRequest) async -> ActionResult {
        await uiActResult(for: request.with(arguments: ["interaction": .string("press")]))
    }

    private func uiSelectResult(for request: ActionRequest) async -> ActionResult {
        var additions: [String: JSONValue] = ["interaction": .string("press")]
        if request.string(for: "query") == nil, let option = request.string(for: "option") {
            additions["query"] = .string(option)
        }
        return await uiActResult(for: request.with(arguments: additions))
    }

    private func uiFocusResult(for request: ActionRequest) async -> ActionResult {
        await uiActResult(for: request.with(arguments: ["interaction": .string("press")]))
    }

    private func uiToggleResult(for request: ActionRequest) async -> ActionResult {
        let currentSettings = await settings()
        let resolvedApplication = resolvePID(from: request)
        if let unresolvedApp = resolvedApplication.unresolvedApp {
            return unresolvedApplicationResult(for: request, app: unresolvedApp)
        }

        let targetResolution = resolveUITarget(
            for: request,
            resolvedApplication: resolvedApplication,
            currentSettings: currentSettings
        )
        if let failure = targetResolution.failure {
            return failure
        }
        guard let targetLookup = targetResolution.targetLookup else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .failed,
                message: "Unable to resolve the requested UI target."
            )
        }

        if let requestedState = request.string(for: "state"),
           let desired = desiredSelectionState(from: requestedState),
           let current = targetLookup.target.isSelectedLike as Bool?,
           current == desired {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .success,
                message: "Target already matched the requested state.",
                payload: baseTargetPayload(
                    targetLookup: targetLookup,
                    interaction: "toggle",
                    extra: [
                        "requestedState": .string(requestedState),
                        "currentState": .bool(current),
                        "changed": .bool(false),
                    ]
                )
            )
        }

        let toggled = await uiActResult(for: request.with(arguments: ["interaction": .string("press")]))
        guard let requestedState = request.string(for: "state"),
              let desired = desiredSelectionState(from: requestedState),
              let payload = toggled.payload?.objectValue
        else {
            return toggled
        }

        let postTargets = payload["postState"]?.objectValue?["targets"]?.arrayValue ?? []
        let changed = postTargets.first?.objectValue?["value"]?.boolValue == desired
        if toggled.outcome == .success, changed {
            return toggled
        }
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: changed ? .success : .failed,
            message: changed ? toggled.message : "Toggled the control, but could not confirm the requested state.",
            payload: toggled.payload
        )
    }

    private func uiReadResult(for request: ActionRequest) async -> ActionResult {
        let currentSettings = await settings()
        let resolvedApplication = resolvePID(from: request)
        if let unresolvedApp = resolvedApplication.unresolvedApp {
            return unresolvedApplicationResult(for: request, app: unresolvedApp)
        }
        guard let snapshotResult = uiObservationSnapshot(
            for: request,
            resolvedApplication: resolvedApplication,
            currentSettings: currentSettings,
            forceRefresh: false
        ) else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .permissionRequired,
                message: "Unable to inspect the requested application."
            )
        }

        let matchedTargets = matchingTargets(in: snapshotResult.snapshot, for: request)
        if let target = matchedTargets.first {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .success,
                message: "Read UI target content.",
                payload: [
                    "text": preferredReadableText(for: target).map(JSONValue.string) ?? .null,
                    "target": target.payload,
                    "targetID": .string(target.id),
                    "sessionID": snapshotResult.snapshot.sessionID.map(JSONValue.string) ?? .null,
                    "snapshotID": snapshotResult.snapshot.snapshotID.map(JSONValue.string) ?? .null,
                    "graphID": snapshotResult.snapshot.sessionID.map(JSONValue.string) ?? .null,
                    "windowTitle": snapshotResult.snapshot.windowTitle.map(JSONValue.string) ?? .null,
                ]
            )
        }

        let visibleText = visibleTextLines(in: snapshotResult.snapshot)
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Read visible UI content.",
            payload: [
                "windowTitle": snapshotResult.snapshot.windowTitle.map(JSONValue.string) ?? .null,
                "sessionID": snapshotResult.snapshot.sessionID.map(JSONValue.string) ?? .null,
                "snapshotID": snapshotResult.snapshot.snapshotID.map(JSONValue.string) ?? .null,
                "graphID": snapshotResult.snapshot.sessionID.map(JSONValue.string) ?? .null,
                "text": .string(visibleText.joined(separator: "\n")),
                "lines": .array(visibleText.map(JSONValue.string)),
                "targets": .array(snapshotResult.snapshot.targets.prefix(25).map { $0.payload }),
            ]
        )
    }

    private func uiWaitResult(for request: ActionRequest) async -> ActionResult {
        let currentSettings = await settings()
        let resolvedApplication = resolvePID(from: request)
        if let unresolvedApp = resolvedApplication.unresolvedApp {
            return unresolvedApplicationResult(for: request, app: unresolvedApp)
        }

        let timeoutMs = max(request.int(for: "timeoutMs") ?? 2_500, 50)
        let pollIntervalMs = max(request.int(for: "pollIntervalMs") ?? 120, 20)
        let startedAt = Date()
        var currentSessionID = request.string(for: "sessionID")
        var lastOutcome: UIObservationOutcome?

        while Int(Date().timeIntervalSince(startedAt) * 1_000) <= timeoutMs {
            guard let snapshotResult = uiObservationSnapshot(
                for: request,
                resolvedApplication: resolvedApplication,
                currentSettings: currentSettings,
                forceRefresh: currentSessionID != nil
            ) else {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .permissionRequired,
                    message: "Unable to inspect the requested application."
                )
            }

            currentSessionID = snapshotResult.snapshot.sessionID
            let outcome = observationOutcome(for: request, snapshot: snapshotResult.snapshot)
            if outcome.passed {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .success,
                    message: "UI condition matched.",
                    payload: observationPayload(outcome: outcome, snapshot: snapshotResult.snapshot)
                )
            }
            lastOutcome = outcome
            try? await Task.sleep(nanoseconds: UInt64(pollIntervalMs) * 1_000_000)
        }

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .notFound,
            message: lastOutcome?.detail ?? "Timed out waiting for the requested UI condition.",
            payload: lastOutcome.map { observationPayload(outcome: $0, snapshot: $0.snapshot) }
        )
    }

    private func uiAssertResult(for request: ActionRequest) async -> ActionResult {
        let currentSettings = await settings()
        let resolvedApplication = resolvePID(from: request)
        if let unresolvedApp = resolvedApplication.unresolvedApp {
            return unresolvedApplicationResult(for: request, app: unresolvedApp)
        }

        guard let snapshotResult = uiObservationSnapshot(
            for: request,
            resolvedApplication: resolvedApplication,
            currentSettings: currentSettings,
            forceRefresh: false
        ) else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .permissionRequired,
                message: "Unable to inspect the requested application."
            )
        }

        let outcome = observationOutcome(for: request, snapshot: snapshotResult.snapshot)
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: outcome.passed ? .success : .notFound,
            message: outcome.detail,
            payload: observationPayload(outcome: outcome, snapshot: snapshotResult.snapshot)
        )
    }

    private func uiDiffResult(for request: ActionRequest) async -> ActionResult {
        let currentSettings = await settings()
        let resolvedApplication = resolvePID(from: request)
        if let unresolvedApp = resolvedApplication.unresolvedApp {
            return unresolvedApplicationResult(for: request, app: unresolvedApp)
        }

        let baselineSessionID = request.string(for: "baselineSessionID") ?? request.string(for: "sessionID")
        guard let baselineSnapshot = snapshotter.sessionSnapshot(id: baselineSessionID) else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .notFound,
                message: "No cached baseline snapshot matched the request."
            )
        }
        if let baselineSessionID {
            _ = snapshotter.endSession(id: baselineSessionID)
        }

        guard let freshSnapshot = uiObservationSnapshot(
            for: request.with(arguments: ["sessionID": .null]),
            resolvedApplication: resolvedApplication,
            currentSettings: currentSettings,
            forceRefresh: true
        )?.snapshot else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .permissionRequired,
                message: "Unable to capture a fresh UI snapshot."
            )
        }

        let diff = diffPayload(before: baselineSnapshot, after: freshSnapshot)
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Compared cached and fresh UI snapshots.",
            payload: diff
        )
    }

    private func uiWatchResult(for request: ActionRequest) async -> ActionResult {
        let currentSettings = await settings()
        let resolvedApplication = resolvePID(from: request)
        if let unresolvedApp = resolvedApplication.unresolvedApp {
            return unresolvedApplicationResult(for: request, app: unresolvedApp)
        }

        let timeoutMs = max(request.int(for: "timeoutMs") ?? 2_500, 50)
        let pollIntervalMs = max(request.int(for: "pollIntervalMs") ?? 120, 20)
        let baselineSessionID = request.string(for: "baselineSessionID") ?? request.string(for: "sessionID")

        let baselineSnapshot: TargetSnapshot
        if let cached = snapshotter.sessionSnapshot(id: baselineSessionID) {
            baselineSnapshot = cached
        } else if let captured = uiObservationSnapshot(
            for: request,
            resolvedApplication: resolvedApplication,
            currentSettings: currentSettings,
            forceRefresh: false
        )?.snapshot {
            baselineSnapshot = captured
        } else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .permissionRequired,
                message: "Unable to capture a baseline UI snapshot."
            )
        }

        let startedAt = Date()
        while Int(Date().timeIntervalSince(startedAt) * 1_000) <= timeoutMs {
            if let baselineSessionID {
                _ = snapshotter.endSession(id: baselineSessionID)
            }
            guard let snapshotResult = uiObservationSnapshot(
                for: request.with(arguments: ["sessionID": .null]),
                resolvedApplication: resolvedApplication,
                currentSettings: currentSettings,
                forceRefresh: true
            ) else {
                break
            }

            let diff = diffPayload(before: baselineSnapshot, after: snapshotResult.snapshot)
            let changed = (diff.objectValue?["changed"]?.boolValue ?? false)
            let outcome = observationOutcome(for: request, snapshot: snapshotResult.snapshot)
            if changed || outcome.passed {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .success,
                    message: outcome.passed ? "Observed requested UI condition." : "Observed UI changes.",
                    payload: [
                        "diff": diff,
                        "observation": observationPayload(outcome: outcome, snapshot: snapshotResult.snapshot),
                    ]
                )
            }
            try? await Task.sleep(nanoseconds: UInt64(pollIntervalMs) * 1_000_000)
        }

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .notFound,
            message: "Timed out watching for UI changes."
        )
    }

    private func uiSubmitResult(for request: ActionRequest) async -> ActionResult {
        if request.string(for: "targetID") != nil || request.string(for: "query") != nil {
            return await uiOpenResult(for: request)
        }

        let strategy = request.string(for: "strategy")?.lowercased() ?? "return"
        let success: Bool
        await applyPreMutationDelay(for: request)
        switch strategy {
        case "command_return", "cmd_return", "cmd-enter":
            success = postReturnKey(command: true)
        default:
            success = postReturnKey()
        }
        await applyPostMutationDelay(for: request)
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: success ? .success : .failed,
            message: success ? "Submitted the focused UI element." : "Unable to submit the focused UI element."
        )
    }

    private func uiChooseFileResult(for request: ActionRequest) async -> ActionResult {
        guard let path = request.string(for: "path"), path.isEmpty == false else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .invalidRequest,
                message: "Missing path."
            )
        }

        let insertArguments = propagatedUIArguments(from: request).merging(
            [
                "text": .string(path),
                "submit": .bool(false),
            ],
            uniquingKeysWith: { _, new in new }
        )
        let insertResult = await textInsertResult(
            for: ActionRequest(
                action: .textInsert,
                arguments: insertArguments,
                origin: request.origin
            )
        )
        guard insertResult.outcome == .success else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: insertResult.outcome,
                message: insertResult.message,
                payload: insertResult.payload
            )
        }

        if let confirmQuery = request.string(for: "confirmQuery"), confirmQuery.isEmpty == false {
            let confirmArguments = propagatedUIArguments(from: request).merging(
                ["query": .string(confirmQuery)],
                uniquingKeysWith: { _, new in new }
            )
            let submitResult = await uiSubmitResult(
                for: ActionRequest(action: .uiSubmit, arguments: confirmArguments, origin: request.origin)
            )
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: submitResult.outcome,
                message: submitResult.message,
                payload: [
                    "path": .string(path),
                    "insert": insertResult.payload ?? .null,
                    "submit": submitResult.payload ?? .null,
                ]
            )
        }

        if request.bool(for: "submit") == true {
            let submitArguments = propagatedUIArguments(from: request).merging(
                ["strategy": request.arguments["strategy"] ?? .string("return")],
                uniquingKeysWith: { _, new in new }
            )
            let submitResult = await uiSubmitResult(
                for: ActionRequest(action: .uiSubmit, arguments: submitArguments, origin: request.origin)
            )
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: submitResult.outcome,
                message: submitResult.message,
                payload: [
                    "path": .string(path),
                    "insert": insertResult.payload ?? .null,
                    "submit": submitResult.payload ?? .null,
                ]
            )
        }

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Inserted the requested file path into the dialog.",
            payload: [
                "path": .string(path),
                "insert": insertResult.payload ?? .null,
            ]
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
        await applyPreMutationDelay(for: request)
        let success = scrollController.step(direction: direction, amount: amount, snapshot: snapshot)
        await applyPostMutationDelay(for: request)

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: success ? .success : .failed,
            message: success ? "Scrolled \(direction)." : "Failed to scroll."
        )
    }

    private func scrollToResult(for request: ActionRequest) async -> ActionResult {
        let currentSettings = await settings()
        let resolvedApplication = resolvePID(from: request)
        if let unresolvedApp = resolvedApplication.unresolvedApp {
            return unresolvedApplicationResult(for: request, app: unresolvedApp)
        }

        let timeoutMs = max(request.int(for: "timeoutMs") ?? 3_000, 100)
        let pollIntervalMs = max(request.int(for: "pollIntervalMs") ?? 120, 20)
        let maxSteps = max(request.int(for: "maxSteps") ?? 20, 1)
        let direction = request.string(for: "direction") ?? "down"
        let amount = request.int(for: "amount") ?? 3
        var stepCount = 0
        let startedAt = Date()
        let observationLimit = max(request.int(for: "limit") ?? 250, 250)
        defer { _ = scrollController.endSession() }

        while Int(Date().timeIntervalSince(startedAt) * 1_000) <= timeoutMs, stepCount <= maxSteps {
            guard let snapshotResult = uiObservationSnapshot(
                for: request,
                resolvedApplication: resolvedApplication,
                currentSettings: currentSettings,
                forceRefresh: true,
                minimumLimit: observationLimit,
                bypassCache: true
            ) else {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .permissionRequired,
                    message: "Unable to inspect scrollable targets."
                )
            }

            let matchCandidates = scrollMatchCandidates(
                in: snapshotResult.snapshot,
                for: request,
                direction: direction
            )
            if matchCandidates.isEmpty == false {
                if let stabilizedMatch = await stabilizedScrollMatch(
                    from: matchCandidates,
                    request: request,
                    snapshotResult: snapshotResult,
                    resolvedApplication: resolvedApplication,
                    currentSettings: currentSettings,
                    direction: direction,
                    pollIntervalMs: pollIntervalMs,
                    maxSteps: maxSteps,
                    observationLimit: observationLimit,
                    stepCount: &stepCount
                ) {
                    return ActionResult(
                        requestID: request.id,
                        action: request.action,
                        outcome: .success,
                        message: "Found matching UI target while scrolling.",
                        payload: [
                            "target": stabilizedMatch.target.payload,
                            "targetID": .string(stabilizedMatch.target.id),
                            "stepCount": .number(Double(stepCount)),
                            "sessionID": stabilizedMatch.snapshot.sessionID.map(JSONValue.string) ?? .null,
                            "snapshotID": stabilizedMatch.snapshot.snapshotID.map(JSONValue.string) ?? .null,
                            "graphID": stabilizedMatch.snapshot.sessionID.map(JSONValue.string) ?? .null,
                        ]
                    )
                }

                // Target was found but could not be stabilized into a comfortable
                // viewport position. Return it anyway instead of continuing to
                // scroll past it, which causes the oscillation bug where the loop
                // scrolls away from the already-visible target.
                let bestMatch = matchCandidates[0].0
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .success,
                    message: "Found matching UI target while scrolling.",
                    payload: [
                        "target": bestMatch.payload,
                        "targetID": .string(bestMatch.id),
                        "stepCount": .number(Double(stepCount)),
                        "sessionID": snapshotResult.snapshot.sessionID.map(JSONValue.string) ?? .null,
                        "snapshotID": snapshotResult.snapshot.snapshotID.map(JSONValue.string) ?? .null,
                        "graphID": snapshotResult.snapshot.sessionID.map(JSONValue.string) ?? .null,
                    ]
                )
            }

            if stepCount == maxSteps {
                break
            }

            if scrollController.currentSession() == nil {
                guard scrollController.startSession(
                    targetID: request.string(for: "scrollTargetID"),
                    snapshot: snapshotResult.snapshot
                ) != nil else {
                    return ActionResult(
                        requestID: request.id,
                        action: request.action,
                        outcome: .notFound,
                        message: "No scrollable container matched the request."
                    )
                }
            }

            guard scrollController.step(direction: direction, amount: amount, snapshot: snapshotResult.snapshot) else {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .failed,
                    message: "Failed to scroll the active container."
                )
            }
            stepCount += 1
            try? await Task.sleep(nanoseconds: UInt64(pollIntervalMs) * 1_000_000)
        }

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .notFound,
            message: "Reached the scroll limit without finding a matching UI target.",
            payload: ["stepCount": .number(Double(stepCount))]
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
            let requestedWindowID = request.int(for: "windowID")
            let requestedTitle = request.string(for: "title") ?? request.string(for: "query")
            let requestedPID = request.int(for: "pid").map(Int32.init)
            guard let rule = windowController.excludeRule(
                windowID: requestedWindowID,
                title: requestedTitle,
                pid: requestedPID,
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

        let requestedWindowID = request.int(for: "windowID")
        let requestedTitle = request.string(for: "title") ?? request.string(for: "query")
        let requestedPID = request.int(for: "pid").map(Int32.init)
        await applyPreMutationDelay(for: request)
        let didFocus = windowController.focus(
            windowID: requestedWindowID,
            title: requestedTitle,
            pid: requestedPID
        )
        await applyPostMutationDelay(for: request)
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: didFocus ? .success : .failed,
            message: didFocus ? "Focused window." : "Unable to focus the requested window."
        )
    }

    private func windowAssertResult(for request: ActionRequest) async -> ActionResult {
        let rules = await settings().excludedWindows
        let match = windowController.matchingWindow(
            windowID: request.int(for: "windowID"),
            title: request.string(for: "title"),
            query: request.string(for: "query"),
            pid: request.int(for: "pid").map(Int32.init),
            excluding: rules
        )
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: match == nil ? .notFound : .success,
            message: match == nil ? "No visible window matched the request." : "Found matching window.",
            payload: match?.payload
        )
    }

    private func mediaScreenshotResult(for request: ActionRequest) async -> ActionResult {
        guard let path = request.string(for: "path"), path.isEmpty == false else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .invalidRequest,
                message: "media.screenshot requires a non-empty path."
            )
        }

        let format = normalizedScreenshotFormat(from: request.string(for: "format"))
        guard format == "png" || format == "jpg" else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .invalidRequest,
                message: "media.screenshot supports png and jpg formats."
            )
        }

        guard let scope = mediaCaptureScope(from: request) else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .notFound,
                message: "Unable to resolve a screenshot scope for the requested app or window."
            )
        }

        let result = await screenMediaController.screenshot(
            ScreenshotCaptureRequest(
                path: path,
                format: format,
                includeCursor: request.bool(for: "includeCursor") ?? false,
                scope: scope
            )
        )
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: result.outcome,
            message: result.message,
            payload: result.payload
        )
    }

    private func mediaRecordResult(for request: ActionRequest) async -> ActionResult {
        let operation = (request.string(for: "operation") ?? request.string(for: "action") ?? "status").lowercased()

        switch operation {
        case "start":
            guard let path = request.string(for: "path"), path.isEmpty == false else {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .invalidRequest,
                    message: "media.record start requires a path."
                )
            }
            let sessionID = request.string(for: "sessionID") ?? UUID().uuidString
            let codec = normalizedRecordingCodec(from: request.string(for: "codec"))
            let fps = max(request.int(for: "fps") ?? 12, 1)
            guard let scope = mediaCaptureScope(from: request) else {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .notFound,
                    message: "Unable to resolve a recording scope for the requested app or window."
                )
            }
            let result = await screenMediaController.startRecording(
                ScreenRecordingRequest(
                    sessionID: sessionID,
                    path: path,
                    codec: codec,
                    fps: fps,
                    includeCursor: request.bool(for: "includeCursor") ?? false,
                    maxDurationSeconds: request.int(for: "maxDurationSeconds"),
                    scope: scope
                )
            )
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: result.outcome,
                message: result.message,
                payload: result.payload
            )
        case "stop":
            let result = await screenMediaController.stopRecording(sessionID: request.string(for: "sessionID"))
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: result.outcome,
                message: result.message,
                payload: result.payload
            )
        case "status":
            let result = await screenMediaController.recordingStatus(sessionID: request.string(for: "sessionID"))
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: result.outcome,
                message: result.message,
                payload: result.payload
            )
        default:
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .invalidRequest,
                message: "media.record supports start, stop, and status."
            )
        }
    }

    private func mediaStreamResult(for request: ActionRequest) async -> ActionResult {
        let operation = (request.string(for: "operation") ?? request.string(for: "action") ?? "status").lowercased()

        switch operation {
        case "start":
            let sessionID = request.string(for: "sessionID") ?? UUID().uuidString
            let format = (request.string(for: "format") ?? "mjpeg").lowercased()
            let fps = max(request.int(for: "fps") ?? 4, 1)
            guard let scope = mediaCaptureScope(from: request) else {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .notFound,
                    message: "Unable to resolve a streaming scope for the requested app or window."
                )
            }
            let result = await screenMediaController.startStream(
                ScreenStreamRequest(
                    sessionID: sessionID,
                    format: format,
                    endpoint: request.string(for: "endpoint"),
                    fps: fps,
                    includeCursor: request.bool(for: "includeCursor") ?? false,
                    scope: scope
                )
            )
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: result.outcome,
                message: result.message,
                payload: result.payload
            )
        case "stop":
            let result = await screenMediaController.stopStream(sessionID: request.string(for: "sessionID"))
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: result.outcome,
                message: result.message,
                payload: result.payload
            )
        case "status":
            let result = await screenMediaController.streamStatus(sessionID: request.string(for: "sessionID"))
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: result.outcome,
                message: result.message,
                payload: result.payload
            )
        default:
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .invalidRequest,
                message: "media.stream supports start, stop, and status."
            )
        }
    }

    private func mediaCaptureScope(from request: ActionRequest) -> ScreenCaptureScope? {
        if let windowID = request.int(for: "windowID") {
            let window = windowController.visibleWindows(excluding: []).first { $0.id == windowID }
            return ScreenCaptureScope(
                windowID: windowID,
                rect: window?.frame,
                description: window.map { "window:\($0.appName)/\($0.title)" } ?? "window:\(windowID)"
            )
        }

        let resolvedApplication = resolvePID(from: request)
        if resolvedApplication.unresolvedApp != nil {
            return nil
        }

        if let pid = resolvedApplication.pid {
            let window = windowController.visibleWindows(excluding: []).first { $0.pid == pid }
            if let window {
                return ScreenCaptureScope(
                    windowID: window.id,
                    rect: window.frame,
                    description: "app:\(window.appName)"
                )
            }
            return ScreenCaptureScope(
                windowID: nil,
                rect: nil,
                description: "app:\(resolvedApplication.appName ?? "\(pid)")"
            )
        }

        return .fullScreen
    }

    private func normalizedScreenshotFormat(from value: String?) -> String {
        switch (value ?? "png").lowercased() {
        case "jpeg":
            return "jpg"
        default:
            return (value ?? "png").lowercased()
        }
    }

    private func normalizedRecordingCodec(from value: String?) -> String {
        switch (value ?? "h264").lowercased() {
        case "hevc", "raw":
            return (value ?? "h264").lowercased()
        default:
            return "h264"
        }
    }

    private func musicVolumeResult(for request: ActionRequest) async -> ActionResult {
        if let value = request.int(for: "value") {
            await applyPreMutationDelay(for: request)
            let result = await musicController.setVolume(value)
            await applyPostMutationDelay(for: request)
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
            await applyPreMutationDelay(for: request)
            let result = await airPlayController.disconnect()
            await applyPostMutationDelay(for: request)
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: result.0 ? .success : .failed,
                message: result.1
            )
        }

        if action == "menu" || action == "open_menu" || action == "chooser" {
            await applyPreMutationDelay(for: request)
            let result = await airPlayController.openMenu()
            await applyPostMutationDelay(for: request)
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

        await applyPreMutationDelay(for: request)
        let result = await airPlayController.connect(device: device)
        await applyPostMutationDelay(for: request)
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
        let text = request.string(for: "text") ?? request.string(for: "keys") ?? ""
        guard text.isEmpty == false else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .invalidRequest,
                message: "No text was provided."
            )
        }

        let currentSettings = await settings()
        let resolvedApplication = resolvePID(from: request)
        if let unresolvedApp = resolvedApplication.unresolvedApp {
            return unresolvedApplicationResult(for: request, app: unresolvedApp)
        }
        let pid = resolvedApplication.pid

        let targetResolution = textInsertTargetLookup(
            for: request,
            pid: pid,
            labelAlphabet: currentSettings.labelAlphabet
        )
        if let failure = targetResolution.failure {
            return failure
        }
        await applyPreMutationDelay(for: request)
        if let targetLookup = targetResolution.targetLookup {
            let didFocus = performInteraction(
                "press",
                on: targetLookup.target,
                pid: pid,
                labelAlphabet: currentSettings.labelAlphabet,
                request: request
            )
            guard didFocus else {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .failed,
                    message: "Unable to focus the requested text target."
                )
            }
            await sleeper.sleep(milliseconds: 120)
        }

        guard let capture = focusedTextBridge.captureFocusedContext() else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .notFound,
                message: "No focused text input is available."
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
        await applyPostMutationDelay(for: request)
        let postCapture = focusedTextBridge.captureFocusedContext()
        let expectationsSatisfied = textInsertExpectationsSatisfied(
            request: request,
            insertedText: text,
            initialContext: capture.context,
            postContext: postCapture?.context,
            submitResult: submitResult
        )
        let actionMs = Date().timeIntervalSince(startedAt) * 1_000
        let postStateStartedAt = Date()
        let targetLookup = targetResolution.targetLookup
        let postState = submitResult && expectationsSatisfied
            ? await postActionStatePayload(
                for: request,
                pid: pid,
                labelAlphabet: currentSettings.labelAlphabet,
                currentSessionID: targetLookup?.metrics.sessionID
            )
            : nil
        let postActionRefreshMs = postState == nil ? 0 : Date().timeIntervalSince(postStateStartedAt) * 1_000
        var payload: JSONValue = [
            "application": context.applicationName.map(JSONValue.string) ?? .null,
            "elementIdentifier": .string(context.elementIdentifier),
            "targetID": targetLookup.map { JSONValue.string($0.target.id) } ?? .null,
            "target": targetLookup.map { $0.target.payload } ?? .null,
            "sessionID": targetLookup.map { JSONValue.string($0.metrics.sessionID) } ?? request.arguments["sessionID"] ?? .null,
            "snapshotID": targetLookup.map { JSONValue.string($0.metrics.snapshotID) } ?? request.arguments["snapshotID"] ?? .null,
            "graphID": targetLookup.map { JSONValue.string($0.metrics.sessionID) } ?? request.arguments["graphID"] ?? request.arguments["sessionID"] ?? .null,
        ]
        if let payloadObject = payload.objectValue, let postState {
            payload = .object(
                payloadObject.merging(
                    ["postState": postState],
                    uniquingKeysWith: { _, new in new }
                )
            )
        }
        if debugTimingsRequested(for: request), let payloadObject = payload.objectValue {
            payload = .object(
                payloadObject.merging(
                    [
                        "timings": debugTimingsPayload(
                            searchMetrics: nil,
                            actionMs: actionMs,
                            postActionRefreshMs: postActionRefreshMs
                        ),
                    ],
                    uniquingKeysWith: { _, new in new }
                )
            )
        }

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: submitResult && expectationsSatisfied ? .success : .failed,
            message: submitResult == false
                ? "Inserted text, but failed to submit."
                : (expectationsSatisfied ? "Inserted text into the focused input." : "Inserted text, but the requested postconditions did not match."),
            payload: payload
        )
    }

    private func textReadResult(for request: ActionRequest) async -> ActionResult {
        let currentSettings = await settings()
        let resolvedApplication = resolvePID(from: request)
        if let unresolvedApp = resolvedApplication.unresolvedApp {
            return unresolvedApplicationResult(for: request, app: unresolvedApp)
        }

        let pid = resolvedApplication.pid
        let targetResolution = textInsertTargetLookup(
            for: request,
            pid: pid,
            labelAlphabet: currentSettings.labelAlphabet
        )
        if let failure = targetResolution.failure {
            return failure
        }

        await applyPreMutationDelay(for: request)
        if let targetLookup = targetResolution.targetLookup {
            let didFocus = performInteraction(
                "press",
                on: targetLookup.target,
                pid: pid,
                labelAlphabet: currentSettings.labelAlphabet,
                request: request
            )
            guard didFocus else {
                return ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .failed,
                    message: "Unable to focus the requested text target."
                )
            }
            await sleeper.sleep(milliseconds: 120)
        }

        guard let capture = focusedTextBridge.captureFocusedContext() else {
            if request.string(for: "query") != nil || request.string(for: "targetID") != nil {
                return await uiReadResult(for: request)
            }
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .notFound,
                message: "No focused text input is available."
            )
        }

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: .success,
            message: "Read the focused text input.",
            payload: [
                "applicationBundleID": capture.context.applicationBundleID.map(JSONValue.string) ?? .null,
                "application": capture.context.applicationName.map(JSONValue.string) ?? .null,
                "processIdentifier": capture.context.processIdentifier.map { .number(Double($0)) } ?? .null,
                "elementIdentifier": .string(capture.context.elementIdentifier),
                "windowTitle": capture.context.windowTitle.map(JSONValue.string) ?? .null,
                "text": .string(capture.context.text),
                "cursor": [
                    "location": .number(Double(capture.context.cursor.range.location)),
                    "length": .number(Double(capture.context.cursor.range.length)),
                    "preferredColumn": capture.context.cursor.preferredColumn.map { .number(Double($0)) } ?? .null,
                ],
                "isSecureInput": .bool(capture.context.isSecureInput),
                "targetID": targetResolution.targetLookup.map { .string($0.target.id) } ?? .null,
                "target": targetResolution.targetLookup.map { $0.target.payload } ?? .null,
                "sessionID": targetResolution.targetLookup.map { .string($0.metrics.sessionID) } ?? request.arguments["sessionID"] ?? .null,
                "snapshotID": targetResolution.targetLookup.map { .string($0.metrics.snapshotID) } ?? request.arguments["snapshotID"] ?? .null,
                "graphID": targetResolution.targetLookup.map { .string($0.metrics.sessionID) } ?? request.arguments["graphID"] ?? request.arguments["sessionID"] ?? .null,
            ]
        )
    }

    private func menuSelectResult(for request: ActionRequest) async -> ActionResult {
        let menuPath = menuPathComponents(from: request)
        guard menuPath.isEmpty == false else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .invalidRequest,
                message: "Missing menu path."
            )
        }

        guard let appName = request.string(for: "app") ?? NSWorkspace.shared.frontmostApplication?.localizedName,
              appName.isEmpty == false
        else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .notFound,
                message: "Unable to determine which application menu to control."
            )
        }

        let quotedPath = menuPath.map(appleScriptStringLiteral).joined(separator: ", ")
        let quotedApp = appleScriptStringLiteral(appName)
        let script = """
        set selectedPath to {\(quotedPath)}
        set didSelect to false
        tell application \(quotedApp) to activate
        delay 0.05
        tell application "System Events"
            tell process \(quotedApp)
                try
                    set currentMenuBarItem to menu bar item (item 1 of selectedPath) of menu bar 1
                    click currentMenuBarItem
                    if (count of selectedPath) is 1 then
                        set didSelect to true
                    else
                        set currentMenu to menu 1 of currentMenuBarItem
                        repeat with idx from 2 to count of selectedPath
                            set itemName to item idx of selectedPath
                            set currentMenuItem to first menu item of currentMenu whose name is itemName
                            if idx is (count of selectedPath) then
                                click currentMenuItem
                                set didSelect to true
                            else
                                set currentMenu to menu 1 of currentMenuItem
                            end if
                        end repeat
                    end if
                on error
                    try
                        key code 53
                    end try
                end try
            end tell
        end tell
        return didSelect
        """

        await applyPreMutationDelay(for: request)
        guard let result = try? await shellRunner.run(
            launchPath: "/usr/bin/osascript",
            arguments: ["-e", script],
            timeout: 2.0
        ) else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .failed,
                message: "Unable to control the application menu."
            )
        }
        await applyPostMutationDelay(for: request)

        let succeeded = result.terminationStatus == 0 &&
            result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: succeeded ? .success : .notFound,
            message: succeeded ? "Selected the requested menu item." : "Could not find the requested menu path.",
            payload: [
                "app": .string(appName),
                "menuPath": .array(menuPath.map(JSONValue.string)),
            ]
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

    private func inputKeyComboResult(for request: ActionRequest) async -> ActionResult {
        guard let descriptor = keyComboDescriptor(from: request) else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .invalidRequest,
                message: "Missing key combo."
            )
        }

        guard let resolvedKey = KeyboardKeyResolver.resolve(descriptor.key) else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .invalidRequest,
                message: "Unsupported key '\(descriptor.key)'."
            )
        }

        let modifiers = descriptor.modifiers.union(resolvedKey.implicitModifiers)
        let events = keyPressEvents(for: resolvedKey, modifiers: modifiers)

        await applyPreMutationDelay(for: request)
        let success = keyboardPerformer.post(events: events)
        await applyPostMutationDelay(for: request)

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: success ? .success : .failed,
            message: success ? "Posted keyboard combo." : "Unable to post keyboard combo.",
            payload: [
                "key": .string(descriptor.key),
                "modifiers": .array(modifiers.map(\.rawValue).sorted().map(JSONValue.string)),
                "eventCount": .number(Double(events.count)),
            ]
        )
    }

    private func inputKeySequenceResult(for request: ActionRequest) async -> ActionResult {
        let parsedSteps: [ParsedKeySequenceStep]
        do {
            parsedSteps = try parseKeySequenceSteps(from: request)
        } catch let error as KeySequenceParsingError {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .invalidRequest,
                message: error.message
            )
        } catch {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .failed,
                message: error.localizedDescription
            )
        }

        guard parsedSteps.isEmpty == false else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .invalidRequest,
                message: "No key sequence was provided."
            )
        }

        await applyPreMutationDelay(for: request)
        var success = true
        var eventCount = 0
        for step in parsedSteps {
            if step.events.isEmpty == false {
                success = keyboardPerformer.post(events: step.events)
                eventCount += step.events.count
                if success == false {
                    break
                }
            }
            if step.delayAfterMs > 0 {
                await sleeper.sleep(milliseconds: step.delayAfterMs)
            }
        }
        await applyPostMutationDelay(for: request)

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: success ? .success : .failed,
            message: success ? "Posted keyboard sequence." : "Unable to post keyboard sequence.",
            payload: [
                "stepCount": .number(Double(parsedSteps.count)),
                "eventCount": .number(Double(eventCount)),
            ]
        )
    }

    private func uiGestureResult(for request: ActionRequest) async -> ActionResult {
        let preset = normalizedGesturePreset(from: request)
        guard preset.isEmpty == false else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .invalidRequest,
                message: "Missing gesture preset."
            )
        }

        let currentSettings = await settings()
        let resolvedApplication = resolvePID(from: request)
        if let unresolvedApp = resolvedApplication.unresolvedApp {
            return unresolvedApplicationResult(for: request, app: unresolvedApp)
        }

        switch preset {
        case "scroll_up":
            return await scrollGestureResult(
                for: request,
                preset: preset,
                direction: "up",
                resolvedApplication: resolvedApplication,
                currentSettings: currentSettings
            )
        case "scroll_down":
            return await scrollGestureResult(
                for: request,
                preset: preset,
                direction: "down",
                resolvedApplication: resolvedApplication,
                currentSettings: currentSettings
            )
        case "swipe_left", "swipe_right":
            return await swipeGestureResult(
                for: request,
                preset: preset,
                resolvedApplication: resolvedApplication,
                currentSettings: currentSettings
            )
        default:
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .unsupported,
                message: "Gesture preset '\(preset)' is not supported."
            )
        }
    }

    private func scrollGestureResult(
        for request: ActionRequest,
        preset: String,
        direction: String,
        resolvedApplication: ResolvedTargetApplication,
        currentSettings: WizmacSettings
    ) async -> ActionResult {
        let targetResolution = optionalUITargetResolution(
            for: request,
            resolvedApplication: resolvedApplication,
            currentSettings: currentSettings
        )
        if let failure = targetResolution.failure {
            return failure
        }

        let snapshot = gestureSnapshot(
            for: request,
            resolvedApplication: resolvedApplication,
            labelAlphabet: currentSettings.labelAlphabet
        )
        guard let snapshot else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .permissionRequired,
                message: "Unable to inspect scrollable targets for the requested gesture."
            )
        }

        if let targetLookup = targetResolution.targetLookup {
            scrollController.focus(targetID: targetLookup.target.id)
        }

        let distance = max(request.arguments["distance"]?.doubleValue ?? Double((request.int(for: "amount") ?? 3) * 120), 1)
        let totalAmount = max(request.int(for: "amount") ?? Int((distance / 120).rounded(.awayFromZero)), 1)
        let durationMs = max(request.int(for: "durationMs") ?? 0, 0)
        let segmentCount = max(1, min(8, durationMs > 0 ? Int(ceil(Double(durationMs) / 120.0)) : 1))
        let interSegmentDelay = segmentCount > 1 ? max(durationMs / segmentCount, 1) : 0

        await applyPreMutationDelay(for: request)
        var success = true
        for index in 0..<segmentCount {
            let amount = totalAmount / segmentCount + (index < (totalAmount % segmentCount) ? 1 : 0)
            if amount > 0 {
                success = scrollController.step(direction: direction, amount: amount, snapshot: snapshot) && success
            }
            if index < (segmentCount - 1), interSegmentDelay > 0 {
                await sleeper.sleep(milliseconds: interSegmentDelay)
            }
        }
        await applyPostMutationDelay(for: request)

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: success ? .success : .failed,
            message: success ? "Performed \(preset) gesture." : "Unable to perform \(preset) gesture.",
            payload: [
                "preset": .string(preset),
                "direction": .string(direction),
                "distance": .number(distance),
                "durationMs": .number(Double(durationMs)),
                "amount": .number(Double(totalAmount)),
                "segmentCount": .number(Double(segmentCount)),
                "targetID": targetResolution.targetLookup.map { .string($0.target.id) } ?? .null,
            ]
        )
    }

    private func swipeGestureResult(
        for request: ActionRequest,
        preset: String,
        resolvedApplication: ResolvedTargetApplication,
        currentSettings: WizmacSettings
    ) async -> ActionResult {
        let targetResolution = optionalUITargetResolution(
            for: request,
            resolvedApplication: resolvedApplication,
            currentSettings: currentSettings
        )
        if let failure = targetResolution.failure {
            return failure
        }

        let snapshot = gestureSnapshot(
            for: request,
            resolvedApplication: resolvedApplication,
            labelAlphabet: currentSettings.labelAlphabet
        )
        guard let frame = gestureFrame(snapshot: snapshot, targetLookup: targetResolution.targetLookup) else {
            return ActionResult(
                requestID: request.id,
                action: request.action,
                outcome: .notFound,
                message: "Unable to determine where to perform the requested gesture."
            )
        }

        let durationMs = max(request.int(for: "durationMs") ?? 180, 0)
        let requestedDistance = max(request.arguments["distance"]?.doubleValue ?? min(frame.width * 0.35, 240), 24)
        let availableDistance = max(min(requestedDistance, max(frame.width - 24, 24)), 24)
        let margin = min(max(frame.width * 0.1, 12), 32)
        let center = frame.center
        let halfDistance = availableDistance / 2
        let minimumX = frame.x + margin
        let maximumX = frame.x + frame.width - margin
        let startX: Double
        let endX: Double

        switch preset {
        case "swipe_left":
            startX = min(maximumX, center.x + halfDistance)
            endX = max(minimumX, center.x - halfDistance)
        default:
            startX = max(minimumX, center.x - halfDistance)
            endX = min(maximumX, center.x + halfDistance)
        }

        let steps = max(4, min(48, durationMs > 0 ? max(durationMs / 16, 4) : 8))
        let start = CGPoint(x: startX, y: center.y)
        let end = CGPoint(x: endX, y: center.y)

        await applyPreMutationDelay(for: request)
        let success = pointerPerformer.drag(from: start, to: end, steps: steps)
        await applyPostMutationDelay(for: request)

        return ActionResult(
            requestID: request.id,
            action: request.action,
            outcome: success ? .success : .failed,
            message: success ? "Performed \(preset) gesture." : "Unable to perform \(preset) gesture.",
            payload: [
                "preset": .string(preset),
                "distance": .number(availableDistance),
                "durationMs": .number(Double(durationMs)),
                "targetID": targetResolution.targetLookup.map { .string($0.target.id) } ?? .null,
            ]
        )
    }

    private func gestureSnapshot(
        for request: ActionRequest,
        resolvedApplication: ResolvedTargetApplication,
        labelAlphabet: String
    ) -> TargetSnapshot? {
        if let pid = resolvedApplication.pid {
            return snapshotter.snapshotApplication(pid: pid, labelAlphabet: labelAlphabet)
        }
        return snapshotter.snapshotFrontmostApplication(labelAlphabet: labelAlphabet)
    }

    private func optionalUITargetResolution(
        for request: ActionRequest,
        resolvedApplication: ResolvedTargetApplication,
        currentSettings: WizmacSettings
    ) -> UITargetResolution {
        let hasTargetID = request.string(for: "targetID")?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasQuery = request.string(for: "query")?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        guard hasTargetID || hasQuery else {
            return UITargetResolution(targetLookup: nil, failure: nil)
        }

        return resolveUITarget(
            for: request,
            resolvedApplication: resolvedApplication,
            currentSettings: currentSettings
        )
    }

    private func gestureFrame(snapshot: TargetSnapshot?, targetLookup: UITargetLookupResult?) -> TargetRect? {
        if let frame = targetLookup?.target.frame {
            return frame
        }

        if let snapshot {
            if let frame = scrollController.scrollTargets(from: snapshot).first?.frame {
                return frame
            }

            return snapshot.targets
                .compactMap(\.frame)
                .max { lhs, rhs in
                    (lhs.width * lhs.height) < (rhs.width * rhs.height)
                }
        }

        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return nil
        }
        return TargetRect(visibleFrame)
    }

    private func normalizedGesturePreset(from request: ActionRequest) -> String {
        (request.string(for: "preset") ?? request.string(for: "gesture") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func keyComboDescriptor(from request: ActionRequest) -> (key: String, modifiers: Set<TextKeyModifier>)? {
        if let key = request.string(for: "key")?.trimmingCharacters(in: .whitespacesAndNewlines),
           key.isEmpty == false {
            return (key, parsedModifiers(from: request.arguments["modifiers"]))
        }

        if let combo = request.string(for: "combo") ?? request.string(for: "shortcut") {
            return parseComboString(combo)
        }

        return nil
    }

    private func keyPressEvents(
        for resolvedKey: KeyboardResolvedKey,
        modifiers: Set<TextKeyModifier>
    ) -> [SynthesizedKeyEvent] {
        [
            SynthesizedKeyEvent(
                kind: .keyDown,
                keyCode: resolvedKey.keyCode,
                characters: resolvedKey.characters,
                modifiers: modifiers
            ),
            SynthesizedKeyEvent(
                kind: .keyUp,
                keyCode: resolvedKey.keyCode,
                characters: resolvedKey.characters,
                modifiers: modifiers
            ),
        ]
    }

    private func parsedModifiers(from value: JSONValue?) -> Set<TextKeyModifier> {
        switch value {
        case let .array(items):
            return Set(items.compactMap { item in
                item.stringValue.flatMap(parsedModifier(from:))
            })
        case let .string(raw):
            let tokens = raw
                .split(whereSeparator: { $0 == "+" || $0 == "," || $0 == " " })
                .map(String.init)
            return Set(tokens.compactMap(parsedModifier(from:)))
        default:
            return []
        }
    }

    private func parsedModifier(from raw: String) -> TextKeyModifier? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "control", "ctrl":
            return .control
        case "option", "opt", "alt":
            return .option
        case "shift":
            return .shift
        case "command", "cmd":
            return .command
        case "function", "fn":
            return .function
        default:
            return nil
        }
    }

    private func parseComboString(_ raw: String) -> (key: String, modifiers: Set<TextKeyModifier>)? {
        let components = raw
            .split(separator: "+")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        guard let key = components.last else { return nil }

        let modifierTokens = components.dropLast()
        let modifiers = modifierTokens.compactMap(parsedModifier(from:))
        guard modifiers.count == modifierTokens.count else {
            return nil
        }

        return (key, Set(modifiers))
    }

    private enum KeySequenceParsingError: Error {
        case invalid(String)

        var message: String {
            switch self {
            case let .invalid(message):
                return message
            }
        }
    }

    private func parseKeySequenceSteps(from request: ActionRequest) throws -> [ParsedKeySequenceStep] {
        if let items = request.array(for: "sequence") ?? request.array(for: "events") {
            return try items.map(parseKeySequenceStep(from:))
        }

        if let raw = request.string(for: "keys") ?? request.string(for: "sequence"),
           raw.isEmpty == false {
            return try keySequenceTokens(from: raw).map { token in
                try parseKeySequenceStep(from: .string(token))
            }
        }

        throw KeySequenceParsingError.invalid("No key sequence was provided.")
    }

    private func parseKeySequenceStep(from value: JSONValue) throws -> ParsedKeySequenceStep {
        switch value {
        case let .string(raw):
            if let combo = parseComboString(raw) {
                return try parsedKeySequenceStep(
                    key: combo.key,
                    modifiers: combo.modifiers,
                    kind: "press",
                    delayAfterMs: 0
                )
            }
            return try parsedKeySequenceStep(
                key: raw,
                modifiers: [],
                kind: "press",
                delayAfterMs: 0
            )
        case let .object(object):
            let delayAfterMs = max(object["delayMs"]?.intValue ?? 0, 0)
            if let combo = object["combo"]?.stringValue {
                guard let parsedCombo = parseComboString(combo) else {
                    throw KeySequenceParsingError.invalid("Unsupported combo '\(combo)'.")
                }
                return try parsedKeySequenceStep(
                    key: parsedCombo.key,
                    modifiers: parsedCombo.modifiers,
                    kind: object["kind"]?.stringValue ?? "press",
                    delayAfterMs: delayAfterMs
                )
            }

            if object["key"] == nil, object["token"] == nil, delayAfterMs > 0 {
                return ParsedKeySequenceStep(events: [], delayAfterMs: delayAfterMs)
            }

            guard let key = object["key"]?.stringValue ?? object["token"]?.stringValue else {
                throw KeySequenceParsingError.invalid("Each key sequence step must include a key or combo.")
            }

            return try parsedKeySequenceStep(
                key: key,
                modifiers: parsedModifiers(from: object["modifiers"]),
                kind: object["kind"]?.stringValue ?? "press",
                delayAfterMs: delayAfterMs
            )
        default:
            throw KeySequenceParsingError.invalid("Unsupported key sequence step.")
        }
    }

    private func parsedKeySequenceStep(
        key: String,
        modifiers: Set<TextKeyModifier>,
        kind: String,
        delayAfterMs: Int
    ) throws -> ParsedKeySequenceStep {
        guard let resolvedKey = KeyboardKeyResolver.resolve(key) else {
            throw KeySequenceParsingError.invalid("Unsupported key '\(key)'.")
        }

        let combinedModifiers = modifiers.union(resolvedKey.implicitModifiers)
        let normalizedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let events: [SynthesizedKeyEvent]

        switch normalizedKind {
        case "down", "keydown", "key_down":
            events = [
                SynthesizedKeyEvent(
                    kind: .keyDown,
                    keyCode: resolvedKey.keyCode,
                    characters: resolvedKey.characters,
                    modifiers: combinedModifiers
                ),
            ]
        case "up", "keyup", "key_up":
            events = [
                SynthesizedKeyEvent(
                    kind: .keyUp,
                    keyCode: resolvedKey.keyCode,
                    characters: resolvedKey.characters,
                    modifiers: combinedModifiers
                ),
            ]
        case "press", "tap":
            events = keyPressEvents(for: resolvedKey, modifiers: combinedModifiers)
        default:
            throw KeySequenceParsingError.invalid("Unsupported key sequence event kind '\(kind)'.")
        }

        return ParsedKeySequenceStep(events: events, delayAfterMs: delayAfterMs)
    }

    private func keySequenceTokens(from raw: String) throws -> [String] {
        var tokens: [String] = []
        var index = raw.startIndex

        while index < raw.endIndex {
            if raw[index] == "<" {
                guard let close = raw[index...].firstIndex(of: ">") else {
                    throw KeySequenceParsingError.invalid("Unterminated key token in sequence.")
                }
                let token = String(raw[raw.index(after: index)..<close])
                if token.isEmpty == false {
                    tokens.append(token)
                }
                index = raw.index(after: close)
            } else {
                tokens.append(String(raw[index]))
                index = raw.index(after: index)
            }
        }

        return tokens
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

        if let destinationQuery = request.string(for: "destinationQuery") ?? request.string(for: "toQuery"),
           destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
           let searchResult = snapshotter.search(
               query: destinationQuery,
               pid: pid,
               labelAlphabet: labelAlphabet,
               limit: max(request.int(for: "limit") ?? 1, 1),
               sessionID: request.string(for: "sessionID"),
               scope: searchScope(for: request),
               includeMenus: includeMenus(for: request)
           ),
           let frame = searchResult.snapshot.targets.first?.frame {
            return frame.center
        }

        return nil
    }

    private func uiSearchPayload(_ searchResult: UISearchResult, includeDebugTimings: Bool) -> JSONValue {
        var payload: JSONValue = [
            "appName": .string(searchResult.snapshot.appName),
            "bundleIdentifier": searchResult.snapshot.bundleIdentifier.map(JSONValue.string) ?? .null,
            "windowTitle": searchResult.snapshot.windowTitle.map(JSONValue.string) ?? .null,
            "sessionID": searchResult.snapshot.sessionID.map(JSONValue.string) ?? .null,
            "graphID": searchResult.snapshot.sessionID.map(JSONValue.string) ?? .null,
            "snapshotID": searchResult.snapshot.snapshotID.map(JSONValue.string) ?? .null,
            "stale": .bool(false),
            "engine": .string("ax"),
            "approvalMode": .string("strict"),
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

    private func debugTimingsPayload(
        searchMetrics: UISessionMetrics?,
        actionMs: Double,
        postActionRefreshMs: Double = 0
    ) -> JSONValue {
        [
            "clientProcessMs": .number(0),
            "transportMs": .number(0),
            "approvalMs": .number(0),
            "cacheLookupMs": .number(searchMetrics?.cacheLookupMs ?? 0),
            "snapshotMs": .number(searchMetrics?.snapshotMs ?? 0),
            "rankingMs": .number(searchMetrics?.rankingMs ?? 0),
            "graphLookupMs": .number(searchMetrics?.cacheLookupMs ?? 0),
            "snapshotRefreshMs": .number(searchMetrics?.snapshotMs ?? 0),
            "routePlanMs": .number(searchMetrics?.rankingMs ?? 0),
            "actionMs": .number(actionMs),
            "postActionRefreshMs": .number(postActionRefreshMs),
            "engine": .string("ax"),
            "approvalMode": .string("strict"),
            "cacheHit": .bool(searchMetrics?.cacheHit ?? false),
        ]
    }

    private func baseTargetPayload(
        targetLookup: UITargetLookupResult,
        interaction: String,
        extra: [String: JSONValue] = [:]
    ) -> JSONValue {
        var payload: [String: JSONValue] = [
            "targetID": .string(targetLookup.target.id),
            "target": targetLookup.target.payload,
            "interaction": .string(interaction),
            "appName": .string(targetLookup.metrics.appName),
            "windowTitle": targetLookup.metrics.windowTitle.map(JSONValue.string) ?? .null,
            "sessionID": .string(targetLookup.metrics.sessionID),
            "snapshotID": .string(targetLookup.metrics.snapshotID),
            "graphID": .string(targetLookup.metrics.sessionID),
            "engine": .string("ax"),
        ]
        for (key, value) in extra {
            payload[key] = value
        }
        return .object(payload)
    }

    private enum PostActionStateMode {
        case none
        case search(query: String, limit: Int)
        case capture(detail: String)
    }

    private struct UITargetResolution {
        var targetLookup: UITargetLookupResult?
        var failure: ActionResult?
    }

    private struct TextInsertTargetResolution {
        var targetLookup: UITargetLookupResult?
        var failure: ActionResult?
    }

    private struct UIObservationSnapshotResult {
        var snapshot: TargetSnapshot
        var metrics: UISessionMetrics
    }

    private struct UIObservationOutcome {
        var passed: Bool
        var detail: String
        var matchedTargets: [TargetDescriptor]
        var snapshot: TargetSnapshot
    }

    private func requestedPostActionState(for request: ActionRequest) -> PostActionStateMode {
        let nextLimit = max(request.int(for: "nextLimit") ?? 20, 1)
        if let nextQuery = request.string(for: "nextQuery") {
            return .search(query: nextQuery, limit: nextLimit)
        }

        guard let rawState = request.arguments["postState"] else {
            return .none
        }

        switch rawState {
        case .bool(false):
            return .none
        case .bool(true):
            return .capture(detail: "compact")
        case let .string(value):
            switch value.lowercased() {
            case "none", "false", "off":
                return .none
            case "search", "refresh":
                return .search(query: request.string(for: "query") ?? "", limit: nextLimit)
            case "capture", "compact":
                return .capture(detail: "compact")
            case "full":
                return .capture(detail: "full")
            default:
                return .capture(detail: "compact")
            }
        default:
            return .capture(detail: "compact")
        }
    }

    private func postActionStatePayload(
        for request: ActionRequest,
        pid: pid_t?,
        labelAlphabet: String,
        currentSessionID: String?
    ) async -> JSONValue? {
        let mode = requestedPostActionState(for: request)
        guard case .none = mode else {
            let sessionID = request.string(for: "sessionID") ?? currentSessionID
            if let sessionID {
                _ = snapshotter.endSession(id: sessionID)
            }

            switch mode {
            case let .search(query, limit):
                guard let searchResult = snapshotter.search(
                    query: query,
                    pid: pid,
                    labelAlphabet: labelAlphabet,
                    limit: limit,
                    sessionID: nil,
                    scope: searchScope(for: request),
                    includeMenus: includeMenus(for: request)
                ) else {
                    return nil
                }
                return uiSearchPayload(
                    searchResult,
                    includeDebugTimings: debugTimingsRequested(for: request)
                )
            case let .capture(detail):
                guard let searchResult = snapshotter.search(
                    query: "",
                    pid: pid,
                    labelAlphabet: labelAlphabet,
                    limit: 250,
                    sessionID: nil,
                    scope: searchScope(for: request),
                    includeMenus: false
                ) else {
                    return nil
                }
                guard var payload = uiSearchPayload(
                    searchResult,
                    includeDebugTimings: debugTimingsRequested(for: request)
                ).objectValue else {
                    return nil
                }
                payload["graphID"] = payload["sessionID"] ?? .null
                payload["stale"] = .bool(false)
                payload["engine"] = .string("ax")
                if detail != "full" {
                    payload["targets"] = .array((payload["targets"]?.arrayValue ?? []).prefix(25).map { $0 })
                }
                return .object(payload)
            case .none:
                return nil
            }
        }

        return nil
    }

    private func dragArguments(for request: ActionRequest) -> [String: JSONValue] {
        var arguments = request.arguments
        arguments["interaction"] = .string("drag")

        if arguments["targetID"] == nil,
           arguments["query"] == nil,
           let sourceQuery = request.string(for: "sourceQuery")?.trimmingCharacters(in: .whitespacesAndNewlines),
           sourceQuery.isEmpty == false {
            arguments["query"] = .string(sourceQuery)
        }

        if arguments["destinationTargetID"] == nil, let value = arguments["toTargetID"] {
            arguments["destinationTargetID"] = value
        }

        if arguments["destinationQuery"] == nil,
           let destinationQuery = request.string(for: "destinationQuery") ?? request.string(for: "toQuery"),
           destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            arguments["destinationQuery"] = .string(destinationQuery)
        }

        return arguments
    }

    private func desiredSelectionState(from rawValue: String) -> Bool? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on", "checked", "selected", "enabled":
            return true
        case "0", "false", "no", "off", "unchecked", "unselected", "disabled":
            return false
        default:
            return nil
        }
    }

    private func uiObservationSnapshot(
        for request: ActionRequest,
        resolvedApplication: ResolvedTargetApplication,
        currentSettings: WizmacSettings,
        forceRefresh: Bool,
        minimumLimit: Int = 25,
        bypassCache: Bool = false
    ) -> UIObservationSnapshotResult? {
        let sessionID = forceRefresh ? nil : request.string(for: "sessionID")

        if forceRefresh == false,
           bypassCache == false,
           let cachedSnapshot = snapshotter.sessionSnapshot(id: sessionID) {
            let cachedSessionID = cachedSnapshot.sessionID ?? sessionID ?? UUID().uuidString
            let cachedSnapshotID = cachedSnapshot.snapshotID ?? UUID().uuidString
            return UIObservationSnapshotResult(
                snapshot: cachedSnapshot,
                metrics: UISessionMetrics(
                    sessionID: cachedSessionID,
                    snapshotID: cachedSnapshotID,
                    appName: cachedSnapshot.appName,
                    windowTitle: cachedSnapshot.windowTitle,
                    targetCount: cachedSnapshot.targets.count,
                    cacheHit: true,
                    cacheHitRate: 1,
                    lastRefreshedAt: cachedSnapshot.generatedAt,
                    snapshotMs: 0,
                    cacheLookupMs: 0,
                    rankingMs: 0
                )
            )
        }

        guard let searchResult = snapshotter.search(
            query: "",
            pid: resolvedApplication.pid,
            labelAlphabet: currentSettings.labelAlphabet,
            limit: max(request.int(for: "limit") ?? minimumLimit, minimumLimit),
            sessionID: sessionID,
            scope: searchScope(for: request),
            includeMenus: includeMenus(for: request),
            bypassCache: bypassCache
        ) else {
            return nil
        }

        return UIObservationSnapshotResult(snapshot: searchResult.snapshot, metrics: searchResult.metrics)
    }

    private func matchingTargets(in snapshot: TargetSnapshot, for request: ActionRequest) -> [TargetDescriptor] {
        if let requestedTargetID = request.string(for: "targetID") ?? request.string(for: "query").flatMap(inferredTargetID(from:)) {
            return snapshot.targets.filter { $0.id == requestedTargetID }
        }

        guard let query = request.string(for: "query")?.trimmingCharacters(in: .whitespacesAndNewlines),
              query.isEmpty == false
        else {
            return snapshot.targets
        }

        let limit = max(request.int(for: "limit") ?? 25, 1)
        let directMatches = snapshot.targets
            .compactMap { target -> (TargetDescriptor, Int)? in
                let exactScore = FuzzyMatcher.exactMatchScore(query: query, in: target)
                if exactScore > 0 {
                    return (target, exactScore + 1_000)
                }

                let directScore = FuzzyMatcher.directTextScore(query: query, in: target)
                guard directScore > 0 else { return nil }
                return (target, directScore + 700)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
            }
            .map(\.0)

        if directMatches.isEmpty == false {
            return Array(directMatches.prefix(limit))
        }

        return SemanticTargetRanker.rankedTargets(in: snapshot, query: query, limit: limit)
    }

    private func scrollMatchingTargets(in snapshot: TargetSnapshot, for request: ActionRequest) -> [TargetDescriptor] {
        scrollMatchCandidates(
            in: snapshot,
            for: request,
            direction: request.string(for: "direction") ?? "down"
        ).map(\.0)
    }

    private func scrollMatchCandidates(
        in snapshot: TargetSnapshot,
        for request: ActionRequest,
        direction: String
    ) -> [(TargetDescriptor, Int)] {
        if let requestedTargetID = request.string(for: "targetID") ?? request.string(for: "query").flatMap(inferredTargetID(from:)) {
            return snapshot.targets
                .filter { $0.id == requestedTargetID }
                .map { ($0, Int.max) }
        }

        guard let query = request.string(for: "query")?.trimmingCharacters(in: .whitespacesAndNewlines),
              query.isEmpty == false
        else {
            return snapshot.targets.map { ($0, 0) }
        }

        let limit = max(request.int(for: "limit") ?? 25, 1)
        let container = resolvedScrollContainer(in: snapshot, for: request)
        var matchesByID: [String: (TargetDescriptor, Int)] = [:]

        for target in snapshot.targets {
            let baseScore: Int
            if let requestedTargetID = request.string(for: "targetID"), target.id == requestedTargetID {
                baseScore = Int.max / 4
            } else {
                let exactScore = FuzzyMatcher.exactMatchScore(query: query, in: target)
                if exactScore > 0 {
                    baseScore = exactScore + 1_000
                } else {
                    let strictScore = FuzzyMatcher.strictTextScore(query: query, in: target)
                    guard strictScore > 0 else { continue }
                    baseScore = strictScore + 700
                }
            }

            let totalScore = baseScore + scrollVisibilityBonus(
                for: target,
                container: container,
                direction: direction
            )

            if let existing = matchesByID[target.id], existing.1 >= totalScore {
                continue
            }
            matchesByID[target.id] = (target, totalScore)
        }

        return matchesByID.values
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                let leftArea = (lhs.0.frame?.width ?? 0) * (lhs.0.frame?.height ?? 0)
                let rightArea = (rhs.0.frame?.width ?? 0) * (rhs.0.frame?.height ?? 0)
                if leftArea != rightArea {
                    return leftArea > rightArea
                }
                return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
            }
            .prefix(limit)
            .map { ($0.0, $0.1) }
    }

    private func stabilizedScrollMatch(
        from matches: [(TargetDescriptor, Int)],
        request: ActionRequest,
        snapshotResult: UIObservationSnapshotResult,
        resolvedApplication: ResolvedTargetApplication,
        currentSettings: WizmacSettings,
        direction: String,
        pollIntervalMs: Int,
        maxSteps: Int,
        observationLimit: Int,
        stepCount: inout Int
    ) async -> (target: TargetDescriptor, snapshot: TargetSnapshot)? {
        guard let initialMatch = matches.first?.0 else { return nil }

        let initialContainer = resolvedScrollContainer(in: snapshotResult.snapshot, for: request)
        if isStableScrollMatch(initialMatch, container: initialContainer, direction: direction) {
            return (initialMatch, snapshotResult.snapshot)
        }
        guard stepCount < maxSteps else { return nil }

        guard let correctiveDirection = oppositeScrollDirection(from: direction) else {
            return nil
        }

        if scrollController.currentSession() == nil,
           scrollController.startSession(
               targetID: request.string(for: "scrollTargetID"),
               snapshot: snapshotResult.snapshot
           ) == nil {
            return nil
        }

        var latestSnapshotResult = snapshotResult

        for _ in 0..<2 {
            guard stepCount < maxSteps else { break }
            guard scrollController.step(direction: correctiveDirection, amount: 1, snapshot: latestSnapshotResult.snapshot) else {
                break
            }
            stepCount += 1
            try? await Task.sleep(nanoseconds: UInt64(pollIntervalMs) * 1_000_000)

            guard let refreshedSnapshotResult = uiObservationSnapshot(
                for: request,
                resolvedApplication: resolvedApplication,
                currentSettings: currentSettings,
                forceRefresh: true,
                minimumLimit: observationLimit,
                bypassCache: true
            ) else {
                break
            }

            latestSnapshotResult = refreshedSnapshotResult
            guard let refreshedMatch = scrollMatchCandidates(
                in: refreshedSnapshotResult.snapshot,
                for: request,
                direction: direction
            ).first?.0 else {
                break
            }

            let refreshedContainer = resolvedScrollContainer(in: refreshedSnapshotResult.snapshot, for: request)
            if isStableScrollMatch(refreshedMatch, container: refreshedContainer, direction: direction) {
                return (refreshedMatch, refreshedSnapshotResult.snapshot)
            }
        }

        return nil
    }

    private func resolvedScrollContainer(in snapshot: TargetSnapshot, for request: ActionRequest) -> TargetDescriptor? {
        if let currentSessionTargetID = scrollController.currentSession()?.targetID,
           let currentSessionTarget = snapshot.targets.first(where: { $0.id == currentSessionTargetID }) {
            return currentSessionTarget
        }

        if let requestedTargetID = request.string(for: "scrollTargetID"),
           let requestedTarget = snapshot.targets.first(where: { $0.id == requestedTargetID }) {
            return requestedTarget
        }

        return scrollController.scrollTargets(from: snapshot).first
    }

    private func scrollVisibilityBonus(
        for target: TargetDescriptor,
        container: TargetDescriptor?,
        direction: String
    ) -> Int {
        guard let targetFrame = target.frame?.cgRect else { return 0 }

        var score = 0
        if targetFrame.height >= 24 {
            score += 24
        } else if targetFrame.height < 10 {
            score -= 60
        }

        if targetFrame.width >= 160 {
            score += 16
        } else if targetFrame.width < 60 {
            score -= 24
        }

        guard let containerFrame = container?.frame?.cgRect else { return score }
        let visibleRect = targetFrame.intersection(containerFrame)
        guard visibleRect.isNull == false, visibleRect.width > 0, visibleRect.height > 0 else {
            return score - 120
        }

        let visibleHeightRatio = visibleRect.height / max(targetFrame.height, 1)
        if visibleHeightRatio >= 0.98 {
            score += 40
        } else if visibleHeightRatio >= 0.80 {
            score += 28
        } else if visibleHeightRatio >= 0.65 {
            score += 12
        } else {
            score -= 60
        }

        let edgeMargin = scrollEdgeMargin(for: containerFrame)
        switch direction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "up":
            if visibleRect.minY <= containerFrame.minY + edgeMargin {
                score -= 50
            }
        case "down":
            if visibleRect.maxY >= containerFrame.maxY - edgeMargin {
                score -= 50
            }
        default:
            break
        }

        return score
    }

    private func isStableScrollMatch(
        _ target: TargetDescriptor,
        container: TargetDescriptor?,
        direction: String
    ) -> Bool {
        guard let targetFrame = target.frame?.cgRect else { return true }
        guard targetFrame.width >= 48, targetFrame.height >= 10 else { return false }
        guard let containerFrame = container?.frame?.cgRect else { return true }

        let visibleRect = targetFrame.intersection(containerFrame)
        guard visibleRect.isNull == false, visibleRect.width > 0, visibleRect.height > 0 else { return false }

        let visibleHeightRatio = visibleRect.height / max(targetFrame.height, 1)
        guard visibleHeightRatio >= 0.65 else { return false }

        let edgeMargin = scrollEdgeMargin(for: containerFrame)
        switch direction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "up":
            return visibleRect.minY > containerFrame.minY + edgeMargin
        case "down":
            return visibleRect.maxY < containerFrame.maxY - edgeMargin
        default:
            return true
        }
    }

    private func scrollEdgeMargin(for containerFrame: CGRect) -> CGFloat {
        max(12, min(32, containerFrame.height * 0.08))
    }

    private func oppositeScrollDirection(from direction: String) -> String? {
        switch direction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "up":
            return "down"
        case "down":
            return "up"
        case "left":
            return "right"
        case "right":
            return "left"
        default:
            return nil
        }
    }


    private func preferredReadableText(for target: TargetDescriptor) -> String? {
        let candidates = [target.value ?? "", target.title, target.subtitle ?? "", target.hint ?? "", target.path.last ?? ""]
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return trimmed
            }
        }
        return nil
    }

    private func visibleTextLines(in snapshot: TargetSnapshot) -> [String] {
        var seen = Set<String>()
        var lines: [String] = []
        for target in snapshot.targets {
            guard let text = preferredReadableText(for: target) else { continue }
            if seen.insert(text).inserted {
                lines.append(text)
            }
        }
        return lines
    }

    private func observationOutcome(for request: ActionRequest, snapshot: TargetSnapshot) -> UIObservationOutcome {
        let normalizedQuery = request.string(for: "query")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedText = request.string(for: "text")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedWindowTitle = request.string(for: "windowTitle")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let expectGone = request.bool(for: "gone") ?? false
        let hasSelector = request.string(for: "targetID") != nil || normalizedQuery.isEmpty == false

        var matchedTargets = hasSelector ? matchingTargets(in: snapshot, for: request) : snapshot.targets

        if normalizedText.isEmpty == false {
            matchedTargets = matchedTargets.filter { target in
                let haystack = [
                    preferredReadableText(for: target) ?? "",
                    target.hint ?? "",
                    target.path.joined(separator: " "),
                ]
                .joined(separator: "\n")
                return haystack.localizedCaseInsensitiveContains(normalizedText)
            }
        }

        if let requestedState = request.string(for: "state"),
           let desiredState = desiredSelectionState(from: requestedState) {
            matchedTargets = matchedTargets.filter { $0.isSelectedLike == desiredState }
        }

        let matchCount = matchedTargets.count
        var passed = true
        var detailComponents: [String] = []

        if normalizedWindowTitle.isEmpty == false {
            let windowMatches = (snapshot.windowTitle ?? "").localizedCaseInsensitiveContains(normalizedWindowTitle)
            passed = passed && windowMatches
            detailComponents.append(windowMatches ? "Window title matched." : "Window title did not match.")
        }

        if expectGone {
            let gone = matchCount == 0
            passed = passed && gone
            detailComponents.append(gone ? "Target is gone." : "Target is still visible.")
        } else if let exactCount = request.int(for: "count") {
            let countMatches = matchCount == exactCount
            passed = passed && countMatches
            detailComponents.append(countMatches ? "Found exactly \(exactCount) match(es)." : "Found \(matchCount) match(es), expected \(exactCount).")
        } else {
            if let minCount = request.int(for: "minCount") {
                let countMatches = matchCount >= minCount
                passed = passed && countMatches
                detailComponents.append(countMatches ? "Found at least \(minCount) match(es)." : "Found \(matchCount) match(es), expected at least \(minCount).")
            }
            if let maxCount = request.int(for: "maxCount") {
                let countMatches = matchCount <= maxCount
                passed = passed && countMatches
                detailComponents.append(countMatches ? "Found at most \(maxCount) match(es)." : "Found \(matchCount) match(es), expected at most \(maxCount).")
            }
        }

        if expectGone == false,
           request.int(for: "count") == nil,
           request.int(for: "minCount") == nil,
           request.int(for: "maxCount") == nil,
           (hasSelector || normalizedText.isEmpty == false)
        {
            let found = matchCount > 0
            passed = passed && found
            detailComponents.append(found ? "Found matching UI content." : "No matching UI content is currently visible.")
        }

        if detailComponents.isEmpty {
            let hasVisibleTargets = snapshot.targets.isEmpty == false
            passed = hasVisibleTargets
            detailComponents.append(hasVisibleTargets ? "Captured visible UI content." : "No visible UI content is available.")
        }

        return UIObservationOutcome(
            passed: passed,
            detail: detailComponents.joined(separator: " "),
            matchedTargets: matchedTargets,
            snapshot: snapshot
        )
    }

    private func observationPayload(outcome: UIObservationOutcome, snapshot: TargetSnapshot) -> JSONValue {
        [
            "passed": .bool(outcome.passed),
            "detail": .string(outcome.detail),
            "matchedCount": .number(Double(outcome.matchedTargets.count)),
            "targets": .array(outcome.matchedTargets.prefix(25).map { $0.payload }),
            "appName": .string(snapshot.appName),
            "windowTitle": snapshot.windowTitle.map(JSONValue.string) ?? .null,
            "sessionID": snapshot.sessionID.map(JSONValue.string) ?? .null,
            "snapshotID": snapshot.snapshotID.map(JSONValue.string) ?? .null,
            "graphID": snapshot.sessionID.map(JSONValue.string) ?? .null,
        ]
    }

    private func diffPayload(before: TargetSnapshot, after: TargetSnapshot) -> JSONValue {
        let beforeByID = Dictionary(uniqueKeysWithValues: before.targets.map { ($0.id, $0) })
        let afterByID = Dictionary(uniqueKeysWithValues: after.targets.map { ($0.id, $0) })

        let beforeIDs = Set(beforeByID.keys)
        let afterIDs = Set(afterByID.keys)

        let added = after.targets.filter { beforeIDs.contains($0.id) == false }
        let removed = before.targets.filter { afterIDs.contains($0.id) == false }
        let updated = after.targets.filter { target in
            guard let prior = beforeByID[target.id] else { return false }
            return prior != target
        }

        let changed = before.appName != after.appName ||
            before.windowTitle != after.windowTitle ||
            before.bundleIdentifier != after.bundleIdentifier ||
            added.isEmpty == false ||
            removed.isEmpty == false ||
            updated.isEmpty == false

        return [
            "changed": .bool(changed),
            "before": [
                "appName": .string(before.appName),
                "bundleIdentifier": before.bundleIdentifier.map(JSONValue.string) ?? .null,
                "windowTitle": before.windowTitle.map(JSONValue.string) ?? .null,
                "targetCount": .number(Double(before.targets.count)),
                "sessionID": before.sessionID.map(JSONValue.string) ?? .null,
                "snapshotID": before.snapshotID.map(JSONValue.string) ?? .null,
            ],
            "after": [
                "appName": .string(after.appName),
                "bundleIdentifier": after.bundleIdentifier.map(JSONValue.string) ?? .null,
                "windowTitle": after.windowTitle.map(JSONValue.string) ?? .null,
                "targetCount": .number(Double(after.targets.count)),
                "sessionID": after.sessionID.map(JSONValue.string) ?? .null,
                "snapshotID": after.snapshotID.map(JSONValue.string) ?? .null,
            ],
            "addedTargets": .array(added.prefix(25).map { $0.payload }),
            "removedTargets": .array(removed.prefix(25).map { $0.payload }),
            "updatedTargets": .array(updated.prefix(25).map { $0.payload }),
        ]
    }

    private func propagatedUIArguments(from request: ActionRequest) -> [String: JSONValue] {
        let keys = [
            "targetID",
            "query",
            "limit",
            "pid",
            "app",
            "sessionID",
            "snapshotID",
            "scope",
            "includeMenus",
            "launchIfNeeded",
            "activate",
            "postState",
            "nextQuery",
            "nextLimit",
            "debugTimings",
            "autoTrust",
            "trustedSessionID",
            "adapter",
        ]

        return keys.reduce(into: [String: JSONValue]()) { partialResult, key in
            if let value = request.arguments[key], value != .null {
                partialResult[key] = value
            }
        }
    }

    private func textInsertTargetLookup(
        for request: ActionRequest,
        pid: pid_t?,
        labelAlphabet: String
    ) -> TextInsertTargetResolution {
        if let targetID = request.string(for: "targetID") {
            guard let lookup = snapshotter.target(
                id: targetID,
                pid: pid,
                labelAlphabet: labelAlphabet,
                sessionID: request.string(for: "sessionID"),
                snapshotID: request.string(for: "snapshotID"),
                scope: searchScope(for: request),
                includeMenus: includeMenus(for: request)
            ) else {
                return TextInsertTargetResolution(
                    targetLookup: nil,
                    failure: ActionResult(
                        requestID: request.id,
                        action: request.action,
                        outcome: .notFound,
                        message: "Target not found."
                    )
                )
            }
            return TextInsertTargetResolution(targetLookup: lookup, failure: nil)
        }

        guard let query = request.string(for: "query") else {
            return TextInsertTargetResolution(targetLookup: nil, failure: nil)
        }

        if let targetID = inferredTargetID(from: query) {
            guard let lookup = snapshotter.target(
                id: targetID,
                pid: pid,
                labelAlphabet: labelAlphabet,
                sessionID: request.string(for: "sessionID"),
                snapshotID: request.string(for: "snapshotID"),
                scope: searchScope(for: request),
                includeMenus: includeMenus(for: request)
            ) else {
                return TextInsertTargetResolution(
                    targetLookup: nil,
                    failure: ActionResult(
                        requestID: request.id,
                        action: request.action,
                        outcome: .notFound,
                        message: "Target not found."
                    )
                )
            }
            return TextInsertTargetResolution(targetLookup: lookup, failure: nil)
        }

        guard let searchResult = snapshotter.search(
            query: query,
            pid: pid,
            labelAlphabet: labelAlphabet,
            limit: max(request.int(for: "limit") ?? 1, 1),
            sessionID: request.string(for: "sessionID"),
            scope: searchScope(for: request),
            includeMenus: includeMenus(for: request)
        ) else {
            return TextInsertTargetResolution(
                targetLookup: nil,
                failure: ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .permissionRequired,
                    message: "Unable to inspect the requested application."
                )
            )
        }

        guard let firstTarget = searchResult.snapshot.targets.first else {
            return TextInsertTargetResolution(
                targetLookup: nil,
                failure: ActionResult(
                    requestID: request.id,
                    action: request.action,
                    outcome: .notFound,
                    message: "No UI target matched '\(query)'."
                )
            )
        }

        return TextInsertTargetResolution(
            targetLookup: UITargetLookupResult(
                target: firstTarget,
                metrics: searchResult.metrics
            ),
            failure: nil
        )
    }

    private func ambientBatchArguments(from arguments: [String: JSONValue]) -> [String: JSONValue] {
        var ambient: [String: JSONValue] = [:]
        for key in Self.ambientBatchArgumentKeys {
            if let value = arguments[key] {
                ambient[key] = value
            }
        }
        if ambient["graphID"] == nil, let sessionID = ambient["sessionID"] {
            ambient["graphID"] = sessionID
        }
        return ambient
    }

    private func updatedAmbientBatchArguments(
        from payload: JSONValue?,
        existing: [String: JSONValue]
    ) -> [String: JSONValue] {
        var ambient = existing
        guard let object = payload?.objectValue else {
            return ambient
        }
        for key in Self.ambientBatchArgumentKeys {
            if let value = object[key], value != .null {
                ambient[key] = value
            }
        }
        if ambient["graphID"] == nil, let sessionID = ambient["sessionID"] {
            ambient["graphID"] = sessionID
        }
        return ambient
    }

    private func batchedActionName(from rawTool: String) -> ActionName? {
        if let action = ActionName(rawValue: rawTool) {
            return action
        }

        switch rawTool.lowercased() {
        case "search":
            return .uiSearch
        case "act", "click":
            return .uiAct
        case "copy":
            return .uiCopy
        case "open":
            return .uiOpen
        case "focus":
            return .uiFocus
        case "select":
            return .uiSelect
        case "toggle":
            return .uiToggle
        case "read":
            return .uiRead
        case "wait":
            return .uiWait
        case "until":
            return .uiUntil
        case "assert":
            return .uiAssert
        case "diff":
            return .uiDiff
        case "watch":
            return .uiWatch
        case "submit":
            return .uiSubmit
        case "choose_file", "choosefile":
            return .uiChooseFile
        case "gesture":
            return .uiGesture
        case "key_combo", "keycombo":
            return .inputKeyCombo
        case "key_sequence", "keysequence":
            return .inputKeySequence
        default:
            return nil
        }
    }

    private func interpolateBatchArguments(
        _ arguments: [String: JSONValue],
        bindings: [String: JSONValue],
        ambientArguments: [String: JSONValue],
        lastResult: JSONValue?
    ) -> [String: JSONValue] {
        var resolved = ambientArguments
        for (key, value) in arguments {
            resolved[key] = interpolateJSONValue(
                value,
                bindings: bindings,
                ambientArguments: ambientArguments,
                lastResult: lastResult
            )
        }
        if resolved["graphID"] == nil, let sessionID = resolved["sessionID"] {
            resolved["graphID"] = sessionID
        }
        return resolved
    }

    private func interpolateJSONValue(
        _ value: JSONValue,
        bindings: [String: JSONValue],
        ambientArguments: [String: JSONValue],
        lastResult: JSONValue?
    ) -> JSONValue {
        switch value {
        case let .string(string):
            return interpolateTemplateString(
                string,
                bindings: bindings,
                ambientArguments: ambientArguments,
                lastResult: lastResult
            )
        case let .array(array):
            return .array(
                array.map {
                    interpolateJSONValue(
                        $0,
                        bindings: bindings,
                        ambientArguments: ambientArguments,
                        lastResult: lastResult
                    )
                }
            )
        case let .object(object):
            return .object(
                object.mapValues {
                    interpolateJSONValue(
                        $0,
                        bindings: bindings,
                        ambientArguments: ambientArguments,
                        lastResult: lastResult
                    )
                }
            )
        case .bool, .number, .null:
            return value
        }
    }

    private func interpolateTemplateString(
        _ value: String,
        bindings: [String: JSONValue],
        ambientArguments: [String: JSONValue],
        lastResult: JSONValue?
    ) -> JSONValue {
        let context = interpolationContext(
            bindings: bindings,
            ambientArguments: ambientArguments,
            lastResult: lastResult
        )
        let pattern = #"\{\{\s*(.*?)\s*\}\}"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return .string(value)
        }

        let range = NSRange(location: 0, length: (value as NSString).length)
        let matches = expression.matches(in: value, range: range)
        guard matches.isEmpty == false else {
            return .string(value)
        }

        if matches.count == 1,
           let match = matches.first,
           match.range == range,
           let pathRange = Range(match.range(at: 1), in: value),
           let resolved = resolveInterpolationPath(String(value[pathRange]), in: context)
        {
            return resolved
        }

        let nsValue = value as NSString
        let rendered = NSMutableString(string: value)
        for match in matches.reversed() {
            let pathRange = match.range(at: 1)
            guard pathRange.location != NSNotFound else {
                continue
            }
            let path = nsValue.substring(with: pathRange)
            guard let resolved = resolveInterpolationPath(path, in: context)
            else {
                continue
            }
            rendered.replaceCharacters(in: match.range, with: stringFragment(for: resolved))
        }
        return .string(rendered as String)
    }

    private func interpolationContext(
        bindings: [String: JSONValue],
        ambientArguments: [String: JSONValue],
        lastResult: JSONValue?
    ) -> [String: JSONValue] {
        var context = bindings
        context["env"] = .object(ambientArguments)
        if let lastResult {
            context["last"] = lastResult
        }
        return context
    }

    private func resolveInterpolationPath(
        _ rawPath: String,
        in context: [String: JSONValue]
    ) -> JSONValue? {
        let segments = interpolationSegments(from: rawPath)
        guard let first = segments.first else { return nil }

        var current: JSONValue?
        switch first {
        case let .key(key):
            current = context[key]
        case .index:
            current = nil
        }

        for segment in segments.dropFirst() {
            switch (current, segment) {
            case let (.some(.object(object)), .key(key)):
                current = object[key]
            case let (.some(.array(array)), .index(index)) where array.indices.contains(index):
                current = array[index]
            default:
                return nil
            }
        }

        return current
    }

    private enum InterpolationSegment {
        case key(String)
        case index(Int)
    }

    private func interpolationSegments(from rawPath: String) -> [InterpolationSegment] {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.isEmpty == false else { return [] }

        var segments: [InterpolationSegment] = []
        var buffer = ""
        var index = path.startIndex

        func flushBuffer() {
            guard buffer.isEmpty == false else { return }
            segments.append(.key(buffer))
            buffer.removeAll(keepingCapacity: true)
        }

        while index < path.endIndex {
            let character = path[index]
            if character == "." {
                flushBuffer()
                index = path.index(after: index)
                continue
            }
            if character == "[" {
                flushBuffer()
                guard let closeIndex = path[index...].firstIndex(of: "]") else {
                    buffer.append(character)
                    index = path.index(after: index)
                    continue
                }
                let token = path[path.index(after: index)..<closeIndex]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let arrayIndex = Int(token) {
                    segments.append(.index(arrayIndex))
                } else if token.isEmpty == false {
                    segments.append(.key(token))
                }
                index = path.index(after: closeIndex)
                continue
            }
            buffer.append(character)
            index = path.index(after: index)
        }

        flushBuffer()
        return segments
    }

    private func stringFragment(for value: JSONValue) -> String {
        switch value {
        case let .string(string):
            return string
        case let .number(number):
            if number.rounded(.towardZero) == number {
                return String(Int(number))
            }
            return String(number)
        case let .bool(boolean):
            return boolean ? "true" : "false"
        case .null:
            return ""
        case .array, .object:
            guard let data = try? JSONEncoder().encode(value) else { return "" }
            return String(decoding: data, as: UTF8.self)
        }
    }

    private static let ambientBatchArgumentKeys: [String] = [
        "pid",
        "app",
        "sessionID",
        "snapshotID",
        "graphID",
        "scope",
        "includeMenus",
        "launchIfNeeded",
        "activate",
        "trustedSessionID",
        "adapter",
    ]

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

    private func textInsertExpectationsSatisfied(
        request: ActionRequest,
        insertedText: String,
        initialContext: TextContextSnapshot,
        postContext: TextContextSnapshot?,
        submitResult: Bool
    ) -> Bool {
        guard submitResult else { return false }

        if let expectText = request.string(for: "expectText"),
           expectText.isEmpty == false,
           (postContext?.text.localizedCaseInsensitiveContains(expectText) ?? false) == false {
            return false
        }

        if request.bool(for: "expectCleared") == true,
           (postContext?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) == false {
            return false
        }

        if request.bool(for: "expectSent") == true {
            guard request.bool(for: "submit") == true else { return false }
            let currentText = postContext?.text ?? ""
            let cleared = currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let changedAwayFromInserted = currentText != initialContext.text && currentText.contains(insertedText) == false
            if cleared == false && changedAwayFromInserted == false {
                return false
            }
        }

        return true
    }

    private func postReturnKey(command: Bool = false) -> Bool {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false)
        else {
            return false
        }

        if command {
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
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

    private func menuPathComponents(from request: ActionRequest) -> [String] {
        if let explicit = request.array(for: "menuPath")?
            .compactMap(\.stringValue)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ $0.isEmpty == false }),
           explicit.isEmpty == false {
            return explicit
        }

        let rawPath = request.string(for: "path") ?? ""
        if rawPath.contains(">") {
            return rawPath
                .split(separator: ">")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
        }

        return rawPath.isEmpty ? [] : [rawPath]
    }

    private func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
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
