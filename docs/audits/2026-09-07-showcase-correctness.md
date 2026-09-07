# Showcase-driven table correctness and selection DX

This follows the showcase workaround audit on `e40d9b95` in PR #227, based on
main `944f7fb7`. The inspection covered app samples, the developer console,
and live documentation examples. The concrete controller defect was reproduced
against that original source. The selection DX revision follows `7ee0acc6`.

## Chosen contract

Dimensions belong to `DataTable`. Applications that own row selection supply
`selectedIndex` and `onSelectionChanged` alongside their rows:

```dart
DataTable(
  rowCount: rows.length,
  columns: columns,
  cellBuilder: (row, column) => rows[row][column] ?? '',
  selectedIndex: selectedRow,
  onSelectionChanged: (row) => setState(() => selectedRow = row),
)
```

Updating rows and the desired selection in one app state change is sufficient.
The widget resolves selection against the new dimensions when it rebuilds.
It clamps out-of-range indices and uses zero as the empty-table sentinel.
Configuration changes do not echo through `onSelectionChanged`; navigation
requests do. The app accepts a request by rebuilding with the new index.
`onSelect` remains row activation, separate from cursor movement.

The existing controller remains available for imperative row, cell, and range
selection. An assertion rejects supplying both a controller and `selectedIndex`.
Without either, the table manages selection internally. Controller listeners
still receive dimension changes, after both dimensions and all selection
coordinates have been committed. Unchanged rebuilds remain silent. Nested
listener selection changes are not overwritten after notification.

This fixes the demonstrated invalid intermediate state: shrinking a 5-by-3
table to 1-by-1 previously notified listeners with selection `(0, 2)` and old
column count 3 before correcting it to `(0, 0)` and column count 1. A detail
listener using the new application data could read a removed cell.

The dimension operation is private. Having applications repeat widget counts
in a controller update created a second source of truth. Declarative row
selection removes that duplication. Stable row identity and fallback selection
after filtering remain app decisions; the framework does not search all row
keys on every rebuild or queue selection corrections for a later frame.

## Application simplification

Finance keeps the selected transaction ID in app state, resolves it against
filtered rows, and passes the corresponding index to the table. Its table
controller, listener, disposal, and manual count updates are removed. Tests
cover shrinking, expanding while retaining a transaction outside the old index
range, and several filters including an empty result before a single rebuild.
Keyboard interactions complete a frame between requests so the responsive
`LayoutBuilder` can deliver the accepted selection.

Two other audit findings were obsolete workarounds on the qualified paths:

- The console's explicit navigation refresh after every `setState` was
  removed. Navigator already reconciles updated home props. Its 25 existing
  workflow tests cover state updates, navigation, commands, and transcripts.
- Live charts start their ticker immediately instead of waiting 250 ms.
  Three browser regressions await real presented frames and verify changing
  visual DOM through the production rAF scheduler. They are included in the
  normal repository check, alongside the guide and full gallery browser tests.

Sprite autofocus, game tick-delta policy, application keyboard ownership,
simulated requests, and post-frame palette opening were not established as
framework defects by this audit and were left outside this change.

## Review and validation

The showcase pass now adds 24 cases: seven controller tests, 12 declarative
selection tests, two finance regressions, and three browser chart tests.
Local source and interaction review covered atomic clamping, empty data,
controller replacement, notification reentrancy, accepted and rejected input,
activation and copy, pointer and semantic selection, ownership transitions,
and extended cell ranges through layout-time rebuilds.

Review found that restoring a controlled selection during a child's build
could discard its requested range before a parent `LayoutBuilder` delivered
the accepted row. Rendering now uses the app-owned row while retaining the
requested range for that acknowledgement. Each new interaction starts from
the accepted selection, so rejected requests do not leak into activation or
copy. The layout-time range and rejected-request tests cover those boundaries.

Final DX qualification passed:

- Full widget suite: **1,219 passed**, one existing skip.
- All samples: **94 passed**, including all 13 finance cases.
- Documentation/API checks: **78 passed**.
- Expanded Chrome gate: **41 passed**, including finance and real-rAF charts.
- Widget and sample analysis passed; four existing informational widget lints
  remain in untouched files. Patch whitespace checks passed.

These are affected-surface checks, not a new full repository or performance run.
[DX qualification evidence](evidence/2026-09-07-table-selection-dx.json) records
the exact source and local-log hashes.

The earlier full contributor run passed 5,582 tests, with final follow-up runs
of 1,211 widget tests and 41 browser tests before this API revision. Those
receipts and the original baseline failures remain historical evidence for
`7ee0acc6` in the [original qualification record](evidence/2026-09-07-showcase-correctness.json)
and [baseline log](evidence/2026-09-07-showcase-correctness-baseline.log).
The archived finance probes exercise the superseded controller-update contract.
The gallery run also found three stale tests, reproduced at the unchanged
baseline; the corrected gallery now participates in the normal PR gate.
Earlier core performance and wire receipts remain scoped to `e40d9b95`.
