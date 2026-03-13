---
name: wizmac-fixture-lab
description: Use when a task needs deterministic macOS UI validation against the Wizmac fixture app. Best for exercising search, hints, click, drag, window focus, text mode, and multi-window flows without relying on third-party apps.
---

# Wizmac Fixture Lab

Use this skill when the safest validation target is the built-in fixture app.

## Why Use The Fixture

`WizmacFixtureHost` gives you a repeatable UI surface with:

- a main window containing searchable buttons and text controls
- AppKit text field and text view fixtures
- a WebKit editable surface
- tables and hierarchy rows
- popovers, sheets, and alerts
- secondary, duplicate-secondary, and inspector windows

This is the preferred manual validation target for automation changes.

## Basic Loop

1. Build with `swift build`.
2. Launch the fixture app:

```bash
swift run WizmacFixtureHost
```

3. Use the CLI to inspect and act:

```bash
swift run wizmac ui search --query Primary
swift run wizmac window list
swift run wizmac ui search --query Inspector
```

## Good Queries To Start With

- `Primary`
- `Open Secondary Window`
- `Open Inspector Window`
- `Search`
- `NSTextField`
- `NSTextView`

## Best Uses

- validating `ui.search`, `ui.hints`, `ui.capture`, `ui.act`, and `ui.drag`
- testing `window.list` and `window.focus`
- checking `text.attach`, `text.insert`, and `text.send_keys`
- verifying approval and trusted-session flows against a low-risk app

## When To Read More

- Read `../../docs/testing.md` for the broader validation strategy.
- Read `../../docs/operations.md` for service and CLI setup.
