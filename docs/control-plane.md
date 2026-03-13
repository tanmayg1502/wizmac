# Wizmac Control Plane

This document describes the public command surface exposed by Wizmac and the transport behavior behind it.

## Surfaces

Wizmac exposes the same logical tool surface through several front doors:

- `wizmac` namespaced CLI commands
- `wizmac call <tool.name>`
- `wizmac json '<json-rpc request>'`
- `wizmac mcp` for newline-delimited JSON-RPC over stdio
- localhost HTTP JSON-RPC served by the shared service
- optional paired remote HTTP JSON-RPC

The source of truth for the tool inventory is `ControlPlaneToolRegistry`.

## CLI Forms

### Namespaced syntax

Format:

```bash
swift run wizmac <namespace> <action> [--key value|key=value ...]
```

Examples:

```bash
swift run wizmac system permissions
swift run wizmac ui search --query Primary
swift run wizmac remote pair --name "QA Agent"
```

### Explicit tool-call syntax

Format:

```bash
swift run wizmac call <tool.name> [--key value|key=value ...]
```

Examples:

```bash
swift run wizmac call ui.search query=Primary
swift run wizmac call window.focus title="Fixture Host"
```

### Inline JSON-RPC

Format:

```bash
swift run wizmac json '<json-rpc request>'
```

Example:

```bash
swift run wizmac json '{"jsonrpc":"2.0","id":"1","method":"tools/list"}'
```

### Service helper commands

Format:

```bash
swift run wizmac service [start|health|snapshot|settings]
```

Notes:

- `start` boots the shared service and waits
- `health`, `snapshot`, and `settings` talk to the long-lived service client

### HTTP bootstrap helper

Format:

```bash
swift run wizmac serve [--host 127.0.0.1|0.0.0.0|custom] [--port 47242] [--path /rpc]
```

With no flags, this behaves like foreground service start. When host or port flags are supplied, it also applies a remote-server settings patch so remote HTTP is enabled.

Current limitation:

- the CLI bootstrap helper only accepts `/rpc`

## JSON-RPC Methods

`ControlPlaneDispatcher.handleJSONRPC` currently supports:

- `initialize`
- `notifications/initialized`
- `ping`
- `tools/list`
- `tools/call`
- `resources/list`
- `resources/read`
- `wizmac/health`
- `service.health`
- `wizmac/snapshot`
- `service.snapshot`
- `service.settings.get`
- `wizmac/settings/update`
- `service.settings.update`

Current note:

- `initialize` advertises tool capability metadata, but not resource capability metadata, even though `resources/list` and `resources/read` are implemented

## Resource URIs

The service exposes these resource URIs:

- `wizmac://permissions`
- `wizmac://audit`
- `wizmac://approvals`
- `wizmac://sessions`
- `wizmac://health`

These are useful for MCP-style clients that want current state without inventing custom tool calls.

## Tool Families

### UI

- `ui.apps`
- `ui.search`
- `ui.act`
- `ui.copy`
- `ui.capture`
- `ui.prefetch`
- `ui.execute`
- `ui.hints`
- `ui.drag`
- `ui.session_end`

### Scroll

- `scroll.targets`
- `scroll.focus`
- `scroll.step`
- `scroll.session_start`
- `scroll.session_end`

### Window

- `window.list`
- `window.focus`
- `window.exclude`

### Text

- `text.attach`
- `text.detach`
- `text.insert`
- `text.send_keys`
- `text.mode`
- `text.status`

### Media / Display

- `media.music_volume`
- `display.airplay_devices`
- `display.airplay_connect`
- `display.airplay_disconnect`

### System / Service

- `system.permissions`
- `system.permissions_request`
- `system.audit`
- `system.health`
- `system.sessions`
- `system.confirmation_status`
- `system.confirmation_resolve`
- `system.trusted_session_start`
- `system.trusted_session_end`

### Remote

- `remote.clients`
- `remote.pair`
- `remote.revoke`

## Common Argument Conventions

Many tools share a common set of routing and execution arguments:

- `pid` or `app` to target a specific application
- `launchIfNeeded` and `activate` for app activation behavior
- `sessionID` and `snapshotID` for stateful UI flows
- `targetID` to resolve a previously captured UI element exactly
- `scope` and `includeMenus` for accessibility-tree breadth
- `debugTimings` for instrumentation
- `autoTrust` and `trustedSessionID` for trusted local automation

`system.permissions_request` currently recognizes:

- `permission = accessibility | screen_recording | automation_music`
- `operation = prompt | request | open_settings`

## Source And Origin Semantics

Wizmac tracks where a request came from because approval and trust behavior depend on it.

Transport-level `ControlPlaneSourceKind` values:

- `cli`
- `mcp`
- `http`
- `automation`
- `menuBar`

Core-level `RequestOriginKind` values:

- `cli`
- `mcp`
- `remote`
- `menuBar`
- `hotkey`
- `test`

Important rule:

- authenticated remote HTTP requests become core `remote` origins, even if the embedded JSON-RPC body tries to present itself as a local source

## Auto-Trust Behavior

`ControlPlaneDispatcher` can transparently start a trusted local automation session before an eligible request.

This only happens when:

- `autoTrust=true`
- `trustedSessionID` is not already present
- the source is local (`cli`, `mcp`, or `menuBar`)
- the action is in `TrustedAutomationPolicy.defaultAllowedActions`

If the trusted-session bootstrap succeeds, the dispatcher injects the new `trustedSessionID` into the original request.

## Local Transport Behavior

### Service discovery

The shared service writes a local transport descriptor to:

```text
~/Library/Application Support/Wizmac/service-endpoint.xpc
```

That descriptor currently points local clients at the localhost HTTP server on port `7877`.

Operational note:

- some health/status APIs still report `xpc://wizmac/service`, but production local discovery currently uses this HTTP descriptor

### Local HTTP server

The shared service always hosts an unauthenticated local HTTP JSON-RPC endpoint on:

```text
http://127.0.0.1:7877/rpc
```

Because this local surface is trusted, forwarded source headers can be honored.

The HTTP server also accepts `/mcp` as an alias path for JSON-RPC traffic.

### Anonymous XPC

`WizmacServiceHost` also starts an anonymous XPC listener for in-process and test-oriented communication.

## Remote HTTP Behavior

The optional remote server is configured from `settings.remoteServer` and normally advertises:

```text
http://<host>:<port>/rpc
```

This is plain HTTP today, not HTTPS or mTLS.

Default values:

- host: `127.0.0.1`
- port: `47242`
- path: `/rpc`

When remote identities are configured:

- requests must include `X-Client-ID`
- signature verification is preferred through `X-Wizmac-Signature`
- a legacy bearer-token path still exists for migrated clients

Security note:

- if remote HTTP is enabled before any client is paired, the current code path skips remote auth entirely; do not expose that listener outside local development

## Approval Semantics

Risky actions do not fail silently. They return a confirmation-needed response with:

- `status = confirmationRequired`
- an approval ID in the payload
- an audit record saying the action was queued

Resolution paths:

```bash
swift run wizmac system confirmation_status
swift run wizmac system confirmation_resolve --approvalID <uuid> --decision approve
```

The menu bar app also resolves approvals through the shared service client.

## Useful Request Examples

### List tools over JSON-RPC

```json
{
  "jsonrpc": "2.0",
  "id": "tools",
  "method": "tools/list"
}
```

### Call `ui.search`

```json
{
  "jsonrpc": "2.0",
  "id": "search-1",
  "method": "tools/call",
  "params": {
    "name": "ui.search",
    "arguments": {
      "query": "Primary",
      "debugTimings": true
    }
  }
}
```

For exact reuse of a previously captured target, prefer:

```json
{
  "jsonrpc": "2.0",
  "id": "search-by-id",
  "method": "tools/call",
  "params": {
    "name": "ui.search",
    "arguments": {
      "targetID": "<captured target id>",
      "sessionID": "<optional ui session id>",
      "snapshotID": "<optional snapshot id>"
    }
  }
}
```

### Read service snapshot

```json
{
  "jsonrpc": "2.0",
  "id": "snapshot",
  "method": "service.snapshot"
}
```

## When To Read Other Docs

- Read [operations.md](operations.md) for service lifecycle, permissions, data files, and pairing workflows.
- Read [implementation-guide.md](implementation-guide.md) when you need to add or change a tool.
- Read [testing.md](testing.md) for fixture-backed CLI testing and transport benchmarks.
