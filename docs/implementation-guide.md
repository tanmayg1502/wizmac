# Wizmac Implementation Guide

This is the "where do I change this?" document. It maps the main targets to their responsibilities and gives recipes for common extension work.

## Module Guide

### `WizmacCore`

Owns the shared language of the system:

- action names and result models
- settings defaults and persistence-facing models
- approval records and decisions
- stores for settings, audit, approvals, and service state
- trusted automation session policy and normalization helpers

Change here when you need to:

- add or rename an action
- change risky vs auto-approved defaults
- add a new persisted setting
- change how approval summaries are formed

High-signal files:

- `Sources/WizmacCore/Models.swift`
- `Sources/WizmacCore/ServiceModels.swift`
- `Sources/WizmacCore/Stores.swift`
- `Sources/WizmacCore/Approval.swift`
- `Sources/WizmacCore/TrustedAutomation.swift`

### `WizmacSystem`

Owns the macOS edge. This is where abstract actions become real system calls.

Capabilities here include:

- AX application and target discovery
- UI snapshots and session metadata
- pointer movement, click, drag, and copy flows
- window listing and focus
- scroll target discovery and step execution
- permission inspection and onboarding
- focused text capture and writeback
- Apple Music and AirPlay adapters

Change here when you need to:

- adjust how a tool interacts with the operating system
- add richer capture/search data
- change low-level text, window, or pointer behavior

High-signal files:

- `Sources/WizmacSystem/SystemExecutor.swift`
- `Sources/WizmacSystem/AccessibilitySnapshotter.swift`
- `Sources/WizmacSystem/FocusedTextBridge.swift`
- `Sources/WizmacSystem/ScrollController.swift`
- `Sources/WizmacSystem/WindowController.swift`
- `Sources/WizmacSystem/PermissionInspector.swift`

### `WizmacTextMode`

Owns the text-engine model and reducer behavior.

It currently provides:

- engine protocol and service facade
- reducer-driven fallback behavior
- a libvim-branded engine backed by an embedded shim
- text state, commands, cursor models, and key handling

Change here when you need to:

- modify modal editing semantics
- tune how keys are coalesced into inserts vs commands
- replace or deepen the current libvim integration

High-signal files:

- `Sources/WizmacTextMode/TextModeReducer.swift`
- `Sources/WizmacTextMode/TextModeModels.swift`
- `Sources/WizmacTextMode/FallbackTextModeEngine.swift`
- `Sources/WizmacTextMode/LibVimTextModeEngine.swift`
- `Sources/WizmacTextMode/EmbeddedLibVimShim.swift`

### `WizmacControlPlane`

Owns the public control surface and the shared-service lifecycle.

Responsibilities:

- tool definitions and schemas
- JSON-RPC method handling
- MCP stdio server
- HTTP JSON-RPC server
- XPC transport
- service host/client/process manager
- runtime-owned actions and session summaries
- remote identity enrollment, lookup, and revocation
- fixture-backed transport routing for tests

Change here when you need to:

- add a new public tool
- change CLI or JSON-RPC behavior
- adjust local vs remote source translation
- change service startup or transport discovery
- modify remote auth or pairing behavior

High-signal files:

- `Sources/WizmacControlPlane/ToolRegistry.swift`
- `Sources/WizmacControlPlane/CommandRouting.swift`
- `Sources/WizmacControlPlane/ServiceControlPlane.swift`
- `Sources/WizmacControlPlane/HTTPJSONRPCServer.swift`
- `Sources/WizmacControlPlane/XPCServiceBridge.swift`
- `Sources/WizmacControlPlane/RemoteIdentityStore.swift`

### `WizmacCLI`

Thin entry point for:

- namespaced command syntax
- explicit `call` syntax
- inline JSON-RPC
- MCP stdio mode
- service helpers like `health`, `snapshot`, and `settings`
- remote HTTP bootstrapping via `serve`

Change here when you need to:

- add a new top-level CLI mode
- change argument parsing ergonomics
- improve help or operator workflows

High-signal file:

- `Sources/WizmacCLI/main.swift`

### `WizmacService`

Tiny executable target that only boots `WizmacServiceHost`.

Change here only when startup ownership or lifecycle needs to shift.

### `WizmacMenuBarApp`

SwiftUI/AppKit shell for operators.

Responsibilities:

- onboarding missing permissions
- toggling local and remote interfaces
- viewing service health and session summaries
- pairing and revoking remote clients
- approving or rejecting risky actions

Change here when you need to:

- expose new service state to humans
- add an operator control
- improve status visibility or onboarding

High-signal files:

- `Sources/WizmacMenuBarApp/LiveMenuBarBackend.swift`
- `Sources/WizmacMenuBarApp/MenuBarModels.swift`
- `Sources/WizmacMenuBarApp/MenuBarViews.swift`

### `WizmacFixtureHost` and `WizmacFixtureHostSupport`

Deterministic validation surface for UI automation.

Change here when you need to:

- add a stable reproduction surface for a bug
- test a new kind of UI target
- add more windows or editable controls for automation validation

High-signal files:

- `Sources/WizmacFixtureHost/FixtureContentView.swift`
- `Sources/WizmacFixtureHost/FixtureEditorViews.swift`
- `Sources/WizmacFixtureHost/WizmacFixtureHostApp.swift`
- `Sources/WizmacFixtureHostSupport/FixtureSupport.swift`

## Common Change Recipes

### Add A New Tool

1. Add a new `ActionName` in `WizmacCore/Models.swift`.
2. Decide whether it is executor-owned or service-owned.
3. Add the tool schema in `ControlPlaneToolRegistry`.
4. Route the action:
   - service-owned: `WizmacServiceRuntime.handle`
   - executor-owned: `MacAutomationExecutor.execute`
5. Add risky or auto-approved defaults if needed.
6. Add tests in the nearest target:
   - registry/dispatcher behavior in `WizmacControlPlaneTests`
   - executor behavior in `WizmacSystemTests`
7. Update `docs/control-plane.md` and any README examples.

### Add A New Service-Owned Action

Use this path when the action should read or mutate service state rather than call macOS directly.

Typical touchpoints:

- `ActionName`
- `ToolRegistry`
- `WizmacServiceRuntime.handle`
- `WizmacServiceRuntime.snapshot` if it changes visible service state
- `ServiceClientControlPlaneRouter` tests or runtime tests

Examples already following this pattern:

- `system.health`
- `system.sessions`
- `remote.pair`
- `remote.revoke`

### Add A New macOS Executor Action

Use this path when the action should interact with AppKit, AX, media, text, or related adapters.

Typical touchpoints:

- `ActionName`
- `ToolRegistry`
- `MacAutomationExecutor.execute`
- one or more supporting controller or bridge files in `WizmacSystem`
- `ExecutorContractTests` or a focused system test

### Change Approval Behavior

Approval behavior is intentionally centralized.

Touchpoints:

- default action buckets in `WizmacCore/Models.swift`
- decision logic in `WizmacCore/Approval.swift`
- trusted-session scope in `WizmacCore/AutomationPolicy.swift`
- operator flows in `WizmacMenuBarApp` if the UX should change too

Questions to answer before you change it:

- Is the action state-changing?
- Should local trusted automation bypass it?
- Should the menu bar still bypass it?
- Does the summary reveal too much sensitive data?

### Add Session State To The Service Snapshot

When a new subsystem needs durable visibility:

1. Extend the matching service/session model in `WizmacCore/ServiceModels.swift`.
2. Teach `WizmacServiceRuntime` how to update and snapshot it.
3. Decide whether it should also appear in `activeSessions`.
4. Expose it in the menu bar backend if humans should see it.

### Expand Remote Access

Remote work almost always touches:

- `RemoteIdentityStore`
- `HTTPJSONRPCServer`
- `WizmacServiceRuntime.registeredRemoteHTTPIdentities`
- `WizmacServiceHost.syncRemoteServer`
- control-plane tests around source and auth behavior

Preserve these invariants:

- authenticated remote HTTP stays remote in origin semantics
- client pairing is explicit
- permissions/approvals still apply to risky remote actions

## Where To Look By Symptom

| Symptom | Start here |
| --- | --- |
| Tool is missing from `tools/list` | `ToolRegistry.swift` |
| CLI syntax works but JSON-RPC does not | `CommandRouting.swift` |
| JSON-RPC works but execution says unsupported | `SystemExecutor.swift` or `WizmacServiceRuntime.handle` |
| Approval appears unexpectedly | `Approval.swift`, `Models.swift`, `TrustedAutomation.swift` |
| Remote request source looks wrong | `HTTPJSONRPCServer.swift`, `CoreRouterAdapter.swift` |
| Service never comes up | `WizmacServiceProcessManager` in `ServiceControlPlane.swift` |
| Text mode attaches but behaves oddly | `TextModeReducer.swift`, `LibVimTextModeEngine.swift`, `FocusedTextBridge.swift` |
| Menu bar snapshot looks stale | `LiveMenuBarBackend.swift`, `WizmacServiceRuntime.snapshot` |

## Change Boundaries To Keep Clean

- Keep JSON-RPC and CLI normalization in `WizmacControlPlane`.
- Keep approval, audit, and settings defaults in `WizmacCore`.
- Keep AppKit/AX behavior in `WizmacSystem`.
- Keep modal text semantics in `WizmacTextMode`.
- Keep human operator UX in `WizmacMenuBarApp`.

If a change starts crossing all of those layers at once, pause and confirm that the abstraction boundary still makes sense.
