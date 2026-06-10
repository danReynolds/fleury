# Workstream: Reactive Render Engine

## Purpose

Preserve Flutter-style developer ergonomics while making terminal rendering
fast, predictable, and correct under dense app workloads.

## Current State

- Fleury already has widgets, elements, state, render objects, constraints,
  cell buffers, ANSI diffing, focus, key bindings, repaint boundaries,
  animation scheduling, debug shell, and testing.
- RFC 0009 documents performance hypotheses and benchmark needs.
- M0.5 defines the scenario benchmark lab that will turn performance claims
  into app-shaped workloads.
- A first scenario benchmark runner now exists with `SB.1 Time To Counter App`,
  JSON output, filtering, save support, and candidate threshold metadata.
- The core runner now includes `SB.2 Text Editing Composer Stress`, keeping
  the strong text/input claim under 10k-character mixed-width editor pressure.
- The core runner now includes `SB.12 Layout Dirtiness Cache`, proving the first
  dirty-layout foundation with performed/skipped layout counts across first,
  update, paint-only style, paint-only text, and idle frames.
- A widgets-package scenario runner now adds `SB.3 DataTable 100k Rows`, keeping
  high-level widget scenarios out of the core package dependency graph.
- The widgets runner now includes `SB.5 Streaming Markdown`, which keeps
  streamed rich-text rendering, sanitization, semantic links, block copy, and
  parse/update cost under direct pressure.
- The widgets runner now includes `SB.6 Dashboard Update Pressure`, which keeps
  many small progress, gauge, sparkline, chart, counter, and status surfaces
  updating under retained reactive frame pressure and now reports layout
  performed/skipped counts for dashboard updates.
- The same widgets runner now includes `SB.7 Resize Storm`, which keeps a
  table/log/editor surface mounted through 500 alternating terminal sizes and
  validates semantic table/log/text-field nodes after every resize.
- The widgets runner now includes `SB.8 Overlay And Command Palette Churn`,
  which keeps app command discovery, palette filtering, modal focus,
  route-depth restoration, semantic invoke/dismiss actions, and disabled
  command behavior under repeated overlay pressure.
- The demo-app package now includes `SB.10 Demo-App Journey`, measuring the
  integrated example across app shell, command palette, DataTable, LogRegion,
  process task, diagnostics, semantics, accessibility, and debug capture.
- A first hot-path render island now exists through `DataTable`, proving that a
  widget can bypass per-cell widget composition while still exposing focus,
  selection, visible-row semantics, stable keys, sort/filter metadata,
  selected-row copy, rectangular cell/range copy, mouse hit selection, and
  tests.
- Debug frame insight now reports frame reasons, dirty bounds, dirty source
  labels, terminal/capability fallback state, and repaint-boundary cache
  metrics through frame events, the debug panel, capture artifacts, and runtime
  tests.
- Render objects now track layout dirtiness, skip same-constraint layout when a
  subtree is clean, bubble child layout invalidation to parents, and report
  debug-only `layout:` dirty-source labels. Audited core paint-only setters can
  now invalidate paint without relayout, while unaudited setters keep the
  conservative compatibility path.
- Dirty layout/paint propagation now has first benchmark evidence for static
  subtree skips, idle root skips, and paint-only root skips. The remaining
  optimization work is a broader widget-package setter audit under scenario
  pressure.
- A first widget-package paint-only audit now covers stable-shape visual
  updates for `LineChart`, `Heatmap`, `CalendarHeatmap`, `Canvas`, `Digits`,
  `RangeSlider`, and `Image`. Focused tests assert these updates reuse cached
  layout, while shape-sensitive fields stay layout-dirty.
- The DataTable render island now owns explicit setter invalidation:
  visible selection and visible-cell content updates are paint-only, while
  row-count, column, spacing, and header-geometry changes remain layout-dirty.
  Focused layout-stat tests cover those hot visible update paths, and `SB.3`
  remains under the candidate 100k-row threshold.
- The composition `Table` render object now also owns explicit setter
  invalidation. Visible selected-row movement can repaint without relayout,
  while column count/widths, spacing, header geometry, children, and selection
  changes that may move the body window remain layout-dirty.
- Core `RenderText` now treats same-width single-line content swaps as
  paint-only when the current layout shape is known to stay stable. Wrapping,
  newline, empty/non-empty, and intrinsic-width-changing content updates remain
  layout-dirty. `SB.12` now includes a same-width text paint-only frame so this
  optimization is covered by scenario evidence, not only focused render tests.
- Core multi-child render objects now treat same-identity, same-order child
  replacement as a layout no-op, while reorders/add/drop still invalidate
  parent layout. `RenderTable` follows the same rule in `fleury_widgets`.
  `SB.12` now includes a child-list no-op frame with p95 0 performed /
  1 skipped layout work.
- `ScrollView` now keeps its generic viewport paint path bounded to the visible
  viewport: it still lays out the arbitrary child at full natural height, but
  paints into a viewport-sized scratch buffer with a translated negative child
  offset. `CellBuffer` writes now clip translated out-of-bounds paints while
  reads still throw, preserving scroll/selection behavior without allocating a
  full child-height scratch buffer per paint.
- `RenderFlex` now culls non-selectable child subtrees whose laid-out paint
  bounds cannot intersect the current `CellBuffer`. Selectable subtrees still
  receive offscreen paint calls so full `cellBounds`, clipped
  `visibleBounds`, and reading-order selection behavior remain correct through
  scrolled Columns/Rows. `SB.12` now includes a viewport paint sub-journey that
  records only 24 painted rows for a 24-row viewport over a 2,000-row
  `ScrollView` child.
- The M3.7 launch boundary is closed: high-performance render machinery stays
  first-party/private for MVP launch. Production libraries do not export
  layout-debug counters, child-list helper functions, paint-culling internals,
  render-island extension APIs, or first-party widget-package `Render*`
  implementations, while `fleury_test` keeps the diagnostics needed for tests
  and benchmarks.
- The core widget public boundary now keeps `LayoutBuilder` and
  `LayoutWidgetBuilder` public while hiding implementation-only
  `RenderLayoutBuilder`, whose callback is owned by the private element.
- The same boundary now applies to additional core widgets: `TextInput`,
  `TextArea`, `RichText`, and `Scrollbar` stay public while their
  implementation renderers and scrollbar geometry/metrics plumbing stay out of
  production barrels. Standalone low-level render primitives remain public
  only where app authors can use them independently.
- Render diagnostics now keep the same production/test split across layout and
  repaint-boundary counters: production exposes useful primitives such as
  `RenderRepaintBoundary`, while `RepaintBoundaryFrameStats` remains available
  through `fleury_test.dart` for tests, captures, and benchmarks.
- Core root lifecycle now follows the same compatibility rule as subtree
  reconciliation: `BuildOwner.updateRoot` preserves the root element and state
  only for compatible `runtimeType` plus `Key` updates; incompatible type/key
  replacements dispose the old tree and mount a fresh root. Stale root handles
  are rejected instead of mutating a defunct tree.
- Core list and scroll controllers now have explicit lifecycle semantics:
  `ListController` and `ScrollController` retain final readable selection,
  range, offset, and layout metrics after disposal, clear transient pending
  jumps, and reject post-dispose selection, pin, jump, and scroll mutations.
- Animation primitives now follow the same final-readable/no-stale-mutation
  rule: `Ticker`, `FrameTicker`, and `Animation<T>` retain final timing, mute,
  and value state after disposal, while stale mute, snap, stop, and retarget
  mutations fail explicitly instead of mutating disposed scheduler-owned
  objects.
- Selection and overlay primitives now apply the same rule without breaking
  teardown cleanup: `SelectionContainerDelegate.remove` and
  `OverlayEntry.remove` remain idempotent cleanup paths, while new selection
  registration/dispatch and overlay rebuild/visibility mutations fail after
  disposal.
- Focus manager lifecycle now detaches registered nodes during manager
  disposal and rejects post-dispose focus movement or key dispatch, while
  `FocusNode` cleanup remains idempotent after the manager is gone.
- Scheduler and binding lifecycle now prevent disposed runtime roots from
  being restarted: `TickerScheduler` and `TuiBinding` reject new ticker,
  reassemble, and post-frame registration after disposal while preserving
  idempotent cleanup and shutdown post-frame draining.
- Input dispatcher lifecycle now cancels pending key sequences on disposal and
  rejects post-dispose event dispatch or global binding replacement, keeping
  stale keyboard events from reaching a torn-down focus tree.
- Debug/test runtime roots now follow the same lifecycle contract where they
  own app-session resources: `DebugCaptureRecorder` keeps final bounded
  captures readable but rejects attach/record calls after disposal, and
  `FakeTerminalDriver` keeps final size/output/call-count state readable while
  rejecting new terminal activity after disposal.

## Target Capabilities

- Retained reactive widget API with stable state and hot reload.
- Efficient frame scheduling, layout, paint, diffing, and resize handling.
- First-party render islands for high-volume widgets without losing
  semantics, focus, hit testing, copy, theme, or tests.
- Scenario benchmarks for real workloads, not only microbenchmarks.

## Milestone Checklist

- [x] RRE.1 Define scenario benchmark harness.
  - Intent: Make performance claims measurable.
  - Acceptance: Harness covers table scrolling, log tailing, text editing,
    streaming markdown, dashboard updates, resize storms, overlay churn, and
    streaming content/logs.
  - Evidence: [Scenario benchmark lab](../scenario-benchmark-lab.md).
  - Notes: Align with RFC 0009 benchmark output shape and preserve current
    microbenchmark baselines as lower-level evidence.

- [x] RRE.2 Establish baseline numbers.
  - Intent: Know where Fleury stands before optimizing.
  - Acceptance: Baselines recorded for Phase 1 scenarios with reproducible
    commands and environment notes.
  - Evidence:
    [scenario benchmark runner](../../../packages/fleury/benchmark/scenario_benchmarks.dart),
    [benchmark README](../../../packages/fleury/benchmark/README.md),
    [core Phase 1 baseline](../../../packages/fleury/benchmark/results/phase1-core-2026-05-31.json),
    [text editing baseline](../../../packages/fleury/benchmark/results/phase2-text-editing-2026-06-01.json),
    [layout dirtiness baseline](../../../packages/fleury/benchmark/results/phase2-layout-dirtiness-2026-06-01.json),
    [widgets scenario benchmark runner](../../../packages/fleury_widgets/benchmark/scenario_benchmarks.dart),
    [widgets Phase 1 baseline](../../../packages/fleury_widgets/benchmark/results/phase1-widgets-2026-05-31.json),
    [Streaming Markdown baseline](../../../packages/fleury_widgets/benchmark/results/phase2-streaming-markdown-2026-06-01.json),
    [Dashboard Update baseline](../../../packages/fleury_widgets/benchmark/results/phase2-dashboard-update-2026-06-01.json),
    [widgets Resize Storm baseline](../../../packages/fleury_widgets/benchmark/results/phase2-resize-storm-2026-06-01.json),
    [Overlay Command Palette baseline](../../../packages/fleury_widgets/benchmark/results/phase2-overlay-command-palette-2026-06-01.json),
    [optimized Overlay Command Palette baseline](../../../packages/fleury_widgets/benchmark/results/phase2-overlay-command-palette-optimized-2026-06-01.json),
    [demo-app scenario benchmark runner](../../../packages/fleury_example_console/benchmark/scenario_benchmarks.dart),
    [demo-app journey baseline](../../../packages/fleury_example_console/benchmark/results/phase2-demo-app-journey-2026-06-01.json).
  - Notes: Local Dart is now 3.12.1. `SB.1` saved a 20-iteration baseline
    with command-to-frame p95 254 us and semantic-query p95 102 us. `SB.3`
    saved a 20-iteration 100k-row DataTable baseline with page-move p95
    772 us, selected-row copy p95 310 us, and semantic-query p95 2497 us.
    `SB.2` saved a 10-iteration 10k-character text editing baseline with
    cursor-move p95 798 us, insertion/deletion p95 641 us, selection p95
    2191 us, chunked-paste completion p95 18573 us, and semantic-query p95
    508 us.
    `SB.7` saved a 5-iteration, 500-resize-event baseline over a
    table/log/editor surface with resize-frame p95 488 us, semantic-query p95
    593 us, and zero unsafe visible frames across 2500 measured resize frames.
    `SB.5` saved a 5-iteration, 1000-chunk streaming markdown baseline with
    chunk-update p95 13428 us, chunk-parse p95 12588 us, chunk-frame p95
    926 us, semantic-query p95 2155 us, and zero unsafe visible frames.
    `SB.6` saved a 20-iteration, 400-tick dashboard baseline with
    update-total p95 267 us, update-frame p95 120 us, update-pump p95
    97 us, semantic-query p95 439 us, update-frame layout p95 45 performed /
    29 skipped, and zero unsafe visible frames.
    `SB.8` first saved a 20-iteration, 1000-command overlay baseline with zero
    stale palette semantics and zero unexpected invocations, but it also
    exposed launch-critical command-palette latency: filter p95 98705 us,
    settle p95 93096 us, and full-cycle p95 247544 us. The optimized follow-up
    baseline after lazy visible rows and ranked cached search drops filter p95
    to 1121 us, settle p95 to 227 us, and full-cycle p95 to 6429 us while
    preserving the same correctness counters.
    `SB.10` saved a 10-iteration demo-app journey baseline with full-journey
    p95 101284 us, command-palette p95 13979 us, DataTable filter p95 6906 us,
    debug-capture p95 8400 us, process run-to-success p95 53184 us, and
    semantic-query p95 754 us.
    `SB.9` saved a 10-iteration subprocess/output baseline with stream-frame
    p95 6230 us, process-panel-render p95 10649 us, semantic-query p95 1965
    us, restored terminal handoff state, and zero unsafe artifact leaks on a
    1 MB target process fixture.
    `SB.12` saved a refreshed 20-iteration layout-dirtiness baseline with
    command-to-frame p95 11799 us, idle-frame p95 692 us, paint-only-frame p95
    1210 us, text-paint-only-frame p95 3251 us, update-frame layout p95
    7 performed / 3 skipped, paint-only-frame layout p95 0 performed /
    1 skipped, text-paint-only-frame layout p95 0 performed / 1 skipped, and
    idle-frame layout p95 0 performed / 1 skipped over a static-pane plus
    changing-counter fixture. The child-list replacement follow-up records
    command-to-frame p95 3559 us, child-list no-op frame p95 4363 us, and
    child-list no-op layout p95 0 performed / 1 skipped while preserving
    paint-only/text-paint-only/idle layout p95 0 performed / 1 skipped.
    The viewport paint follow-up records command-to-frame p95 7014 us,
    viewport-first-frame p95 4773 us, viewport-scroll-frame p95 1245 us,
    viewport painted rows p95 24 on a 24-row viewport over a 2,000-row child,
    and paint-only/text-paint-only/child-list/idle layout p95 0 performed /
    1 skipped.
    Candidate thresholds remain informational until variance is better known.

- [x] RRE.3 Prove semantic render island pattern.
  - Intent: Let hot widgets bypass expensive composition while preserving
    framework affordances.
  - Acceptance: DataTable or LogView prototype exposes semantics, focus, hit
    testing, copy, theme, and tests while using optimized rendering.
  - Evidence:
    [DataTable render island](../../../packages/fleury_widgets/lib/src/data_table.dart),
    [DataTable tests](../../../packages/fleury_widgets/test/data_table_test.dart),
    [DataTable scenario benchmark](../../../packages/fleury_widgets/benchmark/scenario_benchmarks.dart).
  - Notes: First evidence covers semantics, focus, keyboard selection,
    theme-derived selection styling, selected-row copy/export, rectangular
    cell/range copy/export, and tests. Final slice adds mouse hit selection
    over the painted render-island viewport: clicks select visible rows, and
    Shift-click in cell mode extends a rectangular range using the same
    controller and semantic state as keyboard selection.

- [x] RRE.4 Expand debug frame insight.
  - Intent: Make rendering performance understandable during development.
  - Acceptance: Inspector reports frame timing, dirty regions, rebuilds,
    repaint boundaries, and active capability fallbacks.
  - Evidence:
    [debug frame events](../../../packages/fleury/lib/src/debug/debug_events.dart),
    [debug panel](../../../packages/fleury/lib/src/debug/debug_panel.dart),
    [debug capture recorder](../../../packages/fleury/lib/src/debug/debug_capture.dart),
    [runtime frame emission](../../../packages/fleury/lib/src/runtime/run_tui.dart),
    [layout debug stats](../../../packages/fleury/lib/src/rendering/render_layout_stats.dart),
    [repaint-boundary debug stats](../../../packages/fleury/lib/src/rendering/render_repaint_boundary.dart),
    [debug inspector tests](../../../packages/fleury/test/debug/debug_shell_test.dart),
    [runtime debug event tests](../../../packages/fleury/test/runtime/run_tui_test.dart),
    [debug capture tests](../../../packages/fleury/test/debug/debug_capture_test.dart).
  - Notes: Inspector signal now covers frame timing, schedule reason, dirty
    cells/bounds, dirty source labels, active terminal/capability fallback
    rows, layout invalidation labels, and repaint-boundary
    totals/repaint/cache/copied-cell counts. Layout frame stats now report
    performed/skipped layout counts in debug frames, capture artifacts, and the
    `SB.12` scenario benchmark. This closes the first
    developer-visible rendering-performance insight pass.

- [x] RRE.5 Close launch high-performance API boundary.
  - Intent: Prevent internal optimization machinery from becoming accidental
    public API before package/demo-app pressure proves the right extension
    shape.
  - Acceptance: Production libraries do not expose layout-debug stats,
    child-list helper functions, paint-culling internals, or render-island
    extension APIs; `fleury_widgets` does not expose concrete first-party
    `Render*` implementations from its public barrel; test-only diagnostics
    remain available through `fleury_test`.
  - Evidence:
    [performance API boundary tests](../../../packages/fleury/test/rendering/performance_api_boundary_test.dart),
    [render object layout tests](../../../packages/fleury/test/rendering/render_object_test.dart),
    [remote public API boundary tests](../../../packages/fleury/test/remote/public_api_boundary_test.dart),
    [widget public API boundary tests](../../../packages/fleury_widgets/test/public_api_boundary_test.dart).
  - Notes: This closes M3.7 for the MVP cycle as first-party render-object
    discipline. Future public render-island APIs should be designed after
    external packages need them, not from the private implementation shape.

## Implementation Notes

- Keep the cell-buffer architecture, but judge it by developer-visible wins:
  latency, flicker resistance, resize behavior, diagnostics, and benchmarks.
- Avoid optimization work without scenario pressure.
- Preserve terminal correctness when Flutter-like expectations conflict with
  terminal realities.
- The first scenario harness should emit JSON records with environment,
  fixture, timing, output, memory, semantic, and capability/security metadata
  before hard CI thresholds are enforced.
- Keep scenario benchmarks separate from `benchmark/all.dart` while the suite is
  slow, app-shaped, and baseline-oriented. The microbenchmark suite remains the
  fast local hot-loop check.
- First layout-dirtiness implementation is intentionally conservative:
  `markNeedsLayout` is the explicit API, `RenderObject.layout` skips
  same-constraint clean subtrees, child layout dirtiness bubbles upward, and
  `markNeedsPaint` still invalidates layout for compatibility with unaudited
  setters. The first paint-only split adds `markNeedsPaintOnly`, removes
  element-level unconditional relayout after render-object widget updates, and
  avoids multi-child `replaceAllChildren` calls when the render-child identity
  order is unchanged. Core style/visibility/cursor/bounds setters now use the
  paint-only path; list render objects intentionally keep mutable-controller
  relayout because selection and jump state are consumed during layout.
- The first widget-package audit is intentionally scenario-led: dashboard
  progress, gauge, sparkline, and bar-chart value/style setters now use
  paint-only invalidation where shape is stable, while label/count/chrome
  changes remain layout-dirty. `SB.6` records layout stats so future widget
  audits are driven by visible pressure instead of broad setter churn.
- The second widget-package audit extends the same rule across additional
  visual surfaces. Only stable-shape changes use `markNeedsPaintOnly`: chart
  series/ranges/cursors/styles, same-shape heatmap values, calendar heatmap
  values/styles, canvas painter/bounds/marker/style, same-width digit text and
  style, range-slider values/focus/styles, and image fit/glyph/protocol/color
  policy. Geometry and intrinsic-size changes still call `markNeedsLayout`.
- Render islands should not depend on element reconciliation to dirty layout
  by accident. Hot render-object setters own their layout/paint invalidation:
  DataTable keeps visible selection and visible cell-builder refreshes
  paint-only, but relayouts when the viewport, columns, row count, spacing, or
  header geometry can change.
- Composition render objects should follow the same discipline even when they
  are not render islands. `RenderTable` keeps visible selected-row changes and
  separator/selection style changes paint-only, but relayouts when children,
  columns, spacing, headers, or row-window state can change.
- Multi-child render objects should not use reconciliation as accidental
  invalidation. Supplying the same render child identities in the same order is
  a no-op for layout; reorders, additions, removals, and geometry-affecting
  property changes remain layout-dirty.
- Text content is only paint-only under a narrow stable-shape rule: same display
  width, single line, and either non-wrapping or currently fitting under the
  active constraints. Lazy list selection remains conservative because selected
  row builders may change arbitrary layout.
- Generic viewport optimization depends on clipped paint writes. Keep
  `CellBuffer.at`/`atColRow` strict for reads, but allow write APIs to clip
  translated negative/out-of-bounds paint coordinates so scrollable scratch
  buffers can stay viewport-sized.
- Paint culling must preserve non-visual paint side effects. Flex can skip
  pure offscreen child paint, but selectable subtrees still need paint to
  refresh their full screen-space anchors even when `visibleBounds` is null.
- Keep M3.7 internals private for launch. Public API growth should be driven by
  stable examples, package integrations, and demo-app pain, not by exposing
  whichever helper shape happened to unlock the first performance slices.
- Widget implementation render objects should be public only when app authors
  can use them independently. If the render object depends on a private element
  callback, keep the widget API public and the render implementation private.
- Editable-text, rich-text selection, and scrollbar render objects are
  implementation-owned because they carry widget-specific state and callbacks.
  Keep their app-facing surface at the widget/controller level until a real
  package integration proves a lower-level contract.
- Diagnostic DTOs are not automatically production API. Keep frame-counter
  evidence behind `fleury_test.dart` unless app authors need a stable runtime
  metrics contract.
- Root replacement should stay simple and explicit: preserve state on
  compatible updates, remount on incompatible updates, and require callers to
  keep the returned root element when the identity changes.
- Core viewport/list controllers are app-facing state, not just render plumbing.
  Keep their final read state available for diagnostics, but treat mutation after
  disposal as lifecycle misuse so stale callbacks cannot silently move selection
  or scroll offsets after unmount.

## Risks And Open Questions

- Layout caching and the first paint-only split are now present, but
  conservative paint-to-layout invalidation may still leave performance on the
  table in unaudited widget-package render objects until scenario evidence
  justifies moving each setter.
- Paint-only audits can become unsafe if they ignore intrinsic-size or
  layout-derived paint state. Keep adding focused layout-stat regression tests
  whenever a render-object setter moves from `markNeedsPaint` to
  `markNeedsPaintOnly`.
- Render islands may split the framework if semantics and focus are not
  mandatory.
- Benchmark fixtures can become misleading if they do not resemble real apps.
- Post-MVP public render-island APIs may still be valuable, but only after
  external package authors need hooks that the current widget/render-object
  subclassing and `fleury_test` diagnostics cannot satisfy.

## Acceptance Evidence

- [Scenario benchmark lab](../scenario-benchmark-lab.md).
- [Scenario benchmark runner](../../../packages/fleury/benchmark/scenario_benchmarks.dart).
- [Benchmark README](../../../packages/fleury/benchmark/README.md).
- [Core Phase 1 baseline](../../../packages/fleury/benchmark/results/phase1-core-2026-05-31.json).
- [Text editing Phase 2 baseline](../../../packages/fleury/benchmark/results/phase2-text-editing-2026-06-01.json).
- [Layout Dirtiness Phase 2 baseline](../../../packages/fleury/benchmark/results/phase2-layout-dirtiness-2026-06-01.json).
- [Layout Dirtiness viewport paint baseline](../../../packages/fleury/benchmark/results/phase2-layout-dirtiness-viewport-paint-2026-06-02.json).
- [Widgets scenario benchmark runner](../../../packages/fleury_widgets/benchmark/scenario_benchmarks.dart).
- [Widgets Phase 1 baseline](../../../packages/fleury_widgets/benchmark/results/phase1-widgets-2026-05-31.json).
- [Streaming Markdown Phase 2 baseline](../../../packages/fleury_widgets/benchmark/results/phase2-streaming-markdown-2026-06-01.json).
- [Dashboard Update Phase 2 baseline](../../../packages/fleury_widgets/benchmark/results/phase2-dashboard-update-2026-06-01.json).
- [Widgets Resize Storm baseline](../../../packages/fleury_widgets/benchmark/results/phase2-resize-storm-2026-06-01.json).
- [Demo-app scenario benchmark runner](../../../packages/fleury_example_console/benchmark/scenario_benchmarks.dart).
- [Paint-only invalidation tests](../../../packages/fleury_widgets/test/paint_only_invalidation_test.dart).
- [RenderText tests](../../../packages/fleury/test/rendering/render_text_test.dart).
- [RenderFlex tests](../../../packages/fleury/test/rendering/render_flex_test.dart).
- [Table render object](../../../packages/fleury_widgets/lib/src/table.dart).
- [Table tests](../../../packages/fleury_widgets/test/table_test.dart).
- [Demo-app journey baseline](../../../packages/fleury_example_console/benchmark/results/phase2-demo-app-journey-2026-06-01.json).
- [DataTable render island](../../../packages/fleury_widgets/lib/src/data_table.dart).
- [DataTable tests](../../../packages/fleury_widgets/test/data_table_test.dart).
- [Debug frame events](../../../packages/fleury/lib/src/debug/debug_events.dart).
- [Render object layout dirtiness](../../../packages/fleury/lib/src/rendering/render_object.dart).
- [Render object layout tests](../../../packages/fleury/test/rendering/render_object_test.dart).
- [Performance API boundary tests](../../../packages/fleury/test/rendering/performance_api_boundary_test.dart).
- [CellBuffer tests](../../../packages/fleury/test/rendering/cell_buffer_test.dart).
- [ScrollView tests](../../../packages/fleury/test/widgets/scroll_view_test.dart).
- [ScrollView selection probe tests](../../../packages/fleury/test/widgets/selection/scrollview_selection_probe_test.dart).
- [Scroll bounds tests](../../../packages/fleury/test/widgets/selection/scroll_bounds_test.dart).
- [Selection auto-scroll tests](../../../packages/fleury/test/widgets/selection/auto_scroll_test.dart).
- [Debug panel](../../../packages/fleury/lib/src/debug/debug_panel.dart).
- [Runtime frame emission](../../../packages/fleury/lib/src/runtime/run_tui.dart).
- [Repaint-boundary debug stats](../../../packages/fleury/lib/src/rendering/render_repaint_boundary.dart).
- [Debug inspector tests](../../../packages/fleury/test/debug/debug_shell_test.dart).
- [Runtime debug event tests](../../../packages/fleury/test/runtime/run_tui_test.dart).
- [Debug capture tests](../../../packages/fleury/test/debug/debug_capture_test.dart).
