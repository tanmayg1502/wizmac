# Wizmac Operations

This guide covers how to run Wizmac locally, what gets persisted, how remote pairing works, and where to look when something goes wrong.

## Build And Launch

Build everything:

```bash
swift build
```

Run the service directly:

```bash
swift run WizmacService
```

Run the CLI:

```bash
swift run wizmac help
```

Run the menu bar app:

```bash
swift run WizmacMenuBarApp
```

Run the fixture app:

```bash
swift run WizmacFixtureHost
```

Run the bootstrap helper:

```bash
swift run wizmac init
```

`wizmac init` is meant to be the first-command readiness check. It should confirm that the shared service can start, report permission gaps, surface remote pairing hints when relevant, and write out a sample batch flow for the current workspace.

## Homebrew Packaging

See [docs/homebrew.md](homebrew.md) for the current packaging and release flow. The short version is:

```bash
brew tap <owner>/<tap>
brew install --cask wizmac
open /Applications/Wizmac.app
```

The cask is the main end-user install path. The formula remains available for power users who want a source-built CLI and `brew services`.

## Shared Service Lifecycle

Most local callers do not need to start the service manually.

`WizmacServiceClient` will ask `WizmacServiceProcessManager` to ensure the service is running. The process manager tries to find one of:

- `WIZMAC_SERVICE_BIN`
- `WizmacService` next to the current executable
- `.build/.../WizmacService`
- fallback `wizmac service start`

The service host then:

1. starts localhost HTTP on `127.0.0.1:7877/mcp` and `/rpc`
2. starts an anonymous XPC listener
3. writes the local transport descriptor file
4. bootstraps runtime state
5. syncs the optional remote HTTP server

When the packaged menu bar app is running, it should be the long-lived owner for permission prompts, approval UX, launch-at-login registration, and keeping the local service available.

## Permissions

The most important macOS permissions are:

- Accessibility
- Screen Recording
- Apple Events / Automation, depending on the specific action

Ways to inspect or request them:

```bash
swift run wizmac system permissions
swift run wizmac system permissions_request --permission accessibility --operation prompt
swift run wizmac system permissions_request --permission screen_recording --operation open_settings
swift run wizmac system permissions_request --permission automation_music --operation request
```

The menu bar app exposes the same flows with a friendlier operator surface.

## State Files

Wizmac persists state under:

```text
~/Library/Application Support/Wizmac/
```

Files:

| File | Purpose |
| --- | --- |
| `settings.json` | Settings, interface toggles, remote server config, action defaults, hotkeys |
| `audit.jsonl` | Append-only audit log |
| `pending-approvals.json` | Risky actions waiting for approval |
| `service-state.json` | Last persisted service health snapshot |
| `remote-identities.json` | Paired remote identities, authority record, and migrated legacy metadata |
| `remote-client-secrets.json` | Legacy bearer tokens used for migration support |
| `service-endpoint.xpc` | Local transport descriptor consumed by local clients; today it points to loopback HTTP |
| `Certificates/` | Certificate directory referenced by remote settings |

## Remote Pairing

### Pair a client

```bash
swift run wizmac remote pair --name "QA Agent"
```

That returns an enrollment bundle containing:

- client identity metadata
- client certificate PEM
- client private key PEM
- CA-like certificate PEM
- server host and port
- server certificate fingerprint

### List paired clients

```bash
swift run wizmac remote clients
```

### Revoke a client

```bash
swift run wizmac remote revoke --clientID <uuid>
```

Or use the menu bar app to pair and revoke clients interactively.

## Remote Server Modes

Remote bind behavior is controlled by `RemoteBindMode`:

- `localhost` -> binds to `127.0.0.1`
- `lan` -> binds to `0.0.0.0` but still advertises the configured host
- `custom` -> binds to the configured host directly

The CLI helper:

```bash
swift run wizmac serve --host 127.0.0.1 --port 47242
```

updates service settings and keeps the shared service running in the foreground.

If you run `swift run wizmac serve` with no flags, it behaves like foreground service start and does not automatically enable remote HTTP.

Before exposing remote HTTP, pair at least one client. With zero paired identities, the current remote listener does not enforce auth yet.

Current transport note:

- the remote listener is plain HTTP today, not HTTPS or mTLS

## Trusted Local Automation

Trusted automation is the fastest safe path for repeated local state-changing actions in one app.

Start a session:

```bash
swift run wizmac system trusted_session_start --app "WizmacFixtureHost"
```

End a session:

```bash
swift run wizmac system trusted_session_end --trustedSessionID <uuid>
```

Or let the dispatcher do it automatically on eligible local tool calls:

- explicitly with `autoTrust=true`
- or implicitly for local mutation requests that already target a specific app, PID, or window

## Local Transport Reality Check

Two local-transport facts can look contradictory if you only read health output:

- actual local client discovery uses the `service-endpoint.xpc` descriptor, which currently points to `http://127.0.0.1:7877/rpc`
- the MCP-facing localhost endpoint for agent tools is `http://127.0.0.1:7877/mcp`
- some service-health fields still report `xpc://wizmac/service` as the local control-plane URL

When in doubt, trust the transport descriptor and real listener behavior.

## Approvals

Inspect pending approvals:

```bash
swift run wizmac system confirmation_status
```

Resolve one:

```bash
swift run wizmac system confirmation_resolve --approvalID <uuid> --decision approve
```

The menu bar app is the intended human-facing approval UI.

## Fixture Operations

Use `WizmacFixtureHost` before validating behavior against real apps. It gives you:

- a main window with text fields, text editor, table, hierarchy buttons, popover, and modal surfaces
- secondary and duplicate secondary windows for focus/list tests
- an inspector window
- AppKit text controls and a WebKit editable region

This is the safest place to validate:

- `ui.search`
- `window.list`
- `window.focus`
- `text.attach`
- `text.send_keys`
- `scroll.*`

## Benchmarking

The repo includes a latency benchmark script:

```bash
scripts/benchmark_wizmac_latency.sh
```

Useful environment variables:

- `WIZMAC_BIN`
- `WIZMAC_BENCH_QUERY`
- `WIZMAC_BENCH_APP`
- `WIZMAC_BENCH_TARGET_ID`
- `WIZMAC_BENCH_TEXT`
- `WIZMAC_BENCH_ITERATIONS`

## Troubleshooting

### The CLI says the service cannot be started

Check:

- `swift build` succeeded
- `.build/.../WizmacService` or `.build/.../wizmac` exists
- `WIZMAC_SERVICE_BIN` is not pointing at a stale binary

### Search or click returns permission errors

Check:

- Accessibility permission is granted
- Screen Recording is granted when richer inspection is needed
- the target app is frontmost or explicitly addressed by `app` or `pid`

### Remote requests are rejected

Check:

- remote HTTP is enabled
- the client is paired
- `X-Client-ID` matches a paired client
- the signature header is correct, or the client is using a migrated legacy token

### Remote listener seems reachable without credentials

Check whether remote HTTP was enabled before any identities were paired. In the current implementation, that path is effectively unauthenticated and should only be used for local development.

### The menu bar app looks empty

That usually means the shared service snapshot could not be loaded. Check `swift run wizmac service health` and the service status shown in the menu bar.

### Text mode behaves differently than expected

Remember that the current `libvim` path is still backed by an embedded shim and reducer logic. If behavior looks off, validate both `WizmacTextModeTests` and `TextModeRuntimeCoordinatorTests`.
