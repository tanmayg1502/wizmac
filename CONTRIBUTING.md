# Contributing To Wizmac

This guide is for both human contributors and coding agents. The goal is to make changes predictable, fast to validate, and easy to extend without accidentally bypassing the shared-service architecture.

## Prerequisites

- macOS 13+
- Xcode 16+ or modern Apple Command Line Tools
- Swift 6.2 toolchain support
- Accessibility permission when validating real automation
- Screen Recording permission when validating capture or richer inspection flows

## Setup

Build and run the tests once before deeper work:

```bash
swift build
swift test
```

Useful app entry points:

```bash
swift run WizmacFixtureHost
swift run WizmacMenuBarApp
swift run WizmacService
swift run wizmac help
```

## Development Loops

### 1. Shared models and policy work

Use this loop when touching settings, approval rules, stores, action models, or trusted automation:

```bash
swift test --filter WizmacCoreTests
```

Relevant code:

- `Sources/WizmacCore/Models.swift`
- `Sources/WizmacCore/Approval.swift`
- `Sources/WizmacCore/CommandBus.swift`
- `Sources/WizmacCore/Stores.swift`
- `Sources/WizmacCore/TrustedAutomation.swift`

### 2. Control-plane and transport work

Use this loop when changing CLI behavior, tool schemas, source/origin rules, JSON-RPC, MCP, service lifecycle, remote pairing, or HTTP/XPC transport behavior:

```bash
swift test --filter WizmacControlPlaneTests
```

Relevant code:

- `Sources/WizmacCLI/main.swift`
- `Sources/WizmacControlPlane/ToolRegistry.swift`
- `Sources/WizmacControlPlane/CommandRouting.swift`
- `Sources/WizmacControlPlane/ServiceControlPlane.swift`
- `Sources/WizmacControlPlane/HTTPJSONRPCServer.swift`
- `Sources/WizmacControlPlane/XPCServiceBridge.swift`

### 3. macOS executor work

Use this loop when changing UI search, clicking, copy, scroll, window focus, permissions, AirPlay, Music, or the focused-text bridge:

```bash
swift test --filter WizmacSystemTests
```

Relevant code:

- `Sources/WizmacSystem/SystemExecutor.swift`
- `Sources/WizmacSystem/AccessibilitySnapshotter.swift`
- `Sources/WizmacSystem/FocusedTextBridge.swift`
- `Sources/WizmacSystem/ScrollController.swift`
- `Sources/WizmacSystem/WindowController.swift`

### 4. Text-mode work

Use this loop when changing the reducer, key translation, shim behavior, or runtime capture coordination:

```bash
swift test --filter WizmacTextModeTests
swift test --filter TextModeRuntimeCoordinatorTests
```

Relevant code:

- `Sources/WizmacTextMode/TextModeReducer.swift`
- `Sources/WizmacTextMode/LibVimTextModeEngine.swift`
- `Sources/WizmacTextMode/FallbackTextModeEngine.swift`
- `Sources/WizmacSystem/TextModeRuntimeCoordinator.swift`

### 5. Menu bar or fixture work

Use this loop when editing SwiftUI app surfaces or fixture support models:

```bash
swift test --filter WizmacAppTests
```

Relevant code:

- `Sources/WizmacMenuBarApp/`
- `Sources/WizmacFixtureHost/`
- `Sources/WizmacFixtureHostSupport/`

## Manual Validation

### Fixture-first validation

Prefer the fixture app before live-system validation:

```bash
swift run WizmacFixtureHost
swift run wizmac ui search --query Primary
swift run wizmac window list
```

The fixture host is intentionally built to exercise:

- multiple windows
- nested buttons and hierarchy lists
- tables and selection
- sheets, alerts, and popovers
- AppKit text fields and text views
- a WebKit editable surface

### Menu bar validation

Use `WizmacMenuBarApp` when validating:

- permission onboarding flows
- service toggles
- pending approval resolution
- trusted automation sessions
- remote pairing and revoke flows

### CLI and transport validation

Use the explicit CLI forms when changing the control plane:

```bash
swift run wizmac call ui.search query=Primary
swift run wizmac ui search --query Primary
swift run wizmac json '{"jsonrpc":"2.0","id":"1","method":"tools/list"}'
swift run wizmac mcp
```

## Documentation Expectations

If your change affects behavior, update the docs in the same branch:

- `README.md` for public entry points or common workflows
- `docs/control-plane.md` for command/transport changes
- `docs/architecture.md` for architectural shifts
- `docs/implementation-guide.md` for extension points or change recipes
- `docs/operations.md` for persistence, permissions, or remote behavior
- `docs/testing.md` for new validation paths

## Design Principles To Preserve

- Prefer the shared service over per-client runtimes.
- Keep the public action surface centered on `ActionName` and `ControlPlaneToolRegistry`.
- Keep approval and audit behavior explicit and testable.
- Treat remote callers as remote origins even when they try to embed local-looking metadata.
- Preserve deterministic validation paths through fixture-backed tests when possible.

## Before You Finish

Use the smallest checklist that matches your change:

- Did you update or add the nearest tests?
- Did you keep docs aligned with behavior?
- Did you avoid breaking the shared-service flow?
- Did you check whether the action should be risky, auto-approved, or trusted-session eligible?
- Did you leave enough breadcrumbs for the next contributor in code comments or docs?
