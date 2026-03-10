# Wizmac

Wizmac is a native macOS automation workspace that combines:

- modal text editing inspired by `SketchyVim`
- UI search, hinting, clicking, and copying inspired by `Wooshy`
- scroll-target discovery inspired by `Scrolla`
- visible-window switching inspired by `WooshyWindowToTheForeground`
- Music volume and AirPlay display controls inspired by the Alfred workflows

## Targets

- `WizmacCore`: shared models, stores, approval policy, and command bus
- `WizmacSystem`: macOS adapters for permissions, AX snapshots, windows, scroll, text, Music, and AirPlay
- `WizmacTextMode`: fallback Vim-like text engine and service API
- `WizmacControlPlane`: CLI, MCP stdio, and HTTP JSON-RPC / MCP transport pieces
- `WizmacMenuBarApp`: menu bar shell for permissions, audit, approvals, and server toggles
- `WizmacFixtureHost`: test app with representative controls and multiple windows

## Build

```bash
swift build
swift test
```

## Run

CLI:

```bash
swift run wizmac system permissions
swift run wizmac window list
swift run wizmac ui search --query button
swift run wizmac system confirmation_status
```

MCP over stdio:

```bash
swift run wizmac mcp
```

HTTP JSON-RPC server:

```bash
swift run wizmac serve --host 127.0.0.1 --port 7878
```

Shared service shell:

```bash
swift run wizmac service health
swift run wizmac service snapshot
```

Menu bar app:

```bash
swift run WizmacMenuBarApp
```

Fixture host:

```bash
swift run WizmacFixtureHost
```

## Current Status

- CLI, MCP, HTTP transport, audit logging, and approval queuing are working.
- Local clients talk to a single shared background `WizmacService` process instead of creating private runtimes.
- Permissions, UI search, click/move, scroll targeting, window focus/listing, Music volume, and AirPlay device listing are wired into the system runtime.
- The menu bar app reads live shared-service permissions, sessions, audit entries, remote clients, and pending approvals.
- Text mode is wired through a fallback engine and focused AX text contexts. It supports attach/state inspection and deterministic key processing, but it is not yet backed by `libvim`.
- Remote access currently uses bearer-token auth tied to a paired client ID. mTLS/client certificates are not wired yet.

## Data Storage

Wizmac stores runtime data in:

- `~/Library/Application Support/Wizmac/settings.json`
- `~/Library/Application Support/Wizmac/audit.jsonl`
- `~/Library/Application Support/Wizmac/pending-approvals.json`
- `~/Library/Application Support/Wizmac/remote-client-secrets.json`
- `~/Library/Application Support/Wizmac/service-state.json`

## Remote Auth Notes

- Pair a remote client first through `remote.pair` or the menu bar.
- Remote requests must send both `Authorization: Bearer <token>` and `X-Client-ID: <paired-client-uuid>`.
- Risky actions such as `remote.pair`, `remote.revoke`, clicks, copy, text writes, and AirPlay changes queue approval unless they come from trusted local origins like the menu bar.
