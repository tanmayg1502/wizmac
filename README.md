# Wizmac

Wizmac is a native macOS automation workspace and control plane for humans and agents. It combines:

- accessibility-tree search, hinting, capture, clicking, dragging, and copy flows
- window discovery and focus management
- modal text editing backed by a Vim-like text engine
- Apple Music volume and AirPlay display control
- approval, audit, and trusted-session safety rails
- local and remote control-plane access over CLI, MCP stdio, localhost HTTP, and paired remote HTTP

The project is packaged as a Swift monorepo with a long-lived shared service (`WizmacService`), a command-line client (`wizmac`), a menu bar app for permissions and approvals, and a fixture app for deterministic UI testing.

## Why This Repo Exists

Wizmac is trying to make macOS automation feel like a first-class workspace instead of a loose collection of scripts. The design centers on one shared service that owns:

- stateful sessions for UI, hints, scroll, text mode, and trusted automation
- audit logging and approval queues
- remote pairing and identity management
- a single system executor that knows how to talk to macOS APIs

That lets local humans, local agents, and paired remote agents all hit the same surface area without each caller re-creating its own runtime.

## Repository Map

| Target | Responsibility |
| --- | --- |
| `WizmacCore` | Shared models, settings, stores, approval policy, trusted automation, and the command bus |
| `WizmacSystem` | macOS adapters for AX snapshots, text bridging, windows, scrolling, permissions, media, and pointer automation |
| `WizmacTextMode` | Vim-like text engine, reducer, runtime coordinator, and libvim shim/fallback implementations |
| `WizmacControlPlane` | Tool registry, JSON-RPC/MCP handling, HTTP/XPC transports, shared-service host/client, and remote identity logic |
| `WizmacCLI` | `wizmac` executable for namespaced commands, direct tool calls, JSON-RPC, MCP, and service helpers |
| `WizmacService` | Long-lived background process that hosts the shared runtime |
| `WizmacMenuBarApp` | SwiftUI menu bar shell for onboarding, approvals, sessions, and remote client management |
| `WizmacFixtureHost` | Multi-window fixture app with representative controls for manual and automated testing |
| `WizmacFixtureHostSupport` | Shared fixture store/models used by the fixture app and app tests |

## Quick Start

### Prerequisites

- macOS 13 or newer
- Xcode 16 or newer, or current Apple Command Line Tools with Swift 6.2 support
- Accessibility permission for active automation work
- Screen Recording permission for richer inspection/capture workflows

### Build And Test

```bash
swift build
swift test
```

### Run The Main Surfaces

Build once, then use the fast path that matches your task:

```bash
swift run wizmac help
swift run wizmac service health
swift run WizmacMenuBarApp
swift run WizmacFixtureHost
```

### Common CLI Workflows

Inspect permissions:

```bash
swift run wizmac system permissions
```

Search the frontmost app's accessibility tree:

```bash
swift run wizmac ui search --query Primary
```

Call the same tool through explicit tool syntax:

```bash
swift run wizmac call ui.search query=Primary
```

List windows:

```bash
swift run wizmac window list
```

Inspect service state:

```bash
swift run wizmac service snapshot
```

Run the MCP server on stdio:

```bash
swift run wizmac mcp
```

`wizmac mcp` currently speaks newline-delimited JSON-RPC over stdio.

Start the shared service with remote HTTP enabled:

```bash
swift run wizmac serve --host 127.0.0.1 --port 47242
```

Pair at least one remote client before exposing that listener. If remote HTTP is enabled with no paired identities, the current server behavior does not enforce remote authentication yet.

Pair a remote client:

```bash
swift run wizmac remote pair --name "QA Agent"
```

## How The System Fits Together

1. `wizmac`, the menu bar app, and tests all talk to the same control-plane model.
2. Local callers usually go through `WizmacServiceClient`, which auto-starts `WizmacService` if needed.
3. `WizmacServiceHost` exposes a localhost HTTP JSON-RPC endpoint plus an anonymous XPC listener for in-process or local clients.
4. `WizmacServiceRuntime` owns service state, approval queues, remote identities, and session snapshots.
5. Service-owned actions are handled directly in the runtime; the rest flow through `CommandBus` into `MacAutomationExecutor`.
6. `MacAutomationExecutor` is the macOS edge: AX snapshots, text bridges, pointer actions, scrolling, windows, media, and AirPlay.

For the full design, see [docs/architecture.md](docs/architecture.md).

## Data And Runtime State

Wizmac persists runtime state under `~/Library/Application Support/Wizmac/`:

- `settings.json`
- `audit.jsonl`
- `pending-approvals.json`
- `remote-identities.json`
- `remote-client-secrets.json` for legacy bearer-token migration state
- `service-state.json`
- `service-endpoint.xpc`
- `Certificates/`

The meaning of each file and the operational caveats are documented in [docs/operations.md](docs/operations.md).

## Documentation Index

### Start Here

- [AGENTS.md](AGENTS.md): shortest repo map for coding agents
- [CONTRIBUTING.md](CONTRIBUTING.md): setup, dev loops, testing, and change expectations
- [docs/README.md](docs/README.md): index of the deeper technical docs

### Deep Dives

- [docs/architecture.md](docs/architecture.md): system design, runtime topology, and trust model
- [docs/implementation-guide.md](docs/implementation-guide.md): module-by-module change guide and extension recipes
- [docs/control-plane.md](docs/control-plane.md): CLI, JSON-RPC, MCP, service methods, transports, and request semantics
- [docs/operations.md](docs/operations.md): service lifecycle, permissions, persistence, remote pairing, and troubleshooting
- [docs/testing.md](docs/testing.md): test suites, fixture-host workflows, and latency benchmarks

### Repo-Local Skills For Agents

- [skills/wizmac-cli/SKILL.md](skills/wizmac-cli/SKILL.md): fastest path for using the CLI and control plane
- [skills/wizmac-development/SKILL.md](skills/wizmac-development/SKILL.md): efficient contribution workflow for this codebase
- [skills/wizmac-fixture-lab/SKILL.md](skills/wizmac-fixture-lab/SKILL.md): how to use the fixture app for deterministic validation

## Current Status And Limits

- The shared-service architecture, audit flow, approval queue, CLI, MCP, and HTTP transports are in place.
- Remote access supports paired identities with signature verification and a legacy bearer-token migration path.
- Text mode is wired end to end, but the current `libvim` integration is still an embedded shim rather than a full native libvim backend.
- The codebase is intentionally macOS-specific and leans on AppKit, AX APIs, and Network framework transports.

If you are landing here to make changes, start with [AGENTS.md](AGENTS.md) and [docs/implementation-guide.md](docs/implementation-guide.md).
