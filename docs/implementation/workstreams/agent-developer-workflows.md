# Workstream: Agent And Developer Workflows

## Purpose

Make Fleury the natural framework for agentic and developer-tool TUIs: code
review, command execution, diffs, logs, tool calls, permissions, plans,
progress, files, and streaming transcripts.

## Current State

- Fleury has many primitives useful for agent UIs: widgets, focus, key
  bindings, navigator, overlay, log view, markdown text, command palette,
  dialogs, tables, trees, charts, debug shell, and terminal output capture.
- Several agent/developer workflow objects are now first-class widgets and
  semantics; `WorkflowSnapshot` now ties those protocol-neutral records into a
  reference workflow model without owning provider transport or ACP schemas.
- The current-cycle example proof-app workflow scenario is defined in
  [proof-app-scenario.md](../proof-app-scenario.md).
- The first runnable proof-app package skeleton now lives at
  [packages/fleury_example_console](../../../packages/fleury_example_console).
- M1.4 proof app v0 is complete for the current cycle: it exercises app
  screens, commands, status, command palette, text input, DataTable, fake
  worker state, diagnostics, semantic queries, and debug capture through
  targeted tests. The proof app's own sidebar and diagnostic semantic actions
  now route through the same screen-controller and command-registry paths as
  commands and visible controls.
- The framework does not yet provide a Dune-backed workflow scenario or a later
  reference agent console.
- `fleury_widgets` now includes a first protocol-neutral approval surface:
  `ApprovalPrompt`, `ApprovalRequest`, and `ApprovalDecision`, with semantic
  submit/cancel actions and proof-app command coverage.
- `fleury_widgets` now includes a protocol-neutral `MessageList` transcript
  surface with message roles/status, sanitized copy/export, semantic message
  nodes, aggregate focus/navigation, refresh-stable selected-message state when
  not following the tail, accessibility fallback state, and proof-app
  Transcript screen adoption. The proof app now assigns durable transcript
  event IDs and owns the transcript `MessageListController`, proving selected
  message identity across appends, scrollback trimming, and screen changes.
- `fleury_widgets` now includes a protocol-neutral `ToolCallCard` execution
  surface with tool-call role/status/argument semantics, sanitized
  copy/export, semantic cancel, and proof-app Process screen adoption.
- `fleury_widgets` now includes a protocol-neutral `TaskGraph` plan/task
  surface with summary counts, task status/progress/dependency semantics,
  aggregate focus/navigation, refresh-stable selected-task state, sanitized
  copy/export, and proof-app Overview adoption.
- `fleury_widgets` now includes protocol-neutral `ModelStatusBar` and
  `TokenMeter` surfaces with model/runtime/context-window semantics, safe
  accessibility fallback state, and proof-app Overview adoption.
- `fleury_widgets` now includes a protocol-neutral `FileMentionPicker` for
  composer file/symbol references, with semantic query focus/result
  navigation, activate/copy actions, refresh-stable selected-mention state,
  sanitized mention export, accessibility fallback state, and proof-app
  Transcript composer adoption.
- The proof app Transcript composer now uses `CompletionTextInput` for
  deterministic slash-command and mention suggestions plus
  `TextHistoryController` submitted-note recall, proving provider-backed
  composer completion and history through the same semantic model as standalone
  text widgets.
- `fleury_widgets` now includes a protocol-neutral `ConversationNavigator` for
  thread/session lists, with semantic focus/navigation/activate/copy actions,
  refresh-stable selected-conversation state, sanitized conversation export,
  accessibility fallback state, and proof-app Transcript adoption.
- `ConversationNavigatorController` and `FileMentionPickerController` now
  follow the launch lifecycle contract: final selection/visible-range state
  remains readable after teardown, while stale selection and jump mutations
  throw controller-specific lifecycle errors.
- `fleury_widgets` now includes a protocol-neutral `ContextPanel` for
  model-context packs, with context item/budget semantics, sanitized copy/select
  actions, aggregate semantic focus/navigation, accessibility fallback state,
  refresh-stable selected context, and proof-app Overview adoption.
- `fleury_widgets` now includes a protocol-neutral `TraceTimeline` for
  workflow, task, process, diagnostic, and debug event timelines, with
  trace-event semantics, sanitized copy/select actions, accessibility fallback
  state, and proof-app Diagnostics adoption.
- `fleury_widgets` now includes a protocol-neutral `PatchReview` for code-review
  and patch-review workflows, with patch/file semantics, sanitized file
  copy/select actions, aggregate semantic focus/navigation, accessibility
  fallback state, refresh-stable selected file, and proof-app Changes adoption
  while composing `DiffView` for line and hunk review.
- Live workflow controllers now follow the launch lifecycle contract:
  `LogRegionController`, `MessageListController`, `TraceTimelineController`,
  `TaskGraphController`, `ContextPanelController`, and
  `PatchReviewController` keep final selection, visible-range, and tail-follow
  state readable after teardown while rejecting stale selection, jump,
  scroll-to-tail, and workflow-row mutations.
- `fleury_widgets` now includes `WorkflowSnapshot`, `WorkflowSummary`, and
  `WorkflowHealth` as the first protocol-neutral reference workflow model over
  messages, tool calls, approvals, tasks, model status, context, file mentions,
  conversations, trace events, patch files, and logs. The proof app Overview
  screen now exposes the summary as safe semantic state and text-first
  accessibility/fallback state.
- Dune through a future `dune_cli` app is the later flagship product.
- ACP-specific fast-follow work is tracked separately in
  [`fleury_acp` fast-follow package](fleury-acp-fast-follow.md).
- App-level typed extensions now give future workflow/provider packages a
  protocol-neutral place to register app-owned services or workflow models for
  widgets and commands, without making Fleury core own provider transport,
  adapter lifecycle, ACP schemas, or Dune-specific state.
- [Agent adapter boundary](../agent-adapter-boundary.md) defines which
  protocol-neutral primitives Fleury launch must expose for later domain
  adapters.
- [Agent adapter readiness audit](../agent-adapter-readiness-audit.md) closes
  M1.5 for launch scope without starting ACP implementation.

## Target Capabilities

- First-party shapes for sessions, plans, messages, tool calls, approvals,
  diffs, code patches, terminal output, progress, model status, context, file
  mentions, task graphs, and workflow/debug timelines.
- Agent console reference app that pressure-tests streaming markdown, diffs,
  tool calls, approvals, logs, cancellation, semantics, security, replay, and
  performance.
- Structured actions so humans, tests, and agents can operate the same UI.
- Example proof-app workflows first, then later Dune/`dune_cli` workflows that
  prove these widgets against a real product.

## Milestone Checklist

- [x] ADW.1 Define reference agent workflow model.
  - Intent: Establish the forcing app for next-generation TUI needs.
  - Acceptance: Model covers session, plan, message, tool call, approval,
    diff, terminal output, cancellation, progress, model status, context, and
    transcript regions.
  - Evidence:
    [workflow snapshot model](../../../packages/fleury_widgets/lib/src/workflow_snapshot.dart),
    [workflow snapshot tests](../../../packages/fleury_widgets/test/workflow_snapshot_test.dart),
    [proof app Overview workflow summary](../../../packages/fleury_example_console/lib/fleury_example_console.dart),
    [proof app tests](../../../packages/fleury_example_console/test/proof_console_test.dart).
  - Notes: Keep the model framework-shaped, not tied to one provider. Current
    slice adds immutable `WorkflowSnapshot`, aggregate `WorkflowSummary`,
    `WorkflowHealth`, lookup helpers, safe semantic-state projection, and
    proof-app Overview adoption. The follow-up fallback slice adds an
    allow-listed accessibility summary for workflow ID/title/health, activity,
    context, trace, patch, review, and log counts. It deliberately does not own
    routing, persistence, JSON-RPC, ACP content blocks, provider sessions, task
    execution, or transcript storage.

- [x] ADW.2 Build proof-app workflow scenario spec.
  - Intent: Turn agent UI complexity into a benchmark and test fixture.
  - Acceptance: Scenario includes navigation, commands, streamed transcript/log
    output, composer/input, dense data table, progress/cancellation,
    diagnostics, capability fallbacks, and debug capture.
  - Evidence:
    [Proof-app scenario](../proof-app-scenario.md),
    [proof app package](../../../packages/fleury_example_console),
    [proof app tests](../../../packages/fleury_example_console/test/proof_console_test.dart).
  - Notes: This is intentionally protocol-neutral. Tool calls, approvals, ACP,
    and a later reference agent console are deferred until the core is proven.
    The first package skeleton now pressures app-shell commands, screens,
    status, command palette, text input, table fixture, diagnostics, debug
    capture, and tester semantics. The current workflow slice adds command
    palette navigation, table selection activation, composer submission,
    deterministic log bursts, stream-command disabled behavior, and debug
    snapshot transcript evidence. The current semantic-evidence slice adds
    queryable navigation, transcript-log, and diagnostic nodes plus assertions
    for command metadata, table cell state, composer value, progress state,
    capability fallback state, and debug capture action. Phase 1 exit
    validation reran proof-app analyze and workflow tests successfully.
    Current Phase 2 proof-app slice adds an Indexed Logs screen that builds and
    refreshes a retained-log index through `TaskController` /
    `TaskYieldPolicy`, filters through `LogRegionSearchIndex`, exposes
    `LogRegion` semantics, and records the workflow in `SB.10`. The follow-up
    search slice routes Global Search through reusable `SearchResultIndex`
    ranking while keeping result production debounced and app-owned. The
    current semantic-action settling slice makes the proof app's app-authored
    sidebar navigation and Diagnostics report actions operable through
    semantic invocation rather than descriptive-only nodes. The current
    composer-completion slice replaces the Transcript composer with
    `CompletionTextInput` and proves slash-command completion through semantic
    menu activation. The current composer-history slice wires
    `TextHistoryController` into the same composer and proves submitted-note
    recall while preserving completion-menu priority for Up/Down.

- [x] ADW.3 Add agent workflow semantics.
  - Intent: Make workflow objects inspectable and automatable.
  - Acceptance: Semantic graph exposes messages, tool calls, approvals,
    diffs, logs, progress, permissions, actions, and current selection/focus.
  - Evidence:
    [MessageList](../../../packages/fleury_widgets/lib/src/message_list.dart),
    [message list tests](../../../packages/fleury_widgets/test/message_list_test.dart),
    [proof app Transcript tests](../../../packages/fleury_example_console/test/proof_console_test.dart).
  - Notes: Structured actions should avoid screen scraping. Current slice makes
    `MessageList` semantically operable: aggregate focus/navigation reaches the
    backing list, activating a visible transcript row focuses and selects it
    through `MessageListController`, disables follow-tail for browsing, and
    then exposes the existing selected-row copy action. Refreshed message lists
    preserve the selected stable message ID when follow-tail is disabled. The
    proof app now keeps transcript event IDs stable and holds the message-list
    controller in app state so selection survives live appends, scrollback
    trimming, and screen switches. ADW.3 is complete for the MVP through
    protocol-neutral semantics for messages, tool calls, approvals, patches,
    logs, progress, task graphs, traces, context, file mentions, conversations,
    model/token state, selections, focus, copy/select/cancel actions, and
    workflow summaries. Provider-specific automation protocols remain adapter
    work.

- [x] ADW.4 Build first widget set.
  - Intent: Provide visible developer-tool value.
  - Acceptance: MessageList, StreamingMarkdown, ToolCallCard,
    ApprovalPrompt, PatchReview, TraceTimeline, TokenMeter,
    ContextPanel, TaskGraph, CommandRunner, FileMentionPicker,
    ModelStatusBar, and ConversationNavigator have initial contracts.
  - Evidence:
    [MessageList](../../../packages/fleury_widgets/lib/src/message_list.dart),
    [message list tests](../../../packages/fleury_widgets/test/message_list_test.dart),
    [ToolCallCard](../../../packages/fleury_widgets/lib/src/tool_call_card.dart),
    [tool call card tests](../../../packages/fleury_widgets/test/tool_call_card_test.dart),
    [TaskGraph](../../../packages/fleury_widgets/lib/src/task_graph.dart),
    [task graph tests](../../../packages/fleury_widgets/test/task_graph_test.dart),
    [ModelStatusBar and TokenMeter](../../../packages/fleury_widgets/lib/src/model_status_bar.dart),
    [model status tests](../../../packages/fleury_widgets/test/model_status_bar_test.dart),
    [FileMentionPicker](../../../packages/fleury_widgets/lib/src/file_mention_picker.dart),
    [file mention picker tests](../../../packages/fleury_widgets/test/file_mention_picker_test.dart),
    [ConversationNavigator](../../../packages/fleury_widgets/lib/src/conversation_navigator.dart),
    [conversation navigator tests](../../../packages/fleury_widgets/test/conversation_navigator_test.dart),
    [ContextPanel](../../../packages/fleury_widgets/lib/src/context_panel.dart),
    [context panel tests](../../../packages/fleury_widgets/test/context_panel_test.dart),
    [TraceTimeline](../../../packages/fleury_widgets/lib/src/trace_timeline.dart),
    [trace timeline tests](../../../packages/fleury_widgets/test/trace_timeline_test.dart),
    [PatchReview](../../../packages/fleury_widgets/lib/src/patch_review.dart),
    [patch review tests](../../../packages/fleury_widgets/test/patch_review_test.dart),
    [ApprovalPrompt](../../../packages/fleury_widgets/lib/src/approval_prompt.dart),
    [approval prompt tests](../../../packages/fleury_widgets/test/approval_prompt_test.dart),
    [proof app approval workflow](../../../packages/fleury_example_console/test/proof_console_test.dart).
  - Notes: First slice is `ApprovalPrompt`, intentionally protocol-neutral and
    backed by `SemanticRole.approval` plus submit/cancel actions. Current
    slice adds `MessageList`, intentionally protocol-neutral and backed by
    `SemanticRole.messageList` / `SemanticRole.message` plus aggregate
    focus/navigation, row activation for selection, refreshed-list
    selected-message preservation, selected-message copy, and explicit
    tail-follow preservation for live transcripts. Current proof-app hardening
    adds durable transcript IDs plus an app-owned `MessageListController` to
    prove that selected-message identity survives appends and screen changes.
    Current tool-call slice adds
    `ToolCallCard`, intentionally
    protocol-neutral and backed by `SemanticRole.toolCall` plus copy/cancel
    actions. Current plan/task slice adds `TaskGraph`, intentionally
    protocol-neutral and backed by `SemanticRole.taskGraph` plus task-node
    semantics, aggregate focus/navigation, semantic activation for selection,
    refreshed-list selected-task preservation, and selected-node copy.
    Current model/context slice adds
    `ModelStatusBar` and `TokenMeter`, intentionally protocol-neutral and
    backed by `SemanticRole.modelStatus` / `SemanticRole.tokenMeter` with
    model state, latency, queue depth, token totals, and context-window usage.
    Current file-reference slice adds `FileMentionPicker`, intentionally
    protocol-neutral and backed by `SemanticRole.fileMentionPicker` /
    `SemanticRole.fileMention` with file path, kind, language, line/column,
    mention text, aggregate query focus/result navigation, refreshed-list
    selected-mention preservation, sanitized copy, and semantic activation
    into the proof-app composer. Current conversation-navigation slice adds
    `ConversationNavigator`, intentionally protocol-neutral and backed by
    `SemanticRole.conversationNavigator` / `SemanticRole.conversation` with
    thread/session identity, status, unread/message counts, pinned state,
    aggregate focus/navigation, refreshed-list selected-conversation
    preservation, sanitized copy, and semantic activation in the proof-app
    Transcript screen.
    Current context-pack slice adds `ContextPanel`, intentionally
    protocol-neutral and backed by `SemanticRole.contextPanel` /
    `SemanticRole.contextItem` with item identity, kind, token count, priority,
    pinned/source state, aggregate budget state, semantic focus/navigation,
    refresh-stable selected context, sanitized copy, and semantic activation in
    the proof-app Overview screen.
    Current trace-timeline slice adds `TraceTimeline`, intentionally
    protocol-neutral and backed by `SemanticRole.traceTimeline` /
    `SemanticRole.traceEvent` with event identity, kind, status, source,
    duration, selected-event state, aggregate counts, semantic focus/navigation,
    refreshed-list selection preservation, sanitized copy, and semantic
    activation in the proof-app Diagnostics screen. Current effect-history
    slice adds task-event adapters for `TraceTimeline`, exposing live
    task/progress/output events in Diagnostics with task run, event sequence,
    event kind, progress, source, and output-safety metadata while keeping raw
    output/error/result payloads in the appropriate output/debug channels.
    Current patch-review slice adds `PatchReview`, intentionally
    protocol-neutral and backed by `SemanticRole.patchReview` /
    `SemanticRole.patchFile` with patch identity, review status, per-file
    status, file-level stats, selected-file state, semantic focus/navigation,
    refresh-stable selected file, sanitized copy, and semantic activation in
    the proof-app Changes screen. It composes `DiffView` instead of replacing
    line and hunk review semantics.
    `WorkflowSnapshot` closes the first reference read-model layer over these
    widgets. ADW.4 is complete for the MVP: future v2 widgets, Dune/`dune_cli`
    pressure, ACP-specific content blocks, and provider-specific workflows are
    tracked as later work.
    Broader session persistence, provider threads, routing, and transport
    ownership remain app/adapter responsibilities.

## Implementation Notes

- Agent workflows are a proving ground, not the only product direction.
- The same primitives should help database tools, deploy tools, CI dashboards,
  code review tools, and operations consoles.
- The first proof app is a developer operations console, not an ACP console.
- The proof app is complete as a pressure harness, not as polished public
  sample copy. It should continue to catch regressions while Phase 2 widgets
  are added.
- [RFC 0012: App kernel](../../rfcs/0012-app-kernel.md) is the command/screen
  layer these workflows should build on; agent-specific models should not
  bypass the app command registry.
- Permission and approval flows must integrate with security policy and
  replay. The first approval prompt now has semantic actions and proof-app
  transcript evidence; permission-specific policy remains a later workflow
  layer.
- Message/transcript workflows should use protocol-neutral roles and status,
  not ACP or provider-specific schemas. `MessageList` is the launch surface for
  compact transcripts; richer streaming markdown and tool-call cards should
  compose with it rather than replacing the semantic message model. Message-row
  activation means semantic automation can select transcript rows before using
  the existing sanitized copy path. Stable message IDs preserve selected
  message state across app refreshes only after users stop following the tail;
  live tail-follow append remains the default transcript behavior.
- Tool-call workflows should use protocol-neutral tool name, status, argument,
  progress, output, copy, and cancel semantics. `ToolCallCard` composes with
  app-owned runners/tasks and must not own protocol transport or JSON-RPC
  request models.
- Plan/task workflows should use protocol-neutral task IDs, status, progress,
  dependencies, selection activation, and copy semantics. `TaskGraph` is a
  compact plan surface, not a scheduler or workflow engine. Task activation
  focuses and selects; stable task IDs preserve selected plan state across app
  refreshes.
- Model/context workflows should use protocol-neutral model name/provider,
  status, mode, latency, queue depth, token totals, and context-window state.
  `ModelStatusBar` and `TokenMeter` are status surfaces, not protocol
  transport, session, pricing, or provider quota models.
- File-reference workflows should use protocol-neutral path/kind/language,
  optional source location, mention text, activation, and copy semantics.
  `FileMentionPicker` is a composer/reference picker, not a filesystem index,
  LSP symbol resolver, provider context store, or ACP content-block model.
  Aggregate focus reaches the query input, aggregate navigation reaches the
  result list, and stable file paths preserve selected mention state across
  app-owned result refreshes. Its controller should keep final read state
  after teardown but reject stale selection or jump calls.
- Conversation workflows should use protocol-neutral thread/session identity,
  title, status, unread/message counts, latest-message summary, activation, and
  copy semantics. `ConversationNavigator` is a navigator surface, not a
  provider session store, transport model, route controller, or ACP thread
  schema. Row activation focuses and selects; stable conversation IDs preserve
  selected thread/session state across app refreshes. Its controller follows
  the same post-dispose mutation rule as other app-facing selection surfaces.
- Context-pack workflows should use protocol-neutral item identity, kind,
  priority, token count, source, pinned state, activation, and copy semantics.
  `ContextPanel` is a context inspector/selector, not a retriever, provider
  context store, pruning engine, billing model, or ACP content-block schema.
- Trace and workflow timeline surfaces should use protocol-neutral event IDs,
  kind, status, source, timestamps, duration, activation, and copy semantics.
  `TraceTimeline` is a workflow/debug timeline, not a replay log, distributed
  tracing protocol, provider transport event stream, or ACP fixture format.
  Task-event adapters should preserve event ordering and safety flags, not
  duplicate task output, errors, result values, or stack traces.
- Patch-review workflows should use protocol-neutral patch IDs, file paths,
  review status, file stats, activation, and copy semantics. `PatchReview` is a
  review/file-summary surface over `DiffView`, not a git client, patch-apply
  engine, provider review API, merge policy, or ACP content-block schema.
- Live workflow controllers are likely to receive async updates from
  subprocesses, task streams, transcript appenders, and diagnostics after a
  screen unmounts. Keep their final readable selection/tail-follow state
  available for diagnostics, but reject public mutation after disposal at the
  widget-controller boundary.
- Reference workflow models should aggregate protocol-neutral records and
  publish safe summary state, not become app state managers. `WorkflowSnapshot`
  is a read model over existing Fleury workflow records; apps still own
  routing, persistence, provider sessions, task execution, transcript storage,
  and adapter-specific schemas.
- Agent-adapter readiness should be implemented through semantic actions,
  command IDs, worker/task state, safe output regions, selection/copy, and
  debug capture hooks. Do not introduce provider or ACP protocol models into
  core.
- M1.5 is complete as a boundary audit. The next agent-workflow work should be
  protocol-neutral widgets and reference workflow models, not ACP transport.

## Risks And Open Questions

- Agent-specific APIs could narrow the framework if introduced too early.
- Streaming transcript performance can hide data-widget and markdown costs.
- Provider-specific protocol choices should stay outside the core framework.

## Acceptance Evidence

- First protocol-neutral reference workflow model:
  [WorkflowSnapshot](../../../packages/fleury_widgets/lib/src/workflow_snapshot.dart).
- [workflow snapshot tests](../../../packages/fleury_widgets/test/workflow_snapshot_test.dart).
- First protocol-neutral approval prompt:
  [ApprovalPrompt](../../../packages/fleury_widgets/lib/src/approval_prompt.dart).
- First protocol-neutral message transcript:
  [MessageList](../../../packages/fleury_widgets/lib/src/message_list.dart).
- First protocol-neutral tool-call card:
  [ToolCallCard](../../../packages/fleury_widgets/lib/src/tool_call_card.dart).
- First protocol-neutral task graph:
  [TaskGraph](../../../packages/fleury_widgets/lib/src/task_graph.dart).
- First protocol-neutral model/context status surface:
  [ModelStatusBar and TokenMeter](../../../packages/fleury_widgets/lib/src/model_status_bar.dart).
- First protocol-neutral file mention picker:
  [FileMentionPicker](../../../packages/fleury_widgets/lib/src/file_mention_picker.dart).
- First protocol-neutral conversation navigator:
  [ConversationNavigator](../../../packages/fleury_widgets/lib/src/conversation_navigator.dart).
- First protocol-neutral context panel:
  [ContextPanel](../../../packages/fleury_widgets/lib/src/context_panel.dart).
- First protocol-neutral trace timeline:
  [TraceTimeline](../../../packages/fleury_widgets/lib/src/trace_timeline.dart).
- First protocol-neutral patch review:
  [PatchReview](../../../packages/fleury_widgets/lib/src/patch_review.dart).
- [message list tests](../../../packages/fleury_widgets/test/message_list_test.dart).
- [tool call card tests](../../../packages/fleury_widgets/test/tool_call_card_test.dart).
- [task graph tests](../../../packages/fleury_widgets/test/task_graph_test.dart).
- [model status tests](../../../packages/fleury_widgets/test/model_status_bar_test.dart).
- [file mention picker tests](../../../packages/fleury_widgets/test/file_mention_picker_test.dart).
- [conversation navigator tests](../../../packages/fleury_widgets/test/conversation_navigator_test.dart).
- [context panel tests](../../../packages/fleury_widgets/test/context_panel_test.dart).
- [trace timeline tests](../../../packages/fleury_widgets/test/trace_timeline_test.dart).
- [patch review tests](../../../packages/fleury_widgets/test/patch_review_test.dart).
- [approval prompt tests](../../../packages/fleury_widgets/test/approval_prompt_test.dart).
- [Proof-app scenario](../proof-app-scenario.md).
- [proof app package](../../../packages/fleury_example_console).
- [proof app tests](../../../packages/fleury_example_console/test/proof_console_test.dart).
- [Agent adapter boundary](../agent-adapter-boundary.md).
- [Agent adapter readiness audit](../agent-adapter-readiness-audit.md).
- Pending reference app.
