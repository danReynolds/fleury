# Workstream: Replay, Devtools, And Testing

## Purpose

Make complex TUI behavior reproducible, inspectable, and testable without a
real terminal.

## Current State

- Fleury has `FleuryTester`, fake drivers, golden assertions, debug shell,
  debug panels, debug events, and output capture.
- Deterministic clock, ticker-scheduler, and clipboard fakes now live behind
  `fleury_test.dart` rather than production barrels, preserving a clean
  Flutter-style production/test import split while keeping tests and internal
  benchmarks deterministic.
- Tests can drive input, assert output, and query semantic snapshots across
  first-widget M1.1 targets.
- Tests can now invoke supported semantic actions by current semantic node,
  role, label, and state filters for app-authored semantics, app commands,
  app-owned screen/section nodes, status items, text fields, text areas,
  buttons, and
  basic controls. Production-widget coverage now includes `DataTable`,
  `LogRegion`, `SearchPanel`, `Tree`, `TreeTable`, `FileBrowser`,
  `FilePicker`, `ColorPicker`, `NumberInput`, `PasswordInput`, and `Tooltip`
  copy/select/open/activate/focus behavior, plus JSON/diff/code/markdown
  document-view open/copy/focus behavior, form submit/cancel/field focus,
  process cancel, dialog dismiss, and command-palette submit/dismiss/row
  activation, approval prompt submit/cancel behavior, and message-list
  focus/navigation, row activation, refresh-stable selected-message state, and
  selected-message copy behavior, tool-call copy/cancel behavior, and
  task-graph focus/navigation, task-node activation, refresh-stable
  selected-task state, and selected-task copy behavior. Public toaster
  notifications now
  expose semantic dismiss and optional activate actions through the same paths
  as visible hotkeys. Numeric controls and date pickers now expose semantic
  increment/decrement actions through their existing keyboard movement paths.
  Dashboard visualization coverage now includes chart semantics and
  accessibility fallback for Gauge, Sparkline, BarChart, Histogram, Heatmap,
  CalendarHeatmap, and LineChart, semantic text for Digits, plus semantic
  focus/increment/decrement cursor actions for interactive LineChart and
  demo-app Overview telemetry assertions. Generic `Canvas` coverage now
  proves plain canvases stay semantic-silent and app-authored custom drawings
  can opt into image/chart semantics with marker and bounds fallback state.
- Model/context status testing now covers `ModelStatusBar` as
  `SemanticRole.modelStatus` and `TokenMeter` as `SemanticRole.tokenMeter`,
  including safe semantic and accessibility assertions for model state,
  latency, queue depth, token totals, and context-window usage.
- File-reference workflow testing now covers `FileMentionPicker` as
  `SemanticRole.fileMentionPicker` and file rows as
  `SemanticRole.fileMention`, including aggregate query focus/result
  navigation, semantic activation into the demo-app composer, refreshed-list
  selected-mention preservation, and sanitized selected-mention copy.
- Conversation workflow testing now covers `ConversationNavigator` as
  `SemanticRole.conversationNavigator` and conversation rows as
  `SemanticRole.conversation`, including semantic focus/navigation, semantic
  activation in the demo-app Transcript screen, refreshed-list
  selected-conversation preservation, and sanitized selected-conversation copy.
- Context-pack workflow testing now covers `ContextPanel` as
  `SemanticRole.contextPanel` and context rows as `SemanticRole.contextItem`,
  including semantic focus/navigation, semantic activation in the demo-app
  Overview screen, refreshed-list selected-context preservation, and sanitized
  selected-context-item copy.
- Trace workflow testing now covers `TraceTimeline` as
  `SemanticRole.traceTimeline` and trace rows as `SemanticRole.traceEvent`,
  including semantic activation in the demo-app Diagnostics screen and
  sanitized selected-trace-event copy.
- Patch-review workflow testing now covers `PatchReview` as
  `SemanticRole.patchReview` and file rows as `SemanticRole.patchFile`,
  including semantic focus/navigation, semantic activation in the demo-app
  Changes screen, refreshed-list selected-file preservation, sanitized
  selected-file copy, and nested `DiffView` hunk-copy behavior.
- Reference workflow model testing now covers `WorkflowSnapshot`,
  `WorkflowSummary`, `WorkflowHealth`, immutable record aggregation, lookup
  helpers, safe semantic-state projection, and demo-app Overview summary
  adoption without provider or ACP schemas. Accessibility testing now also
  verifies the safe workflow fallback summary produced from the same semantic
  state.
- Debug shell now exposes a semantic Tree-tab summary, app/command/focus state,
  task/effect aggregate summaries, individual task summaries, capability
  fallback summaries, selected semantic-node details, keyboard cursor
  navigation over a graph window, and a Rebuilds tab with frame reasons, phase
  costs, dirty-cell counts, dirty bounds, source-level build/layout/paint
  invalidation labels, repaint-boundary cache metrics, and recent frame
  diagnostics. The Tree tab now renders inspection schema/action/focus summary
  from `SemanticInspectionSnapshot` and uses inspection nodes for selected-node
  details, so live devtools follow the same redaction-aware protocol as tests
  and capture artifacts. The Tree tab also renders terminal
  profile/capability/fallback/warning rows from the runtime diagnosis provider.
  `DebugController` now keeps final inspector state readable after disposal,
  clears live semantic and terminal diagnosis providers during teardown, and
  rejects post-dispose debug-shell mutations. It does not yet expose full
  replay capture.
- Bounded debug-capture hooks now record terminal diagnosis, input/resize
  events, frame metadata, optional output summaries, and redacted semantic
  snapshots suitable for writing targeted regression tests. Capture snapshots
  now also include typed, queryable text-first accessibility/fallback output
  derived from those semantic trees or supplied explicitly by non-widget
  fallback sessions, aggregate accessibility summary counts for quick artifact
  triage, safe metadata-only task-event summaries for workflow debugging, and
  deterministic fake/replay clock markers.
- `DebugCaptureArtifact` now turns serialized snapshots into a queryable
  regression-test surface for inputs, frames, output summaries, task-event
  summaries, time markers, semantic nodes, and accessibility narration without
  requiring full replay. It now also exposes semantic role/action totals from
  the inspection snapshot for quick artifact triage.
- Debug capture now serializes semantics through `SemanticInspectionSnapshot`,
  so capture artifacts and future inspection/automation adapters share the
  same schema-versioned, redaction-aware semantic JSON instead of maintaining
  separate serializers. Capture artifacts now also parse that JSON back into a
  `SemanticInspectionSnapshot`, proving the artifact/test consumer path uses
  the public protocol instead of hand-walking private maps.
- `FleuryTester` now exposes `semanticInspectionSnapshot()` and
  `semanticInspectionJson()` so tests can assert against the same inspection
  protocol directly without routing through debug-capture artifacts.
- `FleuryTester.invokeSemanticAction` now accepts a semantic node id, allowing
  tests and future adapters to inspect a node from parsed protocol JSON and
  invoke one of its advertised actions without relying on role/label
  uniqueness.
- `SB.10 Demo-App Journey` now records debug-capture artifact size and checks
  that the integrated demo app can finish with semantics plus accessibility
  output intact after command, table, transcript, process, and diagnostics
  workflow pressure.
- M0.7 defines a targeted debug-capture prototype and keeps full shareable
  replay artifacts deferred.

## Target Capabilities

- Semantic testing by role, label, value, focus, action, error, and selection.
- Debug capture hooks for input, resize, fake time, worker/process status,
  terminal profiles, semantic snapshots, frame timing, and rendered frames.
- Full replay logs and shareable replay artifacts are deferred until after
  launch foundations are stable.
- Inspector views for focus, commands, semantic graph, dirty regions, effects,
  frame timing, and capability fallbacks.
- Later shareable replay artifacts for bug reports and regression tests, after
  debug capture proves what data is actually needed.

## Milestone Checklist

- [x] RDT.1 Add semantic testing APIs.
  - Intent: Reduce brittle golden-only behavior tests.
  - Acceptance: Tester can query and activate semantic nodes across controls,
    fields, tables, dialogs, commands, routes, and progress regions.
  - Evidence:
    [tester snapshot API](../../../packages/fleury/lib/src/testing/fleury_tester.dart),
    [semantic tree queries](../../../packages/fleury/lib/src/semantics/semantics.dart),
    [semantic tests](../../../packages/fleury/test/semantics/semantics_test.dart),
    [app semantic tests](../../../packages/fleury/test/app/fleury_app_test.dart),
    [navigator semantic tests](../../../packages/fleury/test/widgets/navigator_test.dart),
    [control semantic tests](../../../packages/fleury_widgets/test/controls_test.dart),
    [button semantic tests](../../../packages/fleury_widgets/test/button_test.dart),
    [table semantic tests](../../../packages/fleury_widgets/test/table_test.dart),
    [DataTable semantic tests](../../../packages/fleury_widgets/test/data_table_test.dart),
    [LogRegion semantic tests](../../../packages/fleury_widgets/test/log_region_test.dart),
    [SearchPanel semantic tests](../../../packages/fleury_widgets/test/search_panel_test.dart),
    [Tree semantic tests](../../../packages/fleury_widgets/test/tree_test.dart),
    [TreeTable semantic tests](../../../packages/fleury_widgets/test/tree_table_test.dart),
    [FileBrowser semantic tests](../../../packages/fleury_widgets/test/file_browser_test.dart),
    [FilePicker semantic tests](../../../packages/fleury_widgets/test/file_picker_test.dart),
    [ColorPicker semantic tests](../../../packages/fleury_widgets/test/color_picker_test.dart),
    [NumberInput semantic tests](../../../packages/fleury_widgets/test/number_input_test.dart),
    [PasswordInput semantic tests](../../../packages/fleury_widgets/test/password_input_test.dart),
    [Tooltip semantic tests](../../../packages/fleury_widgets/test/tooltip_test.dart),
    [JsonView semantic tests](../../../packages/fleury_widgets/test/json_view_test.dart),
    [DiffView semantic tests](../../../packages/fleury_widgets/test/diff_view_test.dart),
    [CodeView semantic tests](../../../packages/fleury_widgets/test/code_view_test.dart),
    [MarkdownView semantic tests](../../../packages/fleury_widgets/test/markdown_view_test.dart),
    [form semantic tests](../../../packages/fleury_widgets/test/form_test.dart),
    [ProcessPanel semantic tests](../../../packages/fleury_widgets/test/process_panel_test.dart),
    [dialog semantic tests](../../../packages/fleury_widgets/test/dialog_test.dart),
    [progress semantic tests](../../../packages/fleury_widgets/test/progress_bar_test.dart),
    [stepper semantic tests](../../../packages/fleury_widgets/test/stepper_test.dart),
    [range slider semantic tests](../../../packages/fleury_widgets/test/range_slider_test.dart),
    [date picker semantic tests](../../../packages/fleury_widgets/test/date_picker_test.dart),
    [approval prompt semantic tests](../../../packages/fleury_widgets/test/approval_prompt_test.dart),
    [message list semantic tests](../../../packages/fleury_widgets/test/message_list_test.dart),
    [tool call card semantic tests](../../../packages/fleury_widgets/test/tool_call_card_test.dart),
    [task graph semantic tests](../../../packages/fleury_widgets/test/task_graph_test.dart),
    [model status semantic tests](../../../packages/fleury_widgets/test/model_status_bar_test.dart),
    [file mention picker semantic tests](../../../packages/fleury_widgets/test/file_mention_picker_test.dart),
    [conversation navigator semantic tests](../../../packages/fleury_widgets/test/conversation_navigator_test.dart),
    [context panel semantic tests](../../../packages/fleury_widgets/test/context_panel_test.dart),
    [trace timeline semantic tests](../../../packages/fleury_widgets/test/trace_timeline_test.dart),
    [patch review semantic tests](../../../packages/fleury_widgets/test/patch_review_test.dart),
    [toaster semantic tests](../../../packages/fleury_widgets/test/toaster_test.dart),
    [demo app approval workflow](../../../packages/fleury_example_console/test/demo_console_test.dart),
    [command semantic tests](../../../packages/fleury_widgets/test/command_palette_test.dart).
  - Notes: Query coverage now exists for text, fields, controls, table,
    dialog, command palette, command entries, navigator routes, and progress.
    Semantic action invocation now dispatches through semantic contributors
    instead of widget internals and covers app-authored `Semantics`,
    app/global commands, app-owned screen/section nodes, status items, text fields,
    text areas, buttons, checkboxes, toggles, radios, composition `Table`,
    `DataTable`,
    `LogRegion`, `SearchPanel`, `Tree`, `TreeTable`, and `FileBrowser`.
    `LogRegion` now includes aggregate focus/navigation plus visible-row
    semantic activation that focuses the region and selects log entries through
    `LogRegionController` before using the selected-row copy path.
    Document-view coverage now includes `JsonView` branch open/copy,
    `DiffView` focus/visible-line activation/copy, `CodeView`
    focus/visible-line activation/copy, and `MarkdownView`
    focus/visible-block activation/copy. Workflow/modal coverage now includes
    `FormPanel` submit/cancel/field focus, `ProcessPanel`
    cancel, `Dialog` dismiss, and `CommandPalette` submit/dismiss/row
    activation. Navigator coverage now includes route and navigator
    close/dismiss dispatch through the same `maybePop` path as Esc/back.
    Numeric-control coverage now includes `Stepper` as
    `SemanticRole.spinButton` and `RangeSlider` as `SemanticRole.slider`, with
    semantic focus plus increment/decrement actions that reuse their existing
    keyboard nudge behavior. Date-control coverage now includes `DatePicker`
    as `SemanticRole.datePicker`, with semantic focus plus day
    increment/decrement actions that reuse the existing date-move behavior.
    Approval workflow coverage now includes `ApprovalPrompt` as
    `SemanticRole.approval`, with semantic submit/cancel actions routed
    through the same callbacks as visible approve/deny buttons and demo-app
    command coverage. Transcript workflow coverage now includes `MessageList`
    as `SemanticRole.messageList` / `SemanticRole.message`, with selected-row
    semantic copy routed through the same sanitized clipboard path as Ctrl+C,
    aggregate focus/navigation routed to the backing list, row semantic
    activation selecting messages through `MessageListController`, refreshed
    message-list selection preservation by stable ID when not following the
    tail, tail-follow append preservation, and demo-app transcript adoption.
    Demo-app coverage now also verifies durable transcript message IDs and an
    app-owned controller preserve selected-message identity across live appends,
    scrollback trimming, and screen changes.
    Core task workflow coverage now includes `TaskStatusView` semantic cancel
    dispatch through `TaskController.cancel`. Tool-call workflow coverage now
    includes `ToolCallCard` as `SemanticRole.toolCall`, with semantic copy and
    cancel routed through the same sanitized copy/callback path as visible
    controls and demo-app Process screen adoption. Plan/task workflow
    coverage now includes `TaskGraph` as `SemanticRole.taskGraph`, with
    aggregate focus/navigation routed to the backing list, task-node semantic
    activation selecting through `TaskGraphController`, refreshed-list
    selected-task preservation by stable ID, selected task-node semantic copy,
    and demo-app Overview adoption.
    Model/context workflow coverage now includes `ModelStatusBar` and
    `TokenMeter` semantic and accessibility assertions plus demo-app Overview
    adoption. File-reference workflow coverage now includes `FileMentionPicker`
    semantic focus/navigation/activate/copy, file path/kind/language/location/
    mention state, refreshed-list selected-mention preservation, sanitized
    export, and demo-app Transcript composer adoption.
    Conversation workflow coverage now includes `ConversationNavigator`
    semantic focus/navigation/activate/copy, conversation ID/status/unread/
    message/pinned state, refreshed-list selected-conversation preservation,
    sanitized export, and demo-app Transcript adoption.
    Context-pack workflow coverage now includes `ContextPanel` semantic
    focus/navigation/activate/copy, context item ID/kind/token/priority/
    pinned/source state, aggregate budget state, refreshed-list
    selected-context preservation, sanitized export, and demo-app Overview
    adoption.
    Trace workflow coverage now includes `TraceTimeline` semantic
    focus/navigation/activate/copy, trace event ID/kind/status/source/duration
    state, aggregate trace counts, refreshed-list selected-trace preservation,
    sanitized export, and demo-app Diagnostics adoption.
    Patch-review workflow coverage now includes `PatchReview` semantic
    focus/navigation/activate/copy, patch ID/status, file path/status,
    addition/deletion/hunk state, refreshed-list selected-file preservation,
    sanitized file export, nested `DiffView` hunk copy, and demo-app Changes
    adoption. Reference workflow coverage now includes `WorkflowSnapshot`
    summary health/count state and demo-app Overview semantic assertions over
    the aggregate workflow model. Notification coverage now includes `Toaster` semantic
    dismiss/activate, severity, stack position, auto-dismiss timing, action
    label/key state, and accessibility fallback assertions. Tab coverage now
    includes semantic focus/select/activate actions, position/count/shortcut
    fallback assertions, and inactive `IndexedStack` page semantic pruning.
    Menu coverage now includes semantic trigger open, menu-item activate,
    submenu open, item position/count fallback, and lazy visible-row semantics.
    Select coverage now includes semantic trigger open, option select/activate,
    disabled-option state, checked applied option state, selected value state,
    and option position/count fallback assertions.
    Autocomplete coverage now includes text-field placeholder labeling,
    suggestion-menu close, suggestion select/activate, query state, selected
    suggestion state, suggestion count, and suggestion position/count fallback
    assertions. CompletionTextInput coverage now includes completion-menu
    focus/close state, selected-row metadata, and row select/activate through
    the same completion acceptance path as Tab. Demo-app coverage now also
    drives the Transcript composer through semantic completion-menu activation
    for slash-command completions and submitted-note history recall through
    `TextHistoryController`. FilePicker coverage now includes
    tree/tree-item semantic
    snapshots, selected directory/file state, semantic focus, directory open,
    file selection, safe path values, and tree collection fallback assertions.
    ColorPicker coverage now includes list/radio swatch snapshots, selected
    color state, custom semantic swatch labels, semantic select/activate, and
    palette grid fallback assertions. NumberInput coverage now includes
    constrained numeric text-field metadata, parsed numeric value, bounds,
    decimal/negative policy, accessibility fallback state, and semantic submit
    clamping through the same path as Enter. PasswordInput coverage now
    includes semantic secret-field metadata, optional semantic labels, custom
    app metadata, redacted values, and redacted clipboard state. Tooltip
    coverage now includes
    semantic help-region snapshots, sanitized tooltip message value/hint,
    overlay-visible state, and hidden overlay pruning.
    Composition Table coverage now includes table focus/activate dispatch and
    body-cell select/activate dispatch through the same focus, selection, and
    `onSelect` paths as keyboard interaction. Demo-app app-authored sidebar
    navigation and diagnostic actions now dispatch through the existing
    screen-controller and command-registry paths.
    RDT.1 is complete for the MVP. A local semantic-action audit found no
    remaining production widget with exposed semantic actions lacking tester
    invocation coverage; future action coverage should be opened only when new
    widgets expose concrete open/close/copy/select or domain-specific actions.

- [x] RDT.2 Define debug/replay hook points.
  - Intent: Keep future replay possible without making full replay a launch
    blocker.
  - Acceptance: Hook points cover input, resize, fake time, worker/process
    status, terminal profile, semantic snapshots, frame metadata, and rendered
    output where needed by tests.
  - Evidence:
    [debug capture recorder](../../../packages/fleury/lib/src/debug/debug_capture.dart),
    [debug event hooks](../../../packages/fleury/lib/src/debug/debug_events.dart),
    [runtime hook emission](../../../packages/fleury/lib/src/runtime/run_tui.dart),
    [debug capture artifact API](../../../packages/fleury/lib/src/debug/debug_capture.dart),
    [debug capture tests](../../../packages/fleury/test/debug/debug_capture_test.dart),
    [runtime debug capture test](../../../packages/fleury/test/runtime/run_tui_test.dart),
    [demo app capture-to-test workflow](../../../packages/fleury_example_console/test/demo_console_test.dart).
  - Notes: Input, resize, terminal profile, frame metadata, redacted semantic
    snapshots, text-first accessibility/fallback output, output-summary
    records, safe task-event summaries, and deterministic time markers now
    have bounded hook points.
    `DebugCaptureArtifact` gives those captured records a stable enough query
    surface for targeted regression assertions without freezing a broad replay
    artifact format. `TraceTimeline` now has a reusable task-event adapter,
    giving tests and devtools a live inspectable effect-history surface with
    safe task event metadata before full replay is in scope. The demo app
    uses those hooks to capture and assert a command/table/worker/status
    workflow. Accessibility/fallback output now includes safe app, command,
    task, view, row/cell, and developer-document state from semantic nodes,
    which makes captured artifacts more useful without exposing arbitrary
    state maps. Typed accessibility fields now expose enabled, focused,
    selected, checked, expanded, busy, and value-redacted state directly for
    adapters and tests while preserving the existing plain-text narration.
    Accessibility capture now also serializes `AccessibilitySnapshotSummary`,
    so artifacts carry node/role/focus/error/redaction/action counts without
    requiring full tree traversal. `DebugCaptureArtifact` now exposes typed
    summary accessors for accessibility node count, role counts, focused node
    id, action count, and redaction count so regression tests do not hand-walk
    capture JSON. Task-event summaries deliberately omit raw task output,
    result values, error messages, and stack traces so artifacts can preserve
    workflow ordering without becoming unsafe logs. Time markers
    record only source, label, sequence, fake-time flag, and elapsed
    microseconds from a caller-owned clock, not wall-clock timestamps. Richer
    subprocess capture remains deferred until a concrete scenario needs it.
    RDT.2 is complete for the MVP. Full replay artifacts remain deferred to a
    later product track; the launch surface is bounded hook points plus
    targeted capture-to-test evidence.

- [x] RDT.3 Expand debug inspector.
  - Intent: Make framework internals visible while building Phase 1.
  - Acceptance: Inspector answers focus, command, semantic node, dirty region,
    effect status, frame cost, and capability fallback questions.
  - Evidence:
    [debug panel semantic summary](../../../packages/fleury/lib/src/debug/debug_panel.dart),
    [debug controller state](../../../packages/fleury/lib/src/debug/debug_state.dart),
    [debug shell key dispatch](../../../packages/fleury/lib/src/debug/debug_shell.dart),
    [debug frame events](../../../packages/fleury/lib/src/debug/debug_events.dart),
    [debug invalidation collector](../../../packages/fleury/lib/src/debug/debug_invalidation.dart),
    [runtime semantic provider](../../../packages/fleury/lib/src/runtime/run_tui.dart),
    [debug semantic summary test](../../../packages/fleury/test/debug/debug_shell_test.dart),
    [runtime debug event tests](../../../packages/fleury/test/runtime/run_tui_test.dart).
  - Notes: M1.1 added a semantic summary to the Tree tab. M1.10 first slice
    adds frame schedule reasons, Rebuilds-tab frame diagnostics, Tree-tab task
    summaries, and Tree-tab capability fallback summaries. Later M1.10 slices
    add dirty bounds from the real `runTui` diff path, a semantic graph outline,
    debug-only source-level build/layout/paint invalidation labels, and an
    on-demand terminal diagnosis provider with profile/capability rows. The
    task/effect section now aggregates task status counts and total event counts from
    semantic nodes. Bounded capture-to-test hooks now exist and are exercised by
    the demo app. The Tree tab now supports semantic cursor navigation,
    selected-node details, state/action/flag summaries, a bounded graph
    window, and inspection-protocol schema/action/focus summary over the same
    `SemanticInspectionSnapshot` serializer used by debug capture. RRE.4 adds
    layout performed/skipped counts, repaint-boundary totals, repaint/cache
    counts, and copied-cell counts to `FrameEvent`, the Live/Rebuilds tabs,
    and serialized capture frames. Deeper graph
    search/filtering remains a later enhancement,
    but the MVP inspector now answers focus, command, semantic node, dirty
    region, effect status, frame cost, repaint-boundary behavior, and
    capability fallback questions. Current lifecycle hardening clears live
    provider hooks on `DebugController.dispose`, keeps final inspector state
    readable for diagnostics, and rejects stale debug-shell mutations after
    teardown.

- [x] RDT.4 Create targeted capture-to-test flow.
  - Intent: Turn difficult bugs into tests without requiring full replay.
  - Acceptance: A captured failing scenario can produce enough structured
    evidence to write a regression test.
  - Evidence:
    [debug capture tests](../../../packages/fleury/test/debug/debug_capture_test.dart),
    [runtime debug capture test](../../../packages/fleury/test/runtime/run_tui_test.dart),
    [demo app capture-to-test workflow](../../../packages/fleury_example_console/test/demo_console_test.dart).
  - Notes: The recorder can produce a redacted JSON-shaped snapshot with
    frame/input/terminal/semantic/accessibility/output-summary/task-event/time
    marker records. The artifact query helper can then locate inputs, frame
    causes, output summaries, task-event summaries, deterministic time markers,
    semantic nodes, and accessibility text directly from that serialized shape.
    The
    demo app now drives a deterministic Runs-screen workflow through command
    invocation, resize metadata, worker start, DataTable focus/selection,
    debug capture, status semantics, accessibility narration, and
    output-summary assertions, then verifies the serialized snapshot contains
    enough app/table/status facts to seed a regression test. `SB.10` adds
    benchmark pressure around the integrated demo-app capture size and
    semantic/accessibility output after a longer app journey.

## Implementation Notes

- Testing should operate at semantic, layout, and frame levels.
- Semantic action invocation is intentionally semantic-first: tests resolve a
  current semantic node, reject disabled/unsupported actions before dispatch,
  then walk contributor-owned semantic subtrees children-first. That lets
  generated nodes such as command entries invoke through the app/scope owner
  without exposing widget internals; app-owned screen/section nodes dispatch
  through the `Semantics` callbacks the app provides.
- Lazy render-island widgets keep row-level semantic action support tied to
  mounted visible rows. Tester workflows should render before invoking
  visible-row actions after any rebuild that can remount a lazy list.
- Hierarchical widgets follow the same visible-row rule: aggregate tree/file
  nodes provide stable focus/open/copy entry points, while row-level open,
  activate, and copy act only on mounted visible rows.
- Document views expose semantic actions through their existing controller and
  sanitized copy/export paths. Row/block-level copy remains selected row or
  block oriented so semantic artifacts do not imply off-screen document rows
  are mounted.
- Workflow and modal semantic actions should reuse the existing controller,
  callback, command, or navigation path. Semantic submit/cancel/dismiss should
  not create a second workflow state machine; approval prompts follow this
  rule by dispatching through their existing decision callback.
- Future replay depends on the effects/workflow model being structured.
- Debug tools should prefer useful facts over polished UI in early phases.
- App-kernel state from [RFC 0012: App kernel](../../rfcs/0012-app-kernel.md)
  should be inspectable: active screen, active command scopes, command
  registry entries, status items, and command invocation failures.
- Frame diagnostics now carry best-effort schedule reasons such as initial,
  build, post-frame, hot-reload, debug-key, resize, key, paste, text-input, and
  mouse. These are not full causal traces, but they are enough to start
  answering "what caused the last frame?" without committing to replay files.
- Dirty diagnostics now carry an emitted-cell bounding rectangle from the real
  ANSI diff path plus best-effort build/layout/paint invalidation source
  labels. This is enough to answer "which widget or render object caused this
  frame?" for common `setState`, layout dirtiness, and render-update paths
  without committing to full replay causality.
- Repaint-boundary diagnostics are collected only while debug listeners are
  active and then attached to `FrameEvent`, giving inspector and capture users a
  cache-hit/cache-miss view without turning the paint path into a general
  profiler.
- Layout diagnostics use the same debug-only pattern: `RenderObject.layout`
  records performed versus same-constraint skipped layout calls only while a
  debug frame or scenario benchmark has enabled the collector.
- The Tree tab semantic cursor is intentionally small: Arrow Up/Down and Home
  are consumed only while the debug shell is open on the Tree tab. This makes
  semantic graph inspection usable without adding a full panel focus model.
- Capability/security state from
  [RFC 0013: Capability and security contract](../../rfcs/0013-capability-security-contract.md)
  is now inspectable through the runtime terminal profile, capability report,
  fallback count, warning count, unsupported feature rows, active/passive
  compatibility finding counts, and per-feature probe/passive status rows.
  The Tree tab now also summarizes semantic redaction, sanitized output,
  truncated output, and largest original-output length across the current
  semantic graph. Capability resolution drilldown now summarizes available,
  degraded, policy-blocked, unsupported, unsafe, and required-blocked semantic
  capability requests, with attention rows for blocked/unsafe/unsupported
  feature nodes.
- [Prototype-first tracks](../prototype-first-tracks.md) defines the first
  capture-to-test scenario: input, resize, fake time, active screen, focus,
  commands, worker state, terminal profile, frame metadata, semantic snapshot,
  and sanitized output summary.
- `DebugCaptureRecorder` is a bounded recorder over the debug event stream. It
  is a hook-point prototype, not a stable replay artifact format. Semantics
  serialization redacts node values when semantic state marks values as
  redacted, obscured, or clipboard-redacted. Accessibility capture is derived
  from the same semantic state so bug artifacts get a safe plain-text fallback
  view without inventing a second redaction path. Recorder disposal now keeps
  final captured evidence readable while rejecting post-dispose attach/record
  mutation, so capture artifacts cannot silently change after teardown.
- `DebugCaptureArtifact` is the targeted replay-hook prototype for the MVP:
  queryable evidence over a captured artifact, not event replay. It consumes
  the same diagnostic accessibility projection as tests, so terminal profile
  and capability fallback evidence can appear in safe fallback output without
  scraping rendered cells. It also consumes app-status accessibility
  projection, so debug captures can prove status count, item identity,
  severity, values, command identity, and action state from the semantic graph.
  Search/log accessibility projection now adds data-heavy widget totals,
  filtered counts, selected result/source context, log filter details, and
  source/view row positions to the same safe text-first artifact path. Workflow
  summary projection now adds aggregate workflow health, activity, context,
  trace, patch, review, and log-count state for demo-app/debug artifacts.
  Process task projection now adds command display, exit code, success/failure,
  and cancelability to the same artifact path, so process regressions have
  structured fallback evidence without scraping rendered process cells.
  The artifact query API exposes accessibility summary counters directly,
  keeping capture-to-test assertions stable without walking nested JSON maps.
  Tests can assert the facts that matter while full replay remains a later
  Phase 3 product.
- Task-event capture is metadata-only by design. It keeps event source,
  sequence, run ID, kind, status, progress totals, and output safety flags, but
  omits raw output text, result values, error messages, and stack traces.
- Time-marker capture is deterministic by design. It keeps marker source,
  label, sequence, fake-time flag, and elapsed microseconds from a caller-owned
  clock, while avoiding wall-clock timestamps and host-specific timing.
- The demo app capture-to-test workflow deliberately uses synthetic frame and
  command records with a real semantic tree. That keeps the test deterministic
  while proving the captured artifact API is sufficient to reconstruct the
  important app facts from an app-shaped scenario.

## Risks And Open Questions

- Capture artifacts could leak secrets if redaction is late.
- Too much capture detail may make artifacts large and unstable.
- Semantic APIs must not freeze immature internals too early.

## Acceptance Evidence

- [semantic tests](../../../packages/fleury/test/semantics/semantics_test.dart).
- [app semantic tests](../../../packages/fleury/test/app/fleury_app_test.dart).
- [navigator semantic tests](../../../packages/fleury/test/widgets/navigator_test.dart).
- [control semantic tests](../../../packages/fleury_widgets/test/controls_test.dart).
- [button semantic tests](../../../packages/fleury_widgets/test/button_test.dart).
- [DataTable semantic tests](../../../packages/fleury_widgets/test/data_table_test.dart).
- [LogRegion semantic tests](../../../packages/fleury_widgets/test/log_region_test.dart).
- [SearchPanel semantic tests](../../../packages/fleury_widgets/test/search_panel_test.dart).
- [Tree semantic tests](../../../packages/fleury_widgets/test/tree_test.dart).
- [TreeTable semantic tests](../../../packages/fleury_widgets/test/tree_table_test.dart).
- [FileBrowser semantic tests](../../../packages/fleury_widgets/test/file_browser_test.dart).
- [FilePicker semantic tests](../../../packages/fleury_widgets/test/file_picker_test.dart).
- [ColorPicker semantic tests](../../../packages/fleury_widgets/test/color_picker_test.dart).
- [NumberInput semantic tests](../../../packages/fleury_widgets/test/number_input_test.dart).
- [PasswordInput semantic tests](../../../packages/fleury_widgets/test/password_input_test.dart).
- [Tooltip semantic tests](../../../packages/fleury_widgets/test/tooltip_test.dart).
- [JsonView semantic tests](../../../packages/fleury_widgets/test/json_view_test.dart).
- [DiffView semantic tests](../../../packages/fleury_widgets/test/diff_view_test.dart).
- [CodeView semantic tests](../../../packages/fleury_widgets/test/code_view_test.dart).
- [MarkdownView semantic tests](../../../packages/fleury_widgets/test/markdown_view_test.dart).
- [form semantic tests](../../../packages/fleury_widgets/test/form_test.dart).
- [ProcessPanel semantic tests](../../../packages/fleury_widgets/test/process_panel_test.dart).
- [table semantic tests](../../../packages/fleury_widgets/test/table_test.dart).
- [dialog semantic tests](../../../packages/fleury_widgets/test/dialog_test.dart).
- [progress semantic tests](../../../packages/fleury_widgets/test/progress_bar_test.dart).
- [command semantic tests](../../../packages/fleury_widgets/test/command_palette_test.dart).
- [model status semantic tests](../../../packages/fleury_widgets/test/model_status_bar_test.dart).
- [file mention picker semantic tests](../../../packages/fleury_widgets/test/file_mention_picker_test.dart).
- [conversation navigator semantic tests](../../../packages/fleury_widgets/test/conversation_navigator_test.dart).
- [context panel semantic tests](../../../packages/fleury_widgets/test/context_panel_test.dart).
- [trace timeline semantic tests](../../../packages/fleury_widgets/test/trace_timeline_test.dart).
- [patch review semantic tests](../../../packages/fleury_widgets/test/patch_review_test.dart).
- [debug semantic summary test](../../../packages/fleury/test/debug/debug_shell_test.dart).
- [runtime restoration and debug shell tests](../../../packages/fleury/test/runtime/run_tui_test.dart).
- [debug capture tests](../../../packages/fleury/test/debug/debug_capture_test.dart).
- [debug capture artifact API](../../../packages/fleury/lib/src/debug/debug_capture.dart).
- [accessibility snapshot tests](../../../packages/fleury/test/semantics/accessibility_test.dart).
- [Prototype-first tracks](../prototype-first-tracks.md).
- [demo app capture-to-test workflow](../../../packages/fleury_example_console/test/demo_console_test.dart).
- [demo app journey benchmark](../../../packages/fleury_example_console/benchmark/scenario_benchmarks.dart).
