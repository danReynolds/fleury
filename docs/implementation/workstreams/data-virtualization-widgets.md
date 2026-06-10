# Workstream: Data Virtualization And Widgets

## Purpose

Make Fleury an obvious choice for dense developer tools by providing serious
tables, trees, logs, markdown, code, JSON, diff, file, and search surfaces.

## Current State

- `fleury_widgets` includes higher-level widgets such as table, tree,
  markdown text, menus, controls, charts, picker widgets, dialogs, and
  progress widgets.
- Gauge, Sparkline, BarChart, Histogram, Heatmap, CalendarHeatmap, and
  LineChart now expose chart semantics and accessibility/fallback state instead
  of being visual-only render surfaces. Interactive LineChart also exposes
  semantic focus/increment/decrement cursor actions, and the demo app Overview
  telemetry strip exercises gauge, trend, and bar-chart semantics. `Digits`
  exposes its underlying value as semantic text so large clock/counter glyphs
  remain inspectable. Generic `Canvas` drawings now support opt-in image/chart
  semantics with marker and logical-bounds fallback state while staying silent
  by default under higher-level widgets.
- The composition-based `Table` remains the simple aligned-grid widget for
  small data surfaces. Its table and body-cell semantic actions now reuse the
  same focus, row-selection, and `onSelect` paths as keyboard interaction.
- A first `DataTable` render-island widget now exists with visible-row
  virtualization, stable row keys, keyboard selection, fixed headers, sort/filter
  semantic metadata, sanitized/clipped cell painting, selected-row TSV/CSV
  export, Ctrl+C selected-row copy, controller-backed cell-selection mode,
  rectangular cell/range export and copy, range-aware semantics, and mouse hit
  selection over the rendered viewport.
- First-party `buildDataTableRowOrder` helpers now cover app-owned filtering and
  sorting without forcing the render island to materialize every row as a
  widget.
- `SB.3 DataTable 100k Rows` now runs from the `fleury_widgets` scenario
  benchmark runner and records timing, visible range, selected key, ANSI bytes,
  semantic node count, selected-row copy latency, RSS delta, and cell-builder
  call counts.
- `SB.4 LogRegion Tailing And Scrollback` now runs from the `fleury_widgets`
  scenario benchmark runner and records timing for fixture build, mount, first
  render, append bursts, scrollback jumps, scroll-to-tail, selected-entry copy,
  filter queries, semantic query, ANSI bytes, semantic node count, visible
  range, copied bytes, sanitizing fixture rows, and RSS delta.
- `LogRegionSearchIndex` now provides an optional app-owned retained-log search
  index for large typeahead workloads. The indexed `SB.4` follow-up records
  search-index build cost separately from query, append, copy, and semantic
  timing so the widget hot path does not hide indexing policy.
- `LogRegionSearchIndex` now also supports cooperative task-owned build and
  refresh paths via `TaskContext`/`TaskYieldPolicy`. The refreshed `SB.4`
  cooperative baseline proves progress and event-loop yield checkpoints on the
  same 100k-entry retained-log fixture.
- The demo app now includes an Indexed Logs screen that builds and refreshes a
  retained-log index through `TaskController` / `TaskYieldPolicy`, filters the
  retained rows through `LogRegionSearchIndex`, and renders the results with
  `LogRegion` semantics.
- `SB.5 Streaming Markdown` now runs from the `fleury_widgets` scenario
  benchmark runner and records per-chunk parse, frame, and combined update
  timing while streaming 1000 markdown chunks with headings, lists, table-like
  rows, code fences, links, unsafe OSC payloads, unsafe link schemes,
  selected-block copy, semantic markdown/link nodes, and unsafe-frame checks.
- `SB.11 TreeTable Hierarchy Filter And Copy` now runs from the
  `fleury_widgets` scenario benchmark runner and records timing for 100k-leaf
  hierarchy fixture build, mount, first render, branch expansion, page/jump
  navigation, filtered descendant reveal, selected-row copy, semantic query,
  ANSI bytes, visible ranges, tree node count, sanitizer fixture rows, and RSS
  delta.
- The demo app Runs screen now uses `DataTable` for stable-key row semantics,
  keyboard selection, filtering, activation, and selected-row copy.
- The demo app Transcript screen now uses `LogRegion`, an app-authored
  structured log/transcript region in `fleury_widgets` with sanitized
  rendering, sanitized search/filter and export helpers, tail-following
  selection, copy/export helpers, clipboard policy reports, lazy visible-row
  mounting, and semantic log/list-item state.
- `SearchPanel` now provides a reusable search-result surface with a query
  field, cached `SearchResultIndex` ranking, custom matcher injection, lazy
  result rows, activation, selected-result copy, sanitized search/render/copy,
  and semantic result state.
- The demo app now includes a Global Search screen that uses app-owned
  debounced search results with `DebouncedTaskController`, ranks those results
  with `SearchResultIndex`, and renders them through `SearchPanel`; semantic
  row activation navigates into the matching app surface.
- `FileBrowser` now provides a Phase 2 filesystem browsing surface with lazy
  rows, semantic tree/tree-item state, hidden-file policy, query filtering,
  directory navigation, file activation, selected-path copy/export, source/view
  index separation, and sanitizer-safe display/search/semantics/clipboard text.
- Base `Tree` now exposes semantic tree/tree-item nodes, depth/branch/expanded
  state, stable positional row keys, selected state/actions, and sanitizer-safe
  labels as the tree-side foundation for TreeTable.
- `TreeTable` now provides explicit-key hierarchical data tables with
  DataTable-compatible columns/export formats, expansion/collapse navigation,
  filtered descendant discovery, optional `TreeTableSearchIndex` acceleration,
  lazy visible rows, semantic tree rows plus table cells, selected-row
  copy/export, and sanitizer-safe rendering/search/semantics/export.
- `TreeTableSearchIndex` now has a cooperative `TaskController` build path for
  large hierarchies. The refreshed `SB.11` cooperative baseline records task
  event/progress evidence while preserving the indexed exact-token query path.
- `TreeTableSearchIndex` now supports `TreeTableFilterMode.prefixToken` through
  sorted token lookup, giving large hierarchy UIs an indexed typeahead path for
  IDs, paths, and symbols without making fuzzy subsequence search an implicit
  heavyweight service.
- `DataTableController` and `TreeTableController` now follow the launch
  controller lifecycle contract: final selection/range/expansion state remains
  readable after teardown, but stale table-selection and tree-expansion
  mutations throw explicit lifecycle errors.
- `TableController` and `FileBrowserController` now follow the same lifecycle
  contract for simpler data/file surfaces: final selection state remains
  readable after teardown, but stale row, jump, and file-browser selection
  mutations fail explicitly.
- `FormController` and `FormWizardController` now follow the same lifecycle
  contract for production form workflows: final values, errors, submitted
  state, validation state, and wizard step remain readable after teardown,
  post-dispose form/step mutations fail explicitly, and late async validation
  results are ignored after disposal.
- The demo app now includes a Tree screen that exercises TreeTable through app
  navigation, a screen-local focus command, semantic tree/table-cell state,
  activation into the transcript, and selected-row copy.
- `JsonView` now provides a Phase 2 structured payload surface with parsed or
  already-materialized JSON documents, collapsible object/array rows, JSON
  pointer/path state, subtree or line copy, parse-error semantics, safe
  string/key display, lazy visible-row mounting, and semantic JSON/node state.
- The demo app now includes a Payload screen that exercises `JsonView` through
  app navigation, a screen-local focus command, safe display of terminal-control
  payloads, selected-node copy, and transcript feedback.
- `DiffView` now provides a Phase 2 unified-diff surface with parsed
  file/hunk/add/delete/context rows, old/new line numbers, file path state,
  selected-line or selected-hunk copy, safe display/copy of terminal-control
  payloads, lazy visible-row mounting, and semantic diff/line state.
- The demo app now includes a Changes screen that exercises `DiffView` through
  app navigation, a screen-local focus command, safe display of terminal-control
  payloads, selected-hunk copy, and transcript feedback.
- `CodeView` now provides a Phase 2 source inspection surface with source-line
  classification, line-number rendering, indentation and source-shape counts,
  selected-line or whole-document copy, safe display/copy of terminal-control
  payloads, lazy visible-row mounting, and semantic code/line state.
- The demo app now includes a Source screen that exercises `CodeView` through
  app navigation, a screen-local focus command, safe display of terminal-control
  payloads, selected-line copy, and transcript feedback.
- `MarkdownView` now provides a Phase 2 document inspection surface with parsed
  Markdown rows, heading/list/link/code counts, visible URL fallback semantics,
  selected-block or whole-document copy, safe display/copy of terminal-control
  payloads, lazy visible-row mounting, and semantic markdown/block state.
- Developer-document controllers now follow the launch lifecycle contract:
  `CodeViewController`, `DiffViewController`, `JsonViewController`, and
  `MarkdownViewController` keep final selection/visible-range and JSON
  expansion state readable after teardown, while rejecting stale selection,
  jump, expand, collapse, and toggle mutations.
- The demo app now includes a Docs screen that exercises `MarkdownView`
  through app navigation, a screen-local focus command, safe display of
  terminal-control payloads, selected-block copy, link semantics, and transcript
  feedback.
- The full demo app test suite now passes with the Runs-screen `DataTable`,
  Transcript-screen `LogRegion`, Tree-screen `TreeTable`, and Payload-screen
  `JsonView`, Changes-screen `DiffView`, Source-screen `CodeView`, and
  Docs-screen `MarkdownView` in place.
- `FleuryWidgetTheme` now covers the first production-toolkit style defaults
  for data selection/separators/empty states, log severity rows, diff line
  kinds, CodeView line kinds, and JSON parse errors while keeping explicit
  widget styles authoritative.
- Core includes lazy list and scroll primitives.
- Data widgets are not yet a unified production data framework with semantics,
  virtualization, copy/export, search, sorting, and benchmark guarantees.

## Target Capabilities

- DataTable with virtualization, stable row keys, sorting, filtering/search,
  selection, fixed headers, copy, and semantic cells.
- TreeTable, FileBrowser, LogView/LogRegion, JsonView, DiffView, CodeView,
  MarkdownView, and SearchPanel.
- Large data sets and streaming data remain responsive.
- Data widgets expose semantic rows, cells, regions, selections, and actions.

## Milestone Checklist

- [x] DVW.1 Define DataTable v1 contract.
  - Intent: Make the first data widget a clear production win.
  - Acceptance: Contract covers row identity, column model, sort/filter,
    selection, focus, copy, semantics, virtualization, fixed headers, and
    benchmark scenarios.
  - Evidence:
    [DataTable API](../../../packages/fleury_widgets/lib/src/data_table.dart),
    [DataTable tests](../../../packages/fleury_widgets/test/data_table_test.dart),
    [DataTable scenario benchmark](../../../packages/fleury_widgets/benchmark/scenario_benchmarks.dart).
  - Notes: Initial contract covers columns, row count, cell builder, stable row
    key builder, selected-row controller, focus, keyboard selection, selected-row
    activation, fixed/flex widths, fixed header, sort/filter metadata,
    virtualized semantics, selected-row export, selected-row copy, and demo-app
    Runs-screen adoption. Final v1 contract adds row/cell selection mode,
    Shift-extended rectangular ranges, selected cell/range copy, rectangular
    export, and first-party row-order helpers for filtering/sorting.

- [x] DVW.2 Build DataTable v1 as semantic render island.
  - Intent: Handle large data without forcing every visible cell through
    normal widget composition.
  - Acceptance: 100k-row benchmark remains responsive and semantic queries
    expose rows, cells, sort state, selection, and actions.
  - Evidence:
    [DataTable render object](../../../packages/fleury_widgets/lib/src/data_table.dart),
    [DataTable tests](../../../packages/fleury_widgets/test/data_table_test.dart),
    [DataTable scenario benchmark](../../../packages/fleury_widgets/benchmark/scenario_benchmarks.dart).
  - Notes: The render object paints only visible body rows and the semantic
    contributor emits the header plus visible rows/cells with row keys, selected
    state, visible range, sort state, filter state, and copy action metadata.
    Full demo-app integration is now green. Cell mode highlights and exposes
    selected rectangular ranges without mounting per-cell widgets, while row
    mode preserves the original whole-row behavior. Semantic action handlers now
    let tests focus, select, activate, and copy the table or mounted visible
    rows/cells through the semantic graph. Mouse hit selection now maps
    terminal-cell coordinates back through the render-island viewport metrics:
    row-mode clicks select visible rows, and Shift-click in cell mode extends
    rectangular ranges without mounting per-cell widgets.

- [x] DVW.3 Define streaming view contracts.
  - Intent: Prepare for logs, markdown, code, diffs, and agent transcripts.
  - Acceptance: Contract covers append/update rate, backpressure, scroll
    anchoring, selection, search, copy, sanitization, and replay events.
  - Evidence:
    [LogRegion](../../../packages/fleury_widgets/lib/src/log_region.dart),
    [LogRegion tests](../../../packages/fleury_widgets/test/log_region_test.dart),
    [demo app Transcript screen](../../../packages/fleury_example_console/lib/fleury_example_console.dart),
    [SB.4 LogRegion benchmark](../../../packages/fleury_widgets/benchmark/scenario_benchmarks.dart),
    [SB.4 indexed LogRegion baseline](../../../packages/fleury_widgets/benchmark/results/phase2-logregion-indexed-2026-06-01.json),
    [SB.5 Streaming Markdown benchmark](../../../packages/fleury_widgets/benchmark/scenario_benchmarks.dart),
    [SB.5 Streaming Markdown baseline](../../../packages/fleury_widgets/benchmark/results/phase2-streaming-markdown-2026-06-01.json).
  - Notes: First slice covers app-authored logs/transcripts through
    `LogRegion`. It deliberately does not replace core `LogView`, which remains
    the runtime stdout/stderr capture view. The first benchmark baseline passes
    with 100k starting entries plus a 1000-entry append burst. Search/filter is
    source-entry based rather than mounted-row based, searches sanitized text,
    exposes source and filtered view indexes separately, and has benchmark
    pressure through `SB.4`. Semantic copy now works through both the log
    region and selected mounted row nodes, aggregate focus/navigation requests
    focus the backing list, and visible row activation focuses the region while
    selecting entries through `LogRegionController` and leaving follow-tail
    mode. The indexed `SB.4` follow-up adds optional `LogRegionSearchIndex`
    support:
    filter-query p95 moves from
    68785 us to 35979 us on the 100k-entry fixture, while index construction
    is measured explicitly at 319669 us p95 so apps can decide whether to
    build, debounce, or offload it. Streaming markdown now has a first pressure
    baseline through `SB.5`: the saved 1000-chunk run stays under the candidate
    update budget with full-document parse-on-append, so an incremental parser
    is deferred until larger documents, richer wrapping, or peer comparisons
    prove the need. DVW.3 is complete for the MVP; isolate/off-main indexing
    and incremental parsing remain measured future work.

- [x] DVW.4 Expand developer-tool widget suite.
  - Intent: Build the Phase 2 production toolkit.
  - Acceptance: LogView, JsonView, DiffView, CodeView, MarkdownView,
    TreeTable, FileBrowser, and SearchPanel meet semantics, keyboard,
    selection, and benchmark expectations.
  - Evidence:
    [LogRegion](../../../packages/fleury_widgets/lib/src/log_region.dart),
    [LogRegion tests](../../../packages/fleury_widgets/test/log_region_test.dart),
    [demo app Transcript usage](../../../packages/fleury_example_console/lib/fleury_example_console.dart),
    [LogRegion benchmark baseline](../../../packages/fleury_widgets/benchmark/results/phase2-logregion-2026-05-31.json),
    [SearchPanel](../../../packages/fleury_widgets/lib/src/search_panel.dart),
    [SearchPanel tests](../../../packages/fleury_widgets/test/search_panel_test.dart),
    [demo app Global Search usage](../../../packages/fleury_example_console/lib/fleury_example_console.dart),
    [demo app Global Search test](../../../packages/fleury_example_console/test/demo_console_test.dart),
    [demo app ranked-search baseline](../../../packages/fleury_example_console/benchmark/results/phase2-demo-app-ranked-search-2026-06-01.json),
    [FileBrowser](../../../packages/fleury_widgets/lib/src/file_browser.dart),
    [FileBrowser tests](../../../packages/fleury_widgets/test/file_browser_test.dart),
    [Tree](../../../packages/fleury_widgets/lib/src/tree.dart),
    [Tree tests](../../../packages/fleury_widgets/test/tree_test.dart),
    [TreeTable](../../../packages/fleury_widgets/lib/src/tree_table.dart),
    [TreeTable tests](../../../packages/fleury_widgets/test/tree_table_test.dart),
    [demo app Tree screen](../../../packages/fleury_example_console/lib/fleury_example_console.dart),
    [demo app Tree tests](../../../packages/fleury_example_console/test/demo_console_test.dart),
    [TreeTable benchmark baseline](../../../packages/fleury_widgets/benchmark/results/phase2-treetable-2026-06-01.json),
    [TreeTable index-hardening baseline](../../../packages/fleury_widgets/benchmark/results/phase2-treetable-index-2026-06-01.json),
    [JsonView](../../../packages/fleury_widgets/lib/src/json_view.dart),
    [JsonView tests](../../../packages/fleury_widgets/test/json_view_test.dart),
    [demo app Payload screen](../../../packages/fleury_example_console/lib/fleury_example_console.dart),
    [demo app Payload tests](../../../packages/fleury_example_console/test/demo_console_test.dart),
    [DiffView](../../../packages/fleury_widgets/lib/src/diff_view.dart),
    [DiffView tests](../../../packages/fleury_widgets/test/diff_view_test.dart),
    [PatchReview](../../../packages/fleury_widgets/lib/src/patch_review.dart),
    [PatchReview tests](../../../packages/fleury_widgets/test/patch_review_test.dart),
    [demo app Changes screen](../../../packages/fleury_example_console/lib/fleury_example_console.dart),
    [demo app Changes tests](../../../packages/fleury_example_console/test/demo_console_test.dart),
    [CodeView](../../../packages/fleury_widgets/lib/src/code_view.dart),
    [CodeView tests](../../../packages/fleury_widgets/test/code_view_test.dart),
    [demo app Source screen](../../../packages/fleury_example_console/lib/fleury_example_console.dart),
    [demo app Source tests](../../../packages/fleury_example_console/test/demo_console_test.dart),
    [MarkdownView](../../../packages/fleury_widgets/lib/src/markdown_text.dart),
    [MarkdownView tests](../../../packages/fleury_widgets/test/markdown_view_test.dart),
    [Streaming Markdown benchmark baseline](../../../packages/fleury_widgets/benchmark/results/phase2-streaming-markdown-2026-06-01.json),
    [demo app Docs screen](../../../packages/fleury_example_console/lib/fleury_example_console.dart),
    [demo app Docs tests](../../../packages/fleury_example_console/test/demo_console_test.dart).
  - Notes: `LogRegion` is the first Phase 2 developer-tool widget slice. Reuse
    its sanitized copy/export, aggregate focus/navigation, semantic row
    activation, and semantic-state shape for terminal output, diff/code, and
    process panels where it fits.
    `SearchPanel` is the first
    M2.3 search-result slice and follows the same source-index plus view-index
    callback pattern as `LogRegion`; semantic focus, selected-result copy, and
    selected-result activation now invoke the same callbacks as keyboard
    workflows. The demo app Global Search screen now proves the app-owned
    async/debounced result pattern without putting task policy inside
    `SearchPanel`: `DebouncedTaskController` builds the result list,
    `SearchResultIndex` gives the reusable exact/prefix/contains/fuzzy ranking
    policy, and the widget owns query input, list semantics, copy, and
    activation. The accessibility/fallback projection now preserves
    `SearchPanel` and `LogRegion` result/entry totals, filtered counts,
    selected index/category/source, log filter details, copy-prefix policy,
    and source/view row positions so prompt fallback and debug artifacts can
    describe data-heavy production widgets without scraping rendered rows.
    `FileBrowser`
    is the second M2.3 slice and
    keeps legacy `FilePicker` intact while adding a semantic, sanitizer-safe
    browser surface for production filesystem tools. Base `Tree` is now
    semantic/sanitizer-safe enough to act as the hierarchy contract underneath a
    future TreeTable. `TreeTable` now completes the named M2.3 widget surface
    at v0, and the demo app now puts it under app-kernel, semantics,
    activation, and copy pressure. Semantic actions now cover Tree focus/open/
    activate, TreeTable open/activate/copy, and FileBrowser open/copy using the
    same visible-row semantics as their keyboard workflows. `SB.11` now adds
    benchmark pressure:
    `TreeTableSearchIndex` gives 100k-leaf exact-token descendant reveal a
    4074 us p95 query path while measuring index construction separately.
    Current index-hardening slice keeps the same public API but drops private
    per-entry map copies and regex tokenization; the saved 5-iteration
    follow-up baseline measures index-build p95 at 1040888 us on the same
    100k-leaf fixture. Prefix-token filtering is now the indexed typeahead
    mode for durable identifiers; fuzzy contains/subsequence search remains an
    explicit scan until larger demo workflows justify n-gram indexing,
    isolate-backed search, or cached flattened-row policy.
    `JsonView` is the first structured developer-document view in M2.2. It
    deliberately shares tree/list interaction mechanics but has first-party JSON
    semantic roles because path, parse-error, type, and subtree-copy behavior
    should be stable for tests, inspectors, and future adapters.
    `DiffView` is the second structured developer-document view in M2.2 and
    gets first-party semantic roles because file path, hunk, old/new line, row
    activation, and copy mode are core developer-tool concepts rather than
    generic list state.
    `CodeView` is the third structured developer-document view in M2.2 and
    covers source-line meaning, line numbers, source-shape counts, indentation,
    sanitized code semantics, semantic line activation, and copy/export before
    richer syntax highlighting or symbol indexing.
    `PatchReview` is the protocol-neutral review layer above `DiffView`: it adds
    patch/file status, per-file stats, selected-file activation, and safe
    file-summary copy while reusing `DiffView` for line and hunk semantics.
    `MarkdownView` closes the named M2.2 document-view surface by keeping
    lightweight `MarkdownText` for inline rendering while adding a navigable,
    copyable, semantic document viewer for help text, model output, and
    developer documentation. Visible markdown blocks now support semantic
    activation through the existing `MarkdownViewController` before selected
    block copy. `SB.5` now puts streaming markdown under
    parse/update/frame, copy, semantic-link, and unsafe-frame benchmark
    pressure.
    Semantic action handlers now route `LogRegion` focus/row activation/copy,
    `JsonView` branch open/copy, `DiffView` focus/line activation/copy,
    `CodeView` focus/line activation/copy, and `MarkdownView` focus/block
    activation/copy through the same controller and sanitized copy/export paths
    used by keyboard workflows.
    The M2.5 component-theme slice now gives these production widgets shared
    theme defaults for repeated severity, data-state, code-line, diff-line,
    JSON-error, and Markdown-block styles without changing their semantic
    contracts or copy/export behavior. DVW.4 is complete for the MVP: the
    first production toolkit covers logs, search, files, tree tables, JSON,
    diffs, code, Markdown, patch review, demo-app adoption, and benchmark or
    targeted test evidence. Future widgets should be opened as concrete
    demo-app or product-driven additions.

## Implementation Notes

- The visible developer win is "I can build a real tool without building a
  table framework first."
- Data widgets need terminal capability and security policies because they
  often display untrusted subprocess, file, markdown, or network content.
- [RFC 0013: Capability and security contract](../../rfcs/0013-capability-security-contract.md)
  is the policy source for sanitized logs, markdown links, restricted ANSI,
  image escapes, copy/export redaction, malformed Unicode, and huge-line
  behavior.
- Virtualization must not erase semantic accessibility or testability.
- The demo-app scenario uses the Runs screen as the first table forcing case:
  filtering, selection, copy, stable row identity, large deterministic fixture,
  and semantic row/cell queries.
- Do not put `DataTable` benchmarks in the core `fleury` package runner unless
  the runner moves: `fleury_widgets` depends on `fleury`, so `fleury` cannot also
  depend on `fleury_widgets`.
- Selected-row copy intentionally exports only the selected row first. It proves
  clipboard policy, sanitization, semantics, and virtualized export without
  committing prematurely to cell/range selection UX.
- Cell/range copy is now a second selection mode rather than a replacement for
  row selection. This keeps row-first command tables simple while making dense
  inspection/data tools possible.
- Data-heavy widget controllers should keep diagnostic read state after
  disposal, but every app-facing mutation path must reject stale callbacks after
  unmount. This includes direct `DataTableController` row/cell selection and
  `TreeTableController` selection/expand/collapse operations above its wrapped
  `ListController`.
- Form controllers have the same read-after-dispose rule, but async validation
  needs extra generation invalidation: late validator futures may resolve for
  already-started callers, but they must not restore validating state or write
  stale errors after a form or wizard has unmounted.
- Sorting/filtering helpers return source-row order. Apps can map that order
  into `rowKeyBuilder`/`cellBuilder`, keeping the render island focused on
  visible rows and avoiding hidden full-widget materialization.
- `LogRegion` uses `ListView.builder` rather than eager row mounting. Tests
  that inspect rendered log rows need a render pass before checking row text or
  row semantics; this keeps app logs scalable. Command palettes now follow the
  same visible-row semantic discipline after SB.8 proved 1000-command palettes
  need bounded row mounting too.
- `LogRegionController` defaults to tail-following initial selection by
  clamping an intentionally large starting index once the underlying list knows
  its item count. This makes large log regions open at the tail rather than at
  row zero.
- Core `LogView` remains the captured-output view installed by `runTui`.
  `LogRegion` is the app-facing structured log/transcript widget, avoiding a
  public-name collision for users importing both core and widgets packages.
- `SB.4` uses `controller.visibleRange` after render for benchmark correctness
  because the aggregate `Semantics` wrapper state is built before layout writes
  the latest visible range back to the `ListController`. Row semantics remain
  visible-row accurate after render.
- `LogRegion` filter/copy semantics keep source-entry indexes and filtered view
  indexes separate. Copy callbacks return both so apps can preserve durable log
  identity while still describing the current filtered selection.
- `LogRegion` row activation is focus-plus-selection-only. Activating a visible
  row focuses the backing list, leaves follow-tail, and selects the filtered
  view index; it does not parse, execute, acknowledge, or otherwise mutate the
  underlying log entry.
- `LogRegion` searches sanitized message text, plus id/source/severity labels.
  This prevents hidden OSC/CSI payloads from becoming searchable/copyable
  content while still allowing visible text search. The default query path
  remains an optimized linear scan for small/simple retained logs; large
  typeahead workloads can opt into `LogRegionSearchIndex`, with construction
  cost intentionally visible to the app rather than hidden inside the widget
  hot path.
- `SearchPanel` is intentionally result-surface-first rather than an async
  search engine. Apps own corpus construction, remote calls, debounce, worker,
  and indexing policy, while `SearchResultIndex` provides the shared
  small/medium result ranking model for exact, prefix, contains, and fuzzy
  matches.
- `FileBrowser` intentionally copies sanitized paths by default. File names can
  carry terminal controls; activation callbacks can use the structured entry,
  but rendered, searched, semantic, and clipboard/export text must stay safe.
- `Tree` uses positional row keys for its semantic v0 because `TreeNode` has no
  explicit id. TreeTable should add explicit keys for durable dynamic data.
- `TreeTable` uses an explicit node-key model from the start. It does not wrap
  `DataTable` directly because tree item semantics and branch navigation are
  first-order behavior; it still reuses DataTable columns and export formats so
  flat and hierarchical tables feel related.
- Document-view controllers wrap lazy list state for scalable rendering. Their
  public selection/jump/branch APIs should guard disposal at the document-view
  level so app code gets stable controller-specific lifecycle errors rather
  than lower-level `ListController` failures.
- Simple data/file controllers should follow the same public lifecycle rule as
  larger render islands: read final state after disposal for diagnostics, but
  reject stale selection or jump mutation after unmount.
- `SB.11` records the first large-hierarchy evidence for `TreeTable`: 100k
  leaves plus 100 branch nodes, `TreeTableSearchIndex` build p95 1851310 us,
  exact-token filter-query p95 4074 us, selected-row copy p95 8002 us,
  semantic-query p95 1979 us, and page-move p95 11640 us. This validates the
  explicit lookup path. Prefix-token filtering now covers indexed ID/path/
  symbol typeahead; broad fuzzy typeahead, worker indexing, and cache policy
  remain evidence-driven follow-ups.
- `JsonView` sanitizes string values and object keys before display, semantics,
  and copy/export. JSON escaping alone is not enough because active OSC/CSI/DCS
  payloads can otherwise become visible escaped secrets; the widget collapses
  terminal-control payloads before JSON encoding selected subtrees.
- `DiffView` parses unified diffs as a structured document instead of styling
  raw text. That preserves file path, hunk index, old/new line numbers,
  additions/deletions, selected-hunk copy, and semantic testability while still
  sanitizing terminal controls before display, semantics, and copy/export.
- `CodeView` deliberately starts with whole-line classification rather than a
  token highlighter. This keeps the first source-inspection surface stable,
  safe, semantic, and copyable before adding language grammars, symbol maps, or
  folding.
- `MarkdownView` deliberately sits beside `MarkdownText`. `MarkdownText`
  remains the small inline renderer; `MarkdownView` owns document navigation,
  copy/export, aggregate block/link counts, visible-link fallback semantics,
  semantic block selection, and sanitizer-safe row state.

## Risks And Open Questions

- Generic data abstractions can become too abstract before real widgets prove
  them.
- Copy/export behavior may conflict with virtualized off-screen data.
- Hidden-column copy policy and multi-range selection are unresolved beyond
  v1.
- Markdown/code/diff rendering can dominate performance if parsed too often.
- Lazy log rows mean off-screen log semantics are intentionally absent until
  rendered; higher-level search/export APIs must operate from source entries,
  not mounted row widgets.
- Interactive filtering over very large retained logs now has an optional
  index, and index construction now has cooperative task-owned build/refresh
  paths. This gives apps progress, cancellation, and event-loop yield points,
  but it is still not off-main execution. Launch-grade indexing still needs a
  decision on eager, incremental, isolate/worker-backed, or cached construction
  for long-lived logs.
- SearchPanel default matching now has a first-party cached ranking model for
  small/medium result sets. Very large or remote result sets still need
  app-owned indexing, streaming, debounce, worker, or paging policy rather than
  hiding those costs in the widget hot path.
- FileBrowser currently lists one directory level at a time. TreeTable or a
  future expanded file tree should decide whether filesystem browsing needs a
  shared hierarchical row model rather than duplicating tree flattening logic.
- Tree semantic row keys are positional and can shift when sibling order
  changes. This is acceptable for static/simple trees but not enough for
  TreeTable's dynamic-data identity story.
- TreeTable is currently widget-composed with lazy visible rows rather than a
  render island. `TreeTableSearchIndex` makes exact-token lookup fast enough
  for 100k-leaf ID/path/symbol workflows, and cooperative index construction
  now gives task progress/cancellation/yield checkpoints. Before broader launch
  claims, decide whether fuzzy fallback scans need a richer query index,
  isolate-backed execution, cached flattened rows, or a dedicated TreeTable
  render island using the current API as the contract.

## Acceptance Evidence

- [DataTable API](../../../packages/fleury_widgets/lib/src/data_table.dart).
- [DataTable semantic/virtualization tests](../../../packages/fleury_widgets/test/data_table_test.dart).
- [SB.3 DataTable 100k Rows benchmark](../../../packages/fleury_widgets/benchmark/scenario_benchmarks.dart).
- [Demo app Runs screen](../../../packages/fleury_example_console/lib/fleury_example_console.dart).
- [Demo app Runs tests](../../../packages/fleury_example_console/test/demo_console_test.dart).
- [LogRegion API](../../../packages/fleury_widgets/lib/src/log_region.dart).
- [LogRegion tests](../../../packages/fleury_widgets/test/log_region_test.dart).
- [Demo app Transcript screen](../../../packages/fleury_example_console/lib/fleury_example_console.dart).
- [SB.4 LogRegion benchmark](../../../packages/fleury_widgets/benchmark/scenario_benchmarks.dart).
- [SB.4 LogRegion baseline](../../../packages/fleury_widgets/benchmark/results/phase2-logregion-2026-05-31.json).
- [SB.4 indexed LogRegion baseline](../../../packages/fleury_widgets/benchmark/results/phase2-logregion-indexed-2026-06-01.json).
- [SB.4 cooperative LogRegion index baseline](../../../packages/fleury_widgets/benchmark/results/phase2-logregion-cooperative-index-2026-06-01.json).
- [SearchPanel API](../../../packages/fleury_widgets/lib/src/search_panel.dart).
- [SearchPanel tests](../../../packages/fleury_widgets/test/search_panel_test.dart).
- [Demo app Global Search screen](../../../packages/fleury_example_console/lib/fleury_example_console.dart).
- [Demo app Global Search test](../../../packages/fleury_example_console/test/demo_console_test.dart).
- [Demo app ranked-search baseline](../../../packages/fleury_example_console/benchmark/results/phase2-demo-app-ranked-search-2026-06-01.json).
- [Demo app Indexed Logs screen](../../../packages/fleury_example_console/lib/fleury_example_console.dart).
- [Demo app Indexed Logs test](../../../packages/fleury_example_console/test/demo_console_test.dart).
- [FileBrowser API](../../../packages/fleury_widgets/lib/src/file_browser.dart).
- [FileBrowser tests](../../../packages/fleury_widgets/test/file_browser_test.dart).
- [Tree API](../../../packages/fleury_widgets/lib/src/tree.dart).
- [Tree semantic tests](../../../packages/fleury_widgets/test/tree_test.dart).
- [TreeTable API](../../../packages/fleury_widgets/lib/src/tree_table.dart).
- [TreeTable tests](../../../packages/fleury_widgets/test/tree_table_test.dart).
- [Demo app Tree screen](../../../packages/fleury_example_console/lib/fleury_example_console.dart).
- [Demo app TreeTable regression](../../../packages/fleury_example_console/test/demo_console_test.dart).
- [SB.11 TreeTable benchmark](../../../packages/fleury_widgets/benchmark/scenario_benchmarks.dart).
- [SB.11 TreeTable baseline](../../../packages/fleury_widgets/benchmark/results/phase2-treetable-2026-06-01.json).
- [SB.11 cooperative TreeTable index baseline](../../../packages/fleury_widgets/benchmark/results/phase2-treetable-cooperative-index-2026-06-01.json).
- [JsonView API](../../../packages/fleury_widgets/lib/src/json_view.dart).
- [JsonView tests](../../../packages/fleury_widgets/test/json_view_test.dart).
- [Demo app Payload screen](../../../packages/fleury_example_console/lib/fleury_example_console.dart).
- [Demo app Payload regression](../../../packages/fleury_example_console/test/demo_console_test.dart).
- [DiffView API](../../../packages/fleury_widgets/lib/src/diff_view.dart).
- [DiffView tests](../../../packages/fleury_widgets/test/diff_view_test.dart).
- [Demo app Changes screen](../../../packages/fleury_example_console/lib/fleury_example_console.dart).
- [Demo app Changes regression](../../../packages/fleury_example_console/test/demo_console_test.dart).
- [CodeView API](../../../packages/fleury_widgets/lib/src/code_view.dart).
- [CodeView tests](../../../packages/fleury_widgets/test/code_view_test.dart).
- [Demo app Source screen](../../../packages/fleury_example_console/lib/fleury_example_console.dart).
- [Demo app Source regression](../../../packages/fleury_example_console/test/demo_console_test.dart).
- [MarkdownView API](../../../packages/fleury_widgets/lib/src/markdown_text.dart).
- [MarkdownView tests](../../../packages/fleury_widgets/test/markdown_view_test.dart).
- [SB.5 Streaming Markdown baseline](../../../packages/fleury_widgets/benchmark/results/phase2-streaming-markdown-2026-06-01.json).
- [Demo app Docs screen](../../../packages/fleury_example_console/lib/fleury_example_console.dart).
- [Demo app Docs regression](../../../packages/fleury_example_console/test/demo_console_test.dart).
- Full demo app suite passes with `DataTable`, `LogRegion`, `TreeTable`,
  `JsonView`, `DiffView`, `CodeView`, and `MarkdownView` adoption under Dart
  3.12.1.
- Pending later hidden-column copy policy, multi-range selection, fuzzy
  TreeTable filtering hardening, off-thread index construction policy, and
  document-view hardening such as Markdown filtering/typeahead, richer syntax,
  folding, or indexing when demo workflows demand them.
