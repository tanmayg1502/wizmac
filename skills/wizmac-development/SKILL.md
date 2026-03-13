---
name: wizmac-development
description: Use when implementing, refactoring, or documenting code in the Wizmac repo. Helps agents choose the right module, the smallest verification loop, and the fastest fixture-backed workflow for Swift package development on macOS.
---

# Wizmac Development

Use this skill when the task is about changing the codebase, not just operating the CLI.

## Default Workflow

1. Read `../../AGENTS.md`.
2. Read `../../docs/implementation-guide.md`.
3. Build once with `swift build`.
4. Pick the smallest matching test suite before editing.
5. Prefer `WizmacFixtureHost` over live third-party apps for manual validation.

## Choose The Smallest Useful Test Loop

- `swift test --filter WizmacCoreTests` for shared models, settings, approvals, and trusted automation
- `swift test --filter WizmacControlPlaneTests` for CLI, tool registry, JSON-RPC, transports, and service routing
- `swift test --filter WizmacSystemTests` for executor behavior and macOS adapters
- `swift test --filter WizmacTextModeTests` for reducer and engine behavior
- `swift test --filter WizmacAppTests` for menu bar and fixture-support behavior

## Change Mapping

### Public tool or action changes

Touch these in order:

1. `ActionName` in `WizmacCore`
2. `ControlPlaneToolRegistry`
3. `WizmacServiceRuntime` or `MacAutomationExecutor`
4. approval defaults if the action mutates state
5. nearest tests
6. docs in `README.md` and `docs/`

### Service or transport changes

Start with:

- `../../docs/control-plane.md`
- `Sources/WizmacControlPlane/CommandRouting.swift`
- `Sources/WizmacControlPlane/ServiceControlPlane.swift`
- `Sources/WizmacControlPlane/HTTPJSONRPCServer.swift`
- `Sources/WizmacControlPlane/XPCServiceBridge.swift`

### Text-mode changes

Start with:

- `Sources/WizmacTextMode/TextModeReducer.swift`
- `Sources/WizmacTextMode/LibVimTextModeEngine.swift`
- `Sources/WizmacSystem/FocusedTextBridge.swift`
- `swift test --filter TextModeRuntimeCoordinatorTests`

## Manual Validation Strategy

- Use `swift run WizmacFixtureHost` for UI, window, scroll, and text workflows.
- Use `swift run WizmacMenuBarApp` for permission, approval, and remote-pairing UX.
- Use explicit CLI and JSON-RPC forms when touching control-plane behavior.

## Documentation Rule

If behavior changes, update the docs in the same turn:

- `../../README.md`
- `../../docs/architecture.md`
- `../../docs/implementation-guide.md`
- `../../docs/control-plane.md`
- `../../docs/operations.md`
- `../../docs/testing.md`

The repo treats docs as part of the implementation, not an afterthought.
