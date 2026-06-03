# Fleury Agent Adapter Boundary

**Status:** Phase 0 definition complete
**Milestone:** M0.8 Agent adapter and `fleury_acp` package boundary
**Owner:** Agent/developer workflows, `fleury_acp` fast-follow package,
semantic app graph, effects/workflow/process, data widgets, replay/devtools,
and terminal capability/security.

## Purpose

Fleury should launch agent-adapter ready without becoming ACP-native.

The boundary is:

- Fleury core and reusable widgets expose protocol-neutral foundations for
  developer-tool and agent-style apps.
- `fleury_acp` is a later optional package that owns ACP transport, schemas,
  protocol models, ACP-specific widgets, and ACP replay fixtures.
- Fleury core never imports ACP schemas, ACP method names, JSON-RPC transport
  code, or ACP-specific widget assumptions.

This keeps Fleury valuable beyond one protocol while making a fast-follow ACP
package practical.

## ACP Source Snapshot

Primary ACP docs refreshed on 2026-05-31:

- [Overview](https://agentclientprotocol.com/protocol/overview): ACP uses
  JSON-RPC 2.0 methods and notifications; common flow includes initialize,
  session setup, `session/prompt`, `session/update`, permissions, and
  `session/cancel`.
- [Prompt turn](https://agentclientprotocol.com/protocol/prompt-turn): prompt
  turns include user content, plan updates, agent message chunks, tool calls,
  tool-call updates, stop reasons, and cancellation semantics.
- [Tool calls](https://agentclientprotocol.com/protocol/tool-calls): tool
  calls report real-time progress/results and can include terminal content.
- [Terminals](https://agentclientprotocol.com/protocol/terminals): terminal
  output can be displayed live, retrieved incrementally, truncated, and
  released after use.
- [Transports](https://agentclientprotocol.com/protocol/transports): stdio is
  a defined transport; messages are UTF-8 JSON-RPC messages delimited by
  newlines, and agent stdout must contain only valid ACP messages.

These docs reinforce the boundary: ACP is mostly transport, protocol schema,
session lifecycle, and agent workflow state. Fleury should support those
through general UI/runtime primitives, not by making ACP concepts part of core.

## What Fleury Launch Must Expose

These are launch adapter-readiness requirements. They do not require ACP
implementation.

### Semantic App Graph

Fleury must expose semantic nodes and actions for:

- Screens/routes.
- Commands/actions.
- Text inputs and composers.
- Message/transcript regions.
- Tool-call regions.
- Plan/task graph regions.
- Model/runtime status and token/context-window regions.
- File mention/reference regions.
- Workflow/debug trace timeline regions.
- Progress/task state.
- Output/log regions.
- Data tables and selections.
- Markdown/content regions.
- Diff/code and patch-review regions.
- Dialogs, confirmations, and approval-like interactions.
- Capability fallback and policy-block state.
- Debug capture action and diagnostic regions.

Adapter packages should be able to map protocol objects into semantic nodes
without screen scraping.

### App Kernel

Fleury must expose:

- Stable command IDs and direct command invocation.
- Command metadata: label, description, category, shortcut, enabled state,
  visible state, and semantic action.
- Screen identity and active screen state.
- Status items for active task/progress/fallback summaries.
- Programmatic navigation and command-palette integration.

An adapter package should map protocol operations into commands and status,
not private widget callbacks.

### Effects, Workers, And Process Hooks

Fleury must expose:

- Worker/task state: idle, queued, running, succeeded, failed, cancelled.
- Progress updates.
- Cancellable operations.
- Ordered output chunks.
- Fake-time hooks for tests.
- Terminal handoff boundaries for later subprocess support.
- Structured failure and cancellation records.

ACP prompt turns, tool calls, terminal requests, and cancellations can map onto
these without Fleury knowing ACP names.

### Output Regions And Sanitization

Fleury must expose reusable output surfaces for:

- Plain text logs.
- Rich text/markdown.
- Protocol-neutral message transcripts.
- Restricted ANSI output.
- Terminal-like command output.
- Truncation and scrollback policy.
- Search, selection, and copy.
- Redaction before display, copy, debug capture, or future replay artifacts.

ACP terminal output and tool-call content should pass through the same safety
pipeline as any other untrusted process output.

### Data And Developer-Tool Widgets

Fleury or `fleury_widgets` should own reusable, protocol-neutral widgets:

- DataTable.
- LogView/output region.
- MessageList/transcript region.
- MarkdownView/StreamingMarkdown.
- DiffView.
- CodeView.
- PatchReview.
- ModelStatusBar and TokenMeter.
- FileMentionPicker.
- ConversationNavigator.
- ContextPanel.
- TraceTimeline.
- Progress/status widgets.
- CommandRunner or terminal-output region once process support is ready.
- Search/filter widgets.

If a widget is useful for database tools, deploy tools, CI dashboards, code
review tools, and agent tools, keep it protocol-neutral.

### Testing, Debug Capture, And Future Replay

Fleury must expose:

- Semantic tester queries.
- Command invocation in tests.
- Fake input, fake resize, and fake time.
- Worker/process state snapshots.
- Terminal profile/capability snapshots.
- Sanitized output summaries.
- Redaction counts or policy events.
- Debug capture hook points.

`fleury_acp` can add ACP replay fixtures later, but Fleury launch only needs
the protocol-neutral hooks.

## What `fleury_acp` Owns

The fast-follow package owns:

- ACP JSON-RPC transport.
- ACP stdio process management.
- ACP schema/version handling.
- ACP client/agent capability negotiation.
- ACP session IDs and lifecycle.
- ACP prompt turn models.
- ACP content block models.
- ACP tool call and tool call update models.
- ACP permission request mapping.
- ACP terminal method mapping.
- ACP cancellation mapping.
- ACP-specific replay fixtures.
- ACP-specific widgets and adapters.

Examples of ACP-specific widgets:

- `AcpSessionList`.
- `AcpPromptTurnView`.
- `AcpToolCallCard`.
- `AcpPermissionPrompt`.
- `AcpTerminalAttachment`.
- `AcpModeSwitcher`.
- `AcpCommandProvider`.

These widgets can compose Fleury primitives, but their public API should speak
ACP terms only inside `fleury_acp`.

## What Stays Out Of Fleury Core

Fleury core should not contain:

- ACP schemas.
- ACP method names such as `session/prompt`, `session/update`, or
  `terminal/output`.
- JSON-RPC request/response types.
- ACP transport implementations.
- ACP session/prompt/tool-call classes.
- ACP-specific widgets.
- ACP replay fixture formats.
- Protocol-specific permission models.

Fleury may contain generic equivalents such as task state, command state,
approval/confirmation UI, output regions, and capability policy.

Current implementation note: `fleury_widgets` now includes a
protocol-neutral `ApprovalPrompt` over `SemanticRole.approval` with
submit/cancel actions. This is intentionally not ACP-specific; `fleury_acp`
can later map ACP permission requests onto this surface or provide
ACP-specific widgets that compose it.

Current implementation note: `fleury_widgets` also includes protocol-neutral
`MessageList`, `ToolCallCard`, `TaskGraph`, `ModelStatusBar`, and
`TokenMeter` surfaces, plus `FileMentionPicker`, `ConversationNavigator`,
`ContextPanel`, `TraceTimeline`, and `PatchReview`, over
`SemanticRole.messageList`, `SemanticRole.message`, `SemanticRole.toolCall`,
`SemanticRole.taskGraph`, `SemanticRole.modelStatus`, and
`SemanticRole.tokenMeter`, `SemanticRole.fileMentionPicker`, and
`SemanticRole.fileMention`, `SemanticRole.conversationNavigator`,
`SemanticRole.conversation`, `SemanticRole.contextPanel`,
`SemanticRole.contextItem`, `SemanticRole.traceTimeline`, and
`SemanticRole.traceEvent`, `SemanticRole.patchReview`, and
`SemanticRole.patchFile`. These provide transcript, execution, plan,
model/context status, file-reference, thread/session navigation, context pack
UI, workflow/debug timelines, and patch-review summaries without ACP imports;
`fleury_acp` can later map prompt-turn content blocks, tool-call updates, plan
updates, model/session status, file content references, ACP sessions/threads,
provider context packs, protocol event streams, and provider review events onto
them.

## Mapping Model

| ACP concept | `fleury_acp` responsibility | Fleury protocol-neutral surface |
| --- | --- | --- |
| Initialize/capabilities | Parse ACP capabilities and negotiate protocol version. | Terminal/app capability diagnostics and status items. |
| Session | Own ACP session IDs and lifecycle. | Screen state, semantic regions, app status, command scopes. |
| Prompt turn | Parse prompt content and stop reasons. | Text input/composer, transcript region, task lifecycle, cancellation action. |
| Plan update | Parse ACP plan entries. | Progress/task list semantics and status widgets. |
| Agent message chunk | Parse content blocks. | Streaming markdown/text output region with sanitization. |
| Tool call | Parse ACP tool call state. | Generic task/progress/output semantics and optional protocol-neutral task widgets. |
| Prompt/tool/process timeline | Own protocol event ordering and fixture mapping. | Generic trace timeline event semantics, activation, copy, and diagnostics state. |
| Patch or review update | Own provider review events and patch application policy. | Generic patch review file/status semantics plus `DiffView` line/hunk review. |
| Permission request | Parse ACP request/outcome. | Confirmation/approval dialog semantics and command actions. |
| Terminal output | Parse terminal IDs and output methods. | Sanitized terminal-output region, scrollback, truncation, selection/copy. |
| Cancellation | Map `session/cancel` and cancelled stop reason. | Worker cancellation, command disabled state, status, semantic action. |
| Replay fixture | Own ACP event fixture format. | Debug capture hooks and semantic/output snapshots. |

## Launch Readiness Checklist

Fleury launch is adapter-ready when:

- [x] Semantic graph can represent commands, text inputs, tasks/progress,
  output regions, selections, dialogs, data rows/cells, trace timelines,
  diagnostics, and capability fallback state.
- [x] `FleuryApp` exposes command registry, command invocation, screen state,
  status, and command palette integration.
- [x] Worker/task model exposes success, failure, cancellation, progress,
  ordered output, and semantic state.
- [x] Sanitized output pipeline handles raw ANSI, unsafe OSC/control
  sequences, malformed Unicode, huge lines, markdown links, and redaction.
- [x] Data/output widgets expose selection, copy, search, truncation, and
  semantic state.
- [x] Debug capture hooks can snapshot input, resize, fake time, worker state,
  terminal profile, semantic state, and sanitized output summary.
- [x] Capability/security policy is visible to widgets, semantics, tests, and
  inspector.
- [x] No Fleury core package imports ACP schemas or JSON-RPC transport types.

## Fast-Follow Package Shape

Candidate package layout after Fleury launch foundations stabilize:

```text
packages/
  fleury_acp/
    lib/
      fleury_acp.dart
      src/transport/
      src/protocol/
      src/adapters/
      src/widgets/
      src/testing/
    test/
    example/
```

Dependencies:

- `fleury_acp` depends on `fleury`.
- `fleury_acp` may depend on `fleury_widgets` if reusable widgets remain
  outside core.
- `fleury` and `fleury_widgets` do not depend on `fleury_acp`.

Testing strategy:

- Protocol fixtures live in `fleury_acp/test/fixtures`.
- Golden/semantic tests use `FleuryTester`.
- Transport tests use fake JSON-RPC streams.
- Output tests use the Fleury sanitizer/capability policy.
- Replay fixtures remain package-owned until Fleury has a stable public replay
  format.

## Phase 1 Hand-Off

M1.5 should implement adapter-readiness, not ACP:

- Add semantic fields/actions that adapter packages need.
- Ensure app commands can be invoked by ID in tests and adapters.
- Ensure worker/task state can represent external protocol operations.
- Ensure output regions and copy paths use safety/redaction hooks.
- Ensure debug capture and inspector expose enough state for a future adapter.
- Add a no-ACP-import check if package structure makes it easy.

`fleury_acp` implementation starts only after the Phase 1 core proves the
example subpackage, text editing, app shell, DataTable, output safety, and
debug hooks.

## Risks And Stop Conditions

- If ACP changes significantly, keep `fleury_acp` experimental and do not pull
  protocol concepts into core.
- If adapter readiness starts delaying semantic tree, app shell, text editing,
  DataTable, benchmark harness, or output safety, cut it back to the generic
  primitives above.
- If a widget speaks only ACP terminology, it belongs in `fleury_acp`.
- If a widget is broadly useful, keep it protocol-neutral and prove it in the
  example subpackage before using it in an ACP package.
