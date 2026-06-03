# Fleury Implementation Milestones

**Status legend:** `[ ]` not started, `[~]` in progress, `[x]` complete,
`[!]` blocked or needs decision.

## Phase Scorecards

These targets are planning instruments. Revise them when real usage and
benchmark data arrive.

| Phase | Success scorecard |
| --- | --- |
| Phase 0 | Example subpackage proof-app scenario committed; three architecture RFCs complete; peer scorecard skeleton exists; benchmark scenario list exists. |
| Phase 1 | Example subpackage is created early and proves the MVP slice continuously; semantic tree, app kernel, text editing core, DataTable, agent-adapter readiness boundary, and benchmark harness are usable; time-to-counter-app target is defined and measured. |
| Phase 2 | Dune/`dune_cli` first integration slice begins after the core is proven; targeted debug-capture/replay hooks are validated where needed; public package/distribution/docs assets are credible; benchmarks are compared against current peers. |
| Phase 3 | Fleury has maintained showcase apps, repeatable peer benchmarks, and a visible ecosystem story beyond Dune. |

## Phase 0: Architecture Guardrails And Scenario Lab

**Goal:** Decide the core contracts that would be expensive to retrofit after
large widget and app-shell work, without spending months writing RFCs before
implementation.

- [x] M0.1 Example subpackage proof-app scenario spec
  - Intent: Define the realistic workflow that will prove Fleury in this cycle.
  - Implementation context: Use an example subpackage as the forcing example
    for sidebar navigation, streamed content, composer/input, commands,
    status, output/log regions, one dense data surface, selection, capability
    fallbacks, and debug capture.
  - Acceptance: Scenario identifies the Phase 1 proof-app slice and the Fleury
    primitives it must validate.
  - Evidence: [Proof-app scenario](proof-app-scenario.md).
  - Notes: Completed as a developer operations console scenario. Dune/`dune_cli`,
    tool calls, approvals, ACP, and full replay are not current-cycle blockers.

- [x] M0.2 Semantic app graph RFC
  - Intent: Define the durable meaning layer above rendered cells.
  - Implementation context: Start from Button, Text, TextInput, TextArea,
    Table, Dialog, Navigator, Progress, and Command.
  - Acceptance: `FleuryTester` can query role, label, value, focus, action,
    error state, and selection state in the RFC examples.
  - Evidence: [RFC 0011: Semantic app graph](../rfcs/0011-semantic-app-graph.md).
  - Notes: This is the first architecture gate because it affects testing,
    accessibility, replay, prompt fallback, and agent operation. Draft it
    against the M0.1 proof-app scenario rather than as an abstract taxonomy.

- [x] M0.3 App kernel RFC
  - Intent: Define the application framework layer.
  - Implementation context: Cover `FleuryApp`, screens, command registry,
    actions, shortcut scopes, command palette structure, status binding,
    lifecycle, and proof-app needs.
  - Acceptance: RFC defines how commands, focus, navigation, status, and app
    lifecycle compose.
  - Evidence: [RFC 0012: App kernel](../rfcs/0012-app-kernel.md).
  - Notes: This is the framework boundary that turns widgets into apps. It
    preserves existing `Navigator` and `KeyBindings` while adding app-level
    screens, commands, status, lifecycle, and semantic contributions.

- [x] M0.4 Capability and security contract RFC
  - Intent: Let widgets declare required, preferred, and optional terminal
    capabilities plus fallback behavior, while defining safe defaults for
    untrusted output.
  - Implementation context: Build on existing terminal capability types,
    drivers, width resolver, input parser, renderer, text sanitizer, and
    output capture.
  - Acceptance: RFC covers colors, mouse, keyboard protocols, clipboard,
    links, images, tmux/SSH awareness, diagnostic reporting, raw ANSI, OSC 52,
    OSC 8, markdown, subprocess output, malformed Unicode, huge lines, and
    secret redaction hooks.
  - Evidence:
    [RFC 0013: Capability and security contract](../rfcs/0013-capability-security-contract.md).
  - Notes: Completed as a combined capability requirement and output-security
    contract. Phase 1 should implement requirement resolution,
    `fleury diagnose --json`, restricted ANSI parsing, policy-gated
    clipboard/links/images, redaction hooks, and semantic/inspector exposure.

- [x] M0.5 Scenario benchmark lab
  - Intent: Define the workloads that will validate performance claims.
  - Implementation context: Use text editing, 100k-row tables, log tailing,
    streaming markdown, dashboard updates, resize storms, overlay churn,
    subprocess handoff, and streaming content/logs.
  - Acceptance: Benchmark scenarios have names, target metrics, fixture
    shape, peer comparison targets, and pass/fail thresholds to refine during
    implementation.
  - Evidence: [Scenario benchmark lab](scenario-benchmark-lab.md).
  - Notes: Performance posture is scenario-first. The lab preserves existing
    microbenchmarks while adding app-shaped workloads and peer targets from
    Nocterm, Ratatui, OpenTUI, Textual, Bubble Tea, and Ink.

- [x] M0.6 Peer scorecard skeleton
  - Intent: Track moving targets instead of stale peer assumptions.
  - Implementation context: Include Nocterm, Bubble Tea v2, Textual, OpenTUI,
    Ratatui, and Ink.
  - Acceptance: Scorecard template records versions, source links, claims,
    known gaps, benchmark targets, and Fleury differentiators.
  - Evidence: [Peer scorecards](peer-scorecards.md).
  - Notes: First source-linked snapshot captured current package/release refs,
    source links, claims to verify, known gaps, scenario benchmark mappings,
    and the 2026-Q2 comparison skeleton. Update at phase boundaries and major
    peer releases.

- [x] M0.7 Prototype-first tracks for progressive modes, replay, and effects
  - Intent: Avoid over-standardizing before implementation teaches the shape.
  - Implementation context: Prototype against the example subpackage and
    Phase 1 widgets before writing full RFCs.
  - Acceptance: Each track has a narrow prototype scenario and defers broad
    API commitments.
  - Evidence: [Prototype-first tracks](prototype-first-tracks.md).
  - Notes: Progressive forms, debug capture/future replay, structured
    effects/workers, and subprocess handoff each have a narrow prototype
    scenario, explicit non-frozen APIs, and Phase 1 hand-off points. Full
    replay is not a Phase 1 requirement.

- [x] M0.8 Agent adapter and `fleury_acp` package boundary
  - Intent: Define what Fleury launch must expose for future domain adapters.
  - Implementation context: Model protocol-neutral sessions, plans, tasks,
    approvals, diffs, terminal output, cancellation, progress, status, and
    transcript regions without importing ACP concepts.
  - Acceptance: Boundary shows how `fleury_acp` can map ACP transport and
    ACP-specific widgets onto Fleury semantics, actions, effects, capability
    policy, and debug/replay hook points after launch.
  - Evidence: [Agent adapter boundary](agent-adapter-boundary.md).
  - Notes: ACP transport, protocol models, JSON-RPC handling, ACP replay
    fixtures, and ACP-specific widgets are not launch scope. Fleury launch
    owns protocol-neutral semantics, commands, effects, output regions,
    selection/copy, capability/security policy, and debug-capture hooks.

**Exit criteria:**

- [x] Semantic testing, prompt fallback, replay, and capability-aware widgets
  share one coherent set of contracts through RFC 0011, RFC 0012, RFC 0013,
  the prototype-first tracks, and the agent-adapter boundary.
- [x] Every Phase 1 task has a clear owning workstream in the Phase 1
  ownership map below.
- [x] Open decisions that would block Phase 1 are recorded in
  [decision-log.md](decision-log.md).
- [x] Phase 0 has not expanded beyond three architecture RFCs.
- [x] The example subpackage has a concrete Phase 1 proof-app scenario.

## Phase 1: Clear-Choice Foundations

**Goal:** Close the gaps that would block a serious developer from choosing
Fleury over Nocterm, Textual, Bubble Tea, Ink, or Ratatui for a new app.

The example subpackage is not a late demo. Start its skeleton as soon as the
semantic tree and app shell have enough surface area, then keep it running as
the continuous integration target for Phase 1 API shape, widget behavior,
terminal fallbacks, and performance evidence.

### Phase 1 Ownership Map

| Milestone | Owning workstream |
| --- | --- |
| M1.1 Semantic tree v0 | [Semantic app graph](workstreams/semantic-app-graph.md) with [Replay, devtools, and testing](workstreams/replay-devtools-testing.md) for tester/inspector integration. |
| M1.2 Text editing v2 | [Text editing engine](workstreams/text-editing-engine.md) with [Terminal capability and security](workstreams/terminal-capability-security.md) for paste, clipboard, password, and redaction policy. |
| M1.3 `FleuryApp` shell | [App kernel and command shell](workstreams/app-kernel-command-shell.md). |
| M1.4 Example subpackage proof app v0 | [Agent and developer workflows](workstreams/agent-developer-workflows.md), [App kernel and command shell](workstreams/app-kernel-command-shell.md), and the widget/runtime workstreams it exercises. |
| M1.5 Agent adapter-readiness boundary | [`fleury_acp` fast-follow package](workstreams/fleury-acp-fast-follow.md) and [Agent and developer workflows](workstreams/agent-developer-workflows.md). |
| M1.6 Worker/task model | [Effects, workflow, and process](workstreams/effects-workflow-process.md). |
| M1.7 Terminal diagnose and capability model | [Terminal capability and security](workstreams/terminal-capability-security.md). |
| M1.8 Scenario benchmark harness | [Reactive render engine](workstreams/reactive-render-engine.md). |
| M1.9 DataTable v1 | [Data virtualization and widgets](workstreams/data-virtualization-widgets.md) with [Semantic app graph](workstreams/semantic-app-graph.md). |
| M1.10 Debug inspector expansion | [Replay, devtools, and testing](workstreams/replay-devtools-testing.md). |
| M1.11 Sanitized output pipeline | [Terminal capability and security](workstreams/terminal-capability-security.md) with [Effects, workflow, and process](workstreams/effects-workflow-process.md). |
| M1.12 Initial distribution path | [Adoption, distribution, and ecosystem](workstreams/adoption-distribution-ecosystem.md). |

- [x] M1.1 Semantic tree v0
  - Intent: Implement the minimum semantic node model in core, tester, and
    inspector.
  - Implementation context: Cover Button, Text, TextInput, TextArea, Table,
    Dialog, Navigator, Progress, and Command first.
  - Acceptance: Tests can query semantic role, label, value, focus, action,
    selection, validation error, and capability requirement state.
  - Evidence:
    [semantic core types](../../packages/fleury/lib/src/semantics/semantics.dart),
    [tester snapshot API](../../packages/fleury/lib/src/testing/fleury_tester.dart),
    [semantic tests](../../packages/fleury/test/semantics/semantics_test.dart),
    [navigator semantic tests](../../packages/fleury/test/widgets/navigator_test.dart),
    [debug semantic summary test](../../packages/fleury/test/debug/debug_shell_test.dart),
    [control semantic tests](../../packages/fleury_widgets/test/controls_test.dart),
    [button semantic tests](../../packages/fleury_widgets/test/button_test.dart),
    [table semantic tests](../../packages/fleury_widgets/test/table_test.dart),
    [dialog semantic tests](../../packages/fleury_widgets/test/dialog_test.dart),
    [progress semantic tests](../../packages/fleury_widgets/test/progress_bar_test.dart),
    [command palette semantic tests](../../packages/fleury_widgets/test/command_palette_test.dart).
  - Notes: Current slice adds immutable semantic nodes/tree, `Semantics`
    wrapper, on-demand `FleuryTester.semantics()`, automatic `Text`,
    `TextInput`, `TextArea`, Checkbox, Toggle, Switch, Radio, and Button
    semantics, Table shape/cell/selection semantics, Dialog semantics,
    Navigator/route semantics, Progress semantics, CommandPalette/Command
    semantics, Navigator/active-route close/dismiss dispatch through
    `maybePop`, and Table semantic action dispatch through the same focus,
    row-selection, and activation paths as keyboard interaction.
    semantics, query filters for focus, action, selection, validation, and
    capability fallback state, plus the first debug Tree-tab semantic summary.
    Semantic action invocation has since been hardened through the app-kernel,
    widget, workflow, and replay/devtools workstreams rather than remaining
    frozen in the original M1.1 descriptive-semantics slice.

- [x] M1.2 Text editing v2
  - Intent: Make text input feel production-grade.
  - Implementation context: Build pure `TextEditingValue`, selection,
    grapheme indexing, keymaps, clipboard, undo, completion, paste policy,
    password policy, and multiline behavior before replacing widgets.
  - Acceptance: Model tests cover emoji, CJK, combining marks, wide
    characters, word movement, selection, undo, history, and bracketed paste.
  - Evidence:
    [RFC 0014: Text editing v2](../rfcs/0014-text-editing-v2.md),
    [completion controller](../../packages/fleury/lib/src/editing/text_completion.dart),
    [completion input](../../packages/fleury_widgets/lib/src/completion_text_input.dart),
    [text keymap](../../packages/fleury/lib/src/editing/text_keymap.dart),
    [pure editing model](../../packages/fleury/lib/src/editing/text_editing.dart),
    [history controller](../../packages/fleury/lib/src/editing/text_history.dart),
    [paste scheduling](../../packages/fleury/lib/src/editing/text_paste.dart),
    [completion tests](../../packages/fleury/test/editing/text_completion_test.dart),
    [keymap tests](../../packages/fleury/test/editing/text_keymap_test.dart),
    [completion input tests](../../packages/fleury_widgets/test/completion_text_input_test.dart),
    [paste tests](../../packages/fleury/test/editing/text_paste_test.dart),
    [pure editing model tests](../../packages/fleury/test/editing/text_editing_model_test.dart),
    [controller tests](../../packages/fleury/test/widgets/text_editing_controller_test.dart),
    [TextInput behavior tests](../../packages/fleury/test/widgets/text_input_test.dart),
    [TextArea behavior tests](../../packages/fleury/test/widgets/text_area_test.dart),
    [semantic tests](../../packages/fleury/test/semantics/semantics_test.dart).
  - Notes: First slice adds `TextRange`, `TextSelection`, `TextEditingValue`,
    and `TextEditingModel`, then routes `TextEditingController`, `TextInput`,
    and `TextArea` through grapheme-safe insert/delete/movement and line
    movement. Current slices add shift-extension and visible selected ranges
    for `TextInput` and `TextArea`, basic controller undo/redo wired to
    Ctrl+Z/Ctrl+Y, explicit paste dispatch through `TextInputClaimant.onPaste`,
    single-transaction paste undo, contiguous typed-input coalescing,
    validation/read-only/disabled semantics, obscured-value semantic redaction,
    a first `TextClipboardPolicy` surface, and cursor-aware horizontal scroll
    for `TextInput` and `TextArea`, plus field-level copy/cut enforcement
    through `TextClipboardPolicy`, and opt-in `TextInput` submission history
    through `TextHistoryController`. Current completion slice adds completion
    option/range/query state, arbitrary range replacement, Tab acceptance, and
    semantic completion state, plus provider-backed rendered completion UI in
    `fleury_widgets`; completion-menu rows now support semantic
    select/activate through the same range replacement path as Tab, and the
    menu supports semantic close without clearing text. The proof app
    Transcript composer now uses `CompletionTextInput` for slash-command and
    mention suggestions plus `TextHistoryController` for submitted-note recall,
    proving the rendered completion and submission-history paths in an
    app-scale workflow. Current paste slice adds
    `TextPastePolicy`, chunked
    post-frame paste sessions for `TextInput` and `TextArea`, paste-progress
    semantics, cancellation on user edits, and one undo transaction per
    scheduled paste. Current composition slice adds composing range/value
    helpers, controller update/commit/cancel APIs, one-undo-step composition
    commit behavior, and text-field/text-area semantic composing state.
    Current lifecycle hardening keeps disposed controller values readable while
    clearing transient history/composition state and rejecting post-dispose
    mutations, including no-op edit commands.
    Auxiliary controller hardening now applies the same lifecycle rule to
    submission history and completion state: stored history entries remain
    readable, browsing/menu state clears during disposal, and post-dispose
    mutation is explicit misuse.
    Final M1.2 slice adds grapheme-safe whitespace-delimited word movement, a
    `TextEditingKeymap` intent resolver, default single-line/multiline maps,
    Emacs-style presets, and widget wiring for custom maps. Full terminal IME
    protocol support and Vi-style modal editing stay outside the MVP, but
    adapter/keymap seams now exist.

- [x] M1.3 `FleuryApp` shell
  - Intent: Provide app-scale structure for commands, shortcuts, command
    palette, status binding, screens, and lifecycle.
  - Implementation context: Align with existing navigator, focus, key
    bindings, debug shell, and theme primitives.
  - Acceptance: A sample app can declare global commands, scoped commands,
    key hints, status bar content, and command palette entries.
  - Evidence:
    [app shell](../../packages/fleury/lib/src/app/app.dart),
    [app shell tests](../../packages/fleury/test/app/fleury_app_test.dart),
    [command core](../../packages/fleury/lib/src/app/commands.dart),
    [command tests](../../packages/fleury/test/app/command_registry_test.dart),
    [status model](../../packages/fleury/lib/src/app/status.dart),
    [tester command helpers](../../packages/fleury/lib/src/testing/fleury_tester.dart),
    [debug panel](../../packages/fleury/lib/src/debug/debug_panel.dart),
    [debug shell tests](../../packages/fleury/test/debug/debug_shell_test.dart),
    [command palette adapter](../../packages/fleury_widgets/lib/src/command_palette.dart),
    [command palette tests](../../packages/fleury_widgets/test/command_palette_test.dart).
  - Notes: First slice adds `CommandId`, `AppCommand`, `CommandRegistry`,
    `CommandRegistryScope`, and `CommandScope`. Commands now have metadata,
    visible/enabled predicates, direct async-capable invocation with typed
    results, scoped parent/local resolution, shortcut emission through
    `KeyBindings`, and semantic command nodes. Current screen-shell slice adds
    `ScreenId`, `FleuryScreen`, `ScreenController`, `FleuryApp`,
    `ActiveScreenView`, app/screen scopes, command-context app/screen
    extensions, active screen rendering, screen-local command scopes, and
    app/screen semantic state. Current status slice adds `StatusItem`,
    `StatusController`, `FleuryApp.status`, command-context status access,
    `AppStatusBar`, and semantic status nodes. Current palette/key-hint slice
    adds registry-backed `AppCommandPalette`, command metadata/shortcut
    semantics in palette rows, disabled-command handling, active-screen
    command priority over app commands, direct concrete-command invocation,
    and app command shortcut visibility in `KeyHintBar`. Final slice adds
    tester command registry access, command invocation by ID, last invocation
    result visibility, app semantic last-command state, and debug Tree-tab app
    state/command summaries. Current launch hardening locks the async command
    v0 rule with tests: direct invocations await `FutureOr` callbacks before
    recording completed/failed results, while shortcut dispatch remains
    fire-and-forget and publishes the result after callback settlement.
    Registry lifecycle hardening prevents async command completions from
    publishing late `lastResult` state after disposal, while preserving the
    in-flight future result for already-started callers. Screen, status, and
    app-controller lifecycle hardening now rejects post-dispose mutations and
    detaches child-controller listeners during app-controller teardown. M1.3
    acceptance is met. Polished focus preservation across preserved screens is
    deferred until the proof app or a focused preserved-screen scenario proves
    the exact behavior needed.

- [x] M1.4 Example subpackage proof app v0
  - Intent: Keep Fleury under realistic app pressure before Dune/`dune_cli`.
  - Implementation context: Use the Phase 0 proof-app scenario to validate app
    shell, semantic graph, text editing, selection, adapter-ready workflows,
    data views, capability fallback, and diagnostics.
  - Acceptance: A runnable example subpackage demonstrates the selected workflow
    and records what Fleury primitives were validated or found missing at each
    Phase 1 foundation step.
  - Evidence:
    [proof app package](../../packages/fleury_example_console),
    [proof app source](../../packages/fleury_example_console/lib/fleury_example_console.dart),
    [proof app tests](../../packages/fleury_example_console/test/proof_console_test.dart).
  - Notes: First skeleton adds a standalone package with path dependencies,
    `ProofConsoleApp`, registered screens, app and screen commands, status,
    registry-backed command palette access, key hints, text filters/composer,
    table fixture, progress, diagnostics, debug capture counter, and tester
    workflow coverage. Current workflow slice adds in-app command palette
    navigation, focusable runs table selection/activation, transcript composer
    submission, deterministic log bursts, disabled stream-command behavior,
    and debug snapshot evidence in the transcript. Current semantic-evidence
    slice adds app-authored navigation, transcript-log, and diagnostic semantic
    nodes, plus tests for command row metadata, selected table cells, composer
    value, progress state, diagnostics capability/fallback state, and debug
    capture action. The proof-app settling slice fixed stale semantic proxy
    subtrees, app-owned tester command routing, palette rendering under tight
    constraints, and task/status assertions; the full proof app test now passes
    under Dart 3.12.1. Later semantic-action settling routes the proof app's
    app-authored sidebar navigation and Diagnostics report actions through the
    existing screen-controller and command-registry paths. Exit validation on
    2026-05-31 reran
    `dart analyze test/proof_console_test.dart` and
    `dart test test/proof_console_test.dart` in
    `packages/fleury_example_console`; both passed. It is intentionally a
    pressure harness, not a polished public example. Dune/`dune_cli` follows
    after core confidence is higher.

- [x] M1.5 Agent adapter-readiness boundary
  - Intent: Ensure fast-follow packages such as `fleury_acp` can be built
    without changing Fleury core.
  - Implementation context: Keep protocol transport, schemas, protocol
    models, and protocol-specific widgets outside Fleury launch scope.
  - Acceptance: Fleury exposes the semantic actions, effects, output regions,
    replay hooks, selection/copy, capability/security policy, and
    protocol-neutral widgets needed by a later `fleury_acp` package.
  - Evidence:
    [agent adapter boundary](agent-adapter-boundary.md),
    [agent adapter readiness audit](agent-adapter-readiness-audit.md),
    [`fleury_acp` fast-follow workstream](workstreams/fleury-acp-fast-follow.md).
  - Notes: This closes the launch boundary only. ACP transport, schemas,
    protocol models, ACP-specific widgets, and ACP replay fixtures remain
    deferred to the fast-follow package.

- [x] M1.6 Worker/task model
  - Intent: Make async work, subprocesses, progress, cancellation, and output
    binding framework-native.
  - Implementation context: Expose structured status and future replay hook
    points without requiring full replay artifacts.
  - Acceptance: Worker tests cover success, failure, cancellation, progress,
    captured output, and UI update ordering.
  - Evidence: [Task controller](../../packages/fleury/lib/src/effects/task.dart),
    [worker tests](../../packages/fleury/test/effects/task_test.dart),
    [task event semantics](../../packages/fleury/lib/src/semantics/semantics.dart),
    [process task controller](../../packages/fleury/lib/src/effects/process_task.dart),
    [process task tests](../../packages/fleury/test/effects/process_task_test.dart),
    [terminal handoff driver contract](../../packages/fleury/lib/src/terminal/terminal_driver.dart),
    [fake driver handoff tests](../../packages/fleury/test/terminal/fake_driver_test.dart),
    [proof app task wiring](../../packages/fleury_example_console/lib/fleury_example_console.dart),
    [proof app workflow tests](../../packages/fleury_example_console/test/proof_console_test.dart).
  - Notes: First slice adds a controller/context task model with status,
    progress, output, cancellation, restart, result/error state, and
    `SemanticRole.task` exposure. Second slice adds terminal handoff and a
    native `ProcessTaskController`. Third slice adds bounded structured
    `TaskEvent` history for replay/devtools hooks. Fourth slice sanitizes and
    caps native process output before task/event storage. Current hardening
    slice makes `TaskStatusView` semantic cancel dispatch through
    `TaskController.cancel`, so generic task status surfaces are operable
    through the semantic graph. Launch lifecycle hardening on 2026-06-02 makes
    `TaskController.dispose` cancel active runs, complete active futures as
    canceled, invalidate stale async writes, and reject post-dispose
    `start`/`reset` calls. Debounced wrapper lifecycle coverage now proves
    pending-work cancellation on dispose, post-dispose schedule/run/reset
    errors, idempotent cleanup cancel, and preservation of externally owned
    task controllers. Exit validation on 2026-05-31 reran task, process-task,
    and fake terminal-handoff tests; they passed. Runtime output-buffer
    lifecycle hardening now keeps final `LogBuffer` lines readable after
    teardown while rejecting post-dispose appends. External editor shape
    remains an explicit Phase 2 follow-up case, not an M1.6 blocker.

- [x] M1.7 Terminal diagnose and capability model
  - Intent: Make terminal behavior visible, testable, and machine-readable.
  - Implementation context: Extend existing capability and driver surfaces
    rather than introducing a separate detection stack.
  - Acceptance: `fleury diagnose --json` reports detected capabilities,
    terminal profile, fallbacks, warnings, and unsupported features.
  - Evidence:
    [capability detection](../../packages/fleury/lib/src/terminal/capabilities.dart),
    [capability requirements](../../packages/fleury/lib/src/terminal/capability_requirements.dart),
    [diagnosis model](../../packages/fleury/lib/src/terminal/diagnostics.dart),
    [CLI diagnose wiring](../../packages/fleury/bin/fleury.dart),
    [diagnostics tests](../../packages/fleury/test/terminal/diagnostics_test.dart),
    [capability requirement tests](../../packages/fleury/test/terminal/capability_requirements_test.dart),
    [image capability semantics](../../packages/fleury_widgets/lib/src/image.dart),
    [image capability tests](../../packages/fleury_widgets/test/image_test.dart),
    [markdown link policy semantics](../../packages/fleury_widgets/lib/src/markdown_text.dart),
    [markdown link policy tests](../../packages/fleury_widgets/test/markdown_text_test.dart),
    [clipboard write reports](../../packages/fleury/lib/src/runtime/clipboard.dart),
    [clipboard report tests](../../packages/fleury/test/runtime/clipboard_test.dart),
    [text clipboard semantics](../../packages/fleury/test/semantics/semantics_test.dart),
    [proof app diagnostics](../../packages/fleury_example_console/lib/fleury_example_console.dart),
    [proof app diagnostics tests](../../packages/fleury_example_console/test/proof_console_test.dart).
  - Notes: First slice centralizes env-derived capability detection, adds
    structured `TerminalDiagnosis` JSON with fallbacks/warnings/unsupported
    features, and wires `fleury diagnose --json`. Second slice adds typed
    capability requirements, fallback metadata, policy/unsafe resolution
    states, and semantic state export. Third slice wires the first widget
    integration through `Image` semantics. Fourth slice adds safe
    `MarkdownText` link semantics with OSC 8 disabled by default and visible
    URL fallback. Fifth slice adds structured clipboard write reports plus
    text-field/text-area clipboard policy semantics. Sixth slice surfaces the
    diagnosis/resolution model in the proof app Diagnostics screen. Exit
    validation on 2026-05-31 reran terminal diagnostics, capability
    requirement, clipboard, proof-app diagnostics, and
    `dart tool/fleury_dev.dart cli diagnose --json`; all passed. Real-terminal
    compatibility checks remain Phase 2 hardening.

- [x] M1.8 Scenario benchmark harness
  - Intent: Convert Phase 0 scenarios into repeatable benchmark runs.
  - Implementation context: Reuse benchmark discipline from RFC 0009.
  - Acceptance: Benchmark output is diffable and includes frame timing,
    allocation-sensitive signals where available, and scenario metadata.
  - Evidence:
    [scenario benchmark runner](../../packages/fleury/benchmark/scenario_benchmarks.dart),
    [benchmark README](../../packages/fleury/benchmark/README.md),
    [text editing baseline](../../packages/fleury/benchmark/results/phase2-text-editing-2026-06-01.json),
    [widgets scenario benchmark runner](../../packages/fleury_widgets/benchmark/scenario_benchmarks.dart),
    [widgets benchmark README](../../packages/fleury_widgets/benchmark/README.md).
  - Notes: The core runner supports `--list`, `--filter`, `--json`, `--save`,
    warmup/iteration/seed/size options, and `SB.1 Time To Counter App`. The
    widgets runner adds package-local `SB.3 DataTable 100k Rows` so core `fleury`
    does not depend on `fleury_widgets`. Both emit JSON records with environment,
    terminal size, p50/p95/p99/max timing, ANSI byte count, semantic node count,
    candidate thresholds, pass state, and notes. Dart is now 3.12.1 locally; the
    stale 3.6.0 SDK blocker is resolved for these runners. Phase 1 baseline
    files now capture 20-iteration `SB.1` and `SB.3` runs. Phase 2 benchmark
    pressure now includes `SB.2` Text Editing, `SB.4` LogRegion, `SB.11`
    TreeTable, and `SB.7` Resize Storm. The first SB.2 baseline validates a
    10k-character mixed-width editor plus chunked paste, selection, undo/redo,
    history, completion acceptance, secret redaction, and semantics with
    cursor-move p95 798 us, insertion/deletion p95 641 us, selection p95
    2191 us, paste-complete p95 18573 us, and semantic-query p95 508 us. The
    first SB.7 baseline validates 500 alternating terminal sizes per iteration
    over a table/log/editor surface with resize-frame p95 488 us and zero unsafe
    frames. The proof-app package now adds `SB.10`
    Proof-App Journey, with a 10-iteration baseline over command palette,
    debounced global search, diagnostics, fake task, DataTable filter/copy,
    transcript updates, native process success, debug capture, semantics, and
    accessibility.
    `SB.8` now adds a 20-iteration, 1000-command overlay/command-palette
    baseline with zero stale palette semantics and zero unexpected invocations,
    which first exposed fuzzy filtering and open/settle latency as optimization
    gaps. The optimized follow-up baseline uses lazy visible rows, cached
    search fields, stable command-id search, and ranked exact/prefix/contains
    matching to bring filter p95 to 1121 us and full-cycle p95 to 6429 us while
    preserving the same correctness counters.
    `SB.9` now adds a 10-iteration subprocess/output safety baseline over a
    1,000,000-byte target process fixture plus stderr failure, cancellation,
    external-editor handoff, terminal-output streaming, semantic checks, and
    unsafe artifact assertions. The saved baseline records process-run p95
    647254 us, cancellation p95 11823 us, stream-frame p95 6230 us,
    process-panel-render p95 10649 us, semantic-query p95 1965 us, restored
    terminal handoff state, and zero unsafe visible/copy/semantic leaks.
    `SB.12` now adds a 20-iteration layout-dirtiness baseline over a static
    pane plus changing counter pane, with command-to-frame p95 11799 us,
    idle-frame p95 692 us, paint-only-frame p95 1210 us,
    text-paint-only-frame p95 3251 us, update-frame layout p95 7 performed /
    3 skipped, paint-only-frame layout p95 0 performed / 1 skipped,
    text-paint-only-frame layout p95 0 performed / 1 skipped, and idle-frame
    layout p95 0 performed / 1 skipped.
    The dashboard widget follow-up refreshes `SB.6` with layout stats after
    auditing visual setters on progress, gauge, sparkline, and bar-chart
    surfaces; the saved baseline records update-total p95 267 us,
    update-frame p95 120 us, update-frame layout p95 45 performed /
    29 skipped, and zero unsafe frames.

- [x] M1.9 DataTable v1
  - Intent: Deliver a visible production-data win.
  - Implementation context: Treat the table as a semantic render island with
    virtualization, stable keys, selection, sort, filter/search, fixed header,
    copy, and benchmark coverage.
  - Acceptance: 100k-row scenario remains responsive and exposes semantic
    rows, cells, columns, sort state, selection, and actions.
  - Evidence:
    [DataTable render island](../../packages/fleury_widgets/lib/src/data_table.dart),
    [DataTable tests](../../packages/fleury_widgets/test/data_table_test.dart),
    [DataTable scenario benchmark](../../packages/fleury_widgets/benchmark/scenario_benchmarks.dart),
    [proof app Runs usage](../../packages/fleury_example_console/lib/fleury_example_console.dart),
    [proof app workflow tests](../../packages/fleury_example_console/test/proof_console_test.dart).
  - Notes: First slice adds a separate `DataTable` in `fleury_widgets` rather
    than retrofitting the existing widget-composition `Table`. It paints only
    visible body rows, exposes virtualized table/row/cell semantics, supports
    stable row keys, keyboard movement, fixed headers, sort/filter semantic
    metadata, sanitized/clipped cell text, selected-row TSV/CSV export, and
    Ctrl+C selected-row copy through the framework clipboard service. The proof
    app Runs screen now uses `DataTable` with local filter updates, stable run
    keys, keyboard selection, activation, and selected-row copy coverage. SB.3
    now measures selected-row copy latency in addition to navigation and
    semantic query latency. A follow-up proof-app settling pass fixed unrelated
    command/status/palette synchronization failures, so DataTable is now proven
    inside the full proof app suite. Final v1 slice adds controller-backed
    cell-selection mode, Shift-extended rectangular ranges, range-aware semantic
    state, selected cell/range copy and rectangular export, plus first-party
    `buildDataTableRowOrder` filter/sort helpers used by the proof app's filter
    flow. Later render-island hardening adds mouse hit selection over the
    painted viewport, including row-mode click selection and Shift-click cell
    range extension. Hidden-column policy, multi-range selection, and richer
    spreadsheet affordances are deferred beyond M1.9.

- [x] M1.10 Debug inspector expansion
  - Intent: Make app state and runtime behavior inspectable during
    development.
  - Implementation context: Add focus, command registry, semantic graph,
    dirty regions, effects, frame timing, and capability fallbacks.
  - Acceptance: Inspector can answer "what is focused?", "what command will
    run?", "why did this repaint?", and "what capability fallback is active?".
  - Evidence:
    [debug frame events](../../packages/fleury/lib/src/debug/debug_events.dart),
    [debug capture recorder](../../packages/fleury/lib/src/debug/debug_capture.dart),
    [debug invalidation collector](../../packages/fleury/lib/src/debug/debug_invalidation.dart),
    [layout debug stats](../../packages/fleury/lib/src/rendering/render_layout_stats.dart),
    [render object layout dirtiness](../../packages/fleury/lib/src/rendering/render_object.dart),
    [debug panel](../../packages/fleury/lib/src/debug/debug_panel.dart),
    [repaint-boundary debug stats](../../packages/fleury/lib/src/rendering/render_repaint_boundary.dart),
    [runtime frame reasons](../../packages/fleury/lib/src/runtime/run_tui.dart),
    [debug inspector tests](../../packages/fleury/test/debug/debug_shell_test.dart),
    [runtime debug event tests](../../packages/fleury/test/runtime/run_tui_test.dart),
    [render object layout tests](../../packages/fleury/test/rendering/render_object_test.dart),
    [debug capture tests](../../packages/fleury/test/debug/debug_capture_test.dart),
    [proof app capture-to-test workflow](../../packages/fleury_example_console/test/proof_console_test.dart).
  - Notes: First slice adds best-effort frame schedule reasons, a useful
    Rebuilds tab with recent frame costs, dirty-cell counts, slow/worst-frame
    summaries, and recent frame reasons, plus Tree-tab summaries for task and
    capability fallback semantic nodes. Second slice records dirty bounds from
    the real diff path even when paint flash is off and adds a preorder
    semantic graph outline to the Tree tab. Existing Tree-tab app/command/focus
    summaries remain the command/focus answer. Third slice adds a debug-only
    build/layout/paint invalidation collector and carries dirty source labels
    on `FrameEvent` into the Live/Rebuilds tabs, proving real `setState` and
    render-object causality through `runTui`. Fourth slice adds an on-demand
    terminal diagnosis
    provider on `DebugController`, installs it from `runTui`, and renders
    terminal profile/capability/fallback/warning rows in the Tree tab. Fifth
    slice adds semantic task/effect aggregate rows for total tasks, status
    counts, and event counts before individual task rows. Sixth slice adds a
    bounded `DebugCaptureRecorder`, terminal/input debug events, redacted
    semantic snapshot serialization, output-summary hooks, and a `runTui`
    capture test. Seventh slice wires that capture shape into the proof app:
    commands, resize metadata, DataTable selection, worker status, status bar,
    output summaries, and serialized semantic assertions now seed a concrete
    regression test. Eighth slice adds Tree-tab semantic cursor navigation,
    selected-node details, and a graph window so the inspector can answer
    targeted semantic-node questions without full replay. Ninth slice adds
    repaint-boundary totals, repaint/cache counts, and copied-cell counts to
    frame events, the Live/Rebuilds tabs, debug capture JSON, and runtime
    tests. Tenth slice adds render-object layout dirtiness, same-constraint
    layout caching, upward child-layout invalidation, and `layout:` dirty-source
    labels while conservatively keeping paint invalidations layout-dirty until
    setter coverage is audited. Eleventh slice adds performed/skipped layout
    stats to frame events, debug panels, capture JSON, and `SB.12 Layout
    Dirtiness Cache`, whose first baseline proves update-frame static-subtree
    skips and idle-frame root skips. Twelfth slice adds the first audited
    paint-only invalidation path, removes element-level unconditional relayout
    after render-object widget updates, guards multi-child render-object sync
    when child identity/order is unchanged, and refreshes SB.12 with
    paint-only-frame layout p95 0 performed / 1 skipped. M1.10 is complete for
    the MVP; deeper graph search/filtering can follow after the core launch
    foundations are stable. Current lifecycle hardening keeps
    `DebugController` final mode/tab/paint/cursor state readable after
    teardown, clears live semantic and terminal diagnosis providers, and
    rejects post-dispose debug-shell mutations.

- [x] M1.11 Sanitized output pipeline
  - Intent: Keep untrusted text, logs, markdown, and process output safe by
    default.
  - Implementation context: Build from the Phase 0 security policy and
    existing text sanitizer/rendering code.
  - Acceptance: Tests cover raw ANSI, OSC sequences, links, images, malformed
    Unicode, huge lines, markdown, and secret redaction hooks.
  - Evidence:
    [text sanitizer tests](../../packages/fleury/test/rendering/text_sanitizer_test.dart),
    [process task controller](../../packages/fleury/lib/src/effects/process_task.dart),
    [process task tests](../../packages/fleury/test/effects/process_task_test.dart),
    [task output semantics](../../packages/fleury/lib/src/semantics/semantics.dart),
    [semantic redaction tests](../../packages/fleury/test/semantics/semantics_test.dart),
    [debug capture tests](../../packages/fleury/test/debug/debug_capture_test.dart),
    [debug shell tests](../../packages/fleury/test/debug/debug_shell_test.dart),
    [clipboard tests](../../packages/fleury/test/runtime/clipboard_test.dart),
    [markdown policy tests](../../packages/fleury_widgets/test/markdown_text_test.dart),
    [image capability tests](../../packages/fleury_widgets/test/image_test.dart),
    [DataTable export tests](../../packages/fleury_widgets/test/data_table_test.dart),
    [proof app workflow tests](../../packages/fleury_example_console/test/proof_console_test.dart).
  - Notes: First implementation slice covers native subprocess task output:
    control-sequence sanitization, line caps, and semantic metadata. Second
    slice tightens `sanitizeForDisplay` so CSI/OSC/DCS/APC terminal control
    sequences collapse as units, preventing OSC 52 clipboard payloads, OSC 8
    hyperlink targets, Sixel/DCS data, and Kitty/APC image data from leaking
    into display/output storage after ESC stripping. Native subprocess output
    now decodes malformed UTF-8 with visible replacement characters instead of
    failing the task. Final audit slice withholds semantic values from
    redacted `TextInput`/`TextArea` clipboard policies, redacts validation
    errors/query/token-shaped debug state in capture serialization, and makes
    the debug Tree tab honor semantic redaction flags. Markdown link policy,
    image fallback semantics, DataTable sanitized export/copy, clipboard
    reports, process output, debug capture, and proof-app workflow coverage are
    now enough to close M1.11 for the MVP. Runtime `LogBuffer` lifecycle
    hardening now prevents stale appends after teardown while keeping final
    captured lines readable.

- [x] M1.12 Initial distribution path
  - Intent: Make Fleury examples easy to try once the APIs are
    credible.
  - Implementation context: Define package commands, local install path,
    standalone binary path, and future Homebrew/npm wrapper plan without
    over-investing before launch readiness.
  - Acceptance: A developer can run a documented local path for examples and
    the example proof app.
  - Evidence:
    [workspace README](../../README.md),
    [local distribution path](local-distribution-path.md),
    [repo-local launcher](../../tool/fleury_dev.dart),
    [proof app README](../../packages/fleury_example_console/README.md).
  - Notes: Added `dart tool/fleury_dev.dart` commands for bootstrap, list,
    proof app, core demos, widget demos, CLI passthrough, quick checks, local
    CLI activation, and standalone CLI compilation. The standalone binary path
    generated `build/fleury` and successfully ran `diagnose --json`. Public
    launch polish remains deferred.

**Exit criteria:**

- [x] A dense keyboard-first app can be built with text input, commands,
  workers, data tables, terminal diagnostics, semantic tests, and visible
  performance metrics.
- [x] Phase 1 benchmark scenarios have baseline numbers.
- [x] Phase 1 APIs are stable enough for first-party examples.
- [x] The example subpackage v0 proves the chosen proof-app slice.
- [x] Peer scorecard has current Nocterm, Bubble Tea v2, Textual, OpenTUI,
  Ratatui, and Ink entries.

## Phase 2: Production App Toolkit

**Goal:** Make Fleury the fastest route to dense production terminal apps.

- [x] M2.1 Forms framework with shared full-screen, inline, prompt-mode, and
  wizard/page-flow rendering.
  - Notes: First slice adds a shared `FormDefinition`/`FormController` model,
    field specs for text, secret, select, and checkbox fields,
    `FormPanelLayout.fullScreen` and `FormPanelLayout.inline` widget
    projections, `FormPromptSession` for sequential prompt-mode fallback,
    `SemanticRole.form` and `SemanticRole.formField`, required/custom
    validation, redacted secret semantics, submit/cancel actions, and focused
    tests. The proof app now includes a Connection screen backed by the same
    connection setup field definition used in the prompt-session tests. Second
    slice adds prompt-mode semantic and accessibility projections directly to
    `FormPromptSession`, so sequential fallback exposes the same form/form-field
    roles, active prompt, prompt position, validation, option count,
    submit/cancel actions, and secret redaction as the visual form. Third
    slice wires visual `FormPanel` semantic submit/cancel and form-field focus
    actions through the existing controller, callbacks, and field focus nodes.
    Current API-stability slice adds safe `FormSnapshot` and
    `FormFieldSnapshot` launch surfaces over controller state, redacting secret
    values by default while preserving raw submission values on
    `FormController.values`, plus controller reset semantics that update
    mounted text controls and keep visual `FormPanel` redaction/accessibility
    state aligned with prompt-mode fallback. Latest richer-field slice adds
    `FormFieldSpec.number` / `FormFieldType.number` with min/max, decimal,
    negative-value policy, controlled `NumberInput` visual binding,
    prompt-mode parsing, safe snapshots, semantics, validation, and proof-app
    connection workflow evidence. Latest date-field slice adds
    `FormFieldSpec.date` / `FormFieldType.date` with date-only typed values,
    first/last date bounds, week-start policy, visual `DatePicker`
    projection, prompt-mode `YYYY-MM-DD` parsing, safe snapshots, semantics,
    validation, and proof-app connection workflow evidence. Latest
    multi-select-field slice adds `FormFieldSpec.multiSelect` /
    `FormFieldType.multiSelect` with typed list values, min/max selected
    bounds, disabled-option validation, visual keyboard toggling,
    comma-separated prompt-mode parsing, safe snapshots, semantics,
    accessibility state, and proof-app connection workflow evidence. Latest
    path-field slice adds `FormFieldSpec.path` / `FormFieldType.path` with
    file/directory/any path kind metadata, optional absolute-path,
    existence, and file/directory validation, text-entry visual binding,
    prompt-mode parsing, safe snapshots, semantics, accessibility state, and
    proof-app connection workflow evidence. Latest async-validation slice adds
    `FormFieldAsyncValidator`, validating field/form snapshot state,
    `validateAsync`, `validateFieldAsync`, `submitAsync`, visual `FormPanel`
    semantic-submit waiting, prompt-mode `submitCurrentAsync`, busy
    semantics/accessibility output, stale-result cancellation, and proof-app
    connection workflow evidence. Final wizard/page-flow slice adds
    `FormWizardStep`, `FormWizardController`, and `FormWizard` as a projection
    over the existing `FormDefinition`/`FormController`, with step-level
    validation gates, async-aware next/submit semantic actions, visible-field
    form projection, step metadata, and proof-app Connection screen adoption
    as a three-step setup flow. M2.1 is closed for the MVP; future form work
    should be driven by concrete product workflows rather than broadening the
    base contract speculatively.
- [x] M2.2 LogView/LogRegion, JsonView, DiffView, CodeView, and MarkdownView.
  - Notes: First slice adds `LogRegion` in `fleury_widgets` for app-authored
    logs/transcripts while preserving core `LogView` for runtime-captured
    stdout/stderr. `LogRegion` supports structured entries, tail-following
    selection, lazy visible-row mounting through `ListView.builder`, sanitized
    search/filter/copy/export, clipboard policy reports, semantic
    log/list-item state, semantic focus/navigation, and semantic row activation
    for visible log selection. The proof app Transcript screen now uses
    `LogRegion`.
    `SB.4 LogRegion Tailing And Scrollback` now records a 100k-entry baseline
    with append-burst, scrollback, copy, filter-query, semantic-query,
    ANSI-byte, and RSS metrics. An indexed follow-up adds optional
    `LogRegionSearchIndex`, reducing filter-query p95 from 68785 us to
    35979 us on the same 100k-entry fixture while recording index-build cost
    separately at 319669 us p95. Second slice adds `JsonView` for structured
    JSON payload inspection: parsed/already-materialized documents, collapsible
    object/array rows, JSON pointer/path state, safe string/key display, subtree
    or line copy, parse-error semantics, first-party `SemanticRole.json` and
    `SemanticRole.jsonNode`, and proof-app Payload screen pressure. Third slice
    adds `DiffView` for unified diff inspection: parsed file/hunk/add/delete
    rows, old/new line numbers, file path state, selected-line or selected-hunk
    copy, terminal-control sanitization, first-party `SemanticRole.diff` and
    `SemanticRole.diffLine`, and proof-app Changes screen pressure. Fourth
    slice adds `CodeView` for source inspection: source-line classification,
    line-number display, indentation and non-empty/comment/blank counts,
    selected-line or whole-document copy, terminal-control sanitization,
    first-party `SemanticRole.code` and `SemanticRole.codeLine`, and proof-app
    Source screen pressure. Fifth slice adds `MarkdownView` for document
    inspection: parsed Markdown rows, heading/list/link/code counts, visible
    URL fallback semantics, selected-block or whole-document copy,
    terminal-control sanitization, first-party `SemanticRole.markdown` and
    `SemanticRole.markdownBlock`, and proof-app Docs screen pressure.
    Patch-review follow-up adds `PatchReview` as the protocol-neutral review
    layer above `DiffView`: patch/file status, per-file stats, selected-file
    activation, sanitized file-summary copy, `SemanticRole.patchReview`,
    `SemanticRole.patchFile`, and proof-app Changes pressure while keeping hunk
    review inside `DiffView`. Further
    filter/typeahead/indexing work should wait for a larger proof workflow.
    Semantic action coverage now routes `LogRegion` focus/row activation/copy,
    `JsonView` open/copy, `DiffView` focus/line activation/copy, `CodeView`
    focus/line activation/copy, and `MarkdownView` focus/block activation/copy
    through the same controller and sanitized copy/export paths as keyboard
    workflows.
    Sixth slice adds
    `SB.5 Streaming Markdown`, which appends 1000 markdown chunks per measured
    iteration with code fences, links, table-like rows, unsafe OSC payloads,
    unsafe link schemes, selected-block copy, semantic markdown/link checks,
    and unsafe-frame detection. The first saved baseline keeps full-document
    parse-on-append below the candidate update budget, so incremental markdown
    parsing is deferred until larger documents or peer comparisons prove the
    need.
- [x] M2.3 TreeTable, FileBrowser, and SearchPanel.
  - Notes: First slice adds `SearchPanel` in `fleury_widgets` for typed
    result lists that are not app commands. It supports a query `TextInput`,
    reusable `SearchResultIndex` exact/prefix/contains/fuzzy ranking, custom
    matcher injection for app-owned source-order policies, `ListView.builder`
    result navigation, Enter activation, selected-result Ctrl+C copy through
    clipboard policy reports, sanitized search/render/copy, and semantic
    region/list-item state with source result indexes separated from filtered
    view indexes. Second slice adds `FileBrowser` as the Phase 2
    production filesystem surface: lazy rows, semantic tree/tree-item state,
    hidden-file policy, query filtering, directory navigation, selected-path
    copy/export, and sanitizer-safe display/search/semantics/clipboard text.
    Third slice hardens base `Tree` semantics and sanitizer behavior so
    TreeTable can reuse tested tree/tree-item meaning rather than inventing a
    parallel hierarchy model. Fourth slice adds `TreeTable` with explicit node
    keys, DataTable-compatible columns/export formats, expansion/collapse
    navigation, filtered descendant discovery, visible-row laziness, semantic
    tree rows plus table cells, selected-row copy/export, and sanitizer-safe
    rendering/search/semantics/export. The proof app now has a Tree screen that
    exercises TreeTable through app navigation, focus commands, semantics,
    activation into the transcript, and selected-row copy. `SB.11 TreeTable
    Hierarchy Filter And Copy` now records a 100k-leaf hierarchy baseline:
    `TreeTableSearchIndex` build p95 is 1851310 us, exact-token filtered
    descendant reveal is 4074 us p95, selected-row copy is 8002 us p95, and
    semantic query is 1979 us p95. Current index-hardening slice removes
    private per-row map copies and replaces regex tokenization with a manual
    scanner; the saved 5-iteration follow-up baseline brings index-build p95
    to 1040888 us on the same 100k-leaf fixture while preserving exact-token
    behavior for `A-Za-z0-9_:-` symbol tokens. Current cooperative-index slice
    adds task-owned `LogRegionSearchIndex` build/refresh and
    `TreeTableSearchIndex` build paths through `TaskYieldPolicy`; refreshed
    saved baselines record `SB.4` search-index-build p95 375479 us with
    progress current 100000, and `SB.11` index-build p95 826676 us with
    progress current 100100. Current prefix-token slice adds
    `TreeTableFilterMode.prefixToken`, using sorted search-index tokens for
    fast ID/path/symbol typeahead while preserving direct filtering parity and
    ancestor reveal. M2.3 search policy is now explicit: exact-token and
    prefix-token modes are index-backed for durable identifiers, while fuzzy
    contains/subsequence remains an opt-in scan until a proof workflow justifies
    richer n-gram indexing, isolate-backed execution, cached flattened rows,
    or render-island search support.
    Semantic action coverage now includes `SearchPanel` focus/activate/copy,
    `Tree` focus/open/activate, `TreeTable` open/activate/copy, and
    `FileBrowser` open/copy over mounted visible rows. The proof app Global
    Search screen now uses `SearchPanel` as the result surface for an app-owned
    debounced search task, proving that async result production can stay
    outside the widget while reusable ranking, semantics, and activation stay
    first-party. The ranked-search follow-up saves a refreshed `SB.10` baseline
    with global-search p95 84221 us and selected result key `run.RUN-1002`.
    The proof app Indexed Logs screen now proves cooperative retained-log
    indexing in an integrated workflow: `TaskController` / `TaskYieldPolicy`
    build and refresh `LogRegionSearchIndex`, and `LogRegion` exposes filtered
    result semantics with append-refresh evidence.
- [x] M2.4 ProcessPanel, CommandRunner, and terminal output regions.
  - Notes: First slice adds `ProcessPanel` in `fleury_widgets` for
    `ProcessTaskController` output/status surfaces. It maps bounded sanitized
    `TaskOutput` into `LogRegion`, exposes task/process semantic state,
    supports filtered output, selected-output copy, progress display, and
    Escape cancellation while preserving the core process model.
    `ProcessCommandRunner` and `ProcessCommandScope` now add start/cancel app
    commands, shortcuts, semantic actions, non-blocking command invocation, and
    command-state refresh around the same controller. The proof app now has a
    Process screen that runs `dart --version` through `ProcessCommandScope` and
    displays output through `ProcessPanel`. `TerminalOutputRegion` now adapts
    runtime `LogBuffer` stdout/stderr capture into `LogRegion` so captured
    terminal output gets filtering, copy, sanitization, lazy rows, and log
    semantics. Runtime `LogBuffer` lifecycle hardening now prevents stale
    appends after teardown while keeping final captured lines readable.
    Latest slice wires `ProcessPanel` semantic cancel through
    `ProcessTaskController.cancel`, preserving the same cancellation path as
    Escape and command-runner cancellation. Current slice adds native
    external-editor handoff through `editTextInExternalEditor`: `$VISUAL` /
    `$EDITOR` resolution, platform fallback, temp-buffer editing, inherited
    stdio, `TerminalHandoffDriver` suspension/resume, changed-text metadata,
    non-zero exit handling, and focused fake-driver tests. Final slice adds
    `SB.9 Subprocess Handoff And Untrusted Output`, which runs a 1 MB target
    subprocess fixture through success, non-zero exit, cancellation,
    external-editor handoff, captured-output streaming, copy, semantics, and
    unsafe artifact checks. Future process work should be opened as concrete
    app-scenario follow-up rather than broadening this slice into a shell
    framework.
- [x] M2.4a Debounced restartable task primitive.
  - Notes: `DebouncedTaskController` wraps the existing `TaskController` so
    typeahead, search, and index workloads can coalesce pending changes, cancel
    stale running work, run immediately when needed, and preserve progress,
    output, events, results, and task semantics through the same model as other
    Fleury workers. The proof app Global Search screen now uses it to feed
    `SearchPanel` and route selected results back into app navigation. It is not
    an isolate/off-main indexing story by itself; it is the shared policy
    primitive needed before wiring heavy indexes into production widgets.
    Lifecycle hardening coverage now proves pending debounce cancellation,
    final readable task state, post-dispose misuse errors, and external
    `TaskController` ownership.
- [x] M2.4b Cooperative task yielding for heavy app-owned work.
  - Notes: `TaskYieldPolicy` / `TaskYieldCheckpoint` now give long-running
    `TaskController` work explicit progress, cancellation, and event-loop yield
    checkpoints. `LogRegionSearchIndex.buildCooperatively`,
    `LogRegionSearchIndex.refreshCooperatively`, and
    `TreeTableSearchIndex.buildCooperatively` prove the model against retained
    log and hierarchy index workloads. This still is not isolate-backed
    execution; it is the launch-quality cooperative foundation before any
    worker pool or isolate indexing API. The proof app now consumes this path
    directly in the Indexed Logs screen and refreshed `SB.10` benchmark.
- [x] M2.5 Theme and component-theme expansion.
  - Notes: First slice adds `FleuryWidgetTheme` as a typed
    `ThemeData.extensions` entry for widget-package defaults without growing
    core `ThemeData`. It covers control focus, disabled controls, switch
    on/off styles, progress filled/track styles, and Markdown document block
    styles. `Checkbox`, `Toggle`, `Radio`, `Switch`, disabled `Button`,
    `ProgressBar`, and `MarkdownView` now resolve these defaults while keeping
    explicit widget styles authoritative. The proof app now runs under a
    custom `Theme` with `FleuryWidgetTheme` tokens and tests Markdown heading
    styling through the Docs screen. Second slice expands the same extension
    to production-toolkit surfaces that had repeated hardcoded styles:
    DataTable/TreeTable selection, separators, empty states, LogRegion
    severities, DiffView line kinds, and JsonView parse errors. The proof app
    now applies those tokens to Runs and Changes screens, and focused tests
    verify explicit widget styles still override theme defaults. Final slice
    adds CodeView line-kind tokens for blank/comment/import/declaration/
    keyword/string/plain rows and applies them in the proof-app Source theme.
    The launch token set is intentionally limited to repeated production
    widget states: controls, progress, data, logs, code, diff, JSON, and
    markdown. Rich syntax theming, per-token highlighting, and broader design
    system work are deferred until proof-app or widget-suite pressure shows
    real duplication.
- [~] M2.6 Dune/`dune_cli` first integration slice after the core framework is
  proven through the example subpackage.
  - MVP status: Deferred by current-cycle scope. The proof app is the active
    integration harness; Dune/`dune_cli` should start after the core APIs and
    widget surfaces are stable under proof-app tests.
- [~] M2.7 Optional `fleury_acp` fast-follow package if Dune/`dune_cli` later
  needs ACP integration.
  - MVP status: Deferred by current-cycle scope. Fleury core remains
    protocol-neutral and adapter-ready; ACP transport, schemas,
    protocol-specific widgets, and ACP replay fixtures belong in a later
    sibling package.
- [x] M2.8 Accessibility and fallback model built from semantic nodes.
  - Notes: First slice adds a text-first `AccessibilitySnapshot` derived from
    `SemanticTree`, plus `FleuryTester.accessibilitySnapshot()`. It preserves
    semantic role, label, safe value, hint, validation, focus/selection,
    checked/expanded/busy state, progress, data collection ranges,
    capability fallback state, clipboard policy, actions, JSON export, and
    plain-text narration while redacting secret values. This is not a broad
    OS screen-reader claim; it is the portable semantic fallback layer for
    tests, prompt fallback, debug capture, and future accessibility adapters.
    Second slice connects the same model to `FormPromptSession`, giving
    prompt-mode fallback a semantic and accessibility projection without a
    second metadata path. Third slice adds accessibility output to
    `DebugCaptureSnapshot`, deriving it from captured semantic trees or
    accepting an explicit accessibility snapshot for non-widget fallback
    sessions. Current slice expands the semantic-derived accessibility
    projection with allow-listed app-kernel, command, task, output, view,
    row/cell, and developer-document state used by the proof app and
    production widgets, while preserving redaction for selected keys on
    redacted nodes. Current API-stabilization slice adds typed node fields and
    snapshot filters for enabled, focused, selected, checked, expanded, busy,
    value-redacted, action, value, validation, and state matching so adapters
    and tests do not have to parse narration strings. Latest adapter-facing
    slice adds `AccessibilitySnapshotSummary`, focused-node/source-id lookup,
    actionable-node, validation-error, and redacted-value selectors, plus
    debug-capture summary serialization. Date-picker state now uses the same
    allow-listed fallback path for selected date, visible month/year, bounds,
    week-start policy, and bounded increment/decrement availability.
    Model/status and token-meter state now uses the same allow-listed fallback
    path for model name/provider/status/mode, latency, queue depth,
    context-window usage, token totals, and near/over-limit state. File
    mention state now uses the same allow-listed fallback path for file path,
    kind, language, line/column, mention text, and selected file state.
    Conversation navigator state now uses the same allow-listed fallback path
    for conversation ID, status, unread/message counts, pinned state, and
    selected conversation state. Context panel state now uses the same
    allow-listed fallback path for context item ID, kind, token count,
    priority, pinned/source state, selected context item state, and aggregate
    context item/token counts. Trace timeline state now uses the same
    allow-listed fallback path for trace ID, kind, status, source, duration,
    selected trace ID, and aggregate trace counts. Patch-review state now uses
    the same allow-listed fallback path for patch ID, patch/file status,
    selected file path, file counts, addition/deletion counts, hunk counts, and
    review-state counts. Wizard form state now uses the same allow-listed
    fallback path for visible field count, step position/count, current step
    id/title, and back/forward availability. Notification/toast state now uses
    the same allow-listed fallback path for severity, stack position,
    auto-dismiss timing, and optional action label/key; toast nodes expose
    dismiss and optional activate semantic actions. Tab state now uses the same
    allow-listed fallback path for tab position/count and shortcut; tab nodes
    expose focus/select/activate semantic actions, and `IndexedStack` prunes
    inactive page semantics while keeping page state mounted. Menu state now
    uses the same allow-listed fallback path for item count and item
    position/count; menu trigger/body/item nodes expose focus/open/close and
    activate semantics while preserving the existing overlay and lazy visible
    row behavior. Select option-list state reuses the same fallback path for
    option count and position/count; select trigger/list/option nodes expose
    focus/open/close/select/activate semantics, selected value state, disabled
    option state, and checked applied-option state. Autocomplete suggestion
    state reuses the same fallback path for suggestion count and
    position/count; suggestion-menu rows expose close/select/activate
    semantics, query state, and selected suggestion state while the underlying
    text field keeps core `TextInput` semantics. `FilePicker` now follows the
    same tree/tree-item contract as `Tree` and `FileBrowser`, exposing a
    semantic tree root, selected-entry state, sanitized current-directory and
    selected-path values, row tree items, and focus/navigation/open actions for
    directory navigation and file selection. `ColorPicker` now exposes the
    palette as a semantic list and each swatch as a radio-like option with
    checked/selected state, color metadata, semantic select/activate actions,
    and optional custom semantic color labels for app palettes. `TextInput`
    now exposes an additive `semanticLabel`/`semanticState` seam for
    specialized text fields, `NumberInput` uses it to publish constrained
    numeric text-field state, parsed numeric value, bounds, number policy, and
    semantic submit clamping without pretending to be a spin button, and
    `PasswordInput` uses it to publish secret-field metadata while retaining
    value redaction and redacted clipboard policy. `Tooltip`
    now exposes a semantic help region with the tooltip message as hint/value
    and a visible semantic text node while the focus-triggered overlay is
    shown. Diagnostic nodes now use the same allow-listed fallback path for
    terminal size/profile, capability-row count, fallback/warning/unsupported
    counts, debug-capture count, streaming state, and OSC policy state. App
    status bars now use the same allow-listed fallback path for status item
    count, status item ID, severity, value, command identity, and action state.
    Search and log surfaces now use the same allow-listed fallback path for
    result/entry totals, filtered counts, selected index/category/source, log
    filter state, copy-prefix policy, and source/view row indexes while
    keeping generic severity fallback wording stable for non-status widgets.
    Workflow summary regions now use the same allow-listed fallback path for
    workflow ID/title/health, message/tool/task activity, model status,
    context items/tokens, file mentions, conversations/unread state, trace
    activity, patch files, review issues, and warning/error log counts.
    Data-visualization surfaces now expose `SemanticRole.chart`, typed chart
    state, and allow-listed fallback text for gauges, sparklines, bar charts,
    histograms, heatmaps, calendar heatmaps, and interactive line charts.
    Block-rendered Digits now expose semantic text for clocks and counters.
    Generic `Canvas` drawings now stay semantic-silent by default but can opt
    into image/chart semantics with marker/bounds state and text-first
    fallback output, so custom drawings are inspectable without duplicating
    richer semantics from first-party chart wrappers.
    The proof app Overview telemetry strip proves dashboard chart semantics in
    the integrated scenario. Task-event trace rows
    now use typed task run/sequence/kind/progress/output-safety state plus
    allow-listed fallback text, giving proof-app Diagnostics inspectable
    effect history without serializing raw task output, result values, errors,
    or stack traces into trace metadata.
    Process task fallback now includes command display, exit code,
    success/failure, and cancelability from `ProcessPanel` semantics, giving
    process workflows a useful text-first/debug artifact story without
    inventing a second process model.
    M2.8 is complete for the MVP: future widget-specific summaries should be
    opened only when proof workflows demand them, and broad OS accessibility
    claims remain out of scope until adapter evidence exists.
- [x] M2.9 Windows driver.
  - Notes: First slice adds `WindowsTerminalDriver`,
    `createNativeTerminalDriver`, and shared native terminal enter/exit
    sequences. `runTui` now chooses the Windows driver on Windows and the
    POSIX driver elsewhere. The Windows driver enables virtual terminal input
    and output through `SetConsoleMode` when available, uses Dart stdin
    line/echo mode for raw input, polls terminal size for resize events, and
    preserves terminal handoff semantics. Focused tests cover platform-driver
    selection and safe non-Windows no-op behavior for the native console-mode
    controller. Current hardening slice extracts pure console-mode planning
    and tests the input/output mode bit decisions without needing a Windows
    host. The planner now enables virtual-terminal input, processed
    virtual-terminal output, and delayed newline auto-return semantics; the
    diagnose command uses the native driver selector and emits OS/Dart platform
    evidence for matrix review. Current launch API boundary slice keeps
    Windows console-mode controller injection, pure bit-planning helpers,
    native-platform selector hooks, and raw terminal sequence builders out of
    production public libraries while preserving the stable driver/probe/parser
    extension surface through
    [terminal public API boundary tests](../../packages/fleury/test/terminal/terminal_public_api_boundary_test.dart).
    Current Windows validation-planning slice adds
    `terminal-matrix-audit --target-preset=windows`, expanding the audit target
    set to Windows Terminal, conhost, PowerShell, and Windows IDE terminal
    captures. The generated
    [Windows validation plan](windows-validation-plan.md) and
    [Windows validation review packet](windows-validation-review-packet.md)
    record the current 0/4 ready-target state and capture/review commands.
    MVP status: local Windows driver and diagnosis support is complete for the
    MVP boundary. Real Windows Terminal, conhost, PowerShell, and IDE terminal
    validation is deferred out of MVP and remains documented through the
    post-MVP Windows validation plan and review packet.
- [~] M2.10 Active capability probes and real-terminal compatibility tests.
  - Notes: First slice adds an opt-in active probe model and CLI path:
    `TerminalProbeTransport`, `runTerminalProbeSuite`,
    `TerminalProbeReport`, and `fleury diagnose --probe`. The probe suite
    checks primary device attributes as a sentinel, Kitty keyboard status
    (`CSI ? u`), and Kitty graphics query support with bounded per-probe
    timeouts. Active writes are never part of normal app startup or default
    diagnosis; they run only when a developer explicitly passes `--probe`.
    Non-TTY environments return structured skipped evidence. Second slice adds
    `TerminalCompatibilityReport`, which compares passive/env-derived diagnosis
    with active probe results for Kitty keyboard and Kitty graphics support,
    giving real-terminal matrix entries explicit confirmed, active-confirmed,
    passive-unverified, unsupported, or inconclusive findings. Third slice adds
    `dart tool/fleury_dev.dart terminal-matrix`, which captures labeled
    diagnosis/probe JSON entries under
    `docs/implementation/terminal-matrix/` with a compact review summary.
    Current matrix-review slice adds automatic `review.status`,
    `review.issues`, and `review.notes` to each entry so non-interactive
    captures, skipped probes, passive-unverified findings, inconclusive
    findings, tmux/SSH context, and active-only confirmations are visible
    before evidence is used for launch claims. Latest probe-evidence slice
    classifies transport `TimeoutException`s as `timeout` instead of generic
    `error`, and matrix summaries now carry active-probe status counts so
    skipped, timed-out, unsupported, confirmed, and errored probes are visible
    without hand-reading every probe entry. Current PTY-fixture slice adds a
    `script(1)`-backed pseudo-terminal smoke test for the active probe suite when
    the host provides a compatible command-mode `script` utility. Current
    matrix-capture hardening adds `fleury diagnose --json-output=<path>` and
    makes `terminal-matrix` preserve inherited stdio while diagnose writes JSON
    to a temporary file, preventing false non-interactive matrix entries caused
    by piping diagnose stdout. Current platform-evidence slice adds OS/Dart
    platform fields to diagnosis JSON and matrix summaries so Windows and
    non-Windows captures can be reviewed without guessing from environment
    variables. Current active-evidence slice exposes compatibility-confirmed
    feature sets and `TerminalDiagnosis.confirmedAvailableFeatures`, letting
    apps/tests feed opt-in confirmed probe evidence into
    `resolveCapabilityRequirement(additionalAvailableFeatures: ...)` without
    changing passive startup detection. Current audit-tooling slice adds
    `dart tool/fleury_dev.dart terminal-matrix-audit`, which scans collected
    matrix entries, reports review status/platform coverage, flags invalid
    files, and lists target terminal labels that still lack ready reviewed
    evidence. Latest audit hardening accepts clean target-prefixed labels such
    as `iterm2-3-5` and context-first labels such as `tmux-kitty` / `ssh-iterm2`
    without letting context captures satisfy clean terminal targets. Matrix
    summaries and audits now include fallback, warning, and unsupported-feature
    counts/codes so degraded captures are visible before raw diagnosis review.
    Latest inspector slice renders compatibility finding counts and per-feature
    active/passive summaries in the debug Tree tab so probe evidence is visible
    inside Fleury devtools, not only in JSON files.
    Current inspector-safety slice adds aggregate semantic safety rows for
    redacted values, sanitized output, truncation, and largest original output
    length, keeping unsafe-content handling visible in the same inspector.
    Latest policy-drilldown slice adds semantic capability resolution counts
    and attention rows for degraded, policy-blocked, unsupported, unsafe, and
    required-blocked feature requests.
    Current audit-planning slice adds readiness totals, `strictPass`, and a
    missing-target `collectionPlan` to `terminal-matrix-audit`, plus suggested
    capture commands in the human audit output so real-terminal collection can
    proceed target by target without hand-built labels.
	    Latest audit-test slice adds black-box launcher coverage for
	    `terminal-matrix-audit`, proving clean target-prefix matching,
	    tmux/SSH context-label classification, strict-mode invalid-entry failure,
	    and missing-target collection-plan output through the actual developer
	    command. Current capture-context slice adds repeated
	    `--review-note=<text>` support to `terminal-matrix`, preserving
	    capture-time profile/version/context notes in `review.notes` without
	    overriding automatic triage issues. Current audit-readiness slice
	    separates targets with no captures from targets with non-ready captures in
	    `terminal-matrix-audit` JSON and human output through `nextAction`,
	    ready/non-ready entry counts, `nonReadyTargetCount`, and
	    `targetsNeedingReview`.
    Latest collection-plan slice adds
    `terminal-matrix-audit --write-plan=<path>`, generating a Markdown
    checklist from the same target matching and review-state logic as the JSON
    audit. The current
    [terminal matrix collection plan](terminal-matrix-collection-plan.md)
    records 2/2 ready MVP targets and the exact external capture commands.
    Current review-packet slice adds
    `terminal-matrix-audit --write-review=<path>`, generating a target-by-target
    reviewer packet from the same audit model as the strict gate. The current
    [terminal matrix review packet](terminal-matrix-review-packet.md) records
    2/2 ready MVP targets and gives reviewers a single checklist for matched
    entries, issues, notes, terminal/platform facts, active probe summaries,
    compatibility summaries, and unmatched entries.
    Current MVP-readiness slice adds
    `dart tool/fleury_dev.dart mvp-readiness`, a combined external-evidence
    gate that audits the non-Windows MVP launch terminal matrix and reports the
    post-MVP Windows validation preset without enforcing it. It writes
    [mvp-readiness-report.md](mvp-readiness-report.md).
    Current final-gate slice adds `dart tool/fleury_dev.dart mvp-final-gate`,
    which runs the local RC gate and then enforces the combined external
    evidence gate. Current refresh slice adds
    `dart tool/fleury_dev.dart mvp-evidence-refresh`, regenerating all
    generated evidence packets from the current matrix state. Current reviewed
    acceptance slice adds `dart tool/fleury_dev.dart terminal-matrix-accept`,
    allowing explainable `needsAttention` entries to become
    `acceptedForLaunch` while preserving original issues and reviewer notes.
	    MVP status: complete for the narrowed terminal target set of Apple
	    Terminal and tmux. iTerm2, Kitty, Ghostty, Alacritty, WezTerm, and SSH
	    are post-MVP extended matrix targets.
- [x] M2.11 Targeted debug-capture and replay-hook prototype if example or
  Dune/`dune_cli` testing exposes bugs that require it.
  - Notes: Full replay remains deferred, but targeted debug capture now records
    semantic snapshots and text-first accessibility/fallback output for
    regression-oriented bug artifacts. Current slice adds
    `DebugCaptureArtifact`, a queryable test helper over serialized capture
    JSON, so tests can assert on captured inputs, frames, output summaries,
    safe task-event summaries, deterministic time markers, accessibility
    narration, and semantic nodes without hand-walking nested maps. The
    proof-app capture-to-test regression now uses this artifact surface,
    proving the MVP replay-hook path as targeted evidence rather than broad
    replay.
- [x] M2.12 MVP adoption positioning and public-scope disposition.
  - Notes: First M2.12 slice adds the internal
    [Why Fleury?](why-fleury.md) positioning draft and refreshes peer version
    facts on 2026-06-01. The draft names three concrete wins against Nocterm,
    three against Bubble Tea v2, the proof-app role, the later Dune/`dune_cli`
    flagship role, launch-ready claims, and claims not yet ready. The local
    distribution path and peer scorecard skeleton are also in place. Public
    package docs, public comparison copy, docs site, scaffolding, adoption
    metrics, and release collateral are explicitly deferred until API freeze
    and are not MVP blockers.

**Exit criteria:**

- [x] Production developer tools can use Fleury for forms, logs, files, diffs,
  code, markdown, process orchestration, diagnostics, and replayable bugs.
- [x] MVP real-terminal compatibility checks cover macOS Terminal and tmux.
  iTerm2, Kitty, Ghostty, Alacritty, WezTerm, SSH, Windows Terminal, and
  broader Windows host validation are post-MVP.
- [x] The example proof app is strong enough to validate the framework before
  Dune/`dune_cli` becomes the first product showcase.

## Phase 3: Ecosystem Leadership

**Goal:** Move beyond parity with peers and define the next generation of
terminal app development.

- [ ] M3.1 Agent workflow widget suite v2.
- [ ] M3.2 Dune/`dune_cli` maintained as flagship showcase.
- [ ] M3.3 Terminal devtools protocol and browser/devtools bridge.
- [ ] M3.4 Snapshot/replay debugging with shareable artifacts.
- [x] M3.5 Remote app/session story.
  - Notes: Existing code already includes `RemoteTerminalDriver`,
    `RemoteFrameTransport`, Unix-socket shell transport, browser `serve`
    bridge, spawn-mode browser session isolation, upward `.fleury/handle`
    discovery, and focused remote protocol/driver/serve tests. Current
    hardening slices add a bounded remote frame payload cap,
    `RemoteProtocolException`, typed malformed INIT/RESIZE/UTF-8 failures,
    Unix-socket transport error forwarding, and pre-INIT driver failure instead
    of a hung remote handshake. The served browser client now caps incoming
    frame payload lengths before buffering, and `fleury serve` rejects
    cross-origin WebSocket upgrades while preserving same-origin browser
    sessions. Bridge and spawn modes now attach the browser WebSocket listener
    before the app socket connects, buffer bounded pre-app browser frames, and
    have regressions proving real `runTui` apps receive the browser INIT frame
    sent immediately on WebSocket open. `fleury serve` now keeps same-origin
    browser WebSocket upgrades as the default and adds explicit
    `--allow-origin=<origin>` / `--allow-origin=*` opt-ins for cross-origin
    browser clients. A real browser validation pass rendered the counter
    quickstart through xterm.js with connected status; socket integration
    tests continue to cover browser-to-app byte flow. The launch API boundary
    is now explicit and tested: public libraries expose `runTui`,
    `TerminalDriver`, and CLI-driven shell/serve behavior, while remote
    protocol, transport, and driver internals remain under `src/remote`. Real
    `fleury shell` workflow validation now covers shell startup, real
    counter-quickstart attach, first paint, Space input through the shell PTY,
    Ctrl+C proxy teardown, terminal restore sequences, and attached app exit.
    That validation found and fixed three launch-relevant defects: unclaimed
    printable terminal text now falls through to character `KeyBindings`,
    shell signal cleanup now closes the active remote session before exiting,
    and `RemoteTerminalDriver.restore()` now closes transport resources even
    after the peer has already sent `BYE`.
- [x] M3.6 Stable semantic inspection protocol for automation and AI agents.
  - Notes: First v0 slice adds `SemanticInspectionSnapshot` and
    `SemanticInspectionNode` as a schema-versioned, JSON-safe, redaction-aware
    semantic tree export with node/role/action/focus summary fields and query
    helpers. Debug capture now reuses this serializer, so regression artifacts
    and future automation adapters share the same semantic JSON boundary. The
    launch v1 protocol now defines stable top-level and node field sets,
    exposes `fromJson` parsers for snapshots and nodes, treats schema v1 as
    additive-forward-compatible by ignoring unknown fields, recomputes summary
    counts from parsed roots, reapplies redaction flags while parsing, and
    rejects malformed roots or unsupported schema versions. `DebugCaptureArtifact`
    now exposes a parsed `semanticInspectionSnapshot`, and tester coverage
    proves an inspect-then-act flow where adapter-shaped code parses semantic
    JSON, selects a node by protocol fields, and invokes the advertised action
    by node id. External browser/devtools protocols and provider-specific
    automation adapters remain later M3.3/M3.8 work, not blockers for the
    launch inspection contract.
- [x] M3.7 Optional high-performance engine boundary for render/data hot
  paths.
  - Notes: First M3.7 slice extends the existing layout-dirtiness and
    `markNeedsPaintOnly` foundation into widget-package render objects. Stable
    visual updates now skip layout for `LineChart`, same-shape `Heatmap`
    value changes, `CalendarHeatmap` value/style changes, `Canvas` painter/
    bounds/marker/style changes, same-width `Digits` text and style changes,
    `RangeSlider` value/focus/style changes, and `Image` fit/glyph/protocol/
    color-policy changes. Shape-sensitive fields such as heatmap labels/cell
    widths, calendar date ranges/labels, digit width changes, and decoded image
    replacement remain layout-dirty. Current DataTable render-island slice
    makes setter invalidation explicit and keeps visible selection and
    visible-cell content refreshes paint-only while row-count, columns,
    spacing, and header geometry remain layout-dirty. Current composition
    `Table` slice gives `RenderTable` explicit setter invalidation and keeps
    visible selected-row movement paint-only while columns, spacing, headers,
    children, and row-window changes remain layout-dirty. Current core text
    slice keeps same-width single-line `RenderText` content updates paint-only
    while wrapping, newline, empty/non-empty, and intrinsic-width changes remain
    layout-dirty; `SB.12` now measures same-width text swaps as a separate
    paint-only frame. Current child-list replacement slice makes same-identity,
    same-order child replacement a layout no-op for core multi-child render
    objects and composition `RenderTable`, while reorders/add/drop remain
    layout-dirty. `SB.12` now measures a child-list no-op frame with p95
    0 performed / 1 skipped layout work. Current `ScrollView` viewport-paint
    slice changes generic scroll paint from a full child-height scratch buffer
    to a viewport-sized scratch buffer with translated negative offsets, backed
    by clipped `CellBuffer` writes and focused scroll/selection regression
    tests. Current `RenderFlex` paint-culling slice skips child subtrees whose
    laid-out bounds cannot intersect the current paint buffer, preserving
    offscreen paint for selectable subtrees so full `cellBounds` and visible
    bounds remain correct under scrolled selection. `SB.12` now includes a
    viewport paint sub-journey over a 2,000-row `ScrollView` child and records
    p95 24 painted rows on a 24-row viewport plus viewport-scroll-frame p95
    1245 us. Final launch-boundary slice keeps this work as first-party
    render-object discipline rather than a public high-performance extension
    API. Production libraries do not export layout-debug counters, child-list
    helper functions, paint-culling internals, or first-party widget-package
    `Render*` implementation classes; `fleury_test` keeps the render
    diagnostics needed by tests and benchmarks. Current widget public-boundary
    hardening also keeps implementation-only `RenderLayoutBuilder` out of
    production barrels while preserving public `LayoutBuilder` and
    `LayoutWidgetBuilder`. Follow-up core widget boundary hardening keeps
    app-facing `TextInput`, `TextArea`, `RichText`, and `Scrollbar` public
    while hiding their implementation renderers and scrollbar geometry/metrics
    plumbing from production barrels. Repaint-boundary frame counters now
    follow the same production/test split as layout counters: production keeps
    `RenderRepaintBoundary`, while `fleury_test.dart` owns the diagnostics DTO.
    M3.7 is complete for MVP as a local core hardening milestone. Public
    render-island APIs, broader extension points, or stronger engine-boundary
    claims should wait for post-MVP package/proof-app pressure. Current root
    lifecycle hardening makes `BuildOwner.updateRoot` follow the same
    compatibility rule at the
    app root that subtree reconciliation already uses: preserve state for
    compatible root updates, remount and dispose for incompatible type/key
    replacements, and reject stale root handles. Core list/scroll controller
    lifecycle hardening now keeps final selection/range/offset/metric state
    readable after disposal, clears transient pending list jumps, and rejects
    post-dispose list/scroll mutations. Data-heavy widget controller lifecycle
    hardening applies the same launch rule to `DataTableController` and
    `TreeTableController`: final selection/range/expansion state stays readable
    for diagnostics, while stale row/cell selection and tree expansion
    mutations fail explicitly after teardown. Developer-document controller
    lifecycle hardening now extends that wrapper-list rule to `CodeView`,
    `DiffView`, `JsonView`, and `MarkdownView` controllers, keeping final
    selection/expansion state readable while rejecting stale selection, jump,
    and JSON branch mutations. Live workflow controller lifecycle hardening now
    covers `LogRegion`, `MessageList`, `TraceTimeline`, `TaskGraph`,
    `ContextPanel`, and `PatchReview` controllers, keeping final
    selection/tail-follow state readable while rejecting stale selection, jump,
    scroll-to-tail, and workflow-row mutations. Navigation/simple-surface
    controller lifecycle hardening now covers `TabController`,
    `TableController`, `ConversationNavigatorController`,
    `FileMentionPickerController`, and `FileBrowserController`, keeping final
    index/selection state readable while rejecting stale tab, row, picker, and
    browser selection mutations. Form controller lifecycle hardening now covers
    `FormController` and `FormWizardController`, keeping final form values,
    errors, submitted state, validation state, and wizard step readable after
    teardown while rejecting stale form/step mutations and invalidating late
    async validation results. Animation lifecycle hardening now covers
    `Ticker`, `FrameTicker`, and `Animation<T>`, keeping final timing, mute,
    and value state readable after teardown while rejecting stale post-dispose
    mute, snap, stop, and retarget mutations. Core selection/overlay lifecycle
    hardening now covers `SelectionContainerDelegate` and `OverlayEntry`,
    keeping cleanup removal idempotent while rejecting new registration,
    selection dispatch, rebuild, and visibility mutation after disposal.
    Focus manager lifecycle hardening now detaches focused/attached nodes on
    manager teardown, keeps node cleanup idempotent, and rejects post-dispose
    focus movement and key dispatch. Scheduler/binding lifecycle hardening now
    prevents disposed `TickerScheduler` and `TuiBinding` instances from being
    restarted through new ticker, reassemble, or post-frame registrations,
    while keeping shutdown drains and cleanup calls idempotent. Input
    dispatcher lifecycle hardening now clears pending sequences on teardown and
    rejects post-dispose event dispatch or global binding replacement. Final
    debug/test runtime hardening applies the same contract to
    `DebugCaptureRecorder` and `FakeTerminalDriver`: final captured/driver
    evidence remains readable after teardown, but new debug recording or fake
    terminal activity after disposal fails explicitly. The selection demo E2E
    also now proves Ctrl+C bubbles through app bindings so `runTui` can exit
    when the selection layer has no selected text to copy.
- [x] M3.8 Plugin and extension story for widgets, commands, themes, data
  sources, and workflow integrations.
  - Notes: First slice adds typed app-level extensions to the existing
    `FleuryApp` shell. `FleuryApp.extensions` registers plain domain/service
    objects; `FleuryAppController.extension<T>()`,
    `FleuryApp.extension<T>(context)`, and command-context
    `appExtension<T>()` expose them to widgets and commands. The seam is
    deliberately smaller than a plugin runtime: no package loading,
    discovery, adapter lifecycle, ACP, or Dune coupling. The static
    contribution convention now lets extensions that opt into
    `FleuryAppExtension` provide app-level commands, status items, and
    package-owned theme extension defaults plus typed data sources; app-owned
    commands and ambient host theme extensions still win collisions. The proof
    app now registers `ProofConsoleExtension`, reads it from screen builders
    and command enablement/action code, and lets the extension contribute the
    diagnostics command, stream/debug status items, `FleuryWidgetTheme`
    defaults, and `ProofSearchDataSource` global-search corpus in a separate
    package without broadening core. Current reusable-package slice adds
    `packages/fleury_git`, with `FleuryGitExtension`, Git command callbacks,
    app status, widget theme defaults, a typed repository data source,
    `GitStatusPanel`, and package tests for contribution, host precedence,
    disabled commands, semantic state, and theme override behavior. M3.8 is
    complete for the launch extension story: package-shaped integrations are
    static, typed, and app-owned; package discovery, loading, adapter
    lifecycle, and provider protocols remain future proof-driven work.
- [~] M3.9 Cross-framework comparative benchmarks and showcase apps.
  - MVP status: The peer-benchmark governance/checkpoint slice is complete for
    this cycle, and further peer comparison work is intentionally deferred
    until post-MVP. Resume only after Fleury's public API is stable and major
    core implementation work is done, so benchmark artifacts measure the
    launch shape rather than a moving target.
  - MVP execution rule: Existing M3.9 artifacts and tooling may be maintained
    only when they unblock or protect core/API stabilization. Do not start new
    peer fixtures, repeated-run families, full-scale parity runs,
    cross-machine runs, showcase comparison apps, or public comparison copy
    during the MVP cycle.
  - Notes: First slice adds
    [comparative-benchmark-manifest.json](comparative-benchmark-manifest.json)
    plus `dart tool/fleury_dev.dart benchmark-manifest`. The manifest maps
    Fleury's SB.1-SB.12 benchmark families to peer-equivalent contracts,
    required metrics, correctness gates, and primary peer targets while leaving
    `peerRuns` empty until matching peer fixtures are implemented and run. This
    starts M3.9 as a machine-readable evidence contract, not a public
    superiority claim. The current ingestion slice adds
    `dart tool/fleury_dev.dart benchmark-result`, which validates one peer-run
    artifact against known peers, scenario peer targets, required metrics, and
    passing claim gates before writing a manifest copy with that run appended to
    `peerRuns`. The checked-in manifest remains empty until real peer fixtures
    are implemented and run. Current peer-fixture slice adds
    [Nocterm SB.1 counter fixture](../../peer-fixtures/nocterm/sb1_counter),
    including a Nocterm `0.6.0` counter app, test-harness behavior test, JSON
    artifact producer, and a saved local 20-iteration
    [run artifact](../../peer-fixtures/nocterm/sb1_counter/results/nocterm-sb1-counter-2026-06-01.json).
    The artifact validates through `benchmark-result` and records
    `nocterm-test-harness` mode; it is evidence for fixture parity and local
    tester behavior, not a public real-terminal performance claim. The next
    peer slice adds
    [Nocterm SB.2 text editing fixture](../../peer-fixtures/nocterm/sb2_text_editing)
    with a 10k-character mixed-width editor, selection replacement, paste,
    redaction, and app-owned undo/history/completion adapters. The saved
    [SB.2 run artifact](../../peer-fixtures/nocterm/sb2_text_editing/results/nocterm-sb2-text-editing-2026-06-01.json)
    validates through `benchmark-result`; it records that Nocterm owns
    `TextField` while undo/redo, history, and completion are fixture-owned
    adapter code. The next text-editing peer slice adds
    [Textual SB.2 text editing fixture](../../peer-fixtures/textual/sb2_text_editing)
    with a 10k-character mixed-width editor, Textual `TextArea`, password
    `Input`, built-in cursor movement, selection, edit/paste APIs, and
    undo/redo, plus fixture-owned history and completion adapters. The saved
    [SB.2 run artifact](../../peer-fixtures/textual/sb2_text_editing/results/textual-sb2-text-editing-2026-06-02.json)
    validates through `benchmark-result`; it records
    `textual-run-test-harness` mode, widget/app-state queries instead of
    Fleury-equivalent semantic graph evidence, and no real-terminal evidence.
    The next Bubble Tea/Bubbles text-editing peer slice adds
    [Bubble Tea SB.2 text editing fixture](../../peer-fixtures/bubbletea/sb2_text_editing)
    with a 10k-character mixed-width editor, Bubble Tea model/update/view
    structure, Bubbles `textarea` cursor/edit/paste behavior, Bubbles
    `textinput` password masking and suggestions, plus fixture-owned
    selection, undo/redo, and history adapters. The saved
    [SB.2 run artifact](../../peer-fixtures/bubbletea/sb2_text_editing/results/bubbletea-sb2-text-editing-2026-06-02.json)
    validates through `benchmark-result`; it records
    `bubbletea-textarea-model-harness` mode, app-state queries instead of
    Fleury-equivalent semantic graph evidence, and no real-terminal evidence.
    The next Ink text-editing peer slice adds
    [Ink SB.2 text editing fixture](../../peer-fixtures/ink/sb2_text_editing)
    with a 10k-character mixed-width editor, Ink/React rendering,
    `react-ink-textarea`, `ink-text-input` single-line and password inputs,
    plus fixture-owned selection, redo, history, completion, and app-state
    query adapters. The saved
    [SB.2 run artifact](../../peer-fixtures/ink/sb2_text_editing/results/ink-sb2-text-editing-2026-06-02.json)
    validates through `benchmark-result`; it records
    `ink-testing-library-memory` mode, app-state/frame queries instead of
    Fleury-equivalent semantic graph evidence, and no real-terminal evidence.
    The repeated-run evidence slice adds
    `dart tool/fleury_dev.dart benchmark-variance`, which reads already
    validated `fleuryPeerBenchmarkRun` artifacts from files or directories,
    requires one peer/scenario group, reports consistency, per-metric spread,
    correctness gate counts, and a `strictPass` readiness boolean. The first
    saved
    [Ink SB.2 variance artifact](benchmark-variance/ink-sb2-text-editing-2026-06-02.json)
    summarizes three comparable local `ink-testing-library-memory` runs and
    passes strict mode, but it is still not real-terminal or cross-machine
    evidence. The follow-up
    [Nocterm SB.2 variance artifact](benchmark-variance/nocterm-sb2-text-editing-2026-06-02.json)
    summarizes three comparable local `nocterm-test-harness` runs and passes
    strict mode while showing high local timing spread, especially paste and
    test-query timings. This narrows the closest-Dart-peer evidence gap while
    reinforcing that public claims still need broader variance.
    The next text-framework variance slice adds the
    [Textual SB.2 variance artifact](benchmark-variance/textual-sb2-text-editing-2026-06-02.json),
    summarizing three comparable local `textual-run-test-harness` runs on
    Textual `8.2.7` and Python `3.12.13`. It passes strict mode while showing
    meaningful spread in history navigation and test-query timings, and should
    be compared internally until a matching-runtime set is collected for the
    older single Textual artifact.
    The next text-framework variance slice adds the
    [Bubble Tea SB.2 variance artifact](benchmark-variance/bubbletea-sb2-text-editing-2026-06-02.json),
    summarizing three comparable local `bubbletea-textarea-model-harness` runs
    on Bubble Tea `2.0.7` and Bubbles `2.1.0`. It passes strict mode while
    showing meaningful spread in paste, completion-accept, and app-state query
    timings. This completes the first local repeated-run pass across the main
    `SB.2` text-editing peer set: Ink, Nocterm, Textual, and Bubble
    Tea/Bubbles. Public claims still need real-terminal and cross-machine
    variance.
    The next non-Dart table peer slice adds
    [Textual SB.3 DataTable fixture](../../peer-fixtures/textual/sb3_datatable)
    with a 100k-row `DataTable`, public widget-state test query, priority
    jump-to-final-row binding, selected-row TSV copy/export, and a saved
    [SB.3 run artifact](../../peer-fixtures/textual/sb3_datatable/results/textual-sb3-datatable-2026-06-01.json)
    that validates through `benchmark-result`. It records Textual-owned table
    behavior, fixture-owned jump/copy commands, and `textual-run-test-harness`
    mode; it is not repeated real-terminal evidence. The Textual data-widget
    variance slice adds the
    [Textual SB.3 variance artifact](benchmark-variance/textual-sb3-datatable-2026-06-02.json),
    summarizing three comparable local `textual-run-test-harness` runs on
    Textual `8.2.7` and Python `3.12.13`. It passes strict mode while showing
    meaningful mount, page-move, jump-to-end, copy, and widget-state query
    spread. This completes local repeated-run coverage for the main `SB.3`
    data-widget peer set across Ratatui, OpenTUI, Nocterm, and Textual. Public
    claims still need real-terminal and cross-machine variance plus broader
    table/list ergonomics comparison. The next Textual peer
    slice adds
    [Textual SB.4 LogRegion fixture](../../peer-fixtures/textual/sb4_log_region)
    with a 100k-line `Log`, 1000 appended entries, unsafe terminal payloads,
    scrollback/tail movement, selected-entry copy, filter/search, and a saved
    [SB.4 run artifact](../../peer-fixtures/textual/sb4_log_region/results/textual-sb4-log-region-2026-06-01.json)
    that validates through `benchmark-result`. It records Textual-owned append
    rendering and scroll state, fixture-owned sanitization/redaction,
    filtering, selected-entry state, copy/export, and `textual-run-test-harness`
    mode; it is not repeated real-terminal evidence. The Textual log/viewport
    variance slice adds the
    [Textual SB.4 variance artifact](benchmark-variance/textual-sb4-log-region-2026-06-02.json),
    summarizing three comparable local `textual-run-test-harness` runs on
    Textual `8.2.7` and Python `3.12.13`. It passes strict mode while showing
    meaningful append, scrollback, copy, filter, and widget/app-state query
    spread, with unsafe artifact leak count zero in all three runs. This
    expands repeated-run coverage for the `SB.4` log/viewport peer set beyond
    Nocterm and OpenTUI. After the Bubble Tea/Bubbles variance slice below,
    the local `SB.4` repeat set is complete; public claims still need
    real-terminal variance, cross-machine variance, and deeper log/viewport
    ergonomics comparison. The next raw-rendering peer slice adds
    [Ratatui SB.3 DataTable fixture](../../peer-fixtures/ratatui/sb3_datatable)
    with 100k retained rows, Ratatui `Table`/`TableState`/`Buffer` rendering,
    fixture-owned visible-window slicing, navigation, selected-row copy/export,
    state/buffer query, and a saved
    [SB.3 run artifact](../../peer-fixtures/ratatui/sb3_datatable/results/ratatui-sb3-datatable-2026-06-01.json)
    that validates through `benchmark-result`. It records
    `ratatui-buffer-render-harness` mode and is not repeated real-terminal
    evidence. The first data-widget variance slice adds the
    [Ratatui SB.3 variance artifact](benchmark-variance/ratatui-sb3-datatable-2026-06-02.json),
    summarizing three comparable local `ratatui-buffer-render-harness` runs on
    Ratatui `0.30.0` and Rust `1.93.1`. It passes strict mode while showing
    meaningful page-move and app-state/buffer-query spread, with stable RSS
    spread. This starts repeated-run coverage for the `SB.3` peer set; public
    claims still need more data-widget peers, real-terminal variance, and
    cross-machine variance. The next native-core TypeScript peer slice adds
    [OpenTUI SB.3 DataTable fixture](../../peer-fixtures/opentui/sb3_datatable)
    with 100k retained rows, OpenTUI `TextTableRenderable` rendering, styled
    text chunks, fixture-owned visible-window slicing, navigation,
    selected-row copy/export, frame/app-state query, and a saved
    [SB.3 run artifact](../../peer-fixtures/opentui/sb3_datatable/results/opentui-sb3-datatable-2026-06-02.json)
    that validates through `benchmark-result`. It records
    `opentui-test-renderer-memory` mode and is not repeated real-terminal
    evidence. The native-core TypeScript data-widget variance slice adds the
    [OpenTUI SB.3 variance artifact](benchmark-variance/opentui-sb3-datatable-2026-06-02.json),
    summarizing three comparable local `opentui-test-renderer-memory` runs on
    OpenTUI `0.3.1` and Bun `1.3.14`. It passes strict mode while showing
    meaningful page-move, jump-to-end, copy, and frame/app-state query spread.
    This expands repeated-run coverage for the `SB.3` peer set beyond
    Ratatui and before the closest Dart-peer slice. Public claims still need
    real-terminal and cross-machine variance plus broader table/list ergonomics
    comparison. The closest Dart-peer table/list slice adds
    [Nocterm SB.3 DataTable fixture](../../peer-fixtures/nocterm/sb3_datatable)
    with 100k table-shaped rows, Nocterm `ListView.builder`,
    `ScrollController`, and `Text`, fixture-owned table formatting, retained
    rows, visible-window policy, selection, selected-row copy/export,
    terminal/app-state query, and a saved
    [SB.3 run artifact](../../peer-fixtures/nocterm/sb3_datatable/results/nocterm-sb3-datatable-2026-06-02.json)
    that validates through `benchmark-result`. It records
    `nocterm-test-harness` mode and is not repeated real-terminal evidence.
    The closest-Dart-peer data-widget variance slice adds the
    [Nocterm SB.3 variance artifact](benchmark-variance/nocterm-sb3-datatable-2026-06-02.json),
    summarizing three comparable local `nocterm-test-harness` runs on Nocterm
    `0.6.0` and Dart `3.12.1`. It passes strict mode while showing meaningful
    page-move and terminal/app-state query spread. This expands repeated-run
    coverage for the `SB.3` peer set; public claims still need real-terminal
    and cross-machine variance plus broader table/list ergonomics comparison.
    The next log/viewport peer slice adds
    [Bubble Tea SB.4 LogRegion fixture](../../peer-fixtures/bubbletea/sb4_log_region)
    with 100k starting log lines, 1000 appended entries, unsafe terminal
    payloads, scrollback/tail movement, selected-entry copy, filter/search, and
    a saved
    [SB.4 run artifact](../../peer-fixtures/bubbletea/sb4_log_region/results/bubbletea-sb4-log-region-2026-06-02.json)
    that validates through `benchmark-result`. It records Bubble Tea
    model/update/view structure, Bubbles viewport content/scroll primitives,
    fixture-owned sanitization/redaction, filtering, selected-entry state,
    copy/export, app/model-state query, and `bubbletea-viewport-model-harness`
    mode; it is not repeated real-terminal evidence. The Bubble Tea/Bubbles
    log/viewport variance slice adds the
    [Bubble Tea SB.4 variance artifact](benchmark-variance/bubbletea-sb4-log-region-2026-06-02.json),
    summarizing three comparable local `bubbletea-viewport-model-harness` runs
    on Bubble Tea `2.0.7`, Bubbles `2.1.0`, and Go `1.25.0`. It passes strict
    mode while showing meaningful append, scrollback, scroll-to-tail, filter,
    and app/model-state query spread, with unsafe artifact leak count zero in
    all three runs. This completes local repeated-run coverage for the main
    `SB.4` log/viewport peer set across Nocterm, OpenTUI, Textual, and Bubble
    Tea/Bubbles; public claims still need real-terminal variance,
    cross-machine variance, and deeper log/viewport ergonomics comparison. The
    next native-core log slice adds
    [OpenTUI SB.4 LogRegion fixture](../../peer-fixtures/opentui/sb4_log_region)
    with 100k starting log lines, 1000 appended entries, unsafe terminal
    payloads, tail anchoring, scrollback movement, selected-entry copy,
    filter/search, OpenTUI `TextRenderable` rendering, frame/app-state query,
    and a saved
    [SB.4 run artifact](../../peer-fixtures/opentui/sb4_log_region/results/opentui-sb4-log-region-2026-06-02.json)
    that validates through `benchmark-result`. It records
    `opentui-test-renderer-memory` mode and is not repeated real-terminal
    evidence. The next Dart-peer log
    slice adds
    [Nocterm SB.4 LogRegion fixture](../../peer-fixtures/nocterm/sb4_log_region)
    with 100k starting log lines, 1000 appended entries, unsafe terminal
    payloads, scrollback/tail movement, selected-entry copy, filter/search, and a
    saved
    [SB.4 run artifact](../../peer-fixtures/nocterm/sb4_log_region/results/nocterm-sb4-log-region-2026-06-02.json)
    that validates through `benchmark-result`. It records Nocterm-owned
    `ListView.builder`, `ScrollController`, and `Text`, fixture-owned
    sanitization/redaction, filtering, selected-entry state, copy/export,
    terminal/app-state query, and `nocterm-test-harness` mode; it is not
    repeated real-terminal evidence. The closest-Dart-peer log/viewport
    variance slice adds the
    [Nocterm SB.4 variance artifact](benchmark-variance/nocterm-sb4-log-region-2026-06-02.json),
    summarizing three comparable local `nocterm-test-harness` runs on Nocterm
    `0.6.0` and Dart `3.12.1`. It passes strict mode while showing meaningful
    scrollback, scroll-to-tail, copy, filter, and terminal/app-state query
    spread, with unsafe artifact leak count zero in all three runs. This starts
    repeated-run coverage for the `SB.4` log/viewport peer set; public claims
    still need the other `SB.4` peers, real-terminal variance, cross-machine
    variance, and deeper log/viewport ergonomics comparison. The native-core
    TypeScript log/viewport variance slice adds the
    [OpenTUI SB.4 variance artifact](benchmark-variance/opentui-sb4-log-region-2026-06-02.json),
    summarizing three comparable local `opentui-test-renderer-memory` runs on
    OpenTUI `0.3.1` and Bun `1.3.14`. It passes strict mode while showing
    meaningful append, scrollback, filter, and frame/app-state query spread,
    with unsafe artifact leak count zero in all three runs. This expands
    repeated-run coverage for the `SB.4` log/viewport peer set beyond the
    closest Dart peer. The full local repeated-run set is complete once the
    Textual and Bubble Tea/Bubbles variance slices are recorded above; public
    claims still need real-terminal variance, cross-machine variance, and
    deeper log/viewport ergonomics comparison.
    The first streaming-markdown peer slice adds the
    [Textual SB.5 Streaming Markdown fixture](../../peer-fixtures/textual/sb5_streaming_markdown)
    with 100 streamed chunks, Textual `Markdown.append`, unsafe OSC/secret
    payloads, unsafe link schemes, visible URL fallback, selected-block copy,
    markdown metadata query state, and a saved
    [SB.5 run artifact](../../peer-fixtures/textual/sb5_streaming_markdown/results/textual-sb5-streaming-markdown-2026-06-02.json)
    that validates through `benchmark-result`. It records Textual-owned
    Markdown parsing/rendering, append, focus, scrolling, and test harness
    behavior; sanitization/redaction, visible URL fallback, selected-block
    copy/export, markdown metadata, and widget/app-state query are
    fixture-owned app code. This is local `textual-run-test-harness` evidence
    at a 100-chunk scale, not repeated or full 1000-chunk Fleury baseline-scale
    evidence. Full-scale Textual `SB.5` was attempted locally but did not
    finish in a practical validation window, so it remains a separate long-run
    follow-up before public streaming-markdown claims. The next
    streaming-markdown peer slice adds the
    [Bubble Tea/Bubbles/Glamour SB.5 fixture](../../peer-fixtures/bubbletea/sb5_streaming_markdown)
    with 100 streamed chunks, Bubble Tea model/update/view, Bubbles viewport
    state, Glamour full-document terminal Markdown rendering, unsafe
    OSC/secret payloads, unsafe link schemes, visible URL fallback,
    selected-block copy, markdown metadata query state, and a saved
    [SB.5 run artifact](../../peer-fixtures/bubbletea/sb5_streaming_markdown/results/bubbletea-sb5-streaming-markdown-2026-06-02.json)
    that validates through `benchmark-result`. It records chunk-update p95
    145270 us, chunk-frame p95 16742 us, final-render p95 13567 us,
    selected-block-copy p95 72 us, app/model-state query p95 63 us, and zero
    unsafe frames. Sanitization/redaction, visible URL fallback,
    selected-block copy/export, markdown metadata, and app/model-state query
    remain fixture-owned app code. This is local model-harness evidence at a
    100-chunk scale. The streaming Markdown variance slice adds
    [Textual SB.5 variance](benchmark-variance/textual-sb5-streaming-markdown-2026-06-02.json)
    and
    [Bubble Tea/Bubbles/Glamour SB.5 variance](benchmark-variance/bubbletea-sb5-streaming-markdown-2026-06-02.json),
    each strict-passing over three comparable 100-chunk local runs with all
    correctness gates passing and unsafe frame count zero. This hardens local
    `SB.5` evidence, but it is still not full 1000-chunk peer parity,
    real-terminal variance, or cross-machine variance. This is the M3.9
    peer-benchmark stopping point for the MVP cycle: additional peer fixtures,
    OpenTUI/Ink `SB.5` equivalents, full-scale peer parity, cross-machine
    runs, and public comparison claims are deferred until post-MVP, after
    Fleury's API and major core implementation are stable.

**Exit criteria:**

- [~] Fleury enables apps that are easier to test, inspect, replay, operate
  remotely, adapt to terminal capabilities, and integrate with
  agent/developer workflows than peer frameworks.
  - MVP status: Local evidence exists for Fleury's testing, semantic
    inspection, targeted capture, remote shell/browser, capability-aware
    widgets, and protocol-neutral workflow surfaces. Public superiority claims
    still require post-MVP peer-equivalent runs, real-terminal variance, and
    cross-machine evidence after the launch API stabilizes.
