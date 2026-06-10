# Workstream: Effects, Workflow, And Process

## Purpose

Make async work, subprocesses, streams, permissions, progress, cancellation,
and terminal lifecycle handoff framework-native.

## Current State

- Fleury has runtime, output capture, clipboard, terminal lifecycle, input
  dispatch, and async widget foundations. `LogBuffer` now keeps final captured
  output readable after teardown while rejecting post-dispose appends.
- Fleury now has a first core worker/task model through `TaskController`,
  `TaskContext`, `TaskProgress`, `TaskOutput`, `TaskResult`, and
  `TaskStatusView`; running `TaskStatusView` nodes now expose semantic cancel
  through the same `TaskController.cancel` path as direct controller calls.
- `TaskController` now owns its disposal lifecycle: disposing an active
  controller cancels the active run, completes the active future as canceled,
  invalidates late async writes, and rejects post-dispose `start`/`reset`
  calls while keeping `cancel` idempotent.
- Fleury now has `DebouncedTaskController`, a core wrapper around
  `TaskController` for typeahead/search/index workloads that should coalesce
  pending input changes, cancel stale work, and preserve task progress, output,
  events, results, and semantics through the existing task model. Focused
  lifecycle coverage now proves pending-work cancellation on dispose,
  read-after-dispose task state, post-dispose misuse errors, idempotent
  cleanup cancel, and externally owned task-controller preservation.
- Fleury now has `TaskYieldPolicy` / `TaskYieldCheckpoint` for cooperative
  long-running task work. Large index builders can report progress, observe
  cancellation, and yield back to input/render handling without claiming
  isolate-backed execution.
- The demo app Global Search screen now uses `DebouncedTaskController` as the
  app-owned search task feeding `SearchPanel`, proving the primitive in an
  integrated workflow rather than only focused task tests.
- The demo app Indexed Logs screen now uses `TaskController` plus
  `TaskYieldPolicy` to build and refresh a `LogRegionSearchIndex`, proving
  cooperative progress/cancellation/yield checkpoints in an integrated app
  workflow.
- Native Fleury now has a first subprocess task wrapper through
  `ProcessTaskController` and a platform-neutral terminal handoff seam through
  `TerminalHandoffDriver` / `withTerminalHandoff`.
- `ProcessTaskController` now tracks current/last command metadata for process
  UI and semantic surfaces, clearing it on reset.
- `fleury_widgets` now includes `ProcessPanel`, which composes
  `ProcessTaskController` with `LogRegion` for status, progress, filtered
  output, selected-output copy, Escape or semantic cancellation, and task/log
  semantics.
- Native Fleury now includes `ProcessCommandRunner` and `ProcessCommandScope`
  to bind process start/cancel behavior into the app command registry without
  blocking command invocation until a long-running process exits.
- Native Fleury now includes `editTextInExternalEditor` for external editor
  workflows. It resolves explicit commands, `$VISUAL`, `$EDITOR`, and platform
  fallbacks; writes an editable temp buffer; runs the editor with inherited
  stdio; suspends/resumes the TUI through `TerminalHandoffDriver`; and returns
  edited text plus command/exit metadata.
- The demo app now includes a Process screen that runs `dart --version`
  through `ProcessCommandScope`, displays it through `ProcessPanel`, and
  asserts command semantics, exit code, output log semantics, and status bar
  updates.
- `ProcessPanel` task semantics now also feed text-first accessibility/fallback
  with command display, exit code, success/failure, and cancelability, keeping
  process evidence queryable in prompt fallback and debug artifacts.
- `fleury_widgets` now includes `TerminalOutputRegion`, which adapts runtime
  `LogBuffer` stdout/stderr capture into `LogRegion` for filtered, copyable,
  focusable, sanitized, semantic terminal-output regions. `LogBuffer` itself
  now has explicit lifecycle coverage so stale output writes after teardown do
  not silently mutate captured state.
- `fleury_widgets` now includes `ApprovalPrompt`, the first protocol-neutral
  approval workflow surface. It exposes semantic submit/cancel actions and is
  wired into the demo app command flow without adding ACP-specific models.
- `fleury_widgets` now includes `ToolCallCard`, the first protocol-neutral
  tool execution surface. It exposes tool-call status/progress/output
  semantics, sanitized copy, cancellation, and demo-app Process screen
  adoption without owning protocol transport.
- `fleury_widgets` now includes `TaskGraph`, the first protocol-neutral
  plan/task graph surface. It exposes workflow status/progress/dependency
  semantics and selected-task copy without owning scheduling.
- `SB.9 Subprocess Handoff And Untrusted Output` now gives app-shaped process
  benchmark evidence across a 1 MB target subprocess output stream, stderr
  failure, cancellation, external-editor handoff, terminal handoff restoration,
  and unsafe-output artifact checks.
- Fleury now has a first bounded structured task-event history through
  `TaskEvent` / `TaskEventKind`, exposed in task semantics for devtools,
  tests, and future replay hooks.
- Debug capture can now store safe, metadata-only task-event summaries for
  targeted workflow regression artifacts without serializing raw task output,
  result values, error messages, or stack traces.
- Debug capture can now store deterministic fake/replay clock markers for
  targeted workflow artifacts without recording wall-clock timestamps.
- M1.6 is complete for the MVP: task success/failure/cancellation/progress,
  bounded output, process execution, terminal handoff, task events, semantic
  state, and demo-app binding all have targeted test evidence.
- M0.7 defines prototype-first tracks for a deterministic fake task worker and
  subprocess handoff boundary before a broad public API is frozen.

## Target Capabilities

- Worker/task model with success, failure, cancellation, progress, and output.
- Subprocess execution with safe output capture and terminal lifecycle policy.
- Permission requests and approval flows as workflow primitives.
- Structured effect events and hook points for future replay.
- Debounced, restartable, cancellable, and long-running tasks.

## Milestone Checklist

- [x] EWP.1 Define structured effect event hooks.
  - Intent: Keep async/process work inspectable and future-replay-ready
    without requiring full replay at launch.
  - Acceptance: RFC covers input, resize, fake time, workers, subprocesses,
    terminal profiles, semantic snapshots, rendered frames, ordering, and
    failure cases.
  - Evidence: [Task events](../../../packages/fleury/lib/src/effects/task.dart),
    [task event tests](../../../packages/fleury/test/effects/task_test.dart),
    [process task event tests](../../../packages/fleury/test/effects/process_task_test.dart),
    [trace timeline task-event adapter](../../../packages/fleury_widgets/lib/src/trace_timeline.dart),
    [trace timeline task-event tests](../../../packages/fleury_widgets/test/trace_timeline_test.dart),
    [debug capture task-event summaries](../../../packages/fleury/lib/src/debug/debug_capture.dart),
    [debug capture tests](../../../packages/fleury/test/debug/debug_capture_test.dart).
  - Notes: Keep Phase 1 hooks minimal and structurally correct. Current slice
    covers worker/subprocess events; current debug-capture slice records safe
    task-event summaries and deterministic time markers for workflow
    regression artifacts. Current trace-timeline slice maps live task events
    into protocol-neutral workflow rows with task run/sequence/kind/progress,
    source, and output-safety metadata while excluding raw output text, result
    values, errors, and stack traces. Input, resize, frame, terminal-profile,
    and semantic snapshot hooks are covered by the debug capture workstream.
    EWP.1 is complete for the MVP through bounded event hooks and targeted
    capture-to-test evidence; full replay remains a later product track.

- [x] EWP.2 Define Worker API v1.
  - Intent: Provide safe async UI binding.
  - Acceptance: API covers progress, output, result, error, cancellation,
    restart, debounce, ownership, lifecycle cleanup, and semantic state.
  - Evidence: [Task controller](../../../packages/fleury/lib/src/effects/task.dart),
    [worker tests](../../../packages/fleury/test/effects/task_test.dart).
  - Notes: V0 intentionally does not leak isolate/process details. Phase 1
    covers controller/context ownership, lifecycle cleanup, cancellation,
    progress, output, semantic state, and demo-app binding. Current Phase 2
    slice adds `DebouncedTaskController` for restartable typeahead/search/index
    work without inventing a second task state model. The demo app Global
    Search screen is the first integrated consumer. Current cooperative-yield
    slice adds progress/cancellation/yield checkpoints for CPU-heavy work and
    proves them through `LogRegionSearchIndex` and `TreeTableSearchIndex`.
    Launch lifecycle hardening now makes active task disposal cancel the
    active future and freeze out late progress/output writes, which covers
    screen teardown and app shutdown without changing global `ChangeNotifier`
    behavior. Debounced lifecycle coverage now extends the same evidence to
    pending debounces, external task-controller ownership, and post-dispose
    schedule/run/reset misuse.
    Isolate pools and richer workflow primitives are later work.

- [x] EWP.3 Define subprocess and terminal handoff policy.
  - Intent: Avoid common TUI pain around raw mode, mouse mode, output loss,
    scrollback, and editor handoff.
  - Acceptance: Tests cover process output, cancellation, terminal restore,
    external editor handoff, and output capture boundaries.
  - Evidence: [Terminal handoff contract](../../../packages/fleury/lib/src/terminal/terminal_driver.dart),
    [fake-driver handoff tests](../../../packages/fleury/test/terminal/fake_driver_test.dart),
    [process task controller](../../../packages/fleury/lib/src/effects/process_task.dart),
    [process command runner](../../../packages/fleury/lib/src/effects/process_command_runner.dart),
    [external editor helper](../../../packages/fleury/lib/src/effects/external_editor.dart),
    [process task tests](../../../packages/fleury/test/effects/process_task_test.dart),
    [process command tests](../../../packages/fleury/test/effects/process_command_runner_test.dart),
    [external editor tests](../../../packages/fleury/test/effects/external_editor_test.dart),
    [ProcessPanel](../../../packages/fleury_widgets/lib/src/process_panel.dart),
    [ProcessPanel tests](../../../packages/fleury_widgets/test/process_panel_test.dart),
    [TerminalOutputRegion](../../../packages/fleury_widgets/lib/src/terminal_output_region.dart),
    [TerminalOutputRegion tests](../../../packages/fleury_widgets/test/terminal_output_region_test.dart),
    [SB.9 baseline](../../../packages/fleury_widgets/benchmark/results/phase2-subprocess-output-2026-06-01.json).
  - Notes: Coordinate with terminal capability/security. External editor
    handoff now has a native text-buffer helper and fake-driver coverage.
    `SB.9` adds repeated app-shaped pressure for success, non-zero exit,
    cancellation, editor handoff, runtime output capture, and unsafe-output
    artifact checks. First ProcessPanel slice deliberately reuses
    `ProcessTaskController` and `LogRegion` rather than introducing another
    process-output store.

- [x] EWP.4 Add workflow semantics.
  - Intent: Make tasks and permissions inspectable.
  - Acceptance: Semantic graph exposes task status, progress, logs, errors,
    approval actions, cancellation actions, and related output regions.
  - Evidence: `TaskStatusView` in
    [task.dart](../../../packages/fleury/lib/src/effects/task.dart), semantic
    assertions in [task_test.dart](../../../packages/fleury/test/effects/task_test.dart)
    and [demo_console_test.dart](../../../packages/fleury_example_console/test/demo_console_test.dart),
    plus [ProcessPanel tests](../../../packages/fleury_widgets/test/process_panel_test.dart)
    [approval prompt tests](../../../packages/fleury_widgets/test/approval_prompt_test.dart),
    [tool call card tests](../../../packages/fleury_widgets/test/tool_call_card_test.dart),
    and [task graph tests](../../../packages/fleury_widgets/test/task_graph_test.dart).
  - Notes: ProcessPanel now exposes task status, command display, exit code,
    latest output safety metadata, output log semantics, and cancel actions.
    Semantic cancel now dispatches through `ProcessTaskController.cancel`, the
    same path used by Escape and process command cancellation. Core
    `TaskStatusView` semantic cancel dispatches through
    `TaskController.cancel`, so generic task surfaces are operable without a
    process-specific panel. `ApprovalPrompt`
    now exposes generic approval submit/cancel semantics through widget
    callbacks. Permission-specific policy, agent request modeling, and richer
    approval lifecycle state remain pending. `ToolCallCard` now exposes
    generic tool-call copy/cancel semantics while leaving task/process
    ownership in the app or effects layer. `TaskGraph` exposes plan/task
    status semantics while leaving scheduling, dependency execution, and task
    ownership in app or effects code. `TraceTimeline` now exposes live
    task-event history as safe workflow semantics in the demo app, linking
    the worker/effects model to diagnostics without turning traces into raw
    output logs. EWP.4 is complete for the MVP; permission-specific lifecycle
    models remain future evidence-driven widgets or adapter-package work.

## Implementation Notes

- Effects must be observable enough for tests without making normal app code
  verbose.
- Long-running task state should compose with status bars, command palette,
  notifications, and replay.
- Terminal suspension and restoration must be treated as core behavior.
- [RFC 0012: App kernel](../../rfcs/0012-app-kernel.md) keeps command
  invocation separate from worker/effect execution. Commands may start or
  cancel work, but progress, output, cancellation, and replay hooks belong to
  this workstream.
- [RFC 0013: Capability and security contract](../../rfcs/0013-capability-security-contract.md)
  defines the safety boundary for subprocess output: plain sanitized output,
  restricted ANSI parsing, huge-line limits, malformed Unicode handling,
  redaction hooks, and policy-gated rich terminal features.
- [Prototype-first tracks](../prototype-first-tracks.md) defines the fake task
  worker and subprocess handoff prototype scenarios. Use those to shape the
  worker/task model before designing broad process APIs.
- The demo console now uses `TaskController` for its deterministic fake worker
  instead of ad hoc booleans. This gives command enablement, status bar output,
  progress UI, transcript evidence, and semantic task state one source of
  truth.
- `TerminalHandoffDriver` keeps the contract platform-neutral and lets native
  drivers restore user-facing terminal modes around subprocesses without
  making `fleury_core.dart` depend on `dart:io`.
- `ProcessTaskController` is exported from `package:fleury/fleury.dart` only;
  browser/remote hosts still import the portable task model from
  `fleury_core.dart`.
- `TaskEvent` history is bounded and sequence-numbered. It intentionally avoids
  timestamps; replay-clock evidence belongs in explicit debug-capture time
  markers so task streams do not become a wall-clock log.
- Debug capture task-event summaries intentionally omit raw output text, result
  values, error messages, and stack traces. Captures should explain workflow
  ordering and safety metadata without becoming a second task log that can leak
  app secrets.
- Native process output is decoded with malformed UTF-8 replacement, sanitized
  with `sanitizeForDisplay`, and capped before it enters task output, task
  events, semantics, or future debug capture.
- `ProcessPanel` is a UI binding, not a second process runner. Keep command
  start/cancel semantics in the app kernel or task controller; the panel should
  display and control the active task through existing controller state.
- `ProcessCommandRunner` treats command invocation as "start the process" rather
  than "wait for the process to finish." Process success, failure, cancellation,
  and output remain observable through `ProcessTaskController`.
- `ProcessCommandScope` listens to the process controller and rebuilds command
  semantics/shortcut enabled state as the process starts and stops.
- `editTextInExternalEditor` is native-only and intentionally function-sized:
  it is a temp-file handoff helper, not a subprocess DSL. Apps that need richer
  workflows can compose it with app commands, task status, and prompt flows.
- `TerminalOutputRegion` does not replace core `LogView` or `LogConsole`.
  `LogView` remains the minimal runtime/debug tail view; `TerminalOutputRegion`
  is the app-facing captured-output adapter when users need search/filter,
  selected-line copy, semantic focus/row activation, semantic log rows, and
  `LogRegion` safety behavior.
- `ApprovalPrompt` is deliberately UI-level workflow plumbing, not a
  permission-policy engine. Policy, provenance, and protocol mapping should
  remain app-owned or package-owned until concrete agent workflows justify a
  broader model.
- `ToolCallCard` is UI-level execution evidence, not a process runner or
  protocol executor. Keep start/cancel/progress ownership in commands,
  `TaskController`, `ProcessTaskController`, or adapter packages.
- `TaskGraph` is UI-level plan evidence, not a scheduler. Keep workflow
  execution, retries, dependencies, and persistence app-owned until measured
  scenarios justify a framework engine.
- The Phase 1 exit review reran task, process-task, fake terminal-handoff, and
  demo-app tests; all passed for the worker/process MVP.
- The first `SB.9` baseline runs a 1,000,000-byte target subprocess fixture
  plus failure, cancellation, external editor handoff, and captured-output
  streaming. Saved results show process-run p95 647254 us, cancellation p95
  11823 us, stream-frame p95 6230 us, semantic-query p95 1965 us, terminal
  handoff restored in all four paths, and zero unsafe visible/copy/semantic
  artifact leaks.

## Risks And Open Questions

- Too much abstraction could make simple async work feel heavy.
- Subprocess APIs can accidentally become a shell framework.
- Future replay fidelity may conflict with streaming performance if every
  chunk is recorded too verbosely.
- A process runner can easily become a shell DSL. Keep the native v0 bounded
  to start/capture/cancel/exit metadata until scenario benchmarks expose the
  next necessary abstraction.
- `ProcessPanel`, `ProcessCommandRunner`, `TerminalOutputRegion`, and
  `editTextInExternalEditor` prove status/output/cancel UX, command binding,
  native-process demo-app pressure, captured-output convergence, and external
  editor handoff. Further benchmark pressure should come only from concrete
  app scenarios that exceed existing log/output workloads.
- Handoff suppresses framework writes and forces repaint after resume. Process
  task output now has a first sanitizer/cap, but broader markdown/link/image
  and redaction policy still belongs to the sanitized output pipeline.
- Event history should stay bounded by default. Full replay artifacts need an
  explicit sink/storage design rather than growing controller memory without a
  cap.
- `DebouncedTaskController` is policy for coalescing and canceling stale work;
  `TaskYieldPolicy` is policy for cooperative progress/cancellation/yield
  checkpoints. Together they improve responsiveness for app-owned indexing, but
  they do not make CPU-bound indexing run off the main isolate by themselves.
  Worker/isolate boundaries remain separate launch-hardening work before Fleury
  can claim off-main indexing.
- Debounced task disposal should cancel pending timers/futures and detach
  listener ownership, but it should not dispose an externally supplied
  `TaskController`. Apps may share an app-owned task model across wrappers.

## Acceptance Evidence

- Pending RFC.
- [Prototype-first tracks](../prototype-first-tracks.md).
- [Task controller](../../../packages/fleury/lib/src/effects/task.dart).
- [Worker tests](../../../packages/fleury/test/effects/task_test.dart).
- [Cooperative LogRegion index baseline](../../../packages/fleury_widgets/benchmark/results/phase2-logregion-cooperative-index-2026-06-01.json).
- [Cooperative TreeTable index baseline](../../../packages/fleury_widgets/benchmark/results/phase2-treetable-cooperative-index-2026-06-01.json).
- [Demo app Global Search usage](../../../packages/fleury_example_console/lib/fleury_example_console.dart).
- [Demo app Global Search test](../../../packages/fleury_example_console/test/demo_console_test.dart).
- [Process task event tests](../../../packages/fleury/test/effects/process_task_test.dart).
- [Terminal handoff contract](../../../packages/fleury/lib/src/terminal/terminal_driver.dart).
- [Fake driver handoff tests](../../../packages/fleury/test/terminal/fake_driver_test.dart).
- [Process task controller](../../../packages/fleury/lib/src/effects/process_task.dart).
- [Process command runner](../../../packages/fleury/lib/src/effects/process_command_runner.dart).
- [External editor helper](../../../packages/fleury/lib/src/effects/external_editor.dart).
- [Process task tests](../../../packages/fleury/test/effects/process_task_test.dart).
- [Process command runner tests](../../../packages/fleury/test/effects/process_command_runner_test.dart).
- [External editor tests](../../../packages/fleury/test/effects/external_editor_test.dart).
- [ProcessPanel](../../../packages/fleury_widgets/lib/src/process_panel.dart).
- [ProcessPanel tests](../../../packages/fleury_widgets/test/process_panel_test.dart).
- [ApprovalPrompt](../../../packages/fleury_widgets/lib/src/approval_prompt.dart).
- [ApprovalPrompt tests](../../../packages/fleury_widgets/test/approval_prompt_test.dart).
- [ToolCallCard](../../../packages/fleury_widgets/lib/src/tool_call_card.dart).
- [ToolCallCard tests](../../../packages/fleury_widgets/test/tool_call_card_test.dart).
- [TaskGraph](../../../packages/fleury_widgets/lib/src/task_graph.dart).
- [TaskGraph tests](../../../packages/fleury_widgets/test/task_graph_test.dart).
- [TerminalOutputRegion](../../../packages/fleury_widgets/lib/src/terminal_output_region.dart).
- [TerminalOutputRegion tests](../../../packages/fleury_widgets/test/terminal_output_region_test.dart).
- [SB.9 subprocess/output baseline](../../../packages/fleury_widgets/benchmark/results/phase2-subprocess-output-2026-06-01.json).
- [Task output security semantics](../../../packages/fleury/lib/src/semantics/semantics.dart).
- [Demo app task wiring](../../../packages/fleury_example_console/lib/fleury_example_console.dart).
- [Demo app Process screen](../../../packages/fleury_example_console/lib/fleury_example_console.dart).
- [Demo app workflow tests](../../../packages/fleury_example_console/test/demo_console_test.dart).
- External-editor handoff tests cover command resolution, fake-driver
  suspend/resume, edited text metadata, temp cleanup, shell command wrapping,
  and non-zero editor exits.
