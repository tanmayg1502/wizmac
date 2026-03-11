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
            description: "Search the accessibility tree and return matching targets. Pass pid or app (name/bundle ID) to target a specific app instead of the frontmost one.",
            schemaProperties: [
                "query": .string("string"),
                "limit": .string("number"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "debugTimings": .string("boolean"),
                "adapter": .string("string"),
            ]
        ),
        .schemaBacked(
            name: "ui.act",
            title: "Act On UI Target",
            description: "Move, click, double-click, right-click, or drag a target. Pass pid or app to target a specific app.",
            schemaProperties: [
                "targetID": .string("string"),
                "interaction": .string("string"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
                "debugTimings": .string("boolean"),
                "trustedSessionID": .string("string"),
                "adapter": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "ui.copy",
            title: "Copy From UI",
            description: "Copy or yank text associated with a UI target. Pass pid or app to target a specific app.",
            schemaProperties: [
                "targetID": .string("string"),
                "mode": .string("string"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
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
                "graphID": .string("string"),
                "snapshotID": .string("string"),
                "stopOnFailure": .string("boolean"),
                "adapter": .string("string"),
                "debugTimings": .string("boolean"),
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
            ]
        ),
        .schemaBacked(
            name: "ui.drag",
            title: "Drag Between Targets",
            description: "Drag from one target to another target or point. Pass pid or app to target a specific app.",
            schemaProperties: [
                "targetID": .string("string"),
                "toTargetID": .string("string"),
                "x": .string("number"),
                "y": .string("number"),
                "steps": .string("number"),
                "pid": .string("number"),
                "app": .string("string"),
                "sessionID": .string("string"),
                "snapshotID": .string("string"),
                "scope": .string("string"),
                "includeMenus": .string("boolean"),
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
            name: "window.list",
            title: "List Windows",
            description: "List visible windows ordered from frontmost to backmost.",
            schemaProperties: [:]
        ),
        .schemaBacked(
            name: "window.focus",
            title: "Focus Window",
            description: "Raise a visible window to the foreground.",
            schemaProperties: ["windowID": .string("number"), "title": .string("string"), "pid": .string("number")],
            requiresConfirmation: true
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
            schemaProperties: ["trustedSessionID": .string("string")],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "text.detach",
            title: "Detach Text Mode",
            description: "Detach the modal text engine from the active text context.",
            schemaProperties: ["trustedSessionID": .string("string")],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "text.insert",
            title: "Insert Text",
            description: "Insert plain text into the focused input without attaching modal text mode first.",
            schemaProperties: [
                "text": .string("string"),
                "replaceSelection": .string("boolean"),
                "submit": .string("boolean"),
                "debugTimings": .string("boolean"),
                "trustedSessionID": .string("string"),
            ],
            requiresConfirmation: true
        ),
        .schemaBacked(
            name: "text.send_keys",
            title: "Send Keys",
            description: "Send literal or structured keys through the text engine.",
            schemaProperties: [
                "keys": .string("string"),
                "submit": .string("boolean"),
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
