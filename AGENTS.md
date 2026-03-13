# AGENTS.md

This file is the shortest accurate map for an agent landing in the `wizmac` repo.

## Mission

Wizmac is a shared macOS automation service. The codebase exists to let local and remote callers hit one control plane for UI automation, text mode, window control, scroll sessions, permissions, approvals, and remote pairing.

The most important architectural fact is this:

- local callers should normally talk to the shared service, not spin up their own private runtime

That pattern shows up throughout `WizmacControlPlane`, the CLI, the menu bar app, and tests.

## First Five Minutes

1. Read [README.md](README.md) for the repo overview.
2. Read [docs/implementation-guide.md](docs/implementation-guide.md) if you will be changing code.
3. Build once with `swift build`.
4. Prefer targeted tests over full-suite reruns while iterating.
5. Use `WizmacFixtureHost` when you need a stable UI surface for search, window, scroll, and text-mode work.

## Fast Commands

Build:

```bash
swift build
```

Full test suite:

```bash
swift test
```

Common targeted suites:

```bash
swift test --filter WizmacCoreTests
swift test --filter WizmacControlPlaneTests
swift test --filter WizmacSystemTests
swift test --filter WizmacTextModeTests
swift test --filter WizmacAppTests
```

Run the main apps:

```bash
swift run WizmacFixtureHost
swift run WizmacMenuBarApp
swift run WizmacService
```

Use the CLI:

```bash
swift run wizmac help
swift run wizmac service health
swift run wizmac ui search --query Primary
swift run wizmac call ui.search query=Primary
swift run wizmac mcp
```

Latency benchmark:

```bash
scripts/benchmark_wizmac_latency.sh
```

## Cheapest Validation By Change Area

| Change area | Usually enough to run first |
| --- | --- |
| Shared models, settings, approval logic | `swift test --filter WizmacCoreTests` |
| Tool registry, dispatcher, source translation, service client/host | `swift test --filter WizmacControlPlaneTests` |
| AX, window, scroll, permissions, text bridging | `swift test --filter WizmacSystemTests` |
| Reducer or text-engine behavior | `swift test --filter WizmacTextModeTests` |
| Menu bar UI or fixture support models | `swift test --filter WizmacAppTests` |
| CLI latency or fixture-backed transport behavior | `swift test --filter CLITimingTests` |

If a change crosses module boundaries, move outward from the smallest relevant suite.

## High-Signal Source Files

| File | Why it matters |
| --- | --- |
| `Sources/WizmacCore/Models.swift` | Canonical action names, settings defaults, risky vs auto-approved actions |
| `Sources/WizmacCore/Approval.swift` | Approval gating rules |
| `Sources/WizmacCore/CommandBus.swift` | Audit + approval orchestration around executor calls |
| `Sources/WizmacControlPlane/ToolRegistry.swift` | Public tool surface and schemas |
| `Sources/WizmacControlPlane/CommandRouting.swift` | JSON-RPC handling, MCP/resource methods, fixture router hook |
| `Sources/WizmacControlPlane/ServiceControlPlane.swift` | Shared runtime, service host/client/process manager, session tracking |
| `Sources/WizmacControlPlane/HTTPJSONRPCServer.swift` | Local and remote HTTP transport plus remote auth checks |
| `Sources/WizmacSystem/SystemExecutor.swift` | macOS action dispatch entry point |
| `Sources/WizmacTextMode/TextModeService.swift` | Engine facade used by runtime code |
| `Sources/WizmacMenuBarApp/LiveMenuBarBackend.swift` | Menu bar integration with the shared service |
| `Sources/WizmacFixtureHost/FixtureContentView.swift` | Stable manual/automated test surface |

## How To Add Or Change Features

Adding a new tool usually means touching all of these layers:

1. Add the new `ActionName` or supporting model in `WizmacCore`.
2. Expose it in `ControlPlaneToolRegistry`.
3. Route it through `SystemExecutor` or `WizmacServiceRuntime`.
4. Update approval defaults if it mutates state.
5. Add or update tests in the nearest target.
6. Update the docs in `README.md` and `docs/`.

If the feature is service-owned state, it probably belongs in `WizmacServiceRuntime` instead of `MacAutomationExecutor`.

## Behavioral Caveats

- Approval policy exempts menu bar, hotkey, and test origins by default.
- `autoTrust=true` on eligible local tool calls can trigger `system.trusted_session_start` automatically through `ControlPlaneDispatcher`.
- Remote HTTP requests are intentionally treated as remote origins even if they try to spoof a local source in the JSON-RPC body.
- Do not expose remote HTTP before pairing at least one client. With no configured remote identities, the current remote listener does not enforce auth yet.
- The current text-mode backend is wired through `LibVimTextModeEngine`, but the implementation still uses an embedded shim around the reducer.
- The service publishes a local transport descriptor file and also serves localhost HTTP on port `7877`.
- Some health/status surfaces still report `xpc://wizmac/service` even though production local discovery is actually the localhost HTTP descriptor.

## Fixture And Benchmark Notes

- `WizmacFixtureHost` is the preferred manual target for UI search, hints, click, scroll, and text-mode tests.
- The fixture app includes SwiftUI controls, AppKit-backed text controls, a WebKit editable surface, multiple windows, alerts, sheets, popovers, and tables.
- `CLITimingTests` and `ControlPlaneEnvironment.fixtureEnvironmentKey` provide a cheap way to validate CLI and transport behavior without real macOS automation side effects.

## Repo-Local Skills

If your environment supports repo-local skills, use:

- [skills/wizmac-cli/SKILL.md](skills/wizmac-cli/SKILL.md)
- [skills/wizmac-development/SKILL.md](skills/wizmac-development/SKILL.md)
- [skills/wizmac-fixture-lab/SKILL.md](skills/wizmac-fixture-lab/SKILL.md)

They are written to complement this repo's docs rather than duplicate them.
