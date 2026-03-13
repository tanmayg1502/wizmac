# Wizmac Testing Guide

Wizmac uses a mix of unit tests, contract-style tests, fixture-backed transport tests, and manual validation through the fixture app and menu bar app.

## Test Targets

| Target | Focus |
| --- | --- |
| `WizmacCoreTests` | Settings, stores, command bus, and approval/trusted-session logic |
| `WizmacControlPlaneTests` | Tool registry, dispatcher, JSON-RPC behavior, transport/source rules, service bridge behavior |
| `WizmacSystemTests` | Executor contracts for UI, scroll, text, permissions, and runtime coordination |
| `WizmacTextModeTests` | Reducer and engine behavior |
| `WizmacAppTests` | Menu bar and fixture-support behavior |

Most test targets use `XCTest`, while the text-mode target also uses the newer `Testing` package.

## Default Commands

Run everything:

```bash
swift test
```

Run one suite:

```bash
swift test --filter WizmacControlPlaneTests
```

Run one focused test:

```bash
swift test --filter ControlPlaneTests/testDispatcherAutoTrustStartsTrustedSessionForAllowedLocalTool
```

## What Each Key Test Gives You

### `ControlPlaneTests`

Good first stop for:

- tool registration and naming
- JSON-RPC encode/decode
- source/origin behavior
- auto-trust dispatch rules
- local vs remote source semantics

### `CLITimingTests`

These tests validate:

- the built CLI binary can be launched end to end
- explicit `call` syntax
- namespaced CLI syntax
- JSON-RPC CLI syntax
- latency sampling through a fixture-backed control plane

These tests do not require real UI automation because they inject a fixture router through the `WIZMAC_CONTROL_PLANE_FIXTURE` environment variable.

### `ExecutorContractTests`

Use these as the fastest signal for:

- UI hints and search payload contracts
- drag behavior
- scroll-session statefulness
- text attach/status/detach behavior
- key coalescing and post-state behavior
- not-found app behavior

### `TextModeRuntimeCoordinatorTests`

Use these when touching:

- global input capture coordination
- secure-input bypass behavior
- manual bypass toggling
- libvim-backed runtime coordination

### `MenuBarViewModelTests`

Use these when changing:

- backend snapshot loading
- control-plane toggles
- permission onboarding behavior
- trusted automation controls
- remote pair and revoke presentation

## Fixture-Backed Validation

`WizmacFixtureHost` is the main manual validation surface.

Run it with:

```bash
swift run WizmacFixtureHost
```

Useful queries against the fixture app:

```bash
swift run wizmac ui search --query Primary
swift run wizmac ui search --query Inspector
swift run wizmac window list
```

The fixture app is useful because it has:

- consistent button titles
- multiple windows
- nested hierarchy items
- AppKit and WebKit editing surfaces
- tables, alerts, popovers, and sheets

## Persistence Safety In Tests

The test suite generally redirects persistence into temporary directories instead of using the real `~/Library/Application Support/Wizmac` state. That makes the checked-in tests safe to run locally without polluting your main runtime data.

## Fixture Router For Cheap Transport Tests

The control plane can be swapped with a fixture router by setting `WIZMAC_CONTROL_PLANE_FIXTURE` to a JSON-encoded `FixtureControlPlaneEnvironmentConfiguration`.

That is how `CLITimingTests` validates the real CLI without depending on real macOS side effects.

Use that pattern when you need to:

- validate CLI or JSON-RPC plumbing
- measure latency without hitting live UI automation
- create deterministic transport-level tests

## Benchmark Script

The repo includes:

```bash
scripts/benchmark_wizmac_latency.sh
```

Typical use:

```bash
swift build
scripts/benchmark_wizmac_latency.sh
```

If you want act timings too, provide a target:

```bash
WIZMAC_BENCH_TARGET_ID=button-1 scripts/benchmark_wizmac_latency.sh
```

## Suggested Validation Matrix

### If you changed public tool schemas or dispatch behavior

- `swift test --filter WizmacControlPlaneTests`
- a manual CLI smoke test with `swift run wizmac`

### If you changed executor behavior

- `swift test --filter WizmacSystemTests`
- fixture-host manual validation

### If you changed text-mode behavior

- `swift test --filter WizmacTextModeTests`
- `swift test --filter TextModeRuntimeCoordinatorTests`
- manual validation in fixture text fields or editors

### If you changed menu bar behavior

- `swift test --filter WizmacAppTests`
- manual `swift run WizmacMenuBarApp`

## Testing Philosophy

The project tries to keep fast, local, deterministic validation paths for most changes:

- pure models and policy in `WizmacCoreTests`
- transport and control-plane behavior in `WizmacControlPlaneTests`
- contract-style executor tests with stubs in `WizmacSystemTests`
- real manual UI validation against `WizmacFixtureHost`

When adding features, prefer extending an existing fast loop before introducing a new slow or flaky path.
