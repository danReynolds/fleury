# Fleury Demo-App Scenario

**Status:** M0.1 scenario spec  
**Working package:** `packages/fleury_example_console`  
**Current-cycle role:** First realistic demo surface for Fleury core.  
**Later product role:** Dune/`dune_cli` follows after this example proves the
framework foundations.

## Purpose

The demo app should make Fleury prove the framework qualities that would cause
a serious TUI developer to choose it: Flutter-like retained UI in Dart,
app-scale command/action/screen structure, strong text input, terminal
correctness, inspectable semantics, data-heavy widgets, and testable behavior.

This is not a marketing demo. It is a pressure harness. If the example is easy
to build, test, and keep responsive, the framework is moving in the right
direction. If it is awkward, that awkwardness should feed Phase 1 API work.

## Scenario: Developer Operations Console

Build a self-contained developer operations console backed by local fake data
and deterministic streams. The app should feel like a real tool for inspecting
tasks, logs, data, and command output without depending on Dune, ACP, network
services, or external processes.

The user can:

- Move between screens from a left sidebar.
- Open a command palette and run app commands.
- Type commands or notes into a composer.
- Watch streamed output arrive in a transcript/log region.
- Inspect and filter a dense table of task/run records.
- Select rows and copy meaningful text.
- Start, cancel, and observe a fake worker task with progress.
- Open terminal diagnostics and see capability fallbacks.
- Trigger a minimal debug capture that records enough state for diagnosis.

## Why This Scenario

The current repo already has enough pieces to build much of this without a
greenfield rewrite:

- Core framework, render tree, focus, key bindings, navigation, overlays,
  text input, log view, selection, animation, and tester APIs live in
  `packages/fleury`.
- Higher-level widgets such as `Table`, `CommandPalette`, `Dialog`,
  `MarkdownText`, controls, charts, tabs, tree, file picker, progress, and
  toaster live in `packages/fleury_widgets`.
- `packages/fleury/example/chat_demo.dart` already exercises a three-pane app,
  composer, command palette, focus traversal, modal help, and key hints.
- The new demo app should promote that pressure from one example file into a
  package-level integration harness that can grow with Phase 1.

Peer pressure also points at this shape:

- Nocterm already claims the Flutter-like Dart TUI position with hot reload,
  testing, and built example apps, so Fleury needs a demo app that shows
  stronger app structure, semantic testing, terminal correctness, and
  data-heavy behavior.
- Bubble Tea's examples cover chat, forms, command execution, help, lists,
  tables, tabs, progress, text input, and realtime updates; Fleury's demo app
  should exercise those categories in one retained app rather than as isolated
  examples.
- Textual makes app structure, widgets, command palette, testing, and snapshot
  testing first-class; Fleury's demo app should make semantic testing and
  tester-driven interactions part of the acceptance path.
- Ratatui's table and widget examples set the expectation that terminal data
  widgets are serious, stateful, and keyboard navigable.
- OpenTUI emphasizes correctness, stability, high performance, layered
  keymaps, and production usage; Fleury's demo app should expose capability,
  diagnostics, and performance evidence early.

## Screen Model

The first demo-app slice should have these screens:

| Screen | Purpose | Core pressure |
| --- | --- | --- |
| Overview | Summary cards, active task progress, recent logs, key status. | Layout, focus, animation, status, theme. |
| Connection | Shared form definition rendered as a full-screen panel. | Forms, validation, secret redaction, prompt-mode parity. |
| Runs | Dense task/run table with selection, filter text, sort placeholders. | Table, virtualization path, selection, copy, semantic rows. |
| Tree | Hierarchical subsystem table with expansion, activation, and copy. | TreeTable, hierarchy semantics, filtering/index pressure. |
| Payload | Structured JSON fixture. | JsonView, path/pointer semantics, safe subtree copy. |
| Changes | Unified diff fixture. | DiffView, file/hunk/line semantics, safe hunk copy. |
| Source | Source-code fixture. | CodeView, source-line semantics, safe source copy. |
| Docs | Markdown fixture. | MarkdownView, visible-link fallback, component-theme styling, safe block copy. |
| Transcript | Streamed markdown-ish messages and command output. | Streaming text, sanitization, scroll, selection. |
| Logs | Log tail with severity and source filters. | LogView, safe output, high-volume append. |
| Process | Native command execution with scoped process commands and output panel. | ProcessTaskController, ProcessCommandRunner, ProcessPanel, cancellation, output semantics. |
| Diagnostics | Terminal profile, capabilities, fallbacks, debug capture action. | Capability model, inspector hooks, machine-readable state. |

Only Overview, Runs, Transcript, and Diagnostics are required for Phase 1 v0.
Logs can start as a region inside Transcript if schedule requires it.
Process is a Phase 2 pressure screen added after fake-worker and process
primitives exist; it is intentionally not part of the first demo slice.

## Interaction Model

Required key paths:

- `Tab` / `Shift+Tab`: move focus between major regions.
- Arrow keys: navigate within focused lists, tables, sidebar, and text fields.
- `Ctrl+K`: open command palette.
- `F1`: open help dialog.
- `Enter`: activate selected sidebar item, command, table row, or composer
  submission depending on focus.
- `Esc`: close modal or clear local mode.
- `/`: focus filter field on data-heavy screens.
- `Ctrl+C`: runtime exit guard remains framework-level.

The demo app should use current `KeyBindings`, `KeyHintBar`, focus traversal,
and overlay APIs first. If global commands, action dispatch, or screen-scoped
shortcuts become awkward, that is input for the app-kernel RFC.

## Command Palette

The command palette should expose structural commands, not one-off callbacks
hidden in widgets.

Initial commands:

- `Go to Overview`
- `Go to Runs`
- `Go to Transcript`
- `Go to Process`
- `Go to Diagnostics`
- `Start Fake Task`
- `Cancel Active Task`
- `Run Dart Version`
- `Cancel Dart Version`
- `Copy Selection`
- `Toggle Log Stream`
- `Run Terminal Diagnose`
- `Capture Debug Snapshot`

Acceptance pressure:

- Commands have IDs, labels, descriptions, enabled/disabled state, and
  optional shortcuts.
- Commands are discoverable by the palette and by semantic inspection.
- Commands can be tested without relying only on rendered text.

## Data Model

Use deterministic in-memory fixtures:

- `RunRecord`: id, status, title, owner, duration, progress, updatedAt,
  warnings, selected.
- `TranscriptEvent`: id, source, timestamp, kind, text, severity,
  sanitized.
- `LogEntry`: id, source, timestamp, level, message.
- `TaskState`: id, label, progress, status, cancellable, startedAt.
- `ProcessState`: command display, status, exit code, output count, latest
  output source/severity/safety metadata.
- `DiagnosticReport`: terminal name/profile, color mode, width behavior,
  mouse support, clipboard support, image protocol, fallback list, warnings.

The fixtures should support repeatable tests and benchmarks. Random-looking
data should come from fixed seeds.

## Phase 1 Demo Slice

The first runnable version should prove this workflow:

1. Start on Overview.
2. Navigate to Runs from the sidebar.
3. Filter run records with the filter input.
4. Move selection through the table.
5. Open the command palette and start a fake task.
6. Watch progress and transcript/log output update.
7. Type into the composer and submit a note/command.
8. Open Diagnostics and capture a debug snapshot.
9. Assert the workflow with tester APIs and golden/snapshot output.

This slice is deliberately narrower than a full product. It should exercise the
framework seams that matter most before Dune/`dune_cli`.

## Fleury Primitives To Validate

| Primitive | Required validation |
| --- | --- |
| Widget/state model | Stateful screen switching, retained composer and filters, stable row identity. |
| Focus/input | Predictable focus across sidebar, table, composer, palette, and dialogs. |
| Key bindings | Discoverable global and screen-scoped commands with conflict behavior. |
| Navigator/overlay | Help dialog, command palette, diagnostics detail overlay. |
| Text editing | Composer, filters, history, paste policy placeholder, multiline path. |
| Table/data | Selection, pinned header, filtering, large fixture path, row semantics. |
| Log/output | High-volume append, safe text, severity/source styling, scroll behavior. |
| Worker/task | Progress, cancellation, completion/failure, UI update ordering. |
| Process/workflow | Native subprocess start/cancel, command binding, output panel, exit semantics. |
| Capability model | Fallback display and machine-readable diagnostics. |
| Semantics/testing | Query roles, labels, values, focus, actions, selection, and errors. |
| Inspector/debug | Minimal snapshot with focus, screen, commands, capabilities, dirty regions if available. |

## Acceptance Evidence

M0.1 is complete when this scenario is linked from the tracker and used by the
Phase 0 RFCs.

Phase 1 v0 is complete when evidence exists for:

- Runnable example package at `packages/fleury_example_console`.
- Tester workflow covering the demo slice above.
- Golden or snapshot for the main overview/runs layout.
- Semantic queries for sidebar, command palette, table rows, composer,
  progress, diagnostics, and debug capture action.
- Benchmark fixture for large table and streaming transcript/log updates.
- Notes documenting any API awkwardness discovered while building the slice.

## Explicit Non-Goals

- No Dune/`dune_cli` integration in this cycle.
- No ACP transport, ACP schemas, or ACP-specific widgets.
- No real network service dependency.
- No real subprocess execution in the first slice; use fake workers first.
  Native subprocess pressure can be added in Phase 2 after the task/process
  primitives exist.
- No full replay artifact format.
- No public launch polish.

## Open Questions

- Should the example package be named `fleury_example_console`,
  `fleury_example_ops`, or something more product-neutral?
- Should the composer be single-line first, or should Phase 1 force multiline
  `TextArea` immediately?
- Should table filtering live in the demo app, `Table`, or a future
  data-controller abstraction?
- What is the first stable shape for command IDs and command semantic actions?
- What minimal debug snapshot is useful before the full inspector/replay work?

## Sources Used

- Nocterm package page: <https://pub.dev/packages/nocterm>
- Bubble Tea repository and examples: <https://github.com/charmbracelet/bubbletea>
- Textual app/testing/command palette/widget docs: <https://textual.textualize.io/>
- Ratatui widget and table examples: <https://ratatui.rs/examples/widgets/>
- OpenTUI getting started and keymap docs: <https://opentui.com/docs/getting-started/>
