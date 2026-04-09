import Foundation

public struct ControlPlaneToolRegistry: Sendable {
    public let tools: [String: ControlPlaneToolDefinition]

    public init(tools: [ControlPlaneToolDefinition]) {
        self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    }

    public func tool(named name: String) -> ControlPlaneToolDefinition? {
        tools[name]
    }

    public func allTools() -> [ControlPlaneToolDefinition] {
        tools.values.sorted { $0.name < $1.name }
    }

    public func request(
        for toolName: String,
        arguments: [String: StructuredValue],
        source: ControlPlaneSource
    ) -> ControlPlaneActionRequest? {
        let segments = toolName.split(separator: ".", maxSplits: 1).map(String.init)
        guard segments.count == 2 else { return nil }

        return ControlPlaneActionRequest(
            namespace: segments[0],
            action: segments[1],
            arguments: arguments,
            source: source
        )
    }

    public static let `default` = ControlPlaneToolRegistry(tools: [
        .schemaBacked(
            name: "ui.apps",
            title: "List Running Apps",
            description: "List all running GUI applications with their pid, name, and bundle identifier.",
            schemaProperties: [:]
        ),
        .schemaBacked(
            name: "ui.search",
            title: "Search UI",
            description: "Search the accessibility tree and return matching targets, or resolve a previously captured targetID exactly. Pass pid or app (name/bundle ID) to target a specific app instead of the frontmost one.",
            schemaProperties: [
                "query": .string("string"),
                "targetID": .string("string"),
                "limit": .string("number"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "debugTimings": .string("boolean"),
                "adapter": .string("string"),
            ]
        ),
        .schemaBacked(
            name: "input.key_combo",
            title: "Input Key Combo",
            description: "Send a canonical key combo with optional modifier aliases, app targeting, and timing control.",
            schemaProperties: [
                "mods": .string("array"),
                "modifiers": .string("array"),
                "key": .string("string"),
                "app": .string("string"),
                "pid": .string("number"),
                "activate": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "autoTrust": .string("boolean"),
                "trustedSessionID": .string("string"),
                "preDelayMs": .string("number"),
                "postDelayMs": .string("number"),
                "timeoutMs": .string("number"),
                "debugTimings": .string("boolean"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "input.key_sequence",
            title: "Input Key Sequence",
            description: "Send a canonical key sequence with optional step expansion, app targeting, and timing control.",
            schemaProperties: [
                "sequence": .string("string"),
                "steps": .string("array"),
                "app": .string("string"),
                "pid": .string("number"),
                "activate": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "autoTrust": .string("boolean"),
                "trustedSessionID": .string("string"),
                "preDelayMs": .string("number"),
                "postDelayMs": .string("number"),
                "timeoutMs": .string("number"),
                "debugTimings": .string("boolean"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "batch.run",
            title: "Run Batch Flow",
            description: "Run a sequential batch of control-plane steps with step timing, cache, and failure reporting.",
            schemaProperties: [
                "steps": .string("array"),
                "file": .string("string"),
                "format": .string("string"),
                "failFast": .string("boolean"),
                "continueOnError": .string("boolean"),
                "output": .string("string"),
                "maxParallel": .string("number"),
                "cachePolicy": .string("string"),
                "snapshotReuse": .string("string"),
                "invalidateOn": .string("array"),
                "app": .string("string"),
                "pid": .string("number"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "adapter": .string("string"),
                "autoTrust": .string("boolean"),
                "trustedSessionID": .string("string"),
            ]
        ),
        .schemaBacked(
            name: "ui.act",
            title: "Act On UI Target",
            description: "Move, click, double-click, right-click, or drag a target. Pass targetID for an exact hit from a prior tree/search result, or query to resolve and act in one step. Pass pid or app to target a specific app.",
            schemaProperties: [
                "targetID": .string("string"),
                "query": .string("string"),
                "limit": .string("number"),
                "interaction": .string("string"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "autoTrust": .string("boolean"),
                "postState": .string("string"),
                "nextQuery": .string("string"),
                "nextLimit": .string("number"),
                "preDelayMs": .string("number"),
                "postDelayMs": .string("number"),
                "timeoutMs": .string("number"),
                "debugTimings": .string("boolean"),
                "trustedSessionID": .string("string"),
                "adapter": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "ui.gesture",
            title: "Gesture On UI Target",
            description: "Perform a pointer gesture against a target or resolved query with timing control.",
            schemaProperties: [
                "preset": .string("string"),
                "targetID": .string("string"),
                "query": .string("string"),
                "app": .string("string"),
                "pid": .string("number"),
                "distance": .string("number"),
                "durationMs": .string("number"),
                "preDelayMs": .string("number"),
                "postDelayMs": .string("number"),
                "timeoutMs": .string("number"),
                "autoTrust": .string("boolean"),
                "trustedSessionID": .string("string"),
                "debugTimings": .string("boolean"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "ui.copy",
            title: "Copy From UI",
            description: "Copy or yank text associated with a UI target. Pass targetID for an exact hit from a prior tree/search result, or query to resolve and copy in one step. Pass pid or app to target a specific app.",
            schemaProperties: [
                "targetID": .string("string"),
                "query": .string("string"),
                "limit": .string("number"),
                "mode": .string("string"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "autoTrust": .string("boolean"),
                "debugTimings": .string("boolean"),
                "trustedSessionID": .string("string"),
                "adapter": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "ui.open",
            title: "Open UI Target",
            description: "Open the UI item that best matches the query or targetID, promoting from text labels to actionable parents when possible.",
            schemaProperties: [
                "targetID": .string("string"),
                "query": .string("string"),
                "limit": .string("number"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "autoTrust": .string("boolean"),
                "postState": .string("string"),
                "nextQuery": .string("string"),
                "nextLimit": .string("number"),
                "debugTimings": .string("boolean"),
                "trustedSessionID": .string("string"),
                "adapter": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "ui.focus",
            title: "Focus UI Target",
            description: "Focus the best matching UI target by targetID or query, using the least invasive available interaction.",
            schemaProperties: [
                "targetID": .string("string"),
                "query": .string("string"),
                "limit": .string("number"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "autoTrust": .string("boolean"),
                "debugTimings": .string("boolean"),
                "trustedSessionID": .string("string"),
                "adapter": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "ui.select",
            title: "Select UI Option",
            description: "Select a UI option such as a tab, row, radio button, or popup choice by targetID, query, or option text.",
            schemaProperties: [
                "targetID": .string("string"),
                "query": .string("string"),
                "option": .string("string"),
                "limit": .string("number"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "autoTrust": .string("boolean"),
                "postState": .string("string"),
                "nextQuery": .string("string"),
                "nextLimit": .string("number"),
                "debugTimings": .string("boolean"),
                "trustedSessionID": .string("string"),
                "adapter": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "ui.toggle",
            title: "Toggle UI Control",
            description: "Set a checkbox, switch, or radio control to a desired state when the current state is discoverable, otherwise perform a single toggle.",
            schemaProperties: [
                "targetID": .string("string"),
                "query": .string("string"),
                "state": .string("string"),
                "limit": .string("number"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "autoTrust": .string("boolean"),
                "postState": .string("string"),
                "debugTimings": .string("boolean"),
                "trustedSessionID": .string("string"),
                "adapter": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "ui.read",
            title: "Read UI Content",
            description: "Read visible text, values, or the best matching UI target by targetID or query without requiring callers to parse the full tree.",
            schemaProperties: [
                "targetID": .string("string"),
                "query": .string("string"),
                "detail": .string("string"),
                "limit": .string("number"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "debugTimings": .string("boolean"),
                "adapter": .string("string"),
            ]
        ),
        .schemaBacked(
            name: "wait.ui.exists",
            title: "Wait For UI Existence",
            description: "Poll until a UI target exists and optionally remains stable for a requested duration.",
            schemaProperties: [
                "query": .string("string"),
                "targetID": .string("string"),
                "timeoutMs": .string("number"),
                "intervalMs": .string("number"),
                "stableForMs": .string("number"),
                "app": .string("string"),
                "pid": .string("number"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "adapter": .string("string"),
            ]
        ),
        .schemaBacked(
            name: "ui.wait",
            title: "Wait For UI Condition",
            description: "Poll for a UI condition such as a query match, text match, window title, selected state, or disappearance.",
            schemaProperties: [
                "targetID": .string("string"),
                "query": .string("string"),
                "text": .string("string"),
                "windowTitle": .string("string"),
                "state": .string("string"),
                "gone": .string("boolean"),
                "count": .string("number"),
                "minCount": .string("number"),
                "maxCount": .string("number"),
                "timeoutMs": .string("number"),
                "pollIntervalMs": .string("number"),
                "limit": .string("number"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "debugTimings": .string("boolean"),
                "adapter": .string("string"),
            ]
        ),
        .schemaBacked(
            name: "ui.until",
            title: "Wait Until UI Condition",
            description: "Alias for ui.wait with the same condition arguments.",
            schemaProperties: [
                "targetID": .string("string"),
                "query": .string("string"),
                "text": .string("string"),
                "windowTitle": .string("string"),
                "state": .string("string"),
                "gone": .string("boolean"),
                "count": .string("number"),
                "minCount": .string("number"),
                "maxCount": .string("number"),
                "timeoutMs": .string("number"),
                "pollIntervalMs": .string("number"),
                "limit": .string("number"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "debugTimings": .string("boolean"),
                "adapter": .string("string"),
            ]
        ),
        .schemaBacked(
            name: "ui.assert",
            title: "Assert UI Condition",
            description: "Check a UI condition once and fail if it is not currently true.",
            schemaProperties: [
                "targetID": .string("string"),
                "query": .string("string"),
                "text": .string("string"),
                "windowTitle": .string("string"),
                "state": .string("string"),
                "gone": .string("boolean"),
                "count": .string("number"),
                "minCount": .string("number"),
                "maxCount": .string("number"),
                "limit": .string("number"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "debugTimings": .string("boolean"),
                "adapter": .string("string"),
            ]
        ),
        .schemaBacked(
            name: "ui.diff",
            title: "Diff UI State",
            description: "Compare a cached UI session snapshot with a fresh capture and summarize what changed.",
            schemaProperties: [
                "baselineSessionID": .string("string"),
                "sessionID": .string("string"),
                "pid": .string("number"),
                "app": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "debugTimings": .string("boolean"),
                "adapter": .string("string"),
            ]
        ),
        .schemaBacked(
            name: "ui.watch",
            title: "Watch UI State",
            description: "Watch a cached or fresh UI snapshot until it changes or until a requested UI condition becomes true.",
            schemaProperties: [
                "baselineSessionID": .string("string"),
                "sessionID": .string("string"),
                "targetID": .string("string"),
                "query": .string("string"),
                "text": .string("string"),
                "windowTitle": .string("string"),
                "state": .string("string"),
                "gone": .string("boolean"),
                "count": .string("number"),
                "minCount": .string("number"),
                "maxCount": .string("number"),
                "timeoutMs": .string("number"),
                "pollIntervalMs": .string("number"),
                "pid": .string("number"),
                "app": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "debugTimings": .string("boolean"),
                "adapter": .string("string"),
            ]
        ),
        .schemaBacked(
            name: "ui.submit",
            title: "Submit UI Action",
            description: "Submit the current form or message by pressing Return, Command-Return, or clicking a matching submit control.",
            schemaProperties: [
                "targetID": .string("string"),
                "query": .string("string"),
                "strategy": .string("string"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "autoTrust": .string("boolean"),
                "postState": .string("string"),
                "nextQuery": .string("string"),
                "nextLimit": .string("number"),
                "debugTimings": .string("boolean"),
                "trustedSessionID": .string("string"),
                "adapter": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "ui.choose_file",
            title: "Choose File In Dialog",
            description: "Fill a file path into an open/save dialog field and optionally confirm with a matching button or submit strategy.",
            schemaProperties: [
                "path": .string("string"),
                "targetID": .string("string"),
                "query": .string("string"),
                "confirmQuery": .string("string"),
                "submit": .string("boolean"),
                "strategy": .string("string"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "autoTrust": .string("boolean"),
                "postState": .string("string"),
                "nextQuery": .string("string"),
                "nextLimit": .string("number"),
                "debugTimings": .string("boolean"),
                "trustedSessionID": .string("string"),
                "adapter": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "ui.capture",
            title: "Capture UI Graph",
            description: "Capture a focused-window or app snapshot and return graph/session metadata.",
            schemaProperties: [
                "scope": .string("string"),
                "detail": .string("string"),
                "targetID": .string("string"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "includeMenus": .string("boolean"),
                "maxDepth": .string("number"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "adapter": .string("string"),
                "debugTimings": .string("boolean"),
            ]
        ),
        .schemaBacked(
            name: "ui.prefetch",
            title: "Prefetch UI Graph",
            description: "Warm the service-owned graph cache for an app or pid before execution.",
            schemaProperties: [
                "pid": .string("number"),
                "app": .string("string"),
                "scope": .string("string"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "strategy": .string("string"),
                "adapter": .string("string"),
            ]
        ),
        .schemaBacked(
            name: "ui.execute",
            title: "Execute UI Action Batch",
            description: "Execute a batch of UI actions against a known graph/snapshot in a single round trip.",
            schemaProperties: [
                "actions": .string("array"),
                "pid": .string("number"),
                "app": .string("string"),
                "graphID": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "stopOnFailure": .string("boolean"),
                "adapter": .string("string"),
                "debugTimings": .string("boolean"),
                "autoTrust": .string("boolean"),
                "trustedSessionID": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "ui.hints",
            title: "UI Hints",
            description: "Create a hint session for an app. Pass pid or app to target a specific app instead of frontmost.",
            schemaProperties: [
                "query": .string("string"),
                "limit": .string("number"),
                "pid": .string("number"),
                "app": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
            ]
        ),
        .schemaBacked(
            name: "ui.drag",
            title: "Drag Between Targets",
            description: "Drag from one target to another target or point. Pass targetID/query for the source and toTargetID/destinationQuery for the destination.",
            schemaProperties: [
                "targetID": .string("string"),
                "query": .string("string"),
                "sourceQuery": .string("string"),
                "toTargetID": .string("string"),
                "destinationQuery": .string("string"),
                "toQuery": .string("string"),
                "x": .string("number"),
                "y": .string("number"),
                "steps": .string("number"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "autoTrust": .string("boolean"),
                "debugTimings": .string("boolean"),
                "trustedSessionID": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "ui.session_end",
            title: "End UI Session",
            description: "Drop a cached UI search session so future requests rebuild state.",
            schemaProperties: ["sessionID": .string("string")]
        ),
        .schemaBacked(
            name: "scroll.targets",
            title: "List Scroll Targets",
            description: "Enumerate scrollable areas in an app. Pass pid or app to target a specific app instead of frontmost.",
            schemaProperties: [
                "pid": .string("number"),
                "app": .string("string"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "debugTimings": .string("boolean"),
            ]
        ),
        .schemaBacked(
            name: "scroll.focus",
            title: "Focus Scroll Target",
            description: "Select a scrollable area as the active target. Pass pid or app to target a specific app.",
            schemaProperties: [
                "targetID": .string("string"),
                "pid": .string("number"),
                "app": .string("string"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
            ]
        ),
        .schemaBacked(
            name: "scroll.step",
            title: "Scroll Step",
            description: "Scroll an active target by a small or large step. Pass pid or app to target a specific app.",
            schemaProperties: [
                "direction": .string("string"),
                "amount": .string("number"),
                "pid": .string("number"),
                "app": .string("string"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "autoTrust": .string("boolean"),
                "trustedSessionID": .string("string"),
            ]
        ),
        .schemaBacked(
            name: "scroll.session_start",
            title: "Start Scroll Session",
            description: "Start a scroll target session for repeatable scrolling.",
            schemaProperties: ["targetID": .string("string")]
        ),
        .schemaBacked(
            name: "scroll.session_end",
            title: "End Scroll Session",
            description: "End the active scroll target session.",
            schemaProperties: [:]
        ),
        .schemaBacked(
            name: "scroll.to",
            title: "Scroll To UI Target",
            description: "Scroll until a matching UI target becomes visible.",
            schemaProperties: [
                "query": .string("string"),
                "targetID": .string("string"),
                "scrollTargetID": .string("string"),
                "direction": .string("string"),
                "amount": .string("number"),
                "maxSteps": .string("number"),
                "timeoutMs": .string("number"),
                "pollIntervalMs": .string("number"),
                "limit": .string("number"),
                "pid": .string("number"),
                "app": .string("string"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "autoTrust": .string("boolean"),
                "trustedSessionID": .string("string"),
                "debugTimings": .string("boolean"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "scroll.until",
            title: "Scroll Until UI Target",
            description: "Alias for scroll.to with the same arguments.",
            schemaProperties: [
                "query": .string("string"),
                "targetID": .string("string"),
                "scrollTargetID": .string("string"),
                "direction": .string("string"),
                "amount": .string("number"),
                "maxSteps": .string("number"),
                "timeoutMs": .string("number"),
                "pollIntervalMs": .string("number"),
                "limit": .string("number"),
                "pid": .string("number"),
                "app": .string("string"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "autoTrust": .string("boolean"),
                "trustedSessionID": .string("string"),
                "debugTimings": .string("boolean"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "scroll.into_view",
            title: "Scroll Into View",
            description: "Scroll a matching UI target into view if it is not already visible.",
            schemaProperties: [
                "query": .string("string"),
                "targetID": .string("string"),
                "scrollTargetID": .string("string"),
                "direction": .string("string"),
                "amount": .string("number"),
                "maxSteps": .string("number"),
                "timeoutMs": .string("number"),
                "pollIntervalMs": .string("number"),
                "limit": .string("number"),
                "pid": .string("number"),
                "app": .string("string"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "autoTrust": .string("boolean"),
                "trustedSessionID": .string("string"),
                "debugTimings": .string("boolean"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "window.list",
            title: "List Windows",
            description: "List visible windows ordered from frontmost to backmost.",
            schemaProperties: [:]
        ),
        .schemaBacked(
            name: "wait.window.focused",
            title: "Wait For Focused Window",
            description: "Poll until the frontmost visible window matches the requested selector and optional stability window.",
            schemaProperties: [
                "windowID": .string("number"),
                "windowTitle": .string("string"),
                "title": .string("string"),
                "query": .string("string"),
                "app": .string("string"),
                "pid": .string("number"),
                "timeoutMs": .string("number"),
                "intervalMs": .string("number"),
                "stableForMs": .string("number"),
            ]
        ),
        .schemaBacked(
            name: "wait.condition",
            title: "Wait For Generic Condition",
            description: "Poll a supported generic predicate such as ui.exists or window.focused.",
            schemaProperties: [
                "predicate": .string("string"),
                "timeoutMs": .string("number"),
                "intervalMs": .string("number"),
                "stableForMs": .string("number"),
                "query": .string("string"),
                "targetID": .string("string"),
                "windowID": .string("number"),
                "windowTitle": .string("string"),
                "title": .string("string"),
                "app": .string("string"),
                "pid": .string("number"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "adapter": .string("string"),
            ]
        ),
        .schemaBacked(
            name: "window.focus",
            title: "Focus Window",
            description: "Raise a visible window to the foreground.",
            schemaProperties: [
                "windowID": .string("number"),
                "title": .string("string"),
                "query": .string("string"),
                "pid": .string("number"),
                "autoTrust": .string("boolean"),
                "trustedSessionID": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "window.assert",
            title: "Assert Window",
            description: "Verify that a visible window matching an exact or fuzzy selector exists.",
            schemaProperties: [
                "windowID": .string("number"),
                "title": .string("string"),
                "query": .string("string"),
                "pid": .string("number"),
            ]
        ),
        .schemaBacked(
            name: "window.exclude",
            title: "Exclude Window",
            description: "Exclude a window from future focus and list flows.",
            schemaProperties: [
                "windowID": .string("number"),
                "title": .string("string"),
                "pid": .string("number"),
                "excluded": .string("boolean"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "text.attach",
            title: "Attach Text Mode",
            description: "Attach the modal text engine to the currently focused text context.",
            schemaProperties: [
                "autoTrust": .string("boolean"),
                "trustedSessionID": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "text.detach",
            title: "Detach Text Mode",
            description: "Detach the modal text engine from the active text context.",
            schemaProperties: [
                "autoTrust": .string("boolean"),
                "trustedSessionID": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "text.insert",
            title: "Insert Text",
            description: "Insert plain text into the focused input without attaching modal text mode first.",
            schemaProperties: [
                "text": .string("string"),
                "targetID": .string("string"),
                "query": .string("string"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "replaceSelection": .string("boolean"),
                "submit": .string("boolean"),
                "expectText": .string("string"),
                "expectCleared": .string("boolean"),
                "expectSent": .string("boolean"),
                "timeoutMs": .string("number"),
                "postState": .string("string"),
                "nextQuery": .string("string"),
                "nextLimit": .string("number"),
                "autoTrust": .string("boolean"),
                "debugTimings": .string("boolean"),
                "trustedSessionID": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "text.read",
            title: "Read Focused Text",
            description: "Read the currently focused text context without attaching text mode.",
            schemaProperties: [
                "targetID": .string("string"),
                "query": .string("string"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
                "debugTimings": .string("boolean"),
            ]
        ),
        .schemaBacked(
            name: "text.send_keys",
            title: "Send Keys",
            description: "Send literal or structured keys through the text engine.",
            schemaProperties: [
                "keys": .string("string"),
                "submit": .string("boolean"),
                "preDelayMs": .string("number"),
                "postDelayMs": .string("number"),
                "timeoutMs": .string("number"),
                "autoTrust": .string("boolean"),
                "debugTimings": .string("boolean"),
                "trustedSessionID": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "text.mode",
            title: "Text Mode State",
            description: "Get or set the current text engine mode.",
            schemaProperties: ["value": .string("string")]
        ),
        .schemaBacked(
            name: "text.status",
            title: "Text Status",
            description: "Read the attached text-mode session state.",
            schemaProperties: [:]
        ),
        .schemaBacked(
            name: "menu.select",
            title: "Select Menu Path",
            description: "Open and select an application menu path such as File > Export > PDF.",
            schemaProperties: [
                "app": .string("string"),
                "path": .string("string"),
                "menuPath": .string("array"),
                "autoTrust": .string("boolean"),
                "trustedSessionID": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "media.screenshot",
            title: "Take Screenshot",
            description: "Capture a screenshot to the requested path, optionally scoped to an app, pid, or window.",
            schemaProperties: [
                "path": .string("string"),
                "format": .string("string"),
                "includeCursor": .string("boolean"),
                "app": .string("string"),
                "pid": .string("number"),
                "windowID": .string("number"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "media.record",
            title: "Screen Recording",
            description: "Start, stop, or inspect a screen recording session.",
            schemaProperties: [
                "operation": .string("string"),
                "sessionID": .string("string"),
                "fps": .string("number"),
                "codec": .string("string"),
                "path": .string("string"),
                "app": .string("string"),
                "pid": .string("number"),
                "windowID": .string("number"),
                "includeCursor": .string("boolean"),
                "maxDurationSeconds": .string("number"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "media.stream",
            title: "Screen Stream",
            description: "Start, stop, or inspect a local screen streaming session.",
            schemaProperties: [
                "operation": .string("string"),
                "sessionID": .string("string"),
                "format": .string("string"),
                "endpoint": .string("string"),
                "fps": .string("number"),
                "app": .string("string"),
                "pid": .string("number"),
                "windowID": .string("number"),
                "includeCursor": .string("boolean"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "media.music_volume",
            title: "Music Volume",
            description: "Read or change Apple Music or iTunes volume.",
            schemaProperties: ["value": .string("number")],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "display.airplay_devices",
            title: "AirPlay Devices",
            description: "List discoverable AirPlay display targets.",
            schemaProperties: [:]
        ),
        .schemaBacked(
            name: "display.airplay_connect",
            title: "AirPlay Connect",
            description: "Connect, disconnect, or open the AirPlay display chooser.",
            schemaProperties: ["device": .string("string"), "action": .string("string")],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "display.airplay_disconnect",
            title: "AirPlay Disconnect",
            description: "Disconnect the current AirPlay display route.",
            schemaProperties: [:],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "system.permissions",
            title: "Permissions",
            description: "Inspect current macOS automation permissions.",
            schemaProperties: [:]
        ),
        .schemaBacked(
            name: "system.permissions_request",
            title: "Request Permissions",
            description: "Trigger native permission prompts or open the matching macOS privacy settings page.",
            schemaProperties: ["permission": .string("string"), "operation": .string("string")]
        ),
        .schemaBacked(
            name: "system.audit",
            title: "Audit Trail",
            description: "Read recent audit entries.",
            schemaProperties: ["limit": .string("number")]
        ),
        .schemaBacked(
            name: "system.health",
            title: "Service Health",
            description: "Read the health state of the long-lived Wizmac service.",
            schemaProperties: [:]
        ),
        .schemaBacked(
            name: "system.sessions",
            title: "Service Sessions",
            description: "Read active UI, text, hint, scroll, and trusted automation sessions tracked by the service.",
            schemaProperties: [:]
        ),
        .schemaBacked(
            name: "system.confirmation_status",
            title: "Confirmation Status",
            description: "Inspect or resolve a pending confirmation state.",
            schemaProperties: ["approvalID": .string("string"), "decision": .string("string")]
        ),
        .schemaBacked(
            name: "system.confirmation_resolve",
            title: "Resolve Confirmation",
            description: "Approve or reject a pending confirmation request.",
            schemaProperties: ["approvalID": .string("string"), "decision": .string("string")],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "system.trusted_session_start",
            title: "Start Trusted Session",
            description: "Start a short-lived trusted local automation session for a single app.",
            schemaProperties: [
                "app": .string("string"),
                "pid": .string("number"),
                "durationSeconds": .string("number"),
                "launchIfNeeded": .string("boolean"),
                "activate": .string("boolean"),
            ]
        ),
        .schemaBacked(
            name: "system.trusted_session_end",
            title: "End Trusted Session",
            description: "End the active trusted local automation session.",
            schemaProperties: ["trustedSessionID": .string("string")]
        ),
        .schemaBacked(
            name: "remote.clients",
            title: "Remote Clients",
            description: "List currently paired remote clients.",
            schemaProperties: [:]
        ),
        .schemaBacked(
            name: "remote.pair",
            title: "Pair Remote Client",
            description: "Create a new remote enrollment bundle for signature-based remote control.",
            schemaProperties: ["name": .string("string")],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "remote.revoke",
            title: "Revoke Remote Client",
            description: "Remove a remote client and invalidate its access token.",
            schemaProperties: ["clientID": .string("string"), "fingerprint": .string("string")],
            requiresConfirmation: true
        ),
        // ── iOS / iPadOS Physical Device Control ──────────────────────────────
        // Requires idb (Meta iOS Device Bridge): brew install idb-companion
        // WiFi usage: enable Developer Mode on device, then ios.connect host=<device-ip>
        .schemaBacked(
            name: "ios.connect",
            title: "Connect iOS Device over WiFi",
            description: "Connect to an iOS/iPadOS device or idb_companion over WiFi. Pass the device's IP address and optional port (default 27015). After connecting, all other ios.* tools work wirelessly. Requires Developer Mode enabled on the device (Settings > Privacy & Security > Developer Mode).",
            schemaProperties: [
                "host": .string("string"),
                "port": .string("number"),
            ]
        ),
        .schemaBacked(
            name: "ios.disconnect",
            title: "Disconnect iOS Device",
            description: "Disconnect a wirelessly connected iOS/iPadOS device by UDID. Use ios.devices to find the UDID first.",
            schemaProperties: [
                "udid": .string("string"),
            ]
        ),
        .schemaBacked(
            name: "ios.devices",
            title: "List iOS Devices",
            description: "List all physically connected iOS and iPadOS devices with their UDID, name, OS version, and state. Requires a USB-connected device trusted on this Mac.",
            schemaProperties: [:]
        ),
        .schemaBacked(
            name: "ios.screenshot",
            title: "iOS Screenshot",
            description: "Capture a screenshot from a connected iOS/iPadOS device and save it to a local path. Pass udid to target a specific device; omit to use the first connected device.",
            schemaProperties: [
                "udid": .string("string"),
                "path": .string("string"),
            ]
        ),
        .schemaBacked(
            name: "ios.accessibility",
            title: "iOS Accessibility Tree",
            description: "Fetch the full UI accessibility tree from a connected iOS/iPadOS device as JSON. Use this to discover element positions before tapping.",
            schemaProperties: [
                "udid": .string("string"),
            ]
        ),
        .schemaBacked(
            name: "ios.apps",
            title: "List iOS Apps",
            description: "List all installed apps on a connected iOS/iPadOS device, including bundle ID, display name, and install type.",
            schemaProperties: [
                "udid": .string("string"),
            ]
        ),
        .schemaBacked(
            name: "ios.tap",
            title: "iOS Tap",
            description: "Tap at a point (x, y) in screen coordinates on a connected iOS/iPadOS device. Use ios.accessibility first to discover element positions.",
            schemaProperties: [
                "udid": .string("string"),
                "x": .string("number"),
                "y": .string("number"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "ios.swipe",
            title: "iOS Swipe",
            description: "Swipe from (x1, y1) to (x2, y2) on a connected iOS/iPadOS device. Optional durationMs controls swipe speed (default 300ms).",
            schemaProperties: [
                "udid": .string("string"),
                "x1": .string("number"),
                "y1": .string("number"),
                "x2": .string("number"),
                "y2": .string("number"),
                "durationMs": .string("number"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "ios.type",
            title: "iOS Type Text",
            description: "Type text into the currently focused element on a connected iOS/iPadOS device. The on-screen keyboard must be visible or a text field focused.",
            schemaProperties: [
                "udid": .string("string"),
                "text": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "ios.button",
            title: "iOS Press Button",
            description: "Press a hardware button on a connected iOS/iPadOS device. Options: HOME, LOCK, SIDE_BUTTON, SIRI, APPLE_PAY, VOLUME_UP, VOLUME_DOWN.",
            schemaProperties: [
                "udid": .string("string"),
                "button": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "ios.launch",
            title: "iOS Launch App",
            description: "Launch an app by bundle ID on a connected iOS/iPadOS device. Use ios.apps to discover installed bundle IDs.",
            schemaProperties: [
                "udid": .string("string"),
                "bundleID": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "ios.terminate",
            title: "iOS Terminate App",
            description: "Terminate a running app by bundle ID on a connected iOS/iPadOS device.",
            schemaProperties: [
                "udid": .string("string"),
                "bundleID": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "ios.url",
            title: "iOS Open URL",
            description: "Open a URL (including custom app scheme URLs) on a connected iOS/iPadOS device.",
            schemaProperties: [
                "udid": .string("string"),
                "url": .string("string"),
            ],
            requiresConfirmation: true
        ),
    ])
}

private extension ControlPlaneToolDefinition {
    static func schemaBacked(
        name: String,
        title: String,
        description: String,
        schemaProperties: [String: StructuredValue],
        requiresConfirmation: Bool = false
    ) -> ControlPlaneToolDefinition {
        ControlPlaneToolDefinition(
            name: name,
            title: title,
            description: description,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(schemaProperties),
            ]),
            requiresConfirmation: requiresConfirmation
        )
    }
}
