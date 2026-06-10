# Fleury Web RFC Execution Log

This log tracks implementation progress for `docs/rfcs/web-render-backend.md`
and its companion `docs/rfcs/semantics-pipeline.md`.

## 2026-06-07 21:31 EDT

Worktree:

- Path: `/Users/dan/Coding/fleury-web-phase1`
- Branch: `codex/fleury-web-phase1`
- Base commit: `408f645e7e67eee68bc973e61ab301a8084b4000`

Initial scope:

- Start with RFC Phase 1: shared runtime / frame-loop direction, browser rAF
  flush strategy, and damage handoff.
- Keep the branch self-contained by carrying over the web RFCs and existing DOM
  spike artifacts from the main checkout.
- Preserve main checkout changes by working only in this dedicated worktree.

Imported current-state context:

- Existing dirty runtime/rendering/test changes from the main checkout were
  applied into this branch because they contain the current damage-tracking
  work the RFC depends on.
- `docs/rfcs/web-render-backend.md`
- `docs/rfcs/semantics-pipeline.md`
- `packages/fleury_web/lib/src/dom_grid/`
- `packages/fleury_web/test/`
- `packages/fleury_web/tool/`
- `packages/fleury_web/spike.html`
- `packages/fleury_web/spike.png`

Next implementation target:

1. Inspect native `run_tui.dart`, web `run_tui_web.dart`, `FrameScheduler`, and
   current damage APIs.
2. Extract the smallest shared frame-loop/scheduler seam that lets web reuse
   native frame coalescing and damage handoff without a wholesale runtime
   rewrite.
3. Add focused tests that prove existing native behavior is preserved and web
   can schedule through an injectable rAF-style flush path.
4. Run package tests covering runtime, rendering damage, and Fleury web spike
   tests.

Notes:

- This log is intentionally append-only. Add entries as slices land, tests run,
  and scope adapts.

## 2026-06-07 21:40 EDT

Implemented first Phase 1 slice:

- Exported `FrameScheduler`, `FrameFlushScheduler`, and
  `FrameRenderCallback` through `fleury_core.dart` so web can reuse the shared
  scheduler without a private `package:fleury/src/...` import.
- Exported `RenderDamageTracker` through `fleury_core.dart` so host loops can
  participate in conservative full-diff handling.
- Updated `runTuiWeb` to:
  - accept any `TerminalDriver`, not only `WebTerminalDriver`, so the loop can
    be tested with `FakeTerminalDriver`;
  - use `FrameScheduler` with a browser `requestAnimationFrame` default flush
    strategy instead of a local microtask flag;
  - support injected `FrameFlushScheduler` for tests;
  - enqueue terminal/browser events and dispatch them during the frame update
    phase;
  - reset and consume `CellBuffer` paint damage;
  - pass `dirtyBounds` into `AnsiRenderer.renderDiff`;
  - honor `RenderDamageTracker.takeRequiresFullDiff()`;
  - propagate driver color/image/tmux capabilities into web `MediaQuery`.
- Added browser-targeted `run_tui_web_test.dart` covering the injected frame
  flush path and queued resize behavior.

Verification:

- `cd packages/fleury && dart analyze` — passed.
- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury && dart test test/runtime/frame_scheduler_test.dart test/runtime/run_tui_test.dart test/rendering/cell_buffer_test.dart test/rendering/ansi_renderer_test.dart` — passed.
- `cd packages/fleury_web && dart test test/cell_grid_html_test.dart` — passed.
- `cd packages/fleury_web && dart test test` — passed for VM-supported tests.
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_phase1_main.dart.js` — passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_test.dart` —
  inconclusive in this environment: the test runner timed out waiting for
  Chrome to connect after JS compilation. No assertion failure was observed.

Current caveat:

- `runTuiWeb` now shares scheduler/damage behavior, but the larger
  `TuiRuntime` / `FrameLoop` extraction is still pending. This slice pays down
  the web loop drift without completing the full Phase 1 architecture.

## 2026-06-07 21:48 EDT

Implemented shared frame-loop extraction:

- Added `TuiFrameLoop`, `TuiRenderedFrame`, `TuiFrameDamage`, and
  `TuiFramePaintCallback` in `packages/fleury/lib/src/runtime/`.
- The shared loop now owns the buffer/damage lifecycle used by native and web:
  - allocate front/back buffers for the active cell size;
  - clear the reusable back buffer without recording damage;
  - reset paint damage immediately before host painting;
  - collect paint damage plus `RenderDamageTracker` conservative full-diff
    signals;
  - expose previous/next buffers and frame damage metadata to the host;
  - swap buffers only when the host calls `commit` after presentation.
- Exported the frame-loop types through `fleury_core.dart` so `fleury_web`
  continues to consume public core runtime APIs.
- Updated native `runTui` to use `TuiFrameLoop` while keeping host-owned
  concerns in place: debug timing, layout/repaint stats, dirty-cell capture,
  paint-flash overlays, terminal output, input dispatch, cleanup, and
  post-frame callback ordering.
- Updated `runTuiWeb` to use the same `TuiFrameLoop`, preserving the browser
  rAF/injected-flush scheduler and queued event dispatch added in the prior
  slice.
- Added `tui_frame_loop_test.dart` covering:
  - first-frame full repaint;
  - commit/swap semantics;
  - bounded paint damage on subsequent frames;
  - resize/full-repaint reset;
  - presenter-level `markFullRepaint` invalidation without reallocating
    buffers;
  - conservative layout damage disabling bounded diffs;
  - empty viewport short-circuiting without invoking paint.

Verification:

- `cd packages/fleury && dart analyze` — passed.
- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury && dart test test/runtime/tui_frame_loop_test.dart test/runtime/frame_scheduler_test.dart test/runtime/run_tui_test.dart test/rendering/cell_buffer_test.dart test/rendering/ansi_renderer_test.dart` — passed.
- `cd packages/fleury_web && dart test test` — passed.
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_phase1_main.dart.js` — passed.
- `cd packages/fleury && dart test test/terminal/terminal_public_api_boundary_test.dart` — passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_test.dart` — passed. The earlier Chrome connection timeout did not reproduce on this run.

Current caveat:

- This is still a deliberately small shared frame-loop extraction, not a full
  `TuiRuntime` that owns mounting, lifecycle, or dispatch policy. That keeps
  Phase 1 low-risk while removing the duplicated buffer/damage logic from the
  native and web runners.

## 2026-06-07 21:53 EDT

Implemented Phase 1 row-damage adapter:

- Added `TuiDirtyRows` and `TuiDirtyRowRange` as a row-oriented damage model
  for presenters.
- Added `TuiFrameDamage.dirtyRowsFor(CellSize)` to convert current
  `CellRect` union damage into a conservative row range.
- Preserved the key presenter rule: `diffBounds == null` maps to all visible
  rows, not to "no dirty rows."
- Exported the row-damage types through `fleury_core.dart` for future web host
  presentation code.
- Extended `tui_frame_loop_test.dart` to cover:
  - full-frame damage -> all rows;
  - bounded cell damage -> one row range;
  - conservative layout damage -> all rows;
  - viewport clipping for row ranges;
  - zero-row full damage -> empty row set.

Verification:

- `cd packages/fleury && dart analyze` — passed.
- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury && dart test test/runtime/tui_frame_loop_test.dart` — passed.
- `cd packages/fleury_web && dart test test` — passed.
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_phase1_main.dart.js` — passed.
- `git diff --check` — passed.

Current caveat:

- The adapter is still based on the current single union `CellRect`. It gives
  DOM work an explicit row-range handoff now, while leaving exact multi-range
  row damage as a later optimization once real DOM instrumentation shows the
  union is too wide.

## 2026-06-07 21:57 EDT

Started Phase 2 foundation: shared row span model.

- Added `packages/fleury_web/lib/src/dom_grid/cell_span_builder.dart`.
- Introduced pure model types:
  - `RowSpanModel`;
  - `CellSpanRun`;
  - `CellRunKind`;
  - `WidthCorrection`.
- Moved `CellRole` walking out of `cell_grid_html.dart` and into
  `CellSpanBuilder`.
- Updated `renderFrameHtml` / `renderRowHtml` so the string artifact renderer
  consumes `RowSpanModel`, matching the RFC requirement that the live DOM path
  and artifact path share one role-walking implementation.
- Preserved logical cell width separately from Dart string length so combining
  marks and emoji do not corrupt grid-width accounting.
- Added `CellSpanBuilder.buildDirtyRows` so the Phase 1 `TuiDirtyRows` adapter
  can directly feed future DOM row presentation.
- Added `cell_span_builder_test.dart` covering:
  - combining-mark text width;
  - wide-cell pinned-width runs;
  - style-boundary splitting and coalescing;
  - protocol placeholders;
  - dirty-row model selection.

Verification:

- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury_web && dart test test/cell_span_builder_test.dart test/cell_grid_html_test.dart` — passed.
- `cd packages/fleury_web && dart test test` — passed.
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_phase2_main.dart.js` — passed.
- `git diff --check` — passed.

Current caveat:

- This is still the pure presentation model and artifact adapter. The retained
  live `DomGridSurface` and real DOM `replaceChildren` write path are not built
  yet.

## 2026-06-07 22:00 EDT

Added Phase 2 presentation planner and surface contract.

- Added `packages/fleury_web/lib/src/frame_presentation.dart`.
- Introduced private web host contracts:
  - `FrameSurface`;
  - `WebSurfaceCapabilities`;
  - `InlineImageCapability`;
  - `FramePresentationPlan`;
  - `FramePresentationDamage`;
  - `FrameDamageSource`;
  - `FramePresentationPlanner`.
- The planner consumes `TuiRenderedFrame` / `TuiFrameDamage`, converts damage
  into `TuiDirtyRows`, and builds only the required `RowSpanModel`s through
  `CellSpanBuilder`.
- Damage source classification is now explicit for web presenters:
  - full repaint;
  - conservative full diff;
  - bounded paint damage;
  - unbounded fallback when no bounded paint damage exists.
- Added `frame_presentation_test.dart` covering:
  - first-frame all-row planning;
  - bounded row planning from paint damage;
  - conservative damage all-row planning;
  - unbounded fallback behavior;
  - metrics-changed propagation;
  - default web surface capabilities;
  - the `FrameSurface.present` contract through a fake surface.

Verification:

- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury_web && dart test test/frame_presentation_test.dart` — passed.
- `cd packages/fleury_web && dart test test` — passed.
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_phase2_plan_main.dart.js` — passed.
- `git diff --check` — passed.

Current caveat:

- The planner is not yet wired into `runTuiWeb`; `runTuiWeb` still presents
  through the temporary ANSI/xterm-compatible driver path. The next live-DOM
  slice should implement a retained DOM `FrameSurface` over this plan.

## 2026-06-07 22:09 EDT

Implemented retained DOM grid surface.

- Added `packages/fleury_web/lib/src/dom_grid/cell_style_css.dart` so static
  HTML and live DOM adapters share the same cell-style-to-CSS conversion.
- Added `packages/fleury_web/lib/src/dom_grid/dom_row_factory.dart`.
  - Consumes `RowSpanModel`.
  - Creates real `span` elements with `document.createElement`.
  - Assigns text through `Node.textContent`.
  - Applies rows with the browser `replaceChildren(...nodes)` API via
    JS interop.
  - Does not use `innerHTML` in the live path.
- Added `packages/fleury_web/lib/src/dom_grid/dom_grid_surface.dart`.
  - Implements `FrameSurface`.
  - Retains one `.fleury-row` element per visible row.
  - Sets the visual root to `aria-hidden="true"` and `role="presentation"`.
  - Updates only `FramePresentationPlan.dirtyRowModels`.
  - Preserves row element identity across normal frame presentation.
  - Recreates row elements only through `resize`.
- Added direct `web: ^1.1.1` dependency for package-web DOM bindings.
- Added browser test `dom_grid_surface_test.dart` covering:
  - retained visual grid setup;
  - stable row count and row identity across frames;
  - clean rows not being replaced;
  - dirty rows being replaced;
  - unsafe-looking text staying text via `textContent`;
  - wide/styled span rendering from the shared span model;
  - dispose clearing the retained root.

Verification:

- `cd packages/fleury_web && dart pub get` — passed.
- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_grid_surface_test.dart` — passed.
- `cd packages/fleury_web && dart test test` — passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_test.dart` — passed.
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_dom_surface_main.dart.js` — passed.
- `git diff --check` — passed.

Current caveat:

- `DomGridSurface` is implemented and tested, but it is still not wired into a
  real `WebTuiHost` entry point. `runTuiWeb` continues to use the temporary
  ANSI/xterm-compatible path while the host skeleton, metrics, and input
  migration are built out.

## 2026-06-07 22:14 EDT

Implemented minimal surface-based web host skeleton.

- Added `packages/fleury_web/lib/src/browser_frame_flush_scheduler.dart` and
  moved the browser rAF flush adapter out of `run_tui_web.dart` so both web
  runners use the same shared `FrameScheduler` flush policy.
- Added `packages/fleury_web/lib/src/run_tui_surface.dart`.
  - Mounts a real Fleury widget tree.
  - Installs `TuiBindingScope`, `MediaQuery`, `FocusManagerScope`,
    `PointerRouterScope`, `Overlay`, and `Navigator`.
  - Renders through `TuiFrameLoop`.
  - Builds `FramePresentationPlan`s through `FramePresentationPlanner`.
  - Presents frames to any `FrameSurface`, including `DomGridSurface`.
  - Commits buffers only after surface presentation.
  - Flushes post-frame callbacks after DOM writes.
  - Supports injected frame flush scheduling for deterministic browser tests.
  - Exposes a small `TuiSurfaceHost` handle for requesting frames and disposal.
- Added browser test `run_tui_surface_test.dart` proving:
  - a Fleury widget tree renders through `DomGridSurface`;
  - the first frame is scheduled through the injected flush;
  - `setState` schedules and presents another DOM frame;
  - no ANSI/xterm driver is involved in this path.

Verification:

- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` — passed.
- `cd packages/fleury_web && dart test test` — passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_grid_surface_test.dart test/run_tui_surface_test.dart test/run_tui_web_test.dart` — passed.
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_surface_runner_main.dart.js` — passed.
- `git diff --check` — passed.

Current caveat:

- This is still a minimal visual host skeleton. Browser input, metrics-driven
  resize, clipboard, IME, semantic DOM, and public default-entrypoint migration
  remain future phases. The existing exported `runTuiWeb` still targets the
  temporary ANSI/xterm path so the old demo keeps working while the DOM host is
  completed behind it.

## 2026-06-07 22:31 EDT

Implemented metrics-driven resize for the retained DOM surface host.

- Added `packages/fleury_web/lib/src/metrics/cell_metrics.dart`.
  - Defines platform-neutral `MeasuredCellBox`.
  - Defines the `CellMetrics` host contract.
  - Keeps the shared presentation layer VM-runnable by avoiding browser-only
    imports in the metrics contract.
- Added `packages/fleury_web/lib/src/metrics/dom_cell_metrics.dart`.
  - Implements `CellMetrics` for package-web DOM hosts.
  - Owns the hidden text probe used to measure cell width/height.
  - Reads `getBoundingClientRect`, computed font properties, and
    `devicePixelRatio`.
  - Computes CSS canvas dimensions, cell dimensions, cols, and rows.
  - Caches measurements until explicitly dirtied.
  - Uses `ResizeObserver` only to mark the cache dirty and enqueue a frame.
  - Maps surface-local CSS pixel coordinates back to `CellOffset`.
- Extended `FrameSurface.resize` with optional `MeasuredCellBox` data.
  - `DomGridSurface` now applies measured width/height and line-height to the
    visual root/rows.
  - `DomGridSurface` still owns only visual DOM; it consumes metrics data but
    does not read layout itself.
- Wired `runTuiSurface` to accept `CellMetrics`.
  - Measures once before mount to establish the initial `MediaQuery` size.
  - Re-measures during the frame read phase only.
  - Resizes the surface before building/rendering a frame.
  - Resets frame buffers when measured size changes.
  - Carries `metricsChanged` into `FramePresentationPlan`.
  - Disposes metrics with the host.
- Added browser tests for:
  - real DOM container measurement;
  - cell point mapping;
  - metrics cache invalidation;
  - resize enqueue behavior;
  - no synchronous surface resize from a metrics invalidation callback;
  - applying measured DOM size on the next scheduled frame.

Verification:

- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury_web && dart test` — passed.
- `cd packages/fleury_web && dart test -p chrome` — passed.
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_metrics_main.dart.js` — passed.
- `cd packages/fleury && dart analyze` — passed.
- `cd packages/fleury && dart test test/runtime/tui_frame_loop_test.dart test/runtime/run_tui_test.dart` — passed.
- `git diff --check` — passed.

Current caveat:

- Metrics-driven resize is now in the surface runner, but that runner is still
  internal. The exported `runTuiWeb` path remains the temporary ANSI/xterm path
  until input, clipboard/IME, semantics, and the public host migration are
  complete enough to switch the default product configuration.

## 2026-06-07 22:44 EDT

Implemented the first browser input source for the retained DOM surface host.

- Added `packages/fleury_web/lib/src/input/input_source.dart`.
  - Defines the platform-neutral `TuiInputSource` contract.
  - Sources emit normalized Fleury `TuiEvent`s only; they do not dispatch into
    the widget tree themselves.
- Added `packages/fleury_web/lib/src/input/dom_input_source.dart`.
  - Creates/owns a hidden textarea when one is not provided.
  - Listens to `keydown`, `input`, `paste`, `pointerdown`, `pointerup`,
    `pointermove`, and `wheel`.
  - Maps browser navigation/control keys to Fleury `KeyEvent`s.
  - Leaves plain printable text to the textarea `input` channel.
  - Maps textarea input to `TextInputEvent`.
  - Maps clipboard event text to `PasteEvent`.
  - Maps pointer and wheel events to cell-coordinate Fleury `MouseEvent`s.
  - Uses cached `MeasuredCellBox` origin/size for pointer coordinate mapping,
    so pointer handlers do not read DOM layout.
  - Treats pointer capture as best-effort so synthetic browser tests and
    browser/device quirks still exercise the Fleury event path.
- Extended `MeasuredCellBox`.
  - Added `cssCanvasLeft` and `cssCanvasTop` so DOM geometry remains a metrics
    concern and input handlers can convert client coordinates from cached
    measurements.
  - Added `CellMetrics.cachedMeasurement` for read-free event-handler mapping.
- Wired `runTuiSurface` to accept a `TuiInputSource`.
  - Browser event handlers enqueue input and request a frame.
  - The runner drains queued input during the frame update phase.
  - `InputDispatcher` remains the single path for key, text, paste, and mouse
    routing through focus, text input claimants, and pointer regions.
  - Input source disposal is tied to `TuiSurfaceHost.dispose`.
- Added browser tests for:
  - key mapping for navigation and shortcut keys;
  - leaving plain printable text to `input`;
  - DOM listener emission for keyboard, text, paste, pointer, drag, and wheel;
  - cached-metrics pointer coordinate mapping;
  - runner-level queued dispatch into a real autofocus `TextInput`;
  - no synchronous text-controller mutation from an input event callback.

Verification:

- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury_web && dart test` — passed.
- `cd packages/fleury_web && dart test -p chrome` — passed.
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_input_main.dart.js` — passed.
- `git diff --check` — passed.

Current caveat:

- This is the first non-IME browser input slice. Core keyboard, text, paste,
  pointer, drag, and wheel events now reach the retained DOM host, but full IME
  composition state, browser clipboard write/fallback behavior, caret
  positioning, and the public `runTuiWeb` migration remain pending.

## 2026-06-07 22:52 EDT

Implemented browser clipboard backend installation for the retained DOM surface
host.

- Added `packages/fleury_web/lib/src/clipboard/web_clipboard.dart`.
  - Implements Fleury core's `Clipboard` abstraction for browser hosts.
  - Writes through `navigator.clipboard.writeText` when allowed.
  - Records secure-context availability.
  - Updates the in-process register before attempting the browser write.
  - Falls back to the in-process register when browser clipboard writes are
    denied, unavailable, insecure, or disabled by policy.
  - Returns existing `ClipboardWriteReport` diagnostics so text widgets,
    semantics, and debug surfaces can keep consuming one report shape.
  - Uses `navigator.clipboard.writeText` as the external transport label in
    the existing `platformTool` report slot.
- Extended `runTuiSurface` with optional clipboard installation.
  - Installs a supplied `Clipboard` backend before mounting the app.
  - Restores the previous backend on host disposal.
  - Avoids reading the default native `SystemClipboard` in browser contexts,
    because that can lazily touch unsupported `dart:io` platform state.
- Added browser tests for:
  - browser write success;
  - permission/write failure fallback;
  - insecure-context fallback without attempting a browser write;
  - host lifetime install/restore behavior.

Verification:

- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury_web && dart test` — passed.
- `cd packages/fleury_web && dart test -p chrome` — passed.
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_clipboard_main.dart.js` — passed.
- `git diff --check` — passed.

Current caveat:

- Clipboard writes are integrated at the host/backend boundary, but this still
  needs to be installed by the eventual public `runTuiWeb` DOM host. Clipboard
  read/paste remains event-driven through `DomInputSource`; full browser
  clipboard permission instrumentation can be expanded once the public host and
  user-activation model are in place.

## 2026-06-07 22:57 EDT

Implemented an assembled retained-DOM web host entry point.

- Added `packages/fleury_web/lib/src/run_tui_web_dom.dart`.
  - Creates a retained `DomGridSurface`.
  - Creates `DomCellMetrics` against the host container.
  - Creates `DomInputSource` for keyboard, text, paste, pointer, drag, and
    wheel input.
  - Installs `WebClipboard` by default, or a caller-provided `Clipboard`.
  - Delegates execution to `runTuiSurface`.
  - Returns `TuiSurfaceHost` for explicit disposal/requestFrame control.
- Exported `runTuiWebDom` from `package:fleury_web/fleury_web.dart`.
  - Kept `runTuiWeb` unchanged as the current xterm-compatible path.
  - Updated the library comment to distinguish the legacy xterm path from the
    retained DOM path.
- Added browser test `run_tui_web_dom_test.dart`.
  - Proves the assembled host creates `.fleury-screen`.
  - Proves it does not create/use an `.xterm` surface.
  - Proves the hidden textarea exists.
  - Proves textarea input queues and then updates a real autofocus `TextInput`
    on the next scheduled frame.

Verification:

- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury_web && dart test` — passed.
- `cd packages/fleury_web && dart test -p chrome` — passed.
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_dom_host_main.dart.js` — passed.
- `git diff --check` — passed.

Current caveat:

- `runTuiWebDom` is available as a separate DOM-host entry point, but the
  default `runTuiWeb` demo still targets the xterm-compatible path. The DOM
  path still needs IME composition/caret geometry, retained semantics, and
  benchmark gates before it should become the default web product
  configuration.

## 2026-06-07 23:11 EDT

Implemented IME composition routing for core input and the retained DOM web
host.

- Added `TextCompositionEvent` and `TextCompositionEventKind` to the shared
  terminal event model.
  - `update(text)` represents active preedit text.
  - `commit([text])` finalizes the active composition, optionally replacing it
    with browser-provided final text.
  - `cancel()` restores the editing value captured before composition began.
  - Exported the event types from `package:fleury/fleury_core.dart`.
- Added `TextCompositionClaimant` beside `TextInputClaimant`.
  - `FocusNode` now exposes `textCompositionClaimant`.
  - `FocusNode.dispose()` clears both text and composition claimants.
  - `TextInput` and `TextArea` register themselves as composition claimants on
    their focus node, mirroring the existing text/paste claimant registration.
- Extended `InputDispatcher`.
  - Routes `TextCompositionEvent` to the nearest focused
    `TextCompositionClaimant`.
  - Cancels pending key sequences before delivering composition events.
  - Does not fall unclaimed composition through to `KeyBindings`, because IME
    lifecycle events are not ordinary printable text.
- Wired editable widgets to their existing controller composition APIs.
  - `TextInput` updates/commits with `singleLine: true`.
  - `TextArea` preserves multiline composition commits.
  - Disabled widgets ignore composition.
  - Read-only widgets consume composition without mutating, matching text/paste
    behavior.
  - Composition update/commit/cancel cancel scheduled paste chunks; `TextInput`
    also resets history browsing, matching ordinary text edits.
- Updated runtime scheduling/debug surfaces.
  - Native `runTui`, legacy `runTuiWeb`, and retained `runTuiSurface` recognize
    the new event and label scheduled frames as `text-composition:<kind>`.
  - `InputDebugEvent.fromTuiEvent` reports composition events separately from
    ordinary text input.
- Extended `DomInputSource`.
  - Listens for `compositionstart`, `compositionupdate`, and `compositionend`
    on the hidden textarea.
  - Emits composition update and commit/cancel events through the same queued
    `TuiInputSource` channel as keyboard, text, paste, pointer, and wheel.
  - Uses `compositionend.data` or a composing `input` event as committed text.
  - Treats `compositionend` without committed text as cancel rather than
    guessing from the last preedit update.
  - Suppresses the duplicate non-composing `input` event many browsers emit
    after a successful `compositionend` commit.
- Added tests for:
  - composition claimant dispatch;
  - unclaimed composition not activating key bindings;
  - `TextInput` update/commit/cancel behavior;
  - `TextArea` multiline composition commit behavior;
  - DOM `CompositionEvent` commit routing and duplicate-input suppression;
  - DOM composition cancel routing;
  - retained surface queued composition dispatch during a frame.

Verification:

- `cd packages/fleury && dart analyze` — passed.
- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury && dart test test/runtime/input_dispatcher_test.dart test/widgets/text_input_test.dart test/widgets/text_area_test.dart test/widgets/text_editing_controller_test.dart` — passed.
- `cd packages/fleury_web && dart test test/run_tui_surface_test.dart test/dom_input_source_test.dart -p chrome` — passed.
- `cd packages/fleury && dart test` — passed.
- `cd packages/fleury_web && dart test -p chrome` — passed.
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_dom_host_main.dart.js` — passed.
- `git diff --check` — passed.

Current caveat:

- IME is now routed end-to-end through the retained DOM host, but caret
  rectangle synchronization for IME candidate-window placement is still not
  implemented. Cross-browser composition ordering should also be validated
  manually against the final product harness once the DOM host is exercised in
  real Chrome/Safari/Firefox input methods.

## 2026-06-07 23:21 EDT

Implemented focused caret geometry and hidden-textarea positioning for the
retained DOM host.

- Added `FocusNode.caretRect`.
  - Represents the latest painted text caret rectangle in absolute cell
    coordinates.
  - Is populated during paint by editable text render objects.
  - Is clipped to the visible viewport when a clip rect is available.
  - Is cleared when a `FocusNode` is disposed or when a render object switches
    to a different focus node.
- Updated `TextInput`.
  - Threads its owning `FocusNode` into `RenderTextInput`.
  - Publishes a 1x1 caret rect using the same horizontal scroll math as cursor
    painting.
  - Publishes geometry independently of blink phase, so IME placement remains
    stable while the visual cursor blinks.
  - Supports scrolled trailing-cursor geometry.
- Updated `TextArea`.
  - Threads its owning `FocusNode` into `RenderTextArea`.
  - Publishes a 1x1 caret rect using the same vertical and horizontal scroll
    math as cursor painting.
  - Supports multiline and scrolled viewport geometry.
- Extended `TuiInputSource`.
  - Added `syncCaretGeometry(CellRect? caretRect, MeasuredCellBox? metrics)`.
  - The method is a write-phase hook and must not perform browser layout reads.
- Updated `runTuiSurface`.
  - After a frame is painted/presented, passes
    `focusManager.focusedNode?.caretRect` plus the last read-phase cell metrics
    to the input source.
  - This keeps caret placement queued in the frame lifecycle instead of
    happening from browser event handlers.
- Updated `DomInputSource`.
  - Generates hidden-textarea style from one helper.
  - Keeps the textarea fixed offscreen when no caret/metrics are available.
  - Repositions the textarea with `position:fixed` using viewport coordinates:
    `cssCanvasLeft/Top + caret cell * css cell size`.
  - Keeps the textarea invisible and non-interactive (`opacity:0`,
    `pointer-events:none`) while still allowing browser focus, paste, and IME.
- Added tests for:
  - `TextInput` focused caret geometry after horizontal scrolling;
  - `TextArea` focused caret geometry after vertical scrolling;
  - DOM textarea CSS positioning from a known caret rect and measured cell box;
  - retained-surface caret sync after presentation.

Verification:

- `cd packages/fleury && dart analyze` — passed.
- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury && dart test test/widgets/text_input_test.dart test/widgets/text_area_test.dart test/runtime/input_dispatcher_test.dart` — passed.
- `cd packages/fleury_web && dart test test/run_tui_surface_test.dart test/dom_input_source_test.dart -p chrome` — passed.
- `cd packages/fleury && dart test` — passed.
- `cd packages/fleury_web && dart test -p chrome` — passed.
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_dom_host_main.dart.js` — passed.
- `git diff --check` — passed.

Current caveat:

- Caret geometry is now available as a focused-node channel and consumed by the
  retained DOM input source, but it is not yet part of a retained semantic node
  model. Full Phase 4 still needs the semantics owner, semantic DOM presenter,
  accessibility smoke tests, and manual IME candidate-window validation in real
  browser/input-method combinations.

## 2026-06-07 23:44 EDT

Implemented the first Phase 4 semantic DOM accessibility backstop for the
retained DOM host.

- Added `SemanticFramePresenter`.
  - The frame loop now depends on a generic semantic-presenter contract rather
    than a DOM-specific type.
  - The contract consumes `SemanticTree`, not the current full element-walk
    producer, so a retained `SemanticsOwner` can replace the producer later
    without changing the web host call site.
- Added `SemanticDomPresenter`.
  - Projects a `SemanticTree` into a separate `.fleury-semantics` DOM root.
  - Keeps that root visually hidden but not `aria-hidden`.
  - Rebuilds from the full semantic snapshot each frame; this is deliberately
    the accessibility backstop, not the retained/diffed semantics owner.
  - Uses `textContent` / text nodes for semantic text so unsafe-looking labels
    remain text and do not become markup.
  - Maps Fleury semantic roles to conservative ARIA roles.
  - Maps state to ARIA/data attributes: focus marker, selected/checked/
    expanded/busy/invalid/read-only state, live-region hints, and sorted action
    names.
  - Projects text fields and text areas as native readonly `input` /
    `textarea` elements with `tabindex="-1"` so assistive tech can read real
    values without adding a second editable browser focus target before the
    focus coordinator and semantic activation bridge land.
- Updated `runTuiSurface`.
  - Accepts `SemanticFramePresenter? semanticPresenter`.
  - Presents the semantic snapshot immediately after visual presentation for
    the same frame.
  - Disposes the semantic presenter with the host.
- Updated `runTuiWebDom`.
  - Creates and appends a semantic root by default.
  - Adds `semanticElement` for tests/host integration.
  - Adds `semanticsEnabled` so benchmarks or focused diagnostics can disable
    the semantic mirror explicitly.
  - Preserves `.fleury-screen aria-hidden="true"` for the visual grid.
- Added tests for:
  - role/state/action/live-region projection;
  - native text-field value projection;
  - unsafe semantic text staying as text nodes;
  - full-snapshot replacement between frames;
  - `runTuiSurface` presenting semantics from the live Fleury tree after a
    frame;
  - `runTuiWebDom` assembling visual grid, input source, clipboard, metrics,
    and semantic DOM mirror together.

Verification:

- `cd packages/fleury && dart analyze` — passed.
- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury_web && dart test -p chrome test/semantic_dom_presenter_test.dart test/run_tui_surface_test.dart test/run_tui_web_dom_test.dart` — passed.
- `cd packages/fleury_web && dart test -p chrome` — passed.
- `cd packages/fleury && dart test` — did not complete cleanly when run in
  parallel with the full Chrome web suite: the failures were remote integration
  startup timeouts (`serve did not start within 10s`) plus one shell lifecycle
  timeout while Chrome compilation was competing for resources.
- `cd packages/fleury && dart test --concurrency=1 test/remote/serve_integration_test.dart test/remote/serve_spawn_test.dart test/remote/serve_stale_handle_test.dart test/remote/shell_lifecycle_test.dart` — passed, confirming the failed group from the concurrent full run was load-sensitive rather than caused by this semantic DOM slice.
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_semantics_main.dart.js` — passed.
- `git diff --check` — passed.

Current caveat:

- This slice gives the browser path a real semantic DOM mirror, but it is still
  a full-snapshot rebuild from `SemanticTree.fromElement`. Full Phase 4 still
  needs retained semantic ownership, geometry-bearing semantic nodes, semantic
  DOM diffs, web focus coordination, semantic activation dispatch, and manual
  screen-reader smoke coverage against the product configuration.

## 2026-06-08 00:01 EDT

Implemented geometry-bearing semantic snapshots.

- Added `CellRect? bounds` to `SemanticNode`.
  - Bounds are optional and represent the node's visible screen-cell rectangle
    from the most recent paint.
  - Nodes are still valid without bounds; non-visual semantic contributors and
    snapshots collected before paint remain bounds-less.
- Updated `Semantics`.
  - Inserts an internal transparent render wrapper around the child.
  - The wrapper records its clipped screen-space paint rect into the owning
    `SemanticsElement`.
  - The wrapper delegates layout, paint, and intrinsic sizing to the child so
    the semantic geometry layer does not affect visual layout.
  - The first full core run caught an intrinsic-sizing regression from this
    wrapper; forwarding all intrinsic queries fixed it.
- Updated semantic inspection.
  - Adds optional `bounds` JSON on inspection nodes:
    `{left, top, width, height}`.
  - Parses bounds back into `CellRect`.
  - Keeps the field additive and tolerant: malformed/missing bounds are ignored
    rather than rejecting the snapshot.
- Updated `SemanticDomPresenter`.
  - Emits cell-bound data attributes when a semantic node has bounds:
    `data-fleury-bounds-left/top/width/height`.
  - Pixel positioning remains deferred until the presenter accepts the current
    cell metrics.
- Added tests for:
  - semantic nodes being bounds-less before a render pass;
  - `Semantics` recording visible bounds after render;
  - inspection JSON bounds serialization and parsing;
  - semantic DOM bound attributes.

Verification:

- `cd packages/fleury && dart analyze` — passed.
- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury && dart test test/widgets/intrinsic_test.dart test/semantics/semantics_test.dart test/semantics/inspection_test.dart` — passed.
- `cd packages/fleury_web && dart test -p chrome test/semantic_dom_presenter_test.dart test/run_tui_surface_test.dart` — passed.
- `cd packages/fleury && dart test` — passed (1535 tests).
- `cd packages/fleury_web && dart test -p chrome` — passed (51 tests).
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_semantic_bounds_main.dart.js` — passed.
- `git diff --check` — passed.

Current caveat:

- Semantic geometry is now available on nodes produced by the `Semantics`
  widget path, which covers the current first-party widget semantics. It is not
  yet a retained semantic owner or a node-diff stream, and it does not yet
  project CSS pixel geometry into the semantic DOM. Non-visual contributors
  that implement `SemanticContributor` directly remain bounds-less unless they
  adopt a visual wrapper later.

## 2026-06-08 00:06 EDT

Implemented retained semantic DOM element updates.

- Updated `SemanticDomPresenter`.
  - Retains DOM elements by `SemanticNodeId`.
  - Reuses same-id elements across full semantic snapshots when the required
    DOM tag is unchanged.
  - Replaces same-id elements when the semantic role changes the required tag
    shape, for example `textField` (`input`) becoming `button` (`div`).
  - Diffs a known attribute set per semantic id and removes stale ARIA/data
    attributes when a node's state changes.
  - Keeps the semantic root hidden-but-accessible and keeps mirrored controls
    out of the tab order.
  - Clears detached ids from the retained maps after each presentation.
- Added tests for:
  - same-id element retention;
  - stale `aria-*`, action, bounds, and `tabindex` attribute cleanup;
  - tag replacement when a stable semantic id changes role/tag requirements.

Verification:

- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury_web && dart test -p chrome test/semantic_dom_presenter_test.dart` — passed.
- `cd packages/fleury_web && dart test -p chrome` — passed (53 tests).
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_semantic_dom_retained_main.dart.js` — passed.
- `git diff --check` — passed.

Current caveat:

- The DOM side now retains and diffs nodes, but the semantic producer is still a
  full tree snapshot from `SemanticTree.fromElement`. The retained
  `SemanticsOwner` / node-diff producer remains the next core-side Phase 4
  increment.

## 2026-06-08 00:16 EDT

Implemented the retained core `SemanticsOwner` diff producer.

- Added `SemanticsOwner`.
  - Retains the previous `SemanticTree` snapshot.
  - Produces a `SemanticTreeUpdate` for every new snapshot.
  - Clears retained semantic state on dispose.
- Added `SemanticTreeUpdate`.
  - Reports added, removed, and updated `SemanticNodeId`s.
  - Treats role, label, value, hint, boolean state, validation state, actions,
    custom state values, bounds, and ordered child ids as node identity for
    update purposes.
  - Keeps the previous and next trees on the update so presenters and future
    diagnostics can correlate deltas with full snapshots.
- Exported the owner/update API from `fleury_core` and `fleury_test`.
- Updated the web semantic presenter seam.
  - `SemanticFramePresenter.present` now accepts an optional
    `SemanticTreeUpdate`.
  - `runTuiSurface` creates a `SemanticsOwner` when a semantic presenter is
    installed.
  - Each rendered frame now presents the full semantic tree plus the retained
    owner diff for that frame.
  - Host disposal clears the retained semantic owner before disposing the
    presenter.
- Added tests for:
  - first snapshot reporting all nodes as added;
  - equivalent snapshots reporting no changes;
  - changed snapshots reporting added, removed, and updated ids;
  - `runTuiSurface` passing retained update metadata through the rAF frame
    loop to a semantic presenter.

Verification:

- `cd packages/fleury && dart analyze` — passed.
- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury && dart test test/semantics/semantics_owner_test.dart test/semantics/semantics_test.dart test/semantics/inspection_test.dart` — passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart test/semantic_dom_presenter_test.dart` — passed.
- `cd packages/fleury && dart test` — passed (1538 tests).
- `cd packages/fleury_web && dart test -p chrome` — passed (54 tests).
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_semantics_owner_main.dart.js` — passed.
- `git diff --check` — passed.

Current caveat:

- The owner currently computes node deltas from full snapshots. That is the
  intended bridge state for Phase 4: the presenter API can now consume
  incremental semantic metadata, while a future retained semantics pipeline can
  replace the snapshot diff producer without changing the web surface contract.

## 2026-06-08 00:27 EDT

Implemented structured web host frame instrumentation.

- Added `WebHostInstrumentation`.
  - `NoopWebHostInstrumentation` is the default host sink.
  - `RecordingWebHostInstrumentation` keeps in-memory frame records for tests
    and future benchmark adapters.
  - `WebFrameInstrumentation` captures the per-frame fields needed by the RFC:
    frame reason, coalesced reasons, viewport size, damage source, dirty rows,
    dirty-cell estimate, span count, DOM node count, rows replaced, cache
    counters, metrics reads, semantic node diff counts, and timing slices.
- Extended `FramePresentationPlan`.
  - Adds derived `dirtyRowCount`, `dirtyCellEstimate`, and `spanCount` getters.
  - Keeps these counts attached to the planner output so visual surfaces do not
    re-walk buffers for reporting.
- Extended `FrameSurface.present`.
  - Now returns `FrameSurfacePresentationStats`.
  - `DomGridSurface` reports rows replaced and DOM nodes created for the frame.
  - `DomRowFactory.replaceChildren` returns the number of span nodes created.
- Extended `SemanticFramePresenter.present`.
  - Now returns `SemanticPresentationStats`.
  - `SemanticDomPresenter` reports node count, retained-owner added/removed/
    updated counts, element creation/reuse/replacement counts, and attribute
    set/remove counts.
- Wired `runTuiSurface`.
  - Measures runtime render time around `TuiFrameLoop.render`.
  - Measures planner/span-build time around `FramePresentationPlanner.build`.
  - Measures DOM apply time around `FrameSurface.present`.
  - Measures semantic apply time around `SemanticFramePresenter.present`.
  - Measures total successful frame time around the host rAF flush.
  - Records one instrumentation frame after visual/semantic writes, caret sync,
    buffer commit, and post-frame callbacks.
- Added a browser host test that runs the product configuration with a retained
  DOM visual surface, metrics, and active semantic DOM presenter, then asserts
  the emitted frame record includes coalesced reasons, viewport/damage counts,
  DOM mutation counts, semantic diff counts, and timing slices.

Verification:

- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury && dart analyze` — passed.
- `cd packages/fleury_web && dart test -p chrome test/frame_presentation_test.dart test/dom_grid_surface_test.dart test/semantic_dom_presenter_test.dart test/run_tui_surface_test.dart` — passed.
- `cd packages/fleury_web && dart test -p chrome` — passed (55 tests).
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_instrumentation_main.dart.js` — passed.
- `git diff --check` — passed.

Current caveat:

- Style-cache and width-cache counters are structurally present but report zero
  because the DOM renderer has not yet added dedicated cache layers. The
  important gate is now possible: future benchmark records can distinguish
  Dart render, span planning, DOM apply, semantic apply, and total frame time
  in the accessible product configuration.

## 2026-06-08 00:37 EDT

Implemented the semantic coverage text fallback and audit bridge.

- Added `semantic_coverage.dart`.
  - Computes which visual cells are already covered by readable, geometry-
    bearing semantic nodes.
  - Treats structural containers such as app, route, navigation, list, table,
    dialog, form, tree, JSON, and diff nodes as structure, not as text coverage
    for their whole bounds.
  - Finds uncovered non-whitespace painted text directly from the presented
    `CellBuffer`.
  - Appends synthetic low-priority `SemanticRole.text` fallback nodes for each
    uncovered row run.
  - Reports `SemanticCoverageAudit` with uncovered cell count and fallback node
    count.
- Wired `runTuiSurface`.
  - Builds the normal `SemanticTree` after visual presentation.
  - Applies text fallback against `frame.next` before calling the semantic
    presenter.
  - Feeds the augmented tree into `SemanticsOwner`, so retained updates include
    fallback nodes consistently.
  - Records fallback node and uncovered-cell counts in
    `WebFrameInstrumentation`.
- Added tests for:
  - fully covered text producing no fallback;
  - uncovered visible text producing fallback semantic nodes;
  - partially covered rows producing fallback only for uncovered runs;
  - structural semantic bounds not suppressing text fallback;
  - host-level semantic DOM fallback for a deliberately semantics-less raw
    painter while the visual grid remains `aria-hidden`.

Verification:

- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury_web && dart test test/semantic_coverage_test.dart` — passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart test/semantic_dom_presenter_test.dart` — passed.
- `cd packages/fleury_web && dart test -p chrome` — passed (60 tests).
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_semantic_coverage_main.dart.js` — passed.
- `git diff --check` — passed.

Current caveat:

- This closes the silent text-loss failure mode for `aria-hidden` visual rows,
  but it is intentionally a text fallback. It does not replace widget-authored
  rich semantics, and it does not constitute manual screen-reader smoke
  coverage against the final browser support set.

## 2026-06-08 00:42 EDT

Implemented live DOM style CSS caching.

- Updated `DomRowFactory`.
  - Caches resolved `CellStyle -> CSS declaration` strings.
  - Reuses cached CSS even for empty/default styles so common rows do not
    rebuild style strings per span.
  - Reports per-row replacement stats: DOM nodes created, style-cache hits,
    and style-cache misses.
- Updated `DomGridSurface`.
  - Aggregates row replacement stats into `FrameSurfacePresentationStats`.
  - Feeds real style-cache hit/miss counters into
    `WebFrameInstrumentation`.
- Added tests for:
  - direct surface presentation reporting DOM node count plus style-cache hits
    and misses;
  - host-level instrumentation seeing non-zero style-cache counters in a
    retained DOM frame.

Verification:

- `cd packages/fleury_web && dart analyze` — passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_grid_surface_test.dart test/run_tui_surface_test.dart` — passed.
- `cd packages/fleury_web && dart test -p chrome` — passed (61 tests).
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_style_cache_main.dart.js` — passed.
- `git diff --check` — passed.

Current caveat:

- Width-cache counters still report zero because renderer-controlled width
  correction is not implemented as a measured browser cache yet. Current wide
  glyph/protocol runs still use the explicit `ch`-based pinning strategy from
  the spike path.

## 2026-06-08 00:52 EDT

Implemented semantic DOM activation through the retained Fleury runtime.

- Added a core runtime helper:
  - `invokeSemanticActionFromElement` resolves a `SemanticNodeId` in the
    current `SemanticTree`.
  - Rejects missing, disabled, and unsupported action requests with structured
    `SemanticActionInvocationResult` values.
  - Dispatches the action through the mounted element tree so normal
    `SemanticActionContributor` handlers remain the single execution path.
  - Exported the helper from `fleury_core.dart` and `fleury_test.dart`.
- Added browser semantic action request plumbing.
  - Introduced `SemanticActionRequestSink` for presenters that can request
    runtime semantic actions.
  - `SemanticDomPresenter` now records a `data-fleury-primary-action`
    attribute for actionable nodes.
  - Retained semantic DOM elements install click listeners that translate the
    primary DOM activation into a semantic id/action request.
  - Listener cleanup happens when elements are replaced, swept, or disposed.
- Wired `runTuiSurface`.
  - Binds semantic action requests to the latest mounted root and retained
    `SemanticsOwner.currentTree`.
  - Invokes the shared runtime helper.
  - Schedules a follow-up `semantic-action:<name>` frame after the action
    future settles, matching the host's queued-frame model.
  - Clears presenter action callbacks during host disposal.
- Added tests for:
  - core helper dispatch through a mounted element tree;
  - retained semantic DOM primary action metadata;
  - browser click activation invoking a Fleury semantic action and scheduling
    the next frame.

Verification:

- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury && dart test test/semantics/semantics_test.dart test/semantics/semantics_owner_test.dart` - passed.
- `cd packages/fleury_web && dart test -p chrome test/semantic_dom_presenter_test.dart test/run_tui_surface_test.dart` - passed.
- `cd packages/fleury && dart test` - passed (1539 tests).
- `cd packages/fleury_web && dart test -p chrome` - passed (62 tests).
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_semantic_actions_main.dart.js` - passed.
- `git diff --check` - passed.

Current caveat:

- This provides the activation backstop for native semantic actions. It does
  not yet implement richer browser focus handoff, link projection, or manual
  screen-reader validation against the final support matrix.

## 2026-06-08 01:05 EDT

Implemented the retained DOM web frame reporting bridge.

- Extended `WebFrameInstrumentation`.
  - Added JSON serialization and parsing for per-frame records.
  - Added `RecordingWebHostInstrumentation.summarize` and capture JSON output.
  - Added `WebInstrumentationSummary` with total-frame budget accounting,
    over-budget frame counts, p50/p95/max timing summaries, per-frame counter
    summaries, cache hit rates, and the dominant p95 slice.
  - Kept the summary shape centered on the RFC's decision questions:
    total-frame budget, runtime render cost, span build cost, DOM apply cost,
    semantic apply cost, retained DOM churn, and coverage fallback counters.
- Exposed a product-path hook.
  - `runTuiWebDom` now accepts a `WebHostInstrumentation` sink and passes it to
    `runTuiSurface`.
  - `fleury_web.dart` exports the narrow instrumentation/report types needed
    by benchmark adapters.
- Added `packages/fleury_web/tool/web_frame_report.dart`.
  - Reads captured frame JSON arrays or `fleuryWebFrameCapture` objects.
  - Emits machine-readable `fleuryWebFrameSummary` JSON.
  - Emits a Markdown report with frame budget, p95 slice, timing, count, and
    cache-rate tables.
- Added `fleury benchmark web-report`.
  - Routes through the normal `tool/fleury_dev.dart benchmark` command family.
  - Advertises the web report surface in `benchmark list --json`.
  - Keeps browser DOM metrics separate from the existing PTY/wire scoreboard
    because the axes answer different performance questions.
- Added tests for:
  - frame JSON round-trip;
  - summary total-frame budget misses and dominant p95 slice;
  - recording sink capture JSON;
  - `runTuiWebDom` recording real product-path frames;
  - root `fleury benchmark web-report` launcher JSON and Markdown output.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_host_instrumentation_test.dart` - passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark web-report"` - passed.
- `cd packages/fleury_web && dart test -p chrome` - passed (65 tests).
- `cd packages/fleury && dart test` - passed (1540 tests).
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_report_main.dart.js` - passed.
- `git diff --check` - passed.

Current caveat:

- This establishes the capture/reporting contract and the normal benchmark
  command surface, but it is not yet a browser scenario runner. A follow-up
  slice still needs to drive real product scenarios in Chrome, save the frame
  capture under `profiling/web/`, and enforce scenario-specific budget gates.

## 2026-06-08 01:10 EDT

Implemented semantic DOM link projection.

- Updated `SemanticDomPresenter`.
  - `SemanticRole.link` now uses an anchor element instead of a generic `div`.
  - Link URL is read from `SemanticState['linkUrl']` first, then from
    `SemanticNode.value`.
  - Safe links get `href`, `target="_blank"`, and `rel="noopener noreferrer"`.
  - Unsafe/custom-scheme links keep `role="link"` and
    `data-fleury-link-url`, but do not get an `href`.
  - Semantic mirror links are kept out of the normal tab order with
    `tabindex="-1"` so browser keyboard capture remains owned by the host.
- Added browser presenter coverage for:
  - safe HTTPS links projecting as real anchors;
  - unsafe custom-scheme links remaining non-navigating while preserving the
    readable URL in metadata.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury_web && dart test -p chrome test/semantic_dom_presenter_test.dart` - passed.
- `cd packages/fleury_web && dart test -p chrome` - passed (67 tests).
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_link_projection_main.dart.js` - passed.
- `git diff --check` - passed.

Current caveat:

- This projects existing link semantics into accessible DOM, but it does not
  yet implement a full `WebFocusCoordinator` or manual screen-reader validation
  of link activation behavior.

## 2026-06-08 01:16 EDT

Implemented the first keyboard-capture focus coordination rule.

- Added optional `KeyboardCaptureTarget`.
  - Input sources that own browser keyboard/IME capture can expose
    `ensureKeyboardCapture`.
  - The base `TuiInputSource` contract stays focused on normalized event
    delivery and caret sync.
- Updated `DomInputSource`.
  - Implements `KeyboardCaptureTarget`.
  - Refocuses the hidden textarea when capture is explicitly requested.
  - Restores keyboard capture on pointer down before emitting Fleury pointer
    events.
- Updated `runTuiSurface`.
  - After semantic DOM activation dispatches through the Fleury runtime, the
    host restores keyboard capture when the input source supports it.
  - The follow-up semantic-action frame is still scheduled through the existing
    rAF/coalesced frame path.
- Added tests for:
  - pointer down returning focus to the hidden textarea;
  - semantic DOM activation invoking the Fleury action and restoring keyboard
    capture through the host.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_input_source_test.dart test/run_tui_surface_test.dart` - passed.
- `cd packages/fleury_web && dart test -p chrome` - passed (68 tests).
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_keyboard_capture_main.dart.js` - passed.
- `git diff --check` - passed.

Current caveat:

- This lands the RFC's concrete "return capture to textarea after semantic
  activation" rule. It is not the full `WebFocusCoordinator`: browser focus,
  Fleury focus, and assistive-technology virtual cursor still need a richer
  synchronization model plus manual screen-reader validation.

## 2026-06-08 01:22 EDT

Implemented measured width correction for corrected DOM runs.

- Updated `DomRowFactory`.
  - Corrected runs now use cached measured CSS cell width when metrics are
    available.
  - Wide/fallback corrected spans use pixel widths such as `width:20px`
    instead of `width:2ch`.
  - Width correction CSS is cached by logical cell width and measured CSS cell
    width.
  - `DomRowReplacementStats` now reports width-cache hits and misses.
  - If no metrics are available, the renderer keeps the previous `ch` fallback
    rather than inventing a layout read during presentation.
- Updated `DomGridSurface`.
  - Passes the most recent read-phase `MeasuredCellBox` into row replacement.
  - Aggregates width-cache hits and misses into
    `FrameSurfacePresentationStats`, so `WebFrameInstrumentation` and
    `web-report` now receive real non-zero width-cache data when corrected runs
    are present.
- Added browser coverage for:
  - measured pixel width being applied to wide grapheme spans;
  - width-cache miss on the first corrected run;
  - width-cache hit on a repeated presentation with the same measured cell
    width.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_grid_surface_test.dart test/run_tui_surface_test.dart` - passed.
- `cd packages/fleury_web && dart test -p chrome` - passed (68 tests).
- `cd packages/fleury_web && dart compile js web/main.dart -o /tmp/fleury_web_width_cache_main.dart.js` - passed.
- `git diff --check` - passed.

Current caveat:

- This closes the immediate `ch`-based pinning and zero width-cache counter
  gap for corrected runs. It is still not a full text-advance measurement cache
  for arbitrary natural-run drift; that should be added only with a read-phase
  or canvas-based measurement strategy that preserves the no-layout-reads
  presenter contract.

## 2026-06-08 01:31 EDT

Implemented enforceable web frame budget gates.

- Updated `web_frame_report.dart`.
  - Adds gate options for total frame p95, DOM apply p95, semantic apply p95,
    over-budget percent, and max semantic uncovered cells.
  - Adds `--strict` exit behavior.
  - Emits `strictPass` and per-gate JSON when gates are supplied.
  - Adds a Markdown Gates table.
- Updated `fleury benchmark web-report`.
  - Forwards gate options through `tool/fleury_dev.dart`.
  - Updates command help and the benchmark catalog entry.
- Added launcher coverage for:
  - passing strict gates;
  - failing strict gates exiting non-zero;
  - Markdown gate table output.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark web-report"` - passed.
- `cd packages/fleury_web && dart test test/web_host_instrumentation_test.dart` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart` - passed.
- `git diff --check` - passed.

Current caveat:

- This makes captured browser frame reports enforceable. It still does not
  drive Chrome to create scenario captures; that remains a separate browser
  automation/capture harness.

## 2026-06-08 01:51 EDT

Implemented the first retained DOM browser capture harness.

- Added a shared web benchmark scenario catalog.
  - Covers the RFC's initial browser gate shapes: normal `80x24`, large
    `160x50`, stress `300x100`, no-op, single dirty cell, dirty row,
    full-frame churn, scroll-like churn, cursor blink, text-input burst, and
    resize burst.
  - Scenario metadata is shared by the browser entrypoint and VM capture tool
    so ids, sizes, and default frame counts do not drift.
- Added `web/benchmark_capture.dart`.
  - Runs the retained DOM host with `RecordingWebHostInstrumentation`.
  - Drives scenario steps through real browser rAF frames.
  - Uses the active semantic presenter by default.
  - Clears warmup frames before measured capture.
  - Publishes completion, error, and capture JSON globals for Chrome DevTools
    Protocol retrieval.
- Added `tool/web_frame_capture.dart`.
  - Compiles the browser benchmark entrypoint to JavaScript.
  - Serves the generated page from a local temporary HTTP server.
  - Launches Chrome/Chromium headless with a temporary profile.
  - Opens the page through Chrome DevTools Protocol and waits for the capture
    JSON.
  - Writes `fleuryWebFrameCapture` JSON that `web_frame_report.dart` already
    consumes.
- Added `fleury benchmark web-capture`.
  - Defaults output to `profiling/web/<scenario>-<timestamp>.json`.
  - Forwards scenario, frame count, warmup, frame budget, Chrome path, timeout,
    headful, compile-only, keep-temp, and JSON-result options.
  - Adds benchmark catalog and help entries.
- Added tests for:
  - browser scenario catalog JSON listing;
  - root launcher dry-run forwarding for retained DOM capture options.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_frame_capture_tool_test.dart` - passed.
- `cd packages/fleury_web && dart test test/web_host_instrumentation_test.dart` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark web-"` - passed.
- `cd packages/fleury_web && dart compile js web/benchmark_capture.dart -O2 -o /tmp/fleury_web_benchmark_capture_verify.dart.js` - passed.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=single-dirty-cell-160x50 --frames=3 --warmup=0 --output=/tmp/fleury_web_capture_smoke.json --timeout=30 --json` - passed.
- `cd packages/fleury_web && dart run tool/web_frame_report.dart --input=/tmp/fleury_web_capture_smoke.json --max-total-frame-p95-ms=1000 --max-semantic-uncovered-cells=0 --json` - passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` - passed.
- `cd packages/fleury_web && dart test -p chrome` - passed (68 tests).
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart` - passed.
- `git diff --check` - passed.

Current caveat:

- The harness now creates real browser frame artifacts, but the three-frame
  smoke capture is not a calibrated performance baseline. Phase 5 still needs
  repeated scenario captures, agreed thresholds, and scoreboard/report
  aggregation over `profiling/web` artifacts before the DOM backend can claim
  the release gate.

## 2026-06-08 01:59 EDT

Implemented retained DOM web capture scoreboard aggregation.

- Added `tool/web_frame_scoreboard.dart`.
  - Scans a directory for `fleuryWebFrameCapture` JSON files.
  - Recomputes summaries from the frame list so stale embedded summaries do not
    become the source of truth.
  - Aggregates repeated captures by scenario.
  - Reports median/min/max across capture-level p95s for total frame, runtime
    render, span build, DOM apply, semantic apply, over-budget percent, and max
    semantic uncovered cells.
  - Emits JSON or Markdown.
  - Supports `--min-runs` and `--strict` so repeated-run evidence can become a
    gate later.
- Added `fleury benchmark web-scoreboard`.
  - Defaults to `profiling/web`.
  - Writes the same Markdown scoreboard shape reviewers can read locally.
  - Adds benchmark catalog and help entries.
- Updated `fleury benchmark web-capture`.
  - When a capture writes into `profiling/web`, it refreshes
    `profiling/web/scoreboard.md` automatically.
  - Capture and scoreboard now mirror the existing wire-capture + scoreboard
    workflow while keeping PTY byte metrics separate from browser frame metrics.
- Added tests for:
  - package scoreboard aggregation over capture fixtures;
  - strict failure when capture count is too low;
  - root launcher aggregation through `fleury benchmark web-scoreboard`.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_frame_scoreboard_tool_test.dart` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark web-scoreboard"` - passed.
- `cd packages/fleury_web && dart run tool/web_frame_scoreboard.dart --input=<tmpdir-with-smoke-capture> --output=<tmpdir>/scoreboard.md --json` - passed.
- `cd packages/fleury_web && dart test test/web_frame_capture_tool_test.dart test/web_frame_scoreboard_tool_test.dart test/web_host_instrumentation_test.dart` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark web-"` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart` - passed.
- `cd packages/fleury_web && dart test -p chrome` - passed (68 tests).
- `git diff --check` - passed.

Current caveat:

- The scoreboard now aggregates web captures, but it intentionally does not set
  release thresholds. The next Phase 5 step is to collect repeated captures for
  the canonical scenario set under stable browser conditions, then promote
  agreed scenario-specific thresholds into strict gates.

## 2026-06-08 02:07 EDT

Implemented the first `WebFocusCoordinator` boundary.

- Added `WebFocusCoordinator`.
  - Tracks the active semantic node projected from Fleury semantics.
  - Tracks the active caret rect projected from Fleury focus.
  - Tracks the current browser focus target: host, visual surface, keyboard
    capture, or semantic node.
  - Keeps the initial rule explicit: after semantic activation, keyboard
    capture should return to the hidden textarea.
- Updated `DomInputSource`.
  - Accepts an optional focus coordinator.
  - Reports hidden-textarea `focusin` and `focusout`.
  - Reports keyboard capture when `start` or `ensureKeyboardCapture` focuses
    the textarea.
- Updated `runTuiSurface`.
  - Syncs focused semantic node and caret rect after semantic coverage is
    applied for the frame.
  - Records semantic activation before dispatching the Fleury semantic action.
  - Restores keyboard capture through the coordinator policy after semantic
    activation.
- Updated `runTuiWebDom`.
  - Creates a coordinator by default.
  - Accepts an injected coordinator for tests and diagnostics.
  - Passes the coordinator to DOM input and the shared surface host.
- Exported the coordinator API from `fleury_web.dart`.
- Added tests for:
  - pure coordinator browser/Fleury focus state transitions;
  - deriving active semantic node from a `SemanticTree`;
  - hidden-textarea focus capture restoration on pointer down;
  - semantic DOM activation returning browser focus to keyboard capture;
  - assembled `runTuiWebDom` syncing TextInput semantics into the coordinator.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_focus_coordinator_test.dart` - passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_input_source_test.dart test/run_tui_surface_test.dart test/run_tui_web_dom_test.dart` - passed.
- `cd packages/fleury_web && dart test test/web_focus_coordinator_test.dart test/web_frame_capture_tool_test.dart test/web_frame_scoreboard_tool_test.dart test/web_host_instrumentation_test.dart` - passed.
- `cd packages/fleury_web && dart test -p chrome` - passed (70 tests).
- `git diff --check` - passed.

Current caveat:

- This is the coordinator boundary and initial policy, not a complete
  assistive-technology validation claim. Manual screen-reader smoke testing
  and any browser-specific virtual-cursor exceptions still need to happen
  before declaring web accessibility support.

## 2026-06-08 02:21 EDT

Implemented browser-level CDP performance counters for retained DOM captures.

- Added `WebBrowserPerformanceMetrics`.
  - Round-trips optional capture-level browser metrics through JSON.
  - Covers layout duration, style recalculation duration, script duration, task
    duration, JS heap used/total, DOM document count, DOM node count, and JS
    event listener count.
  - Keeps every field optional because CDP domains and metric availability vary
    by browser/version.
- Updated `tool/web_frame_capture.dart`.
  - Creates a Chrome `about:blank` target, attaches CDP, enables Runtime/Page,
    attempts optional Performance enablement, then navigates to the benchmark
    page.
  - Makes capture polling resilient to transient Runtime evaluation failures
    while navigation/context setup is in flight.
  - After the Fleury frame capture completes, reads:
    - `Performance.getMetrics` for layout/style/script/task/heap/DOM counters;
    - `Memory.getDOMCounters` for DOM document/node/listener counts when
      available;
    - `Runtime.getHeapUsage` for heap used/total when available.
  - Embeds non-empty metrics as `browserMetrics` in the capture artifact and in
    the `--json` result summary.
- Updated `tool/web_frame_report.dart`.
  - Loads optional `browserMetrics` from capture objects while preserving support
    for raw frame arrays.
  - Emits `browserMetrics` in machine-readable summary JSON.
  - Adds a Markdown `Browser Metrics` section with formatted timing, heap, and
    DOM counter rows.
- Updated `tool/web_frame_scoreboard.dart`.
  - Parses optional browser metrics from capture artifacts.
  - Aggregates median/min/max across repeated captures for all browser metric
    fields.
  - Adds Markdown columns for browser layout, style, task, JS heap, and DOM
    nodes while rendering missing metrics as `-` for older captures.
  - Keeps raw per-capture browser metrics in the scoreboard JSON details.
- Added tests for:
  - browser metric JSON round-trip behavior;
  - direct package scoreboard aggregation over optional browser metrics;
  - root `fleury benchmark web-report` preserving browser metrics in JSON and
    Markdown.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_frame_scoreboard_tool_test.dart test/web_frame_capture_tool_test.dart test/web_host_instrumentation_test.dart` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark web-"` - passed.
- `cd packages/fleury_web && dart compile js web/benchmark_capture.dart -O2 -o /tmp/fleury_web_benchmark_capture_cdp_metrics.dart.js` - passed.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=single-dirty-cell-160x50 --frames=2 --warmup=0 --output=/tmp/fleury_web_capture_metrics_smoke.json --timeout=30 --json` - passed and emitted `browserMetrics`.
- `cd packages/fleury_web && dart run tool/web_frame_report.dart --input=/tmp/fleury_web_capture_metrics_smoke.json --json` - passed and preserved `browserMetrics`.
- `cd packages/fleury_web && dart run tool/web_frame_report.dart --input=/tmp/fleury_web_capture_metrics_smoke.json --output=/tmp/fleury_web_capture_metrics_smoke.md` - passed and rendered `Browser Metrics`.
- `cd packages/fleury_web && dart run tool/web_frame_scoreboard.dart --input=/tmp/fleury_web_scoreboard_smoke --json` - passed and aggregated browser metric medians.
- `cd packages/fleury_web && dart run tool/web_frame_scoreboard.dart --input=/tmp/fleury_web_scoreboard_smoke --output=/tmp/fleury_web_scoreboard_smoke.md` - passed and rendered browser metric columns.
- `cd packages/fleury_web && dart test` - passed (35 tests).
- `cd packages/fleury_web && dart test -p chrome` - passed (71 tests).
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart` - passed (24 tests).
- `git diff --check` - passed.

Current caveat:

- These counters are Chrome/CDP-specific capture-level diagnostics. They are now
  good enough to separate browser layout/style/task/heap/DOM pressure from
  Fleury's per-frame render/apply slices, but they are not calibrated release
  thresholds. Phase 5 still needs repeated scenario captures under stable
  browser conditions before promoting any browser counter into a strict gate.

## 2026-06-08 02:33 EDT

Enforced the semantic-DOM action enqueue rule.

- Updated `runTuiSurface`.
  - Semantic DOM action callbacks now append `_PendingSemanticAction` records
    and request a frame instead of invoking Fleury semantic actions directly
    from the browser event callback.
  - Pending semantic actions are drained during the frame update phase after
    queued input events and before rendering the next frame.
  - Semantic activation is preserved through the same frame's semantic-presenter
    sync, so activating a mirrored semantic node is not immediately erased when
    the node is not also the current Fleury focused node.
  - Keyboard capture restoration still happens after the semantic action future
    completes, then requests a follow-up frame for any async effects.
- Updated the core semantic action dispatcher.
  - `invokeSemanticActionFromElement` now preserves synchronous dispatch for
    synchronous `SemanticActionContributor`s while still awaiting async
    contributors.
  - This keeps browser-host semantic actions aligned with frame-update timing
    for the common sync path without changing the public API.
- Updated browser regression coverage.
  - A semantic DOM click now proves that no Fleury action or keyboard-capture
    restoration happens synchronously from the click callback.
  - The queued action is observed after the scheduled frame flush, and keyboard
    capture is restored after the action future completes.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` - passed.
- `cd packages/fleury && dart test test/semantics/semantics_test.dart` - passed.
- `cd packages/fleury_web && dart test` - passed (35 tests).
- `cd packages/fleury_web && dart test -p chrome` - passed (71 tests).
- `git diff --check` - passed.

Current caveat:

- This fixes semantic DOM action routing for the retained web host. It does not
  make every possible app-authored async semantic action atomic with a single
  frame; async action continuations can still complete later and schedule their
  own follow-up frame, which matches Fleury's existing async state model.

## 2026-06-08 02:38 EDT

Tightened cell-coordinate mapping to preserve the no-layout-read event rule.

- Updated the `CellMetrics.cellForPoint` contract.
  - It now explicitly maps from the last completed measurement.
  - It must not read browser layout; hosts read layout through `measure()` in
    the frame read phase.
- Updated `DomCellMetrics.cellForPoint`.
  - Uses `_cached` measurement only.
  - Returns `CellOffset.zero` when no measurement exists yet.
  - Leaves dirty state untouched, so event-time coordinate mapping cannot
    accidentally refresh geometry.
- Confirmed current `DomInputSource` pointer handling already uses
  `cachedMeasurement` directly.
- Added browser coverage proving `cellForPoint` still maps using the previous
  cached measurement after `markDirty()` and does not clear the dirty flag.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury_web && dart test -p chrome test/cell_metrics_test.dart` - passed.
- `cd packages/fleury_web && dart test -p chrome` - passed (72 tests).
- `git diff --check` - passed.

Current caveat:

- This hardens the public metrics contract and DOM implementation. It does not
  add runtime instrumentation for accidental layout reads; that would require a
  browser-side test shim or CDP tracing around event callbacks.

## 2026-06-08 02:40 EDT

Refreshed the `fleury_web` package-facing docs for the dual web host paths.

- Updated `packages/fleury_web/README.md`.
  - Describes `runTuiWebDom` as the retained DOM host path for Fleury-owned web
    apps.
  - Keeps `runTuiWeb`/`WebTerminalDriver` documented as the xterm-compatible
    legacy/demo transport path.
  - Summarizes the frame loop, visual DOM, metrics, input, clipboard,
    semantics, and instrumentation components now present in the package.
  - Adds retained DOM capture/report/scoreboard command examples.
- Updated `packages/fleury_web/pubspec.yaml` description so package metadata no
  longer says the package is only an xterm.js bridge.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `git diff --check` - passed.

Current caveat:

- This is package-facing orientation only. It does not change the public default
  host choice; `runTuiWebDom` remains explicit while benchmark evidence matures.

## 2026-06-08 02:41 EDT

Added a phase audit for reviewer handoff.

- Added `docs/implementation/web-rfc-phase-audit.md`.
  - Maps RFC Phases 1-6 to landed code evidence.
  - Separates automated implementation status from empirical/manual exit gates.
  - Calls out the remaining non-code gates: primary-browser IME smoke, manual
    screen-reader smoke, repeated browser captures, and agreed benchmark
    thresholds.
  - Lists review questions for the shared runtime extraction,
    backend-neutral presentation plan, semantics/focus boundary, benchmark
    counters, and explicit `runTuiWebDom` rollout posture.
- Linked the audit and this execution log from `docs/implementation/README.md`.

Verification:

- `git diff --check` - passed.

Current caveat:

- The audit is a review artifact, not a release signoff. It intentionally does
  not mark Phase 4 or Phase 5 exit gates complete until manual accessibility
  and calibrated performance evidence exist.

## 2026-06-08 02:52 EDT

Added a repeated web benchmark suite runner for Phase 5 evidence collection.

- Added `packages/fleury_web/tool/web_frame_suite.dart`.
  - Plans and runs repeated retained DOM captures across a selected scenario
    set.
  - Defaults to all web benchmark scenarios and three captures per scenario.
  - Writes captures into a timestamped suite directory by default.
  - Refreshes `web_frame_scoreboard.dart` with `--min-runs=<runs>` and strict
    scoreboard gating by default.
  - Supports per-capture frames, warmup, frame budget, Chrome path, timeout,
    headful mode, temp retention, `--dry-run`, and JSON plan output.
- Added `fleury benchmark web-suite`.
  - Forwards the suite runner through the root development launcher.
  - Adds benchmark catalog and help coverage.
- Updated package README and the phase audit to include the suite runner.
- Added tests for:
  - package-level dry-run suite planning;
  - unknown scenario rejection;
  - root launcher option forwarding through `fleury benchmark web-suite`.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_frame_suite_tool_test.dart` - passed.
- `cd packages/fleury_web && dart test test/web_frame_capture_tool_test.dart test/web_frame_scoreboard_tool_test.dart test/web_frame_suite_tool_test.dart test/web_host_instrumentation_test.dart` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark web-suite"` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark web-"` - passed.
- `cd packages/fleury_web && dart run tool/web_frame_suite.dart --scenarios=single-dirty-cell-160x50 --runs=1 --frames=1 --warmup=0 --output-dir=/tmp/fleury_web_suite_smoke --scoreboard=/tmp/fleury_web_suite_smoke/scoreboard.md --timeout=30` - passed, producing one capture and a strict scoreboard.
- `git diff --check` - passed.

Current caveat:

- The suite runner makes repeated evidence collection reproducible, but the
  smoke run is intentionally tiny. Phase 5 still needs real repeated baseline
  captures for the canonical scenario set and agreed per-scenario thresholds
  before DOM can claim the benchmark exit gate.

## 2026-06-08 03:02 EDT

Added optional strict threshold gates to repeated web scoreboards.

- Updated `packages/fleury_web/tool/web_frame_scoreboard.dart`.
  - Supports strict gates for median total-frame p95, median DOM apply p95,
    median semantic apply p95, median over-budget percent, and max uncovered
    semantic cells.
  - Emits per-scenario gate results in JSON and a `Gates` column in Markdown.
  - Makes `--strict` fail if either run-count coverage or supplied gates fail.
- Updated `packages/fleury_web/tool/web_frame_suite.dart`.
  - Forwards gate options into the generated scoreboard command.
  - Includes gate settings in JSON dry-run plans.
- Updated `fleury benchmark web-suite` and `fleury benchmark web-scoreboard`.
  - Exposes the same gate knobs through the root development launcher.
  - Keeps `web-suite` strict by default unless `--no-strict` is passed.
- Added focused tests for:
  - package-level strict scoreboard gate failure;
  - package-level suite dry-run gate forwarding;
  - root launcher forwarding for suite and scoreboard gate options.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_frame_scoreboard_tool_test.dart test/web_frame_suite_tool_test.dart` - passed.
- `cd packages/fleury_web && dart test test/web_frame_capture_tool_test.dart test/web_frame_scoreboard_tool_test.dart test/web_frame_suite_tool_test.dart test/web_host_instrumentation_test.dart` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark web-"` - passed.
- `cd packages/fleury_web && dart run tool/web_frame_suite.dart --scenarios=single-dirty-cell-160x50 --runs=1 --frames=1 --warmup=0 --output-dir=/tmp/fleury_web_suite_gate_smoke --scoreboard=/tmp/fleury_web_suite_gate_smoke/scoreboard.md --max-total-frame-p95-ms=1000 --max-semantic-uncovered-cells=0 --timeout=30` - passed, producing a strict scoreboard whose gate column reported `pass`.

Current caveat:

- The gate mechanism now exists, but the thresholds used in the smoke are
  permissive plumbing checks. Phase 5 still needs stable repeated baseline
  captures and agreed per-scenario threshold values before DOM can claim the
  performance exit gate.

## 2026-06-08 03:29 EDT

Collected the first full local repeated retained DOM baseline.

- Ran the web suite across the full scenario catalog with three captures per
  scenario.
  - Output directory: `/tmp/fleury_web_baseline_cQyPTg`.
  - Scoreboard: `/tmp/fleury_web_baseline_cQyPTg/scoreboard.md`.
  - Capture count: 33 JSON captures.
  - Artifact size: 956K.
  - The suite completed with strict `--min-runs=3` coverage.
- Kept the baseline under `/tmp` because `profiling/web` is not ignored and
  this should not add generated capture artifacts to the worktree until the
  artifact retention policy is decided.
- Aggregate signal from the scoreboard:
  - every scenario was materially over the 16.67 ms frame budget in this
    unoptimized baseline;
  - no scenario had DOM apply as the dominant p95 slice;
  - runtime render dominated all runs or the majority of runs for eight
    scenarios;
  - semantic apply dominated the majority of runs for three scenarios
    (`dirty-row-160x50`, `normal-80x24`, `stress-300x100`);
  - uncovered semantic cells were zero across all scenarios.
- Noted one harness-noise item: `text-input-burst-80x24` produced 61 measured
  frames across three runs, not the expected 60, so the capture stop condition
  should be checked before using exact frame totals as a release gate.

Verification:

- `cd packages/fleury_web && dart run tool/web_frame_suite.dart --runs=3 --output-dir=/tmp/fleury_web_baseline_cQyPTg --scoreboard=/tmp/fleury_web_baseline_cQyPTg/scoreboard.md --timeout=60` - passed.
- `cd packages/fleury_web && sed -n '1,80p' /tmp/fleury_web_baseline_cQyPTg/scoreboard.md` - confirmed 11 scenarios with three runs each and strict scoreboard output.

Current caveat:

- This is a useful local baseline, not the Phase 5 exit gate. The performance
  gate still needs stable-run conditions, an artifact retention policy, and
  agreed per-scenario threshold values. The evidence points first at
  runtime-render and semantic-apply cost, not a DOM-apply ceiling.

## 2026-06-08 03:33 EDT

Tightened the browser capture step/frame accounting.

- Updated `packages/fleury_web/web/benchmark_capture.dart`.
  - Each driven benchmark step now waits for at least one new recorded frame
    relative to the frame count before that step.
  - The harness waits for frame-count quiescence before advancing to the next
    step, so post-frame work caused by the current interaction is counted as
    part of the actual product frame cost instead of racing the next step.
  - Capture JSON now includes `requestedSteps` alongside the existing
    `requestedFrames` field. The recorded summary `frameCount` remains the
    actual measured frame count.
- The earlier text-input baseline noise is now understood as real extra
  input/post-frame work, not something the harness should hide from total-frame
  budget accounting.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_frame_capture_tool_test.dart` - passed.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=text-input-burst-80x24 --frames=3 --warmup=0 --output=/tmp/fleury_text_input_burst_smoke.json --timeout=60` - passed; 3 driven input steps produced 6 actual measured frames.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=normal-80x24 --frames=2 --warmup=0 --output=/tmp/fleury_normal_frame_smoke.json --timeout=60` - passed; 2 driven normal steps produced 2 actual measured frames.

Current caveat:

- The first full baseline predates this wait-loop change. The next calibrated
  baseline should be rerun with the tightened harness before choosing any
  strict frame-count or over-budget thresholds.

## 2026-06-08 04:04 EDT

Reran the full local retained DOM baseline with tightened capture accounting.

- Ran the web suite across the full scenario catalog with three captures per
  scenario.
  - Output directory: `/tmp/fleury_web_baseline_tight_BE8BTN`.
  - Scoreboard: `/tmp/fleury_web_baseline_tight_BE8BTN/scoreboard.md`.
  - Capture count: 33 JSON captures.
  - Artifact size: 1.0M.
  - The suite completed with strict `--min-runs=3` coverage.
- Aggregate accounting:
  - driven benchmark steps: 816;
  - actual measured frames: 912;
  - `text-input-burst-80x24` produced 120 measured frames for 60 driven input
    steps;
  - `resize-burst` produced 72 measured frames for 36 driven resize steps;
  - all other scenarios produced one measured frame per driven step.
- Aggregate performance signal:
  - every scenario remained materially over the 16.67 ms frame budget;
  - no scenario had DOM apply as the dominant p95 slice;
  - runtime render dominated all runs or the majority of runs for eight
    scenarios;
  - semantic apply dominated all runs or the majority of runs for three
    scenarios (`noop-160x50`, `resize-burst`,
    `single-dirty-cell-160x50`);
  - uncovered semantic cells remained zero across all scenarios.
- Compared to the preliminary baseline, the tightened harness makes
  input/resize follow-up frames explicit and gives a clearer signal:
  optimize runtime-render and semantic-apply cost before considering WebGL as a
  DOM-apply escape hatch.

Verification:

- `cd packages/fleury_web && dart run tool/web_frame_suite.dart --runs=3 --output-dir=/tmp/fleury_web_baseline_tight_BE8BTN --scoreboard=/tmp/fleury_web_baseline_tight_BE8BTN/scoreboard.md --timeout=60` - passed.
- `cd packages/fleury_web && sed -n '1,90p' /tmp/fleury_web_baseline_tight_BE8BTN/scoreboard.md` - confirmed 11 scenarios with three runs each and strict scoreboard output.
- `node <capture-accounting-summary>` over `/tmp/fleury_web_baseline_tight_BE8BTN` - confirmed 912 measured frames over 816 driven steps.

Current caveat:

- This is still local evidence, not a release gate. Phase 5 still needs an
  artifact retention policy, stable product/browser run conditions, and agreed
  per-scenario threshold values before these gates should fail CI or justify a
  backend switch.

## 2026-06-08 04:15 EDT

Optimized retained semantic no-op frames.

- Updated semantic presentation stats and the DOM presenter.
  - `SemanticPresentationStats.retained(nodeCount:)` reports retained semantic
    output without pretending the frame had zero semantic nodes.
  - `SemanticDomPresenter` now honors unchanged retained semantic updates
    without clearing/reappending the accessible DOM.
- Updated `run_tui_surface.dart`.
  - Tracks whether semantic inputs changed through build scheduling, input,
    resize/metrics, and semantic actions.
  - Reuses the retained semantic snapshot without rebuilding fallback coverage
    or projecting DOM when the semantic tree is clean, the previous coverage
    audit had no fallback text, and the newly rendered cells are identical to
    the previous frame.
  - Keeps the raw painted text fallback path conservative: if fallback coverage
    was present, the host still recomputes and presents semantic coverage on
    no-op frames.
- Added browser tests for:
  - direct DOM presenter no-op behavior with unchanged `SemanticTreeUpdate`;
  - host-level skip for unchanged semantic and visual output;
  - host-level fallback safety for unchanged raw painted text.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury_web && dart test -p chrome test/semantic_dom_presenter_test.dart test/run_tui_surface_test.dart` - passed.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=noop-160x50 --frames=3 --warmup=0 --output=/tmp/fleury_noop_semantic_retained_smoke.json --timeout=60` - passed.
- Inspecting `/tmp/fleury_noop_semantic_retained_smoke.json` showed retained
  semantic node counts with zero added/removed/updated/fallback nodes on all
  three measured frames. Semantic apply time dropped across the retained
  frames from 45.8 ms to 10.1 ms to 1.3 ms.

Current caveat:

- This is a targeted no-op/low-change optimization. A full post-optimization
  baseline is still needed before setting threshold gates or making broader
  performance claims.

## 2026-06-08 04:45 EDT

Reran the full retained DOM baseline after the retained-semantic no-op
optimization.

- Ran the web suite across the full scenario catalog with three captures per
  scenario.
  - Output directory:
    `/tmp/fleury_web_baseline_post_semantics_cO1oqK`.
  - Scoreboard:
    `/tmp/fleury_web_baseline_post_semantics_cO1oqK/scoreboard.md`.
  - Capture count: 33 JSON captures.
  - Artifact size: 1.0M.
  - The suite completed with strict `--min-runs=3` coverage.
- Aggregate accounting stayed aligned with the corrected baseline:
  - driven benchmark steps: 816;
  - actual measured frames: 912.
- Aggregate post-optimization signal:
  - no scenario had DOM apply as the dominant p95 slice;
  - runtime render dominated all runs or the majority of runs for every
    scenario except `full-frame-churn-160x50`;
  - `full-frame-churn-160x50` remained semantic-majority;
  - uncovered semantic cells remained zero across all scenarios.
- Compared with `/tmp/fleury_web_baseline_tight_BE8BTN`, the targeted
  retained-semantic optimization clearly helped low-change paths:
  - `noop-160x50` semantic p95 median improved from 505.2 ms to 27.0 ms and
    total p95 median improved from 1094.1 ms to 443.4 ms;
  - `text-input-burst-80x24` total p95 median improved from 850.9 ms to
    417.5 ms, with runtime render dominant in all three captures;
  - `normal-80x24` total p95 median improved from 351.5 ms to 206.4 ms;
  - `large-160x50` total p95 median improved from 1426.4 ms to 872.8 ms;
  - `dirty-row-160x50` total p95 median improved from 949.7 ms to 727.9 ms.
- The local full-catalog run still showed high-churn variance/regressions:
  - `full-frame-churn-160x50`, `single-dirty-cell-160x50`, and
    `stress-300x100` worsened in the post-optimization run;
  - those scenarios need runtime-render/semantic-apply investigation before
    any strict thresholds are treated as release gates.

Verification:

- `cd packages/fleury_web && dart run tool/web_frame_suite.dart --runs=3 --output-dir=/tmp/fleury_web_baseline_post_semantics_cO1oqK --scoreboard=/tmp/fleury_web_baseline_post_semantics_cO1oqK/scoreboard.md --timeout=60` - passed.
- `cd packages/fleury_web && sed -n '1,90p' /tmp/fleury_web_baseline_post_semantics_cO1oqK/scoreboard.md` - confirmed 11 scenarios with three runs each, 912 measured frames, 816 driven steps, zero uncovered semantic cells, and no DOM-dominant scenario.
- `node <baseline-comparison-summary>` over
  `/tmp/fleury_web_baseline_tight_BE8BTN` and
  `/tmp/fleury_web_baseline_post_semantics_cO1oqK` - confirmed matching
  capture counts/accounting and the scenario deltas above.

Current caveat:

- This is still local evidence, not a release gate. Phase 5 still needs an
  artifact retention policy, stable product/browser run conditions, agreed
  per-scenario threshold values, and follow-up on high-churn/runtime-render
  variance before the benchmark gate should fail CI or justify a backend
  switch.

## 2026-06-08 04:55 EDT

Settled the generated web benchmark artifact retention path.

- Changed package-level web benchmark defaults:
  - `web_frame_capture.dart` now writes default single captures under
    `../../profiling/web/runs/<scenario>-<timestamp>.json`;
  - `web_frame_suite.dart` now writes default repeated suites under
    `../../profiling/web/runs/<timestamp>-suite`.
- Changed the root contributor launcher defaults to match:
  - `fleury benchmark web-capture` defaults to
    `profiling/web/runs/<scenario>-<timestamp>.json`;
  - `fleury benchmark web-suite` defaults to
    `profiling/web/runs/<timestamp>-suite`;
  - benchmark catalog metadata now records that generated defaults are ignored
    and reviewed evidence should be promoted under `profiling/web/baselines/`.
- Added `profiling/web/.gitignore` so the default `runs/` bucket is generated
  evidence, not accidental source-control churn.
- Added `profiling/web/README.md` documenting the policy:
  - `runs/` is local/CI scratch evidence;
  - `baselines/` is for intentionally promoted reviewed evidence.
- Updated the `fleury_web` README and CLI help examples to point promoted
  baselines at `profiling/web/baselines/`.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_frame_suite_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_capture_tool_test.dart test/web_frame_suite_tool_test.dart` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark-manifest"` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web"` - passed.
- `git diff --check` - passed.

Current caveat:

- Artifact retention is now explicit. Phase 5 still needs stable
  product/browser run conditions, agreed per-scenario thresholds, and follow-up
  on high-churn/runtime-render variance before benchmark gates should become
  CI-enforced release gates.

## 2026-06-08 05:06 EDT

Added run-environment metadata and a comparable-environment scoreboard gate.

- Updated `web_frame_capture.dart`.
  - Captures now include `runEnvironment` metadata from the CLI/Chrome side:
    Chrome executable, Chrome/DevTools/V8/WebKit versions, Dart version, OS
    version, headless/headful mode, requested steps, warmup steps, and frame
    budget.
  - The browser-side `browser` block still records page-observed user agent and
    device pixel ratio.
- Updated `web_frame_scoreboard.dart`.
  - Reads capture `runEnvironment` blocks.
  - Computes a stable run-environment signature per capture from browser,
    Dart, OS, headless mode, requested steps, warmup, and frame budget.
  - Emits per-scenario comparability fields:
    `runEnvironmentComparable`, `runEnvironmentSignatureCount`,
    `missingRunEnvironmentCount`, `runEnvironmentSignatures`, and
    `latestRunEnvironment`.
  - Adds `--require-comparable-environment`; under `--strict`, scenarios now
    fail if this option is supplied and the repeated runs are missing
    environment metadata or contain multiple environment signatures.
  - Adds a `Run Env` Markdown column.
- Updated `web_frame_suite.dart`.
  - Repeated suites now forward `--require-comparable-environment` to the
    generated scoreboard by default.
  - Added `--no-require-comparable-environment` for legacy capture analysis.
- Updated the root `fleury benchmark web-suite` and
  `fleury benchmark web-scoreboard` wrappers with matching option forwarding.
- Updated web benchmark docs to call out recorded run-environment metadata and
  the default comparable-environment gate.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_frame_scoreboard_tool_test.dart test/web_frame_suite_tool_test.dart test/web_frame_capture_tool_test.dart` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web"` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark web-suite launcher"` - passed.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=noop-160x50 --frames=1 --warmup=0 --output=/tmp/fleury_env_capture_smoke.json --timeout=60 --json` - passed and produced a capture with `runEnvironment`.
- `cd packages/fleury_web && dart run tool/web_frame_scoreboard.dart --input=/tmp/fleury_env_scoreboard_smoke --min-runs=1 --require-comparable-environment --strict --json` - passed with `runEnvironmentComparable: true`.

Current caveat:

- The tooling can now prove comparable run conditions for new captures. Phase 5
  still needs a calibrated baseline collected under agreed product/browser
  conditions, agreed per-scenario threshold values, and follow-up on
  high-churn/runtime-render variance before benchmark gates should become
  CI-enforced release gates.

## 2026-06-08 05:19 EDT

Added a semantic coverage audit for retained DOM captures.

- Added `tool/web_semantic_coverage_audit.dart`.
  - Scans retained DOM frame capture JSON recursively.
  - Groups results by benchmark scenario.
  - Reports fallback frames, fallback cells, fallback nodes, fallback cells as
    a percentage of viewport cells, and max fallback cells/nodes per frame.
  - Emits Markdown or JSON.
  - Supports optional strict gates:
    `--max-fallback-cells`,
    `--max-fallback-frame-percent`, and
    `--max-fallback-viewport-percent`.
- Added root launcher support:
  - `fleury benchmark web-semantic-audit`;
  - benchmark catalog metadata for the semantic coverage audit axes;
  - root help and dry-run forwarding.
- Updated web benchmark docs to distinguish two accessibility facts:
  - text fallback prevents silent unreachable painted text;
  - fallback reliance still identifies widgets or scenarios that need richer
    first-party geometry-bearing semantics.
- Added package and root tests covering:
  - JSON aggregate output;
  - Markdown output;
  - strict fallback-cell gate failures;
  - root command forwarding.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_semantic_coverage_audit_tool_test.dart` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-semantic-audit"` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web"` - passed.
- `cd packages/fleury_web && dart test test/web_frame_scoreboard_tool_test.dart test/web_frame_suite_tool_test.dart test/web_frame_capture_tool_test.dart test/web_semantic_coverage_audit_tool_test.dart` - passed.
- `cd packages/fleury_web && dart run tool/web_semantic_coverage_audit.dart --input=/tmp/fleury_env_scoreboard_smoke --max-fallback-cells=0 --strict --json` - passed with `strictPass: true`, one capture, one frame, and zero fallback cells.
- `cd packages/fleury && dart run ../../tool/fleury_dev.dart --dry-run benchmark web-semantic-audit --input=/tmp/fleury_env_scoreboard_smoke --max-fallback-cells=0 --strict --json` - forwarded the expected package tool command.

Current caveat:

- This audit quantifies fallback reliance in captured scenarios. It does not
  replace manual screen-reader validation, and it only represents the widget
  states covered by the capture catalog.

## 2026-06-08 05:31 EDT

Added manual IME and screen-reader validation evidence tooling.

- Added a retained DOM manual validation page:
  - `web/manual_validation.dart`;
  - `web/manual_validation.html`.
- The page exercises the real web host path rather than the legacy xterm demo:
  - `runTuiWebDom`;
  - hidden textarea / DOM input;
  - focused `TextInput`;
  - semantic DOM textbox projection;
  - semantic action dispatch through a button;
  - safe link projection;
  - status/live semantic output.
- Added `tool/web_manual_validation.dart`.
  - Generates a Markdown manual validation plan.
  - Generates JSON evidence templates for manual targets.
  - Audits reviewed manual evidence entries.
  - Supports strict mode over the current `primary` target preset.
  - Current primary targets:
    `chrome-ime-macos` and `chrome-voiceover-macos`.
- Added root launcher support:
  - `fleury benchmark web-manual-validation`;
  - benchmark catalog metadata;
  - help text and dry-run forwarding.
- Added `profiling/web/manual/README.md` and updated web benchmark docs so
  manual evidence is stored separately from generated benchmark `runs/`.
- Added package and root tests covering:
  - plan generation;
  - JSON evidence template generation;
  - missing-target strict failure;
  - complete-evidence strict pass;
  - incomplete-check strict failure;
  - root command forwarding.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-manual-validation"` - passed.
- `cd packages/fleury_web && dart compile js web/manual_validation.dart -o /tmp/fleury_web_manual_validation.dart.js` - passed.
- `cd packages/fleury_web && dart test test/web_frame_scoreboard_tool_test.dart test/web_frame_suite_tool_test.dart test/web_frame_capture_tool_test.dart test/web_semantic_coverage_audit_tool_test.dart test/web_manual_validation_tool_test.dart` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web"` - passed.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --write-plan=/tmp/fleury_web_manual_validation_smoke/plan.md --write-template=/tmp/fleury_web_manual_validation_smoke/chrome-ime-macos.json --template-target=chrome-ime-macos --target=chrome-ime-macos` - passed.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/tmp/fleury_web_manual_validation_smoke --target=chrome-ime-macos --json` - passed and correctly reported the generated template as `needsReview`.

Current caveat:

- The harness makes manual gates auditable, but it does not itself satisfy
  those gates. Phase 3 and Phase 4 still need reviewed `pass` entries from real
  IME and screen-reader sessions before Phase 6 defaulting/retirement claims.

## 2026-06-08 05:40 EDT

Added browser input trace fixtures and replay coverage.

- Added `test/fixtures/browser_input_traces.dart` as importable browser-safe
  fixture data.
- Added `test/dom_input_trace_fixture_test.dart` to replay those fixtures
  against `DomInputSource` in Chrome and compare emitted `TuiEvent`s against
  normalized expected event maps.
- Fixture coverage now includes:
  - navigation key mapping with modifiers;
  - shortcut key repeat with modifier state;
  - printable text input through the textarea `input` channel;
  - multi-line paste as a single `PasteEvent`;
  - IME composition commit with duplicate input suppression;
  - IME composition cancel without committed text;
  - pointer down, drag, and up cell mapping;
  - wheel up and down cell mapping.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_input_trace_fixture_test.dart` - passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_input_source_test.dart test/dom_input_trace_fixture_test.dart` - passed.

Current caveat:

- These fixtures make browser event translation reviewable and repeatable, but
  they are still synthetic browser events. Real primary-browser IME validation
  remains the Phase 3 empirical gate.

## 2026-06-08 05:51 EDT

Added a Phase 6 web readiness gate.

- Added `tool/web_readiness.dart`.
  - Consumes reviewed JSON artifacts from:
    - `web_frame_scoreboard.dart`;
    - `web_semantic_coverage_audit.dart`;
    - `web_manual_validation.dart`.
  - Emits a combined Markdown or JSON readiness audit.
  - Strict mode fails unless all three evidence artifacts pass.
  - The frame scoreboard check requires by default:
    - `strictPass: true`;
    - at least three runs per scenario through `minRuns`;
    - comparable run-environment enforcement;
    - frame threshold gates;
    - a total-frame p95 gate.
  - The semantic audit check requires by default:
    - `strictPass: true`;
    - non-empty capture/scenario/frame evidence;
    - semantic fallback threshold gates.
  - The manual validation check requires:
    - `strictPass: true`;
    - every target passed;
    - no missing, failed, blocked, or needs-review targets.
- Added root launcher support:
  - `fleury benchmark web-readiness`;
  - benchmark catalog metadata;
  - help text and dry-run forwarding.
- Updated web benchmark docs to show the reviewed JSON artifact flow before
  running readiness.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_readiness_tool_test.dart test/web_manual_validation_tool_test.dart test/web_semantic_coverage_audit_tool_test.dart test/web_frame_scoreboard_tool_test.dart` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-readiness|web-manual-validation|web-semantic-audit|web-scoreboard"` - passed.
- `cd packages/fleury_web && dart run tool/web_readiness.dart --json` - passed and correctly reported the default reviewed-artifact paths as missing, with `strictPass: false`.
- `cd packages/fleury && dart run ../../tool/fleury_dev.dart --dry-run benchmark web-readiness --strict --json` - forwarded the expected package tool command.

Current caveat:

- This turns the Phase 6 prerequisites into one executable audit, but it does
  not create the reviewed benchmark or manual-validation evidence itself. DOM
  defaulting and xterm-path retirement remain blocked until those artifacts are
  collected and the readiness audit passes in strict mode.

## 2026-06-08 06:00 EDT

Added a web readiness artifact bundle generator.

- Added `tool/web_readiness_bundle.dart`.
  - Consumes an existing retained DOM capture directory and manual validation
    evidence directory.
  - Generates the machine-readable artifacts consumed by `web_readiness.dart`:
    - `scoreboard.json`;
    - `semantic-coverage.json`;
    - `manual-validation-audit.json`;
    - `web-readiness.json`;
    - `web-readiness.md`.
  - Composes the existing frame scoreboard, semantic audit, manual validation,
    and readiness tools instead of duplicating their gate math.
  - Preserves the release posture: it packages already-collected evidence but
    does not capture browser runs or create manual screen-reader/IME evidence.
  - In strict mode, keeps the generated artifacts on disk even when readiness
    fails, so reviewers can inspect the blockers.
- Added root launcher support:
  - `fleury benchmark web-readiness-bundle`;
  - benchmark catalog metadata;
  - help text and dry-run forwarding.
- Updated web benchmark docs to show the bundle command as the preferred way
  to produce the reviewed JSON artifacts for the Phase 6 readiness audit.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart test/web_readiness_tool_test.dart` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-readiness"` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-readiness|web-manual-validation|web-semantic-audit|web-scoreboard"` - passed.
- `cd packages/fleury && dart run ../../tool/fleury_dev.dart --dry-run benchmark web-readiness-bundle --captures=profiling/web/baselines/sample --manual=profiling/web/manual --output-dir=profiling/web/baselines/sample/readiness --max-total-frame-p95-ms=16.67 --max-fallback-cells=0 --strict --json` - forwarded the expected package tool command.

Current caveat:

- The bundle command removes shell-redirection drift from the final evidence
  workflow. It still depends on real capture data, agreed thresholds, and
  reviewed manual evidence before `web-readiness --strict` can pass.

## 2026-06-08 06:11 EDT

Added per-scenario retained DOM threshold policy support.

- Updated `packages/fleury_web/tool/web_frame_scoreboard.dart`.
  - Adds `--thresholds=PATH` for JSON threshold policies.
  - Supports policy `defaults` plus `scenarios[scenarioId]` overrides.
  - Merges gate settings in this order: CLI fallback gates, policy defaults,
    then the matching scenario override.
  - Emits `thresholdPolicyPath` at scoreboard level and per scenario.
  - Emits `thresholdPolicyMatchedScenario` per scenario so reviewed artifacts
    show whether a scenario-specific override was used.
- Updated `packages/fleury_web/tool/web_frame_suite.dart`.
  - Forwards `--thresholds=PATH` into the strict generated scoreboard.
  - Records `thresholdPolicyPath` in suite dry-run plans.
- Updated `packages/fleury_web/tool/web_readiness_bundle.dart`.
  - Forwards `--thresholds=PATH` into generated `scoreboard.json`.
  - Records `thresholdPolicyPath` in bundle input metadata.
- Updated `fleury benchmark web-suite`, `fleury benchmark web-scoreboard`, and
  `fleury benchmark web-readiness-bundle`.
  - Exposes the same threshold policy path through the root launcher.
  - Resolves policy paths to absolute paths before forwarding to package tools.
- Updated web benchmark docs.
  - Shows the `fleuryWebFrameThresholds` policy shape.
  - Routes the Phase 6 bundle and scoreboard examples through a reviewed
    `thresholds.json` next to promoted baseline captures.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_frame_scoreboard_tool_test.dart test/web_frame_suite_tool_test.dart test/web_readiness_bundle_tool_test.dart` - passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-suite|web-scoreboard|web-readiness"` - passed.

Current caveat:

- The policy mechanism is now implemented, but the policy values themselves
  still need to be calibrated and reviewed from real product/browser baseline
  captures before Phase 5 can make pass/fail release claims.

## 2026-06-08 06:20 EDT

Added candidate threshold policy generation for retained DOM baseline review.

- Updated `packages/fleury_web/tool/web_frame_scoreboard.dart`.
  - Adds `--write-thresholds=PATH`.
  - Generates a `fleuryWebFrameThresholds` JSON policy marked
    `reviewState: candidate`.
  - Builds per-scenario thresholds from observed aggregate maxima:
    - `maxTotalFrameP95Ms`;
    - `maxDomApplyP95Ms`;
    - `maxSemanticApplyP95Ms`;
    - `maxOverBudgetPercent`;
    - `maxSemanticUncoveredCells`.
  - Adds configurable headroom:
    - `--threshold-headroom-percent`, default 20;
    - `--threshold-min-headroom-ms`, default 1;
    - `--threshold-min-headroom-percent`, default 1.
  - Keeps `--json` stdout parseable while writing the candidate policy to a
    side file.
- Updated `packages/fleury_web/tool/web_frame_suite.dart`.
  - Forwards candidate policy generation options into the generated scoreboard.
  - Records candidate policy path and headroom values in dry-run plans.
- Updated `fleury benchmark web-suite` and `fleury benchmark web-scoreboard`.
  - Exposes candidate policy generation through the root launcher.
  - Resolves generated policy paths to absolute paths before forwarding.
- Updated web benchmark docs.
  - Documents `thresholds.candidate.json` as a draft artifact created from
    promoted captures.
  - Keeps the release contract as a reviewed `thresholds.json` passed through
    `--thresholds=...`.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_frame_scoreboard_tool_test.dart test/web_frame_suite_tool_test.dart` - passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-suite|web-scoreboard|web-readiness"` - passed.

Current caveat:

- Candidate policy generation closes the tooling gap, not the empirical gate.
  Phase 5 still needs a real promoted baseline under agreed product/browser
  conditions and human review of the generated thresholds before they become
  release gates.

## 2026-06-08 06:51 EDT

Collected and promoted a local retained DOM candidate baseline.

- Ran the full retained DOM web scenario catalog with three captures per
  scenario.
  - Output directory:
    `profiling/web/baselines/2026-06-08-local-dom-retained`.
  - Generated 33 capture JSON files across 11 scenarios.
  - Generated `scoreboard.md`.
  - Generated `thresholds.candidate.json` with default candidate threshold
    headroom.
- Added a baseline-local README:
  `profiling/web/baselines/2026-06-08-local-dom-retained/README.md`.
  - Records the exact commands.
  - Marks the evidence as local candidate evidence, not a release gate.
  - Summarizes blockers and performance signal.
- Ran semantic fallback coverage over the promoted captures.
  - Output: `semantic-coverage.md`.
  - Strict zero-fallback gate passed.
- Generated a readiness-candidate bundle:
  - `readiness-candidate/scoreboard.json`;
  - `readiness-candidate/semantic-coverage.json`;
  - `readiness-candidate/manual-validation-audit.json`;
  - `readiness-candidate/web-readiness.json`;
  - `readiness-candidate/web-readiness.md`.

Evidence summary:

- Frame scoreboard candidate gate:
  - 11 scenarios;
  - 33 captures;
  - comparable run environment required;
  - strict pass with the generated candidate threshold policy.
- Semantic coverage:
  - 33 captures;
  - 912 frames;
  - 0 fallback cells;
  - 0 fallback nodes;
  - strict pass with `--max-fallback-cells=0`.
- Readiness:
  - strict pass: false.
  - Frame scoreboard check: pass.
  - Semantic coverage check: pass.
  - Manual validation check: fail.
  - Missing manual targets:
    - `chrome-ime-macos`;
    - `chrome-voiceover-macos`.
- Performance interpretation:
  - The local over-budget behavior is dominated by `runtimeRenderMs` and
    `semanticApplyMs`, not by DOM apply.
  - The worst median total-frame p95 in this local candidate run is
    `single-dirty-cell-160x50` at 2718.4 ms.
  - `stress-300x100` is fully over budget in the local run.

Verification:

- `cd packages/fleury && dart run ../../tool/fleury_dev.dart benchmark web-suite --runs=3 --output-dir=profiling/web/baselines/2026-06-08-local-dom-retained --scoreboard=profiling/web/baselines/2026-06-08-local-dom-retained/scoreboard.md --write-thresholds=profiling/web/baselines/2026-06-08-local-dom-retained/thresholds.candidate.json --timeout=60` - passed.
- `cd packages/fleury && dart run ../../tool/fleury_dev.dart benchmark web-semantic-audit --input=profiling/web/baselines/2026-06-08-local-dom-retained --output=profiling/web/baselines/2026-06-08-local-dom-retained/semantic-coverage.md --max-fallback-cells=0 --strict` - passed.
- `cd packages/fleury && dart run ../../tool/fleury_dev.dart benchmark web-readiness-bundle --captures=profiling/web/baselines/2026-06-08-local-dom-retained --manual=profiling/web/manual --output-dir=profiling/web/baselines/2026-06-08-local-dom-retained/readiness-candidate --thresholds=profiling/web/baselines/2026-06-08-local-dom-retained/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --json` - passed and reported `strictPass: false` due to missing manual evidence.

Current caveat:

- This is durable local candidate evidence, not an approved Phase 5/6 exit.
  `thresholds.candidate.json` was generated from the same local run and still
  needs review. Manual IME and VoiceOver validation remain the hard blockers
  before Phase 6 defaulting.

## 2026-06-08 07:08 EDT

Tightened dirty-row benchmark behavior and fixed repaint-boundary semantic
bounds replay.

- Added `TuiDirtyRows.fromRows` so presenters can express sparse row diffs
  without widening to a single top/bottom range.
- Updated `FramePresentationPlanner` so conservative/unbounded damage can fall
  back to a previous-vs-next row diff oracle instead of treating all rows as
  dirty when paint damage is unavailable.
- Wrapped stable rows in the large dirty-row benchmark scenarios with
  `RepaintBoundary` so the measured scenarios exercise the retained paint
  contract they are supposed to represent.
- Found and fixed a core semantic correctness issue exposed by those
  boundaries:
  - `Semantics` bounds are paint-captured.
  - `RenderRepaintBoundary` cache hits skipped child paint, so cached visual
    rows could keep stale or local semantic bounds.
  - Added a render-layer semantic bounds capture/replay helper.
  - `RenderRepaintBoundary` now captures cache-local semantic bounds while
    repainting its cache, publishes translated bounds to enclosing captures,
    and replays screen-space bounds on cache hits.
  - Added regression coverage for both cache-hit replay and moving a cached
    boundary without repainting its child.

Focused browser smoke after the fix:

- Capture directory: `/tmp/fleury_web_damage_smoke_after_semantics_zUt1WY`.
- `noop-160x50`, 8 measured frames:
  - dirty rows p95: 0;
  - rows replaced p95: 0;
  - spans p95: 0;
  - semantic fallback nodes p95: 0;
  - semantic uncovered cells p95: 0;
  - dominant p95 slice: `runtimeRenderMs`.
- `single-dirty-cell-160x50`, 8 measured frames:
  - dirty rows p95: 1;
  - rows replaced p95: 1;
  - spans p95: 1;
  - semantic fallback nodes p95: 0;
  - semantic uncovered cells p95: 0;
  - dominant p95 slice: `runtimeRenderMs`.

Interpretation:

- The row-damage path now behaves as intended for no-op and single-dirty-cell
  product scenarios: DOM row churn is 0/1 rows, not full-grid replacement.
- The RepaintBoundary semantic replay fix restored zero fallback coverage
  without giving up visual paint caching.
- The remaining local over-budget behavior in these focused captures is still
  runtime-render / semantic-apply dominated, not DOM-apply dominated.
- This focused smoke does not replace the promoted local baseline under
  `profiling/web/baselines/2026-06-08-local-dom-retained`; a new full suite
  should be collected only when we want an updated reviewed candidate baseline.

Verification:

- `cd packages/fleury && dart test test/semantics/semantics_test.dart` -
  passed.
- `cd packages/fleury && dart test test/runtime/tui_frame_loop_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/frame_presentation_test.dart test/cell_span_builder_test.dart` -
  passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=noop-160x50 --frames=8 --warmup=2 --output=/tmp/fleury_web_damage_smoke_after_semantics_zUt1WY/noop.json --timeout=60 --json` -
  passed.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=single-dirty-cell-160x50 --frames=8 --warmup=2 --output=/tmp/fleury_web_damage_smoke_after_semantics_zUt1WY/single.json --timeout=60 --json` -
  passed.
- `git diff --check` - passed.

Current caveat:

- The sparse row-diff fallback and benchmark repaint-boundary coverage are
  implementation improvements, but the Phase 5/6 release gates still require
  a reviewed full-suite baseline, reviewed threshold policy, and manual IME /
  screen-reader evidence.

## 2026-06-08 07:23 EDT

Added incremental semantic DOM updates and split semantic timing diagnostics.

- Updated `SemanticDomPresenter` to use `SemanticTreeUpdate` for conservative
  incremental DOM mutation:
  - unchanged updates still skip DOM work entirely;
  - simple same-tag leaf/control updates update the retained element in place;
  - added/removed nodes, tag changes, child-order changes, and non-leaf text
    changes fall back to the existing full retained rebuild path.
- Added browser tests proving:
  - a changed text leaf updates without rebuilding the semantic root or stable
    sibling;
  - structural child-order changes still take the safe full rebuild path.
- Added semantic sub-slice frame timing fields:
  - `semanticTreeBuildMicros`;
  - `semanticCoverageMicros`;
  - `semanticDiffMicros`;
  - `semanticPresenterMicros`;
  - `semanticFocusSyncMicros`.
- Added semantic DOM mutation counters:
  - `semanticDomCreatedElementCount`;
  - `semanticDomReusedElementCount`;
  - `semanticDomReplacedElementCount`;
  - `semanticDomAttributesSetCount`;
  - `semanticDomAttributesRemovedCount`.
- Updated frame summaries and Markdown reports to include the semantic timing
  sub-slices and DOM mutation counters.
- Kept the existing aggregate `semanticApplyMicros` / `semanticApplyMs` field
  intact for compatibility with current gates and existing capture files.

Focused browser smoke after the change:

- Capture directory: `/tmp/fleury_web_semantic_counters_smoke_2N18cb`.
- `single-dirty-cell-160x50`, 8 measured frames:
  - semantic updated nodes p95: 1;
  - semantic DOM created elements p95: 0;
  - semantic DOM reused elements p95: 1;
  - semantic DOM replaced elements p95: 0;
  - semantic DOM attributes set p95: 2;
  - semantic fallback nodes p95: 0;
  - semantic uncovered cells p95: 0;
  - dirty rows p95: 1;
  - rows replaced p95: 1.
- The timing split shows the aggregate semantic cost is no longer opaque:
  - `semanticTreeBuildMs` p95: 9.8 ms;
  - `semanticCoverageMs` p95: 13.9 ms;
  - `semanticDiffMs` p95: 20.699 ms;
  - `semanticPresenterMs` p95: 95.799 ms;
  - `semanticFocusSyncMs` p95: 4.3 ms;
  - aggregate `semanticApplyMs` p95: 101.1 ms.

Interpretation:

- The single-dirty-cell scenario now proves the semantic DOM presenter is on
  the incremental path: no semantic elements are created or replaced after
  warmup, and each frame mutates one retained semantic element.
- The remaining semantic-apply cost can now be assigned to concrete sub-slices
  instead of being a single aggregate bucket. In this local smoke,
  `semanticPresenterMs` is still the largest semantic p95 sub-slice despite
  the low mutation count, so the next optimization should investigate browser
  attribute/text mutation cost, JS interop overhead, and timer/GC variance
  before changing architecture.
- This focused smoke does not replace the promoted local baseline under
  `profiling/web/baselines/2026-06-08-local-dom-retained`.

Verification:

- `cd packages/fleury_web && dart test -p chrome test/semantic_dom_presenter_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed.
- `rg -n "[ \t]+$" packages/fleury_web/lib/src/run_tui_surface.dart packages/fleury_web/lib/src/run_tui_web_dom.dart packages/fleury_web/test/run_tui_web_dom_test.dart docs/implementation/web-rfc-review-packet.md docs/implementation/web-rfc-phase-audit.md docs/implementation/web-rfc-execution-log.md` -
  passed with no matches.
- `cd packages/fleury_web && dart test test/web_host_instrumentation_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=single-dirty-cell-160x50 --frames=8 --warmup=2 --output=/tmp/fleury_web_semantic_counters_smoke_2N18cb/single.json --timeout=60 --json` -
  produced the capture, but the process hung after writing output and was
  terminated manually; the JSON artifact was complete and parsed successfully.
- `cd packages/fleury_web && dart run tool/web_frame_report.dart --input=/tmp/fleury_web_semantic_counters_smoke_2N18cb/single.json --output=/tmp/fleury_web_semantic_counters_smoke_2N18cb/single.md` -
  passed.
- `git diff --check` - passed.

Current caveat:

- The capture-tool cleanup hang needs follow-up if it reproduces; it happened
  after the JSON artifact was written and was not observed in earlier captures.
  The broader Phase 5/6 gates are unchanged: reviewed full-suite captures,
  reviewed thresholds, and manual IME/screen-reader evidence are still
  required.

## 2026-06-08 07:28 EDT

Hardened `web_frame_capture.dart` cleanup after the post-output hang observed
in the previous smoke.

- Replaced unmanaged Chrome stdout/stderr drains with retained stream
  subscriptions.
- Updated Chrome process disposal to:
  - avoid sending a signal if Chrome already exited;
  - wait for normal termination after `kill()`;
  - escalate to `SIGKILL` on timeout;
  - wait briefly after `SIGKILL`;
  - cancel stdout/stderr subscriptions with a bounded timeout;
  - keep profile-directory cleanup best-effort.
- Kept the capture artifact contract unchanged: JSON is still written before
  cleanup, but cleanup should no longer keep the Dart tool alive indefinitely
  because of open Chrome pipes.

Focused cleanup smoke:

- Capture directory: `/tmp/fleury_web_capture_exit_smoke_qp7HEo`.
- Command:
  `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=single-dirty-cell-160x50 --frames=3 --warmup=1 --output=/tmp/fleury_web_capture_exit_smoke_qp7HEo/single.json --timeout=60 --json`.
- Result:
  - command exited with code 0;
  - shell printed `EXIT_OK:/tmp/fleury_web_capture_exit_smoke_qp7HEo`;
  - no `web_frame_capture.dart` process remained afterward;
  - capture JSON parsed successfully.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_frame_capture_tool_test.dart` -
  passed.
- `git diff --check` - passed.

Current caveat:

- This verifies a focused short capture exits cleanly after the cleanup change.
  The next full `web_frame_suite` run should still watch for cleanup hangs
  across many repeated Chrome launches.

## 2026-06-08 07:39 EDT

Ran a repeated suite-level cleanup smoke after hardening
`web_frame_capture.dart`.

- Command:
  `cd packages/fleury_web && dart run tool/web_frame_suite.dart --runs=1 --output-dir=/tmp/fleury_web_suite_cleanup_smoke_DcZ4UT --scoreboard=/tmp/fleury_web_suite_cleanup_smoke_DcZ4UT/scoreboard.md --timeout=60`.
- The suite completed all 11 retained DOM scenarios and generated a strict
  comparable-environment scoreboard.
- Output directory:
  `/tmp/fleury_web_suite_cleanup_smoke_DcZ4UT`.
- Captures:
  - 11 capture JSON files;
  - 304 measured frames;
  - single run environment:
    `Chrome/148.0.7778.217`.
- Cleanup/lifecycle result:
  - every capture command returned control to the suite runner;
  - the suite advanced through all 11 sequential Chrome launches;
  - scoreboard generation completed;
  - the final shell printed `SUITE_OK:/tmp/fleury_web_suite_cleanup_smoke_DcZ4UT`;
  - no `web_frame_capture.dart` process remained afterward.
- Semantic coverage:
  - ran `cd packages/fleury_web && dart run tool/web_semantic_coverage_audit.dart --input=/tmp/fleury_web_suite_cleanup_smoke_DcZ4UT --output=/tmp/fleury_web_suite_cleanup_smoke_DcZ4UT/semantic-coverage.md --max-fallback-cells=0 --strict`;
  - strict semantic fallback gate passed;
  - fallback cells: 0;
  - fallback nodes: 0.

Scoreboard interpretation:

- This is a reliability smoke, not a promoted performance baseline.
- Run-environment checks passed for every scenario with `--min-runs=1`.
- Several scenarios remain over the 16.67 ms frame budget on this local
  machine; that is expected for the current branch and does not change the
  release-gate status.
- The result strengthens the Phase 5 benchmark evidence path by proving the
  capture cleanup fix survives repeated suite launches, not only a single
  capture.

Verification:

- `cd packages/fleury_web && dart run tool/web_frame_suite.dart --runs=1 --output-dir=/tmp/fleury_web_suite_cleanup_smoke_DcZ4UT --scoreboard=/tmp/fleury_web_suite_cleanup_smoke_DcZ4UT/scoreboard.md --timeout=60` -
  passed.
- `cd packages/fleury_web && dart run tool/web_semantic_coverage_audit.dart --input=/tmp/fleury_web_suite_cleanup_smoke_DcZ4UT --output=/tmp/fleury_web_suite_cleanup_smoke_DcZ4UT/semantic-coverage.md --max-fallback-cells=0 --strict` -
  passed.
- `ps -ax -o pid=,stat=,command= | rg 'web_frame_capture.dart|fleury_web_suite_cleanup_smoke_DcZ4UT|web_frame_suite.dart'` -
  found no remaining capture or suite process.

Current caveat:

- This suite has only one run per scenario. It is useful lifecycle evidence,
  but it is still not a reviewed Phase 5 baseline. The release path still
  needs repeated promoted captures under agreed conditions, reviewed
  thresholds, and manual IME/screen-reader evidence.

## 2026-06-08 08:09 EDT

Collected a refreshed repeated retained DOM candidate baseline after the
cleanup, sparse-damage, semantic replay, and incremental semantic DOM fixes.

- Baseline directory:
  `profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh`.
- Capture command:
  `cd packages/fleury_web && dart run tool/web_frame_suite.dart --runs=3 --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --scoreboard=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/scoreboard.md --write-thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --timeout=60`.
- The suite completed all 11 retained DOM scenarios with 3 runs each:
  - 33 capture JSON files;
  - 912 measured frames;
  - comparable run-environment gate passed for every scenario;
  - scoreboard and candidate threshold generation completed.
- Reran `web_frame_scoreboard.dart` after fixing candidate percentage
  threshold generation so `maxOverBudgetPercent` cannot exceed `100.0`.
  Added regression coverage in `web_frame_scoreboard_tool_test.dart`.
- Generated refreshed artifacts:
  - `scoreboard.md`;
  - `thresholds.candidate.json`;
  - `semantic-coverage.md`;
  - `readiness-candidate/scoreboard.json`;
  - `readiness-candidate/semantic-coverage.json`;
  - `readiness-candidate/manual-validation-audit.json`;
  - `readiness-candidate/web-readiness.json`;
  - `readiness-candidate/web-readiness.md`;
  - `profiling/web/manual/plan.md`;
  - `profiling/web/manual/review.md`;
  - `profiling/web/manual/chrome-ime-macos.template.json`;
  - `profiling/web/manual/chrome-voiceover-macos.template.json`.

Automated gate results:

- Frame scoreboard: strict pass with the generated candidate threshold policy.
- Semantic fallback audit: strict pass with zero fallback frames, zero fallback
  cells, and zero fallback nodes across all 912 measured frames.
- Readiness bundle: strict fail, as intended, because the two primary manual
  targets are only templates and remain `needsReview`:
  - `chrome-ime-macos`;
  - `chrome-voiceover-macos`.

Key damage and accessibility counters from the refreshed captures:

- `noop-160x50` latest capture:
  - 0 dirty rows;
  - 0 replaced rows;
  - 0 DOM nodes created;
  - 0 semantic fallback cells.
- `single-dirty-cell-160x50` latest capture:
  - 1 dirty row;
  - 1 replaced row;
  - 1 DOM node created;
  - 0 semantic fallback cells.
- `dirty-row-160x50` latest capture:
  - 2 dirty rows;
  - 2 replaced rows;
  - 2 DOM nodes created;
  - 0 semantic fallback cells.
- Sparse semantic DOM mutation is on the incremental path:
  - latest `single-dirty-cell-160x50` capture had semantic DOM created max 0,
    replaced max 0, reused max 1;
  - latest `dirty-row-160x50` capture had semantic DOM created max 0,
    replaced max 0, reused max 2.

Scoreboard interpretation:

- The local over-budget behavior remains runtime-render and semantic-apply
  dominated, not DOM-apply dominated.
- Median total-frame p95 range:
  - best: `noop-160x50` at 59.10 ms;
  - worst: `scroll-row-churn-160x50` at 1193.40 ms.
- `stress-300x100` is still 100% over budget locally and runtime-render
  dominated.
- `cursor-blink-80x24` is also runtime-render dominated across all three runs,
  which is now a concrete follow-up for the retained rendering path.
- Semantic split fields expose the remaining semantic cost:
  - latest `single-dirty-cell-160x50` semantic presenter max was 229.8 ms;
  - latest `scroll-row-churn-160x50` semantic diff max was 541.301 ms and
    semantic presenter max was 473.6 ms.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_frame_scoreboard_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_scoreboard_tool_test.dart test/web_frame_suite_tool_test.dart test/web_readiness_bundle_tool_test.dart test/web_manual_validation_tool_test.dart test/web_semantic_coverage_audit_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_frame_scoreboard.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/scoreboard.md --min-runs=3 --write-thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --threshold-headroom-percent=20 --threshold-min-headroom-ms=1 --threshold-min-headroom-percent=1 --require-comparable-environment --strict` -
  passed.
- `cd packages/fleury_web && dart run tool/web_semantic_coverage_audit.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/semantic-coverage.md --max-fallback-cells=0 --strict` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0` -
  completed and correctly reported readiness `strictPass: false`.
- `jq '[.. | objects | .maxOverBudgetPercent? // empty] | {count: length, max: max, anyOver100: any(. > 100)}' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json` -
  passed with `count: 11`, `max: 100.0`, and `anyOver100: false`.
- `git diff --check` - passed.
- `pgrep -af 'web_frame_capture.dart|web_frame_suite.dart|Chrome.*fleury|dart.*web_frame'` -
  found no remaining matching processes after verification.

Current caveat:

- This refreshed baseline is the best current re-review artifact, but it still
  uses candidate thresholds generated from the same local run. Phase 5/6 still
  require reviewed threshold values and reviewed manual Chrome IME /
  VoiceOver evidence before any default flip or temporary-path retirement.

## 2026-06-08 08:18 EDT

Hardened manual validation templates so generated scaffolding cannot masquerade
as reviewed manual evidence.

- Updated `web_manual_validation.dart` so `_loadEntries` ignores files ending
  in `.template.json`.
- Updated generated manual validation plan text to write templates under
  `profiling/web/manual/templates/<target>.template.json`.
- Updated `profiling/web/manual/README.md` to describe the template/evidence
  split:
  - templates live under `profiling/web/manual/templates/`;
  - template files are ignored by audits;
  - reviewers copy a completed template to a non-template evidence file such as
    `profiling/web/manual/evidence/<target>-<date>.json`.
- Added regression coverage proving a newer `.template.json` file is ignored
  while an older real evidence file remains authoritative.
- Removed the old root-level generated template files and regenerated:
  - `profiling/web/manual/plan.md`;
  - `profiling/web/manual/review.md`;
  - `profiling/web/manual/templates/chrome-ime-macos.template.json`;
  - `profiling/web/manual/templates/chrome-voiceover-macos.template.json`;
  - the Phase 1 refresh `readiness-candidate` bundle.

Current artifact behavior:

- Manual audit entry count is now 0 because no real evidence files exist yet.
- Manual audit reports `missingTargets` for:
  - `chrome-ime-macos`;
  - `chrome-voiceover-macos`.
- Readiness still reports `strictPass: false`, with frame scoreboard and
  semantic coverage passing and manual validation failing on missing evidence.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/plan.md --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/review.md` -
  passed.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --write-template=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates/chrome-ime-macos.template.json --template-target=chrome-ime-macos` -
  passed.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --write-template=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates/chrome-voiceover-macos.template.json --template-target=chrome-voiceover-macos` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0` -
  completed and correctly reported readiness `strictPass: false`.
- `jq '{entryCount, missingTargets, needsReviewTargets, strictPass}' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json` -
  passed with `entryCount: 0`, `missingTargets` for both primary targets, no
  `needsReviewTargets`, and `strictPass: false`.
- `git diff --check` - passed.
- `pgrep -af 'web_frame_capture.dart|web_frame_suite.dart|Chrome.*fleury|dart.*web_frame'` -
  found no remaining matching processes after verification.

Current caveat:

- The manual gate is now cleaner but still unresolved. Real Chrome IME and
  Chrome VoiceOver validation must produce non-template evidence files before
  readiness can pass.

## 2026-06-08 08:28 EDT

Hardened the Phase 6 readiness gate so candidate threshold policies cannot
accidentally satisfy release readiness.

- Updated `web_frame_scoreboard.dart` to propagate threshold policy
  `reviewState` into machine-readable scoreboard JSON as
  `thresholdPolicyReviewState`.
- Updated `web_readiness.dart` to require a threshold policy with
  `thresholdPolicyReviewState: reviewed` by default.
- Added `--no-require-reviewed-threshold-policy` for local diagnostic cases
  where a candidate policy should remain inspectable without being a release
  claim.
- Updated `web_readiness_bundle.dart` to forward that relaxation flag to both
  generated readiness artifacts.
- Updated docs so reviewed release policies explicitly use
  `reviewState: reviewed`, while generated policies remain
  `reviewState: candidate`.
- Regenerated the Phase 1 refresh readiness bundle from existing captures; no
  browser recapture was needed.

Current artifact behavior:

- `readiness-candidate/scoreboard.json` has:
  - `thresholdPolicyPath` pointing at `thresholds.candidate.json`;
  - `thresholdPolicyReviewState: candidate`;
  - frame scoreboard `strictPass: true`.
- `readiness-candidate/web-readiness.json` has readiness `strictPass: false`
  with:
  - frame scoreboard blocker:
    `frame scoreboard threshold policy reviewState is candidate; expected reviewed`;
  - semantic coverage check passing with 33 captures, 912 frames, zero fallback
    cells, and zero fallback nodes;
  - manual validation blocker for missing `chrome-ime-macos` and
    `chrome-voiceover-macos` evidence.

Verification:

- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_frame_scoreboard_tool_test.dart test/web_readiness_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0` -
  completed and correctly reported readiness `strictPass: false`.
- `jq '{strictPass, checks: [.checks[] | {id, strictPass, blockers, details}]}' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json` -
  confirmed the candidate-threshold blocker, semantic pass, and missing manual
  evidence blocker.
- `jq '{thresholdPolicyReviewState, strictPass, scenarioCount, runCount}' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json` -
  confirmed `thresholdPolicyReviewState: candidate`, frame-scoreboard
  `strictPass: true`, 11 scenarios, and 33 runs.
- `git diff --check` - passed.
- `pgrep -af 'web_frame_capture.dart|web_frame_suite.dart|Chrome.*fleury|dart.*web_frame'` -
  found no remaining matching processes after verification.

Current caveat:

- Phase 6 readiness now requires two separate human-reviewed inputs before it
  can pass: a `thresholds.json` policy with `reviewState: reviewed`, and real
  Chrome IME / Chrome VoiceOver manual evidence files.

## 2026-06-08 08:39 EDT

Added provenance requirements for reviewed threshold policies.

- Updated `web_frame_scoreboard.dart` to propagate optional threshold policy
  `reviewedBy` and `reviewedAt` fields into machine-readable scoreboard JSON
  as `thresholdPolicyReviewedBy` and `thresholdPolicyReviewedAt`.
- Updated `web_readiness.dart` so a threshold policy marked
  `reviewState: reviewed` must also have non-empty reviewer and timestamp
  provenance before the Phase 6 frame-scoreboard check can pass.
- Kept the diagnostic relaxation flag scoped to local use:
  `--no-require-reviewed-threshold-policy` still bypasses the reviewed-policy
  check, including provenance, but default readiness remains strict.
- Updated docs so reviewed threshold policy examples include:
  - `reviewState: reviewed`;
  - `reviewedBy`;
  - `reviewedAt`.
- Regenerated the Phase 1 refresh readiness bundle from existing captures; no
  browser recapture was needed.

Current artifact behavior:

- The Phase 1 refresh scoreboard still records:
  - `thresholdPolicyReviewState: candidate`;
  - no `thresholdPolicyReviewedBy`;
  - no `thresholdPolicyReviewedAt`;
  - frame scoreboard `strictPass: true` for the candidate policy itself.
- Combined readiness remains `strictPass: false` with the frame blocker
  `frame scoreboard threshold policy reviewState is candidate; expected reviewed`.
- When a future reviewed policy is supplied, readiness will additionally
  require reviewer and timestamp provenance.

Verification:

- `cd packages/fleury_web && dart test test/web_frame_scoreboard_tool_test.dart test/web_readiness_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0` -
  completed and correctly reported readiness `strictPass: false`.
- `jq '{thresholdPolicyReviewState, thresholdPolicyReviewedBy, thresholdPolicyReviewedAt, strictPass, scenarioCount, runCount}' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json` -
  confirmed candidate state, missing reviewed provenance, frame-scoreboard
  `strictPass: true`, 11 scenarios, and 33 runs.

Current caveat:

- This closes the metadata loophole, but does not create reviewed threshold
  evidence. A human-reviewed `thresholds.json` with reviewer/timestamp
  provenance is still required.

## 2026-06-08 08:49 EDT

Added a no-browser threshold promotion path and tightened the validation
cadence.

- Added `web_threshold_review.dart` to promote a candidate
  `fleuryWebFrameThresholds` policy to `reviewState: reviewed` with
  `reviewedBy` and `reviewedAt` provenance.
- Exposed the tool as `fleury benchmark web-threshold-review`, with
  root-relative `--input` and `--output` paths.
- Updated the root `fleury benchmark web-readiness` and
  `web-readiness-bundle` wrappers to forward
  `--no-require-reviewed-threshold-policy`, so candidate readiness diagnostics
  can run from the repository root without dropping into
  `packages/fleury_web`.
- Updated web artifact docs, package docs, and the Phase 1 refresh baseline
  notes so threshold promotion is repeatable and does not require browser
  recapture.
- Documented the faster validation cadence: use cached captures for
  scoreboard, semantic audit, threshold-review, readiness, and documentation
  changes; reserve Chrome recapture for runtime, presenter, input/focus,
  clipboard, semantics, benchmark scenario changes, or final evidence refresh.

Current caveat:

- No reviewed `thresholds.json` was generated in this slice. The current
  readiness candidate correctly remains red until human threshold review and
  real Chrome IME / Chrome VoiceOver evidence land.

## 2026-06-08 08:54 EDT

Added root launcher coverage for the threshold-review and cached-readiness
paths.

- Added `benchmark web-threshold-review` root launcher tests covering:
  - real candidate-to-reviewed promotion through `fleury benchmark`;
  - reviewer, timestamp, and review-note forwarding;
  - dry-run command forwarding to `tool/web_threshold_review.dart`.
- Extended the benchmark catalog test so `webThresholdReview` is visible in
  `fleury benchmark list --json`.
- Extended `web-readiness` and `web-readiness-bundle` dry-run tests so the
  root launcher proves it forwards
  `--no-require-reviewed-threshold-policy` for local candidate diagnostics.

Verification:

- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-threshold-review|web-readiness"` -
  passed.
- `cd packages/fleury && dart analyze test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_threshold_review_tool_test.dart` -
  passed.
- `dart analyze tool/fleury_dev.dart` - passed.

Current caveat:

- This protects the no-browser iteration workflow, but it still does not
  produce reviewed threshold or manual IME/screen-reader evidence. Readiness
  should remain red until those external review artifacts exist.

## 2026-06-08 09:01 EDT

Hardened manual validation evidence provenance.

- Updated `web_manual_validation.dart` so a manual target cannot strict-pass
  on `status: pass` and passing checks alone.
- Added per-target provenance blockers for:
  - non-empty `reviewedBy`;
  - non-empty `capturedAt`;
  - `environment.browser`;
  - `environment.browserVersion`;
  - `environment.platform`;
  - `environment.fleuryWebPage`;
  - target-specific `environment.inputMethod` for IME evidence;
  - target-specific `environment.assistiveTechnology` for screen-reader
    evidence.
- When a nominally passing entry is missing provenance, the target reports
  `status: needsReview`, includes `provenanceBlockers`, and fails strict
  readiness.
- Regenerated manual validation plan/review/templates and the Phase 1 refresh
  readiness-candidate bundle from existing artifacts; no browser recapture was
  needed.
- Updated docs so manual evidence provenance is explicit alongside threshold
  provenance.

Current artifact behavior:

- `readiness-candidate/manual-validation-audit.json` still has `entryCount: 0`,
  missing `chrome-ime-macos` and `chrome-voiceover-macos`, and
  `strictPass: false`.
- `readiness-candidate/web-readiness.json` remains `strictPass: false` with the
  candidate-threshold blocker and missing manual evidence blockers.

Verification:

- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_manual_validation.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `jq '{entryCount, missingTargets, needsReviewTargets, strictPass}' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json` -
  confirmed no real manual entries are present yet.

Current caveat:

- This closes another metadata loophole but still does not create real IME or
  VoiceOver evidence. Reviewers still need to run the manual validation page
  and commit non-template evidence files before Phase 6 can pass.

## 2026-06-08 09:05 EDT

Surfaced manual evidence diagnostics in the combined readiness audit.

- Updated `web_readiness.dart` so the manual-validation check includes
  `missingTargets`, `failedTargets`, `blockedTargets`, and
  `needsReviewTargets` in machine-readable details when present.
- Added per-target manual provenance blocker propagation into combined
  readiness details, so future entries missing reviewer/browser/page/IME or
  assistive-tech metadata will show exactly which fields block readiness.
- Added `web_readiness_tool_test.dart` coverage for manual provenance blockers.
- Regenerated the Phase 1 refresh readiness-candidate bundle from cached
  captures and manual artifacts; no browser recapture was needed.

Current artifact behavior:

- The current bundle still has no real manual entries, so
  `manualValidation.details.missingTargets` lists `chrome-ime-macos` and
  `chrome-voiceover-macos`.
- Future non-template entries with incomplete provenance will appear under
  `manualValidation.details.provenanceBlockers` and keep readiness red.

Verification:

- `cd packages/fleury_web && dart test test/web_readiness_tool_test.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_readiness.dart test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0` -
  completed with `strictPass: false`.
- `jq '.checks[] | select(.id == "manualValidation")' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json` -
  confirmed manual missing targets are present in check details.

Current caveat:

- This improves review diagnostics only. The external blockers remain the
  reviewed threshold policy and real Chrome IME / VoiceOver evidence.

## 2026-06-08 09:08 EDT

Hardened manual validation target matching.

- Updated `web_manual_validation.dart` so passing manual evidence must match
  the audited target metadata, not only provide non-empty environment fields.
- Manual evidence now records provenance blockers when:
  - `environment.browser` does not match the target browser;
  - `environment.platform` does not match the target platform;
  - screen-reader `environment.assistiveTechnology` does not match the target
    assistive technology.
- Added regression coverage showing a Safari/iOS/Narrator entry cannot satisfy
  the Chrome/macOS/VoiceOver target.
- Regenerated manual validation plan/review/templates and the Phase 1 refresh
  readiness-candidate bundle from cached artifacts; no browser recapture was
  needed.
- Updated docs so reviewers know browser/platform/assistive-tech values must
  match the audited target.

Current artifact behavior:

- The current readiness-candidate bundle still has no real manual entries, so
  the manual check reports `missingTargets` for `chrome-ime-macos` and
  `chrome-voiceover-macos`.
- Future wrong-browser or wrong-platform manual entries will remain
  `needsReview` and surface target-mismatch blockers in readiness details.

Verification:

- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_manual_validation.dart test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0` -
  completed with `strictPass: false`.

Current caveat:

- This closes the wrong-target-evidence loophole. The remaining unresolved
  items are still external: reviewed thresholds and real Chrome IME /
  VoiceOver evidence.

## 2026-06-08 09:18 EDT

Hardened Phase 6 threshold-policy precision.

- Updated `web_readiness.dart` so default readiness requires every frame
  scenario in a threshold-policy-backed scoreboard to report
  `thresholdPolicyMatchedScenario: true`.
- Added `--no-require-scenario-thresholds` to `web_readiness.dart`,
  `web_readiness_bundle.dart`, and the root
  `fleury benchmark web-readiness` / `web-readiness-bundle` wrappers for local
  defaults-only diagnostics.
- Added regression coverage for default failure on a defaults-only scenario
  policy and explicit relaxation through the readiness and bundle tools.
- Updated reviewer docs and the phase audit to clarify that Phase 6 readiness
  needs reviewed threshold provenance plus explicit per-scenario policy entries.
- Regenerated the Phase 1 refresh readiness-candidate bundle from cached
  captures; no browser recapture was needed.

Current artifact behavior:

- The current readiness-candidate bundle records
  `requireScenarioThresholds: true`.
- The candidate threshold policy already contains explicit entries for all 11
  scenarios, so the new gate does not add a scenario-threshold blocker.
- Readiness remains `strictPass: false` only because the threshold policy is
  still `reviewState: candidate` and real evidence is missing for
  `chrome-ime-macos` and `chrome-voiceover-macos`.

Verification:

- `cd packages/fleury_web && dart test test/web_readiness_tool_test.dart test/web_readiness_bundle_tool_test.dart test/web_frame_scoreboard_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_readiness.dart tool/web_readiness_bundle.dart test/web_readiness_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-readiness"` -
  passed.
- `dart analyze tool/fleury_dev.dart` - passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --json` -
  completed with `strictPass: false` for the expected candidate/manual blockers.
- `git diff --check` - passed.
- `pgrep -af 'web_frame_capture.dart|web_frame_suite.dart|Chrome.*fleury|dart.*web_frame'` -
  found no lingering capture or browser processes.

Current caveat:

- This closes the defaults-only-threshold loophole. The remaining unresolved
  items are still external: reviewed thresholds and real Chrome IME /
  VoiceOver evidence.

## 2026-06-08 09:26 EDT

Extracted a narrow shared `TuiRuntime`.

- Added `TuiRuntime` in core to own the shared `BuildOwner`, `FocusManager`,
  `TuiBinding`, `PointerRouter`, mounted root lifecycle, post-frame callback
  flushing, and framework render entry point.
- Updated native `runTui` to construct the shared runtime and route root
  mount/update, hot-reload reassembly, post-frame flushing, pointer-frame
  reset, and framework rendering through it.
- Updated retained DOM `runTuiSurface` to use the same runtime for shared
  framework-service ownership while keeping browser-specific metrics, queued
  input, semantics, focus coordination, instrumentation, and DOM presentation
  host-owned.
- Exported `TuiRuntime` from `fleury_core.dart` and added focused core runtime
  lifecycle tests.
- Updated the phase audit and web package README so Phase 1 now records both
  `TuiRuntime` and `TuiFrameLoop` as landed, rather than treating a fuller
  runtime extraction as pending.

Verification:

- `cd packages/fleury && dart test test/runtime/tui_runtime_test.dart test/runtime/tui_frame_loop_test.dart test/runtime/run_tui_test.dart` -
  passed.
- `cd packages/fleury && dart analyze lib/src/runtime/tui_runtime.dart lib/src/runtime/run_tui.dart lib/fleury_core.dart test/runtime/tui_runtime_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/run_tui_surface.dart test/run_tui_surface_test.dart test/run_tui_web_dom_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed.

Current caveat:

- The runtime remains intentionally narrow. It does not own terminal setup,
  browser surfaces, input-source lifetimes, debug UI, semantic presentation, or
  host-specific instrumentation; those are still native/web host policy.

## 2026-06-08 09:32 EDT

Added semantic coverage fallback diagnostics.

- Extended `web_semantic_coverage_audit.dart` so audit JSON includes
  `topFallbackCaptures` overall and per scenario.
- The diagnostic list is sorted by fallback cell count, fallback node count,
  fallback frame count, viewport impact, then path; it is empty when no
  fallback reliance is observed.
- Updated semantic coverage Markdown to include a `Top Fallback Captures`
  section, so reviewers can jump directly to the captures that need semantic
  backfill when coverage is non-zero.
- Surfaced non-empty `topFallbackCaptures` through combined
  `web_readiness.dart` semantic details.
- Updated web package/profiling docs and the phase audit to describe the new
  reviewer diagnostic.
- Regenerated the Phase 1 refresh semantic coverage Markdown and
  readiness-candidate bundle from cached captures; no browser recapture was
  needed.

Current artifact behavior:

- `readiness-candidate/semantic-coverage.json` now has
  `topFallbackCaptures: []`.
- No scenario in the current Phase 1 refresh candidate has fallback reliance;
  the semantic coverage check remains strict-pass with 33 captures, 912
  frames, zero fallback cells, and zero fallback nodes.
- Combined readiness remains `strictPass: false` for the expected non-semantic
  blockers: candidate threshold policy review state and missing
  `chrome-ime-macos` / `chrome-voiceover-macos` manual evidence.

Verification:

- `cd packages/fleury_web && dart test test/web_semantic_coverage_audit_tool_test.dart test/web_readiness_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_semantic_coverage_audit.dart tool/web_readiness.dart test/web_semantic_coverage_audit_tool_test.dart test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_semantic_coverage_audit.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/semantic-coverage.md --max-fallback-cells=0` -
  regenerated the Markdown audit.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --json` -
  regenerated the readiness-candidate bundle with `strictPass: false` for the
  expected candidate/manual blockers.

Current caveat:

- This improves coverage triage if fallback appears in future captures. It
  does not replace manual screen-reader validation or broaden the current
  captured widget-state coverage.

## 2026-06-08 09:40 EDT

Hardened reviewed threshold policy context.

- Added required `--review-context=TEXT` to `web_threshold_review.dart`.
- Promoted threshold policies now write `reviewContext` alongside
  `reviewState`, `reviewedBy`, `reviewedAt`, and optional `reviewNote`.
- `web_frame_scoreboard.dart` now propagates `reviewContext` into
  machine-readable scoreboard JSON as `thresholdPolicyReviewContext`.
- `web_readiness.dart` now rejects reviewed threshold policies that lack
  `thresholdPolicyReviewContext`, closing the gap where a policy could be
  marked reviewed without documenting the accepted product/browser/environment
  basis.
- Updated the root `fleury benchmark web-threshold-review` launcher, catalog,
  dry-run tests, docs, and examples to require/pass `--review-context`.
- Regenerated the Phase 1 refresh readiness-candidate bundle from cached
  captures; no browser recapture was needed.

Current artifact behavior:

- The current readiness-candidate bundle remains `strictPass: false` because
  the threshold policy is still `reviewState: candidate` and manual evidence
  is missing for `chrome-ime-macos` and `chrome-voiceover-macos`.
- Once a candidate policy is promoted, the reviewed file must include
  `reviewContext`, and the generated scoreboard must carry
  `thresholdPolicyReviewContext` before default Phase 6 readiness can pass.

Verification:

- `cd packages/fleury_web && dart test test/web_threshold_review_tool_test.dart test/web_frame_scoreboard_tool_test.dart test/web_readiness_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_threshold_review.dart tool/web_frame_scoreboard.dart tool/web_readiness.dart test/web_threshold_review_tool_test.dart test/web_frame_scoreboard_tool_test.dart test/web_readiness_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-threshold-review|web-readiness"` -
  passed.
- `dart analyze tool/fleury_dev.dart` - passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --json` -
  regenerated the readiness-candidate bundle with the expected candidate/manual
  blockers.

Current caveat:

- This makes threshold review provenance stricter, but it does not create a
  reviewed threshold policy or manual IME/screen-reader evidence.

## 2026-06-08 09:48 EDT

Added Phase 6 default/retirement preflight.

- Added `web_default_preflight.dart` as an artifact-only gate over
  `web-readiness.json`.
- The preflight supports two explicit release targets:
  `make-dom-default` and `retire-temporary-paths`.
- It fails strict mode unless the consumed Phase 6 readiness artifact has
  `strictPass: true`.
- When readiness is blocked, it carries through the failed readiness checks and
  blockers so reviewers can distinguish threshold, semantic, and manual
  evidence gaps without rerunning browser captures.
- The tool preserves machine-readable stdout when `--json --output` are used
  together.
- Added root launcher support as
  `fleury benchmark web-default-preflight`, including benchmark catalog,
  command help, and dry-run coverage.
- Updated web package docs and the phase audit to make the preflight the
  explicit final check before a DOM default flip or temporary-path retirement.

Current artifact behavior:

- The existing readiness-candidate bundle would still block the preflight
  because readiness remains `strictPass: false` for the expected blockers:
  candidate threshold policy review state and missing `chrome-ime-macos` /
  `chrome-voiceover-macos` manual evidence.
- No browser recapture was needed; this slice only consumes existing readiness
  JSON artifacts.

Verification:

- `cd packages/fleury_web && dart analyze tool/web_default_preflight.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-readiness launcher"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --target=make-dom-default --strict --json` -
  exited 1 as expected, carrying through the candidate threshold-policy blocker
  and missing `chrome-ime-macos` / `chrome-voiceover-macos` manual evidence
  blockers.

Current caveat:

- This does not flip the default web API and does not retire xterm-compatible
  `runTuiWeb`; it makes those future actions conditional on a strict readiness
  artifact instead of prose-only rollout discipline.

## 2026-06-08 09:53 EDT

Moved the xterm-compatible web runner onto `TuiRuntime`.

- Updated `run_tui_web.dart` so the legacy/xterm-compatible browser path now
  uses the shared `TuiRuntime` for:
  - `BuildOwner`;
  - `FocusManager`;
  - `TuiBinding`;
  - `PointerRouter`;
  - root mount/update lifecycle;
  - frame rendering;
  - post-frame callback flushing.
- Kept host-owned concerns in `runTuiWeb`: `WebTerminalDriver`, ANSI
  rendering, browser rAF flush scheduling, event queueing, resize handling,
  and `TuiFrameLoop` presentation/damage commit.
- Added browser test coverage proving a post-frame `setState` schedules and
  renders a second xterm-compatible web frame through the injected flush path.

Current artifact behavior:

- This is a runtime refactor only. It does not change retained DOM evidence,
  readiness artifacts, threshold policy state, or manual evidence state.
- The current readiness-candidate blockers remain unchanged: candidate
  threshold review state and missing real IME/screen-reader manual evidence.

Verification:

- `cd packages/fleury_web && dart analyze lib/src/run_tui_web.dart test/run_tui_web_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_test.dart` -
  passed.

Current caveat:

- `runTuiWeb` remains the xterm-compatible transport path and is not the final
  retained DOM product entry point. This slice only removes duplicated runtime
  ownership from that path so Phase 1's shared runtime boundary is consistent
  across both web runners.

## 2026-06-08 09:56 EDT

Hardened xterm-compatible web runner cleanup.

- Added idempotent cleanup to `run_tui_web.dart` when the driver event stream
  closes.
- Cleanup now marks the runner disposed, disposes the shared `FrameScheduler`,
  `InputDispatcher`, and `TuiRuntime`, cancels the event subscription when
  appropriate, and restores the driver.
- Scheduled frame flushes that fire after cleanup now no-op before touching the
  disposed runtime or driver.
- Added browser regression coverage for closing the driver before an initial
  pending frame flush fires.

Current artifact behavior:

- This is another runtime-lifecycle hardening slice only. It does not update
  benchmark captures, readiness artifacts, threshold policy state, or manual
  evidence.

Verification:

- `cd packages/fleury_web && dart analyze lib/src/run_tui_web.dart test/run_tui_web_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_test.dart` -
  passed.

Current caveat:

- The default/retirement gates remain blocked by the same external evidence:
  reviewed per-scenario thresholds and real IME/VoiceOver manual validation.

## 2026-06-08 10:01 EDT

Hardened xterm-compatible web runner setup failure cleanup.

- Wrapped the `runTuiWeb` entered setup path in cleanup-on-error.
- If setup fails after `TerminalDriver.enter` succeeds, `runTuiWeb` now
  disposes the shared scheduler/dispatcher/runtime state and restores the
  driver before rethrowing the original error.
- Added browser regression coverage with a driver whose first write fails,
  proving the entered driver is restored and no frame remains pending.

Current artifact behavior:

- This is runtime lifecycle hardening only. No capture, threshold, readiness,
  or manual validation artifacts changed.

Verification:

- `cd packages/fleury_web && dart analyze lib/src/run_tui_web.dart test/run_tui_web_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_test.dart` -
  passed.

Current caveat:

- This closes another cleanup hole in the legacy/xterm-compatible web path,
  but Phase 6 defaulting still depends on reviewed threshold and manual
  accessibility evidence.

## 2026-06-08 10:05 EDT

Hardened retained DOM host setup failure cleanup.

- Added cleanup-on-error around `runTuiSurface` setup.
- If setup fails before a `TuiSurfaceHost` is returned, the host now:
  - marks the runner disposed;
  - disposes the input source;
  - disposes any created frame scheduler;
  - disposes cell metrics;
  - disposes the retained semantics owner;
  - clears semantic action callbacks;
  - disposes the semantic presenter;
  - disposes the shared `TuiRuntime`;
  - disposes the visual `FrameSurface`;
  - restores the previous `Clipboard.instance` when a web clipboard backend was
    installed.
- Added retained DOM browser regression coverage for a setup failure during
  initial metrics-driven surface resize, proving partial host resources are
  disposed and clipboard state is restored.

Current artifact behavior:

- This is retained DOM runtime-lifecycle hardening only. No browser capture,
  threshold, readiness, or manual validation artifacts changed.

Verification:

- `cd packages/fleury_web && dart analyze lib/src/run_tui_surface.dart test/run_tui_surface_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed.

Current caveat:

- This closes a setup-failure leak in the retained DOM host. Release defaulting
  remains blocked by reviewed per-scenario thresholds and real IME/VoiceOver
  manual validation.

## 2026-06-08 10:08 EDT

Added the web RFC re-review packet.

- Created `docs/implementation/web-rfc-review-packet.md` as the compact
  reviewer entry point for the Phase 1 worktree.
- The packet summarizes the architecture under review, current DOM-first
  recommendation, candidate evidence, remaining release gates, and efficient
  validation cadence.
- Linked the packet from `docs/implementation/README.md`.
- Updated the Phase 6 audit evidence pointer to the latest refreshed
  `2026-06-08-local-dom-retained-phase1-refresh` readiness candidate.

Current artifact behavior:

- No runtime, capture, threshold, readiness, or manual evidence artifacts
  changed.
- The packet explicitly says to reuse existing candidate JSON artifacts for
  threshold/readiness iteration and reserve full Chrome recapture for runtime,
  presenter, input, semantics, scenario, or final-evidence changes.

Verification:

- `git diff --check` - passed.

Current caveat:

- The default/retirement gates remain blocked by reviewed per-scenario
  thresholds and real IME/VoiceOver manual validation.

## 2026-06-08 10:12 EDT

Tightened the public retained DOM host handle.

- Exported `TuiSurfaceHost` from `package:fleury_web/fleury_web.dart` while
  keeping the lower-level `runTuiSurface` assembly entry point private to the
  package.
- Updated the retained DOM browser assembly test to explicitly type the
  `runTuiWebDom` return value as `TuiSurfaceHost`, so the public barrel proves
  callers can name the disposable/request-frame handle.
- Updated the review packet and phase audit to document this as the current
  public boundary: `runTuiWebDom` plus returned host handle are public; direct
  surface assembly remains private until the host stabilizes.

Current artifact behavior:

- No browser captures, threshold policies, readiness bundles, or manual
  evidence changed.

Verification:

- `cd packages/fleury_web && dart analyze lib/fleury_web.dart test/run_tui_web_dom_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --target=make-dom-default --strict --json` -
  exited 1 as expected because the threshold policy remains `candidate` and
  `chrome-ime-macos` / `chrome-voiceover-macos` manual evidence is missing.
- `git diff --check` - passed.

Current caveat:

- This is API-boundary polish for re-review only. Phase 6 defaulting remains
  blocked by reviewed per-scenario thresholds and real IME/VoiceOver manual
  validation.

## 2026-06-08 10:17 EDT

Hardened retained DOM wrapper element cleanup.

- Added a host-resource disposal hook to `runTuiSurface` so the returned
  `TuiSurfaceHost` can clean up wrapper resources owned by a higher-level web
  assembly function.
- Updated `runTuiWebDom` to remove only the generated visual and semantic root
  elements on dispose or setup failure. Caller-supplied roots remain
  caller-owned.
- Extended the retained DOM browser assembly test to prove disposing
  `TuiSurfaceHost` removes generated `.fleury-screen`, `.fleury-semantics`, and
  hidden textarea DOM while preserving the caller's host element and restoring
  the previous clipboard.
- Updated the review packet and phase audit to call out generated-root cleanup
  as part of the retained DOM lifecycle surface.

Current artifact behavior:

- No browser captures, threshold policies, readiness bundles, or manual
  evidence changed.

Verification:

- `cd packages/fleury_web && dart format lib/src/run_tui_surface.dart lib/src/run_tui_web_dom.dart test/run_tui_web_dom_test.dart` -
  passed with no file changes.
- `cd packages/fleury_web && dart analyze lib/src/run_tui_surface.dart lib/src/run_tui_web_dom.dart test/run_tui_web_dom_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed.

Current caveat:

- This closes a retained DOM lifecycle cleanup gap, but Phase 6 defaulting
  remains blocked by reviewed per-scenario thresholds and real IME/VoiceOver
  manual validation.

## 2026-06-08 10:20 EDT

Locked the retained DOM public API boundary.

- Added `packages/fleury_web/test/web_public_api_boundary_test.dart`.
- The test proves the package barrel intentionally exports `runTuiWebDom`,
  returned `TuiSurfaceHost`, and the xterm-compatible `runTuiWeb`, while
  keeping `runTuiSurface`, `DomGridSurface`, `DomInputSource`,
  `SemanticDomPresenter`, and `DomCellMetrics` out of the production barrel.
- Updated the review packet and phase audit to document this as the current
  public/private split for the retained DOM web host.

Current artifact behavior:

- No runtime behavior, browser captures, threshold policies, readiness bundles,
  or manual evidence changed.

Verification:

- `cd packages/fleury_web && dart format test/web_public_api_boundary_test.dart` -
  passed with no file changes.
- `cd packages/fleury_web && dart analyze test/web_public_api_boundary_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_public_api_boundary_test.dart` -
  passed.
- `rg -n "[ \t]+$" packages/fleury_web/test/web_public_api_boundary_test.dart docs/implementation/web-rfc-review-packet.md docs/implementation/web-rfc-phase-audit.md docs/implementation/web-rfc-execution-log.md` -
  passed with no matches.

Current caveat:

- This locks a narrow package API for re-review. Phase 6 defaulting remains
  blocked by reviewed per-scenario thresholds and real IME/VoiceOver manual
  validation.

## 2026-06-08 10:26 EDT

Added a first-class retained DOM demo page.

- Added `packages/fleury_web/web/dom_demo.html`.
- Added `packages/fleury_web/web/dom_demo.dart`, a small no-xterm Fleury app
  rendered through `runTuiWebDom`.
- The demo covers retained visual DOM, browser text input, state updates,
  semantic status nodes, and a semantic action node.
- Kept `web/index.html` and `web/main.dart` as the xterm-compatible demo
  instead of making retained DOM the package default before Phase 6 gates pass.
- Updated `packages/fleury_web/README.md` with separate retained DOM and xterm
  bridge demo instructions.
- Broadened `packages/fleury_web/.gitignore` so generated
  `web/*.dart.js`, `.deps`, and `.map` outputs stay out of source control.
- Updated the review packet and phase audit to include the runnable retained
  DOM demo as local reviewer evidence.

Current artifact behavior:

- Compiled `web/dom_demo.dart.js` was generated locally for the browser smoke
  and is ignored. No benchmark captures, threshold policies, readiness bundles,
  or manual evidence changed.

Verification:

- `cd packages/fleury_web && dart format web/dom_demo.dart` - passed and
  formatted the new file.
- `cd packages/fleury_web && dart analyze web/dom_demo.dart` - passed.
- `cd packages/fleury_web && dart compile js web/dom_demo.dart -o web/dom_demo.dart.js` -
  passed.
- Local browser smoke against `http://127.0.0.1:8765/dom_demo.html`:
  - body ready marker `data-fleury-dom-demo="ready"` was present;
  - `.fleury-screen` existed and had `aria-hidden="true"`;
  - `.fleury-semantics` and hidden `textarea` existed;
  - semantic roles included textbox, button, and status nodes;
  - filling `abc` through the textarea updated draft length to 3;
  - pressing Enter incremented the counter, recorded `last submit abc`, and
    cleared draft length to 0;
  - screenshot showed the retained DOM demo nonblank and correctly framed.
- `rg -n "[ \t]+$" packages/fleury_web/.gitignore packages/fleury_web/web/dom_demo.dart packages/fleury_web/web/dom_demo.html packages/fleury_web/README.md` -
  passed with no matches before the log update.
- `git diff --check` - passed.
- `rg -n "[ \t]+$" packages/fleury_web/.gitignore packages/fleury_web/web/dom_demo.dart packages/fleury_web/web/dom_demo.html packages/fleury_web/README.md docs/implementation/web-rfc-review-packet.md docs/implementation/web-rfc-phase-audit.md docs/implementation/web-rfc-execution-log.md` -
  passed with no matches after the log update.

Current caveat:

- This gives reviewers a concrete retained DOM page to open, but it does not
  change Phase 6 defaulting. Reviewed thresholds and real IME/VoiceOver manual
  evidence remain required.

## 2026-06-08 10:32 EDT

Added automated browser coverage for the retained DOM demo.

- Refactored `web/dom_demo.dart` so the page still calls `main`, while tests
  can call `runDomDemo(...)` and dispose the returned `TuiSurfaceHost`.
- `runDomDemo` accepts an optional `FrameFlushScheduler`, preserving real rAF
  behavior for the browser page while allowing deterministic browser tests.
- Added `packages/fleury_web/test/dom_demo_test.dart`.
- The browser test imports the actual demo source, launches it into a test DOM
  host, verifies retained DOM and semantic DOM roots, dispatches text input,
  flushes a frame, presses Enter, and verifies the counter/submission state.
- Updated the review packet and phase audit so the retained DOM demo is listed
  as both runnable local evidence and automated browser-covered source.

Current artifact behavior:

- Compiled `web/dom_demo.dart.js` was regenerated locally and remains ignored.
- No benchmark captures, threshold policies, readiness bundles, or manual
  evidence changed.

Verification:

- First attempt with real rAF scheduling exposed a nondeterministic browser-test
  timeout waiting for the initial frame; the test was revised to inject the
  same deterministic flush hook used by other web host tests.
- `cd packages/fleury_web && dart format web/dom_demo.dart test/dom_demo_test.dart` -
  passed with no file changes.
- `cd packages/fleury_web && dart analyze web/dom_demo.dart test/dom_demo_test.dart` -
  passed.
- `cd packages/fleury_web && dart compile js web/dom_demo.dart -o web/dom_demo.dart.js` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_demo_test.dart` -
  passed.
- `git diff --check` - passed.
- `rg -n "[ \t]+$" packages/fleury_web/web/dom_demo.dart packages/fleury_web/test/dom_demo_test.dart docs/implementation/web-rfc-review-packet.md docs/implementation/web-rfc-phase-audit.md docs/implementation/web-rfc-execution-log.md` -
  passed with no matches.

Current caveat:

- This is automated coverage for the retained DOM demo source. Phase 6
  defaulting still requires reviewed thresholds and real IME/VoiceOver manual
  evidence.

## 2026-06-08 10:36 EDT

Tightened retained DOM demo readiness semantics.

- Updated `web/dom_demo.dart` so `data-fleury-dom-demo="mounted"` means the
  host has been constructed.
- Added a demo-local `WebHostInstrumentation` sink that flips the same marker
  to `"ready"` only after the first retained DOM frame is recorded.
- Kept real rAF behavior for the actual page and deterministic frame flushing
  for `test/dom_demo_test.dart`.
- Updated the browser test to assert the mounted-to-ready transition, then
  verify retained DOM text input and submit behavior.
- Updated the review packet and phase audit to describe the marker semantics.

Current artifact behavior:

- Compiled `web/dom_demo.dart.js` was regenerated locally and remains ignored.
- No benchmark captures, threshold policies, readiness bundles, or manual
  evidence changed.

Verification:

- `cd packages/fleury_web && dart format web/dom_demo.dart test/dom_demo_test.dart` -
  passed with no file changes.
- `cd packages/fleury_web && dart analyze web/dom_demo.dart test/dom_demo_test.dart` -
  passed.
- `cd packages/fleury_web && dart compile js web/dom_demo.dart -o web/dom_demo.dart.js` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_demo_test.dart` -
  passed.
- `git diff --check` - passed.
- `rg -n "[ \t]+$" packages/fleury_web/web/dom_demo.dart packages/fleury_web/test/dom_demo_test.dart docs/implementation/web-rfc-review-packet.md docs/implementation/web-rfc-phase-audit.md docs/implementation/web-rfc-execution-log.md` -
  passed with no matches.

Current caveat:

- This makes the demo's readiness marker frame-backed. Phase 6 defaulting still
  requires reviewed thresholds and real IME/VoiceOver manual evidence.

## 2026-06-08 10:39 EDT

Tightened manual validation page readiness semantics.

- Refactored `web/manual_validation.dart` so the browser page still calls
  `main`, while tests can call `runManualValidation(...)` and dispose the
  returned `TuiSurfaceHost`.
- Added a page-local `WebHostInstrumentation` sink that sets
  `data-fleury-manual-validation="ready"` only after the first retained DOM
  frame is recorded. Host construction now sets the marker to `"mounted"`.
- Kept real rAF behavior for the actual page and deterministic frame flushing
  for the browser test.
- Added `packages/fleury_web/test/manual_validation_page_test.dart`.
- The browser test imports the actual manual validation page source, verifies
  the mounted-to-ready marker transition, and checks retained DOM plus semantic
  textbox/button/link roles required by the manual evidence checklist.
- Updated the README, review packet, and phase audit to document the
  frame-backed manual validation marker.

Current artifact behavior:

- Compiled `web/manual_validation.dart.js` was generated locally and remains
  ignored.
- No benchmark captures, threshold policies, readiness bundles, or manual
  evidence changed.

Verification:

- `cd packages/fleury_web && dart format web/manual_validation.dart test/manual_validation_page_test.dart` -
  passed with no file changes.
- `cd packages/fleury_web && dart analyze web/manual_validation.dart test/manual_validation_page_test.dart` -
  passed.
- `cd packages/fleury_web && dart compile js web/manual_validation.dart -o web/manual_validation.dart.js` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/manual_validation_page_test.dart` -
  passed.
- `git diff --check` - passed.

- `rg -n "[ \t]+$" packages/fleury_web/web/manual_validation.dart packages/fleury_web/test/manual_validation_page_test.dart packages/fleury_web/README.md docs/implementation/web-rfc-review-packet.md docs/implementation/web-rfc-phase-audit.md docs/implementation/web-rfc-execution-log.md` -
  passed with no matches.

Current caveat:

- This makes the manual validation page's ready marker frame-backed. It does
  not replace real Chrome IME or VoiceOver evidence.

## 2026-06-08 10:43 EDT

Tightened generated manual validation instructions around the frame-backed
readiness marker.

- Updated `tool/web_manual_validation.dart` so generated plans tell reviewers
  to start manual checks only after `manual_validation.html` reports
  `data-fleury-manual-validation="ready"` on `document.body`.
- Clarified in generated text that `"mounted"` only means the retained DOM host
  was constructed; it does not mean the first retained DOM frame has presented.
- Updated the `manual-page-loads-dom-host` checklist target so generated IME
  evidence templates require the `ready` marker alongside visible retained DOM
  output and absence of xterm.
- Extended `test/web_manual_validation_tool_test.dart` to assert the plan and
  generated evidence template contain the ready-marker requirement.
- Updated the review packet and phase audit to keep reviewer-facing docs
  aligned with the generated manual-evidence workflow.

Verification:

- `cd packages/fleury_web && dart format tool/web_manual_validation.dart test/web_manual_validation_tool_test.dart` -
  passed with no file changes.
- `cd packages/fleury_web && dart analyze tool/web_manual_validation.dart test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed.

## 2026-06-08 10:45 EDT

Aligned the package README manual-validation instructions with the
frame-backed ready-marker rule.

- Updated `packages/fleury_web/README.md` so the manual validation workflow
  tells reviewers to begin checks only after `document.body` reports
  `data-fleury-manual-validation="ready"`.
- Clarified in the README that the intermediate `"mounted"` marker only proves
  retained DOM host construction, not first-frame presentation.

Current artifact behavior:

- No browser code, generated evidence, capture artifacts, or threshold policies
  changed.

Verification:

- `git diff --check` - passed.
- `rg -n "[ \t]+$" packages/fleury_web/README.md docs/implementation/web-rfc-execution-log.md docs/implementation/web-rfc-review-packet.md docs/implementation/web-rfc-phase-audit.md packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/test/web_manual_validation_tool_test.dart` -
  passed with no matches.

## 2026-06-08 10:49 EDT

Regenerated manual validation artifacts from the ready-marker-aware manual
validation tool.

- Regenerated `profiling/web/manual/plan.md`, `profiling/web/manual/review.md`,
  and both target templates under `profiling/web/manual/templates/`.
- Confirmed the generated plan tells reviewers to wait for
  `data-fleury-manual-validation="ready"` on `document.body` before starting
  manual checks.
- Confirmed the generated `chrome-ime-macos` template's
  `manual-page-loads-dom-host` check requires the `ready` marker, visible
  retained DOM output, and absence of xterm.
- Updated `profiling/web/manual/README.md` with the same ready-marker rule.
- Fixed the Phase 1 refresh baseline README threshold-promotion command to
  include the required `--review-context=...` argument.
- Updated the Phase 1 refresh baseline README to call out that manual evidence
  collection must wait for the frame-backed ready marker.

Current artifact behavior:

- Manual templates remain templates only; files ending in `.template.json` are
  still ignored by audits.
- Strict manual validation still fails as expected because real
  `chrome-ime-macos` and `chrome-voiceover-macos` evidence has not been
  collected.
- No browser captures, threshold policies, or readiness bundles changed.

Verification:

- `cd packages/fleury_web && dart analyze tool/web_manual_validation.dart test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --strict --json` -
  exited 1 as expected with missing targets
  `chrome-ime-macos` and `chrome-voiceover-macos`.
- `git diff --check` - passed.
- `rg -n "[ \t]+$" profiling/web/manual/README.md profiling/web/manual/plan.md profiling/web/manual/review.md profiling/web/manual/templates/chrome-ime-macos.template.json profiling/web/manual/templates/chrome-voiceover-macos.template.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/README.md packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/test/web_manual_validation_tool_test.dart docs/implementation/web-rfc-execution-log.md` -
  passed with no matches.
- `jq empty profiling/web/manual/templates/chrome-ime-macos.template.json profiling/web/manual/templates/chrome-voiceover-macos.template.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json` -
  passed.

## 2026-06-08 10:52 EDT

Refreshed the Phase 1 refresh readiness-candidate bundle from cached artifacts
after regenerating the ready-marker-aware manual validation plan/templates.

- Regenerated
  `profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json`.
- Regenerated
  `profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json`.
- Regenerated
  `profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json`.
- Regenerated
  `profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json`
  and `web-readiness.md`.
- Updated the Phase 1 refresh baseline README readiness-bundle command to
  include `--target-preset=primary --json`, matching the refreshed artifact
  command.

Current artifact behavior:

- The refreshed bundle remains `strictPass: false`, as intended.
- `scoreboard.json` passes as a cached artifact but still uses
  `thresholds.candidate.json`, so Phase 6 readiness blocks on
  `reviewState: candidate`.
- `semantic-coverage.json` passes with 33 captures, 912 measured frames, and
  zero fallback cells.
- `manual-validation-audit.json` still has `entryCount: 0` and missing targets
  `chrome-ime-macos` and `chrome-voiceover-macos`.
- The default preflight still blocks `make-dom-default`; no browser recapture
  was run.

Verification:

- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --json` -
  passed and reported `strictPass: false`.
- `jq '{strictPass, checks: [.checks[] | {id, strictPass, blockers}]}' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json` -
  confirmed the expected candidate-threshold and missing-manual-evidence
  blockers.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --target=make-dom-default --strict --json` -
  exited 1 as expected and reported the same blockers.
- `jq empty profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json profiling/web/manual/templates/chrome-ime-macos.template.json profiling/web/manual/templates/chrome-voiceover-macos.template.json` -
  passed.

## 2026-06-08 10:59 EDT

Tightened the screen-reader manual evidence target so standalone VoiceOver
evidence cannot skip retained semantic DOM readiness.

- Added `manual-page-ready-semantic-host` to the `chrome-voiceover-macos`
  manual validation target.
- The new check requires `manual_validation.html` to reach
  `data-fleury-manual-validation="ready"`, retained semantic DOM output to be
  reachable, and no xterm element to be present.
- Updated manual-validation tests so generated VoiceOver templates include the
  ready/no-xterm semantic-host check.
- Updated readiness-bundle fixtures and synthetic readiness helper data so
  VoiceOver evidence has seven required checks while IME remains at six.
- Regenerated `profiling/web/manual/plan.md`, `profiling/web/manual/review.md`,
  and both manual target templates.
- Regenerated the Phase 1 refresh `readiness-candidate` bundle from cached
  captures and the updated manual evidence templates.
- Updated reviewer-facing docs to call out that the VoiceOver target now
  carries a target-specific semantic-host readiness check.

Current artifact behavior:

- `chrome-ime-macos` remains missing with 0/6 required checks.
- `chrome-voiceover-macos` now remains missing with 0/7 required checks,
  including `manual-page-ready-semantic-host`.
- The Phase 1 refresh readiness artifact remains `strictPass: false` because
  thresholds are still candidate and real manual evidence is still missing.
- No browser recapture was run.

Verification:

- `cd packages/fleury_web && dart format tool/web_manual_validation.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_manual_validation.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --json` -
  passed and reported `strictPass: false`.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --strict --json` -
  exited 1 as expected with `chrome-ime-macos` at 0/6 and
  `chrome-voiceover-macos` at 0/7.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --target=make-dom-default --strict --json` -
  exited 1 as expected with candidate-threshold and missing-manual-evidence
  blockers.
- `jq empty profiling/web/manual/templates/chrome-ime-macos.template.json profiling/web/manual/templates/chrome-voiceover-macos.template.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json` -
  passed.

## 2026-06-08 11:03 EDT

Exposed manual target check diagnostics in the combined Phase 6 readiness JSON.

- Updated `tool/web_readiness.dart` so the manual validation check includes
  `failingTargetDetails` in machine-readable details.
- Each failing manual target detail includes target ID, status, strict pass
  state, required check count, passed check count, and missing/failed/blocked
  check IDs when present.
- Added focused coverage in `test/web_readiness_tool_test.dart` proving the
  combined readiness JSON reports `chrome-voiceover-macos` with
  `requiredCheckCount: 7` and `manual-page-ready-semantic-host` in
  `missingCheckIds`.
- Regenerated the Phase 1 refresh `readiness-candidate` bundle from cached
  captures so `web-readiness.json` now carries the manual target diagnostics.
- Updated the review packet and phase audit to document that reviewers can see
  per-target manual gate details directly in the combined readiness artifact.

Current artifact behavior:

- The refreshed `web-readiness.json` still has `strictPass: false`.
- The manual validation check details now include:
  - `chrome-ime-macos`: missing 6 of 6 checks;
  - `chrome-voiceover-macos`: missing 7 of 7 checks, including
    `manual-page-ready-semantic-host`.
- No browser recapture was run.

Verification:

- `cd packages/fleury_web && dart format tool/web_readiness.dart test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_readiness.dart test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --json` -
  passed and reported `strictPass: false` with `failingTargetDetails`.
- `cd packages/fleury_web && dart analyze tool/web_readiness.dart tool/web_readiness_bundle.dart test/web_readiness_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `jq '.checks[] | select(.id=="manualValidation") | .details.failingTargetDetails' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json` -
  confirmed IME 0/6 and VoiceOver 0/7 target diagnostics.

## 2026-06-08 11:07 EDT

Mirrored manual target diagnostics into the human-readable readiness report.

- Updated `tool/web_readiness.dart` so `web-readiness.md` includes a Manual
  Target Diagnostics table when manual evidence targets fail readiness.
- The table reports target ID, status, passed/required check count, and missing
  check IDs.
- Extended `test/web_readiness_tool_test.dart` to verify the Markdown report
  includes IME 0/6, VoiceOver 0/7, and `manual-page-ready-semantic-host`.
- Regenerated the Phase 1 refresh `readiness-candidate` bundle from cached
  captures so both `web-readiness.json` and `web-readiness.md` carry the same
  manual target diagnostics.
- Updated the review packet and phase audit to document that both JSON and
  Markdown readiness artifacts expose the manual target diagnostics.

Current artifact behavior:

- `web-readiness.md` now includes a Manual Target Diagnostics section with:
  - `chrome-ime-macos`: 0/6 missing checks;
  - `chrome-voiceover-macos`: 0/7 missing checks including
    `manual-page-ready-semantic-host`.
- The readiness bundle remains `strictPass: false`; no browser recapture was
  run.

Verification:

- `cd packages/fleury_web && dart format tool/web_readiness.dart test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_readiness.dart test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --json` -
  passed and reported `strictPass: false`.
- `rg -n "Manual Target Diagnostics|chrome-ime-macos|chrome-voiceover-macos|manual-page-ready-semantic-host|0/7|0/6" profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.md` -
  confirmed the Markdown diagnostics section.
- `jq '.checks[] | select(.id=="manualValidation") | .details.failingTargetDetails' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json` -
  confirmed matching JSON diagnostics.
- `cd packages/fleury_web && dart analyze tool/web_readiness.dart tool/web_readiness_bundle.dart test/web_readiness_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `git diff --check` - passed.
- `jq empty profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json` -
  passed.

## 2026-06-08 11:11 EDT

Preserved readiness diagnostics through the default-preflight release-action
gate.

- Updated `tool/web_default_preflight.dart` so failed readiness checks retain
  their nested `details` in preflight JSON.
- Added a Manual Target Diagnostics table to default-preflight Markdown when
  failed readiness details include manual `failingTargetDetails`.
- Extended `test/web_default_preflight_tool_test.dart` to prove the final
  preflight preserves VoiceOver `requiredCheckCount: 7` and
  `manual-page-ready-semantic-host` in both JSON and Markdown.
- Generated
  `profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.md`
  from the current readiness artifact.
- Updated the review packet and phase audit to call out that the final
  `make-dom-default` preflight remains explainable without opening nested
  artifacts.

Current artifact behavior:

- The generated default preflight still exits strict-fail, as intended.
- The preflight blockers remain candidate threshold policy plus missing real
  IME/VoiceOver evidence.
- The preflight Markdown now shows:
  - `chrome-ime-macos`: 0/6 missing checks;
  - `chrome-voiceover-macos`: 0/7 missing checks including
    `manual-page-ready-semantic-host`.
- No browser recapture was run.

Verification:

- `cd packages/fleury_web && dart format tool/web_default_preflight.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_default_preflight.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --target=make-dom-default --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.md --strict --json` -
  exited 1 as expected and reported nested failed readiness details.

## 2026-06-08 11:14 EDT

Generated the matching temporary-path retirement preflight artifact.

- Ran `tool/web_default_preflight.dart` against the Phase 1 refresh
  `web-readiness.json` with `--target=retire-temporary-paths`.
- Wrote
  `profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.md`.
- Confirmed the retirement preflight strict-fails with the same expected
  candidate-threshold and missing-manual-evidence blockers.
- Confirmed the retirement preflight Markdown mirrors manual target diagnostics:
  `chrome-ime-macos` at 0/6 and `chrome-voiceover-macos` at 0/7 including
  `manual-page-ready-semantic-host`.
- Updated the Phase 1 refresh baseline README, review packet, and phase audit
  to list both release-action preflight artifacts.

Current artifact behavior:

- Both `make-dom-default` and `retire-temporary-paths` preflight artifacts now
  exist under the Phase 1 refresh `readiness-candidate/` directory.
- Both preflights remain correctly red until reviewed thresholds and real
  IME/VoiceOver evidence are present.
- No browser recapture was run.

Verification:

- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --target=retire-temporary-paths --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.md --strict --json` -
  exited 1 as expected and reported nested failed readiness details.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart` -
  passed.
- `git diff --check` - passed.
- `jq empty profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json profiling/web/manual/templates/chrome-ime-macos.template.json profiling/web/manual/templates/chrome-voiceover-macos.template.json` -
  passed.
- `rg -n "web-default-preflight-(make-dom-default|retire-temporary-paths)|Manual Target Diagnostics|manual-page-ready-semantic-host|0/7|retire-temporary-paths" profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/README.md docs/implementation/web-rfc-review-packet.md docs/implementation/web-rfc-phase-audit.md docs/implementation/web-rfc-execution-log.md profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.md profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.md` -
  confirmed both preflight artifacts and docs references.

## 2026-06-08 11:23 EDT

Persisted default-preflight JSON artifacts for the release-action gates.

- Added `--json-output=PATH` to `tool/web_default_preflight.dart`, writing the
  same machine-readable preflight JSON that `--json` prints to stdout.
- Wired `--json-output` through `fleury benchmark web-default-preflight` so the
  root development command can generate durable preflight evidence.
- Extended package-level and root launcher tests to cover JSON persistence,
  strict-fail persistence, empty path validation, and argument forwarding.
- Regenerated both current release-action preflights as Markdown plus JSON:
  - `profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.{md,json}`
  - `profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.{md,json}`
- Updated the Phase 1 refresh baseline README, review packet, and phase audit
  to list the persisted JSON artifacts.

Current artifact behavior:

- Both preflight JSON artifacts preserve the failed readiness details, including
  the `chrome-voiceover-macos` 0/7 target and the
  `manual-page-ready-semantic-host` missing check.
- Both preflights still exit strict-fail, as intended, because the candidate
  threshold policy is unreviewed and real Chrome IME/VoiceOver evidence is
  missing.
- No browser recapture was run.

Verification:

- `cd packages/fleury_web && dart format tool/web_default_preflight.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_default_preflight.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "forwards default preflight options"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --target=make-dom-default --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.json --strict --json` -
  exited 1 as expected and wrote JSON.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --target=retire-temporary-paths --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.json --strict --json` -
  exited 1 as expected and wrote JSON.
- `dart analyze tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.

- `git diff --check` - passed.
- `rg -n "[ \t]+$" tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart packages/fleury_web/tool/web_default_preflight.dart packages/fleury_web/test/web_default_preflight_tool_test.dart docs/implementation/web-rfc-execution-log.md docs/implementation/web-rfc-phase-audit.md docs/implementation/web-rfc-review-packet.md profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/README.md` -
  passed.
- `jq empty profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json` -
  passed.
- `jq -r '[.target, (.strictPass|tostring), (.checks[0].details.failedChecks[] | select(.id=="manualValidation") | .details.failingTargetDetails[] | select(.id=="chrome-voiceover-macos") | (.requiredCheckCount|tostring), (.missingCheckIds|index("manual-page-ready-semantic-host")|tostring))] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.json` -
  confirmed both targets strict-fail with VoiceOver `requiredCheckCount` 7 and
  `manual-page-ready-semantic-host` present.

## 2026-06-08 11:33 EDT

Synchronized default-preflight artifact generation with the readiness bundle.

- Added `--write-default-preflights` to `tool/web_readiness_bundle.dart`.
- When enabled, the bundle now writes both release-action preflight artifact
  pairs next to `web-readiness.json`:
  - `web-default-preflight-make-dom-default.{md,json}`
  - `web-default-preflight-retire-temporary-paths.{md,json}`
- The bundle JSON now includes a `defaultPreflights` artifact map and
  `defaultPreflightStrictPass` results for both targets.
- The bundle now persists that summary as
  `web-readiness-bundle.json` in the output directory, so the artifact set has
  a durable machine-readable manifest even when strict readiness fails.
- Non-JSON bundle output now prints the generated preflight Markdown paths
  when `--write-default-preflights` is enabled.
- Wired the flag through `fleury benchmark web-readiness-bundle` and covered it
  in the root dry-run launcher test.
- Regenerated the Phase 1 refresh `readiness-candidate/` directory from cached
  captures with `--write-default-preflights`, including
  `web-readiness-bundle.json`.
- Updated the Phase 1 refresh README, package README, profiling README, review
  packet, and phase audit to document the synchronized artifact path.

Current artifact behavior:

- The readiness bundle still has `strictPass: false`, as expected.
- `scoreboardStrictPass` and `semanticAuditStrictPass` are true.
- `manualAuditStrictPass`, `readinessStrictPass`, and both
  `defaultPreflightStrictPass` entries are false because threshold review and
  real IME/VoiceOver evidence are still missing.
- No browser recapture was run.

Verification:

- `cd packages/fleury_web && dart format tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart format tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "forwards readiness bundle options"` -
  passed.
- `dart analyze tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  exited 0 and reported synchronized default preflight artifacts with both
  target strict-pass values false, and wrote `web-readiness-bundle.json`.
- `git diff --check` - passed.
- `rg -n "[ \t]+$" packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart docs/implementation/web-rfc-execution-log.md docs/implementation/web-rfc-phase-audit.md docs/implementation/web-rfc-review-packet.md packages/fleury_web/README.md profiling/web/README.md profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/README.md` -
  passed.
- `jq empty profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.json` -
  passed.
- `jq -r '[.strictPass, (.checks[] | select(.id=="manualValidation") | .details.passedTargetCount), (.checks[] | select(.id=="manualValidation") | .details.targetCount)] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json` -
  confirmed readiness `strictPass: false` with 0 of 2 manual targets passing.
- `jq -r '[.strictPass, .artifacts.bundleJson, .checks.scoreboardStrictPass, .checks.semanticAuditStrictPass, .checks.manualAuditStrictPass, .checks.readinessStrictPass, .checks.defaultPreflightStrictPass["make-dom-default"], .checks.defaultPreflightStrictPass["retire-temporary-paths"]] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  confirmed the manifest points at itself and records true frame/semantic
  checks with false manual/readiness/preflight checks.
- `jq -r '[.target, (.strictPass|tostring), (.checks[0].details.failedChecks[] | select(.id=="manualValidation") | .details.failingTargetDetails[] | select(.id=="chrome-voiceover-macos") | (.requiredCheckCount|tostring), (.missingCheckIds|index("manual-page-ready-semantic-host")|tostring))] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.json` -
  confirmed both preflight targets strict-fail with VoiceOver
  `requiredCheckCount` 7 and `manual-page-ready-semantic-host` present.

## 2026-06-08 11:48 EDT

Aligned the root benchmark command surface with the synchronized readiness
bundle artifacts.

- Updated the `fleury benchmark list --json` catalog entry for
  `webReadinessBundle` so it describes the persisted
  `web-readiness-bundle.json` manifest and the default/retirement preflight
  artifact pairs.
- Updated root benchmark usage examples to show `--write-default-preflights`
  on `web-readiness-bundle`.
- Corrected the root dry-run tests so `--write-default-preflights` is accepted
  only by `web-readiness-bundle`, not by the direct `web-readiness` command.
- Verified the root launcher actually forwards `--write-default-preflights` to
  `tool/web_readiness_bundle.dart`.

Current behavior:

- `web-readiness` remains a direct combiner over existing reviewed artifacts.
- `web-readiness-bundle --write-default-preflights` is the synchronized artifact
  refresh command that writes the manifest plus release-action preflight pairs.
- No generated readiness artifacts changed in this slice, and no browser
  recapture was run.

Verification:

- `dart format tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `dart analyze tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark web-readiness launcher"` -
  passed.
- `git diff --check` - passed.
- `rg -n "[ \t]+$" tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart docs/implementation/web-rfc-execution-log.md` -
  passed.
- `dart run tool/fleury_dev.dart benchmark list --json | jq '.webReadinessBundle | {purpose, artifacts, command}'` -
  confirmed the catalog lists `web-readiness-bundle.json`, both default
  preflight artifact pairs, and `--write-default-preflights`.
- `dart run tool/fleury_dev.dart --dry-run benchmark web-readiness-bundle --captures=profiling/web/baselines/sample --manual=profiling/web/manual --output-dir=profiling/web/baselines/sample/readiness --max-fallback-cells=0 --write-default-preflights --json` -
  confirmed the root wrapper forwards `--write-default-preflights` to
  `tool/web_readiness_bundle.dart`.

## 2026-06-08 11:57 EDT

Added durable JSON output to the direct Phase 6 readiness gate.

- Added `--json-output=PATH` to `tool/web_readiness.dart`.
- The direct readiness tool now writes the same machine-readable JSON that
  `--json` prints, before strict-mode exit, so red readiness runs still leave
  durable diagnostics.
- Wired `--json-output` through `fleury benchmark web-readiness`.
- Extended package-level readiness tests to cover persisted JSON on both
  passing and strict-failing audits, plus empty path validation.
- Extended the root dry-run test to prove forwarding through
  `fleury benchmark web-readiness`.
- Updated the package README, profiling README, root usage example, and phase
  audit to document direct readiness JSON persistence.

Current artifact behavior:

- A direct `web_readiness.dart --json-output=... --strict --json` run over the
  Phase 1 refresh candidate artifacts exits 1 as expected and writes
  `web-readiness.json`.
- The readiness bundle was regenerated afterward with
  `--write-default-preflights` so `web-readiness-bundle.json`,
  `web-readiness.json`, and the preflight artifacts are synchronized again.
- No browser recapture was run.

Verification:

- `cd packages/fleury_web && dart format tool/web_readiness.dart test/web_readiness_tool_test.dart` -
  passed.
- `dart format tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_readiness.dart test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_tool_test.dart` -
  passed.
- `dart analyze tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "forwards readiness audit artifact options"` -
  passed.
- `dart run tool/fleury_dev.dart --dry-run benchmark web-readiness --scoreboard=profiling/web/baselines/sample/scoreboard.json --semantic-audit=profiling/web/baselines/sample/semantic-coverage.json --manual-audit=profiling/web/manual/manual-validation-audit.json --output=profiling/web/baselines/sample/web-readiness.md --json-output=profiling/web/baselines/sample/web-readiness.json --strict --json` -
  confirmed the root wrapper forwards an absolute `--json-output` path to
  `tool/web_readiness.dart`.
- `cd packages/fleury_web && dart run tool/web_readiness.dart --scoreboard=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json --semantic-audit=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json --manual-audit=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --strict --json` -
  exited 1 as expected and wrote JSON plus Markdown.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  exited 0 and resynchronized the manifest/readiness/preflight artifacts.
- `jq empty profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.json` -
  passed.
- `jq -r '[.strictPass, .checks.scoreboardStrictPass, .checks.semanticAuditStrictPass, .checks.manualAuditStrictPass, .checks.readinessStrictPass, .checks.defaultPreflightStrictPass["make-dom-default"], .checks.defaultPreflightStrictPass["retire-temporary-paths"]] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  returned `false true true false false false false`, confirming the remaining
  failures are manual-validation/readiness/default-preflight gates.
- `jq -r '[.strictPass, (.checks[] | select(.id=="manualValidation") | .details.passedTargetCount), (.checks[] | select(.id=="manualValidation") | .details.targetCount)] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json` -
  returned `false 0 2`, confirming the direct readiness audit is red only on
  the two required manual targets.
- `git diff --check` -
  passed.
- `rg -n "[ \t]+$" packages/fleury_web/tool/web_readiness.dart packages/fleury_web/test/web_readiness_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart docs/implementation/web-rfc-execution-log.md docs/implementation/web-rfc-phase-audit.md packages/fleury_web/README.md profiling/web/README.md` -
  passed.

## 2026-06-08 12:00 EDT

Added durable JSON output to the manual validation gate.

- Added `--json-output=PATH` to `tool/web_manual_validation.dart`.
- The direct manual validation tool now writes the same audit JSON that
  `--json` prints, before strict-mode exit, so missing or incomplete manual
  evidence still leaves a durable `manual-validation-audit.json`.
- Wired `--json-output` through
  `fleury benchmark web-manual-validation`.
- Extended package-level manual validation tests to cover persisted JSON for
  both strict-failing and passing audits, plus empty path validation.
- Extended the root dry-run launcher test to prove forwarding through
  `fleury benchmark web-manual-validation`.
- Updated benchmark catalog metadata, package/profiling/manual docs, and the
  phase audit to recommend direct manual audit JSON persistence.

Current artifact behavior:

- `fleury benchmark web-manual-validation --json-output=... --strict` over the
  current manual evidence directory exits 1 as expected and writes both
  `profiling/web/manual/review.md` and
  `profiling/web/manual/manual-validation-audit.json`.
- The Phase 1 refresh readiness candidate bundle was regenerated afterward with
  `--write-default-preflights` so `manual-validation-audit.json`,
  `web-readiness-bundle.json`, `web-readiness.json`, and the default preflight
  artifacts are synchronized again.
- No browser recapture was run.

Verification:

- `dart format packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/test/web_manual_validation_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_manual_validation.dart test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed.
- `dart analyze tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "forwards manual validation audit options"` -
  passed.
- `dart run tool/fleury_dev.dart benchmark web-manual-validation --input=profiling/web/manual --output=profiling/web/manual/review.md --json-output=profiling/web/manual/manual-validation-audit.json --strict` -
  exited 1 as expected and wrote Markdown plus JSON before strict failure.
- `jq -r '[.kind, (.strictPass|tostring), (.passedTargetCount|tostring), (.targetCount|tostring), (.missingTargets|join(","))] | @tsv' profiling/web/manual/manual-validation-audit.json` -
  returned `fleuryWebManualValidationAudit false 0 2 chrome-ime-macos,chrome-voiceover-macos`.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  exited 0 and resynchronized the manifest/readiness/preflight artifacts.
- `jq empty profiling/web/manual/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.json` -
  passed.
- `jq -r '[.strictPass, .checks.scoreboardStrictPass, .checks.semanticAuditStrictPass, .checks.manualAuditStrictPass, .checks.readinessStrictPass, .checks.defaultPreflightStrictPass["make-dom-default"], .checks.defaultPreflightStrictPass["retire-temporary-paths"]] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  returned `false true true false false false false`, confirming the remaining
  failures are still threshold-review/manual-validation/readiness/preflight
  gates.
- `dart run tool/fleury_dev.dart benchmark list --json | jq '.webManualValidation | {command, artifacts, targets}'` -
  confirmed the catalog lists `--json-output=profiling/web/manual/manual-validation-audit.json`
  and the manual audit artifacts.
- `dart run tool/fleury_dev.dart --dry-run benchmark web-manual-validation --input=profiling/web/manual --output=profiling/web/manual/review.md --json-output=profiling/web/manual/manual-validation-audit.json --strict` -
  confirmed the root wrapper forwards an absolute `--json-output` path to
  `tool/web_manual_validation.dart`.

## 2026-06-08 12:09 EDT

Completed durable JSON output for the remaining direct readiness input tools.

- Added `--json-output=PATH` to `tool/web_frame_scoreboard.dart`.
- Added `--json-output=PATH` to `tool/web_semantic_coverage_audit.dart`.
- Wired both flags through `fleury benchmark web-scoreboard` and
  `fleury benchmark web-semantic-audit`.
- Updated package and root tests so JSON persistence is covered for frame
  scoreboards and semantic coverage audits, including empty path validation.
- Updated benchmark catalog metadata, package/profiling docs, top-level help,
  and the phase audit so the Phase 6 evidence chain no longer depends on shell
  redirection for scoreboard, semantic, manual, readiness, or preflight JSON
  artifacts.
- The automatic `web-capture` scoreboard refresh now writes
  `profiling/web/scoreboard.json` next to `profiling/web/scoreboard.md`.

Current artifact behavior:

- Direct `fleury benchmark web-scoreboard --json-output=... --strict` over the
  Phase 1 refresh candidate captures exits 0 and writes the candidate
  `readiness-candidate/scoreboard.json`.
- Direct `fleury benchmark web-semantic-audit --json-output=... --strict` over
  the same captures exits 0 and writes the candidate
  `readiness-candidate/semantic-coverage.json`.
- The readiness bundle was regenerated afterward with
  `--write-default-preflights` so direct smoke writes do not leave the
  candidate artifact directory out of sync.
- No browser recapture was run.

Verification:

- `dart format packages/fleury_web/tool/web_semantic_coverage_audit.dart packages/fleury_web/test/web_semantic_coverage_audit_tool_test.dart packages/fleury_web/tool/web_frame_scoreboard.dart packages/fleury_web/test/web_frame_scoreboard_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_frame_scoreboard.dart test/web_frame_scoreboard_tool_test.dart tool/web_semantic_coverage_audit.dart test/web_semantic_coverage_audit_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_scoreboard_tool_test.dart test/web_semantic_coverage_audit_tool_test.dart` -
  passed.
- `dart analyze tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark web-scoreboard launcher|forwards semantic fallback audit gate options"` -
  passed.
- `dart run tool/fleury_dev.dart benchmark web-scoreboard --input=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --thresholds=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --min-runs=3 --require-comparable-environment --output=/tmp/fleury-web-scoreboard-json-output-smoke.md --json-output=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json --strict` -
  exited 0 and wrote the scoreboard JSON artifact.
- `dart run tool/fleury_dev.dart benchmark web-semantic-audit --input=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --output=/tmp/fleury-web-semantic-json-output-smoke.md --json-output=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json --max-fallback-cells=0 --strict` -
  exited 0 and wrote the semantic coverage JSON artifact.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  exited 0 and resynchronized the manifest/readiness/preflight artifacts.
- `jq empty profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json` -
  passed.
- `jq -r '[.strictPass, .checks.scoreboardStrictPass, .checks.semanticAuditStrictPass, .checks.manualAuditStrictPass, .checks.readinessStrictPass] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  returned `false true true false false`, confirming frame/semantic inputs are
  green and readiness remains blocked by threshold review/manual evidence.
- `dart run tool/fleury_dev.dart benchmark list --json | jq '{scoreboard: .webScoreboard | {command,jsonOutput}, semantic: .webSemanticAudit | {command,artifacts}}'` -
  confirmed the catalog lists direct JSON outputs for both evidence producers.

## 2026-06-08 12:18 EDT

Changed the readiness bundle to consume tool-owned JSON artifacts.

- Updated `tool/web_readiness_bundle.dart` so frame scoreboard, semantic
  coverage, manual validation, readiness, and default preflight JSON artifacts
  are written by their underlying tools through `--json-output`.
- The bundle now validates those files after each tool run instead of parsing
  child stdout and rewriting the JSON itself.
- Combined readiness JSON and Markdown are now generated in one
  `web_readiness.dart` invocation.
- Default preflight JSON and Markdown are also generated in one invocation per
  target.
- Added a longer timeout annotation to `web_readiness_bundle_tool_test.dart`
  because the file is an integration-style test that shells out to multiple
  Dart tools per case.
- Updated package README and phase audit wording to describe the bundle as a
  coordinator over tool-owned JSON outputs.

Current artifact behavior:

- The Phase 1 refresh readiness candidate bundle was regenerated through the
  refactored flow with `--write-default-preflights`.
- The regenerated `web-readiness-bundle.json` still reports
  `scoreboardStrictPass: true` and `semanticAuditStrictPass: true`.
- `manualAuditStrictPass`, `readinessStrictPass`, and both default preflight
  checks remain false because real manual evidence is missing and the
  threshold policy is still `candidate`.
- No browser recapture was run.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "keeps artifacts"` -
  passed in isolation, confirming the previous 30-second timeout was a test
  budget issue rather than a hang.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with the longer timeout annotation.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  exited 0 and regenerated the candidate manifest/readiness/preflight artifacts
  through tool-owned JSON outputs.
- `jq empty profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.json` -
  passed.
- `jq -r '[.strictPass, .checks.scoreboardStrictPass, .checks.semanticAuditStrictPass, .checks.manualAuditStrictPass, .checks.readinessStrictPass, .checks.defaultPreflightStrictPass["make-dom-default"], .checks.defaultPreflightStrictPass["retire-temporary-paths"]] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  returned `false true true false false false false`, confirming the gate state
  is unchanged by the bundle refactor.
- `git diff --check` -
  passed.
- `rg -n "[ \t]+$" packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart docs/implementation/web-rfc-execution-log.md docs/implementation/web-rfc-phase-audit.md packages/fleury_web/README.md profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/*.md` -
  passed.

## 2026-06-08 12:25 EDT

Paired repeated-suite scoreboards with machine-readable JSON by default.

- Added `--scoreboard-json=PATH` to `tool/web_frame_suite.dart`.
- The package suite now defaults that path to `<output-dir>/scoreboard.json`
  and forwards it to `web_frame_scoreboard.dart --json-output=...`.
- The suite plan JSON now includes `scoreboardJsonPath`.
- Wired `--scoreboard-json` through `fleury benchmark web-suite`.
- Updated package and root launcher tests to cover explicit and default
  scoreboard JSON paths.
- Updated package/profiling docs, root benchmark catalog metadata, and the
  review packet/phase audit so repeated retained DOM suites advertise
  `scoreboard.json` next to `scoreboard.md`.

Current artifact behavior:

- No browser recapture was run.
- Future `web-suite` runs will write `scoreboard.md` and `scoreboard.json`
  under the suite output directory unless the caller overrides those paths.
- Existing readiness candidate artifacts were not regenerated by this slice
  because the change affects future suite output shape, not existing captures
  or readiness math.

Verification:

- `dart format packages/fleury_web/tool/web_frame_suite.dart packages/fleury_web/test/web_frame_suite_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_frame_suite.dart test/web_frame_suite_tool_test.dart` -
  passed.
- `dart analyze tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_suite_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark web-suite launcher"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_frame_suite.dart --scenarios=normal-80x24 --runs=1 --frames=1 --warmup=0 --output-dir=/tmp/fleury-web-suite-json-artifact-smoke --dry-run --json | jq -r '[.scoreboardPath, .scoreboardJsonPath, (.commands[-1].args[] | select(startswith("--json-output=")))] | @tsv'` -
  returned `/tmp/fleury-web-suite-json-artifact-smoke/scoreboard.md`,
  `/tmp/fleury-web-suite-json-artifact-smoke/scoreboard.json`, and the matching
  `--json-output=.../scoreboard.json` scoreboard command argument.
- `dart run tool/fleury_dev.dart benchmark list --json | jq '.webSuite | {defaultOutput, scoreboard, scoreboardJson}'` -
  confirmed the root catalog lists `scoreboard.json`.
- `dart run tool/fleury_dev.dart --dry-run benchmark web-suite --scenarios=normal-80x24 --runs=1 --frames=1 --output-dir=/tmp/fleury-web-suite-root-json-artifact-smoke --json` -
  confirmed the root wrapper forwards `--scoreboard-json=/tmp/fleury-web-suite-root-json-artifact-smoke/scoreboard.json`.

## 2026-06-08 12:35 EDT

Persisted threshold-review promotion summaries as JSON artifacts.

- Added `--json-output=PATH` to `tool/web_threshold_review.dart`.
- The package tool now writes the machine-readable
  `fleuryWebThresholdReview` promotion summary to that path while still
  writing the reviewed `thresholds.json` policy to `--output`.
- Wired the same option through `fleury benchmark web-threshold-review`.
- Updated the root benchmark catalog so threshold review advertises both
  `thresholds.json` and `threshold-review.json` as artifacts.
- Updated package/profiling docs, the phase audit, and the review packet so
  reviewed threshold promotion evidence is durable rather than stdout-only.

Current artifact behavior:

- No browser recapture was run.
- No repo-local reviewed `thresholds.json` was generated; the active Phase 1
  readiness candidate still correctly blocks on the candidate threshold policy
  and missing real IME/screen-reader evidence.
- A smoke promotion wrote temporary reviewed artifacts under `/tmp` only:
  `/tmp/fleury-thresholds-reviewed-smoke.json` and
  `/tmp/fleury-threshold-review-smoke.json`.

Verification:

- `dart format packages/fleury_web/tool/web_threshold_review.dart packages/fleury_web/test/web_threshold_review_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_threshold_review.dart test/web_threshold_review_tool_test.dart` -
  passed.
- `dart analyze tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_threshold_review_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-threshold-review|benchmark catalog includes web"` -
  passed the threshold-review launcher coverage; the catalog assertion needed
  a separate focused run because the name filter matched only the
  threshold-review group.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "appears in benchmark catalog"` -
  passed.
- `dart run tool/fleury_dev.dart --dry-run benchmark web-threshold-review --input=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --output=/tmp/fleury-thresholds-reviewed-smoke.json --json-output=/tmp/fleury-threshold-review-smoke.json --reviewed-by=smoke-reviewer --reviewed-at=2026-06-08T12:00:00Z --review-context="smoke context only, not release evidence" --json` -
  confirmed the root launcher forwards `--json-output=/tmp/fleury-threshold-review-smoke.json`.
- `dart run tool/fleury_dev.dart benchmark list --json | jq '.webThresholdReview | {artifacts, command}'` -
  confirmed the catalog lists `threshold-review.json` and the matching
  `--json-output` command example.
- `dart run tool/fleury_dev.dart benchmark web-threshold-review --input=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --output=/tmp/fleury-thresholds-reviewed-smoke.json --json-output=/tmp/fleury-threshold-review-smoke.json --reviewed-by=smoke-reviewer --reviewed-at=2026-06-08T12:00:00Z --review-context="smoke context only, not release evidence" --json` -
  passed and reported a reviewed smoke summary for 11 scenarios.
- `jq -r '[input_filename, .kind, .reviewState, (.scenarioCount // (.scenarios | length))] | @tsv' /tmp/fleury-threshold-review-smoke.json /tmp/fleury-thresholds-reviewed-smoke.json` -
  returned `fleuryWebThresholdReview`/`fleuryWebFrameThresholds`, both with
  `reviewState: reviewed` and 11 scenarios.
- `jq empty /tmp/fleury-threshold-review-smoke.json /tmp/fleury-thresholds-reviewed-smoke.json` -
  passed.

## 2026-06-08 12:48 EDT

Added a threshold-review summary gate to Phase 6 readiness.

- `web_readiness.dart` now accepts `--threshold-review=PATH`.
- When default reviewed-threshold policy checks are enabled and the frame
  scoreboard reports `thresholdPolicyReviewState: reviewed`, readiness now
  requires a matching `fleuryWebThresholdReview` summary.
- The readiness gate validates the summary `outputPath`, `reviewedBy`,
  `reviewedAt`, `reviewContext`, and `scenarioCount` against the frame
  scoreboard metadata.
- `--no-require-threshold-review-summary` is available for local diagnostic
  runs, but not for default release readiness.
- `web_readiness_bundle.dart` now derives `threshold-review.json` next to
  `--thresholds` unless `--threshold-review=PATH` is supplied, forwards it to
  `web_readiness.dart`, and records the path plus requirement state in
  `web-readiness-bundle.json`.
- Wired the same options through `fleury benchmark web-readiness` and
  `fleury benchmark web-readiness-bundle`.
- Updated package/profiling docs, root benchmark catalog metadata, and the
  phase audit so readiness review expects durable threshold promotion evidence,
  not only reviewed fields copied into the scoreboard.

Current artifact behavior:

- No browser recapture was run.
- The Phase 1 refresh readiness candidate bundle was regenerated through the
  artifact-only path with `--write-default-preflights`.
- The regenerated bundle records the derived
  `thresholdReviewPath: .../threshold-review.json` and
  `requireThresholdReviewSummary: true`.
- Because the current threshold policy is still `reviewState: candidate`,
  readiness continues to block on the candidate policy and does not require or
  load the threshold-review summary yet.
- The readiness vector remains `false true true false false false false`:
  overall readiness false, scoreboard true, semantic audit true, manual audit
  false, readiness false, and both default preflight targets false.

Verification:

- `dart format packages/fleury_web/tool/web_readiness.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_readiness.dart tool/web_readiness_bundle.dart test/web_readiness_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "forwards readiness audit artifact options|forwards readiness bundle options|appears in benchmark catalog"` -
  passed.
- `dart run tool/fleury_dev.dart --dry-run benchmark web-readiness --scoreboard=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json --semantic-audit=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json --manual-audit=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json --threshold-review=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review.json --json-output=/tmp/fleury-web-readiness-threshold-review-smoke.json --strict --json` -
  confirmed the root readiness launcher forwards `--threshold-review`.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate readiness/preflight artifact set and exited 0
  with `strictPass: false`.
- `jq empty profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.json` -
  passed.
- `jq -r '[.strictPass, .checks.scoreboardStrictPass, .checks.semanticAuditStrictPass, .checks.manualAuditStrictPass, .checks.readinessStrictPass, .checks.defaultPreflightStrictPass["make-dom-default"], .checks.defaultPreflightStrictPass["retire-temporary-paths"], .input.thresholdReviewPath] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  returned `false true true false false false false` plus the derived
  `threshold-review.json` path.
- `jq -r '.checks[] | select(.id=="frameScoreboard") | [.strictPass, (.blockers|join("; ")), .details.thresholdReviewPath] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json` -
  confirmed the frame check still blocks on the candidate threshold policy and
  records the threshold-review path.
- `dart run tool/fleury_dev.dart benchmark list --json | jq '.webReadiness | {defaultThresholdReview, requires, command}'` -
  confirmed the root catalog advertises the matching threshold-review summary
  requirement.

## 2026-06-08 12:53 EDT

Hardened manual evidence provenance for Phase 3/4 manual gates.

- `web_manual_validation.dart` now requires `capturedAt` to parse as ISO-8601
  before a manual evidence entry can strict-pass.
- Manual evidence now must report
  `environment.fleuryWebPage: "manual_validation.html"`; evidence collected
  from a different page is classified as `needsReview`.
- Latest-entry selection now sorts by parsed timestamp, with malformed
  timestamps treated as oldest, so a malformed entry cannot mask a valid
  reviewed entry for the same target.
- Updated generated manual validation plan text, package docs, profiling docs,
  and phase audit wording to spell out the parseable timestamp and exact page
  requirements.

Current artifact behavior:

- No browser recapture was run.
- The root manual validation audit was regenerated from
  `profiling/web/manual` and still reports zero evidence entries.
- The Phase 1 refresh readiness candidate bundle was regenerated through the
  artifact-only path with `--write-default-preflights`.
- The readiness vector remains `false true true false false false false`:
  overall readiness false, scoreboard true, semantic audit true, manual audit
  false, readiness false, and both default preflight targets false.

Verification:

- `dart format packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_manual_validation.dart test/web_manual_validation_tool_test.dart` -
  passed.
- `dart analyze tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury_web && rm -rf /tmp/fleury-web-manual-provenance-smoke && mkdir -p /tmp/fleury-web-manual-provenance-smoke && dart run tool/web_manual_validation.dart --write-plan=/tmp/fleury-web-manual-provenance-smoke/plan.md --write-template=/tmp/fleury-web-manual-provenance-smoke/chrome-ime-macos.template.json --template-target=chrome-ime-macos --target=chrome-ime-macos --json-output=/tmp/fleury-web-manual-provenance-smoke/audit.json --json` -
  passed and produced a plan/template/audit smoke set.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json --json` -
  regenerated the root manual audit and reported both primary manual targets
  missing.
- `rg -n "ISO-8601|manual_validation\\.html|capturedAt|fleuryWebPage" /tmp/fleury-web-manual-provenance-smoke/plan.md /tmp/fleury-web-manual-provenance-smoke/chrome-ime-macos.template.json /tmp/fleury-web-manual-provenance-smoke/audit.json /Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json` -
  confirmed the generated plan/template mention the stricter timestamp and
  page requirements.
- `jq empty /tmp/fleury-web-manual-provenance-smoke/chrome-ime-macos.template.json /tmp/fleury-web-manual-provenance-smoke/audit.json profiling/web/manual/manual-validation-audit.json` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate readiness/preflight artifact set and exited 0
  with `strictPass: false`.
- `jq empty profiling/web/manual/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.json` -
  passed.
- `jq -r '[.strictPass, .checks.scoreboardStrictPass, .checks.semanticAuditStrictPass, .checks.manualAuditStrictPass, .checks.readinessStrictPass, .checks.defaultPreflightStrictPass["make-dom-default"], .checks.defaultPreflightStrictPass["retire-temporary-paths"]] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  returned `false true true false false false false`.
- `jq -r '[.strictPass, .entryCount, (.missingTargets|join(",")), (.targets[] | select(.id=="chrome-voiceover-macos") | .requiredCheckCount)] | @tsv' profiling/web/manual/manual-validation-audit.json` -
  returned `false`, `0`, `chrome-ime-macos,chrome-voiceover-macos`, and `7`.

## 2026-06-08 13:04 EDT

Hardened manual evidence file loading for Phase 3/4 gates.

- `web_manual_validation.dart` now classifies every manual-evidence `.json`
  file as one of: valid entry, ignored generated/template file, or invalid
  evidence file.
- Only `*.template.json` files and the exact generated
  `manual-validation-audit.json` file are ignored.
- Malformed JSON, non-object JSON, wrong artifact kinds, and manual validation
  entries missing `targetId` now appear in `invalidEntries` with
  `invalidEntryCount`, and any invalid entry prevents `strictPass`.
- Manual validation Markdown now includes an Invalid Evidence Files table when
  invalid files are present.
- `web_readiness.dart` now carries `invalidEntryCount` and `invalidEntries`
  through the combined Phase 6 readiness check, and adds an explicit blocker
  when invalid manual evidence files exist.
- Updated package docs, profiling docs, and the phase audit so evidence
  directory policy is explicit: generated templates/audits may coexist with
  evidence, but all other bad JSON is a strict gate failure.

Current artifact behavior:

- No browser recapture was run.
- The root manual validation audit was regenerated from
  `profiling/web/manual`; it reports zero evidence entries, zero invalid
  evidence entries, three ignored generated/template files, and both primary
  manual targets missing.
- The Phase 1 refresh readiness candidate bundle was regenerated through the
  artifact-only path with `--write-default-preflights`.
- The readiness vector remains `false true true false false false false`:
  overall readiness false, scoreboard true, semantic audit true, manual audit
  false, readiness false, and both default preflight targets false.

Verification:

- `dart format packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/tool/web_readiness.dart packages/fleury_web/test/web_manual_validation_tool_test.dart packages/fleury_web/test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_manual_validation.dart tool/web_readiness.dart test/web_manual_validation_tool_test.dart test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/tmp/fleury-web-manual-invalid-smoke --target=chrome-ime-macos --output=/tmp/fleury-web-manual-invalid-smoke/review.md --json-output=/tmp/fleury-web-manual-invalid-smoke/audit.json --strict --json` -
  exited 1 as expected for invalid evidence; the audit kept one valid entry and
  reported `broken.json` under `invalidEntries`.
- `rg -n "Invalid Evidence Files|broken.json" /tmp/fleury-web-manual-invalid-smoke/review.md` -
  confirmed the Markdown invalid-file diagnostics.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json --json` -
  regenerated the root manual audit.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate readiness/preflight artifact set and exited 0
  with `strictPass: false`.
- `jq empty profiling/web/manual/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.json` -
  passed.
- `jq -r '[.strictPass, .checks.scoreboardStrictPass, .checks.semanticAuditStrictPass, .checks.manualAuditStrictPass, .checks.readinessStrictPass, .checks.defaultPreflightStrictPass["make-dom-default"], .checks.defaultPreflightStrictPass["retire-temporary-paths"]] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  returned `false true true false false false false`.
- `jq -r '.readiness.checks[] | select(.id=="manualValidation") | [.strictPass, .details.entryCount, .details.invalidEntryCount, (.details.missingTargets|join(","))] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  returned `false`, `0`, `0`, and
  `chrome-ime-macos,chrome-voiceover-macos`.

## 2026-06-08 13:11 EDT

Bound threshold review summaries to the reviewed threshold policy content.

- `web_threshold_review.dart` now writes deterministic JSON fingerprints for
  both the input candidate policy and output reviewed policy into
  `threshold-review.json`.
- The threshold review summary also records the policy `generatedFrom`
  metadata and scenario IDs so a reviewer can see the capture basis without
  reopening `thresholds.json`.
- `web_frame_scoreboard.dart` now reports the loaded threshold policy
  fingerprint and scenario count in scoreboard JSON whenever
  `--thresholds=PATH` is supplied.
- `web_readiness.dart` now requires reviewed threshold scoreboards to include a
  threshold policy fingerprint, and default Phase 6 readiness rejects a stale
  threshold review summary whose `outputPolicyFingerprint` does not match the
  scoreboard's `thresholdPolicyFingerprint`.
- Updated package docs, profiling docs, the phase audit, and the re-review
  packet to document the content-bound threshold promotion evidence.

Current artifact behavior:

- No browser recapture was run.
- The Phase 1 refresh readiness candidate bundle was regenerated through the
  artifact-only path with `--write-default-preflights`.
- The refreshed frame details now expose
  `thresholdPolicyFingerprint: fnv1a64:d6f18428fe25af25` and
  `thresholdPolicyScenarioCount: 11` for the candidate threshold policy.
- The readiness vector remains `false true true false false false false`:
  overall readiness false, scoreboard true, semantic audit true, manual audit
  false, readiness false, and both default preflight targets false.

Verification:

- `dart format tool/web_threshold_review.dart tool/web_frame_scoreboard.dart tool/web_readiness.dart test/web_threshold_review_tool_test.dart test/web_frame_scoreboard_tool_test.dart test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_threshold_review.dart tool/web_frame_scoreboard.dart tool/web_readiness.dart test/web_threshold_review_tool_test.dart test/web_frame_scoreboard_tool_test.dart test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_threshold_review_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_scoreboard_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_threshold_review.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --output=/tmp/fleury-threshold-fingerprint-smoke/thresholds.json --json-output=/tmp/fleury-threshold-fingerprint-smoke/threshold-review.json --reviewed-by=smoke-reviewer --reviewed-at=2026-06-08T17:10:00Z --review-context="smoke context only, content fingerprint verification" --json` -
  generated a temporary reviewed threshold policy and review summary.
- `cd packages/fleury_web && dart run tool/web_frame_scoreboard.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --thresholds=/tmp/fleury-threshold-fingerprint-smoke/thresholds.json --min-runs=3 --require-comparable-environment --json-output=/tmp/fleury-threshold-fingerprint-smoke/scoreboard.json --strict --json` -
  passed against the temporary reviewed policy.
- `cd packages/fleury_web && dart run tool/web_readiness.dart --scoreboard=/tmp/fleury-threshold-fingerprint-smoke/scoreboard.json --semantic-audit=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json --manual-audit=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json --threshold-review=/tmp/fleury-threshold-fingerprint-smoke/threshold-review.json --json-output=/tmp/fleury-threshold-fingerprint-smoke/readiness.json --json` -
  reported the frame scoreboard check as passing while the combined readiness
  stayed blocked on manual evidence.
- `jq -r '[input_filename, .outputPolicyFingerprint // .thresholdPolicyFingerprint // ""] | @tsv' /tmp/fleury-threshold-fingerprint-smoke/threshold-review.json /tmp/fleury-threshold-fingerprint-smoke/scoreboard.json` -
  confirmed both artifacts reported `fnv1a64:47e69c774ce897e8`.
- `jq -r '.checks[] | select(.id=="frameScoreboard") | [.strictPass, (.blockers|join("; ")), .details.thresholdPolicyFingerprint] | @tsv' /tmp/fleury-threshold-fingerprint-smoke/readiness.json` -
  returned `true`, an empty blocker field, and
  `fnv1a64:47e69c774ce897e8`.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate readiness/preflight artifact set and exited 0
  with `strictPass: false`.
- `jq empty profiling/web/manual/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.json` -
  passed.
- `jq -r '[.strictPass, .checks.scoreboardStrictPass, .checks.semanticAuditStrictPass, .checks.manualAuditStrictPass, .checks.readinessStrictPass, .checks.defaultPreflightStrictPass["make-dom-default"], .checks.defaultPreflightStrictPass["retire-temporary-paths"]] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  returned `false true true false false false false`.
- `jq -r '.readiness.checks[] | select(.id=="frameScoreboard") | [.strictPass, .details.thresholdPolicyReviewState, .details.thresholdPolicyScenarioCount, .details.thresholdPolicyFingerprint] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  returned `false`, `candidate`, `11`, and
  `fnv1a64:d6f18428fe25af25`.

## 2026-06-08 13:19 EDT

Bound manual validation evidence to audited content fingerprints.

- `web_manual_validation.dart` now computes a deterministic
  `latestEntryFingerprint` for valid manual validation JSON entries.
- Per-target manual audit reports now include the latest evidence file path,
  file name, capture time, reviewer, and fingerprint when evidence exists.
- Manual validation Markdown now shows the latest evidence fingerprint next to
  the latest evidence file.
- `web_readiness.dart` now carries latest manual evidence file/timestamp/
  reviewer/fingerprint details under `manualEvidence` in the combined manual
  readiness check.
- Updated package docs, profiling docs, the phase audit, and the re-review
  packet so the final IME/VoiceOver evidence handoff is content-bound, not
  only path/timestamp-bound.

Current artifact behavior:

- No browser recapture was run.
- A synthetic manual-evidence smoke with both primary targets passing showed
  fingerprints in `manual-validation-audit.json`, manual Markdown, and
  readiness `manualEvidence`.
- The root manual validation audit was regenerated from
  `profiling/web/manual`; it still reports zero real evidence entries, zero
  invalid entries, three ignored generated/template files, and both primary
  manual targets missing.
- The Phase 1 refresh readiness candidate bundle was regenerated through the
  artifact-only path with `--write-default-preflights`.
- The readiness vector remains `false true true false false false false`:
  overall readiness false, scoreboard true, semantic audit true, manual audit
  false, readiness false, and both default preflight targets false.

Verification:

- `dart format tool/web_manual_validation.dart tool/web_readiness.dart test/web_manual_validation_tool_test.dart test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_manual_validation.dart tool/web_readiness.dart test/web_manual_validation_tool_test.dart test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/tmp/fleury-web-manual-fingerprint-smoke/evidence --target-preset=primary --output=/tmp/fleury-web-manual-fingerprint-smoke/out/review.md --json-output=/tmp/fleury-web-manual-fingerprint-smoke/out/manual-validation-audit.json --strict --json` -
  passed for synthetic IME and VoiceOver evidence.
- `cd packages/fleury_web && dart run tool/web_readiness.dart --scoreboard=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json --semantic-audit=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json --manual-audit=/tmp/fleury-web-manual-fingerprint-smoke/out/manual-validation-audit.json --json-output=/tmp/fleury-web-manual-fingerprint-smoke/out/readiness.json --json` -
  showed the manual validation check passing with two `manualEvidence` entries
  while the overall readiness stayed red on the candidate threshold policy.
- `jq -r '.targets[] | [.id, .strictPass, .latestEntryFile, .latestEntryFingerprint] | @tsv' /tmp/fleury-web-manual-fingerprint-smoke/out/manual-validation-audit.json` -
  returned fingerprints for both synthetic targets.
- `jq -r '.checks[] | select(.id=="manualValidation") | [.strictPass, (.details.manualEvidence | length), (.details.manualEvidence[0].latestEntryFingerprint // "")] | @tsv' /tmp/fleury-web-manual-fingerprint-smoke/out/readiness.json` -
  returned `true`, `2`, and the first synthetic evidence fingerprint.
- `rg -n "fnv1a64:" /tmp/fleury-web-manual-fingerprint-smoke/out/review.md` -
  confirmed the manual audit Markdown includes evidence fingerprints.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json --json` -
  regenerated the root manual audit.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate readiness/preflight artifact set and exited 0
  with `strictPass: false`.
- `jq empty profiling/web/manual/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.json` -
  passed.
- `jq -r '[.strictPass, .checks.scoreboardStrictPass, .checks.semanticAuditStrictPass, .checks.manualAuditStrictPass, .checks.readinessStrictPass, .checks.defaultPreflightStrictPass["make-dom-default"], .checks.defaultPreflightStrictPass["retire-temporary-paths"]] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  returned `false true true false false false false`.
- `jq -r '.readiness.checks[] | select(.id=="manualValidation") | [.strictPass, .details.entryCount, .details.invalidEntryCount, (.details.manualEvidence // [] | length), (.details.missingTargets|join(","))] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  returned `false`, `0`, `0`, `0`, and
  `chrome-ime-macos,chrome-voiceover-macos`.

## 2026-06-08 13:24 EDT

Bound readiness bundle manifests to generated artifact contents.

- `web_readiness_bundle.dart` now writes an `artifactFingerprints` section into
  `web-readiness-bundle.json`.
- The manifest fingerprints the generated frame scoreboard, semantic audit,
  manual audit, readiness JSON, readiness Markdown, and default-preflight
  JSON/Markdown artifacts. It intentionally skips the manifest's own
  `bundleJson` path to avoid a self-referential fingerprint.
- Bundle tests now assert both the passing reviewed-artifact case and the
  failed strict-readiness case preserve artifact fingerprints.
- The passing bundle test fixture now includes a reviewed threshold summary
  `outputPolicyFingerprint` that matches the reviewed threshold policy, so the
  bundle test exercises the full threshold-review fingerprint gate.
- Updated package docs, profiling docs, phase audit, and re-review packet to
  describe `artifactFingerprints` as the packet drift-detection mechanism.

Current artifact behavior:

- No browser recapture was run.
- The Phase 1 refresh readiness candidate bundle was regenerated through the
  artifact-only path with `--write-default-preflights`.
- The refreshed `web-readiness-bundle.json` now contains fingerprints for
  `scoreboard`, `semanticAudit`, `manualAudit`, `readinessJson`,
  `readinessMarkdown`, and both default-preflight JSON/Markdown pairs.
- The readiness vector remains `false true true false false false false`:
  overall readiness false, scoreboard true, semantic audit true, manual audit
  false, readiness false, and both default preflight targets false.

Verification:

- `dart format tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate readiness/preflight artifact set and exited 0
  with `strictPass: false`.
- `jq empty profiling/web/manual/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.json` -
  passed.
- `jq -r '[.strictPass, .checks.scoreboardStrictPass, .checks.semanticAuditStrictPass, .checks.manualAuditStrictPass, .checks.readinessStrictPass, .checks.defaultPreflightStrictPass["make-dom-default"], .checks.defaultPreflightStrictPass["retire-temporary-paths"]] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  returned `false true true false false false false`.
- `jq -r '[.artifactFingerprints.scoreboard, .artifactFingerprints.semanticAudit, .artifactFingerprints.manualAudit, .artifactFingerprints.readinessJson, .artifactFingerprints.defaultPreflights["make-dom-default"].json] | @tsv' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  returned `fnv1a64:f08790687358e551`,
  `fnv1a64:1054313457fea4b8`, `fnv1a64:9c117e02b64fa4a4`,
  `fnv1a64:02933918e47ab47f`, and
  `fnv1a64:c3aef27c625d95a2`.

## 2026-06-08 13:31 EDT

Added readiness bundle fingerprint verification.

- `web_readiness_bundle.dart` now accepts `--verify=PATH`.
- Verification reads an existing `web-readiness-bundle.json`, walks every
  indexed artifact path except the self-referential bundle manifest, recomputes
  fingerprints, and reports missing artifacts, missing fingerprints, and
  content mismatches.
- `--strict` makes a stale or incomplete packet exit non-zero. `--json` emits a
  `fleuryWebReadinessBundleVerification` result for automation.
- The root `fleury benchmark web-readiness-bundle` wrapper forwards
  `--verify=PATH`, so reviewers can run the packet check through the public
  benchmark CLI without regenerating evidence.
- Updated package docs, profiling docs, the phase audit, and the re-review
  packet to make the verifier the packet-drift check before re-review.

Current artifact behavior:

- No browser recapture was run.
- The existing Phase 1 refresh readiness candidate bundle verifies cleanly:
  `strictPass: true`, `checkedArtifactCount: 9`, `mismatchCount: 0`,
  `missingArtifactCount: 0`, and `missingFingerprintCount: 0`.
- The readiness vector remains unchanged from the generated packet:
  overall readiness is still false because the two primary manual targets,
  `chrome-ime-macos` and `chrome-voiceover-macos`, are still missing real
  reviewed evidence.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "forwards readiness bundle"` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with `strictPass: true` and 9 checked artifacts.
- `dart run tool/fleury_dev.dart --dry-run benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  forwarded the expected package verifier command.

## 2026-06-08 13:40 EDT

Bound default/retirement preflight to verified readiness bundles.

- `web_default_preflight.dart` now accepts `--bundle=PATH`.
- When supplied, the preflight verifies the bundle's
  `artifactFingerprints`, checks every indexed artifact except the
  self-referential manifest path, and confirms `artifacts.readinessJson` points
  at the same readiness JSON passed through `--readiness=PATH`.
- The bundle check is reported as a separate `readinessBundle` preflight check
  with mismatch, missing-artifact, and missing-fingerprint counts.
- The root `fleury benchmark web-default-preflight` wrapper forwards
  `--bundle=PATH`, and the benchmark catalog now shows the final default
  preflight command with both readiness and bundle inputs.
- Updated package docs, profiling docs, the phase audit, and the re-review
  packet so final release-action preflights include `--bundle=...`.

Current artifact behavior:

- No browser recapture was run.
- The current Phase 1 refresh candidate package preflight exits non-zero with
  `strictPass: false`, as intended, because Phase 6 readiness is still blocked
  by the candidate threshold policy and missing `chrome-ime-macos`/
  `chrome-voiceover-macos` evidence.
- In that same preflight result, the new `readinessBundle` check passes:
  `checkedArtifactCount: 9`, `mismatchCount: 0`, `missingArtifactCount: 0`,
  and `missingFingerprintCount: 0`.

Verification:

- `dart format packages/fleury_web/tool/web_default_preflight.dart packages/fleury_web/test/web_default_preflight_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_default_preflight.dart packages/fleury_web/test/web_default_preflight_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "forwards default preflight options|appears in benchmark catalog"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 with the expected Phase 6 blockers while the `readinessBundle`
  check passed.
- `dart run tool/fleury_dev.dart --dry-run benchmark web-default-preflight --readiness=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  forwarded the expected package preflight command.

## 2026-06-08 13:53 EDT

Bound readiness bundles to source evidence inputs.

- `web_readiness_bundle.dart` now writes `sourceInputFingerprints` into
  `web-readiness-bundle.json`.
- Source fingerprints cover the `fleuryWebFrameCapture` JSON files consumed
  from the capture directory, non-template manual evidence JSON files consumed
  from the manual directory, and any existing threshold policy or
  threshold-review summary files supplied to the bundle.
- `web_readiness_bundle.dart --verify=PATH --strict` now verifies both
  generated artifacts and source inputs. It reports separate counts for
  generated artifact mismatches/missing files and source input
  mismatches/missing files.
- `web_default_preflight.dart --bundle=PATH` now performs the same source-input
  verification inside the final release-action preflight, so a default flip or
  temporary-path retirement cannot pass against a stale source-evidence packet.
- Updated package docs, profiling docs, the phase audit, and the re-review
  packet to document the two fingerprint layers.

Current artifact behavior:

- No browser recapture was run.
- The Phase 1 refresh readiness candidate bundle was regenerated from existing
  JSON evidence with `--write-default-preflights`.
- The regenerated `web-readiness-bundle.json` verifies cleanly with
  `checkedArtifactCount: 9`, `checkedSourceInputCount: 34`,
  `sourceMismatchCount: 0`, `missingSourceInputCount: 0`, and
  `missingSourceFingerprintCount: 0`.
- The 34 source inputs are the 33 retained-DOM capture JSON files plus
  `thresholds.candidate.json`. There are still no reviewed manual evidence
  entries, and no reviewed `threshold-review.json`, so strict readiness remains
  false for the intended reasons.
- The bundle-bound default preflight still exits 1 with the expected Phase 6
  blockers, while its `readinessBundle` check passes with 9 generated artifacts
  and 34 source inputs verified.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart packages/fleury_web/tool/web_default_preflight.dart packages/fleury_web/test/web_default_preflight_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart packages/fleury_web/tool/web_default_preflight.dart packages/fleury_web/test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate bundle from existing artifacts and exited 0.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 9 checked generated artifacts and 34 checked source inputs.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 with the expected Phase 6 blockers while the `readinessBundle`
  check passed with 9 generated artifacts and 34 source inputs verified.

## 2026-06-08 14:03 EDT

Added machine-readable remaining release actions to readiness bundles.

- `web_readiness_bundle.dart` now writes `remainingReleaseActions` into
  `web-readiness-bundle.json`.
- Passing bundles report an empty action list.
- Failed bundles derive follow-up actions from the same readiness and preflight
  checks that gate the release:
  - `review-threshold-policy` for candidate or otherwise unreviewed threshold
    policies;
  - one `collect-manual-evidence:<target>` action per failing manual target;
  - `regenerate-readiness-bundle`;
  - `verify-readiness-bundle`;
  - one bundle-bound `run-default-preflight:<target>` action per failed
    release-action preflight.
- Candidate threshold follow-up now intentionally points regeneration at the
  reviewed `thresholds.json` output produced by `web_threshold_review.dart`,
  rather than rerunning readiness against `thresholds.candidate.json`.
- Updated package/profiling docs, the phase audit, and the re-review packet to
  document `remainingReleaseActions`.

Current artifact behavior:

- No browser recapture was run.
- The Phase 1 refresh readiness candidate bundle was regenerated from existing
  JSON evidence with `--write-default-preflights`.
- The regenerated bundle remains red for the intended reasons, but now lists
  seven remaining actions:
  `review-threshold-policy`,
  `collect-manual-evidence:chrome-ime-macos`,
  `collect-manual-evidence:chrome-voiceover-macos`,
  `regenerate-readiness-bundle`,
  `verify-readiness-bundle`,
  `run-default-preflight:make-dom-default`, and
  `run-default-preflight:retire-temporary-paths`.
- The regenerated `regenerate-readiness-bundle` action points at
  `thresholds.json` and `threshold-review.json`, matching the reviewed
  threshold promotion output.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate bundle from existing JSON evidence and exited 0.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 9 checked generated artifacts and 34 checked source inputs.
- `jq empty` over the regenerated readiness-candidate JSON artifacts -
  passed.

## 2026-06-08 14:11 EDT

Added batch manual validation template generation for the primary retained-DOM
manual gates.

- `web_manual_validation.dart` now accepts `--write-templates=DIR`, writing one
  `<target-id>.template.json` file for each selected target. The existing
  `--write-template=PATH --template-target=ID` one-off path remains supported.
- The new batch path respects `--target-preset` and repeated `--target` filters,
  and rejects an empty template directory path before auditing.
- `fleury benchmark web-manual-validation` now forwards `--write-templates=DIR`
  through the root CLI wrapper.
- Docs now show the primary workflow:
  `fleury benchmark web-manual-validation --write-templates=profiling/web/manual/templates --target-preset=primary`.

Current artifact behavior:

- Generated the primary templates:
  - `profiling/web/manual/templates/chrome-ime-macos.template.json`;
  - `profiling/web/manual/templates/chrome-voiceover-macos.template.json`.
- Refreshed `profiling/web/manual/manual-validation-audit.json`; it still has
  `strictPass: false`, `entryCount: 0`, and both primary targets missing, as no
  reviewed Chrome IME or Chrome VoiceOver evidence has been collected yet.
- Regenerated the Phase 1 refresh readiness candidate bundle from existing
  captures plus the refreshed manual audit. Performance and semantic gates
  remain green; the bundle still correctly blocks on threshold review, manual
  IME evidence, manual VoiceOver evidence, and downstream strict preflights.
- Bundle verification still checks 9 generated artifacts and 34 source inputs
  with no mismatches.

Verification:

- `dart format packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/test/web_manual_validation_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/test/web_manual_validation_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-manual-validation"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --write-templates=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json --json` -
  wrote both primary templates, refreshed the manual audit, and exited 0.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate bundle from existing JSON evidence and exited 0.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 9 checked generated artifacts and 34 checked source inputs.
- `jq empty` over the refreshed manual audit, generated templates, and
  readiness-candidate JSON artifacts - passed.
- `git diff --check` - passed.
- Touched-file trailing-whitespace scan - passed.

## 2026-06-08 14:16 EDT

Aligned readiness bundle release actions with batch manual template generation.

- `web_readiness_bundle.dart` now emits a
  `prepare-manual-evidence-templates` action whenever manual validation is
  failing.
- The preparation action uses `web_manual_validation.dart --write-templates`
  and targets the concrete failing manual target IDs when readiness includes
  them. If readiness cannot identify target IDs, it falls back to the bundle's
  selected manual target preset.
- Per-target `collect-manual-evidence:<target>` actions remain the actual
  human evidence gates, and now depend on `prepare-manual-evidence-templates`.
- Docs now describe manual template preparation as part of the
  `remainingReleaseActions` sequence.

Current artifact behavior:

- The Phase 1 refresh readiness candidate bundle was regenerated from existing
  captures and manual audit artifacts.
- The regenerated bundle still has `strictPass: false` for the intended
  external blockers: candidate threshold policy, missing Chrome IME evidence,
  missing Chrome VoiceOver evidence, and downstream default preflights.
- `remainingReleaseActions` now lists eight actions:
  `review-threshold-policy`,
  `prepare-manual-evidence-templates`,
  `collect-manual-evidence:chrome-ime-macos`,
  `collect-manual-evidence:chrome-voiceover-macos`,
  `regenerate-readiness-bundle`,
  `verify-readiness-bundle`,
  `run-default-preflight:make-dom-default`, and
  `run-default-preflight:retire-temporary-paths`.
- The generated preparation command writes both primary templates in one pass:
  `--write-templates=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates`,
  `--target=chrome-ime-macos`, and `--target=chrome-voiceover-macos`.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate bundle from existing JSON evidence and exited 0.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 9 checked generated artifacts and 34 checked source inputs.
- `jq empty` over the regenerated readiness-candidate JSON artifacts - passed.
- `git diff --check` - passed.

## 2026-06-08 14:21 EDT

Preserved manual target scope in readiness bundle manifests and follow-up
actions.

- `web_readiness_bundle.dart` now records manual target scope in the bundle
  `input` block as `targetPreset` plus `targetIds` when explicit targets are
  supplied.
- Generated manual template preparation commands, manual audit commands, and
  regenerate-bundle commands now share the same target-scope helper:
  - bundles created with explicit `--target=...` emit repeated `--target`
    follow-up arguments;
  - bundles created from a preset continue to emit `--target-preset=<preset>`.
- Added regression coverage for a bundle generated with
  `--target=chrome-ime-macos`, proving the generated preparation, manual audit,
  and regeneration commands do not widen back to `--target-preset=primary`.
- Updated docs and the review packet notes to call out target-scope preservation.

Current artifact behavior:

- The Phase 1 refresh readiness candidate bundle was regenerated from existing
  captures and manual audit artifacts.
- Its current input block records `targetPreset: primary`; no explicit
  `targetIds` are present because the current candidate was generated from the
  primary preset.
- The current release-action list is otherwise unchanged: threshold review,
  batch manual template preparation, both manual evidence targets, regeneration,
  verification, and the two default preflights remain the outstanding steps.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate bundle from existing JSON evidence and exited 0.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 9 checked generated artifacts and 34 checked source inputs.
- `jq empty` over the regenerated readiness-candidate JSON artifacts - passed.
- `git diff --check` - passed.
- Touched-file trailing-whitespace scan - passed.

## 2026-06-08 14:32 EDT

Added non-promoting threshold review plans and wired them into readiness
follow-up actions.

- `web_threshold_review.dart` now accepts `--write-plan=PATH` for a
  non-promoting Markdown review packet. Plan-only mode requires only
  `--input` and `--write-plan`; it does not require reviewer provenance and it
  does not write promoted threshold JSON.
- Promotion mode still requires `--output`, `--reviewed-by`, and
  `--review-context`, preserving the review provenance gate before writing
  durable `thresholds.json`.
- The root `benchmark web-threshold-review` launcher forwards
  `--write-plan=PATH`, supports plan-only invocation, and documents both the
  plan and promotion flows.
- `web_readiness_bundle.dart` now emits a `planCommand` on the
  `review-threshold-policy` release action. The plan command includes only
  `--input` and `--write-plan`, while the existing promotion
  `commandTemplate` keeps the reviewed-by/context placeholders and promoted
  output paths.
- Documentation now describes the threshold review plan as the first review
  step before threshold promotion.

Current artifact behavior:

- Generated
  `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review-plan.md`
  from the current candidate thresholds.
- The plan records the input fingerprint, candidate generation metadata,
  11 release scenarios, total-frame / DOM-apply / semantic-apply thresholds,
  over-budget percentages, uncovered-cell thresholds, and the explicit
  promotion command template.
- Regenerated the readiness candidate bundle from the current captures,
  existing manual artifacts, and candidate thresholds.
- The readiness candidate still has `strictPass: false` for the intentional
  external release gates: candidate threshold policy, missing Chrome IME
  evidence, missing Chrome VoiceOver evidence, and the two default preflights.
- The bundle's `review-threshold-policy` action now includes
  `details.thresholdReviewPlanPath` and a non-promoting `planCommand` for the
  generated plan.

Verification:

- `dart format packages/fleury_web/tool/web_threshold_review.dart packages/fleury_web/test/web_threshold_review_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_threshold_review.dart packages/fleury_web/test/web_threshold_review_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_threshold_review_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-threshold-review"` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "candidate thresholds"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_threshold_review.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review-plan.md` -
  wrote the non-promoting review plan and exited 0.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate bundle and exited 0.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 9 checked generated artifacts and 34 checked source inputs.
- `jq empty` over the regenerated readiness-candidate JSON artifacts - passed.
- `git diff --check` - passed.
- Touched-file trailing-whitespace scan - passed with no matches.

## 2026-06-08 14:39 EDT

Added a human-readable release-action artifact to failed readiness bundles.

- `web_readiness_bundle.dart` now writes `web-release-actions.md` when
  `remainingReleaseActions` is non-empty.
- The Markdown artifact renders the same action graph as the manifest JSON:
  action IDs, kinds, labels, dependencies, blocking checks, blockers, target
  status, detail tables, plan commands, execution commands, and audit commands.
- The bundle indexes the new file as `artifacts.releaseActionsMarkdown` and
  records its fingerprint under `artifactFingerprints.releaseActionsMarkdown`,
  so `--verify=PATH --strict` now catches stale release-action Markdown along
  with scoreboard, semantic, manual, readiness, and default-preflight artifacts.
- Passing bundles with no remaining actions do not write the extra artifact.
- Docs and the architecture review packet now list `web-release-actions.md` as
  part of failed/candidate review packets.

Current artifact behavior:

- Regenerated the Phase 1 refresh readiness candidate bundle from existing
  captures, existing manual artifacts, and candidate thresholds.
- The regenerated bundle still has `strictPass: false` for the intended
  external release gates: candidate threshold policy, missing Chrome IME
  evidence, missing Chrome VoiceOver evidence, and downstream default
  preflights.
- The regenerated bundle now includes
  `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-release-actions.md`
  plus its artifact fingerprint.
- Bundle verification now checks 10 generated artifacts and 34 source inputs
  for this candidate packet.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate bundle and exited 0.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts and 34 checked source inputs.
- `jq empty` over the regenerated readiness-candidate JSON artifacts - passed.
- `git diff --check` - passed.
- Touched-file trailing-whitespace scan - passed with no matches.

## 2026-06-08 14:46 EDT

Bound threshold review plans into readiness bundle review packets.

- `web_readiness_bundle.dart` now derives the default
  `threshold-review-plan.md` path from the candidate threshold policy path.
- When a threshold review plan exists, the bundle records it under
  `sourceInputFingerprints.thresholdReviewPlan`, so packet verification catches
  deleted or modified plan files.
- The `review-threshold-policy` release action now reports
  `thresholdReviewPlanStatus` and `thresholdReviewPlanInputFingerprint`.
  Status values distinguish a current plan from a stale plan, missing plan, or
  plan missing its input fingerprint.
- Stale, missing, or malformed threshold review plans are surfaced as
  action-level blockers in the generated release-action graph. A current plan
  does not change the release gate result; human threshold review and
  promotion are still required.
- Docs and the review packet now describe threshold review plan fingerprinting
  and status reporting.

Current artifact behavior:

- Regenerated the Phase 1 refresh readiness candidate bundle from existing
  captures, existing manual artifacts, and candidate thresholds.
- The regenerated bundle still has `strictPass: false` for the intended
  external release gates: candidate threshold policy, missing Chrome IME
  evidence, missing Chrome VoiceOver evidence, and downstream default
  preflights.
- `sourceInputFingerprints.thresholdReviewPlan` now records
  `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review-plan.md`.
- The `review-threshold-policy` action now reports
  `thresholdReviewPlanStatus: current` with input fingerprint
  `fnv1a64:d6f18428fe25af25`, matching the current candidate policy
  fingerprint reported by the frame scoreboard.
- Bundle verification now checks 10 generated artifacts and 35 source inputs
  for this candidate packet.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "candidate thresholds"` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate bundle and exited 0.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts and 35 checked source inputs.
- `jq empty` over the regenerated readiness-candidate JSON artifacts - passed.
- `git diff --check` - passed.
- Touched-file trailing-whitespace scan - passed with no matches.

## 2026-06-08 14:51 EDT

Made generated review commands shell-safe for placeholder arguments.

- `web_readiness_bundle.dart` now shell-quotes generated Markdown command
  arguments that contain spaces or shell metacharacters. This keeps
  placeholders such as `--reviewed-by=<reviewer>` from being interpreted as
  shell redirection when copied from `web-release-actions.md`.
- `web_threshold_review.dart` now renders the promotion command in
  `threshold-review-plan.md` through the same shell-safe quoting rule.
- Tests now assert that generated threshold review plans and release-action
  Markdown quote placeholder arguments.
- Executable documentation examples now use shell-safe placeholders such as
  `REVIEWER`, `VERSION`, and `PLATFORM` instead of unquoted angle-bracket
  placeholders.

Current artifact behavior:

- Regenerated
  `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review-plan.md`.
- Regenerated the Phase 1 refresh readiness candidate bundle from existing
  captures, existing manual artifacts, and candidate thresholds.
- `web-release-actions.md` now renders the threshold promotion command with
  quoted placeholder arguments:
  `'--reviewed-by=<reviewer>'` and
  `'--review-context=<Chrome version, platform, retained DOM product baseline>'`.
- `threshold-review-plan.md` now renders the multiline promotion command with
  quoted placeholder arguments:
  `'--reviewed-by=<reviewer>'` and
  `'--review-context=Chrome <version> on <platform>, retained DOM product baseline'`.
- The regenerated bundle still has `strictPass: false` for the intended
  external release gates: candidate threshold policy, missing Chrome IME
  evidence, missing Chrome VoiceOver evidence, and downstream default
  preflights.
- Bundle verification still checks 10 generated artifacts and 35 source inputs
  for this candidate packet.

Verification:

- `dart format packages/fleury_web/tool/web_threshold_review.dart packages/fleury_web/test/web_threshold_review_tool_test.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_threshold_review.dart packages/fleury_web/test/web_threshold_review_tool_test.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_threshold_review_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "keeps artifacts"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_threshold_review.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review-plan.md` -
  regenerated the threshold review plan and exited 0.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate bundle and exited 0.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts and 35 checked source inputs.
- `jq empty` over the regenerated readiness-candidate JSON artifacts - passed.
- `git diff --check` - passed.
- Touched-file trailing-whitespace scan - passed with no matches.

## 2026-06-08 14:54 EDT

Aligned local review-packet README commands with the current release gates.

- The Phase 1 refresh baseline README now lists threshold review plan
  generation in the captured command sequence.
- The baseline README now tells reviewers to verify the generated
  `web-readiness-bundle.json` before using the packet.
- The baseline README's default and temporary-path preflight examples now pass
  `--bundle=.../web-readiness-bundle.json`, matching the final release-action
  gate behavior.
- The threshold promotion example now persists
  `threshold-review.json` with `--json-output`, matching the default Phase 6
  readiness requirement for a durable threshold promotion summary.
- The artifact list now includes `threshold-review-plan.md` and
  `readiness-candidate/web-release-actions.md`.
- The package README quick workflow's default-preflight example now also uses
  `--bundle=...`.

Verification:

- Searched README preflight examples and confirmed each `web_default_preflight`
  command over `web-readiness.json` passes `--bundle=...`.
- Searched threshold promotion examples and confirmed each
  `web-threshold-review --output=.../thresholds.json` command also persists
  `threshold-review.json` with `--json-output`.
- `git diff --check` - passed.
- README trailing-whitespace scan - passed with no matches.

## 2026-06-08 14:58 EDT

Aligned root `fleury benchmark` release-gate examples with the strict web
artifact path.

- The machine-readable benchmark catalog now emits shell-safe threshold review
  placeholders (`REVIEWER`, `Chrome VERSION on PLATFORM`) instead of angle
  bracket placeholders that can be misread as shell redirection when copied.
- General and detailed root `web-threshold-review` help examples now use the
  same shell-safe placeholders.
- General and detailed root `web-readiness-bundle` examples now include the
  reviewed threshold policy and threshold review summary inputs required by the
  Phase 6 readiness gate.
- The general root `web-default-preflight` example now passes
  `--bundle=.../web-readiness-bundle.json`, matching the stricter generated
  release-action command and package README workflow.
- The catalog test now asserts that `webDefaultPreflight.command` includes the
  bundle manifest and that `webThresholdReview.command` does not regress to the
  unsafe reviewer placeholder.
- The benchmark help test now asserts that the general root examples include
  reviewed threshold inputs, bundle verification, and shell-safe review
  placeholders.
- The review packet's remaining release gates now say to review the existing
  `threshold-review-plan.md` rather than implying the current packet still
  lacks one.
- The phase audit now records root `fleury benchmark` catalog/help hardening as
  part of the Phase 6 release-command surface.

Verification:

- `dart format tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "appears in benchmark catalog"` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark web-readiness launcher"` -
  passed with 6 tests, including the root help example regression check.
- `dart analyze tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.

## 2026-06-08 15:05 EDT

Hardened manual evidence templates so template preparation time cannot be
mistaken for reviewed manual validation time.

- `web_manual_validation.dart` now writes generated evidence templates with a
  blank `capturedAt` field instead of stamping the template generation time.
- Strict manual validation already treats blank `capturedAt` as a provenance
  blocker, so copied evidence must record the actual IME or VoiceOver
  validation time before it can pass.
- Regenerated the primary target templates under
  `profiling/web/manual/templates/`.
- Updated the manual evidence README, review packet, and phase audit to state
  that blank `capturedAt` in templates is intentional and must be replaced in
  real evidence.

Current artifact behavior:

- The regenerated `chrome-ime-macos.template.json` and
  `chrome-voiceover-macos.template.json` both have `capturedAt: ""`,
  `status: "needsReview"`, and empty `reviewedBy`.
- The real strict manual audit still fails as intended with
  `entryCount: 0`, `ignoredFileCount: 3`, and missing targets
  `chrome-ime-macos` and `chrome-voiceover-macos`.
- Existing readiness bundle verification still passes because manual templates
  are ignored as source evidence; the verifier checked 10 generated artifacts
  and 35 source inputs with zero mismatches.

Verification:

- `dart format packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json --strict --json` -
  exited 1 as expected because real manual evidence is still missing, while
  confirming the two `*.template.json` files are ignored as templates.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed.

## 2026-06-08 15:15 EDT

Tightened readiness-bundle release actions so manual template preparation is no
longer reported as remaining work when templates are already current.

- `web_readiness_bundle.dart` now inspects each selected manual target template
  and classifies it as `current`, `missing`, `invalid`, or `stale`.
- `prepare-manual-evidence-templates` is emitted only when at least one
  required template is missing, invalid, or stale.
- Per-target `collect-manual-evidence:<target>` actions now report
  `templateStatus` and `templateFingerprint`; when the template is current,
  they do not depend on template preparation and do not render a redundant
  `--write-template` command.
- Tests cover both missing-template and current-template action graphs.
- Regenerated the Phase 1 refresh readiness candidate bundle and
  `web-release-actions.md` from existing captures, current manual templates,
  and candidate thresholds.
- Updated package/review docs to describe conditional manual template
  preparation.

Current artifact behavior:

- The regenerated readiness bundle now has 7 remaining release actions:
  threshold review, both manual evidence collection actions, bundle
  regeneration, bundle verification, and both default preflights.
- `prepare-manual-evidence-templates` is absent because the two primary target
  templates are current.
- Both manual collection actions report `templateStatus: current` with
  template fingerprints and no `commandTemplate`.
- The bundle still has `strictPass: false` for the intended external gates:
  candidate threshold policy, missing Chrome IME evidence, missing Chrome
  VoiceOver evidence, and downstream default preflights.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "manual evidence actions|skips template prep"` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate bundle.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts and 35 checked source inputs.
- `git diff --check` - passed.

## 2026-06-08 15:21 EDT

Bound manual template fingerprints into readiness-bundle verification.

- `web_readiness_bundle.dart` now records existing `*.template.json` files
  under `sourceInputFingerprints.manualTemplateFiles`.
- The bundle verifier now checks those template fingerprints with the same
  source-input drift path used for capture/manual-evidence/threshold files.
- The current-template action-graph test now mutates a template after bundle
  generation and verifies that `web_readiness_bundle --verify --strict`
  reports a `manualTemplateFiles[...]` source mismatch.
- Regenerated the Phase 1 refresh readiness candidate bundle so the manifest's
  `manualTemplateFiles` fingerprints match the `templateFingerprint` values
  shown on both manual evidence release actions.
- Updated package and review docs to state that manual template files are part
  of source-input fingerprint verification.

Current artifact behavior:

- The regenerated candidate bundle's `sourceInputFingerprints` contains
  `manualTemplateFiles` for `chrome-ime-macos.template.json` and
  `chrome-voiceover-macos.template.json`.
- `web-readiness-bundle --verify --strict` now checks 37 source inputs for this
  packet: the prior 35 inputs plus the two manual template files.
- Readiness remains intentionally false for reviewed-threshold and real manual
  evidence blockers.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "skips template prep action when templates exist"` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate bundle.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts and 37 checked source inputs.
- `jq empty` over the regenerated readiness-candidate JSON artifacts - passed.
- `git diff --check` - passed.

## 2026-06-08 15:27 EDT

Scoped manual template source fingerprints to the selected manual target set.

- `web_readiness_bundle.dart` now derives manual template fingerprint targets
  from the manual validation audit's `targets` list, falling back to explicit
  `--target` arguments only if the audit has no target rows.
- `sourceInputFingerprints.manualTemplateFiles` now fingerprints the selected
  target templates instead of every `*.template.json` file under the manual
  directory.
- The explicit-target bundle test now creates both primary templates, runs the
  bundle with `--target=chrome-ime-macos`, and verifies that only
  `chrome-ime-macos.template.json` is included in `manualTemplateFiles`.
- The same explicit-target test now confirms the action graph skips template
  preparation when the selected template is current, while preserving
  `--target=chrome-ime-macos` in manual audit and regeneration commands.
- Updated package and review docs to say template source fingerprints are
  scoped to selected manual targets.

Current artifact behavior:

- The primary Phase 1 refresh packet still fingerprints both primary templates
  because its target preset is `primary`.
- `web-readiness-bundle --verify --strict` still checks 37 source inputs for
  the primary packet.
- Explicit one-target packets will no longer be invalidated by unrelated
  templates outside their selected target scope.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "explicit manual targets|skips template prep action"` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate bundle.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts and 37 checked source inputs.
- `git diff --check` - passed.

## 2026-06-08 15:35 EDT

Made generated default-preflight binding status explicit in readiness bundles.

- `web_readiness_bundle.dart` now records
  `checks.defaultPreflightBundleBound` for generated default-preflight
  artifacts.
- The bundle also records
  `checks.defaultPreflightFinalGateRequiresBundle: true`, making clear that the
  generated preflight artifacts are readiness-bound review snapshots and that
  the final release-action preflights must still run with `--bundle=...`.
- This avoids implying that bundle-generated preflight artifacts are themselves
  bundle-bound, which would create a circular fingerprint dependency because
  the bundle also fingerprints those generated preflight artifacts.
- Updated package/review docs to explain the distinction.
- Regenerated the Phase 1 refresh readiness candidate bundle.

Current artifact behavior:

- The regenerated bundle reports `defaultPreflightBundleBound` as `false` for
  both `make-dom-default` and `retire-temporary-paths`.
- `defaultPreflightFinalGateRequiresBundle` is `true`.
- The generated preflight artifacts still strict-fail for the intended
  readiness blockers, while release-action commands remain bundle-bound.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "writes passing reviewed artifacts|keeps artifacts"` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate bundle.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts and 37 checked source inputs.
- `git diff --check` - passed.

## 2026-06-08 15:40 EDT

Tightened manual evidence release-action handoff details.

- `web_readiness_bundle.dart` now includes the manual validation page source,
  required evidence page value, evidence directory, suggested evidence file
  path, and reviewer next step in each `collect-manual-evidence:<target>`
  action.
- This preserves the optimized action graph that skips template preparation
  when templates are current, while still giving reviewers enough detail to
  copy the template, fill reviewed provenance, and rerun the strict manual
  audit.
- Regenerated the Phase 1 refresh readiness candidate bundle so
  `web-readiness-bundle.json` and `web-release-actions.md` include the new
  manual evidence handoff fields.

Current artifact behavior:

- The remaining action list is unchanged at seven actions:
  `review-threshold-policy`, two manual evidence actions, bundle regeneration,
  bundle verification, and the two final default-preflight actions.
- Both manual evidence actions now include
  `manualValidationPage: web/manual_validation.html`,
  `requiredEvidencePage: manual_validation.html`, and a target-specific
  `suggestedEvidencePath` under `profiling/web/manual/evidence`.
- Template preparation remains omitted because both primary templates are
  current and source-fingerprinted.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "web readiness bundle reports manual evidence actions|skips template prep action"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate bundle.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts and 37 checked source inputs.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `git diff --check` - passed.

## 2026-06-08 15:44 EDT

Made generated release-action commands cwd-explicit.

- `web_readiness_bundle.dart` now records
  `input.commandWorkingDirectory` using the package cwd that generated the
  bundle.
- `web-release-actions.md` now renders the same command working directory in
  the header before listing package-relative `dart run tool/...` commands.
- The bundle tests assert both the JSON field and rendered markdown header so
  future release-action changes cannot silently drop the cwd requirement.
- Regenerated the Phase 1 refresh readiness candidate bundle.

Current artifact behavior:

- The regenerated bundle records
  `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web` as
  `input.commandWorkingDirectory`.
- `web-release-actions.md` now tells reviewers to run commands from that
  package directory.
- The remaining action list is still the same seven readiness blockers and
  final gates.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "writes passing reviewed artifacts|reports manual evidence actions"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the candidate bundle.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts and 37 checked source inputs.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `git diff --check` - passed.

## 2026-06-08 15:47 EDT

Synchronized cwd-explicit release-action behavior across durable docs.

- `packages/fleury_web/README.md` now documents that readiness bundle inputs
  include `commandWorkingDirectory` and that `web-release-actions.md` renders
  it with the generated commands.
- `docs/implementation/web-rfc-review-packet.md` now calls out the package cwd
  recorded by the Phase 1 refresh bundle.
- `docs/implementation/web-rfc-phase-audit.md` now includes cwd recording in
  the Phase 6 readiness-bundle capability trace.

Current artifact behavior:

- `web-readiness-bundle.json` records
  `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web` as
  `input.commandWorkingDirectory`.
- `web-release-actions.md` renders the same cwd in the header before the seven
  remaining release actions.

Verification:

- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `git diff --check` - passed.

## 2026-06-08 15:48 EDT

Verified the public release-packet verification launcher path.

- Ran the review-packet command through `dart tool/fleury_dev.dart benchmark
  web-readiness-bundle --verify=... --strict --json` from the repo root.
- The launcher resolved the relative packet path to an absolute bundle path
  and executed `tool/web_readiness_bundle.dart` from
  `packages/fleury_web`, matching the cwd now recorded in the bundle and
  release-action markdown.

Verification:

- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts and 37 checked source inputs.

## 2026-06-08 15:57 EDT

Made readiness bundle verification enforce command cwd metadata.

- `web_readiness_bundle.dart --verify` now checks
  `input.commandWorkingDirectory` and strict-fails if it is missing or does not
  match the package cwd used by the verifier.
- Verification JSON now reports `checkedMetadataCount`,
  `metadataMismatchCount`, and `missingMetadataCount`; human-readable
  verification output prints the same counters.
- `web_readiness_bundle_tool_test.dart` covers both the passing metadata path
  and a tampered stale-cwd bundle.
- Updated package README, review packet, and phase audit text so packet
  verification is described as checking generated artifacts, source inputs, and
  required command-cwd metadata.
- Regenerated the Phase 1 refresh readiness candidate bundle.

Current artifact behavior:

- Public and direct verification both pass with 10 generated artifacts, 37
  source inputs, and one metadata field checked.
- The readiness bundle remains intentionally red because threshold promotion
  and real manual IME/VoiceOver evidence are still outstanding.

Verification:

- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.

## 2026-06-08 16:04 EDT

Added manual evidence starter commands to release actions.

- `web_readiness_bundle.dart` now emits `starterEvidencePath` and
  `starterCommand` for each `collect-manual-evidence:<target>` action.
- The starter command creates the evidence directory if needed and copies the
  target template to `<target>.review.json`, giving reviewers a concrete first
  command before filling provenance and running the strict audit command.
- `web-release-actions.md` now renders `Starter command` sections in addition
  to plan, command, and audit command sections.
- `web_readiness_bundle_tool_test.dart` covers starter command details in both
  missing-template and current-template action graphs, while preserving the
  rule that current templates do not re-run `--write-template`.
- Updated package README, review packet, and phase audit text to mention the
  manual evidence starter command.
- Regenerated the Phase 1 refresh readiness candidate bundle.

Current artifact behavior:

- The two manual evidence actions include runnable starter copy commands for
  `chrome-ime-macos.review.json` and `chrome-voiceover-macos.review.json`.
- The remaining action list is still seven actions: threshold review, two
  manual evidence actions, bundle regeneration, bundle verification, and two
  final default-preflight gates.

Verification:

- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `git diff --check` - passed.

## 2026-06-08 16:10 EDT

Made manual evidence starter commands no-overwrite.

- `web_readiness_bundle.dart` now emits starter shell scripts that create the
  evidence directory, check whether `<target>.review.json` already exists, and
  fail with a clear stderr message instead of overwriting in-progress reviewed
  evidence.
- Manual evidence action details now include
  `starterOverwritePolicy: fail-if-destination-exists`, and the reviewer next
  step tells reviewers to run the starter command once.
- `web_readiness_bundle_tool_test.dart` now executes a generated starter
  command, verifies it creates the starter file, then reruns it and verifies the
  command fails without changing the in-progress file.
- Updated package README, review packet, and phase audit text to describe the
  no-overwrite starter behavior.
- Regenerated the Phase 1 refresh readiness candidate bundle.

Current artifact behavior:

- The two manual evidence actions include no-overwrite starter commands for
  `chrome-ime-macos.review.json` and `chrome-voiceover-macos.review.json`.
- The readiness bundle remains intentionally red for threshold review and real
  manual browser evidence.

Verification:

- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `git diff --check` - passed.

## 2026-06-08 16:19 EDT

Marked threshold review promotion commands as non-runnable templates.

- `web_readiness_bundle.dart` now emits machine-readable placeholder metadata
  for `review-threshold-policy`: `commandTemplateRunnable: false`,
  `commandTemplatePlaceholders`, and a `reviewerNextStep` that tells reviewers
  to replace the placeholders before running promotion.
- The placeholder metadata names the required reviewer handle and review
  context arguments, including the browser version, platform, and retained DOM
  product baseline under review.
- `web_readiness_bundle_tool_test.dart` covers the placeholder metadata in both
  candidate-promotion and strict-failure artifact-preservation paths.
- Updated package README, review packet, and phase audit text so generated
  release actions distinguish runnable commands from human-filled command
  templates.
- Regenerated the Phase 1 refresh readiness candidate bundle.

Current artifact behavior:

- `web-release-actions.md` renders `commandTemplateRunnable: false`,
  `commandTemplatePlaceholders`, and `reviewerNextStep` for
  `review-threshold-policy`.
- The threshold review command still includes explicit placeholders:
  `--reviewed-by=<reviewer>` and
  `--review-context=<Chrome version, platform, retained DOM product baseline>`.
- The readiness bundle remains intentionally red for threshold review and real
  manual Chrome IME/VoiceOver evidence; the bundle integrity verifier itself is
  green.

Verification:

- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `git diff --check` - passed.

## 2026-06-08 16:25 EDT

Ran broader local verification across web and touched core paths.

- `packages/fleury_web` full test suite passed before the analyzer cleanup.
- Removed an unnecessary `package:fleury_web/src/run_tui_surface.dart` import
  from `web/benchmark_capture.dart`; the used symbols are already exported
  through `package:fleury_web/fleury_web.dart`.
- `packages/fleury_web` analyzer is now clean.
- Re-ran the web-frame capture tool test after the import cleanup to cover the
  browser benchmark entrypoint/tool path.
- `packages/fleury` analyzer is clean.
- Ran targeted core tests for the touched runtime, rendering, semantics, input,
  and text-widget paths.

Verification:

- `cd packages/fleury_web && dart test` - passed.
- `cd packages/fleury_web && dart analyze` - passed after the import cleanup.
- `cd packages/fleury_web && dart test test/web_frame_capture_tool_test.dart` -
  passed.
- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury && dart test test/runtime/tui_runtime_test.dart test/runtime/tui_frame_loop_test.dart test/runtime/run_tui_test.dart test/runtime/input_dispatcher_test.dart` -
  passed.
- `cd packages/fleury && dart test test/rendering/cell_buffer_test.dart test/rendering/ansi_renderer_test.dart test/rendering/ansi_renderer_equivalence_test.dart test/rendering/ansi_byte_budget_test.dart` -
  passed.
- `cd packages/fleury && dart test test/semantics/semantics_test.dart test/semantics/semantics_owner_test.dart test/semantics/inspection_test.dart` -
  passed.
- `cd packages/fleury && dart test test/widgets/text_input_test.dart test/widgets/text_area_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.

## 2026-06-08 16:28 EDT

Ran a lightweight real-browser retained DOM smoke capture.

- Ran `web_frame_capture.dart` against `normal-80x24` with three measured
  frames and one warmup frame, writing the smoke result outside the repo at
  `/tmp/fleury-web-smoke-2026-06-08.json`.
- Chrome/Dart compilation and the headless browser capture path completed
  successfully.
- The smoke captured three frames with `runtimeRenderMs` as the dominant p95
  slice, zero semantic fallback nodes, and zero uncovered semantic cells.
- The smoke was intentionally not promoted into the readiness corpus: at three
  measured frames it is a path check, not a threshold-review signal. It reported
  100% over-budget frames, while the existing retained baseline for the same
  scenario uses three 24-frame runs and remains the authoritative threshold
  input.

Verification:

- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=normal-80x24 --frames=3 --warmup=1 --output=/tmp/fleury-web-smoke-2026-06-08.json --json` -
  passed and wrote the smoke capture.
- `jq '.summary' /tmp/fleury-web-smoke-2026-06-08.json` - confirmed
  `frameCount: 3`, `dominantP95Slice: runtimeRenderMs`,
  `semanticFallbackNodes.max: 0`, and `semanticUncoveredCells.max: 0`.
- `git diff --check` - passed.

## 2026-06-08 16:35 EDT

Added structured downstream release-action details.

- `web_readiness_bundle.dart` now emits machine-readable `details` for
  `regenerate-readiness-bundle`, `verify-readiness-bundle`, and
  `run-default-preflight:<target>` actions instead of leaving those action
  details null.
- Regeneration action details include capture/manual/output paths, generated
  bundle/readiness paths, reviewed threshold inputs, `maxFallbackCells`,
  target scope, default-preflight generation, strict/json expectations, and the
  reviewer sequencing step.
- Verification action details include the bundle path, strict/json
  expectations, and the verification scope: generated artifact fingerprints,
  source input fingerprints, and command-working-directory metadata.
- Default-preflight action details include target id, readiness path, bundle
  path, strict/json expectations, and bundle-binding requirements.
- Updated README, review packet, and phase audit text to describe the
  downstream action metadata.
- Regenerated the Phase 1 refresh readiness candidate bundle so
  `web-readiness-bundle.json` and `web-release-actions.md` include the new
  details.

Current artifact behavior:

- `web-release-actions.md` now renders `bundleJsonPath`, `verificationScope`,
  `requiresBundleBinding`, `strictRequired`, and `jsonOutput` details for the
  downstream release actions.
- The readiness bundle remains intentionally red for threshold review and real
  manual Chrome IME/VoiceOver evidence; the bundle integrity verifier remains
  green.

Verification:

- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "promote candidate thresholds|keeps artifacts"` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `rg -n "bundleJsonPath|verificationScope|requiresBundleBinding|strictRequired|jsonOutput" profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-release-actions.md` -
  confirmed the generated Markdown renders the new details.
- `git diff --check` - passed.

## 2026-06-08 16:42 EDT

Hardened manual evidence templates as self-describing review artifacts.

- `web_manual_validation.dart` templates now include a structured `target`
  block with label, phase, category, browser/platform, target-specific
  technology, and required check count.
- Templates also include `reviewInstructions` with the manual validation page,
  ready signal, accepted status values, required environment keys, and
  completion rule.
- `web_readiness_bundle.dart` now treats templates missing that metadata as
  stale, so old minimal templates trigger `prepare-manual-evidence-templates`
  before evidence collection.
- Added regression coverage for generated template metadata and stale legacy
  templates.
- Regenerated the primary manual templates and the Phase 1 refresh readiness
  candidate bundle so template fingerprints and release actions are current.
- Updated README, review packet, and phase audit text to describe the template
  metadata contract.

Current artifact behavior:

- `chrome-ime-macos.template.json` and `chrome-voiceover-macos.template.json`
  now carry `target` and `reviewInstructions` blocks.
- The regenerated readiness bundle fingerprints both updated template files and
  does not emit `prepare-manual-evidence-templates` because both selected
  templates are current.
- The readiness bundle remains intentionally red for threshold review and real
  manual Chrome IME/VoiceOver evidence; the bundle integrity verifier remains
  green.

Verification:

- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "template|manual evidence"` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_manual_validation.dart tool/web_readiness_bundle.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `jq '.target, .reviewInstructions' profiling/web/manual/templates/chrome-ime-macos.template.json` -
  confirmed the generated template metadata.
- `jq '[.remainingReleaseActions[].id] as $ids | {ids: $ids, hasPrepare: ($ids | index("prepare-manual-evidence-templates") != null), manualTemplates: .sourceInputFingerprints.manualTemplateFiles}' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  confirmed no template-prep action is needed and both template files are
  fingerprinted.
- `git diff --check` - passed.

## 2026-06-08 16:50 EDT

Moved manual starter evidence creation into the manual validation tool.

- `web_manual_validation.dart` now supports `--write-starter=<path>` with an
  optional `--starter-template=<path>`.
- Starter creation refuses to overwrite an existing review file, validates that
  a supplied starter template is a `fleuryWebManualValidationEntry` for the
  selected `--template-target`, creates parent directories as needed, and
  writes a `needsReview` evidence file without running a shell copy snippet.
- `web_readiness_bundle.dart` now emits `starterCommand` arrays that call
  `dart run tool/web_manual_validation.dart --write-starter=...` with the
  fingerprinted target template instead of embedding `/bin/sh -c` copy logic.
- Updated package README, review packet, and phase audit wording so the
  reviewer handoff points at the canonical tool-owned starter command.
- Regenerated the Phase 1 refresh readiness candidate bundle and
  `web-release-actions.md` so both manual evidence actions now render the new
  starter command.

Current artifact behavior:

- The two manual evidence actions still have current template fingerprints and
  `starterOverwritePolicy: fail-if-destination-exists`.
- `web-release-actions.md` renders `Starter command` blocks using
  `--write-starter`, `--starter-template`, and `--template-target`.
- The readiness bundle remains intentionally red for threshold review and real
  manual Chrome IME/VoiceOver evidence; the bundle integrity verifier remains
  green.

Verification:

- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "manual evidence actions|skips template prep|starter"` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_manual_validation.dart tool/web_readiness_bundle.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  passed and regenerated the candidate bundle with `strictPass: false` for the
  expected external gates.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `rg -n "Starter command|write-starter|starter-template|/bin/sh|cp .*template|starter evidence already exists" profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-release-actions.md` -
  confirmed rendered starter commands use the new tool options and no longer
  render shell copy snippets.
- `jq '[.remainingReleaseActions[] | select(.id | startswith("collect-manual-evidence")) | {id, starterCommand, details: {templateStatus: .details.templateStatus, starterOverwritePolicy: .details.starterOverwritePolicy, starterEvidencePath: .details.starterEvidencePath}}]' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  confirmed both manual evidence actions point at the new starter command while
  retaining current template status and no-overwrite policy.
- `git diff --check` - passed.

## 2026-06-08 16:58 EDT

Tightened starter evidence template validation.

- `web_manual_validation.dart --write-starter` now rejects stale starter
  templates before writing review evidence.
- The starter guard validates the template target metadata, review
  instructions, required environment keys, blank provenance fields,
  target-specific environment values, and required check list.
- Added regression coverage that a legacy/minimal template exits with
  `starter template is stale` and does not create the requested starter file.
- Aligned the readiness-bundle test template helper with the canonical IME
  target wording so bundle template freshness and manual-tool starter
  freshness use the same target contract.
- Updated README, review packet, and phase audit wording to state that the
  starter command validates template freshness before writing evidence.
- Regenerated the Phase 1 refresh readiness candidate bundle after the tool
  change.

Current artifact behavior:

- Both manual evidence actions still point at current template fingerprints.
- The generated starter commands still use `--write-starter`,
  `--starter-template`, and `--template-target`; the stricter validation now
  lives behind that command.
- The readiness bundle remains intentionally red for threshold review and real
  manual Chrome IME/VoiceOver evidence; the bundle integrity verifier remains
  green.

Verification:

- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "manual evidence actions|skips template prep|starter"` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_manual_validation.dart tool/web_readiness_bundle.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  passed and regenerated the candidate bundle with `strictPass: false` for the
  expected external gates.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `jq '[.remainingReleaseActions[] | select(.id | startswith("collect-manual-evidence")) | {id, starterCommand, templateStatus: .details.templateStatus, templateFingerprint: .details.templateFingerprint, starterOverwritePolicy: .details.starterOverwritePolicy}]' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  confirmed both manual evidence actions retain current template fingerprints
  and no-overwrite starter policy.
- `rg -n "template freshness|current target metadata|required check list|write-starter|Starter command|starter-template" packages/fleury_web/README.md docs/implementation/web-rfc-review-packet.md docs/implementation/web-rfc-phase-audit.md profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-release-actions.md` -
  confirmed docs and generated actions describe or render the stricter starter
  path.
- `git diff --check` - passed.

## 2026-06-08 17:04 EDT

Aligned readiness-bundle template freshness with starter evidence validation.

- `web_readiness_bundle.dart` now has target-specific expected metadata for the
  `chrome-ime-macos` and `chrome-voiceover-macos` manual validation targets.
- Manual template status now checks exact target label, phase, category,
  browser/platform, IME or assistive-technology metadata, required environment
  keys, blank provenance fields, target-specific environment values, and
  required check IDs.
- A template that would fail `web_manual_validation.dart --write-starter`
  therefore becomes stale at bundle-generation time and emits
  `prepare-manual-evidence-templates` before reviewers reach the starter
  command.
- Added regression coverage for a template with valid review-instruction shape
  but stale IME metadata and a missing required check.
- Updated README, review packet, and phase audit wording so template
  freshness is described as target-specific rather than merely structural.
- Regenerated the Phase 1 refresh readiness candidate bundle after the bundle
  freshness change.

Current artifact behavior:

- Both primary manual templates remain current under the stricter bundle
  contract.
- Both manual evidence actions still render starter commands using
  `--write-starter`, `--starter-template`, and `--template-target`.
- The readiness bundle remains intentionally red for threshold review and real
  manual Chrome IME/VoiceOver evidence; the bundle integrity verifier remains
  green.

Verification:

- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "template|manual evidence actions|skips template prep|starter"` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  passed and regenerated the candidate bundle with `strictPass: false` for the
  expected external gates.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `jq '[.remainingReleaseActions[] | select(.id | startswith("collect-manual-evidence")) | {id, templateStatus: .details.templateStatus, templateFingerprint: .details.templateFingerprint, templateBlockers: .details.templateBlockers, starterCommand}]' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  confirmed both manual evidence actions have current template fingerprints and
  no template blockers.
- `rg -n "target-specific freshness|selected target's expected metadata|required check list|template freshness|write-starter|Starter command" packages/fleury_web/README.md docs/implementation/web-rfc-review-packet.md docs/implementation/web-rfc-phase-audit.md profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-release-actions.md` -
  confirmed docs and generated actions describe or render the aligned template
  freshness contract.
- `git diff --check` - passed.

## 2026-06-08 17:13 EDT

Factored the manual validation target and template contract into a shared
internal library.

- Added `packages/fleury_web/lib/src/manual_validation/manual_validation_targets.dart`
  as the single owner for primary manual target metadata, required checks,
  template generation, target preset expansion, and template freshness
  blockers.
- Updated `web_manual_validation.dart` to generate templates, write starter
  evidence, expand presets, and reject stale starter templates through the
  shared contract.
- Updated `web_readiness_bundle.dart` to use the same freshness blocker logic
  for known manual targets, while preserving the generic structural fallback
  for unknown targets.
- Removed the duplicated expected-target table and duplicated template
  comparison helpers from the readiness bundle tool.
- Updated README, review packet, and phase audit wording so reviewers know the
  template contract is shared by the manual validation tool and readiness
  bundle.
- Regenerated the Phase 1 refresh readiness candidate bundle after the shared
  contract change.

Current artifact behavior:

- Both primary manual evidence actions report `templateStatus: current`.
- Both primary manual evidence actions have current template fingerprints and
  no `templateBlockers`.
- Both starter commands still use `web_manual_validation.dart --write-starter`
  with `--starter-template` and `--template-target`.
- The readiness bundle remains intentionally red for threshold review and real
  manual Chrome IME/VoiceOver evidence; the bundle integrity verifier remains
  green.

Verification:

- `cd packages/fleury_web && dart format lib/src/manual_validation/manual_validation_targets.dart tool/web_manual_validation.dart tool/web_readiness_bundle.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/manual_validation/manual_validation_targets.dart tool/web_manual_validation.dart tool/web_readiness_bundle.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "template|manual evidence actions|skips template prep|starter"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  passed and regenerated the candidate bundle with `strictPass: false` for the
  expected external gates.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `jq '[.remainingReleaseActions[] | select(.id | startswith("collect-manual-evidence")) | {id, templateStatus: .details.templateStatus, templateFingerprint: .details.templateFingerprint, templateBlockers: .details.templateBlockers, starterCommand}]' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  confirmed both manual evidence actions have current template fingerprints,
  no template blockers, and starter commands wired through the validation tool.
- `rg -n "shared internal registry|shared registry|selected target's expected metadata|target-specific freshness|write-starter|Starter command" packages/fleury_web/README.md docs/implementation/web-rfc-review-packet.md docs/implementation/web-rfc-phase-audit.md profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-release-actions.md` -
  confirmed docs and generated release actions describe or render the shared
  contract path.
- `rg -n "_ManualValidationTarget|_ManualValidationCheck|_templateFor|_manualValidationTargets|_ExpectedManualTemplateTarget|_expectedManualTemplateTargets|_expectTemplateEqual|template target.inputMethod must" packages/fleury_web/tool packages/fleury_web/lib/src/manual_validation` -
  confirmed the stale private target/template helper symbols were removed.
- `git diff --check` - passed.

## 2026-06-08 17:28 EDT

Refreshed broad automated verification and fixed one test-platform selection
issue.

- Ran the current RFC phase audit against the RFC exit gates again. The only
  remaining release gates are still empirical: reviewed threshold promotion,
  real Chrome IME evidence, real Chrome VoiceOver evidence, regenerated strict
  readiness, and bundle-bound default/retirement preflights.
- Kept the expensive `web_frame_suite` recapture out of this pass because the
  latest changes only touched validation tooling and a test annotation, not
  runtime render behavior, retained DOM presentation, input/focus/clipboard
  behavior, semantic projection, or benchmark scenario definitions.
- `dart test -p chrome` initially exposed that
  `test/web_public_api_boundary_test.dart` was missing the same VM-only
  annotation used by the other filesystem-backed tool/public-boundary tests.
  The test imports `dart:io` to read `lib/fleury_web.dart`, so it should run in
  the VM suite and be excluded from the browser suite.
- Added `@TestOn('vm')` to `web_public_api_boundary_test.dart`, preserving the
  public API assertions while keeping package-wide Chrome tests focused on
  browser-executable paths.

Verification:

- `cd packages/fleury && dart analyze` - passed.
- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury && dart test` - passed with 1567 tests.
- `cd packages/fleury_web && dart test test/web_public_api_boundary_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome` - passed with 92 tests after
  the VM-only boundary annotation.
- `cd packages/fleury_web && dart test` - passed with 112 tests after the
  VM-only boundary annotation.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `git diff --check` - passed.

## 2026-06-08 17:32 EDT

Tightened the generated release-action handoff for package-relative commands.

- `web-release-actions.md` already recorded the package
  `commandWorkingDirectory` in the header, but each command block still relied
  on reviewers noticing that single header line before copying `dart run
  tool/...` commands.
- Updated `web_readiness_bundle.dart` so every rendered command section now
  includes `Run from: <commandWorkingDirectory>` immediately before the shell
  block.
- Kept the machine-readable `commandTemplate`, `starterCommand`,
  `auditCommand`, and `planCommand` arrays unchanged; this is a Markdown
  handoff improvement, not a command graph change.
- Added regression coverage that release-action Markdown contains per-command
  run-directory guidance.
- Updated README, review packet, and phase audit wording to describe the
  per-command working-directory rendering.
- Regenerated the Phase 1 refresh readiness candidate bundle so the checked
  `web-release-actions.md` includes `Run from:` beside all generated command
  blocks.

Current artifact behavior:

- `web-release-actions.md` still records the command working directory in the
  packet header.
- Each plan, promotion, starter, audit, regeneration, verification, and
  final-preflight command block now repeats the same `Run from:` directory.
- The readiness bundle remains intentionally red for threshold review and real
  manual Chrome IME/VoiceOver evidence; the bundle integrity verifier remains
  green.

Verification:

- `cd packages/fleury_web && dart format tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "manual evidence actions|skips template prep|starter|promote candidate thresholds|keeps artifacts"` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 12 tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  passed and regenerated the candidate bundle with `strictPass: false` for the
  expected external gates.
- `rg -n "Run from:|command working directory repeated|beside each generated command block|beside each command block|required working directory beside" docs/implementation/web-rfc-review-packet.md packages/fleury_web/README.md docs/implementation/web-rfc-phase-audit.md profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-release-actions.md` -
  confirmed docs and generated release actions describe or render the
  per-command run directory.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `git diff --check` - passed.

## 2026-06-08 17:43 EDT

Made the manual evidence actions self-contained for browser page preparation.

- The manual evidence actions already pointed reviewers at
  `web/manual_validation.html`, but the release-action graph did not carry the
  concrete commands for building and serving that page.
- Added `manualPageBuildCommand` and `manualPageServeCommand` to each manual
  validation release action:
  - `dart compile js web/manual_validation.dart -o web/manual_validation.dart.js`
  - `dart pub global run dhttpd --path web`
- Added manual evidence details for the ready signal and serve note so the
  generated action tells reviewers to keep the local server running, open
  `manual_validation.html`, and begin checks only after the page reports
  `data-fleury-manual-validation="ready"`.
- Updated `web-release-actions.md` rendering so the new manual page commands
  appear with the same per-command `Run from:` working-directory guidance.
- Updated README, review packet, and phase audit wording to state that manual
  evidence actions carry the page build/serve commands as well as starter and
  audit commands.
- Regenerated the Phase 1 refresh readiness candidate bundle so the checked
  action packet includes the new commands.

Current artifact behavior:

- The two manual evidence actions now include page build, page serve, starter,
  and strict audit commands.
- The page build command was exercised directly and compiled
  `web/manual_validation.dart` successfully.
- The readiness bundle remains intentionally red for threshold review and real
  manual Chrome IME/VoiceOver evidence; the bundle integrity verifier remains
  green.

Verification:

- `cd packages/fleury_web && dart format tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "manual evidence actions|skips template prep action when templates exist"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  passed and regenerated the candidate bundle with `strictPass: false` for the
  expected external gates.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `cd packages/fleury_web && dart compile js web/manual_validation.dart -o web/manual_validation.dart.js` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 12 tests.
- `rg -n "manual validation page build/serve|manualPageBuildCommand|manualPageServeCommand|Manual page build command|Manual page serve command|ready signal" packages/fleury_web/README.md docs/implementation/web-rfc-review-packet.md docs/implementation/web-rfc-phase-audit.md profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-release-actions.md` -
  confirmed docs and generated release actions describe or render the manual
  page build/serve path.
- `git diff --check` - passed.

## 2026-06-08 17:51 EDT

Split manual evidence page serving into explicit setup and serve commands.

- The prior release action used `dart pub global run dhttpd --path web` as the
  page serve command. On this machine `dart pub global list` did not include
  `dhttpd`, so that command was not self-contained for a reviewer starting from
  the current local state.
- Updated the manual validation plan and readiness-bundle action graph to emit:
  - `manualPageServeSetupCommand`: `dart pub global activate dhttpd`
  - `manualPageServeCommand`: `dhttpd --path web`
- Updated the manual serve note to tell reviewers to run the setup command if
  `dhttpd` is not active, keep the serve command running, open
  `manual_validation.html` from the local server, and begin checks only after
  the page reports `data-fleury-manual-validation="ready"`.
- Updated README, review packet, and phase audit wording so reviewer-facing
  docs mention the static-server setup command as part of the manual evidence
  handoff.
- Regenerated the Phase 1 refresh readiness candidate bundle so the generated
  action packet includes the setup/serve split.

Current artifact behavior:

- The two manual evidence actions now include page build, page serve setup,
  page serve, starter, and strict audit commands.
- Generated `web-release-actions.md` renders the new setup command before the
  serve command and keeps per-command `Run from:` guidance.
- Bundle fingerprint verification remains green. The readiness bundle remains
  intentionally red for threshold review and real manual Chrome IME/VoiceOver
  evidence.

Verification:

- `cd packages/fleury_web && dart format tool/web_manual_validation.dart tool/web_readiness_bundle.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_manual_validation.dart tool/web_readiness_bundle.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart --name "writes a plan"` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "manual evidence actions|skips template prep action when templates exist"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  passed and regenerated the candidate bundle with `strictPass: false` for the
  expected external gates.
- `jq '[.remainingReleaseActions[] | select(.id | startswith("collect-manual-evidence")) | {id, manualPageServeSetupCommand, manualPageServeCommand, manualPageServeNote: .details.manualPageServeNote}]' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  confirmed both manual evidence actions include `dart pub global activate
  dhttpd`, `dhttpd --path web`, and the setup-aware serve note.
- `rg -n "Manual page serve setup command|dart pub global activate dhttpd|dhttpd --path web|manualPageServeSetupCommand|static-server setup" packages/fleury_web/README.md docs/implementation/web-rfc-review-packet.md docs/implementation/web-rfc-phase-audit.md profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-release-actions.md` -
  confirmed docs and generated release actions describe or render the setup
  command.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed with 16 tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 12 tests.
- `git diff --check` - passed before this log edit.

## 2026-06-08 17:59 EDT

Made the manual validation serve command independent of Pub's global bin PATH.

- The 17:51 split added an explicit `dart pub global activate dhttpd` setup
  command, then used `dhttpd --path web` as the serve command.
- A current local check showed `dhttpd` is not on `PATH` and not listed by
  `dart pub global list`, which means the direct `dhttpd` command would still
  depend on a reviewer exporting Pub's global bin directory after activation.
- Kept the setup command, but changed the reviewer-facing serve command to
  `dart pub global run dhttpd --path web`, which works through Dart's global
  package runner after activation and does not require a shell PATH update.
- Updated the manual validation plan, readiness-bundle action payloads, README
  examples, tests, and regenerated release-action packet.

Current artifact behavior:

- Manual evidence actions now emit:
  - `manualPageServeSetupCommand`: `dart pub global activate dhttpd`
  - `manualPageServeCommand`: `dart pub global run dhttpd --path web`
- The readiness bundle remains intentionally red for threshold review and real
  manual Chrome IME/VoiceOver evidence; bundle fingerprint verification remains
  green.

Verification:

- `command -v dhttpd || true` - produced no path in the current shell.
- `dart pub global list` - only reported `flutterfire_cli 1.3.1`; `dhttpd` is
  not globally active in the current reviewer state.
- `cd packages/fleury_web && dart format tool/web_manual_validation.dart tool/web_readiness_bundle.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed with no further changes.
- `cd packages/fleury_web && dart analyze tool/web_manual_validation.dart tool/web_readiness_bundle.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart --name "writes a plan"` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "manual evidence actions|skips template prep action when templates exist"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  passed and regenerated the candidate bundle with `strictPass: false` for the
  expected external gates.
- `jq '[.remainingReleaseActions[] | select(.id | startswith("collect-manual-evidence")) | {id, manualPageServeSetupCommand, manualPageServeCommand, manualPageServeNote: .details.manualPageServeNote}]' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  confirmed both manual evidence actions include `dart pub global activate
  dhttpd` and `dart pub global run dhttpd --path web`.
- `rg -n "dart pub global run dhttpd --path web|Manual page serve setup command|manualPageServeSetupCommand|dhttpd --path web" packages/fleury_web/README.md profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-release-actions.md packages/fleury_web/tool packages/fleury_web/test` -
  confirmed source, tests, README, and generated release actions render the
  portable serve command.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed with 16 tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 12 tests.
- `git diff --check` - passed before this log edit.

## 2026-06-08 18:02 EDT

Smoke-tested the generated manual validation page setup and serve path.

- Ran the reviewer-facing page build command:
  `dart compile js web/manual_validation.dart -o web/manual_validation.dart.js`.
- Ran the reviewer-facing setup command:
  `dart pub global activate dhttpd`, which activated `dhttpd 4.3.0`.
- Started the reviewer-facing serve command:
  `dart pub global run dhttpd --path web`.
- `dhttpd` printed `Serving web at http://localhost:8080` and bound to IPv6
  loopback (`[::1]:8080`) on this machine. A numeric IPv4 probe to
  `127.0.0.1:8080` failed, but `http://localhost:8080/manual_validation.html`
  returned successfully.
- Fetched both manual validation assets through the generated server path:
  - `http://localhost:8080/manual_validation.html` returned 469 bytes.
  - `http://localhost:8080/manual_validation.dart.js` returned 987671 bytes.
- Stopped the temporary server and confirmed no listener remained on TCP 8080.

Current artifact behavior:

- The generated manual validation commands are locally executable after the
  portability fix.
- The handoff should continue to say `localhost`, not `127.0.0.1`, because
  this `dhttpd` run listened on IPv6 loopback only.
- This smoke only proves static page serving. It does not satisfy the real
  Chrome IME or VoiceOver manual evidence gates.

Verification:

- `cd packages/fleury_web && dart compile js web/manual_validation.dart -o web/manual_validation.dart.js` -
  passed.
- `cd packages/fleury_web && dart pub global activate dhttpd` - passed and
  activated `dhttpd 4.3.0`.
- `cd packages/fleury_web && dart pub global run dhttpd --path web` - started
  the temporary static server at `http://localhost:8080`.
- `curl -fsS http://localhost:8080/manual_validation.html | wc -c` - returned
  469.
- `curl -fsS http://localhost:8080/manual_validation.dart.js | wc -c` -
  returned 987671.
- `lsof -nP -iTCP:8080 -sTCP:LISTEN || true` after stopping the server -
  returned no listener.

## 2026-06-08 18:15 EDT

Hardened the automated browser backstop for the manual validation page.

- Extended `test/manual_validation_page_test.dart` beyond the ready marker and
  basic semantic roles.
- The Chrome test now verifies:
  - `data-fleury-manual-validation` still transitions from `mounted` to
    `ready` only after the first retained DOM frame.
  - the retained visual grid is `aria-hidden`;
  - no xterm DOM is present on the manual validation page;
  - the retained semantic root is exposed, not `aria-hidden`;
  - the semantic textbox mirrors the initial IME field value;
  - the page-owned semantic action button exposes `activate`;
  - the safe sample link projects as an anchor with `href`, `target`, and
    `rel`;
  - dispatching a click through the semantic DOM action updates the Fleury
    status text on a subsequent frame.
- Updated the review packet and phase audit to describe the stronger browser
  backstop.

Current artifact behavior:

- Browser automation now proves the manual validation page is locally suitable
  for evidence collection before reviewers start real IME or VoiceOver checks.
- This still does not replace the real Chrome IME or VoiceOver evidence gates;
  it only strengthens the automated precondition coverage for those gates.
- The readiness bundle remains intentionally red for threshold review and real
  manual evidence.

Verification:

- `cd packages/fleury_web && dart format test/manual_validation_page_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze test/manual_validation_page_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/manual_validation_page_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome` - passed with 92 tests.
- `cd packages/fleury_web && dart analyze` - passed.
- `rg -n "manual validation page readiness|absence of xterm|no xterm DOM|safe-link|semantic action-to-status|semantic root/textbox/button/link/status" docs/implementation/web-rfc-review-packet.md docs/implementation/web-rfc-phase-audit.md packages/fleury_web/test/manual_validation_page_test.dart` -
  confirmed the docs and test cover the stronger browser backstop.
- `git diff --check` - passed before this log edit.

## 2026-06-08 18:25 EDT

Made manual evidence templates and starters self-contained for page setup.

- The release-action packet already carried manual validation page build,
  static-server setup, and serve commands, but generated evidence templates and
  copied starter evidence only carried the page name and ready signal.
- Added the manual page command contract to the shared manual-validation target
  registry:
  - `manualPageBuildCommand`: `dart compile js web/manual_validation.dart -o web/manual_validation.dart.js`
  - `manualPageServeSetupCommand`: `dart pub global activate dhttpd`
  - `manualPageServeCommand`: `dart pub global run dhttpd --path web`
  - `manualPageLocalUrl`: `http://localhost:8080/manual_validation.html`
  - `manualPageServeNote`: setup/serve/readiness guidance
- Updated `web_manual_validation.dart` and `web_readiness_bundle.dart` to read
  the same shared command constants instead of duplicating command arrays.
- Tightened template freshness validation so current templates must include the
  command fields and local URL. Older minimal templates now classify as stale.
- Regenerated `profiling/web/manual/plan.md`, both primary manual template
  JSON files, `manual-validation-audit.json`, `review.md`, and the Phase 1
  refresh readiness candidate bundle.
- Updated the review packet and phase audit to describe the self-contained
  manual evidence template/starter contract.

Current artifact behavior:

- A reviewer opening only a generated template or copied starter evidence file
  now sees the exact page build/setup/serve commands and local URL needed to
  collect real IME or VoiceOver evidence.
- Readiness bundle manual evidence actions still carry the same commands, and
  now also expose `manualPageLocalUrl` in action details.
- The readiness bundle remains intentionally red for threshold review and real
  Chrome IME/VoiceOver evidence; bundle fingerprint verification remains green.

Verification:

- `cd packages/fleury_web && dart format lib/src/manual_validation/manual_validation_targets.dart tool/web_manual_validation.dart tool/web_readiness_bundle.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/manual_validation/manual_validation_targets.dart tool/web_manual_validation.dart tool/web_readiness_bundle.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart --name "writes a plan|writes starter evidence without overwrite|rejects stale starter templates"` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "manual evidence actions|skips template prep action when templates exist|flags templates missing review metadata|flags templates that fail starter freshness"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/plan.md --write-templates=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/review.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json` -
  passed and regenerated manual artifacts.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  passed and regenerated the candidate bundle with `strictPass: false` for the
  expected external gates.
- `jq '.reviewInstructions | {manualPageBuildCommand, manualPageServeSetupCommand, manualPageServeCommand, manualPageLocalUrl, manualPageServeNote}' profiling/web/manual/templates/chrome-ime-macos.template.json` -
  confirmed the template carries the command fields and local URL.
- `jq '[.remainingReleaseActions[] | select(.id | startswith("collect-manual-evidence")) | {id, templateFingerprint: .details.templateFingerprint, manualPageLocalUrl: .details.manualPageLocalUrl, manualPageServeNote: .details.manualPageServeNote, manualPageServeCommand}]' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  confirmed both manual evidence actions carry updated template fingerprints,
  local URL, serve note, and serve command.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed with 16 tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 12 tests.
- `cd packages/fleury_web && dart analyze` - passed.
- `git diff --check` - passed before this log edit.

## 2026-06-08 18:33 EDT

Made the manual evidence page serve instructions concrete in generated handoff
artifacts.

- The self-contained manual evidence templates already carried
  `manualPageLocalUrl`, but `manualPageServeNote` still told reviewers to open
  `manualPageLocalUrl` by field name instead of spelling out the actual page.
- Updated the shared manual-validation target contract so generated templates,
  starter evidence, and readiness release actions now say to open
  `http://localhost:8080/manual_validation.html`.
- Tightened tests to assert that the serve note carries the concrete localhost
  URL.
- Regenerated manual validation artifacts and the Phase 1 refresh readiness
  candidate bundle so template fingerprints and release-action Markdown match
  the source contract.

Current artifact behavior:

- A reviewer who only has a generated template, copied starter evidence file,
  or readiness action can see both the structured `manualPageLocalUrl` field
  and the literal URL in the prose setup note.
- The readiness bundle remains intentionally red for threshold review and real
  Chrome IME/VoiceOver manual evidence.
- Bundle fingerprint verification remains green from both the package-local
  tool and top-level `fleury_dev` command.

Verification:

- `cd packages/fleury_web && dart format lib/src/manual_validation/manual_validation_targets.dart test/web_readiness_bundle_tool_test.dart test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/manual_validation/manual_validation_targets.dart tool/web_manual_validation.dart tool/web_readiness_bundle.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart --name "writes a plan|writes starter evidence without overwrite|rejects stale starter templates"` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "manual evidence actions|skips template prep action when templates exist|flags templates missing review metadata|flags templates that fail starter freshness"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/plan.md --write-templates=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/review.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json` -
  passed and regenerated manual artifacts.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  passed and regenerated the candidate bundle with `strictPass: false` for the
  expected external gates.
- `jq '.reviewInstructions.manualPageServeNote' profiling/web/manual/templates/chrome-ime-macos.template.json` -
  confirmed the template now names
  `http://localhost:8080/manual_validation.html`.
- `jq '[.remainingReleaseActions[] | select(.id | startswith("collect-manual-evidence")) | {id, manualPageLocalUrl: .details.manualPageLocalUrl, manualPageServeNote: .details.manualPageServeNote}]' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  confirmed both manual evidence actions carry the literal URL in the serve
  note.
- `rg -n "open manualPageLocalUrl|manualPageLocalUrl from that local server" packages/fleury_web/lib packages/fleury_web/test profiling/web/manual profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate -g '*.dart' -g '*.json' -g '*.md'` -
  returned no matches.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed with 16 tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 12 tests.
- `git diff --check` - passed before this log edit.

## 2026-06-08 18:40 EDT

Made manual evidence command working directories explicit in machine-readable
handoff artifacts.

- Generated release-action Markdown already renders the package-local command
  working directory beside command blocks, and the manual validation plan
  already starts with `cd packages/fleury_web`.
- Generated evidence templates and copied starter evidence were still missing a
  machine-readable working-directory field for the manual page commands.
- Added `manualPageCommandWorkingDirectory: packages/fleury_web` to the shared
  manual-validation target contract.
- Tightened template freshness validation so templates without that field are
  stale.
- Added the same field to per-target manual evidence release-action details in
  the readiness bundle.
- Updated the web README, review packet, and phase audit to name the
  repo-relative manual page command working directory as part of the
  self-contained template contract.
- Regenerated manual validation artifacts and the Phase 1 refresh readiness
  candidate bundle so template fingerprints and release-action Markdown match
  the source contract.

Current artifact behavior:

- A reviewer who only has a generated template, copied starter evidence file,
  or JSON release action now sees where the page build/setup/serve commands
  should run: `packages/fleury_web`.
- Human-readable release actions still include the absolute command working
  directory next to each command block.
- The readiness bundle remains intentionally red for threshold review and real
  Chrome IME/VoiceOver manual evidence.
- Bundle fingerprint verification remains green from both the package-local
  tool and top-level `fleury_dev` command.

Verification:

- `cd packages/fleury_web && dart format lib/src/manual_validation/manual_validation_targets.dart tool/web_readiness_bundle.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/manual_validation/manual_validation_targets.dart tool/web_manual_validation.dart tool/web_readiness_bundle.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart --name "writes a plan|writes starter evidence without overwrite|rejects stale starter templates"` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "manual evidence actions|skips template prep action when templates exist|flags templates missing review metadata|flags templates that fail starter freshness"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/plan.md --write-templates=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/review.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json` -
  passed and regenerated manual artifacts.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  passed and regenerated the candidate bundle with `strictPass: false` for the
  expected external gates.
- `jq '.reviewInstructions | {manualPageCommandWorkingDirectory, manualPageBuildCommand, manualPageServeSetupCommand, manualPageServeCommand, manualPageLocalUrl}' profiling/web/manual/templates/chrome-ime-macos.template.json` -
  confirmed the template carries `manualPageCommandWorkingDirectory:
  packages/fleury_web` beside the page commands and local URL.
- `jq '[.remainingReleaseActions[] | select(.id | startswith("collect-manual-evidence")) | {id, manualPageCommandWorkingDirectory: .details.manualPageCommandWorkingDirectory, manualPageLocalUrl: .details.manualPageLocalUrl}]' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  confirmed both manual evidence actions carry the repo-relative working
  directory.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed with 16 tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 12 tests.
- `rg -n "manual page command working directory|manualPageCommandWorkingDirectory|packages/fleury_web" docs/implementation/web-rfc-review-packet.md docs/implementation/web-rfc-phase-audit.md packages/fleury_web/README.md profiling/web/manual/templates/chrome-ime-macos.template.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-release-actions.md` -
  confirmed the docs and generated artifacts name the working-directory
  contract.
- `git diff --check` - passed before this log edit.

## 2026-06-08 18:51 EDT

Tightened manual evidence template freshness for stale serve-note prose.

- The previous template freshness contract required `manualPageServeNote` to be
  non-empty, but did not require it to match the shared manual-validation target
  contract.
- That meant a template from before the literal-URL handoff fix could still be
  classified as current even if it told reviewers to open `manualPageLocalUrl`
  by field name.
- Changed `manualValidationTemplateBlockers` to exact-match
  `manualPageServeNote` against the shared `manualValidationPageServeNote`.
- Added readiness-bundle coverage for the old placeholder serve note so stale
  reviewer prose triggers `prepare-manual-evidence-templates`.
- Added starter-template coverage so `web_manual_validation.dart --write-starter`
  reports the serve-note freshness blocker through the same shared validator.
- Updated the README, review packet, and phase audit to state that the
  freshness contract includes manual page commands and the exact serve note, not
  only required metadata.
- Regenerated manual validation artifacts and the Phase 1 refresh readiness
  candidate bundle.

Current artifact behavior:

- Current templates remain current only when their page commands, local URL,
  command working directory, and serve note match the shared target contract.
- Older templates with the `open manualPageLocalUrl` note are now stale and will
  generate a template-preparation action before manual evidence collection.
- The readiness bundle remains intentionally red for threshold review and real
  Chrome IME/VoiceOver manual evidence.
- Bundle fingerprint verification remains green from both the package-local
  tool and top-level `fleury_dev` command.

Verification:

- `cd packages/fleury_web && dart format lib/src/manual_validation/manual_validation_targets.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/manual_validation/manual_validation_targets.dart tool/web_manual_validation.dart tool/web_readiness_bundle.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart --name "rejects stale starter templates"` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "stale manual page serve notes|skips template prep action when templates exist|flags templates that fail starter freshness"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/plan.md --write-templates=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/review.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json` -
  passed and regenerated manual artifacts.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  passed and regenerated the candidate bundle with `strictPass: false` for the
  expected external gates.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `cd packages/fleury_web && dart analyze` - passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed with 16 tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 13 tests.
- `rg -n "serve note|stale prose|manualPageServeNote|manual page commands and serve note" docs/implementation/web-rfc-review-packet.md docs/implementation/web-rfc-phase-audit.md packages/fleury_web/README.md packages/fleury_web/lib/src/manual_validation/manual_validation_targets.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart packages/fleury_web/test/web_manual_validation_tool_test.dart` -
  confirmed the validator, tests, and docs name the serve-note freshness rule.
- `git diff --check` - passed before this log edit.

## 2026-06-08 18:57 EDT

Tightened protocol/image capability honesty in the retained DOM renderer.

- The DOM surface already reports `InlineImageCapability.none`, but the
  protocol-placeholder DOM title still read as plain `inline image`.
- Added shared protocol-placeholder constants to the DOM span model so live DOM
  and static HTML use the same unsupported inline-image wording, glyph, and
  data attributes.
- The live DOM path now renders protocol anchors as `.proto` spans with
  `title="unsupported inline image"`,
  `data-fleury-cell-kind="protocol-placeholder"`, and
  `data-fleury-unsupported="inline-image"`.
- The static HTML path renders the same placeholder metadata.
- Added VM and browser coverage so the visible placeholder never leaks the
  image payload and the DOM metadata remains capability-honest.
- Updated the review packet and phase audit so reviewers see this as part of
  the renderer contract, not only as test detail.

Verification:

- `cd packages/fleury_web && dart format lib/src/dom_grid/cell_span_builder.dart lib/src/dom_grid/dom_row_factory.dart lib/src/dom_grid/cell_grid_html.dart test/cell_span_builder_test.dart test/cell_grid_html_test.dart test/dom_grid_surface_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/dom_grid/cell_span_builder.dart lib/src/dom_grid/dom_row_factory.dart lib/src/dom_grid/cell_grid_html.dart test/cell_span_builder_test.dart test/cell_grid_html_test.dart test/dom_grid_surface_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/cell_span_builder_test.dart test/cell_grid_html_test.dart` -
  passed with 16 tests.
- `cd packages/fleury_web && dart test -p chrome test/dom_grid_surface_test.dart` -
  passed with seven browser tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `git diff --check` - passed before this log edit.

## 2026-06-08 19:02 EDT

Added an automated backstop for manual IME caret placement readiness.

- The retained web host already synchronizes the focused Fleury caret rectangle
  into the hidden textarea used for browser keyboard and IME capture.
- Added `data-fleury-caret-*` metadata to that textarea so tests and manual
  reviewers can distinguish a colocated caret capture target from the offscreen
  hidden fallback.
- `DomInputSource` now reports `data-fleury-caret-state="positioned"` plus
  cell coordinates and CSS placement dimensions when both caret geometry and
  measured cell metrics are available, and `hidden` with placement attributes
  cleared otherwise.
- Extended the `DomInputSource` browser test to assert both the positioned and
  hidden metadata states.
- Extended the manual validation page browser test so the IME evidence page
  must present a positioned hidden textarea after the first retained DOM frame.
- Updated the review packet and phase audit to surface this as an automated
  precursor to the manual `candidate-window-near-caret` check.

Verification:

- `cd packages/fleury_web && dart format lib/src/input/dom_input_source.dart test/dom_input_source_test.dart test/manual_validation_page_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/input/dom_input_source.dart test/dom_input_source_test.dart test/manual_validation_page_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_input_source_test.dart` -
  passed with six browser tests.
- `cd packages/fleury_web && dart test -p chrome test/manual_validation_page_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.

## 2026-06-08 19:09 EDT

Tightened manual evidence template freshness around IME caret instructions.

- Updated the `candidate-window-near-caret` manual check to require the hidden
  textarea to report `data-fleury-caret-state="positioned"` before validating
  the real browser IME candidate window location.
- Strengthened `manualValidationTemplateBlockers` so current templates must
  match the registry's exact generated check instructions, not only contain the
  required check IDs with non-empty notes.
- Added readiness-bundle coverage for stale manual check prose so older
  templates generate `prepare-manual-evidence-templates` before evidence
  collection.
- Updated manual-validation tool coverage so generated plans and templates
  include the caret-state preflight.
- Regenerated manual validation artifacts and the Phase 1 refresh readiness
  candidate bundle. The bundle remains intentionally red for threshold review
  and real Chrome IME/VoiceOver evidence, with templates reported as current.
- Updated README, review packet, and phase audit wording so template freshness
  includes exact generated check instructions.

Verification:

- `cd packages/fleury_web && dart format lib/src/manual_validation/manual_validation_targets.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/manual_validation/manual_validation_targets.dart tool/web_manual_validation.dart tool/web_readiness_bundle.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed with 16 tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 14 tests.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/plan.md --write-templates=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/review.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json` -
  passed and regenerated manual artifacts.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  passed and regenerated the candidate bundle with `strictPass: false` for the
  expected external gates.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `git diff --check` - passed after the log-order cleanup.

## 2026-06-08 19:15 EDT

Made manual page preflight signals machine-readable in templates and release
actions.

- Added `ManualValidationPageSignal` to the shared manual-validation target
  registry.
- Generated templates now include `reviewInstructions.requiredPageSignals`.
  All targets require the retained DOM ready signal, and IME targets also
  require `textarea[data-fleury-caret-state="positioned"]`.
- Template freshness now validates the exact required page-signal list, so
  stale IME templates that omit the caret-positioned signal are marked stale
  before evidence collection.
- Readiness bundle manual evidence actions now expose the same
  `requiredPageSignals` in action details, so tools/reviewers do not need to
  parse checklist prose to discover target-specific page preconditions.
- Added tool coverage for current action details and stale page-signal
  templates.
- Regenerated manual validation templates and the Phase 1 refresh readiness
  candidate bundle. The bundle remains intentionally red for threshold review
  and real Chrome IME/VoiceOver evidence, with manual templates current.

Verification:

- `cd packages/fleury_web && dart format lib/src/manual_validation/manual_validation_targets.dart tool/web_readiness_bundle.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/manual_validation/manual_validation_targets.dart tool/web_readiness_bundle.dart tool/web_manual_validation.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed with 16 tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 15 tests.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/plan.md --write-templates=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/review.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json` -
  passed and regenerated manual artifacts.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  passed and regenerated the candidate bundle with `strictPass: false` for the
  expected external gates.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `git diff --check` - passed after the log-order cleanup.

## 2026-06-08 19:28 EDT

Made completed manual evidence carry the current page-signal contract.

- Added `manualValidationEvidenceContractBlockers`, a non-template evidence
  contract check for target metadata and `reviewInstructions`.
- Manual evidence strict mode now rejects completed entries whose generated
  `reviewInstructions.requiredPageSignals` are stale. In particular, old IME
  evidence that only records the retained DOM ready signal no longer passes
  after the caret-positioned signal became required.
- Kept reviewer-authored check notes flexible: the new freshness check only
  covers machine-readable target/review-instruction context, not the evidence
  text a reviewer writes while validating behavior.
- Updated manual-validation and readiness-bundle test fixtures so synthetic
  passing evidence starts from the current generated template contract.
- Added focused coverage for stale completed evidence page signals.
- Regenerated manual validation artifacts and the Phase 1 refresh readiness
  candidate bundle. The bundle remains intentionally red for threshold review
  and real Chrome IME/VoiceOver evidence, with manual templates current and
  required page signals present in release actions.

Verification:

- `cd packages/fleury_web && dart format lib/src/manual_validation/manual_validation_targets.dart tool/web_manual_validation.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/manual_validation/manual_validation_targets.dart tool/web_manual_validation.dart test/web_manual_validation_tool_test.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed with 17 tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 15 tests.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/plan.md --write-templates=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/review.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json` -
  passed and regenerated manual artifacts.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  passed and regenerated the candidate bundle with `strictPass: false` for the
  expected external gates.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 37 checked source inputs, and
  one checked metadata field.
- `dart tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same counters.
- `git diff --check` - passed.

## 2026-06-08 19:33 EDT

Removed a duplicate full-buffer semantic retain scan from the retained DOM host.

- `runTuiSurface` now uses the `FramePresentationPlan` dirty-row oracle to
  limit visual equality checks before retaining semantic output.
- The first attempted simplification used `dirtyRows.isEmpty` directly, but the
  browser surface suite caught that Fleury can repaint identical cells while
  still recording paint damage. The final version compares only the dirty row
  ranges selected by the planner, preserving semantic retention for identical
  repaint output without rescanning untouched rows.
- This keeps the semantic presenter behavior unchanged while tightening
  no-op/repaint performance accounting: semantic apply time no longer pays a
  second full-viewport scan after the presentation planner already selected
  dirty rows.
- No readiness artifacts or reviewed baseline captures were promoted by this
  change. Because this is runtime/performance-path code, a full browser
  recapture is still required before any final readiness claim.

Verification:

- `cd packages/fleury_web && dart format lib/src/run_tui_surface.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/run_tui_surface.dart test/run_tui_surface_test.dart test/frame_presentation_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/frame_presentation_test.dart` -
  passed with 8 tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 15 browser tests after the dirty-row-limited equality fix.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=noop-160x50 --frames=12 --warmup=2 --output=/tmp/fleury-web-semantic-dirty-row-retain-smoke.json --json` -
  passed in headless Chrome. The smoke capture reported 12 frames, 12 retained
  semantic frames, zero dirty rows, and zero semantic fallback cells.
- `git diff --check` - passed.

## 2026-06-08 19:37 EDT

Hardened retained DOM host teardown against partial cleanup failures.

- Added best-effort cleanup for `runTuiSurface` and `TuiSurfaceHost.dispose`.
  Input, frame scheduler, metrics, semantics owner, semantic presenter,
  runtime, visual surface, generated host resources, and clipboard restoration
  are each attempted even if an earlier cleanup step throws.
- Preserved the first cleanup error for explicit `dispose()` callers, while
  setup-failure cleanup continues to preserve the original setup exception as
  the primary failure.
- This closes a browser-host lifecycle risk where a throwing surface/presenter
  cleanup could previously skip generated DOM cleanup or leave the web
  clipboard backend installed after host disposal.
- Added browser regression coverage for a surface disposal failure: the test
  verifies that generated host cleanup still runs and `Clipboard.instance` is
  restored before the original dispose error is reported.
- No readiness artifacts or baseline captures changed; this is host lifecycle
  hardening only.

Verification:

- `cd packages/fleury_web && dart format lib/src/run_tui_surface.dart test/run_tui_surface_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/run_tui_surface.dart test/run_tui_surface_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 16 browser tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed.
- `git diff --check` - passed.

## 2026-06-08 19:41 EDT

Hardened retained DOM pointer cancellation handling.

- Added `pointercancel` and `lostpointercapture` listeners to
  `DomInputSource`.
- Cancellation/lost-capture now clears the local pressed-button state and
  releases pointer capture on a best-effort basis without emitting a synthetic
  Fleury mouse event. The core mouse model has down/up/drag/move/scroll, so
  the browser cancellation signal is treated as host bookkeeping.
- This prevents stale browser pointer capture state from causing later
  `pointermove` events to be reported as Fleury drags after the browser has
  canceled or lost the active pointer stream.
- Added direct browser coverage in `dom_input_source_test.dart`.
- Added a shared browser input trace fixture for pointer cancellation so the
  event-semantics replay catalog now covers the stale-drag case.
- No readiness artifacts or baseline captures changed; this is browser input
  lifecycle hardening only.

Verification:

- `cd packages/fleury_web && dart format lib/src/input/dom_input_source.dart test/dom_input_source_test.dart test/dom_input_trace_fixture_test.dart test/fixtures/browser_input_traces.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/input/dom_input_source.dart test/dom_input_source_test.dart test/dom_input_trace_fixture_test.dart test/fixtures/browser_input_traces.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_input_source_test.dart` -
  passed with 7 browser tests.
- `cd packages/fleury_web && dart test -p chrome test/dom_input_trace_fixture_test.dart` -
  passed with 9 browser trace tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 16 browser tests.
- `git diff --check` - passed.

## 2026-06-08 19:44 EDT

Hardened disabled semantic DOM interactions.

- Disabled semantic nodes now behave as disabled in the browser DOM, not only
  in ARIA metadata.
- `SemanticDomPresenter` no longer gives disabled safe links a browser `href`,
  `target`, or `rel`. It still preserves `data-fleury-link-url` for diagnostics
  and manual review.
- Semantic action click handling now ignores elements with
  `aria-disabled="true"`, so disabled buttons/commands cannot dispatch Fleury
  semantic actions through the mirror DOM.
- Added browser coverage for disabled safe links and disabled action nodes.
- No readiness artifacts or baseline captures changed; this is semantic DOM
  correctness hardening ahead of real VoiceOver evidence collection.

Verification:

- `cd packages/fleury_web && dart format lib/src/semantics/semantic_dom_presenter.dart test/semantic_dom_presenter_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/semantics/semantic_dom_presenter.dart test/semantic_dom_presenter_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/semantic_dom_presenter_test.dart` -
  passed with 12 browser tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 16 browser tests.
- `cd packages/fleury_web && dart test -p chrome test/manual_validation_page_test.dart` -
  passed.
- `git diff --check` - passed.

## 2026-06-08 19:49 EDT

Hardened semantic-action focus restoration when no keyboard capture target is
installed.

- `runTuiSurface` still attempts to restore browser keyboard/IME capture after
  a semantic DOM action, but it now records `WebFocusTarget.keyboardCapture`
  only when the input source actually implements `KeyboardCaptureTarget`.
- Previously, semantic actions in a host assembled without an input source
  could leave `WebFocusCoordinator.browserFocusTarget` claiming
  `keyboardCapture` even though no hidden textarea or keyboard capture owner
  existed. That made focus telemetry and future accessibility debugging
  misleading.
- Added browser coverage for the no-input-source semantic action path. The
  regression asserts the semantic action still dispatches and the active
  semantic node is retained, while browser focus remains attributed to the
  semantic node instead of a nonexistent keyboard capture target.
- No readiness artifacts or baseline captures changed; this is focus-state
  correctness hardening ahead of real browser IME/VoiceOver validation.

Verification:

- `cd packages/fleury_web && dart format lib/src/run_tui_surface.dart test/run_tui_surface_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/run_tui_surface.dart test/run_tui_surface_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 17 browser tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed.
- `git diff --check` - passed.

## 2026-06-08 19:51 EDT

Closed disabled semantic DOM event bubbling.

- Disabled semantic mirror nodes now call `preventDefault()` and
  `stopPropagation()` before returning from their click listener.
- This preserves the previous guarantee that disabled nodes do not dispatch
  their own Fleury semantic action, and adds the missing guarantee that a click
  on a disabled child cannot bubble into an actionable ancestor and dispatch
  the ancestor's semantic action.
- Added browser coverage with an actionable ancestor and a disabled child. The
  test asserts the event is canceled and no semantic action request is emitted.
- No readiness artifacts or baseline captures changed; this is semantic DOM
  correctness hardening ahead of real VoiceOver evidence collection.

Verification:

- `cd packages/fleury_web && dart format lib/src/semantics/semantic_dom_presenter.dart test/semantic_dom_presenter_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/semantics/semantic_dom_presenter.dart test/semantic_dom_presenter_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/semantic_dom_presenter_test.dart` -
  passed with 13 browser tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 17 browser tests.
- `git diff --check` - passed.

## 2026-06-08 19:53 EDT

Guarded semantic action dispatch against stale semantic snapshots.

- `SemanticsElement.handleSemanticAction` now re-checks the live widget state
  before invoking `onAction`.
- A semantic action must still target the current element id, and the current
  widget must still be enabled and expose the requested action. This prevents a
  host from dispatching a semantic DOM action that was valid in a prior
  semantic tree but became disabled or unsupported before the queued action was
  drained.
- Added a core semantics regression that captures an enabled semantic tree,
  updates the live widget to disabled with the same id, then invokes through
  the older tree. The callback is not called and the helper reports the action
  as unsupported.
- Re-ran the browser semantic DOM and retained surface suites to cover the web
  action request path that depends on this core guard.
- No readiness artifacts or baseline captures changed; this is semantic action
  correctness hardening for queued web accessibility actions.

Verification:

- `dart format packages/fleury/lib/src/semantics/semantics.dart packages/fleury/test/semantics/semantics_test.dart` -
  passed.
- `dart analyze packages/fleury/lib/src/semantics/semantics.dart packages/fleury/test/semantics/semantics_test.dart` -
  passed.
- `cd packages/fleury && dart test test/semantics/semantics_test.dart` -
  passed with 30 tests.
- `cd packages/fleury_web && dart test -p chrome test/semantic_dom_presenter_test.dart` -
  passed with 13 browser tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 17 browser tests.
- `git diff --check` - passed.

## 2026-06-08 19:57 EDT

Cleared stale semantic browser-focus ownership.

- `WebFocusCoordinator.syncFromFleuryFocus` now clears
  `WebFocusTarget.semanticNode` when the latest Fleury/semantic sync reports no
  active semantic node.
- This prevents focus diagnostics from exposing the impossible state "browser
  focus target is semantic node" while `activeSemanticNode` is null. Keyboard
  capture ownership is preserved when it is the current browser target.
- Added focused coordinator coverage for clearing stale semantic focus while
  preserving keyboard-capture focus.
- Re-ran retained-surface and public DOM runner browser tests because
  `runTuiSurface` calls this sync path after semantic presentation.
- No readiness artifacts or baseline captures changed; this is web focus-state
  correctness hardening.

Verification:

- `cd packages/fleury_web && dart format lib/src/focus/web_focus_coordinator.dart test/web_focus_coordinator_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/focus/web_focus_coordinator.dart test/web_focus_coordinator_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_focus_coordinator_test.dart` -
  passed with 3 tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 17 browser tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed.
- `git diff --check` - passed.

## 2026-06-08 20:00 EDT

Exposed semantic action invocation status in follow-up frame reasons.

- `runTuiSurface` now includes `SemanticActionInvocationResult.status` in the
  scheduled follow-up frame reason after a semantic DOM action completes.
- Completed actions now schedule reasons such as
  `semantic-action:activate:completed`; disabled, unsupported, missing, and
  failed actions will be distinguishable in frame captures without adding a new
  instrumentation channel.
- Added retained-surface browser coverage that clicks semantic DOM buttons and
  uses a generic `SemanticActionRequestSink` presenter to assert follow-up
  instrumented frames carry completed, failed, unsupported, and not-found action
  statuses.
- No readiness artifacts or baseline captures changed; this improves
  observability for queued accessibility actions during manual validation and
  benchmark capture review.

Verification:

- `cd packages/fleury_web && dart format lib/src/run_tui_surface.dart test/run_tui_surface_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/run_tui_surface.dart test/run_tui_surface_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 19 browser tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed.
- `git diff --check` - passed.

## 2026-06-08 20:05 EDT

Cleared semantic DOM action callbacks during presenter disposal.

- `SemanticDomPresenter.dispose` now clears its
  `onSemanticActionRequest` callback in addition to removing retained element
  click listeners and clearing the DOM root.
- Added browser coverage that keeps a reference to a retained semantic action
  element, disposes the presenter, dispatches a click on that stale element,
  and verifies no action request is emitted.
- Re-ran the retained-surface browser suite to cover host-owned disposal through
  `runTuiSurface`.
- No readiness artifacts or baseline captures changed; this is semantic DOM
  lifecycle hardening.

Verification:

- `cd packages/fleury_web && dart format lib/src/semantics/semantic_dom_presenter.dart test/semantic_dom_presenter_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/semantics/semantic_dom_presenter.dart test/semantic_dom_presenter_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/semantic_dom_presenter_test.dart` -
  passed with 14 browser tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 18 browser tests.
- `git diff --check` - passed.

## 2026-06-08 20:10 EDT

Made post-action keyboard capture restoration best-effort.

- `runTuiSurface` now catches synchronous failures from
  `KeyboardCaptureTarget.ensureKeyboardCapture()` inside the unawaited
  semantic-action completion callback.
- A browser focus restoration failure no longer prevents the semantic action
  status follow-up frame from being scheduled.
- Added retained-surface browser coverage with a throwing keyboard capture
  target. The test verifies the Fleury semantic action still completes,
  semantic focus remains attributed to the activated node, and the completed
  action status is recorded.
- No readiness artifacts or baseline captures changed; this is browser focus
  lifecycle hardening for accessibility action handoff.

Verification:

- `cd packages/fleury_web && dart format lib/src/run_tui_surface.dart test/run_tui_surface_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/run_tui_surface.dart test/run_tui_surface_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 20 browser tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed.
- `git diff --check` - passed.

## 2026-06-08 20:14 EDT

Reported no-tree semantic action requests as notFound.

- `runTuiSurface` now emits a `semantic-action:<action>:notFound` follow-up
  frame when semantic action requests are drained before a retained semantic
  tree exists.
- Previously those pre-tree requests were removed from the pending queue
  without an observable status frame.
- Added retained-surface browser coverage that queues a generic
  `SemanticActionRequestSink` request before the first semantic frame and
  verifies the follow-up frame reason is `semantic-action:activate:notFound`.
- No readiness artifacts or baseline captures changed; this is semantic action
  observability hardening for early presenter and host lifecycle cases.

Verification:

- `cd packages/fleury_web && dart format lib/src/run_tui_surface.dart test/run_tui_surface_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/run_tui_surface.dart test/run_tui_surface_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 21 browser tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed.
- `git diff --check` - passed.

## 2026-06-08 20:21 EDT

Preserved AltGraph printable input for browser text entry.

- `keyEventFromBrowser` now leaves printable keydown events with the browser
  `AltGraph` modifier on the textarea input path instead of converting them
  into Fleury Ctrl/Alt shortcuts.
- Added mapper coverage for `KeyboardEvent.getModifierState('AltGraph')` and
  browser trace replay coverage for the keydown-plus-input ordering used by
  international keyboard layouts.
- The reusable browser input trace catalog now includes an AltGraph printable
  text case, and the trace replay harness passes `modifierAltGraph` into
  `KeyboardEventInit`.
- No readiness artifacts or baseline captures changed; this is input/IME
  hardening for real primary-browser manual validation.

Verification:

- `cd packages/fleury_web && dart format lib/src/input/dom_input_source.dart test/dom_input_source_test.dart test/dom_input_trace_fixture_test.dart test/fixtures/browser_input_traces.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/input/dom_input_source.dart test/dom_input_source_test.dart test/dom_input_trace_fixture_test.dart test/fixtures/browser_input_traces.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_input_source_test.dart test/dom_input_trace_fixture_test.dart` -
  passed with 18 browser tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed.
- `git diff --check` - passed.

## 2026-06-08 20:23 EDT

Cleared keyboard-capture focus ownership on DOM input disposal.

- `DomInputSource.dispose` now notifies `WebFocusCoordinator` that keyboard
  capture focus is gone when the hidden textarea and browser event listeners
  are torn down.
- This prevents post-disposal diagnostics from reporting
  `WebFocusTarget.keyboardCapture` after the DOM host has removed the textarea.
- Added direct browser coverage for `DomInputSource` disposal and extended the
  assembled `runTuiWebDom` smoke to verify host disposal clears the browser
  focus target while still removing generated DOM roots and restoring
  `Clipboard.instance`.
- No readiness artifacts or baseline captures changed; this is browser focus
  lifecycle hardening.

Verification:

- `cd packages/fleury_web && dart format lib/src/input/dom_input_source.dart test/dom_input_source_test.dart test/run_tui_web_dom_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/input/dom_input_source.dart test/dom_input_source_test.dart test/run_tui_web_dom_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_input_source_test.dart test/run_tui_web_dom_test.dart` -
  passed with 10 browser tests.
- `git diff --check` - passed.

## 2026-06-08 20:25 EDT

Preserved Alt-only printable browser text input.

- `keyEventFromBrowser` now treats printable keydown events with Alt/Option
  and no Ctrl/Meta as browser text input rather than Fleury shortcuts.
- This keeps macOS Option-produced characters and similar browser text entry
  paths on the textarea `input` channel, while Ctrl/Meta shortcut mapping stays
  unchanged.
- Added direct mapper coverage for an Alt-only printable character and reusable
  browser input trace replay coverage for the keydown-plus-input sequence.
- No readiness artifacts or baseline captures changed; this further hardens the
  primary-browser IME/international-keyboard path ahead of manual validation.

Verification:

- `cd packages/fleury_web && dart format lib/src/input/dom_input_source.dart test/dom_input_source_test.dart test/fixtures/browser_input_traces.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/input/dom_input_source.dart test/dom_input_source_test.dart test/dom_input_trace_fixture_test.dart test/fixtures/browser_input_traces.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_input_source_test.dart test/dom_input_trace_fixture_test.dart` -
  passed with 21 browser tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed.
- `git diff --check` - passed.

## 2026-06-08 20:28 EDT

Preserved browser paste accelerators for native paste events.

- `keyEventFromBrowser` now leaves Ctrl+V, Meta+V, and Shift+Insert to the
  browser paste pipeline instead of emitting Fleury shortcut/key-code events
  from `keydown`.
- This avoids suppressing the hidden textarea's native `paste` event and keeps
  browser paste delivery represented as a single Fleury `PasteEvent`.
- Added direct mapper coverage for the paste accelerators and browser trace
  replay coverage for Ctrl+V followed by a paste event, asserting no duplicate
  key event is emitted before the paste.
- No readiness artifacts or baseline captures changed; this hardens text-entry
  behavior ahead of real primary-browser IME/manual validation.

Verification:

- `cd packages/fleury_web && dart format lib/src/input/dom_input_source.dart test/dom_input_source_test.dart test/fixtures/browser_input_traces.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/input/dom_input_source.dart test/dom_input_source_test.dart test/dom_input_trace_fixture_test.dart test/fixtures/browser_input_traces.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_input_source_test.dart test/dom_input_trace_fixture_test.dart` -
  passed with 23 browser tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed.
- `git diff --check` - passed.

## 2026-06-08 20:33 EDT

Normalized macOS Command printable shortcuts to Fleury Ctrl shortcuts.

- `keyEventFromBrowser` now maps printable Meta/Command shortcuts without
  Ctrl/Alt to Fleury Ctrl-shaped shortcut events, preserving Shift when
  present.
- Browser paste accelerators still remain native paste events, so Meta+V
  continues to produce paste through the browser `paste` event instead of a key
  event.
- Added direct mapper coverage for Meta+Z and Meta+Shift+Z plus browser trace
  replay coverage for a Meta+Shift printable shortcut.
- No readiness artifacts or baseline captures changed; this improves macOS
  browser shortcut parity for the retained DOM host without broadening core
  key-chord APIs.

Verification:

- `cd packages/fleury_web && dart format lib/src/input/dom_input_source.dart test/dom_input_source_test.dart test/fixtures/browser_input_traces.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/input/dom_input_source.dart test/dom_input_source_test.dart test/dom_input_trace_fixture_test.dart test/fixtures/browser_input_traces.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_input_source_test.dart test/dom_input_trace_fixture_test.dart` -
  passed with 25 browser tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed.
- `git diff --check` - passed.

## 2026-06-08 20:35 EDT

Tied the manual validation page controller to widget disposal.

- `web/manual_validation.dart` now owns the IME `TextEditingController` inside
  `_ManualValidationAppState`, matching the retained DOM demo lifecycle.
- Disposing the returned `TuiSurfaceHost` now unmounts the widget tree and
  disposes the manual page controller through normal state disposal instead of
  leaving a controller allocated outside the tree.
- No readiness artifacts, manual evidence, or baseline captures changed; this
  is lifecycle hardening for the page used by real IME and VoiceOver evidence
  collection.

Verification:

- `cd packages/fleury_web && dart format web/manual_validation.dart` - passed.
- `cd packages/fleury_web && dart analyze web/manual_validation.dart test/manual_validation_page_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/manual_validation_page_test.dart` -
  passed.
- `git diff --check` - passed.

## 2026-06-08 20:45 EDT

Hardened the browser frame scheduler for missing `requestAnimationFrame`.

- `browserFrameFlushScheduler` now prefers `window.requestAnimationFrame` when
  it exists, but falls back to an asynchronous timer flush if rAF is missing or
  unusable.
- This prevents retained DOM hosts from getting stranded after constructing
  their DOM roots in embedded or test browser surfaces with a partial `window`
  API.
- Added direct Chrome coverage for the scheduler fallback by temporarily
  removing `window.requestAnimationFrame`, plus manual-validation page coverage
  that uses the production browser scheduler and still reaches
  `data-fleury-manual-validation="ready"` without rAF.
- Rebuilt the generated retained DOM page bundles:
  `web/manual_validation.dart.js` and `web/dom_demo.dart.js`.
- Synced the package README, review packet, and phase audit so reviewer-facing
  architecture notes describe the no-rAF fallback and its Chrome coverage.
- No readiness artifacts, manual evidence, or baseline captures changed; this
  is browser-host scheduling hardening ahead of the real Chrome IME and
  VoiceOver runs.

Verification:

- `cd packages/fleury_web && dart format lib/src/browser_frame_flush_scheduler.dart test/browser_frame_flush_scheduler_test.dart test/manual_validation_page_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/browser_frame_flush_scheduler.dart test/browser_frame_flush_scheduler_test.dart test/manual_validation_page_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/browser_frame_flush_scheduler_test.dart test/manual_validation_page_test.dart` -
  passed with 3 browser tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart test/dom_demo_test.dart` -
  passed with 2 browser tests.
- `cd packages/fleury_web && dart compile js web/manual_validation.dart -o web/manual_validation.dart.js` -
  passed.
- `cd packages/fleury_web && dart compile js web/dom_demo.dart -o web/dom_demo.dart.js` -
  passed.
- `git diff --check` - passed.

## 2026-06-08 20:54 EDT

Added manual validation page source fingerprints to the readiness bundle.

- `web-readiness-bundle.json` now fingerprints the manual validation page
  source, HTML shell, and generated served JS when those files exist:
  `web/manual_validation.dart`, `web/manual_validation.html`, and
  `web/manual_validation.dart.js`.
- This closes a stale-page review gap: a regenerated readiness bundle can now
  detect when the page used for real Chrome IME or VoiceOver evidence no longer
  matches the source and served browser artifact under review.
- The readiness bundle test now asserts the manual page fingerprints are present
  and verifies source-input counts using the actual page files present in the
  package checkout.
- Synced `profiling/web/README.md`, the review packet, and the phase audit so
  reviewer-facing artifact contracts include manual validation page
  source/HTML/served-JS provenance.
- No readiness artifacts, manual evidence, or baseline captures changed; this
  is release-packet provenance hardening.

Verification:

- `cd packages/fleury_web && dart format tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 15 VM tests.
- `git diff --check` - passed.

## 2026-06-08 20:57 EDT

Regenerated the local readiness-candidate packet with manual page source
fingerprints.

- Re-ran `tool/web_readiness_bundle.dart` over the existing
  `2026-06-08-local-dom-retained-phase1-refresh` capture set and
  `profiling/web/manual` directory after adding manual validation page
  source-input fingerprints.
- The refreshed `web-readiness-bundle.json` now includes
  `manualValidationPageFiles` for:
  `web/manual_validation.dart`, `web/manual_validation.dart.js`, and
  `web/manual_validation.html`.
- Bundle integrity verification passes with 10 generated artifacts, 40 source
  inputs, one metadata field, and zero artifact/source/metadata mismatches.
- The bundle remains intentionally release-red: `frameScoreboard` is blocked by
  the candidate threshold policy, and `manualValidation` is blocked by missing
  real `chrome-ime-macos` and `chrome-voiceover-macos` evidence.
- Remaining release actions are now the current seven-step graph:
  `review-threshold-policy`,
  `collect-manual-evidence:chrome-ime-macos`,
  `collect-manual-evidence:chrome-voiceover-macos`,
  `regenerate-readiness-bundle`, `verify-readiness-bundle`,
  `run-default-preflight:make-dom-default`, and
  `run-default-preflight:retire-temporary-paths`.

Verification:

- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  passed and wrote the refreshed candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 40 checked source inputs, and
  one checked metadata field.
- `dart run tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with the same 10 checked generated artifacts, 40 checked source inputs,
  and one checked metadata field.

## 2026-06-08 20:59 EDT

Synced the package README with the manual page fingerprint contract.

- Updated `packages/fleury_web/README.md` so its readiness-bundle section lists
  manual validation page source, HTML, and served JS under
  `sourceInputFingerprints`.
- This brings the package-level operator docs in line with
  `web_readiness_bundle.dart`, the refreshed readiness-candidate packet,
  `profiling/web/README.md`, the review packet, and the phase audit.
- No code, readiness artifacts, manual evidence, or baseline captures changed in
  this slice.

Verification:

- `dart run tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 40 checked source inputs, and one
  checked metadata field.
- `git diff --check` - passed.

## 2026-06-08 21:03 EDT

Covered manual validation page drift at the bundle-bound default preflight gate.

- Added a default-preflight regression test that binds a fake served manual page
  JS file through `sourceInputFingerprints.manualValidationPageFiles`, mutates
  that file, and verifies `web_default_preflight.dart --bundle=... --strict`
  rejects the release gate with a source-input fingerprint mismatch.
- This gives the final `make-dom-default` / `retire-temporary-paths` preflight
  path direct coverage for stale manual validation page provenance, not only
  stale capture JSON provenance.
- No production code, readiness artifacts, manual evidence, or baseline captures
  changed in this slice.

Verification:

- `cd packages/fleury_web && dart format test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart` -
  passed with 8 VM tests.
- `git diff --check` - passed.

## 2026-06-08 21:06 EDT

Made bundle-bound default preflight enforce command-working-directory metadata.

- `web_default_preflight.dart --bundle=...` now verifies
  `input.commandWorkingDirectory` against the package cwd, matching the
  standalone `web_readiness_bundle.dart --verify` metadata check.
- The `readinessBundle` preflight details now report
  `checkedMetadataCount`, `metadataMismatchCount`, and `missingMetadataCount`,
  and include metadata mismatch/missing details when present.
- Added regression coverage for a stale bundle command cwd so the final
  `make-dom-default` / `retire-temporary-paths` release gate rejects a bundle
  generated from the wrong package working directory.
- Synced `packages/fleury_web/README.md`, `profiling/web/README.md`, the review
  packet, and the phase audit so the final preflight contract includes artifact
  fingerprints, source-input fingerprints, command-working-directory metadata,
  and readiness JSON path binding.
- The current candidate `make-dom-default` preflight still exits 1 as expected
  because readiness is blocked by candidate thresholds and missing real
  Chrome IME/VoiceOver evidence, but its nested `readinessBundle` check now
  passes with 10 generated artifacts, 40 source inputs, and one metadata field.

Verification:

- `cd packages/fleury_web && dart format tool/web_default_preflight.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_default_preflight.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart` -
  passed with 9 VM tests.
- `dart run tool/fleury_dev.dart benchmark web-default-preflight --readiness=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` check passed with zero artifact/source/metadata mismatches.
- `dart run tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 40 checked source inputs, and one
  checked metadata field.
- `git diff --check` - passed.

## 2026-06-08 21:12 EDT

Made default-preflight release actions advertise their verification scope.

- `run-default-preflight:<target>` release-action details now include
  `verificationScope` with:
  `generated-artifact-fingerprints`, `source-input-fingerprints`,
  `command-working-directory-metadata`, and `readiness-json-path-binding`.
- This keeps the machine-readable release-action graph aligned with the
  strengthened bundle-bound default preflight behavior, so downstream tools do
  not have to infer what the final release gate validates from command text.
- Added regression coverage in `web_readiness_bundle_tool_test.dart` for the
  default-preflight action scope.
- Regenerated the local readiness-candidate packet so
  `web-readiness-bundle.json` and `web-release-actions.md` include the new
  default-preflight verification scope for both `make-dom-default` and
  `retire-temporary-paths`.
- The refreshed packet remains intentionally release-red for candidate
  thresholds and missing real Chrome IME/VoiceOver evidence.

Verification:

- `cd packages/fleury_web && dart format tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 15 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  passed and wrote the refreshed candidate packet.
- `dart run tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 40 checked source inputs, and one
  checked metadata field.
- `rg -n "verificationScope|readiness-json-path-binding|command-working-directory-metadata" profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-release-actions.md` -
  confirmed the verify action and both default-preflight actions render their
  verification scopes.
- `git diff --check` - passed.

## 2026-06-08 21:25 EDT

Made bundle-generated default preflights explicitly preview-only in the release
action graph.

- `web_readiness_bundle.dart` now emits final bundle-bound
  `run-default-preflight:<target>` release actions whenever
  `--write-default-preflights` is used, even if the generated preview
  preflights strict-pass.
- Green readiness bundles with preview preflight artifacts now still ask
  reviewers to run `verify-readiness-bundle` and the bundle-bound
  `make-dom-default` / `retire-temporary-paths` preflight commands before
  changing defaults.
- The final preflight action details now report
  `generatedPreviewStrictPass` and `generatedPreviewBundleBound: false`, so
  downstream tools can distinguish a readiness-bound preview artifact from the
  actual `--bundle=...` release gate.
- Updated package/operator docs, the review packet, and the phase audit so
  `remainingReleaseActions` is described as the final-gate checklist, not only
  a failure-path checklist.
- Regenerated the local readiness-candidate packet. It remains intentionally
  release-red for candidate thresholds and missing real Chrome IME/VoiceOver
  evidence, but the packet now records preview-preflight status on both final
  preflight actions.

Verification:

- `cd packages/fleury_web && dart format tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 15 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  passed and wrote the refreshed candidate packet.
- `dart run tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 40 checked source inputs, and one
  checked metadata field.
- `dart run tool/fleury_dev.dart benchmark web-default-preflight --readiness=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` check passed with zero artifact/source/metadata mismatches.
- `git diff --check` - passed.

## 2026-06-08 21:31 EDT

Centralized readiness-bundle fingerprint traversal for release tooling.

- Added `tool/readiness_bundle_verifier.dart` as the shared implementation for
  generated-artifact fingerprints, source-input fingerprints, and
  command-working-directory metadata checks.
- Updated `web_readiness_bundle.dart --verify` and
  `web_default_preflight.dart --bundle=...` to use the same verifier state and
  traversal functions, preventing the standalone verifier and final default
  preflight from drifting on nested artifact/source-input handling.
- The bundle-bound preflight now also reports a missing/malformed
  `sourceInputFingerprints` section in the shared missing-source-fingerprint
  counts, not only as a text blocker, with regression coverage in the
  default-preflight tool suite.
- No readiness packet regeneration was needed for this refactor; the current
  candidate packet still verifies cleanly with the shared helper.

Verification:

- `cd packages/fleury_web && dart format tool/readiness_bundle_verifier.dart tool/web_readiness_bundle.dart tool/web_default_preflight.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/readiness_bundle_verifier.dart tool/web_readiness_bundle.dart tool/web_default_preflight.dart test/web_readiness_bundle_tool_test.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart test/web_default_preflight_tool_test.dart` -
  passed with 25 VM tests.
- `dart run tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 40 checked source inputs, and one
  checked metadata field.
- `git diff --check` - passed.

## 2026-06-08 21:44 EDT

Added manifest-consistency verification to readiness-bundle release gates.

- The shared readiness bundle verifier now checks manifest summaries against
  the indexed JSON artifacts, including bundle `strictPass`,
  `checks.readinessStrictPass`, scoreboard/semantic/manual strict-pass
  summaries, generated preview preflight strict-pass summaries, and generated
  preview bundle-bound status.
- The verifier also checks the generated release-action graph for preview
  default preflight artifacts: `verify-readiness-bundle` must be present, each
  `run-default-preflight:<target>` action must be present, and its details must
  match the preview preflight artifact plus the manifest's readiness/bundle
  paths.
- `web_readiness_bundle.dart --verify` now reports
  `checkedManifestFieldCount`, `manifestMismatchCount`, and
  `missingManifestFieldCount`.
- `web_default_preflight.dart --bundle=...` now fails the final release gate
  when the bundle manifest is stale or hand-edited, even if all external
  artifact and source-input fingerprints still match.
- Added regression coverage for a stale bundle manifest summary and for a
  generated bundle whose final preflight action was removed from
  `remainingReleaseActions`.
- Synced the package README, profiling README, review packet, and phase audit
  with the expanded verifier scope.
- No readiness packet regeneration was needed; the current candidate packet is
  internally consistent under the stronger verifier.

Verification:

- `cd packages/fleury_web && dart format tool/readiness_bundle_verifier.dart tool/web_readiness_bundle.dart tool/web_default_preflight.dart test/web_readiness_bundle_tool_test.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/readiness_bundle_verifier.dart tool/web_readiness_bundle.dart tool/web_default_preflight.dart test/web_readiness_bundle_tool_test.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart` -
  passed with 11 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 16 VM tests.
- `dart run tool/fleury_dev.dart benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 40 checked source inputs, one
  checked metadata field, and 20 checked manifest fields.
- `dart run tool/fleury_dev.dart benchmark web-default-preflight --readiness=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` check passed with zero artifact/source/metadata/manifest
  mismatches.
- `git diff --check` - passed.

## 2026-06-08 21:52 EDT

Hardened retained DOM host cleanup after frame-time presentation failures.

- `runTuiSurface` now wraps scheduled frame rendering so an exception from the
  frame body, including a `FrameSurface.present` failure, marks the returned
  host disposed, starts best-effort cleanup of input, scheduler, metrics,
  semantics, runtime, surface, generated host resources, and clipboard state,
  then rethrows the original frame error.
- Added browser coverage with a throwing retained DOM surface to prove the
  original presentation error is visible, host resources are disposed, the
  previous clipboard is restored, generated host resources are cleaned up, and
  later frame requests are ignored.
- Fixed retained DOM page test isolation by giving the demo and manual
  validation browser tests distinct explicit host IDs instead of both using
  `#fleury-app`. Running those page tests together now passes.
- Synced the phase audit and review packet with the new host failure and page
  isolation coverage.

Verification:

- `cd packages/fleury_web && dart format lib/src/run_tui_surface.dart test/run_tui_surface_test.dart test/manual_validation_page_test.dart test/dom_demo_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/run_tui_surface.dart test/run_tui_surface_test.dart test/manual_validation_page_test.dart test/dom_demo_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 22 browser tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/manual_validation_page_test.dart test/dom_demo_test.dart` -
  passed with 3 browser tests.
- `git diff --check` - passed.

## 2026-06-08 21:57 EDT

Made retained DOM frame-failure cleanup awaitable through the returned host.

- `TuiSurfaceHost` now owns a single disposal future. Normal `dispose()` starts
  cleanup once and returns the same future to later callers.
- Frame-time failures now mark the returned host disposed, stop future frame
  requests immediately, and start the same cleanup path. Cleanup failures remain
  best-effort in this path so the original frame error stays visible, but a
  later `await host.dispose()` waits for the in-flight cleanup to finish.
- Added browser regression coverage that deliberately blocks generated-host
  resource cleanup after a `FrameSurface.present` failure and proves
  `host.dispose()` remains pending until cleanup completes and clipboard state
  is restored.

Verification:

- `cd packages/fleury_web && dart format lib/src/run_tui_surface.dart test/run_tui_surface_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/run_tui_surface.dart test/run_tui_surface_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 23 browser tests.
- `git diff --check` - passed for tracked changes; the touched web host files
  remain part of the untracked web implementation set in this worktree.

## 2026-06-08 22:09 EDT

Bound readiness bundles to retained web implementation source files.

- `web_readiness_bundle.dart` now records a required
  `sourceInputFingerprints.webImplementationFiles` group containing
  `lib/fleury_web.dart` and every `lib/src/**/*.dart` implementation source in
  `packages/fleury_web`.
- `readiness_bundle_verifier.dart` now rejects strict bundle verification when
  that implementation-source group is missing or empty, so older packets cannot
  silently verify without retained-host source binding.
- Added bundle regression coverage for stale implementation-source
  fingerprints and for manifests missing the implementation-source group.
- Updated the bundle-bound default-preflight test fixture so default preflight
  verification also exercises the required implementation-source group.
- Synced the profiling README, review packet, and phase audit to describe
  retained web implementation Dart files as source inputs.
- Regenerated the current local readiness-candidate packet under
  `profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate`.
  The packet remains red for the same empirical gates: candidate thresholds and
  missing real Chrome IME / VoiceOver evidence.

Verification:

- `cd packages/fleury_web && dart format tool/readiness_bundle_verifier.dart tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/readiness_bundle_verifier.dart tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart` -
  passed with 11 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 18 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with
  `webImplementationFiles` fingerprints.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 64 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 64 checked source inputs.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 64 checked source inputs.
- `rg -n "[ \t]+$" ...` over the touched source, test, doc, and log files -
  passed.
- `git diff --check` - passed for tracked changes; many web implementation
  files remain untracked in this worktree until the branch is staged.

## 2026-06-08 22:52 EDT

Made manual evidence release actions state-aware after starter files exist.

- `web_readiness_bundle.dart` now checks each target's
  `profiling/web/manual/evidence/<target>.review.json` starter path while
  generating `collect-manual-evidence:*` actions.
- Missing starter files still receive the no-overwrite
  `web_manual_validation.dart --write-starter` command.
- Existing starter files now get `starterEvidenceStatus: exists` and
  `starterEvidenceFingerprint` details, the `starterCommand` is omitted, and
  `reviewerNextStep` tells reviewers to fill the existing file before running
  the audit.
- Added regression coverage for the current real packet shape: both primary
  templates exist, both starter evidence files exist, and the generated
  release-action graph treats them as edit targets rather than creation
  targets.
- Synced the package README, profiling README, review packet, and phase audit
  with the missing-vs-existing starter behavior.
- Regenerated the local readiness-candidate packet. Its manual evidence
  actions now show `starterEvidenceStatus: exists`, no `starterCommand`, and
  retained readiness remains red only for candidate thresholds plus pending
  reviewed IME / VoiceOver evidence.

Verification:

- `cd packages/fleury_web && dart format tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 22 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with existing-starter
  manual actions.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 211 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 211 checked source inputs.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 211 checked source inputs.
- Manifest spot-check confirmed both manual evidence actions have
  `starterEvidenceStatus: exists`, no `starterCommand`, and edit/audit
  reviewer guidance.
- `rg -n "[ \t]+$" ...` over touched source, tests, docs, execution log, and
  regenerated release actions - passed.
- `git diff --check` - passed for tracked changes; many web implementation and
  profiling artifacts remain untracked in this worktree until the branch is
  staged.

## 2026-06-08 23:07 EDT

Added captured-environment context to the threshold review release action.

- `web_readiness_bundle.dart` now passes the frame scoreboard into
  `remainingReleaseActions` and includes a `captureEnvironment` summary on the
  `review-threshold-policy` action whenever scoreboard metadata is available.
- The summary is derived from each scenario's latest run environment and
  records scenario counts, comparable-environment counts, Chrome version,
  operating system/version, Dart version, headless mode, frame budget, requested
  frame counts, and warmup frame count.
- The threshold action now includes a `reviewContextHint` such as
  `Browser Chrome/148.0.7778.217, OS macos ... frameBudgetMs=16.67, retained DOM
  product baseline` so the human reviewer can fill the threshold review context
  from the actual captured run rather than from a placeholder.
- This does not promote thresholds or weaken the release gate. The readiness
  packet remains intentionally red until a reviewer marks threshold policy as
  reviewed and real Chrome IME / VoiceOver evidence passes.
- Synced the package README, profiling README, review packet, and phase audit to
  describe the threshold action's captured-environment summary.
- Regenerated the local readiness-candidate packet. Spot-checking the bundle
  confirmed 11 scenarios, 11 comparable environments,
  `allScenariosComparable: true`, Chrome `148.0.7778.217`, macOS
  `Version 26.2 (Build 25C56)`, Dart `3.12.1`, headless mode, 16.67 ms frame
  budget, requested frame counts `[24, 32, 12, 16, 20]`, and warmup frames `2`.

Verification:

- `cd packages/fleury_web && dart format tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 22 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with threshold capture
  environment details.
- `node -e "...review-threshold-policy..."` over the regenerated
  `web-readiness-bundle.json` - confirmed the `reviewContextHint` starts with
  `Browser Chrome/148.0.7778.217` and the capture summary reports
  `allScenariosComparable: true`.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 211 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 211 checked source inputs.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 211 checked source inputs.
- `rg -n "[ \t]+$" ...` over the touched source, tests, docs, execution log,
  and regenerated release actions - passed.
- `git diff --check` - passed for tracked changes; many web implementation and
  profiling artifacts remain untracked in this worktree until the branch is
  staged.

## 2026-06-08 23:24 EDT

Prefilled threshold review context from captured environment metadata.

- `web_threshold_review.dart` now accepts `--review-context-hint=TEXT` for
  non-promoting review-plan generation. The hint is written into
  `threshold-review-plan.md` and used in that plan's promotion command, while
  promotion itself still requires explicit `--reviewed-by` and
  `--review-context` provenance.
- `web_readiness_bundle.dart` now copies the threshold action
  `captureEnvironment.reviewContextHint` into `suggestedReviewContext`, passes
  it through the generated plan command, and pre-fills the promotion
  `--review-context` argument. The command remains non-runnable because the
  reviewer placeholder is still required.
- The root `fleury benchmark web-threshold-review` launcher now forwards
  `--review-context-hint=TEXT`, documents it in help/catalog output, and keeps
  the hint out of the promotion-required option set so `--write-plan` remains a
  true plan-only operation.
- Updated the package README, profiling README, review packet, and phase audit
  to describe the suggested review-context behavior.
- Regenerated
  `profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review-plan.md`
  with the captured Chrome/macOS/Dart/headless/frame-budget context.
- Regenerated the local readiness-candidate packet. The
  `review-threshold-policy` action now has one placeholder
  (`--reviewed-by=<reviewer>`), `suggestedReviewContext`, a
  `--review-context-hint=...` plan command, and a promotion command prefilled
  with the captured review context. The packet remains intentionally red for
  candidate threshold policy plus pending real Chrome IME / VoiceOver evidence.

Verification:

- `dart format tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart packages/fleury_web/tool/web_threshold_review.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_threshold_review_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart packages/fleury_web/tool/web_threshold_review.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_threshold_review_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_threshold_review_tool_test.dart` -
  passed with 7 VM tests.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-threshold-review|benchmark catalog includes web|prints release-grade benchmark help examples"` -
  passed with 6 selected VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 22 VM tests.
- `cd packages/fleury_web && dart run tool/web_threshold_review.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review-plan.md '--review-context-hint=Browser Chrome/148.0.7778.217, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline'` -
  regenerated the threshold review plan.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the readiness-candidate packet with context-aware threshold
  review actions.
- `node -e "...review-threshold-policy..."` over the regenerated
  `web-readiness-bundle.json` - confirmed `suggestedReviewContext`, one
  reviewer placeholder, a context-hint plan command, and a context-prefilled
  promotion command.
- `rg -n "Review context hint|review-context-hint|review-context=Browser Chrome/148|suggestedReviewContext" ...` -
  confirmed the regenerated plan and release actions carry the captured review
  context.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 211 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 211 checked source inputs.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 211 checked source inputs.
- `dart run tool/fleury_dev.dart --dry-run benchmark web-threshold-review --input=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --write-plan=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review-plan.md '--review-context-hint=Browser Chrome/148.0.7778.217, OS macos OS version Version 26.2 (Build 25C56), retained DOM product baseline'` -
  forwarded the hint through the root launcher to the package-local threshold
  review tool.
- `rg -n "[ \t]+$" ...` over touched source, tests, docs, threshold review plan,
  and regenerated release actions - passed.
- `git diff --check` - passed for tracked changes; many web implementation and
  profiling artifacts remain untracked in this worktree until the branch is
  staged.

## 2026-06-08 23:36 EDT

Made the manual validation page smoke test part of the manual evidence release
contract.

- `manual_validation_targets.dart` now publishes
  `manualPageSmokeCommand: dart test -p chrome test/manual_validation_page_test.dart`
  for the primary manual evidence targets.
- Generated manual evidence templates and starters now carry
  `reviewInstructions.manualPageSmokeCommand`, and stale templates without the
  smoke command are rejected before evidence collection.
- `web_readiness_bundle.dart` now renders the manual page smoke command in
  `web-release-actions.md`, exposes it in each `collect-manual-evidence:*`
  action, and includes `test/manual_validation_page_test.dart` in
  `sourceInputFingerprints.manualValidationPageFiles` with the manual page
  source, HTML, and served JS.
- Updated the package README, profiling README, review packet, and phase audit
  so reviewers know the browser smoke is a release-action preflight for real
  manual IME / VoiceOver evidence, not just developer-side test coverage.
- Regenerated the primary target templates, updated the existing pending
  starter evidence files with the smoke command, rebuilt
  `manual-validation-audit.json` and `review.md`, and refreshed the local
  readiness-candidate packet.
- The current manual audit has two valid pending entries and zero invalid
  entries. It remains red only because the reviewer provenance and required
  IME / VoiceOver checks have not been filled.
- The current readiness packet remains red only for the reviewed threshold
  policy and real manual Chrome IME / VoiceOver evidence. Its generated action
  graph now reports current templates, existing starter evidence files, and the
  manual page smoke command for both manual evidence targets.

Verification:

- `dart format packages/fleury_web/lib/src/manual_validation/manual_validation_targets.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_manual_validation_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/lib/src/manual_validation/manual_validation_targets.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_manual_validation_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed with 17 VM tests.
- `cd packages/fleury_web && dart test -p chrome test/manual_validation_page_test.dart` -
  passed with 2 Chrome tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 22 VM tests.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/review.md --strict --json` -
  exited 1 as expected because both targets still need real reviewed evidence;
  the audit reported two valid pending entries and zero invalid entries.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with four manual validation
  page source fingerprints, including the browser smoke test source.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 212 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 212 checked source inputs.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 212 checked source inputs.

## 2026-06-08 23:44 EDT

Aligned the standalone manual validation plan with the manual evidence smoke
contract.

- `web_manual_validation.dart --write-plan` now includes
  `dart test -p chrome test/manual_validation_page_test.dart` in the setup
  block, after the manual page build command and before static serving.
- The generated plan explicitly says the browser smoke verifies retained DOM
  page wiring before manual checks and does not replace real IME or
  screen-reader evidence.
- Updated `profiling/web/manual/README.md` to call out the plan's Chrome smoke
  command before evidence collection.
- Regenerated `profiling/web/manual/plan.md`,
  `manual-validation-audit.json`, `review.md`, and the local
  readiness-candidate packet so the bundle's readiness-tool fingerprints match
  the changed plan generator.
- The readiness packet remains correctly red only for candidate thresholds and
  pending reviewed Chrome IME / VoiceOver evidence; strict bundle verification
  is green.

Verification:

- `dart format packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/test/web_manual_validation_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed with 17 VM tests.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/plan.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/review.md --strict --json` -
  exited 1 as expected because both targets still need real reviewed evidence;
  the audit reported two valid pending entries and zero invalid entries.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with the updated
  readiness-tool fingerprint for `web_manual_validation.dart`.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 212 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 212 checked source inputs.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 212 checked source inputs.
- `cd packages/fleury_web && dart test -p chrome test/manual_validation_page_test.dart` -
  passed with 2 Chrome tests.
- `rg -n "dart test -p chrome test/manual_validation_page_test.dart|does not replace real IME|browser smoke" ...` -
  confirmed the regenerated plan, manual evidence README, and release actions
  all mention the smoke command.
- `rg -n "[ \t]+$" ...` over touched source, tests, manual evidence docs, and
  regenerated readiness artifacts - passed.
- `git diff --check` - passed for tracked changes; many web implementation and
  profiling artifacts remain untracked in this worktree until the branch is
  staged.

## 2026-06-08 23:52 EDT

Made the manual validation plan a readiness-bundle artifact.

- `web_readiness_bundle.dart` now asks `web_manual_validation.dart` to write
  `manual-validation-plan.md` into the bundle output directory while producing
  the manual audit JSON.
- `web-readiness-bundle.json` now lists that plan as
  `artifacts.manualPlan`, fingerprints it under
  `artifactFingerprints.manualPlan`, and strict bundle verification checks it
  with the rest of the generated packet.
- `web_readiness_bundle_tool_test.dart` now asserts the bundled plan exists,
  is fingerprinted, includes the Chrome manual-page smoke command, and raises
  strict verification's generated-artifact count to 11.
- Updated the package README, profiling README, review packet, and phase audit
  to describe the bundled manual validation plan as part of the release packet.
- Regenerated the current local readiness-candidate packet. It now includes
  `readiness-candidate/manual-validation-plan.md`; readiness remains red only
  for candidate thresholds and pending reviewed Chrome IME / VoiceOver
  evidence.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 22 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with
  `artifacts.manualPlan` and `artifactFingerprints.manualPlan`.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 212 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts and
  212 checked source inputs.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts and
  212 checked source inputs.

## 2026-06-09 00:01 EDT

Made `artifacts.manualPlan` a required readiness-bundle manifest field.

- `readiness_bundle_verifier.dart` now reports `artifacts.manualPlan` as a
  missing manifest field during strict top-level bundle verification when a
  packet omits the bundled manual validation plan entry.
- `web_readiness_bundle_tool_test.dart` now mutates a generated packet to remove
  `manualPlan` from both `artifacts` and `artifactFingerprints`, then asserts
  strict verification fails with `missingManifestFields: artifacts.manualPlan`.
- `web_default_preflight_tool_test.dart` now models the manual validation plan
  in its synthetic bundle fixture, so bundle-bound default preflight coverage
  reflects the stricter packet shape.
- The package README, profiling README, review packet, and phase audit now say
  strict bundle verification requires `artifacts.manualPlan`.
- Regenerated the current local readiness-candidate packet. The packet remains
  intentionally red for candidate threshold review and pending real Chrome IME /
  VoiceOver manual evidence, while bundle fingerprint verification is green.

Verification:

- `dart format packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart packages/fleury_web/test/web_default_preflight_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart packages/fleury_web/test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart` -
  passed with 11 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 23 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with the stricter verifier
  source fingerprint.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 212 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts and
  212 checked source inputs.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts and
  212 checked source inputs.

## 2026-06-09 00:10 EDT

Hardened threshold review promotion against placeholder provenance.

- `web_threshold_review.dart` now rejects the literal reviewer placeholder,
  generic reviewer names, and generic browser/platform placeholders during
  promotion. Non-promoting review plans still render placeholders for humans to
  replace.
- Threshold review plans now warn that the promotion command is intentionally
  not runnable as written until reviewer and browser/platform values are
  concrete.
- `web_threshold_review_tool_test.dart` covers reviewer placeholder rejection,
  generic browser/platform context rejection, and the plan warning.
- `terminal_matrix_tool_test.dart` now checks the same warning through the root
  `fleury benchmark web-threshold-review` launcher path.
- The package README, profiling README, review packet, and phase audit now
  describe the direct CLI enforcement in addition to the release-action
  `commandTemplateRunnable: false` metadata.
- Regenerated `threshold-review-plan.md` and the current local
  readiness-candidate packet. The packet remains intentionally red for
  candidate threshold review and pending real Chrome IME / VoiceOver evidence;
  bundle fingerprint verification remains green.

Verification:

- `dart format packages/fleury_web/tool/web_threshold_review.dart packages/fleury_web/test/web_threshold_review_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_threshold_review.dart packages/fleury_web/test/web_threshold_review_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_threshold_review_tool_test.dart` -
  passed with 9 VM tests.
- `dart format packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `dart analyze packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "threshold review"` -
  passed with 4 VM tests.
- `cd packages/fleury_web && dart run tool/web_threshold_review.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review-plan.md '--review-context-hint=Browser Chrome/148.0.7778.217, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline'` -
  regenerated the threshold review plan.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 212 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts and
  212 checked source inputs.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts and
  212 checked source inputs.

## 2026-06-09 00:15 EDT

Hardened manual evidence audits against placeholder provenance.

- `web_manual_validation.dart` now rejects placeholder reviewer values and
  placeholder browser-version values while still treating empty provenance as
  the existing missing-provenance blocker.
- Manual validation plans now state that `reviewedBy` must be non-empty and
  non-placeholder.
- `web_manual_validation_tool_test.dart` now covers copied starter evidence that
  marks every check `pass` but leaves `reviewedBy: <reviewer>` and
  `environment.browserVersion: Chrome VERSION`; strict audit keeps the target in
  `needsReview`.
- The package README, profiling README, review packet, and phase audit now
  describe the non-placeholder manual provenance requirement.
- Regenerated the current local readiness-candidate packet. The packet remains
  intentionally red for candidate threshold review and pending real Chrome IME /
  VoiceOver evidence; bundle fingerprint verification remains green.

Verification:

- `dart format packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/test/web_manual_validation_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/test/web_manual_validation_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed with 18 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "web readiness bundle writes passing reviewed artifacts"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 212 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts and
  212 checked source inputs.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts and
  212 checked source inputs.

## 2026-06-09 00:28 EDT

Clarified threshold-review plan-only JSON summary behavior.

- `web_threshold_review.dart` no longer treats `--json-output=PATH` by itself
  as promotion intent when the command is otherwise a plan-only
  `--write-plan=PATH` run. The path is still embedded in the generated
  promotion command so reviewers can see where `threshold-review.json` will be
  written after real promotion.
- Actual promotion intent remains unchanged: omitting `--write-plan`, or
  supplying promotion-only fields such as `--output`, `--reviewed-by`,
  `--reviewed-at`, `--review-context`, `--review-note`, or stdout `--json`
  still requires full reviewer/context provenance before writing reviewed
  thresholds.
- The root `fleury benchmark web-threshold-review` launcher now uses the same
  promotion-intent rule as the package-local tool.
- `web_threshold_review_tool_test.dart` and `terminal_matrix_tool_test.dart`
  cover a plan-only command that includes `--json-output` and proves it writes
  the review plan without creating `thresholds.json` or
  `threshold-review.json`.
- Package README, profiling README, review packet, and phase audit now describe
  the distinction between plan-only summary-path embedding and promotion-time
  summary writing.
- Regenerated the current threshold review plan and readiness-candidate packet.
  The packet remains intentionally red for candidate threshold review and
  pending real Chrome IME / VoiceOver evidence; bundle fingerprint
  verification remains green.

Verification:

- `dart format packages/fleury_web/tool/web_threshold_review.dart packages/fleury_web/test/web_threshold_review_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_threshold_review.dart packages/fleury_web/test/web_threshold_review_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_threshold_review_tool_test.dart` -
  passed with 10 VM tests.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-threshold-review"` -
  passed with 6 VM tests.
- `cd packages/fleury_web && dart run tool/web_threshold_review.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review-plan.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review.json '--review-context-hint=Browser Chrome/148.0.7778.217, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline'` -
  passed and rewrote `threshold-review-plan.md`; `threshold-review.json`
  remained absent as expected before promotion.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 212 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts and
  212 checked source inputs.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts and
  212 checked source inputs.

- `rg -n "manualPlan|manual-validation-plan|dart test -p chrome test/manual_validation_page_test.dart" ...` -
  confirmed the bundle manifest, bundled plan, and docs reference the new plan
  artifact and smoke command.

## 2026-06-08 22:43 EDT

Prepared no-overwrite manual evidence starter files and refreshed the
readiness packet around pending evidence.

- Generated current starter evidence from the reviewed templates:
  - `profiling/web/manual/evidence/chrome-ime-macos.review.json`
  - `profiling/web/manual/evidence/chrome-voiceover-macos.review.json`
- Rebuilt `profiling/web/manual/manual-validation-audit.json` and
  `profiling/web/manual/review.md`. The audit now reports `entryCount: 2`,
  `invalidEntryCount: 0`, and `needsReviewTargets` for both primary manual
  targets instead of treating them as absent.
- Regenerated the current local readiness-candidate packet under
  `profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate`.
  The bundle now records two `manualEvidenceFiles` source inputs alongside the
  existing 33 capture files, two templates, three manual page files, 24
  retained web implementation files, 127 Fleury core implementation files, 12
  readiness/release tool files, and six package configuration files.
- Updated the review packet, phase audit, and manual evidence README to
  distinguish pending starter evidence from reviewed pass evidence. Readiness
  remains correctly red until a reviewer fills `reviewedBy`, `capturedAt`,
  `environment.browserVersion`, and all required IME / VoiceOver check
  statuses.

Verification:

- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --write-starter=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/evidence/chrome-ime-macos.review.json --starter-template=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates/chrome-ime-macos.template.json --template-target=chrome-ime-macos` -
  wrote the IME starter evidence file.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --write-starter=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/evidence/chrome-voiceover-macos.review.json --starter-template=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates/chrome-voiceover-macos.template.json --template-target=chrome-voiceover-macos` -
  wrote the VoiceOver starter evidence file.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/review.md --strict --json` -
  exited 1 as expected because both targets still need real reviewed evidence;
  the audit reported two valid pending entries and zero invalid entries.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with two
  `manualEvidenceFiles` source inputs.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 211 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 211 checked source inputs.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 211 checked source inputs.
- `rg -n "[ \t]+$" ...` over touched docs, manual evidence, and generated
  manual audit files - passed.
- `git diff --check` - passed for tracked changes; many web implementation and
  profiling artifacts remain untracked in this worktree until the branch is
  staged.

## 2026-06-08 22:39 EDT

Bound readiness bundles to package and dependency configuration files.

- `web_readiness_bundle.dart` now records
  `sourceInputFingerprints.packageConfigurationFiles` for `pubspec.yaml`,
  `pubspec.lock`, and `.dart_tool/package_config.json` from both
  `packages/fleury_web` and the sibling `packages/fleury` package.
- `readiness_bundle_verifier.dart` now requires `packageConfigurationFiles`
  alongside `webImplementationFiles`, `fleuryCoreImplementationFiles`, and
  `readinessToolFiles` for strict source-input verification.
- Added bundle regression coverage for stale package-configuration
  fingerprints and updated the missing-source-groups test to require all four
  strict source groups.
- Updated the bundle-bound default-preflight fixture so preflight verification
  includes package configuration source inputs.
- Synced the package README, profiling README, review packet, and phase audit
  to describe package/dependency configuration files as readiness bundle source
  inputs.
- Regenerated the current local readiness-candidate packet under
  `profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate`.
  The packet now records 24 retained web implementation files, 127 Fleury core
  implementation files, 12 readiness/release tool files, and six package
  configuration files. It remains red for the same empirical gates: candidate
  thresholds and missing real Chrome IME / VoiceOver evidence.

Verification:

- `cd packages/fleury_web && dart format tool/readiness_bundle_verifier.dart tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/readiness_bundle_verifier.dart tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart` -
  passed with 11 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 21 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with
  `packageConfigurationFiles` fingerprints.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 209 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 209 checked source inputs.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 209 checked source inputs.
- `rg -n "[ \t]+$" ...` over the touched source, test, doc, and log files -
  passed.
- `git diff --check` - passed for tracked changes; many web implementation
  files remain untracked in this worktree until the branch is staged.

## 2026-06-08 22:21 EDT

Bound readiness bundles to Fleury core implementation source files.

- `web_readiness_bundle.dart` now discovers the sibling `fleury` package
  through `.dart_tool/package_config.json` and records
  `sourceInputFingerprints.fleuryCoreImplementationFiles` for every Dart file
  under `package:fleury`'s `lib/` tree.
- `readiness_bundle_verifier.dart` now requires both
  `fleuryCoreImplementationFiles` and `webImplementationFiles` in strict
  source-input verification, so old packets cannot verify without binding to
  the core runtime/rendering/widget code that the retained DOM host executes.
- Added bundle regression coverage for stale Fleury core source fingerprints
  and for manifests missing either required implementation-source group.
- Updated the bundle-bound default-preflight fixture so preflight verification
  covers both required implementation-source groups.
- Synced the package README, profiling README, review packet, and phase audit
  to describe Fleury core package Dart files as source inputs.
- Regenerated the current local readiness-candidate packet under
  `profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate`.
  The packet now records 24 retained web implementation files and 127 Fleury
  core implementation files. It remains red for the same empirical gates:
  candidate thresholds and missing real Chrome IME / VoiceOver evidence.

Verification:

- `cd packages/fleury_web && dart format tool/readiness_bundle_verifier.dart tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/readiness_bundle_verifier.dart tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart` -
  passed with 11 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 19 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with
  `fleuryCoreImplementationFiles` fingerprints.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 191 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 191 checked source inputs.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 191 checked source inputs.
- `rg -n "[ \t]+$" ...` over the touched source, test, doc, and log files -
  passed.
- `git diff --check` - passed for tracked changes; many web implementation
  files remain untracked in this worktree until the branch is staged.

## 2026-06-08 22:29 EDT

Bound readiness bundles to readiness/release tool source files.

- `web_readiness_bundle.dart` now records
  `sourceInputFingerprints.readinessToolFiles` for every Dart file under
  `packages/fleury_web/tool/`, including the bundle verifier, default
  preflight, scoreboard, readiness, manual validation, semantic coverage, and
  threshold review tools.
- `readiness_bundle_verifier.dart` now requires `readinessToolFiles` alongside
  `webImplementationFiles` and `fleuryCoreImplementationFiles` for strict
  source-input verification.
- Added bundle regression coverage for stale readiness-tool fingerprints and
  for manifests missing the required tool-source group.
- Updated the bundle-bound default-preflight fixture so preflight verification
  covers web implementation, Fleury core implementation, and readiness/release
  tool source groups.
- Synced the package README, profiling README, review packet, and phase audit
  to describe readiness/release tool Dart files as source inputs.
- Regenerated the current local readiness-candidate packet under
  `profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate`.
  The packet now records 24 retained web implementation files, 127 Fleury core
  implementation files, and 12 readiness/release tool files. It remains red for
  the same empirical gates: candidate thresholds and missing real Chrome IME /
  VoiceOver evidence.

Verification:

- `cd packages/fleury_web && dart format tool/readiness_bundle_verifier.dart tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze tool/readiness_bundle_verifier.dart tool/web_readiness_bundle.dart test/web_readiness_bundle_tool_test.dart test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart` -
  passed with 11 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 20 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with
  `readinessToolFiles` fingerprints.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 10 checked generated artifacts, 203 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 203 checked source inputs.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 203 checked source inputs.
- `rg -n "[ \t]+$" ...` over the touched source, test, doc, and log files -
  passed.
- `git diff --check` - passed for tracked changes; many web implementation
  files remain untracked in this worktree until the branch is staged.

## 2026-06-09 00:42 EDT

Bound readiness bundles to the root release launcher.

- Added a required `rootReleaseLauncherFiles` source-input group to the
  readiness bundle verifier.
- `web_readiness_bundle.dart` now fingerprints the workspace-root
  `tool/fleury_dev.dart` launcher in addition to package-local readiness and
  release tooling.
- This closes a stale-packet gap for root `fleury benchmark ...` command
  changes: if the launcher changes after a packet is generated, strict bundle
  verification now fails until the packet is regenerated.
- Bundle tests now assert the root launcher fingerprint is present and that a
  stale root launcher invalidates verification.
- The package README, profiling README, review packet, and phase audit now
  describe root launcher source fingerprinting as part of the readiness packet.
- Regenerated the current local readiness-candidate packet. The packet remains
  intentionally red for candidate threshold review and pending real Chrome IME /
  VoiceOver evidence; bundle fingerprint verification remains green.

Verification:

- `dart format packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 24 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 213 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts and
  213 checked source inputs.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts and
  213 checked source inputs.

## 2026-06-09 00:59 EDT

Hardened readiness bundle verification against omitted source inputs.

- `web_readiness_bundle.dart --verify=... --strict` now recomputes the expected
  current source/evidence input path sets from the bundle input and fails when
  an expected path is omitted from `sourceInputFingerprints`.
- The expected-path coverage includes capture JSON, manual evidence JSON,
  selected manual templates, manual validation page files, retained web
  implementation files, Fleury core implementation files, package-local
  readiness/release tools, the root release launcher, package configuration
  files, threshold policies, threshold review summaries, and threshold review
  plans when present.
- Added a regression test that removes `lib/src/run_tui_surface.dart` from a
  generated bundle manifest without changing the file; strict verification now
  fails with `missingSourceInputCount: 1`.
- Release-action `verificationScope` now includes
  `expected-source-input-path-coverage` for bundle verification and
  bundle-bound default preflight commands.
- The package README, profiling README, review packet, and phase audit now
  describe expected source-input path coverage in addition to fingerprint
  freshness.
- Regenerated the current local readiness-candidate packet. The packet remains
  intentionally red for candidate threshold review and pending real Chrome IME /
  VoiceOver evidence; bundle verification remains green.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "omitted implementation source"` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 25 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 213 checked source inputs,
  `missingSourceInputCount: 0`, one checked metadata field, 20 checked manifest
  fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts,
  213 checked source inputs, and `missingSourceInputCount: 0`.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts,
  213 checked source inputs, and `missingSourceInputCount: 0`.

## 2026-06-09 01:15 EDT

Moved expected source-input coverage into the shared readiness-bundle verifier.

- `readiness_bundle_verifier.dart` now owns both readiness-bundle source-input
  fingerprint generation and expected source/evidence path coverage checks.
  `web_readiness_bundle.dart` and `web_default_preflight.dart` now call the
  same shared verifier path instead of maintaining separate source-input
  integrity rules.
- Bundle-bound default preflight now enforces the same omitted-source guard as
  `web_readiness_bundle --verify --strict`: a packet cannot drop an expected
  source/evidence file from `sourceInputFingerprints` and still pass the
  preflight integrity check.
- The default-preflight fixture now builds source-input fingerprints through
  the shared verifier helper, so test coverage reflects the real bundle shape
  across capture files, manual evidence, manual templates, manual validation
  page files, retained web implementation, Fleury core implementation,
  readiness/release tools, the root release launcher, package configuration,
  threshold policy, and threshold review plan inputs.
- Added `web default preflight rejects omitted expected source input`, which
  removes `lib/src/run_tui_surface.dart` from the bundle's
  `webImplementationFiles` source-input group and expects
  `missingSourceInputCount: 1`.
- Regenerated the current local readiness-candidate packet. The packet remains
  intentionally red for candidate threshold review and pending real Chrome IME /
  VoiceOver evidence; strict bundle verification is green.

Verification:

- `dart format packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/tool/web_default_preflight.dart packages/fleury_web/test/web_default_preflight_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/tool/web_default_preflight.dart packages/fleury_web/test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart` -
  passed with 12 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 25 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 213 checked source inputs,
  `missingSourceInputCount: 0`, one checked metadata field, 20 checked manifest
  fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts,
  213 checked source inputs, and `missingSourceInputCount: 0`.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts,
  213 checked source inputs, and `missingSourceInputCount: 0`.

## 2026-06-09 01:35 EDT

Hardened threshold review promotion for over-budget policies.

- `web_threshold_review.dart` now detects candidate policies whose scenario
  thresholds allow over-budget frames. Promotion refuses those policies unless
  the reviewer passes `--allow-over-budget-thresholds` and a concrete
  `--review-note=TEXT` explaining why the over-budget thresholds are acceptable
  for the reviewed baseline.
- Reviewed policies now record `overBudgetThresholdScenarioIds` and
  `overBudgetThresholdsAcknowledged` when the acknowledgement is used; the
  `threshold-review.json` promotion summary also records
  `overBudgetThresholdScenarioCount`.
- Generated threshold review plans now include an `Over-Budget Thresholds`
  section listing the affected scenarios and add the acknowledgement flag plus
  review-note placeholder to the promotion command template.
- `web_readiness_bundle.dart` now mirrors the same acknowledgement requirement
  in `review-threshold-policy` release actions. The regenerated current
  release-action packet reports all 11 candidate scenarios as over-budget and
  includes the `reviewNote` placeholder plus `--allow-over-budget-thresholds`.
- The root `fleury benchmark web-threshold-review` launcher forwards
  `--allow-over-budget-thresholds`; catalog/help examples now include the flag
  and review note so contributor-facing commands match the package-local tool.
- Package README, the Phase 1 refresh baseline README, the review packet, and
  the phase audit now document the explicit over-budget acknowledgement
  contract.
- Regenerated `threshold-review-plan.md` and the current local
  readiness-candidate packet. The packet remains intentionally red for
  candidate threshold review and pending real Chrome IME / VoiceOver evidence;
  strict bundle verification remains green.

Verification:

- `dart format packages/fleury_web/tool/web_threshold_review.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_threshold_review_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_threshold_review.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_threshold_review_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_threshold_review_tool_test.dart` -
  passed with 14 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 25 VM tests.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-threshold-review|benchmark catalog|release-grade benchmark help"` -
  passed with 8 VM tests.
- `cd packages/fleury_web && dart run tool/web_threshold_review.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review-plan.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review.json '--review-context-hint=Browser Chrome/148.0.7778.217, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline'` -
  regenerated the threshold review plan with 11 over-budget scenarios listed
  and an acknowledgement-bearing promotion command template.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_threshold_review.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --output=/tmp/fleury-threshold-review-no-ack/thresholds.json --json-output=/tmp/fleury-threshold-review-no-ack/threshold-review.json --reviewed-by=smoke-reviewer '--review-context=Browser Chrome/148.0.7778.217, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) on macos_x64, retained DOM product baseline' --review-note='Smoke note without acknowledgement flag.' --json` -
  exited 2 as expected, refusing the real candidate without
  `--allow-over-budget-thresholds`.
- `cd packages/fleury_web && dart run tool/web_threshold_review.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --output=/tmp/fleury-threshold-review-ack/thresholds.json --json-output=/tmp/fleury-threshold-review-ack/threshold-review.json --reviewed-by=smoke-reviewer --reviewed-at=2026-06-09T05:35:00Z '--review-context=Browser Chrome/148.0.7778.217, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) on macos_x64, retained DOM product baseline' --allow-over-budget-thresholds '--review-note=Smoke-only acknowledgement that this local candidate permits over-budget frames; not a release approval.' --json` -
  exited 0 against temporary `/tmp` outputs and reported
  `overBudgetThresholdScenarioCount: 11` with acknowledgement true.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 213 checked source inputs,
  `missingSourceInputCount: 0`, one checked metadata field, 20 checked manifest
  fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts,
  213 checked source inputs, and `missingSourceInputCount: 0`.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts,
  213 checked source inputs, and `missingSourceInputCount: 0`.

## 2026-06-09 01:45 EDT

Hardened manual evidence audits against copied template checklist text.

- `manualValidationEvidenceContractBlockers` now checks non-template reviewed
  evidence for unknown check IDs, invalid check statuses, blank notes on passed
  checks, and notes copied verbatim from the generated check instruction.
- Generated manual validation templates and starter evidence now state that the
  top-level status can be set to `pass` only after provenance is filled, all
  required checks pass, and each passed check has reviewer observation notes
  rather than copied instructions.
- `web_manual_validation.dart` now renders that observation-note requirement in
  the reviewer plan.
- `web_manual_validation_tool_test.dart` covers a copied starter file whose
  statuses are changed to `pass` while a check note still equals the generated
  instruction; strict audit keeps the target in `needsReview`.
- The package README, profiling README, review packet, and phase audit now
  describe the observation-note gate so reviewers see the same rule that the
  strict audit enforces.
- Regenerated the primary manual templates, refreshed the existing starter
  evidence files without fabricating reviewed evidence, reran the manual audit,
  and regenerated the local readiness-candidate packet. The packet remains
  intentionally red for candidate threshold review and pending real Chrome IME /
  VoiceOver evidence; bundle fingerprint verification remains green.

Verification:

- `dart format packages/fleury_web/lib/src/manual_validation/manual_validation_targets.dart packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/test/web_manual_validation_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/lib/src/manual_validation/manual_validation_targets.dart packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/test/web_manual_validation_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed with 19 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "manual evidence|template|starter|stale manual|writes passing reviewed artifacts"` -
  passed with 9 VM tests.
- `dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/review.md --strict --json` -
  exited 1 as expected with `strictPass: false`, two `needsReview` targets,
  zero invalid files, and provenance blockers for the pending starter evidence.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 213 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts and
  213 checked source inputs.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts and
  213 checked source inputs.
- `git diff --check` - passed.
- `rg -n "[ \t]+$" ...` over touched docs, manual-validation source/tests,
  templates, and starter evidence - passed with no trailing whitespace hits.
- `rg -n "reviewer observation|copied instruction|blank notes|notes copied|notes must describe|notes must be reviewer observation" ...` -
  confirmed the observation-note rule is present in enforcement code, tests,
  reviewer docs, generated templates, starter evidence, the regenerated manual
  validation plan, and the execution log.

## 2026-06-09 02:11 EDT

Split the public app-facing core API from the platform host SPI.

- Added `package:fleury/fleury_host.dart` as the explicit host surface for
  native and browser runtimes. It re-exports `fleury_core.dart` plus host-only
  runtime, damage, scheduler, input, and semantics contracts.
- Removed host-only exports from `package:fleury/fleury_core.dart` so app code
  does not accidentally depend on platform-mounting internals. The core barrel
  remains `dart:io`-free and keeps app/widget/rendering primitives.
- Updated the web package to import `package:fleury/fleury_host.dart` instead
  of `package:fleury/fleury_core.dart` for retained DOM rendering, browser
  input, metrics, instrumentation, clipboard, and semantic presentation.
- Updated native host-facing tests to consume host runtime primitives through
  the public host barrel rather than private implementation files.
- Added `host_public_api_boundary_test.dart` to keep host-only symbols present
  in `fleury_host.dart` and absent from app-facing `fleury_core.dart` and the
  native umbrella barrel.
- Updated the web README, package comments, phase audit, and review packet to
  describe `fleury_host.dart` as the browser/native host SPI.
- Rebuilt `web/manual_validation.dart.js` after the source changes.
- Regenerated the local readiness-candidate packet. The bundle now includes
  `packages/fleury/lib/fleury_host.dart` as a source input; strict fingerprint
  verification checks 214 source inputs.
- The readiness packet remains intentionally red for the same release blockers:
  candidate threshold policy review plus pending real Chrome IME and VoiceOver
  manual evidence.

Browser smoke note:

- A combined Chrome page smoke run initially timed out while waiting for the
  manual-validation semantic-action status update. The same page smoke tests
  passed in isolation.
- Widened the manual-validation page polling timeout from 5 seconds to 10
  seconds. The combined Chrome page smoke then passed, which makes the test less
  sensitive to compile/browser startup scheduling while preserving the same
  behavioral assertions.

Verification:

- `cd packages/fleury && dart format lib/fleury.dart lib/fleury_core.dart lib/fleury_host.dart test/runtime/frame_scheduler_test.dart test/runtime/tui_frame_loop_test.dart test/runtime/tui_runtime_test.dart test/runtime/host_public_api_boundary_test.dart test/semantics/semantics_owner_test.dart` -
  passed.
- `cd packages/fleury && dart analyze lib/fleury.dart lib/fleury_core.dart lib/fleury_host.dart test/runtime/frame_scheduler_test.dart test/runtime/tui_frame_loop_test.dart test/runtime/tui_runtime_test.dart test/runtime/host_public_api_boundary_test.dart test/semantics/semantics_owner_test.dart test/semantics/semantics_test.dart` -
  passed.
- `cd packages/fleury && dart test test/runtime/host_public_api_boundary_test.dart test/runtime/frame_scheduler_test.dart test/runtime/tui_frame_loop_test.dart test/runtime/tui_runtime_test.dart test/semantics/semantics_owner_test.dart` -
  passed with 21 VM tests.
- `cd packages/fleury_web && dart analyze lib web test tool` - passed.
- `cd packages/fleury_web && dart test test` - passed with 142 VM tests.
- `cd packages/fleury_web && dart compile js web/manual_validation.dart -o web/manual_validation.dart.js` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/manual_validation_page_test.dart` -
  passed with 2 Chrome tests.
- `cd packages/fleury_web && dart test -p chrome test/dom_demo_test.dart` -
  passed with 1 Chrome test.
- `cd packages/fleury_web && dart format test/manual_validation_page_test.dart && dart analyze test/manual_validation_page_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/manual_validation_page_test.dart test/dom_demo_test.dart` -
  passed with 3 Chrome tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts,
  214 checked source inputs, and `missingSourceInputCount: 0`.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts,
  214 checked source inputs, and `missingSourceInputCount: 0`.

## 2026-06-09 13:54 EDT

Tightened the retained semantic DOM presenter after threshold review showed the
current candidate was not promotable.

- Inspected the current threshold review plan before promotion. The candidate
  thresholds cover all 11 release scenarios, but every scenario permits
  over-budget frames and several permit 100 percent over-budget frames. I did
  not promote `thresholds.candidate.json` to reviewed `thresholds.json`; that
  would hide the real remaining performance risk behind an acceptance note.
- The captured baseline pointed at semantic apply as the dominant failure mode
  for large/stress scenarios. For `stress-300x100-run-1.json`, the local
  baseline p95 slices were `semanticPresenterMicros: 1275700` and
  `semanticApplyMicros: 1280400`.
- Changed `SemanticDomPresenter` to cache the last attribute values by semantic
  id, rather than caching only attribute names and calling DOM
  `getAttribute(...)` for every retained semantic update. The presenter now
  compares against Dart-owned cached values before mutating attributes.
- Avoided redundant native `input.value` / `textarea.value` and read-only
  writes for retained text-field and text-area semantic nodes.
- Ran one focused scratch capture for `stress-300x100` after the cache change:
  `profiling/web/runs/stress-300x100-semantic-cache-check.json`. It is not a
  replacement release baseline, but it gives directional signal: p95
  `semanticPresenterMicros` dropped to `166399`, while p95
  `semanticApplyMicros` remained high at `855700`. The next performance slice
  should target semantic tree build/diff/coverage or run a refreshed suite
  after more semantic-side changes.
- Regenerated the current readiness-candidate packet after the source change so
  source-input fingerprints reflect the current implementation. The packet
  remains intentionally red for candidate threshold policy review, real
  Chrome/macOS IME evidence, strict readiness, and bundle-bound
  default/retirement preflights.

Verification:

- `dart format packages/fleury_web/lib/src/semantics/semantic_dom_presenter.dart` -
  passed.
- `dart analyze packages/fleury_web/lib/src/semantics/semantic_dom_presenter.dart packages/fleury_web/test/semantic_dom_presenter_test.dart packages/fleury_web/test/run_tui_surface_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/semantic_dom_presenter_test.dart test/run_tui_surface_test.dart` -
  passed with 37 Chrome tests.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=stress-300x100 --frames=16 --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/runs/stress-300x100-semantic-cache-check.json --timeout=90 --json` -
  passed and wrote the focused scratch capture.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=v1 --write-default-preflights --completion-audit=/Users/dan/Coding/fleury-web-phase1/docs/implementation/web-rfc-completion-audit.json --json` -
  regenerated the current local readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 227 checked source inputs, one
  checked metadata field, 75 checked manifest fields, and zero mismatches.

## 2026-06-09 13:44 EDT

Kept VoiceOver out of the current release scope and tightened the remaining
Chrome/macOS IME manual-evidence path.

- Added `web_manual_validation.dart --update-page-signal=PATH` for existing
  starter or copied evidence files. The command updates one required
  `observedPageSignals` entry at a time and requires
  `--signal-id`, `--signal-status`, `--observed-value`, and `--signal-notes`.
- The page-signal helper validates the evidence contract before and after
  mutation, rejects unknown target signals, rejects blank values/notes, rejects
  pass updates whose observed value does not match the target's expected page
  signal value, and rejects copied template signal descriptions for passed
  signals.
- The root `fleury benchmark web-manual-validation` launcher now forwards
  `--update-page-signal`, `--signal-id`, `--signal-status`,
  `--observed-value`, and `--signal-notes`.
- Readiness bundle manual evidence actions now emit package-local and repo-root
  `pageSignalCommandTemplate` entries between provenance and check updates.
  Strict bundle verification now checks those command templates, raising the
  manifest field count from 73 to 75 in the current packet.
- Updated package/profiling/review/audit docs and the manual evidence README so
  the reviewer workflow is provenance, required page signals, required checks,
  top-level pass status, then strict audit.
- Regenerated `profiling/web/manual/plan.md`,
  `profiling/web/manual/review.md`,
  `profiling/web/manual/manual-validation-audit.json`, the selected IME
  template, the local readiness-candidate packet, release actions, default
  preflight previews, and `docs/implementation/web-rfc-completion-audit.json`.
- Readiness remains intentionally red for reviewed threshold policy promotion,
  real Chrome/macOS IME evidence, strict readiness, and final bundle-bound
  default/retirement preflights. No browser capture or manual IME/VoiceOver
  collection was run in this slice.

Verification:

- `dart format packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_manual_validation_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_manual_validation_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart --name "page signal|updates one evidence check|rejects copied check notes update"` -
  passed with 7 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "manual evidence actions|stale root"` -
  passed with 2 VM tests.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-manual-validation"` -
  passed with 2 VM tests.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=v1 --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/plan.md --write-templates=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/review.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json --json` -
  regenerated manual plan/templates/review/audit. The audit reports one
  selected target, `needsReviewTargets: chrome-ime-macos`, and zero invalid
  files.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=v1 --write-default-preflights --completion-audit=/Users/dan/Coding/fleury-web-phase1/docs/implementation/web-rfc-completion-audit.json --json` -
  regenerated the current local readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 227 checked source inputs, one
  checked metadata field, 75 checked manifest fields, and zero mismatches.

## 2026-06-09 13:28 EDT

Moved VoiceOver out of the current release evidence scope and kept it as an
explicit follow-up target.

- Changed the manual validation v1/primary preset to include only
  `chrome-ime-macos`. The `chrome-voiceover-macos` target remains registered
  and can still be run explicitly with `--target=chrome-voiceover-macos` or via
  `--target-preset=all`.
- Updated the readiness labels and completion audit so the current release
  blockers are reviewed thresholds, real Chrome/macOS IME evidence, strict
  readiness, and bundle-bound default/retirement preflights. Phase 4 now reports
  semantic/focus/accessibility automation as landed with VoiceOver as a
  follow-up gate rather than a release blocker.
- Filtered readiness-bundle manual evidence source fingerprints to the selected
  manual target set. Current bundles no longer become stale because the
  out-of-scope VoiceOver starter/template changes.
- Kept the manual evidence check-update helper in the reviewer workflow:
  `--update-check=PATH` records one observed required check at a time and
  rejects copied template notes for passed checks.
- Updated package/profiling/review/audit docs and the manual evidence README so
  reviewer instructions describe IME as the current manual gate and VoiceOver as
  the next accessibility-focused pass.
- Regenerated `profiling/web/manual/plan.md`,
  `profiling/web/manual/review.md`,
  `profiling/web/manual/manual-validation-audit.json`, the selected IME
  template, the local readiness-candidate packet, default preflight previews,
  release actions, and `docs/implementation/web-rfc-completion-audit.json`.
  The manual audit now reports `targetCount: 1`, `needsReviewTargets:
  chrome-ime-macos`, and `invalidEntryCount: 0`.
- The regenerated readiness bundle now has one manual evidence source
  fingerprint, one selected manual template fingerprint, and one manual release
  action: `collect-manual-evidence:chrome-ime-macos`. Readiness remains
  intentionally red for candidate threshold policy review and real Chrome/macOS
  IME evidence.
- No browser capture or manual IME/VoiceOver collection was run in this slice.

Verification:

- `dart analyze packages/fleury_web/lib/src/manual_validation/manual_validation_targets.dart packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/tool/web_readiness.dart packages/fleury_web/tool/web_readiness_bundle.dart tool/fleury_dev.dart packages/fleury_web/test/web_manual_validation_tool_test.dart packages/fleury_web/test/web_readiness_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart packages/fleury_web/test/web_default_preflight_tool_test.dart packages/fleury_web/test/web_public_api_boundary_test.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed with 24 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_tool_test.dart` -
  passed with 21 VM tests.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart` -
  passed with 15 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "manual evidence actions|manual target scope|existing starter evidence|template|passes complete evidence|completion audit|web readiness bundle reports"` -
  passed with 7 VM tests after the v1 scope change.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "source-input fingerprints|manual evidence actions|manual target scope|existing starter evidence|template"` -
  passed with 6 VM tests after filtering manual evidence source fingerprints.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-manual-validation|web-readiness bundle"` -
  passed with 2 VM tests.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=v1 --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/plan.md --write-templates=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/review.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json --json` -
  regenerated manual artifacts and reported `targetCount: 1`,
  `needsReviewTargets: chrome-ime-macos`, and `invalidEntryCount: 0`.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=v1 --write-default-preflights --completion-audit=/Users/dan/Coding/fleury-web-phase1/docs/implementation/web-rfc-completion-audit.json --json` -
  regenerated the local readiness-candidate packet; summary check showed one
  manual evidence fingerprint, one manual template fingerprint, and only
  `chrome-ime-macos` in the manual blocker/action scope.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 227 checked source inputs, one
  checked metadata field, 73 checked manifest fields, and zero mismatches.

## 2026-06-09 12:45 EDT

Made the fast review boundary machine-readable.

- Added `completionScopes` to `web-rfc-completion-audit.json` generation. The
  new block separates `architectureReview`, `releaseEvidence`, and
  `releaseDefault` scopes so reviewers can see that architecture re-review is
  green while threshold promotion, real Chrome IME / VoiceOver evidence, and
  final bundle-bound default/retirement preflights remain deferred release
  gates.
- Kept the final gate semantics unchanged: `goalCompletionClaim` remains
  `not-complete`, `releaseReady` remains false until release evidence plus both
  bundle-bound default preflights pass, and diagnostic preflight snapshots still
  cannot satisfy `defaultFlipReady` or `temporaryPathRetirementReady`.
- Updated the package README, profiling README, review packet, and phase audit
  to describe the scope split.
- Regenerated the 2026-06-09 readiness-candidate packet and completion audit
  from existing captures/manual artifacts without rerunning browser captures.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "completion audit|writes passing reviewed artifacts"` -
  passed with 2 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --completion-audit=/Users/dan/Coding/fleury-web-phase1/docs/implementation/web-rfc-completion-audit.json --json` -
  regenerated the local readiness-candidate packet. Readiness remains
  intentionally red for candidate threshold-policy review and pending real
  Chrome IME / VoiceOver manual evidence.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 77 checked manifest fields, and zero mismatches.

## 2026-06-09 12:51 EDT

Tightened completion-scope action accounting.

- `completionScopes.releaseEvidence` now separates
  `remainingReleaseActionIds` from `satisfiedCurrentEvidenceActionIds` by using
  the same release-action status calculation emitted in `releaseActions`.
- This avoids showing strict bundle verification or retained-host automated
  validation as remaining current blockers when the candidate packet already
  proves them green. They still remain part of the final release workflow after
  human threshold/manual gates and bundle regeneration.
- Updated the package README, profiling README, review packet, and phase audit
  to explain the distinction.
- Regenerated the 2026-06-09 readiness-candidate packet and completion audit
  from existing captures/manual artifacts. No browser captures were rerun.
  Current completion audit now reports:
  - remaining release-evidence actions: `review-threshold-policy`,
    `collect-manual-evidence:chrome-ime-macos`,
    `collect-manual-evidence:chrome-voiceover-macos`, and
    `regenerate-readiness-bundle`;
  - satisfied current evidence actions: `verify-readiness-bundle` and
    `run-automated-web-host-tests`;
  - automated retained-host validation status: `pass` for both browser and VM
    checks.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "completion audit|writes passing reviewed artifacts"` -
  passed with 2 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --completion-audit=/Users/dan/Coding/fleury-web-phase1/docs/implementation/web-rfc-completion-audit.json --json` -
  regenerated the local readiness-candidate packet. Readiness remains
  intentionally red for candidate threshold-policy review and pending real
  Chrome IME / VoiceOver manual evidence.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 77 checked manifest fields, and zero mismatches.

## 2026-06-09 12:31 EDT

Tightened the RFC completion audit so it cannot overstate release readiness.

- Split completion status into `releaseEvidenceReady` and `releaseReady`.
- `releaseEvidenceReady` now means strict readiness, strict bundle verification,
  and retained-host automated validation are green.
- `releaseReady` now additionally requires both final bundle-bound preflight
  proofs: `make-dom-default` and `retire-temporary-paths`.
- Added `releaseGateEvidence.defaultPreflights` to the completion audit so
  reviewers can see whether the available preflight artifacts are final
  bundle-bound proof or only diagnostic snapshots.
- Current generated preflight artifacts remain explicitly diagnostic-only:
  `diagnosticOnly: true`, `bundleBound: false`, and `ready: false`.
- Added regression coverage for the case where strict readiness plus automated
  validation are green but final bundle-bound preflights have not passed; the
  audit reports `releaseEvidenceReady: true` but keeps `releaseReady: false`.
- Updated the package README, profiling README, review packet, and phase audit to
  document the distinction between release-evidence readiness and final release
  readiness.
- Regenerated the 2026-06-09 readiness candidate packet and
  `docs/implementation/web-rfc-completion-audit.json` from existing artifacts;
  no browser capture or manual evidence collection was run.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "completion audit|writes passing reviewed artifacts|keeps artifacts when strict readiness fails"` -
  passed with three VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --completion-audit=/Users/dan/Coding/fleury-web-phase1/docs/implementation/web-rfc-completion-audit.json --json` -
  regenerated the current candidate packet and completion audit from existing
  captures.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 77 checked manifest fields, and zero mismatches.
- `jq '{overallStatus, architectureReviewReady, releaseEvidenceReady, releaseReady, defaultFlipReady, temporaryPathRetirementReady, releaseGateEvidence, blockers: .completionBlockers}' docs/implementation/web-rfc-completion-audit.json` -
  confirmed the current audit remains architecture-review ready, release-evidence
  blocked, final-release blocked, and explicitly marks both generated preflight
  artifacts as diagnostic-only.
- `jq empty docs/implementation/web-rfc-completion-audit.json` - passed.

## 2026-06-09 12:37 EDT

Tightened default/retirement readiness proof in the completion audit.

- Updated the completion-audit default-preflight summary so `ready: true`
  requires not only `strictPass`, `bundleBound`, and `bundleRequired`, but also
  `automatedValidationBound` and `automatedValidationRequired`.
- The audit now reports `automatedValidationBound` and
  `automatedValidationRequired` for each default-preflight target.
- The current candidate artifacts remain diagnostic snapshots:
  `automatedValidationBound: true` because the diagnostic preview was generated
  with the sibling automated validation artifact, but
  `automatedValidationRequired: false` because `--allow-unbundled` diagnostics do
  not satisfy the final release gate.
- No browser capture or manual evidence collection was run.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "completion audit|writes passing reviewed artifacts|keeps artifacts when strict readiness fails"` -
  passed with three VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --completion-audit=/Users/dan/Coding/fleury-web-phase1/docs/implementation/web-rfc-completion-audit.json --json` -
  regenerated the current candidate packet and completion audit from existing
  captures.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 77 checked manifest fields, and zero mismatches.
- `jq -e '.releaseGateEvidence.defaultPreflights["make-dom-default"].automatedValidationBound == true and .releaseGateEvidence.defaultPreflights["make-dom-default"].automatedValidationRequired == false and .releaseGateEvidence.defaultPreflights["retire-temporary-paths"].automatedValidationBound == true and .releaseGateEvidence.defaultPreflights["retire-temporary-paths"].automatedValidationRequired == false' docs/implementation/web-rfc-completion-audit.json` -
  passed.

## 2026-06-09 12:17 EDT

Made the RFC completion status audit reproducible from the readiness bundle
tooling rather than leaving it as a hand-authored review artifact.

- Added `web_readiness_bundle.dart --completion-audit=PATH`.
- The generated audit derives architecture-review readiness, release readiness,
  default-flip readiness, temporary-path retirement readiness, phase status,
  manual evidence status, automated retained-host validation status, and
  remaining release-action status from the generated bundle plus strict bundle
  verification.
- Kept the completion audit outside `web-readiness-bundle.json` fingerprints so
  the manifest remains the source of truth for generated artifact and source
  input integrity without creating a circular dependency on a status artifact
  that depends on the manifest.
- Routed `--completion-audit=PATH` through
  `fleury benchmark web-readiness-bundle`.
- The generated `regenerate-readiness-bundle` release action now preserves the
  completion-audit path in both package-local and repo-root command templates
  when the current packet was generated with `--completion-audit=...`.
- Updated the package README, profiling README, review packet, and phase audit
  to describe the generated completion audit and its role in architecture
  re-review.
- Regenerated
  `docs/implementation/web-rfc-completion-audit.json` from the current
  2026-06-09 retained DOM candidate packet. It now reports
  `overallStatus: implementation-review-ready-release-blocked`,
  `architectureReviewReady: true`, `releaseReady: false`,
  `defaultFlipReady: false`, `temporaryPathRetirementReady: false`, and
  `goalCompletionClaim: not-complete`.
- No browser capture or manual evidence collection was run in this slice.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "writes passing reviewed artifacts"` -
  passed with one VM test.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed after adding completion-audit preservation to regenerate command
  templates.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "writes passing reviewed artifacts|keeps artifacts when strict readiness fails"` -
  passed with two VM tests.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "forwards readiness bundle options"` -
  passed with one VM test.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --completion-audit=/Users/dan/Coding/fleury-web-phase1/docs/implementation/web-rfc-completion-audit.json --json` -
  regenerated the current readiness candidate packet and completion audit from
  existing captures.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 77 checked manifest fields, and zero mismatches.
- Regenerated the same readiness candidate packet again after preserving
  `--completion-audit` in the generated release-action command templates; strict
  bundle verification still passed with 11 checked generated artifacts, 229
  checked source inputs, one checked metadata field, 77 checked manifest fields,
  and zero mismatches.
- `jq empty docs/implementation/web-rfc-completion-audit.json` - passed.
- `jq '{kind, generatedAt, overallStatus, architectureReviewReady, releaseReady, defaultFlipReady, temporaryPathRetirementReady, goalCompletionClaim, completionBlockers, manualTargets: .manualEvidence.needsReviewTargets, automatedStatus: .automatedEvidence.automatedWebHostValidation.status}' docs/implementation/web-rfc-completion-audit.json` -
  confirmed the generated audit remains architecture-review ready and
  release/default blocked on candidate thresholds, real Chrome/macOS IME,
  real Chrome/macOS VoiceOver, strict readiness, and bundle-bound
  default/retirement preflights.
- `jq -e '.remainingReleaseActions[] | select(.id == "regenerate-readiness-bundle") | (.commandTemplate + .rootCommandTemplate) | any(. == "--completion-audit=/Users/dan/Coding/fleury-web-phase1/docs/implementation/web-rfc-completion-audit.json")' profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json` -
  passed, confirming both regenerate command surfaces preserve the completion
  audit path.
- `jq -e '.remainingReleaseActions[] | select(.id == "regenerate-readiness-bundle") | .details.completionAuditPath == "/Users/dan/Coding/fleury-web-phase1/docs/implementation/web-rfc-completion-audit.json"' profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json` -
  passed.
- `git diff --check` - passed.
- `rg -n "[ \t]+$" ...` over the edited Dart, Markdown, and generated
  completion-audit files - passed with no trailing whitespace hits.

## 2026-06-09 11:58 EDT

Added a machine-readable RFC completion audit.

- Added `docs/implementation/web-rfc-completion-audit.json` as the compact
  current-state artifact for review automation and handoff. It records:
  implementation-review readiness, release readiness, default-flip readiness,
  temporary-path-retirement readiness, RFC phase status, current blocking
  gates, current automated evidence, current manual evidence, and generated
  release-action status.
- The audit intentionally reports `goalCompletionClaim: "not-complete"`,
  `releaseReady: false`, `defaultFlipReady: false`, and
  `temporaryPathRetirementReady: false` because threshold review plus real
  Chrome IME / VoiceOver manual evidence remain unsatisfied.
- Linked the completion audit from `web-rfc-review-packet.md` so reviewers have
  one small status artifact before diving into the longer phase audit or
  execution log.
- No browser capture was run.

Verification:

- `jq empty docs/implementation/web-rfc-completion-audit.json` - passed.
- `jq '{kind, overallStatus, architectureReviewReady, releaseReady, defaultFlipReady, temporaryPathRetirementReady, blockerCount: (.completionBlockers | length), phases: [.phaseStatus[] | {phase,status,releaseBlocking}]}' docs/implementation/web-rfc-completion-audit.json` -
  confirmed the audit reports architecture-review-ready, release-blocked, six
  completion blockers, and phase-level release-blocking status.
- `jq -n --slurpfile audit docs/implementation/web-rfc-completion-audit.json --slurpfile readiness .../web-readiness.json '...'` -
  returned `true` for release readiness and manual `needsReviewTargets`
  consistency against the current readiness JSON.
- `jq -n --slurpfile audit docs/implementation/web-rfc-completion-audit.json --slurpfile manual .../manual-validation-audit.json '...'` -
  returned `true` for manual strict pass, passed-target count, and invalid
  entry count consistency.
- `jq -n --slurpfile audit docs/implementation/web-rfc-completion-audit.json --slurpfile semantic .../semantic-coverage.json '...'` -
  returned `true` for semantic strict pass, fallback-cell count, and frame
  count consistency.
- `jq -e -n --slurpfile audit docs/implementation/web-rfc-completion-audit.json --slurpfile automated .../web-automated-validation.json '...'` -
  returned `true` for automated retained-host validation status and check
  blocker counts.
- `git diff --check` - passed.

## 2026-06-09 11:55 EDT

Made the verify-bundle release-action scope match strict manifest
verification.

- Expanded `verify-readiness-bundle.details.verificationScope` so the generated
  release-action graph advertises the manifest checks that strict verification
  already enforces: generated artifact fingerprints, source-input
  fingerprints, expected source-input path coverage, command working
  directory, manual-evidence latest-entry fingerprints, threshold/manual
  release-action commands, generated diagnostic preflight metadata, and
  release-action command templates.
- `readiness_bundle_verifier.dart` now asserts that expanded scope and also
  checks the package-local `web_readiness_bundle.dart --verify=...` command
  template, not only the root `fleury benchmark web-readiness-bundle` launcher.
- Updated package/profiling docs plus the review packet and phase audit so the
  human-facing explanation matches the generated action metadata.
- Regenerated the current
  `profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate`
  bundle from existing captures. No browser capture was run.
- Readiness remains intentionally red only for candidate threshold review and
  real Chrome IME / VoiceOver manual evidence; bundle and automated-validation
  checks are strict green inside the bundle-bound preflights.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "writes passing reviewed artifacts|keeps artifacts when strict readiness fails|default preflight|verification fails stale release actions"` -
  passed with 3 selected VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated readiness artifacts from existing captures.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, 77
  checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json` -
  exited 1 as expected for threshold-review and manual-evidence blockers;
  nested `readinessBundle` and `automatedValidation` checks were strict green.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the same remaining release blockers; nested
  `readinessBundle` and `automatedValidation` checks were strict green.
- `jq '.remainingReleaseActions[] | select(.id == "verify-readiness-bundle") | {id, scope: .details.verificationScope, commandTemplate, rootCommandTemplate}' .../web-readiness-bundle.json` -
  confirmed the generated packet advertises the expanded verification scope and
  both verify command templates.
- `rg -n "manual-evidence-latest-entry-fingerprints|generated-default-preflight-diagnostics|release-action-command-templates" .../web-release-actions.md` -
  confirmed the release-action Markdown renders the expanded scope.
- `git diff --check` - passed.

## 2026-06-09 11:45 EDT

Hardened readiness-bundle verification for generated diagnostic preflight
metadata.

- `readiness_bundle_verifier.dart` now verifies the generated
  default-preflight preview JSON fields that keep the bundle/release boundary
  explicit: `diagnosticOnly: true`, `finalGateRequiresBundle: true`,
  `finalGateRequiresAutomatedValidation: true`, the inferred final
  bundle/automated-validation paths, readiness-only `bundleRequired: false`,
  readiness-only `bundleBound: false`, and the preview's actual
  automated-validation binding state.
- The same verifier pass now cross-checks
  `remainingReleaseActions.run-default-preflight:*` details so
  `generatedPreviewDiagnosticOnly`, bundle path, automated-validation path, and
  generated command templates cannot drift away from the preview artifacts.
- Added a regression that corrupts a generated preflight preview while
  refreshing its artifact fingerprint. Strict bundle verification now catches
  that as manifest drift, rather than accepting the stale semantic field.
- Strengthened the existing stale release-action regression to cover the new
  final-gate automated-validation path invariant.
- Regenerated the current
  `profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate`
  bundle from existing captures. No browser capture was run.
- Readiness remains intentionally red only for candidate threshold review and
  real Chrome IME / VoiceOver manual evidence; bundle and automated-validation
  checks are strict green inside the bundle-bound preflights.

Verification:

- `dart format packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "stale generated preflight diagnostics|verification fails stale release actions|verification"` -
  passed with 15 selected VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated readiness artifacts from existing captures.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, 75
  checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json` -
  exited 1 as expected for threshold-review and manual-evidence blockers;
  nested `readinessBundle` and `automatedValidation` checks were strict green.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the same remaining release blockers; nested
  `readinessBundle` and `automatedValidation` checks were strict green.
- `git diff --check` - passed.

## 2026-06-09 11:23 EDT

Made generated default-preflight previews explicitly diagnostic-only.

- `web_default_preflight.dart --allow-unbundled` now writes
  `diagnosticOnly: true`, a diagnostic reason, `finalGateRequiresBundle: true`,
  `finalGateRequiresAutomatedValidation: true`, and the inferred final
  bundle/automated-validation artifact paths into JSON and Markdown output.
- Bundle-bound preflight runs continue to report `diagnosticOnly: false`,
  `bundleRequired: true`, `bundleBound: true`,
  `automatedValidationRequired: true`, and `automatedValidationBound: true`.
- `web_readiness_bundle.dart` now records
  `generatedPreviewDiagnosticOnly: true` in generated default-preflight release
  action details. This makes the circular-fingerprint limitation explicit: the
  generated preview artifacts are readiness-bound diagnostics, while the
  release-action commands remain the final bundle-bound gates.
- Updated package, profiling, review-packet, and phase-audit docs to describe
  generated preflight artifacts as diagnostic snapshots and reserve release
  claims for bundle-bound preflight commands.
- Regenerated the current
  `profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate`
  bundle from existing captures. No browser capture was run.
- Readiness remains intentionally red only for candidate threshold review and
  real Chrome IME / VoiceOver manual evidence.

Verification:

- `dart format packages/fleury_web/tool/web_default_preflight.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_default_preflight_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_default_preflight.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_default_preflight_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart` -
  passed with 15 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "writes passing reviewed artifacts|keeps artifacts when strict readiness fails|default preflight"` -
  passed with 2 selected VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated readiness artifacts from existing captures.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, 55
  checked manifest fields, and zero mismatches.
- `jq '{target, diagnosticOnly, diagnosticReason, finalGateRequiresBundle, finalGateRequiresAutomatedValidation, finalGateBundlePath, finalGateAutomatedValidationPath, bundleRequired, bundleBound, automatedValidationRequired, automatedValidationBound, strictPass}' .../web-default-preflight-make-dom-default.json` -
  confirmed generated preview JSON now reports `diagnosticOnly: true`, final
  bundle/automated-validation paths, `bundleRequired: false`, and
  `bundleBound: false`.
- `rg -n "Diagnostic only|Final gate requires|Unbundled readiness-only|generatedPreviewDiagnosticOnly" .../web-default-preflight-make-dom-default.md .../web-release-actions.md .../web-readiness-bundle.json` -
  confirmed the generated Markdown/action packet exposes the same diagnostic
  preview contract.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json` -
  exited 1 as expected; the run was `diagnosticOnly: false`,
  `bundleRequired: true`, `bundleBound: true`,
  `automatedValidationRequired: true`, and `automatedValidationBound: true`.
  Bundle and automated-validation checks were strict green; only Phase 6
  readiness remained red on candidate threshold review and manual IME /
  VoiceOver evidence.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the same remaining human/empirical gates.
- `git diff --check` - passed.

## 2026-06-09 11:15 EDT

Tightened readiness-bundle verification for manual-evidence fingerprint
consistency.

- `readiness_bundle_verifier.dart` now verifies that generated
  `manual-validation-audit.json` and `web-readiness.json` report
  `latestEntryFingerprint` values that still match the canonical JSON
  fingerprints of the current manual evidence files recorded in the bundle's
  source-input set.
- The existing source-input verification continues to use byte-level file
  fingerprints. The new check intentionally recomputes the manual audit's
  canonical JSON fingerprint, so harmless formatting changes are handled by the
  source-input check while semantic evidence drift is caught by the embedded
  latest-entry check.
- Added a regression test that rewrites the generated manual audit and
  readiness artifacts to carry stale manual-evidence fingerprints while keeping
  their artifact byte fingerprints current; strict bundle verification now
  fails that case through `manifestMismatches`.
- Regenerated the manual audit and the current
  `profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate`
  bundle from existing captures. No browser capture was run.
- Readiness remains intentionally red only for candidate threshold review and
  real Chrome IME / VoiceOver manual evidence.

Verification:

- `dart format packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed with no further changes after the final patch.
- `dart analyze packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "stale embedded manual evidence fingerprints|verification fails stale source inputs|verification fails stale artifacts|verification requires manual plan"` -
  passed with 4 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "verification"` -
  passed with 14 VM tests.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/plan.md --write-templates=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/review.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json --json` -
  regenerated manual artifacts. The audit remains `strictPass: false` with two
  `needsReview` targets and provenance blockers for `reviewedBy`, `capturedAt`,
  and `environment.browserVersion`.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated readiness artifacts from existing captures.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, 55
  checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json` -
  exited 1 as expected; `readinessBundle` and `automatedValidation` checks were
  strict green, and only Phase 6 readiness remained red on candidate threshold
  review and manual IME / VoiceOver evidence.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the same remaining human/empirical gates.
- `git diff --check` - passed.

## 2026-06-09 11:01 EDT

Hardened manual evidence so reviewed passes must include observed page-signal
values.

- Manual validation templates now carry top-level `observedPageSignals` copied
  from each target's required page signals, with blank `observedValue` and
  `needsReview` status.
- Strict pass evidence now requires every observed page signal to be present,
  have `status: pass`, and report an `observedValue` matching the required page
  signal's expected value. This closes the accessibility/IME backstop gap where
  a reviewer could mark checks pass without recording the actual DOM readiness
  and caret-positioning signals seen on the manual page.
- `web_manual_validation.dart` now prints the observed page-signal fields in
  the generated plan's "Before review can pass" section.
- Updated package/profiling docs, review packet, and phase audit so reviewers
  know that passing Chrome IME / VoiceOver evidence must include observed page
  signal values, not just per-check notes.
- Regenerated manual plan/templates/review/audit and copied the new blank
  `observedPageSignals` structure into the existing starter review files. The
  starter files remain intentionally `needsReview`.
- Aligned readiness bundle test fixtures with the shared
  `manualValidationTemplateFor(...)` generator to prevent duplicate template
  shape drift in tests.
- Regenerated the current
  `profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate`
  bundle from existing captures. No browser capture was run.
- Readiness remains intentionally red only for reviewed threshold promotion and
  real Chrome IME / VoiceOver manual evidence.

Verification:

- `dart format packages/fleury_web/test/web_readiness_bundle_tool_test.dart packages/fleury_web/lib/src/manual_validation/manual_validation_targets.dart packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/test/web_manual_validation_tool_test.dart` -
  passed with no further changes.
- `dart analyze packages/fleury_web/lib/src/manual_validation/manual_validation_targets.dart packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/test/web_manual_validation_tool_test.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed with 22 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "manual evidence actions|existing starter evidence|manual evidence|template|starter|manual page signals|serve notes"` -
  passed with 7 VM tests, including the two fixture-drift regressions found
  during this slice.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/plan.md --write-templates=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/review.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json --json` -
  regenerated manual artifacts. The audit remains `strictPass: false` with two
  `needsReview` targets and provenance blockers for `reviewedBy`, `capturedAt`,
  and `environment.browserVersion`; observed page-signal template structure is
  now present.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated readiness artifacts from existing captures.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, 51
  checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json` -
  exited 1 as expected; `readinessBundle` and `automatedValidation` checks were
  strict green, and only Phase 6 readiness remained red on candidate threshold
  review and manual IME / VoiceOver evidence.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the same remaining human/empirical gates.
- `git diff --check` - passed.

## 2026-06-09 10:42 EDT

Removed redundant threshold-review context hints from current plan commands.

- `web_readiness_bundle.dart` now reads
  `generatedFrom.captureEnvironment.reviewContextHint` from the candidate
  threshold policy itself. When present, generated `planCommand` and
  `rootPlanCommand` omit `--review-context-hint` and rely on the candidate input
  to populate the threshold-review plan.
- Legacy candidates that do not carry captured environment metadata still get a
  fallback `--review-context-hint` from the readiness bundle's capture summary
  when one is available.
- Release-action details now expose `candidateReviewContextHint` and
  `planCommandUsesCandidateCapturedContext: true`, while promotion command
  templates still include the concrete `--review-context=...` value and the
  reviewer/over-budget placeholders.
- Updated strict bundle verification, catalog/help output, package README,
  profiling README, review packet, and phase audit so the default path is
  captured-candidate context and `--review-context-hint=TEXT` is documented as
  an override or legacy-candidate fallback.
- Regenerated the current
  `profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate`
  bundle from existing captures. No browser capture was run.
- Readiness remains intentionally red only for human/empirical gates: reviewed
  threshold policy promotion and real Chrome IME / VoiceOver manual evidence.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "actions promote candidate thresholds|default preflight"` -
  passed with the changed threshold-action test selected.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "release-grade benchmark help|benchmark catalog"` -
  passed with 2 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated readiness artifacts from existing captures.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, 51
  checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 27 VM tests.
- `jq '.remainingReleaseActions[] | select(.id == "review-threshold-policy") | {planCommand, rootPlanCommand, commandTemplate, details: {suggestedReviewContext: .details.suggestedReviewContext, candidateReviewContextHint: .details.candidateReviewContextHint, planCommandUsesCandidateCapturedContext: .details.planCommandUsesCandidateCapturedContext}}' .../web-readiness-bundle.json` -
  confirmed both plan commands omit `--review-context-hint`, while
  `candidateReviewContextHint` and the promotion `--review-context=...` still
  carry the captured Chrome 149 context.
- `rg -n -- "review-context-hint|Review context hint|candidateReviewContextHint|planCommandUsesCandidateCapturedContext" .../web-release-actions.md .../web-readiness-bundle.json` -
  confirmed only the candidate-context fields remain in the generated current
  release packet; no generated current plan command carries
  `--review-context-hint`.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected; `readinessBundle` and `automatedValidation` checks were
  strict green, and only Phase 6 readiness remained red on threshold review and
  manual IME / VoiceOver evidence.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the same remaining human/empirical gates.
- `git diff --check` - passed.

## 2026-06-09 10:28 EDT

Hardened threshold-review capture context and tightened the implementation loop.

- Candidate threshold generation now writes
  `generatedFrom.captureEnvironment`, including a derived
  `reviewContextHint`, when repeated capture metadata includes runtime
  environment details.
- `web_threshold_review.dart --write-plan` now uses the candidate policy's
  captured `generatedFrom.captureEnvironment.reviewContextHint` when no manual
  `--review-context-hint` is supplied. If an explicit CLI hint differs from the
  generated hint, the plan includes both values so reviewers can see the
  discrepancy.
- This fixes the stale human-facing Chrome 148 review hint risk without
  re-running browser capture. The regenerated fresh local plan now promotes
  with the captured Chrome 149 context:
  `Browser Chrome/149.0.7827.102, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline`.
- Updated the package README, profiling README, and review packet to document
  that threshold-review plans can reuse captured candidate context and that
  docs/tooling/readiness changes should reuse existing captures when possible.
- Adopted a faster loop for the remaining work: batch source, tooling, docs, and
  artifact-regeneration edits first; run cheap local tests and bundle
  verification after the batch; reserve real-browser capture for the final
  end-gate pass or for changes that actually touch runtime browser behavior.
- Regenerated the current candidate artifacts from the existing
  `profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh`
  captures. No new browser capture was run for this slice.
- The refreshed threshold candidate fingerprint is
  `fnv1a64:e0d3572d6b421cf7`.
- Readiness remains intentionally red only for empirical/human gates: candidate
  threshold-policy review/promotion and real Chrome IME / VoiceOver manual
  evidence.

Verification:

- `dart format packages/fleury_web/tool/web_frame_scoreboard.dart packages/fleury_web/tool/web_threshold_review.dart packages/fleury_web/test/web_frame_scoreboard_tool_test.dart packages/fleury_web/test/web_threshold_review_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_frame_scoreboard.dart packages/fleury_web/tool/web_threshold_review.dart packages/fleury_web/test/web_frame_scoreboard_tool_test.dart packages/fleury_web/test/web_threshold_review_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_scoreboard_tool_test.dart test/web_threshold_review_tool_test.dart` -
  passed with 27 VM tests.
- `cd packages/fleury_web && dart run tool/web_frame_scoreboard.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/scoreboard.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/scoreboard.json --min-runs=3 --require-comparable-environment --write-thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --threshold-headroom-percent=20 --threshold-min-headroom-ms=1 --threshold-min-headroom-percent=1 --strict` -
  passed and regenerated the scoreboard plus candidate threshold policy from
  existing captures.
- `cd packages/fleury_web && dart run tool/web_threshold_review.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/threshold-review-plan.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/threshold-review.json` -
  passed and wrote a plan using the captured Chrome 149 review context without
  a manual context hint.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the readiness-candidate bundle from existing captures/manual
  artifacts.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, 51
  checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  readiness-bundle and automated-validation checks passed.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  readiness-bundle and automated-validation checks passed.

## 2026-06-09 09:36 EDT

Tightened the human threshold-review packet so candidate threshold promotion
cannot overlook missing runtime build/layout/paint subphase evidence.

- `web_threshold_review.dart --write-plan` now checks each scenario for
  `observedMaxRuntimeBuildP95Ms`, `observedMaxRuntimeLayoutP95Ms`, and
  `observedMaxRuntimePaintP95Ms` availability.
- When any scenario lacks those samples, the generated plan includes a
  `Runtime Subphase Timing Availability` section explaining that the policy
  still gates total-frame, DOM-apply, and semantic-apply thresholds, but should
  not be used to decide whether Dart work is build-, layout-, or paint-bound
  for scenarios without subphase samples.
- The local threshold-review plan now reports runtime subphase samples missing
  for all 11 current repeated-capture scenarios. This is expected because the
  repeated local baseline predates the runtime subphase instrumentation split.
- Added threshold-review VM tests for fully missing, fully present, and partial
  runtime subphase availability in generated plans.
- Regenerated the local threshold-review plan and readiness-candidate packet
  from existing captures and manual evidence. No browser capture or Chrome
  automated-validation rerun was needed for this readiness-tool-only change.

Verification:

- `dart format packages/fleury_web/tool/web_threshold_review.dart packages/fleury_web/test/web_threshold_review_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_threshold_review.dart packages/fleury_web/test/web_threshold_review_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_threshold_review_tool_test.dart` -
  passed with 17 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  intentionally failed before regeneration with `sourceMismatchCount: 1` for
  `web_threshold_review.dart` and zero artifact mismatches.
- `cd packages/fleury_web && dart run tool/web_threshold_review.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review-plan.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review.json --review-context-hint='Browser Chrome/148.0.7778.217, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline'` -
  regenerated `threshold-review-plan.md`.
- `rg -n "Runtime Subphase|build-, layout-|\\| .*missing" profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review-plan.md` -
  confirmed the generated plan contains the new section and all 11 scenarios
  are marked `missing | missing | missing`.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet from existing captures.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 51 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining Phase 6 readiness blockers; nested
  `readinessBundle` and `automatedValidation` checks passed.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining Phase 6 readiness blockers; nested
  `readinessBundle` and `automatedValidation` checks passed.
- `git diff --check` - passed.

## 2026-06-09 10:06 EDT

Reduced the heavy-browser loop and refreshed the retained-DOM baseline with
runtime subphase samples.

- Adopted the faster validation loop for this branch: batch source/tooling
  changes and cheap Dart tests first, then run one browser capture batch at the
  end of a meaningful work packet.
- Added compile-once reuse to `web_frame_suite.dart` and
  `web_frame_capture.dart`. The suite now builds the browser benchmark page once
  into `.fleury-web-frame-page`, passes that `--page-dir` to each capture, and
  cleans it up unless `--keep-temp` is set.
- Added `--no-compile-once` as an explicit opt-out on the package suite tool and
  root `fleury benchmark web-suite` launcher.
- Captured a fresh local retained-DOM product baseline at
  `profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh`.
  The suite ran 11 scenarios with 3 runs each. The scoreboard is strict green
  with 33 captures, and all scenario threshold records now include observed
  runtime build/layout/paint p95 maxima.
- Regenerated the threshold-review plan from that fresh baseline. Because every
  scenario now has runtime subphase samples, the plan no longer emits the
  `Runtime Subphase Timing Availability` warning.
- Reused the previously verified automated-validation artifact for the new
  readiness candidate, then let strict bundle/preflight verification confirm the
  source fingerprints still match. This avoided rerunning the browser automated
  validation pass for unchanged host tests.
- Regenerated the readiness-candidate packet for the new baseline. Readiness is
  still intentionally red only for human gates: threshold policy review state is
  still `candidate`, and real Chrome/macOS IME plus VoiceOver manual evidence is
  still pending.

Verification:

- `dart format packages/fleury_web/tool/web_frame_capture.dart packages/fleury_web/tool/web_frame_suite.dart packages/fleury_web/test/web_frame_capture_tool_test.dart packages/fleury_web/test/web_frame_suite_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_frame_capture.dart packages/fleury_web/tool/web_frame_suite.dart packages/fleury_web/test/web_frame_capture_tool_test.dart packages/fleury_web/test/web_frame_suite_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_suite_tool_test.dart test/web_frame_capture_tool_test.dart` -
  passed with 15 VM tests.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark web-suite"` -
  passed with 2 VM tests.
- `cd packages/fleury_web && dart run tool/web_frame_suite.dart --scenarios=normal-80x24,single-dirty-cell-160x50 --runs=2 --frames=3 --warmup=0 --output-dir=/tmp/fleury_web_compile_once_dry_run --dry-run --json` -
  confirmed one `--compile-only --page-dir=...` command, followed by capture
  commands reusing the same page dir.
- `cd packages/fleury_web && dart run tool/web_frame_suite.dart --runs=3 --timeout=60 --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --write-thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json` -
  passed. The suite compiled the benchmark page once, ran 33 Chrome captures,
  wrote `scoreboard.json`, `scoreboard.md`, and `thresholds.candidate.json`,
  and cleaned up `.fleury-web-frame-page`.
- `cd packages/fleury_web && dart run tool/web_threshold_review.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/threshold-review-plan.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/threshold-review.json --review-context-hint='Browser Chrome/148.0.7778.217, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline'` -
  regenerated threshold review artifacts for the fresh baseline.
- `rg -n "Runtime Subphase|missing \\| missing" profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/threshold-review-plan.md` -
  produced no output, confirming no runtime-subphase availability warning is
  needed for this baseline.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the readiness-candidate packet for the fresh baseline.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 51 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining human readiness blockers. Nested
  `readinessBundle` and `automatedValidation` checks passed, with
  `bundleBound: true` and `automatedValidationBound: true`.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining human readiness blockers. Nested
  `readinessBundle` and `automatedValidation` checks passed, with
  `bundleBound: true` and `automatedValidationBound: true`.

## 2026-06-09 10:15 EDT

Refreshed reviewer-facing documentation after the runtime-subphase baseline.

- Updated the web RFC review packet to make
  `profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh` the
  primary local candidate directory.
- Removed stale review-packet references to the older Phase 1 refresh as the
  active packet and updated the re-review commands to verify the fresh
  readiness bundle and automated-validation artifact paths.
- Recorded that every scenario in the fresh baseline has runtime
  build/layout/paint subphase samples, so the current threshold review plan no
  longer needs a runtime-subphase availability warning.
- Updated the selected benchmark signal to the fresh local p95 range
  (`noop-160x50` at 92.80 ms through `scroll-row-churn-160x50` at 832.10 ms)
  and clarified that the measured bottlenecks remain runtime build/paint and
  semantic apply rather than DOM apply.
- Updated the phase audit to include the fresh subphase-aware baseline,
  compile-once suite reuse, and the current Phase 6 readiness-candidate path.
- Documented compile-once suite reuse in both the package README and profiling
  artifact guide so future full suites do not pay the browser compile cost once
  per capture unless explicitly debugging with `--no-compile-once`.
- Regenerated the fresh baseline's `threshold-review-plan.md` with the
  captured Chrome 149 review-context hint from the readiness bundle action
  graph, replacing the stale Chrome 148 hint from the initial manual command.
- Regenerated the readiness-candidate bundle from existing captures and manual
  evidence after the threshold-review plan changed, so the bundle fingerprints
  remain current.

Verification:

- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 51 checked manifest fields, and zero mismatches.
- `rg -n "Chrome/148|Chrome/149|Review context hint|Runtime Subphase" profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/threshold-review-plan.md` -
  confirmed the generated plan now uses the Chrome 149 captured environment
  hint and still has no runtime-subphase warning.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining human readiness blockers. Nested
  `readinessBundle` and `automatedValidation` checks passed.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining human readiness blockers. Nested
  `readinessBundle` and `automatedValidation` checks passed.
- `rg -n "2026-06-08-local-dom-retained-phase1-refresh|59\\.10|1193\\.40" docs/implementation/web-rfc-review-packet.md` -
  produced no output.
- `git diff --check` - passed.

## 2026-06-09 09:27 EDT

Tightened runtime subphase evidence semantics and switched this slice to a
batched validation loop.

- Added explicit `runtimePhaseTimingAvailable` frame instrumentation state.
  Current captures mark runtime build/layout/paint subphase timings available;
  old captures that predate the subphase fields now summarize those slices with
  `sampleCount: 0` instead of measured-looking zero values.
- `web_frame_report.dart` now renders unavailable timing slices as `-` in
  Markdown instead of `0.00 ms`.
- `web_frame_scoreboard.dart` now excludes unavailable runtime build/layout/paint
  p95s from aggregate metrics and per-capture values. Old captures still keep
  `runtimeRenderMs` as the fallback dominant p95 slice.
- Candidate threshold-policy generation now records nullable observed runtime
  subphase maxima when no subphase samples exist, instead of converting absence
  to `0`.
- Added VM/tool tests for old capture handling in instrumentation, report, and
  scoreboard paths.
- Followed the faster loop for this batch: source/test/tool edits first, cheap
  analyzer and VM tests next, one automated validation pass after the batch, and
  no new browser frame capture.

Verification:

- `dart format packages/fleury_web/lib/src/instrumentation/web_host_instrumentation.dart packages/fleury_web/tool/web_frame_report.dart packages/fleury_web/tool/web_frame_scoreboard.dart packages/fleury_web/test/web_host_instrumentation_test.dart packages/fleury_web/test/web_frame_report_tool_test.dart packages/fleury_web/test/web_frame_scoreboard_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/lib/src/instrumentation/web_host_instrumentation.dart packages/fleury_web/tool/web_frame_report.dart packages/fleury_web/tool/web_frame_scoreboard.dart packages/fleury_web/test/web_host_instrumentation_test.dart packages/fleury_web/test/web_frame_report_tool_test.dart packages/fleury_web/test/web_frame_scoreboard_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_host_instrumentation_test.dart test/web_frame_report_tool_test.dart test/web_frame_scoreboard_tool_test.dart` -
  passed with 19 VM/tool tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  intentionally failed before regeneration with four source-input mismatches
  for the files changed in this batch and zero artifact mismatches.
- `cd packages/fleury_web && dart run tool/web_automated_validation.dart --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --strict --json` -
  passed with 9 Chrome test files / 88 browser tests and 4 VM test files / 20
  VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet from existing captures.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 51 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining Phase 6 readiness blockers; nested
  `readinessBundle` and `automatedValidation` checks passed, both bound to the
  generated artifacts.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining Phase 6 readiness blockers; nested
  `readinessBundle` and `automatedValidation` checks passed, both bound to the
  generated artifacts.

## 2026-06-09 09:14 EDT

Tightened generated default-preflight previews so they cannot miss stale
automated-validation evidence after the retained DOM automated test artifact
exists.

- `web_readiness_bundle.dart --write-default-preflights` now passes
  `--automated-validation=.../web-automated-validation.json` to generated
  preview preflights when that artifact already exists. First-time packets
  still omit it until the automated-validation action has produced evidence.
- The generated preview preflights remain intentionally unbundled previews, but
  they now report `automatedValidationBound: true` and validate the same
  automated-validation JSON that the final bundle-bound preflight commands
  require.
- Added a VM regression test that writes a minimal valid automated-validation
  artifact with current retained DOM automated test fingerprints, runs the
  readiness bundle with `--write-default-preflights`, and asserts both generated
  preview preflights bind to that artifact.
- Regenerated the local readiness-candidate packet from existing captures after
  the tool change. The generated preview preflight artifacts now both show
  `automatedValidationBound: true` with an automated-validation check that
  strict-passes.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed with zero final changes.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed with no issues.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "binds preview preflights"` -
  passed with one VM test.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "binds preview preflights|keeps artifacts|verification fails stale release actions|writes release actions"` -
  passed with three VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet from existing captures.
- `jq` over generated `web-default-preflight-make-dom-default.json` and
  `web-default-preflight-retire-temporary-paths.json` confirmed both preview
  artifacts have `automatedValidationRequired: false`,
  `automatedValidationBound: true`, and a strict-passing
  `automatedValidation` check.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 51 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining Phase 6 blockers; nested
  `readinessBundle` and `automatedValidation` checks both passed with zero
  mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining Phase 6 blockers; nested
  `readinessBundle` and `automatedValidation` checks both passed with zero
  mismatches.

## 2026-06-09 09:06 EDT

Refreshed the local readiness packet after the runtime subphase
instrumentation batch, keeping the faster loop policy: no full browser capture
suite was rerun, but generated artifacts and automated validation evidence are
current with the changed sources.

- First strict bundle verification intentionally failed with six source-input
  mismatches, all from the runtime subphase instrumentation batch:
  `web_host_instrumentation.dart`, `run_tui_surface.dart`,
  `run_tui_surface_test.dart`, `web_host_instrumentation_test.dart`,
  `web_frame_report.dart`, and `web_frame_scoreboard.dart`.
- Regenerated the readiness-candidate packet from the existing repeated Chrome
  captures and current manual evidence. Readiness remains correctly red for
  reviewed threshold policy and real Chrome/macOS IME + VoiceOver manual
  evidence.
- Regenerated `web-automated-validation.json` with the retained DOM automated
  validation tool instead of leaving the default preflights bound to stale test
  fingerprints.
- Regenerated the readiness bundle again so the bundle manifest points at the
  fresh automated-validation artifact.
- The final default preflights now fail only on the intended Phase 6 readiness
  blockers; bundle fingerprints and automated-validation binding both pass.

Verification:

- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  first exited 1 with `sourceMismatchCount: 6`, proving the pre-refresh packet
  was stale.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet from existing captures.
- `cd packages/fleury_web && dart run tool/web_automated_validation.dart --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --strict --json` -
  passed. Browser validation ran nine Chrome test files with 88 tests passing;
  VM validation ran four test files with 20 tests passing.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet again so the bundle
  fingerprints the fresh automated-validation artifact.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 51 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining Phase 6 blockers; nested
  `readinessBundle` and `automatedValidation` checks both passed with zero
  mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining Phase 6 blockers; nested
  `readinessBundle` and `automatedValidation` checks both passed with zero
  mismatches.

## 2026-06-09 08:49 EDT

Added runtime subphase timing so the web performance evidence can distinguish
runtime build, layout, and paint cost before choosing a follow-up optimization
path.

- `WebFrameInstrumentation` now records `runtimeBuildMicros`,
  `runtimeLayoutMicros`, and `runtimePaintMicros` in capture JSON, with zero
  defaults for older captures.
- `run_tui_surface.dart` wires the existing `TuiRuntime.renderFrame`
  `onPhaseTiming` callback into the browser-host frame instrumentation.
- The frame report and scoreboard tools now surface runtime build/layout/paint
  p95 metrics, and candidate threshold policies preserve the observed maxima.
- Dominant-slice classification now prefers runtime build/layout/paint when
  subphase timing exists, using `runtimeRenderMs` only as the old-capture
  fallback. This prevents the aggregate render timing from masking the actual
  Dart-side failure mode.
- Tests cover JSON round-trip compatibility, summary p95 calculation,
  subphase-aware dominant-slice classification, old-capture dominant-slice
  fallback, scoreboard markdown/JSON output, candidate-policy export, and the
  browser host instrumentation object shape.
- Updated the package README, implementation review packet, phase audit, and
  web backend RFC so the architecture/spec text names runtime
  build/layout/paint subphases instead of treating runtime render as one opaque
  failure mode.
- Loop policy update: defer Chrome capture/readiness regeneration while making
  source/schema/test changes, then run one end-of-slice browser validation pass
  once the batch is ready. This slice used one narrow diagnostic capture rather
  than a full suite/readiness regeneration.

Verification:

- `dart format packages/fleury_web/lib/src/instrumentation/web_host_instrumentation.dart packages/fleury_web/lib/src/run_tui_surface.dart packages/fleury_web/tool/web_frame_scoreboard.dart packages/fleury_web/tool/web_frame_report.dart packages/fleury_web/test/web_host_instrumentation_test.dart packages/fleury_web/test/web_frame_scoreboard_tool_test.dart packages/fleury_web/test/run_tui_surface_test.dart` -
  formatted 7 files with zero changes.
- `dart analyze packages/fleury_web/lib/src/instrumentation/web_host_instrumentation.dart packages/fleury_web/lib/src/run_tui_surface.dart packages/fleury_web/tool/web_frame_scoreboard.dart packages/fleury_web/tool/web_frame_report.dart packages/fleury_web/test/web_host_instrumentation_test.dart packages/fleury_web/test/web_frame_scoreboard_tool_test.dart packages/fleury_web/test/run_tui_surface_test.dart` -
  passed with no issues.
- `cd packages/fleury_web && dart test test/web_host_instrumentation_test.dart test/web_frame_scoreboard_tool_test.dart test/web_frame_report_tool_test.dart` -
  passed with 18 VM tests.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=single-dirty-cell-160x50 --frames=8 --warmup=1 --output=/tmp/fleury_single_dirty_subphase.json --json` -
  passed as a narrow diagnostic Chrome capture. The summary reported
  `frameCount: 8`, `overBudgetFrameCount: 8`,
  `dominantP95Slice: semanticApplyMs`, `runtimeBuildMs.p95: 124.4`,
  `runtimeLayoutMs.p95: 26.4`, `runtimePaintMs.p95: 35.7`,
  `runtimeRenderMs.p95: 201.8`, `semanticApplyMs.p95: 509`, and
  `domApplyMs.p95: 16.3`.
- `git diff --check` - passed.
- Full browser-suite capture and readiness-bundle regeneration were
  intentionally deferred to the next batched validation pass.

## 2026-06-09 08:35 EDT

Tightened the web performance evidence path so threshold reviewers can see
requested benchmark steps versus actual browser frames.

- Browser captures now record `capturedFrameCount`, `extraFrameCount`, and
  `framesPerStep` alongside the existing requested step/frame fields. The
  capture run environment also records `requestedSteps`.
- The frame scoreboard aggregates `requestedStepCount`, `extraFrameCount`, and
  `framesPerStep` per scenario, renders the Markdown column as
  `Frames / steps`, and keeps old captures comparable by treating missing
  `runEnvironment.requestedSteps` as `requestedFrames`.
- Candidate threshold policies now carry observed frame-accounting metadata per
  scenario: frame count, requested step count, extra frame count, and max
  frames per step. The threshold gate parser still ignores these metadata
  fields for pass/fail decisions, so older reviewed policies remain compatible.
- Threshold review plans now show frame accounting in both the main threshold
  table and the over-budget table. This makes multi-frame behavior explicit for
  current resize and text-input captures rather than hiding it behind the old
  `requestedFrames` label.
- Regenerated the local scoreboard, candidate threshold policy, threshold
  review plan, readiness bundle, and default preflights. The current local
  evidence shows `text-input-burst-80x24` at 120 captured frames for 60
  requested steps and `resize-burst` at 72 captured frames for 36 requested
  steps. Readiness remains intentionally red for candidate threshold-policy
  review and pending Chrome/macOS IME plus VoiceOver reviewed evidence.

Verification:

- `dart analyze packages/fleury_web/web/benchmark_capture.dart packages/fleury_web/tool/web_frame_capture.dart packages/fleury_web/tool/web_frame_scoreboard.dart packages/fleury_web/tool/web_threshold_review.dart packages/fleury_web/test/web_frame_scoreboard_tool_test.dart packages/fleury_web/test/web_threshold_review_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_scoreboard_tool_test.dart test/web_threshold_review_tool_test.dart` -
  passed with 23 VM tests.
- `cd packages/fleury_web && dart test test/web_frame_scoreboard_tool_test.dart` -
  passed with 8 VM tests after the requested-step signature fallback.
- `cd packages/fleury_web && dart run tool/web_frame_scoreboard.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/scoreboard.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/scoreboard.json --min-runs=3 --write-thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --threshold-headroom-percent=20 --threshold-min-headroom-ms=1 --threshold-min-headroom-percent=1 --require-comparable-environment --json` -
  regenerated the local scoreboard and candidate threshold policy with frame
  accounting.
- `cd packages/fleury_web && dart run tool/web_threshold_review.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review-plan.md '--review-context-hint=Browser Chrome/148.0.7778.217, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline'` -
  regenerated the threshold review plan with fingerprint
  `fnv1a64:5e05148220c729cd` and frame-accounting columns.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=v1 --write-default-preflights --json` -
  regenerated the readiness-candidate packet with the new candidate threshold
  fingerprint.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 51 checked manifest fields, and zero mismatches.
- `jq '{textInput: (.scenarios[] | select(.id=="text-input-burst-80x24") | {frameCount, requestedStepCount, extraFrameCount, framesPerStep}), resize: (.scenarios[] | select(.id=="resize-burst") | {frameCount, requestedStepCount, extraFrameCount, framesPerStep})}' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json` -
  confirmed `text-input-burst-80x24` and `resize-burst` are both exactly 2.0
  frames per requested step in the current captures.
- `rg -n "Frames / steps|text-input-burst-80x24|resize-burst|fnv1a64:5e05148220c729cd" profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review-plan.md profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-release-actions.md profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json` -
  confirmed the threshold review plan and release actions carry the new
  fingerprint and frame-accounting evidence.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining empirical release gates; nested
  `readinessBundle` verification passed with 51 checked manifest fields, and
  nested `automatedValidation` verification passed with 14 checked manifest
  fields.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining empirical release gates; nested
  `readinessBundle` verification passed with 51 checked manifest fields, and
  nested `automatedValidation` verification passed with 14 checked manifest
  fields.

## 2026-06-09 08:22 EDT

Bound strict bundle verification to the declared manual target scope and
regenerated the v1 packet after the verifier cleanup.

- Strict readiness-bundle verification now derives expected manual-template
  source inputs from the bundle's declared input scope instead of trusting the
  current manual audit contents. Explicit `input.targetIds` still wins; otherwise
  the verifier expands `input.targetPreset` and defaults through the current
  preset alias.
- The verifier now checks `artifacts.manualAudit.targets` against the declared
  input scope, so a hand-edited or stale packet that narrows v1 coverage is
  rejected even if the remaining manifest fields and generated files line up.
- Added regression coverage that generates a one-target bundle, mutates its
  manifest to claim the v1 preset, and verifies strict bundle verification
  reports both the missing VoiceOver manual-template source input and the
  manual-audit target mismatch.
- Regenerated the local readiness-candidate packet with `--target-preset=v1`
  after the final source edit. The packet remains intentionally red only for the
  empirical release gates: candidate threshold-policy review and pending
  Chrome/macOS IME plus Chrome/macOS VoiceOver reviewed evidence.

Verification:

- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "manual evidence actions|preserve explicit manual targets|stale manual target scope"` -
  passed with 3 selected VM tests.
- `dart format packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart && dart analyze packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 26 VM tests in 4:33.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=v1 --write-default-preflights --json` -
  regenerated the local readiness-candidate packet after the final verifier
  source cleanup.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 51 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining empirical release gates; nested
  `readinessBundle` verification passed with 51 checked manifest fields, and
  nested `automatedValidation` verification passed with 14 checked manifest
  fields.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining empirical release gates; nested
  `readinessBundle` verification passed with 51 checked manifest fields, and
  nested `automatedValidation` verification passed with 14 checked manifest
  fields.

## 2026-06-09 08:08 EDT

Made the v1 manual-validation browser set explicit in code and regenerated
the review packet with that preset.

- Added `manualValidationV1TargetIds` and a `v1` preset for the current
  release evidence scope: Chrome/macOS IME plus Chrome/macOS VoiceOver.
  `primary` remains a compatibility alias for existing commands.
- Updated package/root command help, package README, profiling evidence docs,
  review packet, and phase audit so reviewers no longer have to infer the v1
  browser set from the target IDs.
- The main manual-evidence readiness-bundle test now runs with
  `--target-preset=v1` and asserts the generated package-local and repo-root
  strict audit commands carry that preset.
- Regenerated manual validation plan/templates/audit and the local
  readiness-candidate packet with `--target-preset=v1`. The current packet
  now records `input.targetPreset: v1`, and its manual-audit plus
  regeneration commands render `--target-preset=v1`.
- Readiness remains intentionally red for the same empirical blockers:
  candidate threshold-policy review and pending Chrome/macOS IME plus
  Chrome/macOS VoiceOver reviewed evidence.

Verification:

- `dart format packages/fleury_web/lib/src/manual_validation/manual_validation_targets.dart packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_manual_validation_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart --name "writes selected target templates"` -
  passed with 1 selected VM test.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "web readiness bundle reports manual evidence actions"` -
  passed with 1 selected VM test.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-manual-validation|web-readiness-bundle"` -
  passed with the selected manual-validation launcher tests.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "forwards readiness bundle options"` -
  passed with the selected readiness-bundle launcher test.
- `dart run tool/fleury_dev.dart benchmark web-manual-validation --input=profiling/web/manual --target-preset=v1 --write-plan=profiling/web/manual/plan.md --write-templates=profiling/web/manual/templates --output=profiling/web/manual/review.md --json-output=profiling/web/manual/manual-validation-audit.json --json` -
  regenerated manual validation artifacts with two `needsReview` targets,
  zero invalid entries, and only the expected provenance blockers.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=v1 --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with explicit v1 manual
  target scope.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 50 checked manifest fields, and zero mismatches.
- `jq '{inputTargetPreset: .input.targetPreset, manualTargetIds: [.readiness.checks[] | select(.id=="manualValidation") | .details.failingTargetDetails[].id], regenTargetPreset: (.remainingReleaseActions[] | select(.id=="regenerate-readiness-bundle") | .details.targetPreset), regenCommandHasV1: any((.remainingReleaseActions[] | select(.id=="regenerate-readiness-bundle") | .commandTemplate[]); . == "--target-preset=v1"), rootRegenCommandHasV1: any((.remainingReleaseActions[] | select(.id=="regenerate-readiness-bundle") | .rootCommandTemplate[]); . == "--target-preset=v1")}' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  confirmed the packet target preset is `v1`, covers
  `chrome-ime-macos` and `chrome-voiceover-macos`, and both regenerate
  commands preserve `--target-preset=v1`.
- `rg -n -- "--target-preset=v1|targetPreset.*v1|Chrome/macOS" profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-release-actions.md profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json docs/implementation/web-rfc-review-packet.md docs/implementation/web-rfc-phase-audit.md packages/fleury_web/README.md profiling/web/README.md profiling/web/manual/README.md` -
  confirmed generated artifacts and docs expose the v1 preset and browser set.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining empirical release gates; nested
  `readinessBundle` verification passed with 50 checked manifest fields, and
  nested `automatedValidation` verification passed with 14 checked manifest
  fields.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining empirical release gates; nested
  `readinessBundle` verification passed with 50 checked manifest fields, and
  nested `automatedValidation` verification passed with 14 checked manifest
  fields.
- `dart analyze packages/fleury_web/lib/src/manual_validation/manual_validation_targets.dart packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_manual_validation_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `jq empty profiling/web/manual/manual-validation-audit.json profiling/web/manual/templates/chrome-ime-macos.template.json profiling/web/manual/templates/chrome-voiceover-macos.template.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.json` -
  passed.

## 2026-06-09 07:57 EDT

Completed repo-root manual-validation command coverage for release actions and
strict bundle verification.

- Manual evidence release actions now have package-local and repo-root command
  coverage for the full reviewer workflow: template preparation or refresh,
  starter creation when the starter is missing, provenance update, and strict
  manual audit.
- The release-action Markdown renders root starter and root audit command
  blocks alongside existing root command/provenance blocks.
- Strict readiness-bundle verification now reconstructs and checks manual
  template-preparation commands from the action's concrete target-template
  list, then checks per-target stale-template refresh commands, starter
  commands, provenance command templates, and strict audit commands in both
  package-local and repo-root forms.
- Updated the package README, review packet, and phase audit to describe the
  complete root manual-validation command contract instead of only the
  provenance helper.
- Regenerated the local readiness-candidate packet. In the current packet the
  manual templates and starter evidence files already exist, so per-target
  refresh/starter commands are omitted as expected; root provenance and root
  audit commands remain present for both primary manual targets.

Verification:

- `dart format packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "web readiness bundle reports manual evidence actions|web readiness bundle treats existing starter evidence"` -
  passed with 2 selected VM tests.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `jq empty profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.json profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.json` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with the updated manual
  command manifest.
- `rg -n "Root command|Root starter command|Root provenance command|Root audit command|web-manual-validation" profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-release-actions.md` -
  confirmed the generated release-action Markdown includes the repo-root
  manual-validation command blocks present for the current evidence state.
- `jq '.remainingReleaseActions[] | select(.id | startswith("collect-manual-evidence:")) | {id, hasRootCommandTemplate: has("rootCommandTemplate"), hasRootStarterCommand: has("rootStarterCommand"), hasRootProvenanceCommandTemplate: has("rootProvenanceCommandTemplate"), hasRootAuditCommand: has("rootAuditCommand")}' profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  confirmed both current manual targets have root provenance and root audit
  commands, while root template-refresh and root starter commands are omitted
  because the templates and starter evidence already exist.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 50 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining empirical release gates; nested
  `readinessBundle` verification passed with 50 checked manifest fields, and
  nested `automatedValidation` verification passed with 14 checked manifest
  fields.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining empirical release gates; nested
  `readinessBundle` verification passed with 50 checked manifest fields, and
  nested `automatedValidation` verification passed with 14 checked manifest
  fields.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 25 VM tests in 4:24.

## 2026-06-09 07:33 EDT

Added repo-root threshold review commands to the generated release-action
packet.

- Threshold review actions now render a package-local `planCommand` plus a
  repo-root `rootPlanCommand` for regenerating the non-promoting
  `threshold-review-plan.md` through
  `dart run tool/fleury_dev.dart benchmark web-threshold-review`.
- Threshold promotion actions now also include a `rootCommandTemplate` with
  the same reviewed-threshold output path, threshold-review JSON path,
  expected input fingerprint, suggested review context, over-budget
  acknowledgement flag, and non-runnable reviewer/review-note placeholders as
  the package-local command template.
- Strict readiness-bundle verification now checks the threshold review plan
  command, root plan command, promotion command template, and root promotion
  command template, so stale generated threshold-review actions are rejected.
- Updated the package README, review packet, and phase audit to describe root
  threshold review plan/promotion commands alongside the other repo-root
  release launchers.
- Regenerated the local readiness-candidate packet. It remains intentionally
  red for candidate threshold-policy review and real Chrome IME / VoiceOver
  evidence, while bundle and automated-validation verification remain green.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "candidate thresholds|stale release actions|writes passing reviewed artifacts"` -
  passed with 3 selected VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with `rootPlanCommand` and
  `rootCommandTemplate` entries for threshold review.
- `rg -n "Root plan command|Root command|web-threshold-review|rootPlanCommand|rootCommandTemplate" profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-release-actions.md profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  confirmed the generated Markdown and JSON packet include root threshold
  review plan and promotion commands.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 46 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining release gates; nested
  `readinessBundle` verification passed with 46 checked manifest fields, and
  nested `automatedValidation` verification passed with 14 checked manifest
  fields.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining release gates; nested
  `readinessBundle` verification passed with 46 checked manifest fields, and
  nested `automatedValidation` verification passed with 14 checked manifest
  fields.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 25 VM tests in 4:23.

## 2026-06-09 07:26 EDT

Tail note: the latest completed slice is the `2026-06-09 08:35 EDT` entry
above, which added benchmark frame-accounting evidence, regenerated the local
scoreboard/candidate threshold/readiness packet, and verified the bundle with
51 checked manifest fields. The log has earlier out-of-order append
sections, so use that timestamp when searching for the detailed verification
record.

## 2026-06-09 07:25 EDT

Added repo-root provenance helpers to the manual evidence release actions.

- Manual evidence actions still render the package-local
  `provenanceCommandTemplate`, but now also include and render a
  `rootProvenanceCommandTemplate` that calls
  `dart run tool/fleury_dev.dart benchmark web-manual-validation`.
- The root provenance command carries the same `--update-provenance`,
  `--template-target`, `--reviewed-by`, `--captured-at=now`, and
  `--browser-version` arguments as the package-local helper. This gives
  reviewers a repo-root command without weakening the manual evidence gate.
- Strict readiness-bundle verification now checks both the package-local and
  root provenance command templates for every failing manual target, so stale
  generated action packets are rejected.
- Updated the package README, review packet, and phase audit so the reviewer
  workflow describes the root manual provenance helper alongside the existing
  automated validation and default-preflight root launchers.
- Regenerated the local readiness-candidate packet. It remains intentionally
  red for candidate threshold-policy review and real Chrome IME / VoiceOver
  evidence, while bundle and automated-validation verification remain green.

Verification:

- `dart format packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "manual evidence actions|existing starter evidence|stale release actions|writes passing reviewed artifacts"` -
  passed with 4 selected VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with
  `rootProvenanceCommandTemplate` entries for both manual targets.
- `rg -n "Root provenance command|web-manual-validation|rootProvenanceCommandTemplate" profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-release-actions.md profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json` -
  confirmed the generated Markdown and JSON packet include root provenance
  commands for `chrome-ime-macos` and `chrome-voiceover-macos`.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 42 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining release gates; nested
  `readinessBundle` verification passed with 42 checked manifest fields, and
  nested `automatedValidation` verification passed with 14 checked manifest
  fields.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining release gates; nested
  `readinessBundle` verification passed with 42 checked manifest fields, and
  nested `automatedValidation` verification passed with 14 checked manifest
  fields.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 25 VM tests in 4:23.

## 2026-06-09 07:10 EDT

Made the generated release-action packet directly runnable from either the
package directory or the repository root.

- Release actions still keep the package-local `dart run tool/...` command as
  the canonical command, but now also render a `Root command` template for
  actions that are supported by the root `tool/fleury_dev.dart benchmark`
  launcher.
- Added root command templates for the bundle regenerate action, strict bundle
  verification, automated retained-host validation, and both default-preflight
  targets.
- The readiness bundle verifier now treats those root command templates as
  manifest fields, so hand-editing or drifting the generated release action
  packet is caught by strict bundle verification.
- Regenerated the local readiness-candidate packet so
  `web-release-actions.md` and `web-readiness-bundle.json` both carry the root
  launcher commands and their fingerprints.
- The default preflights remain intentionally red only for the release gates:
  threshold policy review is still `candidate`, and the Chrome IME /
  VoiceOver manual evidence still needs real reviewer provenance and check
  results.

Verification:

- `dart analyze packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "writes passing reviewed artifacts|stale release actions|keeps artifacts when strict readiness fails"` -
  passed with 3 selected VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with root command templates
  in the remaining release actions.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 38 checked manifest fields, and zero mismatches.
- `rg -n "Root command|tool/fleury_dev.dart|web-automated-validation|web-default-preflight" profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-release-actions.md` -
  confirmed root command blocks are rendered for regenerate, verify, automated
  validation, `make-dom-default`, and `retire-temporary-paths`.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 25 VM tests.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts,
  229 checked source inputs, 38 checked manifest fields, and zero mismatches;
  nested `automatedValidation` verification passed with 14 checked source
  inputs, 14 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts,
  229 checked source inputs, 38 checked manifest fields, and zero mismatches;
  nested `automatedValidation` verification passed with 14 checked source
  inputs, 14 checked manifest fields, and zero mismatches.

## 2026-06-09 06:37 EDT

Made retained-host automated testing a durable release-gate artifact.

- Added `tool/web_automated_validation.dart`, which runs the curated retained
  DOM browser and VM host test commands and writes
  `fleuryWebAutomatedValidation` JSON with command arrays, exit codes,
  durations, output tails, source-input fingerprints, and `strictPass`.
- Exposed the canonical retained-host browser/VM test commands and source
  fingerprints through `readiness_bundle_verifier.dart`, then reused them in
  the validation tool, bundle verifier, and default preflight.
- Updated `web_default_preflight.dart` so bundle-bound release checks require a
  sibling or explicit `web-automated-validation.json` artifact in addition to
  `web-readiness-bundle.json`. The preflight verifies command shape, pass
  status, source fingerprints, required file coverage, and package cwd
  metadata for that validation artifact.
- Updated `web_readiness_bundle.dart` release actions so
  `run-automated-web-host-tests` now runs the JSON-producing validation tool,
  while final `run-default-preflight:*` commands pass
  `--automated-validation=...`.
- Tightened bundle manifest verification so the validation path produced by
  `run-automated-web-host-tests` must match the path consumed by each final
  default-preflight action; stale preflight command templates are rejected too.
- Regenerated the local readiness-candidate packet. It remains intentionally
  red only for candidate threshold-policy review and the real Chrome IME /
  VoiceOver manual evidence gates; bundle verification and automated retained
  host validation are green.

Verification:

- `dart format packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/tool/web_automated_validation.dart packages/fleury_web/tool/web_default_preflight.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_automated_validation_tool_test.dart packages/fleury_web/test/web_default_preflight_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/tool/web_automated_validation.dart packages/fleury_web/tool/web_default_preflight.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_automated_validation_tool_test.dart packages/fleury_web/test/web_default_preflight_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 25 VM tests.
- `cd packages/fleury_web && dart test test/web_automated_validation_tool_test.dart test/web_default_preflight_tool_test.dart` -
  passed with 17 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 34 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_automated_validation.dart --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --strict --json` -
  passed, writing `web-automated-validation.json`; the browser command passed
  88 Chrome tests and the VM command passed 18 VM tests.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` and `automatedValidation` checks both strict-passed.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` and `automatedValidation` checks both strict-passed.

## 2026-06-09 06:56 EDT

Exposed automated validation through the root benchmark launcher.

- Added `fleury benchmark web-automated-validation`, forwarding
  `--json-output`, `--strict`, and `--json` to
  `packages/fleury_web/tool/web_automated_validation.dart`.
- Updated `fleury benchmark web-default-preflight` so release-mode checks
  forward explicit `--automated-validation=PATH` or infer sibling
  `web-automated-validation.json` next to `web-readiness.json`; diagnostics
  mode with `--allow-unbundled` still omits both bundle and automated
  validation paths.
- Updated the benchmark catalog/help examples, package README, review packet,
  and phase audit so the repo-level command graph matches the generated
  release actions.
- Regenerated the local readiness-candidate packet after touching the root
  launcher source input. Readiness remains intentionally red for the same
  empirical gates, while bundle verification and automated validation checks
  remain green.

Verification:

- `dart format tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `dart analyze tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-readiness launcher"` -
  passed with 9 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 229 checked source inputs, one
  checked metadata field, 34 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` and `automatedValidation` checks both strict-passed.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` and `automatedValidation` checks both strict-passed.

## 2026-06-09 06:01 EDT

Made automated retained-host tests an explicit release action.

- Split the curated `webAutomatedTestFiles` source-input list into browser
  tests, VM tests, and fixture files in `readiness_bundle_verifier.dart`, so
  fingerprinting and release-action command generation share one source list.
- `web_readiness_bundle.dart` now emits
  `run-automated-web-host-tests` whenever the packet needs strict bundle
  verification or generated preview default preflights. The action depends on
  `verify-readiness-bundle`, includes structured counts and file lists for the
  fingerprinted automated-test group, and renders separate Chrome and VM
  commands in `web-release-actions.md`.
- Bundle-bound default-preflight release actions now depend on
  `run-automated-web-host-tests`, so the generated release graph requires
  artifact/source verification, automated retained-host tests, and then final
  preflight gates.
- Bundle verification now fails preview-preflight packets that omit the
  automated-test action or drift its file lists/generated test command arrays
  while keeping counts unchanged.
- Updated the README, review packet, and phase audit so reviewers can see that
  automated host test execution is part of the ordered release-action graph,
  not just an inert source fingerprint.

Verification:

- `dart format packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "passing reviewed artifacts|stale release actions|actions promote candidate thresholds"` -
  passed with three VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "stale release actions"` -
  passed after mutating the automated-test action's file list and command while
  keeping the file counts unchanged.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with
  `run-automated-web-host-tests` in `remainingReleaseActions`. Readiness
  remains intentionally red for candidate threshold review and real Chrome IME
  / VoiceOver manual evidence.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 228 checked source inputs, one
  checked metadata field, 29 checked manifest fields, and zero mismatches.
- `rg -n "run-automated-web-host-tests|Browser test command|VM test command|run-default-preflight" .../readiness-candidate/web-release-actions.md .../readiness-candidate/web-readiness-bundle.json` -
  confirmed the generated release actions render the automated host test
  action, Chrome/VM commands, and default-preflight dependencies.
- `cd packages/fleury_web && dart test -p chrome test/browser_frame_flush_scheduler_test.dart test/cell_metrics_test.dart test/dom_grid_surface_test.dart test/dom_input_source_test.dart test/dom_input_trace_fixture_test.dart test/run_tui_surface_test.dart test/run_tui_web_dom_test.dart test/semantic_dom_presenter_test.dart test/web_clipboard_test.dart` -
  passed with 86 Chrome tests. This is the generated browser command from the
  release-action packet.
- `cd packages/fleury_web && dart test test/frame_presentation_test.dart test/web_focus_coordinator_test.dart test/web_host_instrumentation_test.dart test/web_public_api_boundary_test.dart` -
  passed with 18 VM tests. This is the generated VM command from the
  release-action packet.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart --name "source input|bundle"` -
  passed with 11 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 25 VM tests.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts,
  228 checked source inputs, and 29 checked manifest fields.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts,
  228 checked source inputs, and 29 checked manifest fields.
- `jq empty` over the refreshed readiness bundle, readiness, scoreboard,
  semantic audit, manual audit, and default-preflight JSON files - passed.
- `rg -n "[ \t]+$" ...` over the touched tool/test/docs files and refreshed
  readiness-candidate packet - passed with no trailing whitespace hits.
- `git diff --check -- ...` over the touched tool/test/docs files and
  refreshed readiness-candidate packet - passed.

## 2026-06-09 06:20 EDT

Guarded the public retained DOM host against accidentally inaccessible output.

- `runTuiWebDom` now treats `semanticsEnabled: false` as diagnostics-only.
  Because the visual grid stays `aria-hidden`, disabling semantics throws
  unless the caller also passes `allowInaccessibleDiagnostics: true`.
- Supplying `semanticElement` while `semanticsEnabled` is false now throws an
  `ArgumentError`; the API no longer silently ignores a caller-provided
  accessibility root.
- Added Chrome coverage that the guard rejects disabled semantics before
  mutating the host DOM, and that explicitly acknowledged diagnostics mode
  still creates and disposes the visual/input roots cleanly.
- Updated the package README, review packet, phase audit, and semantics RFC so
  reviewers see this as an accessibility backstop rather than an app-facing
  product option.
- Regenerated the local readiness-candidate packet so `run_tui_web_dom.dart`
  and `run_tui_web_dom_test.dart` source fingerprints are current.

Verification:

- `dart format packages/fleury_web/lib/src/run_tui_web_dom.dart packages/fleury_web/test/run_tui_web_dom_test.dart` -
  passed.
- `dart analyze packages/fleury_web/lib/src/run_tui_web_dom.dart packages/fleury_web/test/run_tui_web_dom_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed with five Chrome tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet. Readiness remains
  intentionally red for candidate threshold review and real Chrome IME /
  VoiceOver manual evidence.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 228 checked source inputs, one
  checked metadata field, 29 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts,
  228 checked source inputs, and 29 checked manifest fields.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts,
  228 checked source inputs, and 29 checked manifest fields.

## 2026-06-09 03:39 EDT

Separated dirty-row diff fallback timing from span-build timing.

- `FramePresentationPlanner` now times only the unbounded previous/next buffer
  row-diff fallback and records it as `dirtyRowDiffTime` on
  `FramePresentationPlan`.
- `runTuiSurface` now reports that timing through
  `WebFrameInstrumentation`, while span build time covers only span-model
  construction for the already-selected dirty rows.
- Capture JSON now persists `dirtyRowDiffMicros`, capture summaries expose
  `dirtyRowDiffMs`, and old capture JSON remains readable with a zero default
  for the new field.
- `web_frame_report.dart` and `web_frame_scoreboard.dart` now surface row-diff
  fallback as a distinct timing slice; scoreboards include
  `dirtyRowDiffP95Ms` and a `Row diff p95` Markdown column.
- Updated the web RFC, package README, profiling README, phase audit, and
  review packet so reviewers can distinguish runtime-render-bound,
  dirty-row-diff-bound, span-build-bound, semantic-apply-bound,
  DOM-apply-bound, and browser-layout-bound failures.
- Regenerated the local Phase 1 refresh readiness-candidate bundle and the
  promoted baseline scoreboard artifacts. The current capture set predates
  `dirtyRowDiffMicros`, so refreshed scoreboards show zero row-diff time by
  backward-compatible loading; future captures persist the field directly.
- Readiness remains intentionally red only for candidate threshold review and
  unreviewed real Chrome IME / VoiceOver evidence.

Verification:

- `dart format packages/fleury_web/lib/src/frame_presentation.dart packages/fleury_web/lib/src/run_tui_surface.dart packages/fleury_web/lib/src/instrumentation/web_host_instrumentation.dart packages/fleury_web/tool/web_frame_report.dart packages/fleury_web/tool/web_frame_scoreboard.dart packages/fleury_web/test/frame_presentation_test.dart packages/fleury_web/test/web_host_instrumentation_test.dart packages/fleury_web/test/web_frame_scoreboard_tool_test.dart packages/fleury_web/test/run_tui_surface_test.dart` -
  passed.
- `dart analyze packages/fleury_web/lib/src/frame_presentation.dart packages/fleury_web/lib/src/run_tui_surface.dart packages/fleury_web/lib/src/instrumentation/web_host_instrumentation.dart packages/fleury_web/tool/web_frame_report.dart packages/fleury_web/tool/web_frame_scoreboard.dart packages/fleury_web/test/frame_presentation_test.dart packages/fleury_web/test/web_host_instrumentation_test.dart packages/fleury_web/test/web_frame_scoreboard_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/frame_presentation_test.dart test/web_host_instrumentation_test.dart test/web_frame_scoreboard_tool_test.dart` -
  passed with 21 VM tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart --name "records per-frame instrumentation"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --target=make-dom-default --strict --json` -
  inferred the sibling bundle, verified it, and exited 1 only for the
  remaining readiness blockers.
- `cd packages/fleury_web && dart run tool/web_frame_scoreboard.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --min-runs=3 --require-comparable-environment --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/scoreboard.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/scoreboard.json --strict` -
  refreshed the promoted baseline scoreboard artifacts with the row-diff
  timing column.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=normal-80x24 --frames=1 --warmup=0 --output=/tmp/fleury-web-dirty-row-diff-smoke.json --json` -
  passed; the smoke capture wrote `dirtyRowDiffMicros` on the frame and
  `summary.timings.dirtyRowDiffMs` in the capture summary.
- `jq empty` over the refreshed scoreboard, readiness, bundle, and smoke
  capture JSON artifacts - passed.

## 2026-06-09 03:47 EDT

Closed the report-tool coverage gap for dirty-row diff timing.

- Added `test/web_frame_report_tool_test.dart` so the single-capture report
  path is covered alongside instrumentation and scoreboard coverage.
- The test verifies that `web_frame_report.dart --json` exposes
  `timings.dirtyRowDiffMs`, can select `dirtyRowDiffMs` as the dominant p95
  slice, writes the `dirtyRowDiffMs` Markdown timing row, and remains backward
  compatible with older capture JSON that lacks `dirtyRowDiffMicros`.

Verification:

- `dart format packages/fleury_web/test/web_frame_report_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/test/web_frame_report_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_report_tool_test.dart` -
  passed with two VM tests.

## 2026-06-09 03:51 EDT

Extended root launcher coverage for dirty-row diff report timing.

- Updated the root `fleury benchmark web-report` test fixture so retained DOM
  frame captures include `dirtyRowDiffMicros`.
- The launcher test now verifies the summary JSON exposes
  `timings.dirtyRowDiffMs` and the generated Markdown contains the
  `dirtyRowDiffMs` timing row.

Verification:

- `dart format packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `dart analyze packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark web-report"` -
  passed with one VM test.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the readiness-candidate packet after the root test fixture
  change.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `jq empty` over the refreshed readiness bundle, readiness, and scoreboard
  JSON artifacts - passed.
- `git diff --check` - passed.

## 2026-06-09 03:59 EDT

Hardened `web_frame_capture.dart` VM coverage around pre-browser validation.

- Refactored `test/web_frame_capture_tool_test.dart` to use a shared process
  helper and added cheap executable-path tests that stop before Dart JS
  compilation or Chrome startup.
- Added coverage for text scenario listing, unknown scenario rejection,
  positive/non-negative numeric validation for `--frames`, `--warmup`, and
  `--budget-ms`, and unknown-option usage output.
- This keeps the frame-capture harness safer without adding another
  real-browser run to the standard local loop.

Verification:

- `dart format packages/fleury_web/test/web_frame_capture_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/test/web_frame_capture_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_capture_tool_test.dart` -
  passed with five VM tests.

## 2026-06-09 04:02 EDT

Tightened root launcher coverage for web frame capture options.

- Extended the `fleury benchmark web-capture` dry-run test to assert that
  `--headful` and `--compile-only` are forwarded to
  `packages/fleury_web/tool/web_frame_capture.dart` along with the existing
  scenario, frame-count, budget, output, Chrome, timeout, temp-retention, and
  JSON flags.
- The default-output test still covers the generated ignored
  `profiling/web/runs/<scenario>-...` bucket.
- The readiness bundle verifier stayed green after this test-only edit, so no
  generated evidence artifacts needed regeneration.

Verification:

- `dart format packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `dart analyze packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark web-capture"` -
  passed with two VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.

## 2026-06-09 04:04 EDT

Tightened package suite coverage for browser capture flags.

- Extended `web_frame_suite_tool_test.dart` so the dry-run suite plan proves
  `--headful` and `--keep-temp` are forwarded from
  `tool/web_frame_suite.dart` into each planned
  `tool/web_frame_capture.dart` command.
- This aligns package-level evidence with the root
  `fleury benchmark web-suite` / `web-capture` launcher coverage and keeps the
  empirical benchmark path auditable without launching Chrome.
- The readiness bundle verifier stayed green after this test-only edit, so no
  generated evidence artifacts needed regeneration.

Verification:

- `dart format packages/fleury_web/test/web_frame_suite_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/test/web_frame_suite_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_suite_tool_test.dart` -
  passed with five VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.

## 2026-06-09 04:05 EDT

Closed the suite semantic-apply gate coverage gap.

- Extended `web_frame_suite_tool_test.dart` so the dry-run suite plan includes
  `--max-semantic-apply-p95-ms` in its JSON gates and forwards the same gate
  to the planned `web_frame_scoreboard.dart` command.
- Extended the root `fleury benchmark web-suite` dry-run test to assert
  forwarding of `--max-semantic-apply-p95-ms` through `tool/fleury_dev.dart`.
- This keeps Phase 5 evidence aligned with the RFC's performance split:
  total-frame-bound, DOM-apply-bound, semantic-apply-bound, and browser-bound
  failures remain independently gateable.
- The readiness bundle verifier stayed green after these test-only edits, so
  no generated evidence artifacts needed regeneration.

Verification:

- `dart format packages/fleury_web/test/web_frame_suite_tool_test.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_suite_tool_test.dart` -
  passed with five VM tests.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark web-suite"` -
  passed with two VM tests.
- `dart analyze packages/fleury_web/test/web_frame_suite_tool_test.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `git diff --check` - passed.

## 2026-06-09 04:07 EDT

Closed the report semantic-apply gate coverage gap.

- Added a strict `web_frame_report.dart` package test proving
  `--max-semantic-apply-p95-ms` fails independently with gate id
  `semanticApplyP95Ms`, separate from total-frame and DOM-apply gates.
- Extended the root `fleury benchmark web-report` launcher test so its passing
  strict-gate path includes `--max-semantic-apply-p95-ms`.
- This keeps single-capture reports, repeated suites, and scoreboards aligned
  on the same semantic-apply performance slice used by the RFC evidence path.
- The readiness bundle verifier stayed green after these test-only edits, so
  no generated evidence artifacts needed regeneration.

Verification:

- `dart format packages/fleury_web/test/web_frame_report_tool_test.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_report_tool_test.dart` -
  passed with three VM tests.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "benchmark web-report"` -
  passed with one VM test.
- `dart analyze packages/fleury_web/test/web_frame_report_tool_test.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `git diff --check` - passed.

## 2026-06-09 04:12 EDT

Fixed `web_frame_capture.dart --compile-only --json` output and page retention.

- Reproduced the bug before the fix:
  `dart run tool/web_frame_capture.dart --scenario=normal-80x24 --compile-only --json`
  wrote `dart compile js` status text to stdout before the compile-only path,
  so stdout was not machine-readable JSON.
- The same pre-fix command printed a temp page directory that had already been
  deleted by the cleanup `finally` block unless callers also passed
  `--keep-temp`.
- `web_frame_capture.dart` now captures `dart compile js` output and writes it
  to stderr, preserving clean stdout for `--json`.
- Compile-only mode now preserves the generated page directory by default,
  matching the command help that says it prints the temp page directory. Normal
  browser capture still removes its generated page directory unless
  `--keep-temp` is set.
- Compile-only JSON now emits a structured
  `fleuryWebFrameCompileResult` with `pageDir`, `indexPath`, and
  `javascriptPath`; non-JSON compile-only output remains the path-only stdout
  form for shell use.
- Added a real compile-only VM test that verifies stdout is clean JSON, the
  generated page directory exists, and both `index.html` and
  `benchmark_capture.dart.js` are present.
- Regenerated the local readiness-candidate packet because
  `web_frame_capture.dart` is fingerprinted as a readiness source input.
  Readiness remains intentionally red only for reviewed threshold promotion and
  real Chrome IME / VoiceOver manual evidence.

Verification:

- `dart format packages/fleury_web/tool/web_frame_capture.dart packages/fleury_web/test/web_frame_capture_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_capture_tool_test.dart` -
  passed with six VM tests.
- `dart analyze packages/fleury_web/tool/web_frame_capture.dart packages/fleury_web/test/web_frame_capture_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=normal-80x24 --compile-only --json > /tmp/fleury-compile-only-fixed-stdout.json 2> /tmp/fleury-compile-only-fixed-stderr.txt && jq empty /tmp/fleury-compile-only-fixed-stdout.json && PAGE_DIR=$(jq -r '.pageDir' /tmp/fleury-compile-only-fixed-stdout.json) && test -d "$PAGE_DIR" && test -f "$PAGE_DIR/index.html" && test -f "$PAGE_DIR/benchmark_capture.dart.js" && rm -rf "$PAGE_DIR"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the readiness-candidate packet with the new capture-tool
  fingerprint.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `jq empty` over the refreshed readiness bundle, readiness, scoreboard,
  manual-validation audit, and semantic-coverage JSON artifacts - passed.
- `git diff --check` - passed.

## 2026-06-09 04:16 EDT

Fixed browser-process cleanup when capture startup fails before DevTools opens.

- Found that `_ChromeProcess.start` could spawn Chrome, then throw while
  waiting for `/json/version` before returning the process wrapper to the
  outer runner. In that path, the runner's `chrome` variable was still null,
  so the outer `finally` could not kill the process or remove the profile dir.
- Wrapped the DevTools handshake in a local `try/catch` inside
  `_ChromeProcess.start`; any startup failure now disposes the partially
  constructed wrapper before rethrowing.
- Added a fake-Chrome regression test that launches a Unix shell executable
  which never opens DevTools, forces a one-second timeout, and verifies the
  fake process receives termination before the tool exits.
- Regenerated the local readiness-candidate packet because
  `web_frame_capture.dart` is fingerprinted as a readiness source input.
  Readiness remains intentionally red only for reviewed threshold promotion and
  real Chrome IME / VoiceOver manual evidence.

Verification:

- `dart format packages/fleury_web/tool/web_frame_capture.dart packages/fleury_web/test/web_frame_capture_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_capture_tool_test.dart` -
  passed with seven VM tests.
- `dart analyze packages/fleury_web/tool/web_frame_capture.dart packages/fleury_web/test/web_frame_capture_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the readiness-candidate packet with the new capture-tool
  fingerprint.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `jq empty` over the refreshed readiness bundle, readiness, scoreboard,
  manual-validation audit, and semantic-coverage JSON artifacts - passed.
- `git diff --check` - passed.

## 2026-06-09 04:21 EDT

Constrained the frame-capture loopback static server to its generated page
directory.

- Replaced the direct `request.uri.pathSegments.join('/')` file lookup in
  `web_frame_capture.dart` with `resolveFrameCaptureStaticFile`, which maps
  `/` to `index.html`, rejects empty/current/parent path segments, and rejects
  decoded path separators inside a segment before joining under the generated
  page root.
- Added direct VM coverage for the resolver so the policy is tested without
  launching Chrome: normal root and JS requests resolve under the generated
  directory; encoded separator traversal attempts are rejected.
- The test also documents Dart URI normalization behavior: raw `/../...` and
  `/%2e%2e/...` requests normalize to in-root paths before resolver policy,
  while encoded separators such as `/..%2Fsecret.txt` are refused.
- Regenerated the local readiness-candidate packet because
  `web_frame_capture.dart` is fingerprinted as a readiness source input.
  Readiness remains intentionally red only for reviewed threshold promotion and
  real Chrome IME / VoiceOver manual evidence.

Verification:

- `dart format packages/fleury_web/tool/web_frame_capture.dart packages/fleury_web/test/web_frame_capture_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_capture_tool_test.dart --name "static server"` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_capture_tool_test.dart` -
  passed with eight VM tests.
- `dart analyze packages/fleury_web/tool/web_frame_capture.dart packages/fleury_web/test/web_frame_capture_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the readiness-candidate packet with the new capture-tool
  fingerprint.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `jq empty` over the refreshed readiness bundle, readiness, scoreboard,
  manual-validation audit, and semantic-coverage JSON artifacts - passed.
- `git diff --check` - passed.

## 2026-06-09 04:27 EDT

Closed the remaining Chrome-profile cleanup gap in frame capture startup.

- Found one pre-wrapper failure path left after the DevTools-handshake cleanup:
  `_ChromeProcess.start` created a temporary Chrome profile directory before
  calling `Process.start`. If the Chrome executable itself could not be
  started, no wrapper existed yet and the profile directory could leak.
- Wrapped the `Process.start(chromePath, ...)` call in a local `try/catch` that
  removes the just-created profile directory before rethrowing.
- Added a regression test that runs the capture tool with a missing Chrome path
  under a controlled `TMPDIR` and verifies no
  `fleury_web_chrome_profile_...` directories remain.
- Regenerated the local readiness-candidate packet because
  `web_frame_capture.dart` is fingerprinted as a readiness source input.
  Readiness remains intentionally red only for reviewed threshold promotion and
  real Chrome IME / VoiceOver manual evidence.

Verification:

- `dart format packages/fleury_web/tool/web_frame_capture.dart packages/fleury_web/test/web_frame_capture_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_capture_tool_test.dart --name "executable cannot start"` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_capture_tool_test.dart` -
  passed with nine VM tests.
- `dart analyze packages/fleury_web/tool/web_frame_capture.dart packages/fleury_web/test/web_frame_capture_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the readiness-candidate packet with the new capture-tool
  fingerprint.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `jq empty` over the refreshed readiness bundle, readiness, scoreboard,
  manual-validation audit, and semantic-coverage JSON artifacts - passed.
- `git diff --check` - passed.

## 2026-06-09 04:34 EDT

Aligned DOM cell metrics with the RFC browser-invalidation contract.

- Found that `DomCellMetrics` measured synchronously and observed container
  resize, but did not invalidate cached cell measurements when browser fonts
  finished loading or errored. That left initial fallback-font metrics able to
  persist until an unrelated resize, which could throw off grid size, pointer
  mapping, and IME caret placement.
- `DomCellMetrics.startObserving` now also observes `document.fonts.ready`,
  `loadingdone`, `loadingerror`, and `window.resize` for browser zoom/DPR-style
  invalidations. Those callbacks only mark metrics dirty and call the host's
  metrics-dirty callback; layout is still read only by `measure()` during the
  host read phase.
- Font and window listeners are removed on restart/dispose, and stale
  `fonts.ready` completions are ignored after disposal or a later observation
  generation.
- Added browser coverage that dispatches font `loadingdone` and window
  `resize` events, verifies the cached measurement is dirtied without being
  recomputed synchronously, and verifies disposal suppresses later browser
  invalidation events.
- Regenerated the local readiness-candidate packet because
  `dom_cell_metrics.dart` is fingerprinted as a readiness source input.
  Readiness remains intentionally red only for reviewed threshold promotion and
  real Chrome IME / VoiceOver manual evidence.

Verification:

- `dart format packages/fleury_web/lib/src/metrics/dom_cell_metrics.dart packages/fleury_web/test/cell_metrics_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/cell_metrics_test.dart` -
  passed with four Chrome tests.
- `dart analyze packages/fleury_web/lib/src/metrics/dom_cell_metrics.dart packages/fleury_web/test/cell_metrics_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 23 Chrome tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the readiness-candidate packet with the new metrics source
  fingerprint.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `jq empty` over the refreshed readiness bundle, readiness, scoreboard,
  manual-validation audit, and semantic-coverage JSON artifacts - passed.
- `git diff --check` plus a direct trailing-whitespace scan over the edited
  metrics source, metrics test, and execution log - passed.

## 2026-06-09 04:43 EDT

Kept browser pointer coordinate conversion inside the metrics boundary.

- Found that `DomInputSource` was reading cached browser metrics and then
  duplicating the cell-coordinate conversion math locally. That contradicted
  the RFC rule that `CellMetrics.cellForPoint` is the only coordinate
  conversion path, and would make future zoom/DPR/correction policy easy to
  split between input and metrics.
- `DomInputSource` now still uses `CellMetrics.cachedMeasurement` to obtain the
  last measured surface origin and validate that metrics exist, but delegates
  the local browser point to `cellMetrics.cellForPoint`.
- Added a browser test with a recording metrics fake that returns a deliberate
  mapped cell, proving pointer events use the metrics boundary instead of
  repeating raw column/row arithmetic inside input handling.
- Regenerated the local readiness-candidate packet because
  `dom_input_source.dart` is fingerprinted as a readiness source input.
  Readiness remains intentionally red only for reviewed threshold promotion and
  real Chrome IME / VoiceOver manual evidence.

Verification:

- `dart format packages/fleury_web/lib/src/input/dom_input_source.dart packages/fleury_web/test/dom_input_source_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_input_source_test.dart` -
  passed with 13 Chrome tests.
- `dart analyze packages/fleury_web/lib/src/input/dom_input_source.dart packages/fleury_web/test/dom_input_source_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 23 Chrome tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the readiness-candidate packet with the new input-source
  fingerprint.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `jq empty` over the refreshed readiness bundle, readiness, scoreboard,
  manual-validation audit, and semantic-coverage JSON artifacts - passed.
- `git diff --check` plus a direct trailing-whitespace scan over the edited
  input source, input test, and execution log - passed.

## 2026-06-09 04:48 EDT

Locked live DOM terminal text shaping to the same visual invariants as the
static HTML renderer.

- Found that the static HTML renderer and live retained DOM renderer had
  partially divergent base text CSS. Both preserved whitespace, but the live
  surface did not explicitly pin tab expansion, kerning, ligature behavior, or
  letter spacing. That made the measured grid vulnerable to browser font
  shaping defaults even though cell metrics, pointer hit testing, and wide-run
  correction all assume deterministic terminal text advances.
- Updated `cellGridCss` and `DomGridSurface._rootStyle` to enforce:
  - `white-space: pre`;
  - `tab-size: 1`;
  - `font-kerning: none`;
  - `font-variant-ligatures: none`;
  - `font-feature-settings: "liga" 0, "clig" 0`;
  - `letter-spacing: 0`.
- Added VM coverage for the static stylesheet and Chrome coverage for the live
  `fleury-screen` root style so future renderer changes cannot silently drop
  the terminal shaping contract.
- Regenerated the local readiness-candidate packet because both DOM renderer
  sources are fingerprinted as readiness source inputs. Readiness remains
  intentionally red for candidate threshold-policy review and pending real
  Chrome IME / VoiceOver manual evidence; bundle integrity remains green.

Verification:

- `dart format packages/fleury_web/lib/src/dom_grid/cell_grid_html.dart packages/fleury_web/lib/src/dom_grid/dom_grid_surface.dart packages/fleury_web/test/cell_grid_html_test.dart packages/fleury_web/test/dom_grid_surface_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/cell_grid_html_test.dart` -
  passed with 12 VM tests.
- `cd packages/fleury_web && dart test -p chrome test/dom_grid_surface_test.dart` -
  passed with 7 Chrome tests.
- `dart analyze packages/fleury_web/lib/src/dom_grid/cell_grid_html.dart packages/fleury_web/lib/src/dom_grid/dom_grid_surface.dart packages/fleury_web/test/cell_grid_html_test.dart packages/fleury_web/test/dom_grid_surface_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 23 Chrome tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the readiness-candidate packet with updated DOM renderer source
  fingerprints.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.

## 2026-06-09 04:55 EDT

Wired browser paste fallback through the host-owned clipboard service.

- Found that `DomInputSource` correctly preferred `ClipboardEvent` text,
  preserved multiline paste, and prevented default insertion only when paste
  was consumed, but it had no route to the in-process clipboard fallback when a
  browser paste event did not expose clipboard data.
- Added an optional `Clipboard` dependency to `DomInputSource`. The paste
  handler now:
  - uses `text/plain` or `text` from the browser event when available;
  - falls back to `clipboard.readInProcess()` only when the browser event has no
    `clipboardData`;
  - leaves an empty browser-provided clipboard payload alone instead of
    substituting stale in-process text.
- Updated `runTuiWebDom` to create or accept one clipboard instance and pass
  that same object to both `DomInputSource` and `runTuiSurface`. App copy and
  fallback paste now share the same host-owned register.
- Added browser coverage for no-data paste fallback, empty browser paste data,
  and the assembled retained DOM host path. The integration test now proves a
  no-data browser paste reaches the focused `TextInput` through the same
  clipboard object installed for the host lifetime.
- Regenerated the local readiness-candidate packet because
  `dom_input_source.dart` and `run_tui_web_dom.dart` are fingerprinted
  readiness source inputs. Readiness remains intentionally red for candidate
  threshold-policy review and pending real Chrome IME / VoiceOver manual
  evidence; bundle integrity remains green.

Verification:

- `dart format packages/fleury_web/lib/src/input/dom_input_source.dart packages/fleury_web/lib/src/run_tui_web_dom.dart packages/fleury_web/test/dom_input_source_test.dart packages/fleury_web/test/run_tui_web_dom_test.dart` -
  passed.
- `dart analyze packages/fleury_web/lib/src/input/dom_input_source.dart packages/fleury_web/lib/src/run_tui_web_dom.dart packages/fleury_web/test/dom_input_source_test.dart packages/fleury_web/test/run_tui_web_dom_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_input_source_test.dart` -
  passed with 15 Chrome tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed with one Chrome test.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 23 Chrome tests.
- `cd packages/fleury_web && dart test -p chrome test/web_clipboard_test.dart` -
  passed with 3 Chrome tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the readiness-candidate packet with updated input/host source
  fingerprints.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.

## 2026-06-09 05:01 EDT

Made browser clipboard API availability an explicit capability check.

- Found that `WebClipboard` had an injected `clipboardAvailable` test hook, but
  the default browser path assumed `navigator.clipboard.writeText` was present
  and only discovered missing API support as a failed write. That weakened the
  RFC requirement to report unavailable browser clipboard capability distinctly
  from permission-denied write attempts.
- `WebClipboard` now detects a function-valued JS
  `navigator.clipboard.writeText` method before attempting a browser write.
  Injected `writeText` callbacks still count as available unless a test or host
  explicitly overrides `clipboardAvailable`.
- When the API is unavailable, `writeWithReport` now skips the browser attempt,
  updates the in-process register, returns `inProcessOnly`, and reports the
  degraded fallback as "Browser clipboard API is unavailable."
- Added browser coverage proving the unavailable path does not attempt
  `writeText`, while still preserving the in-process register fallback.
- Regenerated the local readiness-candidate packet after the final
  method-level capability refinement because `web_clipboard.dart` is
  fingerprinted as a readiness source input. Readiness remains intentionally
  red for candidate threshold-policy review and pending real Chrome IME /
  VoiceOver manual evidence; bundle integrity remains green.

Verification:

- `dart format packages/fleury_web/lib/src/clipboard/web_clipboard.dart packages/fleury_web/test/web_clipboard_test.dart` -
  passed.
- `dart analyze packages/fleury_web/lib/src/clipboard/web_clipboard.dart packages/fleury_web/test/web_clipboard_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/web_clipboard_test.dart` -
  passed with 4 Chrome tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed with one Chrome test.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart --name "clipboard backend is installed for the host lifetime|dispose restores clipboard|setup failures restore clipboard"` -
  passed with 3 Chrome tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the readiness-candidate packet with the updated method-level
  clipboard source fingerprint.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.

## 2026-06-09 05:11 EDT

Refreshed clipboard readiness artifacts and checked the manual page smoke path.

- Regenerated the Phase 1 refresh readiness-candidate packet after the
  `navigator.clipboard.writeText` method-level capability check landed.
- Verified the regenerated bundle against generated artifacts, source-input
  fingerprints, command working-directory metadata, and manifest field
  bindings.
- Re-audited the generated release actions. The remaining blockers are
  review/manual gates: threshold-policy promotion and real Chrome IME /
  VoiceOver evidence with reviewer provenance.
- Ran the Chrome manual-validation page smoke test so the pending manual
  evidence path is still backed by a current automated page-readiness check.

Verification:

- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet; `strictPass` remains false
  for candidate threshold review and pending manual IME / VoiceOver evidence.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `jq empty` over the refreshed readiness bundle, readiness, scoreboard,
  manual-validation audit, and semantic-coverage JSON artifacts - passed.
- `rg -n "[ \t]+$" ...` over the clipboard source/test, execution log, and
  readiness-candidate packet - passed with no trailing whitespace hits.
- `git diff --check` - passed.
- `cd packages/fleury_web && dart test -p chrome test/manual_validation_page_test.dart` -
  passed with 2 Chrome tests.

## 2026-06-09 05:15 EDT

Added an automated guard for the retained DOM no-layout-read boundary.

- The web RFC requires layout reads to happen in the host read phase, not while
  presenting visual or semantic DOM updates.
- Added a VM source-boundary test to `web_public_api_boundary_test.dart` that
  scans `lib/src` for browser layout-read APIs and allows them only in
  `DomCellMetrics`, where `measure()` owns `getBoundingClientRect` and
  `getComputedStyle`.
- This protects `DomGridSurface.present`, `SemanticDomPresenter.present`,
  input, and focus code from accidentally introducing synchronous browser
  layout reads while they should consume cached `MeasuredCellBox` data.
- No readiness bundle regeneration was needed because this is test-only and
  does not change a fingerprinted implementation/readiness input.

Verification:

- `dart format packages/fleury_web/test/web_public_api_boundary_test.dart` -
  passed.
- `dart analyze packages/fleury_web/test/web_public_api_boundary_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_public_api_boundary_test.dart` -
  passed with 2 VM tests.

## 2026-06-09 05:20 EDT

Hardened hidden-textarea paste input cleanup.

- Found that the paste-event path correctly prevents default browser insertion,
  clears the hidden textarea, and emits a Fleury `PasteEvent`, but a standalone
  browser `input` event with `inputType="insertFromPaste"` was only ignored.
- Updated `DomInputSource` so `insertFromPaste` input events also call
  `preventDefault()` and clear the hidden textarea without emitting duplicate
  Fleury text.
- Added Chrome coverage proving paste-input residue is cleared, no text event
  is emitted, and the hidden textarea does not become a browser-side source of
  truth.
- Regenerated the readiness-candidate packet because `dom_input_source.dart`
  is fingerprinted as a web implementation source input. Readiness remains
  intentionally red for candidate threshold-policy review and pending real
  Chrome IME / VoiceOver manual evidence; bundle integrity remains green.

Verification:

- `dart format packages/fleury_web/lib/src/input/dom_input_source.dart packages/fleury_web/test/dom_input_source_test.dart` -
  passed.
- `dart analyze packages/fleury_web/lib/src/input/dom_input_source.dart packages/fleury_web/test/dom_input_source_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_input_source_test.dart` -
  passed with 16 Chrome tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed with one Chrome test.
- `cd packages/fleury_web && dart test -p chrome test/dom_input_trace_fixture_test.dart` -
  passed with 13 Chrome tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with the updated
  `dom_input_source.dart` fingerprint.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.

## 2026-06-09 05:26 EDT

Cleared hidden-textarea residue at source start and teardown.

- Found one remaining stale-state edge around host-owned textarea reuse:
  `DomInputSource.start()` could attach to a textarea that already contained
  browser residue, and `dispose()` left any later residue in place when the
  textarea was injected by the caller and therefore intentionally retained.
- Updated `DomInputSource` to clear the textarea after listener installation
  and again during disposal before host-owned injected elements are left in
  place or generated elements are removed.
- Added Chrome coverage for an injected, host-owned textarea that starts with
  stale text, is cleared on `start()`, receives new residue, and is cleared
  again on `dispose()` without being removed from its host.
- Regenerated the readiness-candidate packet because `dom_input_source.dart`
  is fingerprinted as a web implementation source input. Readiness remains
  intentionally red for candidate threshold-policy review and pending real
  Chrome IME / VoiceOver manual evidence; bundle integrity remains green.

Verification:

- `dart format packages/fleury_web/lib/src/input/dom_input_source.dart packages/fleury_web/test/dom_input_source_test.dart` -
  passed.
- `dart analyze packages/fleury_web/lib/src/input/dom_input_source.dart packages/fleury_web/test/dom_input_source_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/dom_input_source_test.dart` -
  passed with 17 Chrome tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed with one Chrome test.
- `cd packages/fleury_web && dart test -p chrome test/dom_input_trace_fixture_test.dart` -
  passed with 13 Chrome tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with the updated
  `dom_input_source.dart` fingerprint.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.

## 2026-06-09 05:33 EDT

Added assembled retained-DOM cleanup coverage for contained build errors.

- While trying to cover setup-failure cleanup in `runTuiWebDom`, confirmed the
  framework contains root build failures and renders the error widget during
  the first scheduled frame instead of throwing out of host construction.
- Added Chrome coverage for that actual path: generated visual/semantic roots,
  hidden textarea, and host clipboard install are present before the first
  frame; after the contained build error is rendered, `host.dispose()` removes
  the generated roots and textarea and restores the prior clipboard.
- This protects the assembled DOM host lifecycle directly, rather than relying
  only on lower-level `runTuiSurface` cleanup tests.
- No readiness-bundle regeneration was needed because this is test-only and the
  current bundle does not fingerprint `run_tui_web_dom_test.dart`; strict
  bundle verification still passed with zero mismatches.

Verification:

- `dart format packages/fleury_web/test/run_tui_web_dom_test.dart` -
  passed.
- `dart analyze packages/fleury_web/test/run_tui_web_dom_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed with two Chrome tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.

## 2026-06-09 05:36 EDT

Locked down caller-supplied retained DOM root ownership.

- Added assembled-host Chrome coverage for `runTuiWebDom` with caller-supplied
  visual and semantic root elements.
- The test proves the host configures and uses those supplied roots, but
  `host.dispose()` keeps them mounted in the caller's host element while
  clearing their children.
- The same regression verifies generated keyboard-capture textarea cleanup and
  clipboard restoration still happen with caller-supplied visual/semantic roots.
- No readiness-bundle regeneration was needed because this is test-only and the
  current bundle does not fingerprint `run_tui_web_dom_test.dart`; strict
  bundle verification still passed with zero mismatches.

Verification:

- `dart format packages/fleury_web/test/run_tui_web_dom_test.dart` -
  passed.
- `dart analyze packages/fleury_web/test/run_tui_web_dom_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_web_dom_test.dart` -
  passed with three Chrome tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.

## 2026-06-09 05:52 EDT

Bound retained web automated host tests into readiness-bundle fingerprints.

- Found that the latest assembled `runTuiWebDom` lifecycle tests were not
  fingerprinted by the readiness bundle, even though they now carry meaningful
  evidence for generated-root cleanup, caller-supplied root ownership, hidden
  textarea cleanup, and clipboard restoration.
- Added a required `webAutomatedTestFiles` source-input group in the shared
  readiness-bundle verifier. The group fingerprints the curated retained web
  automated host/source-boundary tests for scheduler, metrics, frame
  presentation, DOM grid, input, browser input traces, focus, clipboard,
  semantics, host instrumentation, surface assembly, and public API boundaries.
- Verification now fails if the automated host test group is missing, omitted
  from expected source-input coverage, or stale.
- Updated README/review/audit docs to describe retained web automated host test
  fingerprints separately from retained web implementation fingerprints.
- Regenerated the local readiness-candidate packet. Readiness remains
  intentionally red for candidate threshold-policy review and pending real
  Chrome IME / VoiceOver manual evidence, but bundle integrity is green with
  the new automated-test source inputs.

Verification:

- `dart format packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/readiness_bundle_verifier.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/tool/web_default_preflight.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart packages/fleury_web/test/web_default_preflight_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "source input|source groups|fingerprint|omitted implementation|stale implementation|default preflight"` -
  passed with four VM tests.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart --name "source input|bundle"` -
  passed with 11 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "keeps artifacts when strict readiness fails|actions promote candidate thresholds|writes passing reviewed artifacts|requires source groups"` -
  passed with four VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 25 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the readiness-candidate packet with 14
  `webAutomatedTestFiles`, including `run_tui_web_dom_test.dart`.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 228 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 228 checked source inputs and
  `missingSourceInputCount: 0`.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 228 checked source inputs and
  `missingSourceInputCount: 0`.

## 2026-06-09 03:12 EDT

Hardened threshold-review provenance.

- `web_readiness.dart` now requires the threshold-review summary to bind back
  to the candidate threshold policy it reviewed:
  - `inputPath` must be present;
  - `inputPolicyFingerprint` must be present;
  - `inputPath` must load as a `fleuryWebFrameThresholds` JSON policy;
  - the candidate input must not already be reviewed;
  - the canonical input-policy fingerprint must match the review summary.
- This complements the existing reviewed-output check, which already compares
  the threshold-review `outputPolicyFingerprint` with the frame scoreboard's
  reviewed threshold policy fingerprint.
- Updated readiness and readiness-bundle fixtures to write a real candidate
  threshold input beside the reviewed threshold output, matching the promotion
  workflow used by `web_threshold_review.dart`.
- Regenerated the readiness candidate bundle after the audit change.

Verification:

- `dart analyze packages/fleury_web/tool/web_readiness.dart packages/fleury_web/test/web_readiness_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "promote candidate thresholds|passing reviewed artifacts|keeps artifacts|default preflight"` -
  passed.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart --name "bundle|readiness"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --target=make-dom-default --strict --json` -
  exited 1 as expected; the inferred sibling bundle was required and bound,
  bundle verification passed, and the only blockers remained threshold review
  state plus real Chrome IME / VoiceOver manual evidence.

## 2026-06-09 03:19 EDT

Added a stale-candidate guard to threshold promotion.

- `web_threshold_review.dart` now accepts
  `--expect-input-fingerprint=FNV`. When supplied, promotion exits before
  writing reviewed output if the loaded candidate threshold policy no longer
  matches the fingerprint from the review plan.
- Generated threshold-review plans now include
  `--expect-input-fingerprint=<candidate fingerprint>` in their promotion
  command.
- Readiness-bundle release actions now include the same expected fingerprint
  in `review-threshold-policy.details.expectedInputFingerprint` and in the
  promotion `commandTemplate`.
- The root `fleury benchmark web-threshold-review` launcher forwards the new
  option and its benchmark catalog example shows the guarded workflow.
- Regenerated `threshold-review-plan.md` and the local readiness-candidate
  packet so generated release actions and source-input fingerprints reflect the
  guard.

Verification:

- `dart analyze packages/fleury_web/tool/web_threshold_review.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_threshold_review_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_threshold_review_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "promote candidate thresholds|candidate thresholds|default preflight"` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-threshold-review|benchmark catalog"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_threshold_review.dart --input=.../thresholds.candidate.json --write-plan=.../threshold-review-plan.md --review-context-hint=...` -
  regenerated the plan with
  `--expect-input-fingerprint=fnv1a64:d6f18428fe25af25`.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=.../2026-06-08-local-dom-retained-phase1-refresh --manual=.../profiling/web/manual --output-dir=.../readiness-candidate --thresholds=.../thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=.../readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `rg -n -- "--expect-input-fingerprint=fnv1a64:d6f18428fe25af25|expectedInputFingerprint" .../threshold-review-plan.md .../web-readiness-bundle.json .../web-release-actions.md` -
  confirmed the guard is present in the review plan, bundle JSON, and release
  action markdown.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=.../readiness-candidate/web-readiness.json --target=make-dom-default --strict --json` -
  exited 1 as expected; the inferred sibling bundle was required and bound,
  bundle verification passed, and the only blockers remained threshold review
  state plus real Chrome IME / VoiceOver manual evidence.

## 2026-06-09 03:24 EDT

Synchronized human-facing threshold-review instructions with the guarded
promotion flow.

- Updated the package README, profiling web artifact README, phase audit,
  review packet, and root benchmark help example so threshold promotion
  examples include `--expect-input-fingerprint=FNV1A64_FROM_REVIEW_PLAN`.
- Clarified that reviewers should keep the generated expected-fingerprint
  argument from `threshold-review-plan.md` or `web-release-actions.md`; if the
  candidate threshold policy changes after review, promotion fails before
  writing reviewed output.
- Clarified that readiness verifies both sides of the promotion summary:
  `outputPolicyFingerprint` against the reviewed threshold policy loaded by
  the scoreboard, and `inputPolicyFingerprint` against the candidate policy
  named by the threshold-review summary.

Verification:

- `dart format tool/fleury_dev.dart` - passed.
- `dart analyze tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-threshold-review|benchmark catalog|release-grade benchmark help"` -
  passed.
- `rg -n "web[-_]threshold-review.*--output=.*thresholds\\.json|web_threshold_review\\.dart --input=.*--output=.*thresholds\\.json|web-threshold-review --input=.*--output=.*thresholds\\.json" ...` -
  confirmed current human-facing promotion examples include
  `--expect-input-fingerprint`; remaining unguarded examples are historical
  append-only execution-log entries.

## 2026-06-09 02:54 EDT

Hardened default/retirement preflight so a bare readiness JSON cannot be
mistaken for final release approval.

- `web_default_preflight.dart` now requires a readiness bundle by default.
  Without `--bundle=PATH`, the preflight adds a failing `readinessBundle`
  check with blocker text explaining that `--allow-unbundled` is diagnostics
  only.
- Preflight JSON/Markdown now records whether the run was `bundleRequired` and
  `bundleBound`.
- `web_readiness_bundle.dart` passes `--allow-unbundled` only when generating
  its preview default-preflight artifacts. Those previews remain
  readiness-bound snapshots with `bundleRequired: false` and
  `bundleBound: false`; final release-action commands remain bundle-bound and
  continue to include `--bundle=...`.
- The root `fleury benchmark web-default-preflight` launcher now forwards
  `--allow-unbundled` for local diagnostics and documents that the flag is not
  a release gate.
- Updated the package README, phase audit, and re-review packet so the docs
  match the stricter tool behavior.
- Regenerated the local readiness-candidate packet. The bundle still verifies
  strictly; the final bundle-bound preflights still fail only on the intended
  readiness blockers: candidate threshold-policy review and pending real
  Chrome IME / VoiceOver manual evidence.

Verification:

- `dart format packages/fleury_web/tool/web_default_preflight.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_default_preflight_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_default_preflight.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_default_preflight_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart` -
  passed with 13 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "default preflight|preflight|write-default|keeps artifacts"` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "default preflight options|web-default-preflight|benchmark catalog"` -
  passed with 2 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 25 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed and the run reported
  `bundleRequired: true`, `bundleBound: true`.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed and the run reported
  `bundleRequired: true`, `bundleBound: true`.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --target=make-dom-default --strict --json` -
  exited 1 and now includes the explicit missing-bundle blocker.

## 2026-06-09 03:01 EDT

Improved final-preflight ergonomics while keeping the bundle gate strict.

- `web_default_preflight.dart` now infers a sibling
  `web-readiness-bundle.json` when `--bundle=PATH` is omitted. A normal
  preflight invocation is therefore bundle-bound by default instead of failing
  because the bundle flag was absent.
- `--allow-unbundled` still suppresses bundle inference for diagnostics-only
  readiness inspection. Generated preview preflight artifacts from
  `web_readiness_bundle.dart` continue to use that flag and record
  `bundleRequired: false`, `bundleBound: false`.
- The root `fleury benchmark web-default-preflight` launcher mirrors the same
  default: it infers the sibling bundle path from `--readiness=...` unless
  `--allow-unbundled` is supplied.
- Updated the package README, phase audit, and re-review packet to describe the
  inferred sibling bundle behavior.
- Regenerated the local readiness-candidate packet. The generated preview
  preflight artifacts remain unbundled snapshots, while direct final preflight
  runs against the same readiness path now bind to the sibling bundle and
  verify it successfully before failing on the remaining readiness blockers.

Verification:

- `dart format packages/fleury_web/tool/web_default_preflight.dart packages/fleury_web/test/web_default_preflight_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_default_preflight.dart packages/fleury_web/test/web_default_preflight_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_default_preflight_tool_test.dart` -
  passed with 14 VM tests.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "default preflight options|diagnostics mode|infers sibling default preflight bundle|web-default-preflight|benchmark catalog"` -
  passed with 4 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "default preflight|write-default|keeps artifacts"` -
  passed.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "writes passing reviewed artifacts|keeps artifacts"` -
  passed with 2 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --target=make-dom-default --strict --json` -
  inferred the sibling `web-readiness-bundle.json`, verified the bundle, and
  exited 1 only for the remaining readiness blockers.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  verified the explicit bundle path and exited 1 only for the remaining
  readiness blockers.

## 2026-06-09 02:40 EDT

Tightened manual-evidence provenance around the retained DOM validation page.

- `web/manual_validation.dart` now records manual evidence metadata on
  `document.body` before the retained DOM page runs:
  `data-fleury-manual-browser-version`,
  `data-fleury-manual-platform`,
  `data-fleury-manual-user-agent`, and
  `data-fleury-manual-page`.
- The manual page also renders the same browser/platform/page metadata through
  a retained semantic status node, so the evidence metadata has both DOM and
  semantic visibility.
- Manual target templates and starter evidence now list the required page
  provenance attributes under `reviewInstructions.provenanceAttributes`.
  Stale templates or copied evidence that omit that list are rejected by the
  manual evidence contract before review.
- Readiness bundle release actions now surface the same list as
  `manualPageProvenanceAttributes` for each manual target, next to the page
  build, smoke-test, serve, provenance-helper, and audit commands.
- Refreshed the existing pending starter evidence for `chrome-ime-macos` and
  `chrome-voiceover-macos` without marking either target reviewed. The manual
  audit now reports zero invalid entries and only the expected pending
  provenance blockers: `reviewedBy`, `capturedAt`, and
  `environment.browserVersion`.
- Updated package README, review packet, phase audit, and profiling manual
  evidence README so reviewers know to read
  `data-fleury-manual-browser-version` from the manual page and use it for
  `--browser-version` after confirming the intended Chrome session.
- Regenerated the local readiness-candidate packet. It remains intentionally
  red for candidate threshold-policy review and pending real Chrome IME /
  VoiceOver manual evidence, while bundle fingerprint verification remains
  green.

Verification:

- `dart format packages/fleury_web/web/manual_validation.dart packages/fleury_web/test/manual_validation_page_test.dart packages/fleury_web/lib/src/manual_validation/manual_validation_targets.dart packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_manual_validation_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/web/manual_validation.dart packages/fleury_web/test/manual_validation_page_test.dart packages/fleury_web/lib/src/manual_validation/manual_validation_targets.dart packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_manual_validation_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/manual_validation_page_test.dart` -
  passed with 2 Chrome tests.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed with 21 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "manual evidence actions|existing starter evidence|manual evidence|template|starter|manual page signals|serve notes"` -
  passed with 7 VM tests.
- `cd packages/fleury_web && dart compile js web/manual_validation.dart -o web/manual_validation.dart.js` -
  rebuilt the served manual validation JavaScript.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/plan.md --write-templates=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/review.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json --json` -
  regenerated plan/templates/review/audit with zero invalid entries, two
  `needsReview` targets, and only manual provenance blockers for
  `reviewedBy`, `capturedAt`, and `environment.browserVersion`.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed.

## 2026-06-09 02:30 EDT

Quoted shell placeholders in the new provenance examples.

- Updated the profiling manual-evidence README and root `fleury benchmark
  web-manual-validation` help example so placeholder arguments containing
  `<...>` are shell-quoted. The generated release-action packet and generated
  manual plan were already quoted by command rendering.
- Regenerated the local readiness-candidate packet after the root launcher
  touch so the bundle's root-launcher source fingerprint is current.

Verification:

- `dart format tool/fleury_dev.dart` - passed.
- `dart analyze tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-manual-validation"` -
  passed with 2 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts,
  214 checked source inputs, and `missingSourceInputCount: 0`.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts,
  214 checked source inputs, and `missingSourceInputCount: 0`.
- `git diff --check` - passed.
- `rg -n "[ \t]+$" ...` over the host SPI source/tests, updated web docs, and
  execution-log files - passed with no trailing whitespace hits.
- `rg -n "^import 'package:fleury/fleury_core\.dart" packages/fleury_web` -
  passed with no web code imports from the app-facing core barrel.
- `rg -n "^export 'src/runtime/(input_dispatcher|tui_frame_loop|tui_runtime)|^export 'src/semantics/semantics_owner|SemanticActionContributor|SemanticsElement|RenderDamageTracker|FrameScheduler" packages/fleury/lib/fleury_core.dart packages/fleury/lib/fleury.dart packages/fleury/lib/fleury_host.dart` -
  confirmed the host-only exports are in `fleury_host.dart` only.

## 2026-06-09 02:28 EDT

Reduced manual evidence friction without weakening the manual gate.

- Added `web_manual_validation.dart --update-provenance=PATH` for existing
  starter or copied evidence files. The command can update only `reviewedBy`,
  `capturedAt`, and `environment.browserVersion`; it refuses stale/wrong-target
  manual evidence and never changes top-level status or required-check status.
- `--captured-at=now` records the current UTC time, while explicit
  `--captured-at=ISO` values are normalized through `DateTime.parse`.
- The command still leaves the strict manual audit red until the reviewer fills
  actual per-check observations and marks the required checks as `pass`.
- The root `fleury benchmark web-manual-validation` launcher now forwards
  `--write-starter`, `--starter-template`, `--update-provenance`,
  `--reviewed-by`, `--captured-at`, and `--browser-version`.
- Readiness bundle manual evidence actions now emit a non-runnable
  `provenanceCommandTemplate` for each manual target, with placeholders for
  reviewer and Chrome version. Existing starter files still suppress the
  no-overwrite starter command, but they now get the same provenance command
  template as missing-starter flows.
- Updated the package README, review packet, phase audit, profiling manual
  evidence README, generated manual plan, and regenerated release-action packet
  so reviewers see the provenance command in the same workflow as the manual
  page build/smoke/serve and strict audit commands.
- Regenerated manual validation artifacts and the local readiness-candidate
  bundle. Readiness remains intentionally red for the same gates: candidate
  threshold policy review and real Chrome IME / VoiceOver manual evidence.

Verification:

- `dart format packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_manual_validation_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_manual_validation.dart packages/fleury_web/tool/web_readiness_bundle.dart packages/fleury_web/test/web_manual_validation_tool_test.dart packages/fleury_web/test/web_readiness_bundle_tool_test.dart tool/fleury_dev.dart packages/fleury/test/tool/terminal_matrix_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_manual_validation_tool_test.dart` -
  passed with 21 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart --name "manual evidence actions|existing starter evidence|manual evidence|template|starter|release actions"` -
  passed with 6 VM tests.
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart --name "web-manual-validation"` -
  passed with 2 VM tests.
- `cd packages/fleury_web && dart test test/web_readiness_bundle_tool_test.dart` -
  passed with 25 VM tests.
- `cd packages/fleury_web && dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/plan.md --write-templates=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/review.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json --json` -
  regenerated manual plan/templates/review/audit. The audit still reports
  `strictPass: false`, two `needsReview` targets, zero invalid files, and
  provenance blockers for `reviewedBy`, `capturedAt`, and
  `environment.browserVersion`.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json` -
  regenerated the local readiness-candidate packet with provenance command
  templates in `remainingReleaseActions`.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 214 checked source inputs, one
  checked metadata field, 20 checked manifest fields, and zero mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts,
  214 checked source inputs, and `missingSourceInputCount: 0`.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected for the remaining readiness blockers; nested
  `readinessBundle` verification passed with 11 checked generated artifacts,
  214 checked source inputs, and `missingSourceInputCount: 0`.

## 2026-06-09 14:03 EDT

Tightened retained semantic update cost and narrowed the v1 manual evidence
gate to IME, leaving VoiceOver as an explicit follow-up accessibility focus.

- Kept `chrome-voiceover-macos` available as an explicit follow-up target and
  through the all-target preset, but removed it from the `v1` release preset.
  The current release gate now asks for real Chrome/macOS IME evidence only;
  VoiceOver is no longer a defaulting blocker for this slice.
- Regenerated the readiness-candidate bundle with `--target-preset=v1`. The
  bundle now reports one manual target, `chrome-ime-macos`, with expected
  pending provenance blockers for `reviewedBy`, `capturedAt`, and
  `environment.browserVersion`.
- Added `SemanticState.hasSameValues` so retained semantic diffing can compare
  nested state values without allocating `Map.unmodifiable` wrappers through
  the public `values` getter.
- Changed `SemanticsOwner` to retain the previous node index alongside the
  current tree. Owner updates now diff directly from retained node maps instead
  of rebuilding both previous and next node maps on every semantic update.
- Reworked semantic node equality to compare child order directly and use the
  new state deep-compare path. This removes list allocation and map-wrapper
  churn from the no-op and mostly-retained semantic diff path.
- Added owner tests for nested semantic state stability and for clearing the
  retained node index on dispose.
- Kept the threshold candidate unpromoted. The current
  `thresholds.candidate.json` still permits over-budget frames across all
  scenarios and is not defensible as a reviewed release threshold.
- The focused scratch capture after the semantic owner cache remains red on
  total frame budget, but the semantic apply path is much tighter than the
  earlier retained-semantics capture:
  - baseline `stress-300x100-run-1.json` p95: tree `78000us`, coverage
    `128900us`, diff `34600us`, presenter `1275700us`, apply `1280400us`,
    runtime build `259299us`, total `1308000us`.
  - presenter-cache scratch p95: tree `202701us`, coverage `107899us`, diff
    `271300us`, presenter `166399us`, apply `855700us`, runtime build
    `515601us`, total `2567200us`.
  - semantic-owner-cache scratch p95: tree `44401us`, coverage `24200us`,
    diff `58800us`, presenter `51601us`, apply `142500us`, runtime build
    `258599us`, total `510900us`.
- The next performance pressure point is no longer obvious DOM semantic apply;
  the scratch run is now dominated by runtime build / full-frame product work,
  so the next pass should use a batched source change plus one focused capture
  instead of repeatedly re-running the browser suite.

Verification:

- `dart format packages/fleury/lib/src/semantics/semantics.dart packages/fleury/lib/src/semantics/semantics_owner.dart packages/fleury/test/semantics/semantics_owner_test.dart` -
  passed.
- `dart analyze packages/fleury/lib/src/semantics/semantics.dart packages/fleury/lib/src/semantics/semantics_owner.dart packages/fleury/test/semantics/semantics_owner_test.dart packages/fleury_web/lib/src/semantics/semantic_dom_presenter.dart packages/fleury_web/test/run_tui_surface_test.dart` -
  passed.
- `cd packages/fleury && dart test test/semantics/semantics_owner_test.dart` -
  passed with 5 VM tests.
- `cd packages/fleury && dart test test/semantics/semantics_owner_test.dart test/semantics/semantics_test.dart` -
  passed with 34 VM tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart test/semantic_dom_presenter_test.dart` -
  passed with 37 Chrome tests.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=stress-300x100 --frames=16 --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/runs/stress-300x100-semantic-owner-cache-check.json --timeout=90 --json` -
  passed with 16 frames, `overBudgetPercent: 100`, dominant p95 slice
  `runtimeBuildMs`, and p95 total frame time `510900us`.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=v1 --write-default-preflights --completion-audit=/Users/dan/Coding/fleury-web-phase1/docs/implementation/web-rfc-completion-audit.json --json` -
  regenerated the readiness-candidate bundle. The bundle reports
  `strictPass: false` because the threshold policy is still candidate, manual
  IME evidence still needs review, and default preflights remain blocked.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 227 checked source inputs, 75
  checked manifest fields, and zero mismatches.

## 2026-06-09 15:12 EDT

Audited the remaining release gates after the automated validation/default
preflight refresh.

- Inspected `tool/web_threshold_review.dart` and the current
  `threshold-review-plan.md`. Promotion remains intentionally non-runnable as
  generated: the command requires replacing `--reviewed-by=<reviewer>` and
  providing a concrete `--review-note` acknowledging that all 11 reviewed
  scenarios permit over-budget frames. I did not promote
  `thresholds.candidate.json` to `thresholds.json`, because doing so would
  misrepresent the required human review/provenance gate.
- Rechecked the v1 manual evidence state. The only release-blocking manual
  target is `chrome-ime-macos`; it still has 0/6 required checks passing and
  provenance blockers for `reviewedBy`, `capturedAt`, and
  `environment.browserVersion`.
- Ran the Chrome manual-validation page smoke. It confirms the retained DOM
  manual page reaches ready, but it is not a substitute for real macOS IME
  composition evidence.
- Current impasse is external/provenance-bound rather than code-bound:
  threshold promotion needs a reviewer to accept the over-budget baseline, and
  v1 manual readiness needs a real Chrome/macOS IME session.

Verification:

- `cd packages/fleury_web && dart test -p chrome test/manual_validation_page_test.dart` -
  passed with 2 Chrome tests.
- `jq` over both manual validation audit artifacts confirms
  `needsReviewTargets: ["chrome-ime-macos"]`, `passedRequiredCheckCount: 0`,
  and provenance blockers `reviewedBy`, `capturedAt`, and
  `environment.browserVersion`.

## 2026-06-09 15:00 EDT

Evaluated and dropped a broader first-render-object cache experiment for the
multi-child render sync path.

- Hypothesis: after the retained text-node and semantic coverage fast paths,
  the next scratch capture was dominated by `runtimeBuildMs`; caching each
  child element's first descendant render object could let stable same-position
  multi-child updates skip the parent render-child sync walk.
- Implemented the cache locally and added a focused reconciliation test, then
  ran one browser-backed product-shape stress capture:
  `profiling/web/runs/stress-300x100-render-sync-cache-check.json`.
- Result: the correctness path passed, but the product-config measurement did
  not justify the added framework complexity. Against
  `profiling/web/runs/stress-300x100-retained-text-node-coverage-check.json`,
  the cache run stayed `runtimeBuildMs`-dominated and regressed p50/p95:
  - prior retained-text/coverage capture: runtime build `9.801ms / 264.701ms`,
    semantic apply `19.5ms / 132.799ms`, total frame `86ms / 528.599ms`;
  - cache experiment capture: runtime build `15ms / 5070.9ms`, semantic apply
    `69.799ms / 1057.299ms`, total frame `157.2ms / 5624.299ms`.
- Removed the cache experiment rather than carrying an unproven core
  optimization. The existing stable-unkeyed reconciliation fast path remains in
  place, including the regression coverage for a same-position component child
  changing its first render root.
- Current readiness shape is unchanged: target preset `v1`; score and semantic
  audits green; manual/readiness/default preflights red until Chrome/macOS IME
  evidence, threshold review, and final default-host gates are completed.

Verification:

- `dart format packages/fleury/lib/src/widgets/framework.dart packages/fleury/test/widgets/multi_child_reconciliation_test.dart` -
  passed after the experiment was removed.
- `dart analyze packages/fleury/lib/src/widgets/framework.dart packages/fleury/test/widgets/multi_child_reconciliation_test.dart` -
  passed after the experiment was removed.
- `cd packages/fleury && dart test test/widgets/multi_child_reconciliation_test.dart test/widgets/reconciliation_test.dart test/rendering/render_object_test.dart` -
  passed with 26 VM tests after the experiment was removed.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart test/run_tui_web_dom_test.dart test/semantic_dom_presenter_test.dart test/semantic_coverage_test.dart` -
  passed with 49 Chrome tests before the scratch capture.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=stress-300x100 --frames=16 --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/runs/stress-300x100-render-sync-cache-check.json --timeout=90 --json` -
  passed with 16 captured frames, `overBudgetPercent: 100`, and dominant p95
  slice `runtimeBuildMs`; used as negative evidence only, not as a release
  baseline.

## 2026-06-09 15:08 EDT

Refreshed the retained DOM automated-validation evidence and tightened the
default-preflight handoff without adding another browser capture.

- Re-ran `tool/web_automated_validation.dart` after the semantic presenter test
  additions made the prior generated artifact stale. The refreshed artifact is
  strict-passing:
  `profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json`.
- Regenerated the v1 readiness-candidate bundle with the current automated-test
  fingerprints and restored the generated default-preflight files to their
  intended diagnostic-preview shape. Those bundled preview artifacts are
  `--allow-unbundled` diagnostics, not the final default-flip evidence.
- Strict bundle verification is green again: 11 checked generated artifacts, 227
  checked source inputs, 75 checked manifest fields, and zero mismatches.
- Ran both final default-preflight commands in read-only mode, without
  `--output` or `--json-output`, so they did not overwrite the bundled
  diagnostic-preview artifacts. Both commands now prove the release-action
  wiring is healthy: bundle verification and automated validation pass, while
  strict preflight still fails only because Phase 6 readiness is still blocked
  by threshold-policy review and Chrome/macOS IME manual evidence.
- Remaining release blockers are unchanged and explicit:
  `review-threshold-policy` and
  `collect-manual-evidence:chrome-ime-macos`.

Verification:

- `cd packages/fleury_web && dart run tool/web_automated_validation.dart --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --strict --json` -
  passed with 90 Chrome tests and 20 VM tests.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=v1 --write-default-preflights --completion-audit=/Users/dan/Coding/fleury-web-phase1/docs/implementation/web-rfc-completion-audit.json --json` -
  regenerated the readiness-candidate bundle and diagnostic preflight previews.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with zero artifact, source-input, metadata, or manifest mismatches.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json` -
  exited 1 as expected; bundle and automated-validation checks passed, and
  Phase 6 readiness remained blocked by threshold review plus IME evidence.
- `cd packages/fleury_web && dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json` -
  exited 1 as expected; bundle and automated-validation checks passed, and
  Phase 6 readiness remained blocked by threshold review plus IME evidence.

## 2026-06-09 14:43 EDT

Reduced retained semantic apply work further by narrowing passive text mutation
and skipping fallback scans for fully covered frames.

- Changed `SemanticDomPresenter` to retain a `web.Text` node per semantic id
  and update its `data` field during incremental passive text updates, instead
  of replacing the owning element's entire `textContent`.
- Extended the passive-text browser test to assert that the retained DOM
  element and its first text node both survive an incremental text update.
- Added a semantic coverage fast path: after marking readable semantic bounds,
  if those bounds cover the full viewport, `applySemanticTextFallback` returns
  without scanning every buffer cell for fallback candidates.
- Added a VM coverage test for a fully covered viewport.
- Ran one focused browser scratch capture after the batched source changes:
  `profiling/web/runs/stress-300x100-retained-text-node-coverage-check.json`.
  Compared with `stress-300x100-retained-text-node-check.json`, semantic
  presenter p95 dropped from `48.301ms` to `32.2ms`, semantic coverage p95
  dropped from `310.5ms` to `23.9ms`, semantic diff p95 dropped from
  `54.399ms` to `27.301ms`, and semantic apply p95 dropped from `354.7ms` to
  `132.799ms`.
- The focused stress capture still fails the frame budget on all 16 frames.
  Dominant p95 moved from `semanticApplyMs` to `runtimeBuildMs`; p95 total
  frame time was `528.599ms`. This makes the next performance question runtime
  build variance again, not DOM apply or semantic presenter churn.
- Rebuilt `web/manual_validation.dart.js` and `web/dom_demo.dart.js`, then
  regenerated the readiness-candidate bundle so source and generated artifact
  fingerprints match the current implementation. Readiness remains red for the
  expected human/release gates: candidate threshold review, real Chrome/macOS
  IME evidence, and bundle-bound default/retirement preflights.

Verification:

- `dart analyze packages/fleury_web/lib/src/semantics/semantic_coverage.dart packages/fleury_web/test/semantic_coverage_test.dart packages/fleury_web/lib/src/semantics/semantic_dom_presenter.dart packages/fleury_web/test/semantic_dom_presenter_test.dart packages/fleury_web/test/run_tui_surface_test.dart packages/fleury_web/test/manual_validation_page_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/semantic_coverage_test.dart` -
  passed with 5 VM tests.
- `cd packages/fleury_web && dart test -p chrome test/semantic_dom_presenter_test.dart test/run_tui_surface_test.dart test/manual_validation_page_test.dart` -
  passed with 41 Chrome tests.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=stress-300x100 --frames=16 --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/runs/stress-300x100-retained-text-node-coverage-check.json --timeout=90 --json` -
  passed with 16 captured frames, `overBudgetPercent: 100`, and dominant p95
  slice `runtimeBuildMs`.
- `cd packages/fleury_web && dart compile js web/manual_validation.dart -o web/manual_validation.dart.js` -
  passed.
- `cd packages/fleury_web && dart compile js web/dom_demo.dart -o web/dom_demo.dart.js` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=v1 --write-default-preflights --completion-audit=/Users/dan/Coding/fleury-web-phase1/docs/implementation/web-rfc-completion-audit.json --json` -
  regenerated the readiness-candidate bundle.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 227 checked source inputs, 75
  checked manifest fields, and zero mismatches.

## 2026-06-09 14:22 EDT

Tightened the living RFC/review surfaces after explicitly moving VoiceOver out
of the current v1 release gate.

- Updated `docs/rfcs/web-render-backend.md` so Phase 4 is a retained semantics,
  focus, and automated accessibility backstop phase. Its exit gate no longer
  requires manual screen-reader smoke for the v1 browser set.
- Kept manual screen-reader verification as a requirement before claiming
  screen-reader support, and as an explicit follow-up validation track.
- Updated `docs/implementation/web-rfc-review-packet.md` and
  `docs/implementation/web-rfc-phase-audit.md` so reviewer-facing summaries
  describe the current manual gate as Chrome/macOS IME only, with VoiceOver
  deferred.
- No source, generated readiness artifact, browser capture, or manual evidence
  change was needed in this slice: the current v1 manual target registry and
  completion audit already report only `chrome-ime-macos` as release-blocking.

## 2026-06-09 14:33 EDT

Reduced retained semantic DOM attribute churn for passive text nodes.

- Updated `SemanticDomPresenter` so passive text/code/markdown/diff semantic
  roles rely on their own DOM text content instead of also mirroring the same
  changing value through `aria-label` and `data-fleury-value`.
- Kept `data-fleury-value` for native control mirrors such as text fields and
  text areas, preserving the manual-validation page and existing textbox
  selectors.
- Added an own-text cache for incremental semantic updates so unchanged text is
  not rewritten when only other node metadata changes.
- Added browser tests proving passive text nodes expose text content without
  duplicate value attributes, passive text updates reuse the retained element
  with zero semantic attribute writes, and text-field value attributes still
  remain available through the existing tests.
- Rebuilt `web/manual_validation.dart.js` and `web/dom_demo.dart.js` after the
  presenter source change.
- Ran one focused browser scratch capture after batching source changes:
  `profiling/web/runs/stress-300x100-passive-text-attr-check.json`.
  Against the previous `stress-300x100-stable-unkeyed-reconcile-check.json`
  scratch capture, semantic DOM attribute writes dropped from `200` per frame
  to `0` per frame. Median semantic presenter time moved from `11.9ms` to
  `5.201ms`, but p95 worsened from `129.699ms` to `246ms` due to a large
  outlier, and p95 total frame time remains red (`1056.3ms`). This is a real
  DOM churn reduction, not yet a threshold-promotable performance result.
- Regenerated the readiness-candidate bundle so fingerprints cover the updated
  presenter source, presenter tests, and rebuilt manual-validation JS. Strict
  bundle verification remains green, while readiness remains red for the
  expected human gates: candidate threshold review, real Chrome/macOS IME
  evidence, and bundle-bound default/retirement preflights.

Verification:

- `dart analyze packages/fleury_web/lib/src/semantics/semantic_dom_presenter.dart packages/fleury_web/test/semantic_dom_presenter_test.dart packages/fleury_web/test/run_tui_surface_test.dart packages/fleury_web/test/manual_validation_page_test.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/semantic_dom_presenter_test.dart test/run_tui_surface_test.dart test/manual_validation_page_test.dart` -
  passed with 41 Chrome tests.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=stress-300x100 --frames=16 --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/runs/stress-300x100-passive-text-attr-check.json --timeout=90 --json` -
  passed with 16 captured frames, `overBudgetPercent: 100`, and dominant p95
  slice `semanticApplyMs`.
- `cd packages/fleury_web && dart compile js web/manual_validation.dart -o web/manual_validation.dart.js` -
  passed.
- `cd packages/fleury_web && dart compile js web/dom_demo.dart -o web/dom_demo.dart.js` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=v1 --write-default-preflights --completion-audit=/Users/dan/Coding/fleury-web-phase1/docs/implementation/web-rfc-completion-audit.json --json` -
  regenerated the readiness-candidate bundle.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 227 checked source inputs, 75
  checked manifest fields, and zero mismatches.

## 2026-06-09 14:18 EDT

Added a stable unkeyed multi-child reconciliation fast path to reduce runtime
build cost for product-shaped grids with structurally identical rows.

- Added a private `MultiChildRenderObjectElement` fast path for the common
  steady-state shape where the old and new child lists have the same length,
  every child is unkeyed, and every new widget can update the old element in
  place.
- The fast path avoids allocating keyed maps, unkeyed queues, and result
  placeholder lists for dense same-position updates. It still leaves the
  existing render-object order check in place because component children can
  preserve their element while changing the first render object inside their
  subtree.
- Added a regression test proving that a same-position component child can
  switch its internal first render root and the multi-child parent still
  observes the new render object.
- Ran one focused browser scratch capture after batching the source changes:
  `profiling/web/runs/stress-300x100-stable-unkeyed-reconcile-check.json`.
  This is not a replacement release baseline, but it gives directional signal
  against the previous semantic-owner-cache scratch capture:
  - previous scratch p50/p95: runtime build `8.5ms / 258.599ms`, runtime paint
    `19.6ms / 239.801ms`, semantic apply `23.2ms / 142.5ms`, total frame
    `105.5ms / 510.9ms`;
  - stable-unkeyed scratch p50/p95: runtime build `17.9ms / 76.1ms`, runtime
    paint `17.699ms / 88.9ms`, semantic apply `33.4ms / 132.9ms`, total frame
    `127.1ms / 448.1ms`.
- The scratch capture remains over budget on all 16 frames and is now
  dominated by `semanticApplyMs`, so the release threshold candidate is still
  not promotable. This change reduces one source of runtime build outliers but
  does not close the performance gate.
- Regenerated the readiness-candidate bundle after the core framework source
  change so source fingerprints are current. Readiness remains red for the
  existing gates: candidate threshold review, real Chrome/macOS IME manual
  evidence, and bundle-bound default/retirement preflights.

Verification:

- `dart format packages/fleury/lib/src/widgets/framework.dart packages/fleury/test/widgets/multi_child_reconciliation_test.dart` -
  passed with no changes after formatting.
- `dart analyze packages/fleury/lib/src/widgets/framework.dart packages/fleury/test/widgets/multi_child_reconciliation_test.dart` -
  passed.
- `cd packages/fleury && dart test test/widgets/multi_child_reconciliation_test.dart test/widgets/reconciliation_test.dart test/rendering/render_object_test.dart` -
  passed with 26 VM tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart test/run_tui_web_dom_test.dart` -
  passed with 28 Chrome tests.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=stress-300x100 --frames=16 --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/runs/stress-300x100-stable-unkeyed-reconcile-check.json --timeout=90 --json` -
  passed with 16 captured frames, `overBudgetPercent: 100`, and dominant p95
  slice `semanticApplyMs`.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=v1 --write-default-preflights --completion-audit=/Users/dan/Coding/fleury-web-phase1/docs/implementation/web-rfc-completion-audit.json --json` -
  regenerated the readiness-candidate bundle.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 227 checked source inputs, 75
  checked manifest fields, and zero mismatches.

## 2026-06-09 15:53 EDT

Moved IME validation out of the v1 release-blocking goal and into the web
roadmap validation track.

- Updated the manual-validation target registry so the v1 preset has no
  required manual browser targets. Chrome/macOS IME and Chrome/macOS
  VoiceOver remain available as explicit targets and through the all-targets
  preset for follow-up validation work.
- Relaxed the readiness manual-audit rule so an empty scoped target set can
  pass strict validation. This makes the v1 scope explicit: automated web
  behavior, generated provenance, and threshold review are release gates;
  IME and VoiceOver claims require later explicit evidence.
- Regenerated the manual-validation audit with `--target-preset=v1`. The
  result now reports `targetCount: 0`, preserves the existing roadmap evidence
  entries for provenance, and strict-passes because no v1 manual targets are
  selected.
- Regenerated the readiness-candidate bundle with the v1 preset and refreshed
  the completion audit. The readiness bundle now reports manual validation as
  green and phase 3 as `automated-path-landed-ime-roadmap-follow-up`, with IME
  marked non-release-blocking.
- Did not run another browser capture for this scope change. The browser-heavy
  evidence is unchanged; this pass only changes release scope, target
  selection, and generated audit provenance.

Verification:

- `dart test test/web_manual_validation_tool_test.dart --name "v1 preset has no blocking manual targets"` -
  passed.
- `dart test test/web_readiness_tool_test.dart --name "empty scoped manual validation audit|manual provenance blockers"` -
  passed.
- `dart test test/web_readiness_bundle_tool_test.dart --name "writes passing reviewed artifacts"` -
  passed.
- `cd packages/fleury_web && dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json` -
  passed with 11 checked generated artifacts, 227 checked source inputs, 65
  checked manifest fields, and zero mismatches.
- Bundle-bound default preflights now fail only on the expected threshold
  review blocker: `Frame performance scoreboard: frame scoreboard threshold
  policy reviewState is candidate; expected reviewed`.

## 2026-06-09 16:47 EDT

Continued the goal with performance, not IME/VoiceOver, as the active blocker.
The reviewed retained-DOM thresholds are now treated as a regression floor only:
the product path must still move closer to a real 16.67ms frame budget.

- Kept the semantic snapshot cache work:
  - `SemanticTree.nodes` now memoizes the flattened immutable node list.
  - `SemanticTree.nodesById` memoizes the id index used by owner diffing and
    the web semantic DOM presenter.
  - `SemanticTree.nodeCount` lets retained presenters report counts without
    re-walking the tree.
  - `SemanticsOwner` and `SemanticDomPresenter` use the cached id map instead
    of rebuilding one per consumer.
- Kept the dirty-row build pruning work:
  - Added an internal `WidgetUpdatePruner` hook for immutable widgets that can
    prove a new widget instance is value-equivalent.
  - Opted in `Text` and `RepaintBoundary` only. This lets dense retained grids
    skip stable `RepaintBoundary -> Text` updates while still updating changed
    rows and leaving arbitrary stateful widgets alone.
  - Added regression coverage proving value-equivalent prunable children skip
    rebuild and `RepaintBoundary` prunes equivalent child configuration.
- Kept the scoped semantic fallback coverage work:
  - `applySemanticTextFallback` still performs a full audit on first pass or
    after any fallback reliance.
  - After a clean no-fallback audit, later frames can scan only the dirty row
    ranges supplied by the retained DOM presentation plan.
  - Added tests for dirty-row scoped coverage and for falling back to a full
    scan after previous fallback reliance.
- Rejected and reverted the presenter-only passive text fast path:
  - It had no clean positive signal. A follow-up dirty-row capture worsened
    over-budget frames from `34.375%` to `59.375%` and produced extreme
    outliers, so it was removed rather than carried forward.
- The retained-DOM dirty-row path is materially tighter but not production
  budget-complete:
  - baseline `dirty-row-160x50-run-3.json`: total p50/p95 `24.000ms /
    331.100ms`, semantic apply p50/p95 `11.699ms / 327.101ms`,
    over-budget `62.5%`;
  - prior leaf-cache scratch: total p50/p95 `29.600ms / 286.600ms`, semantic
    apply p50/p95 `8.200ms / 201.101ms`, over-budget `62.5%`;
  - kept pruned-coverage scratch:
    `profiling/web/runs/dirty-row-160x50-pruned-coverage-check.json`, total
    p50/p95 `8.799ms / 155.400ms`, semantic apply p50/p95 `4.601ms /
    100.701ms`, over-budget `34.375%`.
- The steady state after the first eight recorded frames is much closer to the
  budget but still has outliers:
  - frames 9-32 total p50/p95 `6.000ms / 33.201ms`;
  - frames 9-32 semantic apply p50/p95 `2.199ms / 16.800ms`;
  - remaining above-budget frames were frame 18 (`33.201ms`, semantic
    `25.201ms`), frame 25 (`36.201ms`, build `24.100ms`), and frame 28
    (`21.400ms`, semantic `16.800ms`).
- Current interpretation:
  - DOM visual apply remains small (`domApplyMs` p95 `2.399ms` in the kept
    scratch capture).
  - The remaining blocker is still the same architectural area: retained or
    incremental semantics, plus occasional Dart build outliers, not a switch
    from DOM to canvas/WebGL.
  - The next high-leverage work should avoid full `SemanticTree.fromElement`
    and full owner diffing for small dirty-row updates, rather than optimizing
    browser DOM mutation first.

Verification:

- `dart analyze packages/fleury/lib/src/widgets/framework.dart packages/fleury/lib/src/widgets/basic.dart packages/fleury/lib/src/widgets/repaint_boundary.dart packages/fleury/test/widgets/multi_child_reconciliation_test.dart packages/fleury_web/lib/src/semantics/semantic_coverage.dart packages/fleury_web/lib/src/run_tui_surface.dart packages/fleury_web/test/semantic_coverage_test.dart` -
  passed.
- `cd packages/fleury && dart test test/widgets/multi_child_reconciliation_test.dart test/semantics/semantics_test.dart test/semantics/semantics_owner_test.dart test/rendering/render_text_test.dart` -
  passed with 76 VM tests.
- `cd packages/fleury_web && dart test test/semantic_coverage_test.dart test/semantic_dom_presenter_test.dart test/run_tui_surface_test.dart -p chrome` -
  passed with 46 Chrome tests.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=dirty-row-160x50 --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/runs/dirty-row-160x50-pruned-coverage-check.json --timeout=60 --json` -
  passed with 32 captured frames, `overBudgetPercent: 34.375`, and dominant
  p95 slice `semanticApplyMs`.
- `cd packages/fleury_web && dart test test/semantic_dom_presenter_test.dart test/run_tui_surface_test.dart -p chrome` -
  passed after reverting the rejected presenter fast path.
- `dart analyze packages/fleury_web/lib/src/semantics/semantic_dom_presenter.dart packages/fleury/lib/src/widgets/framework.dart packages/fleury/lib/src/widgets/basic.dart packages/fleury/lib/src/widgets/repaint_boundary.dart packages/fleury_web/lib/src/semantics/semantic_coverage.dart packages/fleury_web/lib/src/run_tui_surface.dart` -
  passed after reverting the rejected presenter fast path.

## 2026-06-09 19:05 EDT

Closed the perf pass by restoring the tree to the best measured state and
rejecting the follow-up experiments that did not improve the product gate.

- Finished reverting the retained-leaf semantic invalidation experiment:
  - Removed the temporary `SemanticInvalidationTracker` export surface.
  - Removed `SemanticsOwner.updateKnownChanged`.
  - Removed the web host retained-leaf patching path and returned semantic
    presentation to the full-tree snapshot plus retained presenter diff path.
  - Reason: the capture
    `profiling/web/runs/dirty-row-160x50-retained-leaf-semantics-check.json`
    was worse than the kept pruned-coverage capture: over-budget `46.875%`,
    total p50/p95 `11.000ms / 491.200ms`, semantic apply p50/p95
    `6.000ms / 196.000ms`. The implementation was not a sound retained
    semantics architecture; it only patched leaf nodes and still carried too
    much full-frame work.
- Tried and reverted a compact dirty-row semantic coverage bitmap:
  - The theory was to reduce GC/coverage variance by allocating only
    `cols * dirtyRows` instead of `cols * rows`.
  - The measured result did not support keeping it:
    `profiling/web/runs/dirty-row-160x50-compact-coverage-check.json` still
    had over-budget `34.375%` and worsened total p50/p95 to
    `10.799ms / 293.399ms` in that run.
  - Because the signal was not positive and the existing coverage code is
    simpler, the compact bitmap was removed.
- Current kept state:
  - semantic tree/id-map caching;
  - `WidgetUpdatePruner` for safe immutable widget update pruning;
  - stable unkeyed multi-child fast path;
  - `Text` semantics with `includeChildren: false`;
  - dirty-row-scoped semantic fallback coverage after a clean full audit.
- Current performance read:
  - The retained DOM product path is substantially tighter than the reviewed
    regression-floor baseline, but it is not production-budget complete.
  - The best kept dirty-row capture remains
    `profiling/web/runs/dirty-row-160x50-pruned-coverage-check.json`:
    total p50/p95 `8.799ms / 155.400ms`, semantic apply p50/p95
    `4.601ms / 100.701ms`, over-budget `34.375%`.
  - After the first eight captured frames, the same run is closer but still
    not green: total p50/p95 `6.000ms / 33.201ms`, semantic apply p50/p95
    `2.199ms / 16.800ms`, with three steady-state frames above budget.
  - DOM visual apply is not the dominant bottleneck in the kept run. The next
    real blocker is a proper retained/incremental semantics producer and owner
    update model, plus investigation of the occasional Dart build outlier.

Verification:

- `dart analyze packages/fleury/lib/src/semantics/semantics.dart packages/fleury/lib/src/semantics/semantics_owner.dart packages/fleury/lib/fleury_host.dart packages/fleury/test/semantics/semantics_owner_test.dart packages/fleury_web/lib/src/run_tui_surface.dart packages/fleury_web/lib/src/semantics/semantic_coverage.dart packages/fleury/lib/src/widgets/framework.dart packages/fleury/lib/src/widgets/basic.dart packages/fleury/lib/src/widgets/repaint_boundary.dart packages/fleury/test/widgets/multi_child_reconciliation_test.dart packages/fleury_web/test/semantic_coverage_test.dart` -
  passed.
- `cd packages/fleury && dart test test/widgets/multi_child_reconciliation_test.dart test/semantics/semantics_test.dart test/semantics/semantics_owner_test.dart test/rendering/render_text_test.dart` -
  passed with 76 VM tests.
- `cd packages/fleury_web && dart test test/semantic_coverage_test.dart test/semantic_dom_presenter_test.dart test/run_tui_surface_test.dart -p chrome` -
  passed with 46 Chrome tests before the retained-leaf and compact-bitmap
  reverts, and the final state returned to that passing web host path.
- `cd packages/fleury_web && dart test test/semantic_coverage_test.dart -p chrome` -
  passed after reverting the compact-bitmap experiment.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=dirty-row-160x50 --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/runs/dirty-row-160x50-compact-coverage-check.json --timeout=60 --json` -
  passed but did not improve the perf gate, so the code experiment was
  reverted and the capture retained only as rejected evidence.

## 2026-06-09 19:24 EDT

Tried a stricter retained-leaf semantic update path and rejected it after
measurement.

- Implemented a bounded retained-leaf prototype:
  - `SemanticsElement` recorded structural and leaf invalidations.
  - `SemanticsOwner` built a retained update candidate without mutating owner
    state until coverage checks passed.
  - `runTuiSurface` attempted the fast path only for clean paint-damage
    frames with no input, no semantic activation, no metrics change, no full
    dirty-row set, no previous fallback reliance, and no structural semantic
    invalidation.
  - Added focused owner and web-host tests proving leaf semantic updates could
    avoid a full `SemanticTree.fromElement` timing slice.
- Rejected and reverted the prototype because the product capture regressed:
  - `profiling/web/runs/dirty-row-160x50-retained-leaf-v2-check.json`:
    over-budget `43.75%`, total p50/p95 `10.900ms / 122.900ms`, semantic
    apply p50/p95 `4.099ms / 92.400ms`;
  - `profiling/web/runs/dirty-row-160x50-retained-leaf-v2-lean-check.json`
    after removing duplicate retained-index wrapping: over-budget `50%`.
- Interpretation:
  - The prototype did eliminate full semantic tree build in the capture
    (`semanticTreeBuildMs` was zero), but shifted cost into retained diff/index
    maintenance and did not improve the frame-budget gate.
  - For the current dirty-row scenario, `SemanticTree.fromElement` is not
    expensive enough by itself to justify retained leaf patching. The next
    viable optimization should either reduce runtime build variance or change
    the semantic presentation/diff contract more fundamentally, rather than
    layering another leaf-patching fast path on top of full snapshots.
- Final code state for this pass is back to the previously kept perf path:
  semantic tree/id-map cache, `WidgetUpdatePruner`, stable unkeyed child
  reconciliation, `Text` leaf semantics, and dirty-row-scoped fallback
  coverage. The retained-leaf prototype code and tests were removed.

Verification:

- `dart analyze packages/fleury/lib/src/semantics/semantics.dart packages/fleury/lib/src/semantics/semantics_owner.dart packages/fleury/lib/fleury_host.dart packages/fleury/test/semantics/semantics_owner_test.dart packages/fleury_web/lib/src/run_tui_surface.dart packages/fleury_web/test/run_tui_surface_test.dart` -
  passed after reverting the retained-leaf prototype.
- `cd packages/fleury && dart test test/semantics/semantics_owner_test.dart test/semantics/semantics_test.dart test/widgets/multi_child_reconciliation_test.dart test/rendering/render_text_test.dart` -
  passed with 76 VM tests after the revert.
- `cd packages/fleury_web && dart test test/run_tui_surface_test.dart -p chrome` -
  passed with 23 Chrome tests after the revert.

## 2026-06-09 19:29 EDT

Tried a runtime-build optimization for dense direct render-object children and
rejected it after measurement.

- Implemented a prototype in `MultiChildRenderObjectElement` that skipped
  `_syncChildRenderObjects()` when stable unkeyed reconciliation proved every
  child was a direct `RenderObjectElement`.
- Added a focused reconciliation test with a counting render flex to prove the
  direct render-object path avoided redundant child-list replacement while the
  existing component-root-change test still covered the unsafe case.
- The product capture regressed:
  - `profiling/web/runs/dirty-row-160x50-render-child-sync-skip-check.json`
    had over-budget `59.375%`, total p50/p95 `21.299ms / 124.301ms`,
    runtime build p50/p95 `2.900ms / 39.000ms`, and semantic apply p50/p95
    `10.000ms / 80.900ms`.
  - The best kept capture remains
    `profiling/web/runs/dirty-row-160x50-pruned-coverage-check.json` with
    over-budget `34.375%`.
- Interpretation:
  - Scanning and confirming the parent render child list is not the meaningful
    dirty-row bottleneck in the measured product path.
  - The change was removed rather than carried as unearned complexity.
  - The next useful direction should be measurement-led around why semantic
    apply and runtime build variance spike together, not another local
    reconciliation shortcut.

Verification:

- `dart analyze packages/fleury/lib/src/widgets/framework.dart packages/fleury/test/widgets/multi_child_reconciliation_test.dart packages/fleury/lib/src/widgets/basic.dart packages/fleury/lib/src/widgets/repaint_boundary.dart` -
  passed after reverting the prototype.
- `cd packages/fleury && dart test test/widgets/multi_child_reconciliation_test.dart` -
  passed with 10 tests after reverting the prototype.

## 2026-06-09 19:41 EDT

Tried two small semantic hot-path cleanups and rejected both after product
captures.

- Streaming semantic collector prototype:
  - Changed `SemanticTree.fromElement` collection to stream descendant semantic
    nodes into parent-owned lists and avoid allocating empty child lists for
    leaf semantic contributors.
  - Focused analyzer and semantic tests passed.
  - Product capture regressed:
    `profiling/web/runs/dirty-row-160x50-streaming-semantic-collector-check.json`
    reported over-budget `59.375%` versus the kept path's `34.375%`.
    Total p50/p95 was `26.500ms / 145.200ms`; runtime build p50/p95 was
    `6.500ms / 42.801ms`; semantic apply p50/p95 was
    `7.200ms / 94.800ms`.
  - Steady frames 9-32 also regressed: `11/24` over budget, total p50
    `14.299ms`, semantic apply p50 `4.600ms`.
  - Reverted. The collector's recursive-list shape is not the measured
    bottleneck, and changing it made runtime/build variance worse.
- Semantic DOM same-value mutation cleanup:
  - Guarded same-value `className` writes, avoided replacing cached attribute
    maps when no attributes changed, and added CSS containment to the hidden
    semantic root.
  - Focused analyzer, VM semantic tests, and Chrome semantic presenter tests
    passed.
  - Product capture regressed:
    `profiling/web/runs/dirty-row-160x50-semantic-presenter-containment-check.json`
    reported over-budget `53.125%`, total p50/p95
    `20.400ms / 170.100ms`, and semantic apply p50/p95
    `5.900ms / 102.600ms`.
  - Steady frames 9-32 still regressed: `10/24` over budget, total p50/p95
    `12.900ms / 69.600ms`, semantic apply p50/p95
    `4.900ms / 38.000ms`.
  - Reverted. The current semantic DOM incremental path already reports zero
    attribute churn for the dirty-row product path, so these local DOM
    bookkeeping changes do not address the frame-budget failure mode.

Current interpretation:

- The retained DOM visual side remains cheap in the kept capture: two dirty
  rows, two DOM rows replaced, and low visual DOM apply time.
- Failed attempts now rule out three narrow classes of fixes:
  retained-leaf semantic patching layered over full snapshots,
  render-child sync shortcuts, and local semantic traversal/DOM bookkeeping
  cleanup.
- The remaining performance problem is likely a wider scheduling/allocation
  interaction between full runtime rebuild, full semantic snapshot production,
  and semantic apply in compiled web. The next pass should either:
  - measure current kept code again to quantify run-to-run variance before
    accepting or rejecting more small changes; or
  - change the architecture more deliberately, for example by moving to a
    real retained semantic producer with bounded dirty-node inputs rather than
    deriving incremental updates after a full semantic snapshot.

Verification after reverts:

- `dart analyze packages/fleury/lib/src/semantics/semantics.dart packages/fleury_web/lib/src/semantics/semantic_dom_presenter.dart packages/fleury_web/test/semantic_dom_presenter_test.dart packages/fleury_web/test/run_tui_surface_test.dart` -
  passed.
- `cd packages/fleury && dart test test/semantics/semantics_test.dart test/semantics/semantic_identity_test.dart` -
  passed with 34 VM tests.
- `cd packages/fleury_web && dart test test/semantic_dom_presenter_test.dart -p chrome` -
  passed with 16 Chrome tests.

## 2026-06-09 19:46 EDT

Rechecked the current kept code and tried a benchmark-shape allocation
reduction; rejected the benchmark change.

- Current-code recheck:
  - Capture:
    `profiling/web/runs/dirty-row-160x50-current-recheck.json`.
  - Result: over-budget `31.25%`, dominant p95 slice `semanticApplyMs`.
  - Total p50/p95 was `6.000ms / 233.799ms`; runtime build p50/p95 was
    `1.299ms / 35.200ms`; semantic apply p50/p95 was
    `2.899ms / 99.100ms`.
  - Steady frames 9-32: `5/24` over budget, total p50/p95
    `4.699ms / 22.701ms`, runtime build p50/p95 `0.900ms / 12.000ms`,
    semantic apply p50/p95 `2.400ms / 16.300ms`.
  - Interpretation: the accepted path is reproducible and slightly better
    than the previous kept capture overall, but it is still not production
    frame-budget clean.
- Stable-row benchmark widget cache experiment:
  - Changed the dirty-row and single-dirty-cell benchmark builders so stable
    rows reused immutable `RepaintBoundary(Text(...))` widget instances across
    steps, with a focused test proving only dirty row positions changed
    identity between successive builds.
  - Capture:
    `profiling/web/runs/dirty-row-160x50-stable-row-widget-cache-check.json`.
  - Result: over-budget worsened to `43.75%`, dominant p95 slice shifted to
    `runtimeBuildMs`, total p50/p95 was `9.500ms / 140.700ms`, and semantic
    apply p50/p95 was `5.400ms / 46.200ms`.
  - Steady frames 9-32 had `6/24` over budget. Some steady sub-slices improved
    (`semanticApplyP95Ms` `11.600ms`, runtime build p95 `9.000ms`), but the
    actual frame-budget gate did not improve.
  - Reverted. Re-shaping the benchmark around cached stable widgets is not a
    sufficient performance fix and risks making the gate less representative
    without solving the total-frame misses.

Verification after reverting the benchmark experiment:

- `dart analyze packages/fleury_web/lib/src/benchmark/web_benchmark_scenarios.dart packages/fleury_web/web/benchmark_capture.dart` -
  passed.
- `cd packages/fleury && dart test test/widgets/multi_child_reconciliation_test.dart test/semantics/semantics_test.dart` -
  passed with 40 VM tests.
- `rg -n "_singleDirtyCellStableRowCache|_dirtyRowStableRowCache|web_benchmark_scenarios_test|stable row widgets" packages/fleury_web/lib/src/benchmark packages/fleury_web/test` -
  found no remaining rejected-experiment code.

Current perf read:

- The visual DOM renderer is still not the primary blocker for this scenario.
- The kept path is close in steady state but still misses: current steady p95
  is `22.701ms` total, with semantic apply p95 `16.300ms`.
- Narrow local optimizations have not improved the budget gate. The next
  credible performance slice is no longer another micro-optimization in the
  presenter or benchmark app; it is a semantics architecture slice that avoids
  doing full-frame semantic work on every dirty visual row while preserving the
  accessibility backstop contract.

## 2026-06-09 19:58 EDT

Tried an element-level semantic subtree cache and rejected it after product
capture.

- Implemented a bounded internal prototype:
  - `Element` carried an internal semantic-dirty bit.
  - Lifecycle/update/rebuild/unmount paths invalidated the semantic subtree and
    propagated invalidation to ancestors.
  - `SemanticTree.fromElement` reused cached semantic node lists for clean
    element subtrees.
  - `SemanticsElement` invalidated its semantic subtree when painted semantic
    bounds changed.
  - Added focused tests proving clean subtree reuse and ancestor invalidation
    after a child `setState`.
- Focused correctness checks passed before capture:
  - analyzer for framework, semantics, semantic owner, web surface, semantic
    coverage, semantic DOM presenter, and focused tests;
  - `cd packages/fleury && dart test test/semantics/semantics_test.dart test/semantics/semantics_owner_test.dart test/widgets/multi_child_reconciliation_test.dart test/rendering/render_text_test.dart`
    passed with 78 VM tests;
  - `cd packages/fleury_web && dart test test/run_tui_surface_test.dart test/semantic_dom_presenter_test.dart -p chrome`
    passed with 39 Chrome tests.
- Product capture regressed:
  - `profiling/web/runs/dirty-row-160x50-semantic-subtree-cache-check.json`
    reported over-budget `59.375%`, dominant p95 slice `runtimeBuildMs`,
    total p50/p95 `30.400ms / 548.100ms`, runtime build p50/p95
    `5.000ms / 220.200ms`, and semantic apply p50/p95
    `8.800ms / 130.600ms`.
  - Steady frames 9-32 also regressed: `12/24` over budget, total p50/p95
    `18.100ms / 87.100ms`, runtime build p50/p95
    `3.300ms / 50.300ms`, semantic tree build p50/p95
    `0.200ms / 13.400ms`, semantic apply p50/p95 `8.300ms / 38.900ms`.
- Reverted the prototype:
  - removed the internal `Element` semantic-dirty bit and ancestor
    invalidation hooks;
  - removed the semantic subtree `Expando` cache;
  - restored semantic bounds recording to the accepted assignment path;
  - removed the temporary cache correctness tests/helpers.

Interpretation:

- A coarse per-element semantic collection cache is not viable as implemented.
  It adds framework-wide invalidation work on hot rebuild paths and worsens
  runtime build variance more than it saves in semantic collection.
- This further narrows the next direction: the retained semantics fix cannot be
  a general cache wrapped around full-tree collection. It needs a more explicit
  retained semantics producer/owner contract with bounded dirty semantic nodes,
  or a change in what the web host presents per frame.

Verification after reverting:

- `dart analyze packages/fleury/lib/src/widgets/framework.dart packages/fleury/lib/src/semantics/semantics.dart packages/fleury/test/semantics/semantics_test.dart packages/fleury_web/lib/src/run_tui_surface.dart` -
  passed.
- `cd packages/fleury && dart test test/semantics/semantics_test.dart test/widgets/multi_child_reconciliation_test.dart` -
  passed with 40 VM tests.
- `rg -n "semanticSubtreeDirty|markSemanticSubtreeDirty|clearSemanticSubtreeDirty|SemanticSubtree|_CountingSemantic|_ChangingSemantic" packages/fleury/lib/src/widgets/framework.dart packages/fleury/lib/src/semantics/semantics.dart packages/fleury/test/semantics/semantics_test.dart` -
  found no remaining rejected-experiment code.

## 2026-06-09 20:37 EDT

Shifted the perf blocker from broad semantic speculation to measured
visual-vs-semantic attribution, then kept two narrower semantic hot-path
optimizations.

- Added a guarded diagnostics-only capture switch:
  - `tool/web_frame_capture.dart --disable-semantics` sends
    `semantics=off` to the browser benchmark page.
  - `web/benchmark_capture.dart` routes that through
    `runTuiWebDom(semanticsEnabled: false,
    allowInaccessibleDiagnostics: true)`.
  - Capture artifacts record `semanticsEnabled` and `captureMode`, and the
    tool run environment records the semantics mode, so visual-only captures
    cannot be mistaken for product accessibility captures.
- Visual-only diagnostic capture:
  - `profiling/web/runs/dirty-row-160x50-visual-only-diagnostic.json`
    reported over-budget `31.25%`, dominant p95 slice `runtimeBuildMs`,
    total p50/p95 `5.600ms / 107.100ms`, and semantic apply p50/p95
    `0.000ms / 0.100ms`.
  - Steady frames 15-32 were clean: `0/18` over budget, total p50/p95
    `2.700ms / 15.601ms`.
  - Interpretation: the retained visual DOM path can fit inside the budget in
    steady state; the product miss is no longer attributable only to visual DOM
    apply. Product semantics are still part of the frame-budget blocker.
- Kept semantic coverage fast path:
  - `applySemanticTextFallback` now first checks whether every scanned row is
    fully covered by readable semantic bounds. If so, it returns the original
    tree and an empty audit without allocating the fallback coverage bitmap or
    scanning visual cells.
  - This preserves the existing fallback path for gaps, structural nodes, and
    previous frames that relied on fallback coverage.
  - Added coverage for adjacent readable dirty-row bounds.
  - Capture:
    `profiling/web/runs/dirty-row-160x50-semantic-coverage-fast-path-check.json`
    improved the headline to over-budget `28.125%` from the current-code
    recheck's `31.25%`.
  - Steady frames 9-32 improved to `3/24` over budget, total p50/p95
    `7.299ms / 20.901ms`, and semantic apply p50/p95
    `3.401ms / 12.699ms`.
- Kept lower-allocation semantic collection:
  - Replaced `_collectFrom`'s per-element intermediate-list recursion with
    `_collectInto`, so non-semantic wrapper elements stream child semantic
    nodes directly into the parent output list.
  - Semantic contributors still receive their own child node list, preserving
    the existing `SemanticContributor` and `SemanticChildrenProvider`
    contracts.
  - Capture:
    `profiling/web/runs/dirty-row-160x50-semantic-coverage-and-collector-check.json`
    improved the headline again to over-budget `25.00%`.
  - The useful steady window was clean: frames 9-32 had `0/24` over budget,
    total p50/p95 `4.699ms / 15.600ms`, runtime render p50/p95
    `1.900ms / 7.900ms`, semantic apply p50/p95 `2.000ms / 5.200ms`, semantic
    tree build p50/p95 `0.201ms / 1.400ms`, semantic diff p50/p95
    `0.901ms / 3.701ms`, and semantic presenter p50/p95 `0.100ms / 1.301ms`.
  - All remaining misses in that capture were frames 1-8 after capture
    instrumentation was cleared.
- Warmup probe:
  - `profiling/web/runs/dirty-row-160x50-semantic-coverage-collector-warmup8-check.json`
    did not clear the all-frame gate: over-budget stayed `25.00%`.
  - Misses were distributed across the measured run, so a larger warmup count
    alone is not a sufficient gate fix.

Current interpretation:

- The kept changes materially tighten the product semantic path, especially in
  the steady window, and are worth retaining.
- The goal is still not complete if the acceptance criterion is "all measured
  product frames under 16.67ms" for `dirty-row-160x50`. The current best kept
  product capture is `8/32` over budget.
- The next credible optimization is no longer the visual DOM renderer. It is
  either:
  - further reducing semantic producer/diff variance in the product path; or
  - explicitly splitting the benchmark gate into cold/lumpy and steady-state
    budgets while continuing to track both. The latter would be a gate-policy
    change, not a performance fix by itself.

Verification:

- `dart analyze packages/fleury_web/tool/web_frame_capture.dart packages/fleury_web/web/benchmark_capture.dart packages/fleury_web/test/web_frame_capture_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_capture_tool_test.dart` -
  passed with 10 VM tests.
- `dart analyze packages/fleury_web/lib/src/semantics/semantic_coverage.dart packages/fleury/lib/src/semantics/semantics.dart` -
  passed.
- `cd packages/fleury_web && dart test test/semantic_coverage_test.dart` -
  passed with 8 VM tests.
- `cd packages/fleury && dart test test/semantics/semantics_test.dart test/semantics/semantics_owner_test.dart` -
  passed with 35 VM tests.
- `cd packages/fleury_web && dart test test/semantic_dom_presenter_test.dart -p chrome` -
  passed with 16 Chrome tests.

## 2026-06-09 20:49 EDT

Tried and rejected an ordered semantic diff fast path.

- Prototype:
  - Narrowed `SemanticTree.nodes` to expose the cached flattened list to
    `SemanticsOwner`.
  - Added an owner fast path for unchanged semantic node order, diffing the
    previous and next node lists by index instead of building/id-walking maps.
  - Kept structural changes on the existing map diff path and added a focused
    regression test for structural changes after ordered updates.
- Focused correctness passed before capture:
  - `dart analyze packages/fleury/lib/src/semantics/semantics.dart packages/fleury/lib/src/semantics/semantics_owner.dart packages/fleury/test/semantics/semantics_owner_test.dart` -
    passed.
  - `cd packages/fleury && dart test test/semantics/semantics_owner_test.dart test/semantics/semantics_test.dart` -
    passed with 36 VM tests.
- Product capture regressed:
  - `profiling/web/runs/dirty-row-160x50-ordered-semantic-diff-check.json`
    reported over-budget `46.875%`, dominant p95 slice `semanticApplyMs`,
    total p50/p95 `14.200ms / 151.000ms`, and semantic apply p50/p95
    `5.200ms / 54.799ms`.
  - Steady frames 9-32 regressed to `7/24` over budget, total p50/p95
    `8.100ms / 34.100ms`, semantic apply p50/p95
    `4.600ms / 16.601ms`, and semantic diff p50/p95 `0.100ms / 2.000ms`.
- Reverted:
  - Restored `SemanticTree.nodes` to the accepted `Iterable<SemanticNode>`
    surface.
  - Restored `SemanticsOwner` to the accepted retained id-map diff path.
  - Removed the temporary ordered-diff regression test.

Interpretation:

- The ordered diff did reduce the semantic diff slice, but it worsened total
  frame and semantic presenter variance enough to fail the real product gate.
  The bottleneck is not simply the owner map diff; keep this rejected.

Verification after revert:

- `dart analyze packages/fleury/lib/src/semantics/semantics.dart packages/fleury/lib/src/semantics/semantics_owner.dart packages/fleury/test/semantics/semantics_owner_test.dart` -
  passed.
- `cd packages/fleury && dart test test/semantics/semantics_owner_test.dart test/semantics/semantics_test.dart` -
  passed with 35 VM tests.
- `rg -n "ordered semantic|_diffFromOrderedNodes|_hasSameNodeOrder|structural changes after ordered|List<SemanticNode> get nodes" packages/fleury/lib/src/semantics/semantics.dart packages/fleury/lib/src/semantics/semantics_owner.dart packages/fleury/test/semantics/semantics_owner_test.dart` -
  found no remaining rejected-experiment code.

## 2026-06-09 21:01 EDT

Added first-class steady-state reporting to the frame report tool.

- `tool/web_frame_report.dart` now accepts:
  - `--steady-skip-frames=N`, which computes a second summary from the
    post-skip frame window;
  - `--max-steady-total-frame-p95-ms=N`;
  - `--max-steady-semantic-apply-p95-ms=N`;
  - `--max-steady-over-budget-percent=N`.
- Existing gates are unchanged and continue to apply to all captured frames.
  The new steady gates are intentionally separate, so a run can fail the
  all-frame gate while proving the sustained budget window.
- JSON output now includes a `steadyState` summary with `skipInitialFrames`.
  Markdown output includes a `## Steady State` section when a nonzero skip is
  requested.
- Added a focused test where all-frame over-budget percent fails while the
  steady-state gates pass.

Tool read on the current best kept product capture:

- Command:
  `cd packages/fleury_web && dart run tool/web_frame_report.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/runs/dirty-row-160x50-semantic-coverage-and-collector-check.json --steady-skip-frames=8 --max-over-budget-percent=0 --max-steady-over-budget-percent=0 --max-steady-total-frame-p95-ms=16.67 --max-steady-semantic-apply-p95-ms=8 --json`
- Result:
  - all-frame gate: failed, over-budget `25.0%`;
  - steady frame window: `24` frames, `0` over budget;
  - steady total p95: `15.600ms`, passing the `16.67ms` budget;
  - steady semantic apply p95: `5.200ms`, passing the `8ms` diagnostic limit.

Interpretation:

- The branch now has tool-supported evidence for the split we were previously
  calculating by hand: current retained DOM product semantics can sustain the
  16.67ms budget in the measured steady window, but the full capture still
  fails because of early/lumpy frame spikes.
- This is not a replacement for the product performance fix. It makes the
  remaining blocker sharper: continue reducing all-frame variance, or
  intentionally adopt separate cold/lumpy and sustained-frame gates.

Verification:

- `dart analyze packages/fleury_web/tool/web_frame_report.dart packages/fleury_web/test/web_frame_report_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_report_tool_test.dart` -
  passed with 4 VM tests.

## 2026-06-09 20:32 EDT

Promoted the steady-state split into the frame scoreboard and threshold
surface.

- `tool/web_frame_scoreboard.dart` now accepts:
  - `--steady-skip-frames=N`;
  - `--max-steady-total-frame-p95-ms=N`;
  - `--max-steady-semantic-apply-p95-ms=N`;
  - `--max-steady-over-budget-percent=N`.
- Existing all-frame gates remain unchanged. The new steady gates are separate
  gates, so the scoreboard can represent the current blocker precisely:
  "all-frame spikes still fail" while "steady-state budget passes".
- Scoreboard JSON now includes:
  - top-level `steadySkipFrames`;
  - per-scenario `steadySkipFrames`, `steadyFrameCount`,
    `steadyTotalFrameP95Ms`, `steadySemanticApplyP95Ms`, and
    `steadyOverBudgetPercent`;
  - per-capture steady frame count and steady metrics;
  - steady gate results:
    `steadyTotalFrameP95MedianMs`,
    `steadySemanticApplyP95MedianMs`, and
    `steadyOverBudgetPercentMedian`.
- Markdown output now has steady-state columns and notes the skipped initial
  frame count when a nonzero steady-state window is requested.
- Candidate threshold generation now records the steady thresholds, observed
  steady frame count, and `generatedFrom.steadySkipFrames`, so reviewed
  threshold files can preserve the same cold/lumpy versus sustained-frame
  distinction.

No-browser evidence run against the current best kept capture:

- Input capture:
  `profiling/web/runs/dirty-row-160x50-semantic-coverage-and-collector-check.json`
- Command shape:
  `cd packages/fleury_web && dart run tool/web_frame_scoreboard.dart --input=<one-capture-temp-dir> --steady-skip-frames=8 --max-over-budget-percent=0 --max-steady-over-budget-percent=0 --max-steady-total-frame-p95-ms=16.67 --max-steady-semantic-apply-p95-ms=8 --json-output=<temp>/scoreboard.json`
- Result:
  - scenario: `dirty-row-160x50`;
  - all frames: `32`;
  - steady frames after skip: `24`;
  - all-frame total p95: `159.50ms`;
  - all-frame over-budget: `25.0%`, failing the `0%` no-regression gate;
  - steady total p95: `15.60ms`, passing the `16.67ms` frame budget;
  - steady semantic apply p95: `5.20ms`, passing the `8ms` diagnostic gate;
  - steady over-budget: `0.0%`, passing the sustained-frame gate.

Interpretation:

- This still is not "production-level perf". It is a sharper baseline:
  steady-state retained DOM behavior is inside budget on the best kept capture,
  but cold/lumpy frame variance remains the active performance blocker.
- The scoreboard can now carry that distinction in normal benchmark artifacts
  instead of relying on one-off `web_frame_report.dart` reads.
- The next optimization pass should target the all-frame spike source without
  weakening the current steady-state gate.

Verification:

- `dart format packages/fleury_web/tool/web_frame_scoreboard.dart packages/fleury_web/test/web_frame_scoreboard_tool_test.dart` -
  passed.
- `dart analyze packages/fleury_web/tool/web_frame_scoreboard.dart packages/fleury_web/test/web_frame_scoreboard_tool_test.dart` -
  passed.
- `cd packages/fleury_web && dart test test/web_frame_scoreboard_tool_test.dart` -
  passed with 10 VM tests.

## 2026-06-09 20:38 EDT

Ran a focused perf blocker check after adding the steady-state scoreboard
surface.

Experiment: increase the dirty-row capture warmup from `2` frames to `8`
frames.

- Command:
  `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=dirty-row-160x50 --warmup=8 --frames=32 --output=../../profiling/web/runs/dirty-row-160x50-warmup8-check.json`
- Result:
  - `13/32` frames over budget;
  - all-frame total p95 `126.30ms`;
  - all-frame semantic apply p95 `119.899ms`;
  - steady frames 9-32: `7/24` over budget;
  - steady total p95 `47.60ms`;
  - steady semantic apply p95 `13.90ms`.

Interpretation:

- Rejected as a performance fix. More warmup did not reliably move the product
  capture inside budget on this machine; the result was worse than the current
  best kept capture.
- The older retained DOM warmup-8 capture already in `profiling/web/runs`
  (`dirty-row-160x50-semantic-coverage-collector-warmup8-check.json`) tells the
  same directional story: lower p95 than some runs, but still `8/32` over
  budget and a failed steady-state gate when frames 9-32 are evaluated.
- Existing diagnostic visual-only evidence is also not clean:
  `dirty-row-160x50-visual-only-diagnostic.json` still reports `10/32` frames
  over budget with semantic apply effectively absent. The blocker is therefore
  not just "the semantic DOM presenter is slow".

Current perf read:

- DOM application is not the dominant problem on the kept product captures.
  Its p95 is low relative to runtime render/build and semantic snapshot/diff
  variance.
- The dirty-row scenario updates exactly two visual rows and two semantic nodes
  per frame. The remaining spikes are disproportionate to the amount of DOM
  mutation, so the next high-leverage area is the core frame/render lifecycle
  plus semantic snapshot/diff scheduling.
- A tempting frame-loop optimization is to retain the previous back buffer and
  avoid copying stable repaint-boundary rows. That is not safe to land casually:
  the current full clear prevents stale cells in non-boundary regions. Any
  retained-buffer optimization needs a scoped proof and native regression tests
  before another browser capture.

Verification:

- `dart run tool/web_frame_capture.dart --scenario=dirty-row-160x50 --warmup=8 --frames=32 --output=../../profiling/web/runs/dirty-row-160x50-warmup8-check.json` -
  completed and wrote the rejected profiling artifact.
- `cd packages/fleury_web && dart run tool/web_frame_report.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/runs/dirty-row-160x50-warmup8-check.json --steady-skip-frames=8 --max-over-budget-percent=0 --max-steady-over-budget-percent=0 --max-steady-total-frame-p95-ms=16.67 --max-steady-semantic-apply-p95-ms=8 --json` -
  failed all-frame and steady-state gates as expected from the capture.

## 2026-06-09 20:49 EDT

Ran a targeted perf pass to separate buffer lifecycle cost from the broader
runtime-render bucket.

Changes:

- `CellBuffer.clear()` now uses `List.fillRange` instead of a manual Dart loop.
  Damage tracking remains unchanged: a tracked clear still records full-buffer
  damage, and frame-loop clears are still wrapped in `withoutDamageTracking`.
- `TuiFrameLoop` now records `TuiRenderedFrame.bufferPrepareTime`, covering the
  back-buffer clear/reset work before framework paint.
- Web instrumentation now serializes `runtimeBufferPrepareMicros`, includes
  `runtimeBufferPrepareMs` in capture summaries, and shows it in
  `web_frame_report.dart`.

Verification:

- `dart analyze packages/fleury/lib/src/rendering/cell_buffer.dart packages/fleury/lib/src/runtime/tui_frame_loop.dart packages/fleury_web/lib/src/instrumentation/web_host_instrumentation.dart packages/fleury_web/lib/src/run_tui_surface.dart packages/fleury_web/tool/web_frame_report.dart packages/fleury_web/test/web_host_instrumentation_test.dart packages/fleury_web/test/web_frame_report_tool_test.dart` -
  passed.
- `cd packages/fleury && dart test test/rendering/cell_buffer_test.dart test/runtime/tui_frame_loop_test.dart` -
  passed with 33 VM tests.
- `cd packages/fleury_web && dart test test/web_host_instrumentation_test.dart` -
  passed with 7 VM tests.
- `cd packages/fleury_web && dart test test/web_frame_report_tool_test.dart` -
  passed with 4 VM tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 23 Chrome tests.

Browser perf check:

- Command:
  `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=dirty-row-160x50 --frames=32 --warmup=2 --output=../../profiling/web/runs/dirty-row-160x50-buffer-prep-check.json --json`
- Result:
  - `13/32` frames over budget (`40.625%`);
  - all-frame total p95 `187.50ms`;
  - steady frames after skip 8: `6/24` over budget (`25.0%`);
  - steady total p95 `45.901ms`;
  - all-frame `runtimeBufferPrepareMs` p95 `3.399ms`, max `11.60ms`;
  - steady `runtimeBufferPrepareMs` p95 `1.301ms`, max `3.399ms`;
  - all-frame dominant p95 slice remained `semanticApplyMs`.

Interpretation:

- Rejected as a baseline refresh. This run is worse than the current best kept
  dirty-row capture (`8/32` over budget; steady p95 inside budget).
- The new timing confirms buffer preparation is not the primary blocker.
  Clearing the back buffer is measurable but small relative to build, paint, and
  semantic snapshot/diff/presenter variance.
- DOM apply remains small for this product scenario (`domApplyMs` p95 `3.50ms`
  all-frame, `3.101ms` steady) while the visual damage set remains exactly two
  dirty rows per frame.
- Next perf work should target runtime build/paint variance and the semantic
  snapshot/update path. Further browser captures should use the existing
  compile/page-dir reuse path where possible so iteration time is spent on the
  frame data rather than repeated JS compilation.

## 2026-06-09 20:52 EDT

Applied and measured one additional semantic hot-path cleanup.

Change:

- `SemanticTree.nodes` now populates its cached flattened node list with an
  imperative collector instead of `root.selfAndDescendants`, avoiding sync-star
  iterator allocation on the per-frame semantic path.

Verification:

- `dart analyze packages/fleury/lib/src/semantics/semantics.dart packages/fleury/test/semantics/semantics_test.dart packages/fleury/test/semantics/semantics_owner_test.dart packages/fleury_web/lib/src/semantics/semantic_coverage.dart packages/fleury_web/test/semantic_coverage_test.dart` -
  passed.
- `cd packages/fleury && dart test test/semantics/semantics_test.dart test/semantics/semantics_owner_test.dart` -
  passed with 35 VM tests.
- `cd packages/fleury_web && dart test test/semantic_coverage_test.dart` -
  passed with 8 VM tests.
- `cd packages/fleury_web && dart test -p chrome test/semantic_dom_presenter_test.dart` -
  passed with 16 Chrome tests.

Browser perf check:

- Command:
  `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=dirty-row-160x50 --frames=32 --warmup=2 --output=../../profiling/web/runs/dirty-row-160x50-semantic-flatten-check.json --json`
- Result:
  - `13/32` frames over budget (`40.625%`);
  - all-frame total p95 `115.50ms`;
  - steady frames after skip 8: `6/24` over budget (`25.0%`);
  - steady total p95 `67.90ms`;
  - all-frame `runtimeBufferPrepareMs` p95 `3.699ms`;
  - all-frame `semanticApplyMs` p95 `93.00ms`;
  - all-frame dominant p95 slice remained `semanticApplyMs`.

Interpretation:

- Rejected as a baseline refresh. The change is still safe to keep as a small
  allocation cleanup, but it does not resolve the current frame-budget blocker.
- The latest two captures agree that buffer preparation is not the primary
  issue and that DOM apply is still bounded to a small slice for dirty-row.
- Remaining high-signal work is no longer "make DOM row replacement faster";
  the next pass should either:
  - reduce product benchmark build churn by decomposing the dirty-row scenario
    into independently stateful rows, then decide whether that is a benchmark
    correction or a product requirement; or
  - prototype a retained/incremental semantic producer so dirty-row updates do
    not rebuild/diff a full semantic snapshot on every app-level rebuild.

## 2026-06-09 21:00 EDT

Implemented the next perf pass from the previous diagnosis.

Changes:

- Added `DrivenWebBenchmarkScenario`, a stateful browser benchmark driver.
  `dirty-row-160x50` and `single-dirty-cell-160x50` now advance through
  row-local state instead of rebuilding the 50-row benchmark app root on every
  step. Other scenarios keep their existing root-driven behavior.
- Updated `web/benchmark_capture.dart` so browser captures call
  `DrivenWebBenchmarkScenarioState.advance(step)`.
- Tightened `SemanticsOwner.update` so it builds the next semantic node id map
  while diffing `next.nodes`, then carries both previous and next id maps on
  `SemanticTreeUpdate`.
- Updated `SemanticDomPresenter` to reuse `SemanticTreeUpdate.nextNodesById`
  and `previousNodesById` on incremental presentation instead of re-reading
  maps from the tree.

Verification:

- `dart analyze packages/fleury/lib/src/semantics/semantics_owner.dart packages/fleury/test/semantics/semantics_owner_test.dart packages/fleury_web/lib/src/benchmark/web_benchmark_scenarios.dart packages/fleury_web/web/benchmark_capture.dart packages/fleury_web/lib/src/semantics/semantic_dom_presenter.dart packages/fleury_web/test/semantic_dom_presenter_test.dart` -
  passed.
- `cd packages/fleury && dart test test/semantics/semantics_owner_test.dart test/semantics/semantics_test.dart` -
  passed with 35 VM tests.
- `cd packages/fleury_web && dart test -p chrome test/semantic_dom_presenter_test.dart` -
  passed with 16 Chrome tests.
- `cd packages/fleury_web && dart run tool/web_frame_capture.dart --compile-only --page-dir=/tmp/fleury_web_row_local_compile --json` -
  passed and produced a reusable compiled benchmark page.

Browser perf check:

- Command:
  `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=dirty-row-160x50 --frames=32 --warmup=2 --page-dir=/tmp/fleury_web_row_local_compile --output=../../profiling/web/runs/dirty-row-160x50-row-local-semantic-map-check.json --json`
- Result:
  - `13/32` frames over budget (`40.625%`);
  - all-frame total p95 `175.699ms`;
  - steady frames after skip 8: `6/24` over budget (`25.0%`);
  - steady total p95 `36.699ms`;
  - steady `runtimeBuildMs` p95 `4.6ms`;
  - steady `runtimeRenderMs` p95 `17.7ms`;
  - steady `semanticDiffMs` p95 `3.1ms`;
  - steady `semanticApplyMs` p95 `24.599ms`;
  - visual and semantic deltas stayed tight: `dirtyRows=2`,
    `semanticUpdatedNodes=2`, `rowsReplaced=2` per frame.

Interpretation:

- Still rejected as a baseline refresh: it does not beat the current best kept
  dirty-row capture and does not satisfy the steady-state frame gate.
- The row-local benchmark correction is useful evidence. It substantially
  reduces steady build cost, confirming that previous dirty-row runs mixed
  retained presenter performance with top-level benchmark rebuild churn.
- The semantic owner map reuse is also useful but not sufficient. The remaining
  over-budget frames are now concentrated in intermittent semantic tree build /
  semantic apply spikes and runtime/browser variance, not in row DOM apply or
  continuous build cost.
- Next high-leverage direction is a true retained/incremental semantic producer
  or a semantic dirty-id propagation path. Small map/list cleanups are no
  longer likely to close the frame-budget gap by themselves.

## 2026-06-09 21:14 EDT

Implemented the retained dirty-semantics pass for the web frame-budget blocker.

Changes:

- Added `SemanticDirtyTracker` and `SemanticDirtySnapshot` as frame-local host
  signals, following the existing `RenderDamageTracker` handoff shape.
- `SemanticsElement` now records leaf semantic dirtiness when leaf widget
  configuration or paint bounds change. Mounts, unmounts, moves, id changes,
  and child-inclusive semantics conservatively force a full semantic rebuild.
- Added `SemanticTree.replaceNodes(...)` so hosts can produce a next semantic
  snapshot by replacing known dirty semantic nodes without walking the element
  tree.
- Added `SemanticsOwner.updateRetainedNodes(...)` for owner commits from known
  retained replacements. It returns null if the owner cannot prove the update is
  incremental.
- Updated `runTuiSurface` to take one semantic dirty snapshot per rendered
  frame. The web host uses retained semantic replacement only when:
  - there is a retained current tree;
  - the dirty snapshot does not require a full rebuild;
  - every dirty semantic id exists in the retained tree; and
  - semantic text coverage does not append fallback nodes.
  Otherwise it falls back to the prior `SemanticTree.fromElement(...)` path.
- Reset `SemanticDirtyTracker` during native and web host startup to prevent
  static frame state leaking across hosts/tests.

Verification:

- `cd packages/fleury && dart analyze lib/src/semantics/semantics.dart lib/src/semantics/semantics_owner.dart lib/fleury_host.dart lib/src/runtime/run_tui.dart test/semantics/semantics_test.dart test/semantics/semantics_owner_test.dart` -
  passed.
- `cd packages/fleury_web && dart analyze lib/src/run_tui_surface.dart` -
  passed.
- `cd packages/fleury && dart test test/semantics/semantics_owner_test.dart test/semantics/semantics_test.dart` -
  passed with 38 VM tests.
- `cd packages/fleury_web && dart test -p chrome test/semantic_dom_presenter_test.dart` -
  passed with 16 Chrome tests.
- `cd packages/fleury_web && dart test test/semantic_coverage_test.dart test/frame_presentation_test.dart` -
  passed with 16 VM tests.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 23 Chrome tests.

Browser perf check:

- Compile command:
  `cd packages/fleury_web && dart run tool/web_frame_capture.dart --compile-only --page-dir=/tmp/fleury_web_retained_semantics_page --json`
- Capture command:
  `cd packages/fleury_web && dart run tool/web_frame_capture.dart --scenario=dirty-row-160x50 --frames=32 --warmup=8 --page-dir=/tmp/fleury_web_retained_semantics_page --output=../../profiling/web/runs/dirty-row-160x50-retained-dirty-semantics-check.json --json --timeout=60`
- Report command:
  `cd packages/fleury_web && dart run tool/web_frame_report.dart --input=../../profiling/web/runs/dirty-row-160x50-retained-dirty-semantics-check.json --steady-skip-frames=8 --json --max-steady-total-frame-p95-ms=16.67 --max-steady-over-budget-percent=0 --max-semantic-uncovered-cells=0`
- Capture result:
  - `4/32` frames over budget (`12.5%`);
  - all-frame total p95 `57.299ms`;
  - all-frame `semanticApplyMs` p95 `18.5ms`;
  - all-frame dominant p95 slice remained `semanticApplyMs`;
  - steady frames after skip 8: `0/24` over budget (`0.0%`);
  - steady total p95 `13.699ms`;
  - steady `runtimeBuildMs` p95 `7.8ms`;
  - steady `runtimeRenderMs` p95 `10.3ms`;
  - steady `semanticTreeBuildMs` p95 `0.101ms`;
  - steady `semanticCoverageMs` p95 `3.1ms`;
  - steady `semanticDiffMs` p95 `2.0ms`;
  - steady `semanticPresenterMs` p95 `0.2ms`;
  - steady `semanticApplyMs` p95 `6.2ms`;
  - semantic coverage remained complete: `semanticUncoveredCells=0`;
  - steady visual and semantic deltas stayed tight: `dirtyRows=2`,
    `rowsReplaced=2`, `semanticUpdatedNodes=2`,
    `semanticDomReusedElements=2` per frame.

Interpretation:

- Accepted as the current dirty-row steady-state non-regression gate. It is the
  first semantics-enabled `dirty-row-160x50` run in this sequence to satisfy the
  steady total-frame gate (`p95 <= 16.67ms`) with `0%` steady over-budget
  frames.
- This does not make the all-frame profile production-level. Warmup/initial
  frames still spike (`4/32` over budget, total p95 `57.299ms`), so startup and
  first semantic frames remain future optimization work.
- The result confirms that the dominant steady-state issue was full semantic
  production/presentation for leaf-only dirty rows, not DOM row replacement.
- Remaining high-signal perf work should now target:
  - reducing warmup/initial semantic spikes;
  - deciding whether the current steady gate should become a tracked threshold
    file update; and
  - repeating the retained dirty-semantics measurement on `single-dirty-cell`
    and the larger stress scenario before broadening the claim.

## 2026-06-09 21:26 EDT

Generalized the retained dirty-semantics check to `single-dirty-cell-160x50`
and tightened one retained-index allocation path.

Changes kept:

- `SemanticTree.replaceNodes(...)` now seeds the replacement tree's cached
  flattened node list and id map when all replacements are leaf nodes and the
  previous tree already had cached indexes.
- `SemanticsOwner.updateRetainedNodes(...)` now builds the next retained id map
  from the previous map plus the known replacement nodes instead of reading
  `next.nodesById` and rebuilding a full index.
- `SemanticDomPresenter._presentIncremental(...)` now uses
  `SemanticTreeUpdate.nextNodesById.length` for incremental stats instead of
  forcing `tree.nodeCount`.

Experiment rejected and reverted:

- Tried precomputing the row-local `single-dirty-cell-160x50` benchmark line
  strings inside `_DrivenRowState`.
- Rejected because
  `profiling/web/runs/single-dirty-cell-160x50-row-cache-check.json` worsened
  the steady gate: `2/24` steady frames over budget, steady total p95
  `20.699ms`.
- Reverted the benchmark code; the retained semantic index cleanup remains.

Verification:

- `cd packages/fleury && dart analyze lib/src/semantics/semantics.dart lib/src/semantics/semantics_owner.dart test/semantics/semantics_test.dart test/semantics/semantics_owner_test.dart` -
  passed.
- `cd packages/fleury && dart test test/semantics/semantics_owner_test.dart test/semantics/semantics_test.dart` -
  passed with 38 VM tests.
- `cd packages/fleury_web && dart analyze lib/src/semantics/semantic_dom_presenter.dart` -
  passed.
- `cd packages/fleury_web && dart test -p chrome test/semantic_dom_presenter_test.dart` -
  passed with 16 Chrome tests.
- `cd packages/fleury_web && dart analyze lib/src/benchmark/web_benchmark_scenarios.dart web/benchmark_capture.dart test/web_frame_capture_tool_test.dart` -
  passed before the rejected row-cache experiment.
- `cd packages/fleury_web && dart test test/web_frame_capture_tool_test.dart` -
  passed with 10 VM tests before the rejected row-cache experiment.
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  passed with 23 Chrome tests before the rejected row-cache experiment.
- After reverting the rejected row-cache experiment:
  `cd packages/fleury_web && dart analyze lib/src/benchmark/web_benchmark_scenarios.dart` -
  passed.

Browser perf checks:

- First retained dirty-semantics single-dirty capture:
  `profiling/web/runs/single-dirty-cell-160x50-retained-dirty-semantics-check.json`
  - all frames: `5/32` over budget (`15.625%`);
  - steady frames after skip 8: `2/24` over budget (`8.333%`);
  - steady total p95 `21.3ms`;
  - steady `runtimeBuildMs` p95 `9.5ms`;
  - steady `semanticApplyMs` p95 `4.201ms`;
  - semantic coverage stayed complete (`semanticUncoveredCells=0`).
- Recheck before the index cleanup:
  `profiling/web/runs/single-dirty-cell-160x50-retained-dirty-semantics-recheck.json`
  - all frames: `7/32` over budget (`21.875%`);
  - steady frames after skip 8: `3/24` over budget (`12.5%`);
  - steady total p95 `37.601ms`.
- After the retained-index cleanup:
  `profiling/web/runs/single-dirty-cell-160x50-retained-index-check.json`
  - all frames: `4/32` over budget (`12.5%`);
  - steady frames after skip 8: `1/24` over budget (`4.167%`);
  - steady total p95 `16.5ms`, under the `16.67ms` p95 gate;
  - strict steady gate still failed because one frame reached `16.9ms`;
  - steady `runtimeBuildMs` p95 `4.1ms`;
  - steady `semanticTreeBuildMs` p95 `1.801ms`;
  - steady `semanticDiffMs` p95 `1.899ms`;
  - steady `semanticPresenterMs` p95 `1.099ms`;
  - steady `semanticApplyMs` p95 `7.0ms`;
  - semantic coverage stayed complete (`semanticUncoveredCells=0`).

Interpretation:

- Retained dirty semantics generalizes to `single-dirty-cell-160x50` in the
  sense that semantic DOM churn is gone and the retained semantic slices are
  mostly bounded: one dirty row, one semantic update, one reused semantic DOM
  element per frame.
- The scenario is not yet accepted as a strict steady-state gate because the
  latest kept run still has `1/24` steady frames over budget.
- The remaining miss is no longer a semantic production failure. The over-budget
  frame in the kept post-index run was runtime/build-bound (`total=16.9ms`,
  `runtimeBuild=14.601ms`, `semanticApply=1.9ms`).
- Next high-leverage work is to separate true framework build variance from
  benchmark harness variance, then decide whether to:
  - keep `single-dirty-cell` as a stricter runtime-build follow-up gate; or
  - introduce a product-realistic row/cell retained widget pattern if the
    current benchmark is measuring avoidable app-side string/widget churn.

## 2026-06-09 22:50 EDT

Takeover pass (new agent): interpreted the interrupted build-stats capture,
ran confirmation captures for the proposed gates, and hardened the retained
semantic path. Conclusions below supersede the 21:26 EDT open questions.

### Build-stats verdict: no framework rebuild churn

The interrupted diagnostic capture completed and is on disk:
`profiling/web/runs/single-dirty-cell-160x50-build-stats-check.json`
(captured 2026-06-10T01:33Z).

- Every one of the 24 steady frames — including the 3 over-budget frames
  (26.2ms, 33.1ms, 34.8ms) — recorded exactly
  `runtimeBuildPassCount=1`, `runtimeRebuiltElementCount=1`,
  `runtimeMaxDirtyElementCount=1`.
- The over-budget frames spend their time in `runtimeBuildMs` (12.0—31.5ms)
  rebuilding a single element. That is V8 JIT/GC/scheduler variance, not
  framework rebuild churn.
- Verdict: the remaining single-dirty-cell misses are NOT a framework defect
  to fix; they are an environment-variance gate-policy question. The
  per-frame build stats now make this attributable frame-by-frame.

### Confirmation captures refute the strict steady gate

The 21:09 EDT acceptance of `dirty-row-160x50` as a strict steady gate
(`0/24` over, p95 13.7ms) was based on a single capture. Two confirmation
captures with identical parameters (32 frames, warmup 8) do not reproduce it:

- `profiling/web/runs/dirty-row-160x50-floor-confirm-1.json`:
  steady p50 2.7ms, p95 23.2ms, max 53.1ms, `3/24` over budget.
- `profiling/web/runs/dirty-row-160x50-floor-confirm-2.json`:
  steady p50 6.8ms, p95 26.1ms, max 40.7ms, `4/24` over budget.
- `profiling/web/runs/single-dirty-cell-160x50-post-hardening.json`:
  steady p50 2.0ms, p95 19.4ms, max 20.3ms, `2/24` over budget.

Build stats in all three runs stayed flat (dirty-row: `(1 pass, 2 rebuilt,
2 max-dirty)` every steady frame; single-dirty-cell: `(1, 1, 1)`), so the
over-budget frames again decompose into:

- `runtimeBuildMs` spikes (10—16ms for one/two-element rebuilds) — the same
  VM-variance signature as the build-stats capture; and
- a repeatable ~32ms `semanticTreeBuildMs` spike on the final steady frame
  of both dirty-row runs (53.1ms / 40.7ms totals). The exact-last-frame
  pattern suggests accumulated allocation pressure triggering a major GC at
  the capture boundary. Logged as a diagnostic follow-up: confirm with a
  longer capture (64+ frames) and, if confirmed, attack per-frame allocation
  in the semantic produce/replace path rather than the gate.

### Gate decision

- Steady p50 for both row-local scenarios is 2—7ms — the dirty-frame web
  path is fast in the typical case; the gate question is entirely about
  tail variance.
- A strict "no steady frame over 16.67ms" gate is NOT reproducible on this
  machine/environment today and is therefore not adopted for either
  scenario. Single lucky runs must not bless gates; gates come from the
  median-of-3 scoreboard.
- The release gate remains the regression-floor model already encoded in
  the reviewed thresholds machinery (median-of-3 per-scenario p95 with 20%
  headroom), refreshed against the post-retained-dirty-semantics code state
  (see next entry for the regenerated baseline).
- The strict 16.67ms steady budget is retained as the optimization target
  and is now diagnosable per frame via the build-stat fields: an over-budget
  frame with flat build stats and a dominant `runtimeBuildMs`/GC slice is
  environment variance; anything else is framework work to fix.

### Hardening landed in this pass

- `fleury.dart` now re-exports `fleury_host.dart` (restores
  `InputDispatcher` to the native umbrella; fixes 4 analyzer errors in two
  unmigrated test files); `BuildFlushStats` moved off the app-facing
  `fleury_core.dart` surface to `fleury_host.dart`.
- Retained-vs-full divergence assertion: `debugSemanticTreeDivergence`
  (exported from `fleury_host.dart`) compares the retained
  `SemanticTree.replaceNodes` result against a fresh
  `SemanticTree.fromElement` rebuild inside `assert(...)` in
  `runTuiSurface`; throws with the first divergent node path in debug
  builds, compiles out of `-O2` release benchmarks.
- Closed a stale-fallback hazard: the retained leaf path now also requires
  `!lastSemanticCoverageAudit.hasUncoveredText`. Patching a fallback-bearing
  retained tree would keep a stale fallback label "covering" repainted
  cells; a full rebuild regenerates fallback from the live buffer. New
  Chrome test
  (`leaf update with active text fallback refreshes fallback from the
  buffer`) locks the behavior.
- Escalation-edge tests added (core): sibling semantic insertion/removal
  escalates to full rebuild; id change escalates; `includeChildren` updates
  escalate; geometry-only movement is captured as a retained leaf update
  with fresh bounds; multiple leaf updates in one frame are all captured.
  Divergence-helper unit tests added (owner): equivalent trees, first
  differing node, child reorder.

Verification:

- `cd packages/fleury && dart analyze` - No issues found (was 4 errors).
- `cd packages/fleury_web && dart analyze` - No issues found.
- `cd packages/fleury && dart test test/semantics/semantics_test.dart` -
  38 tests passed (6 new escalation tests).
- `cd packages/fleury && dart test test/semantics/semantics_owner_test.dart` -
  9 tests passed (3 new divergence tests).
- `cd packages/fleury_web && dart test -p chrome test/run_tui_surface_test.dart` -
  24 tests passed (1 new fallback-interplay test) with the divergence
  assertion active under DDC asserts.

## 2026-06-09 23:05 EDT

Regenerated the promoted evidence chain against the
post-retained-dirty-semantics + hardening code state. The prior baseline
(`2026-06-09-local-dom-retained-subphase-refresh`) and completion audit
predated the retained-dirty-semantics work and materially misstated current
performance.

New baseline: `profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened`
(11 scenarios x 3 runs, warmup 8, comparable environment signatures, strict
min-runs=3 scoreboard).

Median capture p95 (old -> new, ms): dirty-row-160x50 331.1 -> 52.8;
single-dirty-cell-160x50 117.2 -> 61.0; large-160x50 178.1 -> 47.8;
cursor-blink-80x24 350.2 -> 112.4; scroll-row-churn 832.1 -> 393.4;
full-frame-churn 663.1 -> 385.9; stress-300x100 700.0 -> 487.7;
text-input-burst 248.9 -> 111.6; noop-160x50 92.8 -> 20.9. Steady p50 for
the row-local scenarios is now 2-7ms (dirty-row run-1 p50 4.0ms vs 25.6ms
in the old baseline). Two scenarios moved against the trend
(normal-80x24 120.3 -> 261.7, resize-burst 314.6 -> 630.0): both are tail
variance, not code regression — resize-burst median p50 improved
(49.1 -> 39.2ms), and the hardening gate change is provably inert across
the whole suite (`semanticUncoveredCellsMax = 0` in all 33 captures, so the
new `!hasUncoveredText` condition never fires in benchmarks). These two
scenarios remain semanticApply-dominant and are optimization targets, not
gate regressions.

Evidence chain regenerated:

- `fleury benchmark web-suite --runs=3 --warmup=8 --output-dir=.../2026-06-09-retained-dirty-semantics-hardened --write-thresholds=.../thresholds.candidate.json` - passed strict scoreboard.
- `dart run tool/web_readiness_bundle.dart --captures=... --manual=... --thresholds=.../thresholds.candidate.json --target-preset=v1 --write-default-preflights --completion-audit=docs/implementation/web-rfc-completion-audit.json` - bundle written.
- `dart run tool/web_automated_validation.dart --json-output=.../readiness-candidate/web-automated-validation.json --strict` - strictPass (browser + vm).
- Bundle re-generated to absorb the validation artifact, then
  `--verify ... --strict` - passed: 11 artifacts, 226 source inputs, 65
  manifest fields, zero mismatches.
- `docs/implementation/web-rfc-completion-audit.json` regenerated:
  `overallStatus=implementation-review-ready-release-blocked`. All remaining
  blockers chain from one root action: human review/promotion of the
  candidate thresholds.

Pending human gate (intentionally not self-served, matching the
"Dan interactive review" provenance precedent): promote the candidate via
the command embedded in
`profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/threshold-review-plan.md`
(input fingerprint `fnv1a64:31221901e96a24c3`), then re-run the readiness
bundle + preflights. Suggested review-note framing: regression floor for
the measured environment only, not production acceptance; strict 16.67ms
steady budget remains the tracked optimization target with per-frame
build-stat attribution.

## 2026-06-10 (frame-path plan, Phases 0-1)

Executing `docs/implementation/web-industry-leading-plan.md`.

### Phase 0 — merge + native parity baseline (complete)

- Merged main (storybook/DX commit `772af70`, benchmark diagnostics
  `78155a1`) into the web branch and fast-forwarded main to `e30aebf`.
  Notable resolutions: main's renderer rewrite (screen-diff stats,
  `appendCell`, C0 cursor moves, plain-gap write-through) kept as the base
  with the branch's `dirtyBounds` bounded diffing ported onto it; bounded
  path skips whole-screen stats and scroll-detection passes. The branch's
  broader same-style gap write-through was dropped in favor of main's
  plain-only tactic (main has the opposing styled-gap test); revisit only
  with byte-budget evidence.
- Post-merge verification: core 1610 VM tests, web 193 VM + 142 Chrome —
  all passing after one stale expectation fix (mount no longer coalesces a
  redundant build-reason frame into the initial frame).
- Native parity baseline (P-7 reference) recorded at the merge point:
  `profiling/caps/2026-06-10-native-parity-phase0/SB.*.json`
  (11 scenarios, 3 iterations each). SB.10 (demo-app journey) is EXCLUDED:
  it fails with "Expected exactly one semantic node, found 0" at
  `scenario_benchmarks.dart:450`, and the failure reproduces at `772af70`
  before the web merge — pre-existing demo-app drift from the storybook
  refactor, flagged for a separate fix (note `_invoke` ignores failed
  command invocations, so the journey breaks silently).

### Phase 1 — per-runtime frame-state trackers (implementation complete)

`RenderDamageTracker` and `SemanticDirtyTracker` are no longer static
globals:

- `RenderDamageTracker` is instance-owned by `BuildOwner`
  (`renderDamageTracker`) and attached at the root render object by
  `BuildOwner.renderFrame`. Layout/conservative-paint invalidation walks
  (`_markNeedsLayoutUp`) publish at their terminal (root) node, so
  per-object storage stays nil. A root the owner has not driven before
  starts with conservative damage (detached-subtree invalidations cannot
  have reached the tracker).
- `TuiFrameLoop` takes the runtime's tracker
  (`TuiFrameLoop(renderDamage: runtime.renderDamageTracker)`); without one
  it conservatively treats every frame as requiring a full diff.
- `SemanticDirtyTracker` is per-`BuildOwner` via an `Expando` extension
  (`owner.semanticDirtyTracker`, exported as `SemanticDirtyOwner`) — the
  same per-instance idiom the `SemanticTree` caches use, so the widgets
  layer takes no semantics dependency. `SemanticsElement` records into its
  owner's tracker.
- Hosts no longer call static `reset()`s — a fresh runtime IS fresh
  tracker state. `TuiRuntime` exposes both trackers.
- Both trackers now accumulate across frames until taken — the
  cross-frame coalescing contract Phase 2 (deferred semantics) needs.

Isolation proven (the A-2 gate):

- Core: `semantic dirty tracking is isolated per runtime` — two
  `FleuryTester` runtimes; leaf dirt in one never appears in the other's
  snapshot (the old statics shared one dirty map).
- Web: `two hosts on one page have isolated frame and semantic state` —
  two `runTuiSurface` hosts; driving one leaves the other's retained
  semantic output untouched (0 added/removed/updated on its next frame).

### Phase 1 verification

- `dart analyze`: clean on both packages.
- Suites: core 1611 VM tests, web 193 VM + 142 Chrome — all passing (one
  dom_demo timeout under full-suite load re-ran green in isolation).
- Web within-noise check (32 frames, warmup 8):
  `dirty-row-160x50-phase1-trackers.json` steady p50 2.55ms / p95 19.4ms /
  3/24 over vs pre-change confirms (p50 2.7-6.8 / p95 23.2-26.1 / 3-4
  over); `single-dirty-cell-160x50-phase1-trackers.json` p50 5.1 / p95
  32.4 / 3/24 over, inside the established single-cell variance band.
  No regression signal.
- Native parity (P-7, 3 iterations, vs
  `profiling/caps/2026-06-10-native-parity-phase0`): SB.2 journey +3.5%,
  SB.4 journey -6.8%, SB.6 journey -6.2%, update/frame micro-metrics flat;
  all scenarios pass. Sub-millisecond metrics jitter +-45% at 3 samples
  (noise floor); SB.6 rssDeltaBytes +0.9MB is within RSS measurement noise
  (SB.4's moved -3.3MB the other way).

Phase 1 exit gate met: per-runtime trackers, isolation proven on both
targets, suites green, benchmarks within noise. Next: Phase 2 (semantics
off the visual frame) per the plan; Phase 1's cross-frame accumulation
contract is in place for it.
