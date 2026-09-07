# Showcase-driven controller correctness

This follows the showcase workaround audit on `e40d9b95` in PR #227, based on
main `944f7fb7`. The inspection covered app samples, the developer console,
and live documentation examples. The concrete controller defect and finance
reproductions were checked against that original source before qualification.

## Chosen contract

`DataTableController.update` accepts optional row count, column count, and
selection coordinates. It applies the complete state before notifying
listeners. A table uses the same operation when mounting, rebuilding, or
changing controllers. Dimension-only changes notify; unchanged updates are
silent. An empty call preserves a constructor-supplied selection before mount.

This fixes the demonstrated invalid intermediate state: shrinking a 5-by-3
table to 1-by-1 previously notified listeners with selection `(0, 2)` and old
column count 3 before correcting it to `(0, 0)` and column count 1. A detail
listener using the new application data could read a removed cell.

Applications replace their data before calling `update`, and supply the same
counts as the next table widget. That also lets them select a newly added row
before the next frame. Existing single-coordinate setters continue clamping
against the controller's current dimensions. Explicit selection in `update`
collapses the range; a dimensions-only update clamps both range endpoints.
Nested listener updates remain authoritative because the outer operation does
not write state after notification.

The alternatives considered were a second controlled-selection mode on the
widget, automatic key remapping, and deferred pending-selection requests.
Each introduces additional ownership or timing semantics. The small controller
operation fits the existing imperative API and leaves stable identity and the
fallback after filtering with the application. No per-rebuild key search or
new selection model is needed. Suppressing notifications alone would hide
legitimate changes without resolving selection against the new row count.

## Application simplification

Finance computes the intended transaction ID, replaces its rows and selected
ID, then calls `update(rowCount: ..., selectedIndex: ...)` in the same state
change. It no longer primes against the old row count, suppresses listeners
across a frame, or queues a post-frame correction. Tests cover shrinking,
expanding while retaining a transaction outside the old index range, and
several filters including an empty result before any intervening frame.

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

The change adds 16 cases: 11 controller tests, two finance regressions, and
three browser chart tests. Controller coverage includes initial mount,
replacement, simultaneous dimension changes, range endpoints, dimension-only
notification, selecting new rows, empty data, listener reentrancy, no-op calls,
and disposal. Local review found and corrected the pre-mount empty-update
case; its failing first-implementation probe was retained in the local logs.

The original source fails the mixed-dimension observer probe and both new
finance timing regressions. The new `update` API tests establish its added
contract; they are not presented as historical regressions of an API that did
not exist. The archived baseline evidence is alongside this document.

The full contributor run (`dart tool/fleury_dev.dart check`) passed 5,582 tests,
including 534 web tests and 64 integration tests, with two existing skips.
Package analyses and the browser/dart2js smoke passed. The last pre-mount
no-op regression and the complete gallery suite were added during review;
after those corrections, the full widget suite passed 1,211 tests and the exact
expanded browser gate passed 41 tests. These counts overlap and are not added
together. Final affected-file analysis passed; widget analysis reports four
existing informational lints in untouched files.

The broader gallery run initially found three stale tests, all independently
reproduced at the unchanged baseline: references to removed FormWizard demos,
old FormField semantic wrappers, and old form validation/status text and
checkbox defaults. The tests now assert the current controls' semantics,
visible validation errors, invalid-field attributes, successful typed submit,
and actual checkbox state. All 36 gallery tests pass and now run in the normal
PR gate instead of silently falling outside its selected browser files.

[Qualification evidence](evidence/2026-09-07-showcase-correctness.json) records
the source-file and local-log hashes. The
[baseline log](evidence/2026-09-07-showcase-correctness-baseline.log) separates
controller/finance reproductions from the existing gallery assertion failures.
The previous core pass's performance and wire-gate receipts remain scoped to
`e40d9b95`; they were not rerun or relabeled for this showcase change.
