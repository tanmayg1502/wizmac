---
name: wizmac-cli
description: Use when operating or validating the Wizmac control plane from the repo via the CLI, JSON-RPC, MCP stdio, or shared service. Best for efficient command execution, approval-aware automation, and local/remote service checks.
---

# Wizmac CLI

Use this skill when the task is primarily about running Wizmac itself rather than changing the implementation.

## Quick Start

1. Build once with `swift build`.
2. Use `swift run wizmac ...` until you know the task will involve many repeated invocations.
3. For repeated CLI loops, prefer the built binary under `.build/.../wizmac` if it exists.
4. If the task needs a predictable UI target, launch `swift run WizmacFixtureHost` first.

## Best Command Forms

Use the simplest surface that proves the behavior you need:

- Human-readable tool calls: `swift run wizmac ui search --query Primary`
- Exact tool identity: `swift run wizmac call ui.search query=Primary`
- JSON-RPC plumbing: `swift run wizmac json '{"jsonrpc":"2.0","id":"1","method":"tools/list"}'`
- MCP interoperability: `swift run wizmac mcp` for newline-delimited JSON-RPC over stdio
- Shared-service inspection: `swift run wizmac service health` or `swift run wizmac service snapshot`

## Efficient Workflow

### Read-only inspection

Start with:

```bash
swift run wizmac system permissions
swift run wizmac service health
swift run wizmac service snapshot
swift run wizmac window list
```

### UI targeting

For deterministic local validation, use the fixture app and search first:

```bash
swift run WizmacFixtureHost
swift run wizmac ui search --query Primary
```

Once you have a target, move to `ui.act`, `ui.copy`, or `ui.execute`.

### Transport validation

Use:

```bash
swift run wizmac call ui.search query=Primary
swift run wizmac json '{"jsonrpc":"2.0","id":"1","method":"tools/list"}'
swift run wizmac mcp
```

### Remote validation

Use:

```bash
swift run wizmac remote clients
swift run wizmac remote pair --name "QA Agent"
swift run wizmac serve --host 127.0.0.1 --port 47242
```

Do not expose remote HTTP before pairing at least one client. In the current implementation, remote auth is skipped when the allowed-identity list is empty.

## Approval And Trust Notes

- Risky actions can queue approvals instead of executing immediately.
- For repeated local state-changing actions in one app, use `autoTrust=true` or start a trusted session explicitly.
- Menu bar and test origins bypass approvals; CLI and MCP do not, unless the action is auto-approved or covered by a trusted session.

Explicit trusted-session example:

```bash
swift run wizmac system trusted_session_start --app "WizmacFixtureHost"
```

## When To Read More

- Read `../../docs/control-plane.md` for request shapes, tool families, and transport semantics.
- Read `../../docs/operations.md` for permissions, pairing, persistence, and troubleshooting.
- Read `../../docs/testing.md` if the task is really about validation rather than operation.
