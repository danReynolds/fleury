# Workstream: Semantic App Graph

## Purpose

Create the durable meaning layer above cells so Fleury apps are inspectable,
testable, replayable, accessible, adaptable across UI modes, and operable by
automation or agents.

## Current State

- Fleury has widget, element, render, focus, key binding, navigator, testing,
  and debug-shell foundations.
- The first semantic implementation slice now has core semantic types, a
  `Semantics` wrapper, on-demand tester snapshots, automatic `Text`,
  `TextInput`, `TextArea`, basic control semantics, Table semantics, Dialog
  semantics, Navigator/route semantics, Progress semantics, and
  CommandPalette/Command semantics.
- The debug Tree tab can render a first semantic summary through a controller
  snapshot provider. Semantic action invocation now exists for core app
  surfaces and many first-party widgets; deeper inspector diagnostics and
  coverage for future widgets remain ongoing work.
- A text-first accessibility/fallback snapshot now derives from the semantic
  tree and preserves redaction, validation, typed focus/selection/enabled/
  checked/expanded/busy state, actions, progress, collection ranges,
  capability fallback, clipboard policy state, JSON export, and query filters.
- `AccessibilitySnapshotSummary` now exposes aggregate node, role, focus,
  selection, disabled, busy, validation-error, redaction, and action counts so
  adapters and debug capture do not have to hand-walk the tree for common
  status questions.
- `SemanticInspectionSnapshot` now exposes a schema-versioned, JSON-safe,
  redaction-aware semantic tree export with node counts, role counts, action
  totals, focused-node identity, and query helpers for tests, debug capture,
  and future automation/agent adapters. `FleuryTester` exposes the same
  inspection snapshot and JSON directly for regression tests, and semantic
  node-id lookup/action targeting now supports inspect-then-act flows. The
  debug Tree tab now consumes the same inspection snapshot for protocol
  summary and selected-node details, keeping live devtools aligned with
  capture and tester surfaces. The launch v1 inspection protocol now has
  explicit stable top-level/node field sets plus `fromJson` parsers that ignore
  additive future fields, recompute summaries from parsed roots, and reapply
  redaction flags on parse.
- `FormPromptSession` now exposes semantic and accessibility snapshots so
  prompt-mode fallback uses the same meaning layer as visual forms.
- Visual `FormPanel` fields now use the same safe display/redaction state as
  prompt-mode forms through `FormSnapshot` / `FormFieldSnapshot`, including
  typed value-redaction signals for accessibility snapshots.
- Numeric form fields now carry number-specific state through visual and
  prompt-mode form semantics: field type, min/max, decimal policy, negative
  policy, safe display value, validation errors, and accessibility output.
- Date form fields now carry date-specific state through visual and
  prompt-mode form semantics: field type, first/last bounds, week-start
  policy, safe display value, validation errors, and accessibility output.
- Multi-select form fields now carry list-specific state through visual and
  prompt-mode form semantics: selected option count, min/max selected bounds,
  safe display labels, disabled/unknown-option validation, and accessibility
  output.
- Path form fields now carry path-specific state through visual and
  prompt-mode form semantics: file/directory/any path kind, existence policy,
  relative-path policy, safe display value, validation errors, and
  accessibility output.
- Async form validation now carries validating state through visual and
  prompt-mode form semantics: form-level busy state, field-level busy state,
  async-validator availability, validation errors, stale-result cancellation,
  and accessibility output.
- Wizard/page-flow forms now carry the same form and field semantics while
  adding step metadata: layout `wizard`, total/visible field counts, step
  count, current step id/title/index, back/forward availability, and async
  next/submit actions over the shared form controller. The text-first
  accessibility/fallback projection now allow-lists the same wizard facts so
  adapters and debug capture can describe the active page flow without
  dumping arbitrary semantic state.
- Numeric input controls now have first-party semantic roles:
  `SemanticRole.spinButton` for `Stepper` and `SemanticRole.slider` for
  `RangeSlider`, including value/bounds/step state and increment/decrement
  actions.
- `DatePicker` now has `SemanticRole.datePicker`, safe selected-date,
  visible-month, bound, and week-start state, plus semantic focus and day
  increment/decrement actions.
- `ApprovalPrompt` now has `SemanticRole.approval`, safe approval request
  state, and semantic submit/cancel actions for protocol-neutral approval
  workflows.
- `MessageList` now has `SemanticRole.messageList` and
  `SemanticRole.message`, safe message role/status/author/identity state,
  semantic focus/navigation, row activation, selected-message copy actions,
  and refresh-stable selected-message state for protocol-neutral transcript
  workflows that are not following the tail. The demo app now uses durable
  transcript event IDs for message semantics, so selected transcript identity
  survives live appends, scrollback trimming, and screen changes.
- `ToolCallCard` now has `SemanticRole.toolCall`, safe tool name/status/
  argument/progress/output state, and semantic copy/cancel actions for
  protocol-neutral execution workflows.
- `TaskGraph` now has `SemanticRole.taskGraph` plus task-node semantics for
  compact plan/task workflows, including status, dependency, progress,
  aggregate focus/navigation, selected-node copy state, and refresh-stable
  selected-task identity.
- `ModelStatusBar` and `TokenMeter` now have `SemanticRole.modelStatus` and
  `SemanticRole.tokenMeter`, safe model/runtime/context-window state, and
  text-first fallback summaries for model/provider/status/mode, latency, queue
  depth, token totals, and context usage.
- `FileMentionPicker` now has `SemanticRole.fileMentionPicker` and
  `SemanticRole.fileMention`, safe file path/kind/language/location/mention
  state, aggregate query focus/result navigation, semantic activate/copy
  actions, refresh-stable selected-mention identity, and text-first fallback
  summaries for composer file-reference workflows.
- `ConversationNavigator` now has `SemanticRole.conversationNavigator` and
  `SemanticRole.conversation`, safe thread/session identity, status,
  unread/message count, pinned/selected state, semantic
  focus/navigation/activate/copy actions, refresh-stable selected-conversation
  identity, and text-first fallback summaries for protocol-neutral
  conversation workflows.
- `ContextPanel` now has `SemanticRole.contextPanel` and
  `SemanticRole.contextItem`, safe context item identity, kind, token count,
  priority, pinned/source state, selected item state, semantic
  focus/navigation/activate/copy actions, refresh-stable selected item state,
  and text-first fallback summaries for model-context workflows.
- `TraceTimeline` now has `SemanticRole.traceTimeline` and
  `SemanticRole.traceEvent`, safe trace event identity, kind, status, source,
  duration, selected trace state, semantic focus/navigation/activate/copy
  actions, refresh-stable selected trace state, and text-first fallback
  summaries for workflow/debug timelines.
- `PatchReview` now has `SemanticRole.patchReview` and
  `SemanticRole.patchFile`, safe patch identity, review/file status, file stats,
  selected-file state, semantic focus/navigation/activate/copy actions,
  refresh-stable selected-file state, and text-first fallback summaries for
  code-review workflows.
- `WorkflowSnapshot` now aggregates protocol-neutral workflow records into
  `WorkflowSummary` / `WorkflowHealth` and can publish safe workflow count,
  health, activity, failure, model, context, conversation, trace, patch, and
  log summary state through `SemanticState`. The demo app Overview screen uses
  this to expose a reference workflow summary without introducing a provider or
  ACP schema. The text-first accessibility/fallback projection now summarizes
  that workflow state through an allow-listed `workflow ...` state line rather
  than requiring consumers to inspect raw state maps.
- `Toaster` notifications now have `SemanticRole.notification`, safe severity,
  stack position, auto-dismiss, and action-key state, plus semantic dismiss and
  optional activate actions over the same paths as visible hotkeys.
- `Tabs` now have `SemanticRole.tab` nodes with selected/focused state,
  focus/select/activate actions, tab position/count, shortcut fallback state,
  and semantic actions routed through the same controller path as keyboard tab
  switching.
- `IndexedStack` now exposes only its active child to semantic collection and
  semantic-action dispatch, so preserved off-screen page state does not leak
  hidden controls into tester, accessibility, debug, or future adapter views.
- `Menu` now has semantic trigger/button, menu, and menu-item nodes with
  focus/open/close/activate actions, submenu expanded state, item
  position/count, and text-first fallback summaries for overlay menu workflows.
  Menu item rows follow existing lazy-list semantics: render/layout mounts the
  visible row nodes before row-level semantic assertions or actions target them.
- `Select` now follows the same overlay-control contract with semantic trigger,
  option-list, and option-row nodes, focus/open/close/select/activate actions,
  selected value state, disabled-option state, checked applied-option state, and
  text-first fallback summaries for option position/count.
- `Autocomplete` now exposes its underlying `TextInput` semantics through
  placeholder labels and adds semantic suggestion-menu/menu-item nodes with
  close/select/activate actions, query state, suggestion count, selected
  suggestion state, and text-first fallback summaries for suggestion
  position/count.
- `FilePicker` now aligns the legacy/simple filesystem selector with
  `Tree`/`FileBrowser` semantics: a semantic tree root carries the current
  directory and selected-entry state, tree-item rows carry sanitized path/type
  state, and focus/navigation/open actions route through the existing keyboard
  navigation and file-selection behavior.
- `ColorPicker` now exposes the palette as a semantic list and each swatch as
  a radio-like semantic option with checked/selected state, color metadata,
  semantic select/activate actions, and custom semantic color labels for
  app-owned palettes.
- `TextInput` now supports additive `semanticLabel` and `semanticState`
  parameters so specialized text fields can publish stable domain facts while
  preserving core editing semantics. `NumberInput` uses that seam for
  constrained numeric text-field state, parsed value, bounds, number policy,
  and semantic submit clamping without using spin-button semantics.
- `PasswordInput` now uses the same text-field semantic seam for secret-field
  metadata, preserving redacted values and redacted clipboard policy while
  allowing app-specific credential facts.
- `Tooltip` now exposes focus-triggered help as semantic information: the
  wrapper region carries a sanitized message value/hint and visible state, and
  the overlay contributes a text node only while the tooltip is shown.
- Debug capture now serializes accessibility/fallback output from captured
  semantic trees, giving regression artifacts a safe plain-text view.
- Process task accessibility/fallback now projects command display, exit code,
  success/failure, and cancelability from existing `ProcessPanel` semantic
  state, so process screens stay understandable in prompt fallback and debug
  artifacts without scraping rendered cells.
- [RFC 0013: Capability and security contract](../../rfcs/0013-capability-security-contract.md)
  defines the capability/fallback/security state that semantic nodes should
  surface.
- Custom semantic proxy elements now rebuild their child subtree when updated,
  which keeps semantic snapshots current after parent `setState` calls in app
  shell, command scope, status, and demo-app workflows.
- Navigator route semantics now prune child semantics for inactive/leaving
  routes while keeping route nodes mounted, so preserved route state does not
  leak stale modal controls or command actions into semantic queries.
- Navigator and active route semantic close/dismiss actions now dispatch
  through `NavigatorState.maybePop`, preserving the same `PopScope` and back
  behavior as keyboard-driven navigation.

## Target Capabilities

- Semantic nodes for controls, numeric controls, date controls, text fields,
  tables, dialogs, approval prompts, message transcripts, routes, progress,
  commands, tool calls, task graphs, model status, token/context meters,
  file mention pickers, conversation navigators, context panels, trace
  timelines, patch reviews, notifications,
  validation errors,
  selections, and data regions.
- Tester queries by role, label, value, focus, action, and state.
- Tester action invocation by semantic node id for automation-style
  inspect-then-act flows.
- Inspector view for semantic graph alongside widget/render/focus state.
- Prompt-mode, accessibility, replay, and agent operation use the same
  semantic source of truth.
- Text-first accessibility/fallback snapshots can produce JSON and plain-text
  narration without inspecting rendered cells.
- Accessibility snapshots expose adapter-friendly summary and lookup helpers
  for focused node, source id, actionable nodes, validation errors, and
  redacted values.
- Semantic inspection snapshots expose a bounded machine-readable protocol for
  automation and agents without requiring consumers to depend on debug-capture
  artifacts or raw widget/render internals.

## Milestone Checklist

- [x] SAG.1 Write semantic app graph RFC.
  - Intent: Define node shape, ownership, lifecycle, and query model.
  - Acceptance: RFC covers roles, labels, values, focus, actions, selection,
    errors, routes, tables, progress, and capability requirements.
  - Evidence: [RFC 0011: Semantic app graph](../../rfcs/0011-semantic-app-graph.md).
  - Notes: Keep public fields minimal; leave room for internal evolution.

- [x] SAG.2 Implement semantic node model v0.
  - Intent: Add core data structures without forcing every widget to adopt
    semantics immediately.
  - Acceptance: Nodes can be attached, updated, queried, and inspected in
    tests.
  - Evidence:
    [semantic core types](../../../packages/fleury/lib/src/semantics/semantics.dart),
    [tester snapshot API](../../../packages/fleury/lib/src/testing/fleury_tester.dart),
    [semantic tests](../../../packages/fleury/test/semantics/semantics_test.dart).
  - Notes: Initial implementation uses an on-demand element-tree collector and
    manual `Semantics` wrapper. Stable app IDs are supported; element-derived
    IDs are frame-local.

- [x] SAG.3 Add semantics to first widgets.
  - Intent: Prove the model with common and strategic widgets.
  - Acceptance: Button, Text, TextInput, TextArea, Table, Dialog, Navigator,
    Progress, and Command expose v0 semantics.
  - Evidence:
    [Text semantics](../../../packages/fleury/lib/src/widgets/basic.dart),
    [TextInput semantics](../../../packages/fleury/lib/src/widgets/text_input.dart),
    [TextArea semantics](../../../packages/fleury/lib/src/widgets/text_area.dart),
    [Navigator semantics](../../../packages/fleury/lib/src/widgets/navigator.dart),
    [control semantics](../../../packages/fleury_widgets/lib/src/controls.dart),
    [Table semantics](../../../packages/fleury_widgets/lib/src/table.dart),
    [Dialog semantics](../../../packages/fleury_widgets/lib/src/dialog.dart),
    [Progress semantics](../../../packages/fleury_widgets/lib/src/progress_bar.dart),
    [Command palette semantics](../../../packages/fleury_widgets/lib/src/command_palette.dart),
    [semantic tests](../../../packages/fleury/test/semantics/semantics_test.dart),
    [navigator semantic tests](../../../packages/fleury/test/widgets/navigator_test.dart),
    [control semantic tests](../../../packages/fleury_widgets/test/controls_test.dart),
    [button semantic tests](../../../packages/fleury_widgets/test/button_test.dart),
    [table semantic tests](../../../packages/fleury_widgets/test/table_test.dart),
    [dialog semantic tests](../../../packages/fleury_widgets/test/dialog_test.dart),
    [approval prompt tests](../../../packages/fleury_widgets/test/approval_prompt_test.dart),
    [message list tests](../../../packages/fleury_widgets/test/message_list_test.dart),
    [tool call card tests](../../../packages/fleury_widgets/test/tool_call_card_test.dart),
    [task graph tests](../../../packages/fleury_widgets/test/task_graph_test.dart),
    [model status tests](../../../packages/fleury_widgets/test/model_status_bar_test.dart),
    [file mention picker tests](../../../packages/fleury_widgets/test/file_mention_picker_test.dart),
    [file picker tests](../../../packages/fleury_widgets/test/file_picker_test.dart),
    [number input tests](../../../packages/fleury_widgets/test/number_input_test.dart),
    [password input tests](../../../packages/fleury_widgets/test/password_input_test.dart),
    [tooltip tests](../../../packages/fleury_widgets/test/tooltip_test.dart),
    [conversation navigator tests](../../../packages/fleury_widgets/test/conversation_navigator_test.dart),
    [context panel tests](../../../packages/fleury_widgets/test/context_panel_test.dart),
    [trace timeline tests](../../../packages/fleury_widgets/test/trace_timeline_test.dart),
    [patch review tests](../../../packages/fleury_widgets/test/patch_review_test.dart),
    [progress semantic tests](../../../packages/fleury_widgets/test/progress_bar_test.dart),
    [color picker tests](../../../packages/fleury_widgets/test/color_picker_test.dart),
    [command semantic tests](../../../packages/fleury_widgets/test/command_palette_test.dart).
  - Notes: First-widget coverage is complete for M1.1. Virtualized/off-screen
    data semantics and semantic action invocation have since moved through
    later RDT/DVW hardening slices. The
    latest route semantics slices keep inactive/leaving route nodes visible but
    exclude their child semantics, then route active navigator/route
    close/dismiss actions through `maybePop` so semantic automation cannot
    bypass `PopScope` guards. The first
    protocol-neutral approval prompt now exposes approval role/state and
    submit/cancel actions through the same semantic layer. `MessageList` adds
    transcript-specific roles without importing provider or ACP schemas.
    `ToolCallCard` adds execution-specific role/state over app-owned task or
    process runners without importing protocol transport models. `TaskGraph`
    adds compact plan/task semantics without owning scheduling or dependency
    execution. `ModelStatusBar` and `TokenMeter` add model/runtime and
    context-window semantics without owning provider sessions, transport,
    quotas, or billing policy. `FileMentionPicker` adds composer
    file-reference semantics, query focus, result navigation, and selected
    mention identity preservation without owning filesystem indexing, language
    server symbol resolution, provider context stores, or protocol content
    blocks. `ConversationNavigator` adds thread/session navigation semantics
    without owning provider session stores, transport models, app routing, or
    ACP thread schemas. `ContextPanel` adds context-pack item/budget semantics
    without owning retrieval, provider context stores, pruning, billing, or ACP
    content-block models. `TraceTimeline` adds workflow/debug event semantics
    without owning full replay logs, distributed tracing protocols, provider
    transport streams, or ACP replay fixtures. `PatchReview` adds patch/file
    review semantics while composing `DiffView`, without owning git operations,
    patch application, provider review APIs, merge policy, or ACP content-block
    models. `WorkflowSnapshot` adds safe aggregate workflow state over these
    records without owning routing, persistence, provider sessions, task
    execution, transcript storage, or adapter schemas.

- [x] SAG.4 Expose semantic queries in `FleuryTester`.
  - Intent: Make semantic testing a visible developer win.
  - Acceptance: Tests can locate nodes by role, label, action, value, focus,
    validation state, and selection state.
  - Evidence:
    [tester snapshot API](../../../packages/fleury/lib/src/testing/fleury_tester.dart),
    [semantic tree queries](../../../packages/fleury/lib/src/semantics/semantics.dart),
    [semantic tests](../../../packages/fleury/test/semantics/semantics_test.dart).
  - Notes: The first query API is `tester.semantics().where/single`, not a
    large finder DSL. It filters role, label, value, action, focus, selected,
    enabled, checked, busy, validation error, capability requirement, and
    active fallback.

- [x] SAG.5 Add text-first accessibility/fallback snapshot.
  - Intent: Convert semantic trees into portable narration/fallback evidence
    for tests, prompt mode, debug capture, and future accessibility adapters.
  - Acceptance: Snapshot preserves roles, labels, safe values, validation,
    focus/selection, actions, progress, collection ranges, capability fallback,
    clipboard policy, JSON export, and plain-text output while redacting secret
    values.
  - Evidence:
    [accessibility snapshot model](../../../packages/fleury/lib/src/semantics/accessibility.dart),
    [tester accessibility snapshot API](../../../packages/fleury/lib/src/testing/fleury_tester.dart),
    [accessibility snapshot tests](../../../packages/fleury/test/semantics/accessibility_test.dart),
    [form prompt fallback tests](../../../packages/fleury_widgets/test/form_test.dart).
  - Notes: This is not a full screen-reader bridge. It deliberately uses the
    same semantic graph as testing and debug capture so fallback modes do not
    reinterpret rendered cells or leak redacted values. The first prompt-mode
    consumer is `FormPromptSession`, which now exposes active prompt, prompt
    position, validation, options, and secret redaction through this projection.
    Debug capture now serializes the same projection for captured semantic
    trees or explicit accessibility snapshots. The projection now includes
    allow-listed app, command, task, output-safety, view, row/cell, and
    developer-document state so fallback output can describe real production
    app surfaces without dumping arbitrary semantic-state keys. Workflow
    summary regions now add an allow-listed aggregate line for workflow
    ID/title/health, activity counts, model status, context, file mentions,
    conversations, traces, patches, review issues, and log warnings/errors.
    The current API
    stabilization slice adds typed `AccessibilityNode` fields and
    `AccessibilitySnapshot.where/single` filters for enabled, focused,
    selected, checked, expanded, busy, value-redacted, action, value,
    validation, and state queries, so adapters and tests do not have to parse
    narration strings for launch-critical facts.
    Visual forms now feed the same redaction keys into accessibility snapshots
    as prompt-mode forms, so secret fields can be queried through
    `valueRedacted: true` without depending on layout mode.
    Numeric form fields now use the same semantic and accessibility path as
    other form fields, including number bounds and prompt-mode parse errors.
    Date form fields now reuse that path with date-only display values,
    first/last bounds, week-start policy, and prompt-mode parse/bounds errors.
    Multi-select form fields now reuse that path with safe selected labels,
    selected-option counts, min/max selected bounds, disabled/unknown-option
    validation, and prompt-mode comma-separated parsing.
    Path form fields now reuse that path with safe display values,
    file/directory/any path kind, existence and absolute-path policy state,
    filesystem validation errors, and prompt-mode parsing.
    Async validation now reuses the same path with busy form/field semantics,
    `hasAsyncValidator` state, text-first accessibility output, visual
    semantic-submit waiting, prompt-mode `submitCurrentAsync`, and stale async
    result cancellation.
    Wizard/page-flow now reuses the same field projection by filtering
    `FormPanel` over the active step, while the outer `FormWizard` publishes
    aggregate form state, step metadata, and semantic increment/decrement/
    submit/cancel actions. Current fallback slice adds visible field count,
    step position/count, current step id/title, and back/forward availability
    to the allow-listed form fallback text.
    Current adapter-facing slice adds `AccessibilitySnapshotSummary` and
    direct snapshot selectors for focused nodes, semantic source ids,
    actionable nodes, validation-error nodes, and value-redacted nodes. Debug
    capture now serializes the same summary next to plain-text output and the
    tree root. Date controls now add allow-listed date state to the same
    fallback projection without dumping arbitrary widget state. Approval
    prompts now add allow-listed request, subject, detail count, and action
    label state for text-first fallback output. Message nodes now add
    allow-listed role, status, author, and message ID state. Tool-call nodes
    now add allow-listed ID, tool name, status, argument count, cancellation,
    progress, and safe output state. Task graph nodes now add allow-listed
    graph counts, task status, dependency count, progress, and selected task
    state. Model status and token-meter nodes now add allow-listed model
    name/provider/status/mode, latency, queue depth, token totals,
    context-window usage, and near/over-limit state. File mention nodes now
    add allow-listed file path, kind, language, line/column, mention text, and
    selected file state. Conversation nodes now add allow-listed conversation
    ID, status, unread/message counts, pinned state, and selected conversation
    state. Context nodes now add allow-listed context item ID, kind, token
    count, priority, pinned/source state, selected context item state, and
    aggregate context item/token counts. Trace nodes now add allow-listed trace
    ID, kind, status, source, duration, selected trace ID, and aggregate trace
    count state. Patch-review nodes now add allow-listed patch ID, patch/file
    status, selected file path, file counts, addition/deletion counts, hunk
    counts, and review-state counts. Notification nodes now add allow-listed
    severity, stack position, auto-dismiss timing, and optional action
    label/key state. Password input nodes now expose allow-listed secret-field
    state while preserving value redaction. Tooltip nodes expose their
    sanitized help text as region hint/value plus overlay-visible state
    without inventing actions for an informational surface. Diagnostic nodes
    now add allow-listed terminal profile, capability-row count,
    fallback/warning/unsupported counts, debug-capture count, streaming state,
    and OSC policy state for demo-app diagnostics and future adapter output.
    App status bars now add allow-listed item count, item ID, severity, value,
    command identity, and action state for prompt fallback, debug capture, and
    future adapter output.
    Search and log surfaces now add allow-listed result/entry totals, filtered
    counts, selected index/category/source, log filter state, copy-prefix
    policy, and source/view row indexes while preserving generic severity
    fallback text for non-status widgets.
    Gauge, Sparkline, BarChart, Histogram, Heatmap, CalendarHeatmap, and
    interactive LineChart now publish `SemanticRole.chart` with typed chart
    state for type, counts, ranges, latest values, date ranges, week-start
    policy, references, cursor position, and semantic cursor actions. `Digits`
    publishes its underlying value as semantic text so block-rendered counters
    and clocks are inspectable without cell scraping.
    Generic `Canvas` drawing surfaces now expose opt-in image/chart semantics
    with marker and logical-bounds state when app code supplies semantic
    meaning, while default canvases remain silent to avoid duplicate semantics
    under higher-level visual widgets.
    The demo app Overview telemetry strip proves these visual dashboard
    surfaces are not silent in semantic snapshots or fallback output.
    Process task fallback now includes command display, exit code,
    success/failure, and cancelability from existing task semantic state, which
    keeps `ProcessPanel` useful to prompt fallback, debug capture, and future
    adapters without adding a process-specific accessibility model.
    SAG.5 is complete for the MVP. Future role-specific fallback summaries
    should be evidence-driven hardening work, while native platform accessibility
    adapters remain a later evidence-backed track.

- [x] SAG.6 Add stable semantic inspection snapshot v1.
  - Intent: Give tests, debug capture, and future automation adapters a safe
    machine-readable semantic graph without scraping rendered cells.
  - Acceptance: A semantic tree can produce and parse schema-versioned JSON
    with node count, role counts, action count, focused node id, redacted
    values, sanitized strings, structured state, query helpers, explicit stable
    field sets, additive future-field tolerance, and inspect-then-act support.
  - Evidence:
    [semantic inspection snapshot](../../../packages/fleury/lib/src/semantics/inspection.dart),
    [tester inspection API](../../../packages/fleury/lib/src/testing/fleury_tester.dart),
    [semantic inspection tests](../../../packages/fleury/test/semantics/inspection_test.dart),
    [debug capture integration](../../../packages/fleury/lib/src/debug/debug_capture.dart),
    [debug capture tests](../../../packages/fleury/test/debug/debug_capture_test.dart).
  - Notes: The launch v1 protocol is stable at the envelope/node-field level,
    while richer role-specific state can continue to mature through
    evidence-driven evidence. Debug capture consumes the same serializer and now
    exposes a parsed `SemanticInspectionSnapshot`, so semantic JSON has one
    redaction/sanitization boundary and one parser boundary. `FleuryTester`
    exposes the same inspection shape so tests can verify adapter-facing
    semantic JSON without creating capture artifacts. Current actionability
    slices add node-id lookup to `SemanticTree` /
    `SemanticInspectionSnapshot`, let `FleuryTester.invokeSemanticAction`
    target an inspected semantic node id directly, make the debug Tree tab
    render selected-node details through inspection nodes, and prove an
    adapter-shaped flow that parses semantic JSON before invoking an advertised
    action by node id.

## Implementation Notes

- Treat semantics as a framework layer, not as a debug-only add-on.
- Semantic snapshots are collected on demand for now so Phase 1 can prove the
  model without adding every-frame runtime cost.
- The render tree should not be the only source of semantic truth for
  workflow objects such as commands, workers, approvals, permissions, and
  routes.
- Do not model every future accessibility field in v0; model enough to unlock
  testing, inspection, and prompt fallback.
- Draft SAG.1 against the developer operations console in
  [demo-app-scenario.md](../demo-app-scenario.md): sidebar routes,
  command palette commands, table rows/cells, composer value, progress state,
  diagnostics, focus, selection, and debug-capture action are the first
  semantic pressure points.
- Capability resolution should appear as semantic state on affected widgets
  and diagnostics regions, not only in human-readable logs.
- The progressive interaction prototype in
  [prototype-first-tracks.md](../prototype-first-tracks.md) should consume
  semantic nodes for labels, values, validation, focus, required state,
  password/redaction policy, and submit/cancel actions rather than inventing a
  separate prompt-mode metadata model.
- The first debug integration is intentionally summary-level: the debug
  controller exposes a nullable semantic-tree provider, `runTui` wires it to
  the current root element, and the Tree tab reports semantic node count,
  focused node, and role counts. Rich browsing and capture remain RDT work.
- Semantic proxy components must call the framework update path and rebuild
  children when their widget changes. Without that, parent state changes can
  update a semantic wrapper but leave its subtree stale.
- Accessibility snapshots should stay semantic-derived and text-first. Native
  platform adapters can translate the same snapshot later, but launch should
  avoid claiming OS integration until real adapter evidence exists.
- Summary counts should describe the safe accessibility projection, not raw
  semantics. For example, validation errors on redacted nodes stay omitted from
  the accessibility summary just as they are omitted from node narration.
- Prompt-mode projections should expose semantic trees directly where they do
  not mount widgets. That keeps fallback modes first-class without forcing
  invisible widget trees only to recover semantics.

## Risks And Open Questions

- Public API surface could harden too early.
- Semantic updates may create runtime overhead if invalidation is too broad.
- Tables and virtualized views need semantics for off-screen items without
  pretending every row is mounted as a widget.

## Acceptance Evidence

- [RFC 0011: Semantic app graph](../../rfcs/0011-semantic-app-graph.md).
- [semantic core types](../../../packages/fleury/lib/src/semantics/semantics.dart).
- [accessibility snapshot model](../../../packages/fleury/lib/src/semantics/accessibility.dart).
- [semantic tests](../../../packages/fleury/test/semantics/semantics_test.dart).
- [accessibility snapshot tests](../../../packages/fleury/test/semantics/accessibility_test.dart).
- [form prompt fallback tests](../../../packages/fleury_widgets/test/form_test.dart).
- [date picker semantic tests](../../../packages/fleury_widgets/test/date_picker_test.dart).
- [approval prompt tests](../../../packages/fleury_widgets/test/approval_prompt_test.dart).
- [message list tests](../../../packages/fleury_widgets/test/message_list_test.dart).
- [tool call card tests](../../../packages/fleury_widgets/test/tool_call_card_test.dart).
- [task graph tests](../../../packages/fleury_widgets/test/task_graph_test.dart).
- [model status tests](../../../packages/fleury_widgets/test/model_status_bar_test.dart).
- [file mention picker tests](../../../packages/fleury_widgets/test/file_mention_picker_test.dart).
- [conversation navigator tests](../../../packages/fleury_widgets/test/conversation_navigator_test.dart).
- [context panel tests](../../../packages/fleury_widgets/test/context_panel_test.dart).
- [trace timeline tests](../../../packages/fleury_widgets/test/trace_timeline_test.dart).
- [patch review tests](../../../packages/fleury_widgets/test/patch_review_test.dart).
- [debug capture accessibility tests](../../../packages/fleury/test/debug/debug_capture_test.dart).
- [control semantic tests](../../../packages/fleury_widgets/test/controls_test.dart).
- [button semantic tests](../../../packages/fleury_widgets/test/button_test.dart).
- [table semantic tests](../../../packages/fleury_widgets/test/table_test.dart).
- [dialog semantic tests](../../../packages/fleury_widgets/test/dialog_test.dart).
- [progress semantic tests](../../../packages/fleury_widgets/test/progress_bar_test.dart).
- [command semantic tests](../../../packages/fleury_widgets/test/command_palette_test.dart).
- [debug semantic summary test](../../../packages/fleury/test/debug/debug_shell_test.dart).
