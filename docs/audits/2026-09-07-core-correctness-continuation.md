# TUI and reactive lifecycle correctness continuation

Baseline: `944f7fb71e9b99ec6644b797ecbb1d4b6ecc09b8`, refreshed main after
#226. This extends the [first lifecycle pass](2026-09-07-core-correctness.md)
in PR #227. The user's original dirty worktree was not modified.

## Method and scope

The continuation examined common TUI and reactive framework failure modes:
fragmented input and modifiers, dependency/provider replacement, focus
ownership and modal boundaries, synchronous listener reentrancy, and editing
transaction ordering. It also inspected async builder replacement,
notification removal, frame scheduling, and keyboard sequence dispatch.
Those inspections are not exhaustive correctness claims.

The next unexhausted areas are held keyboard-sequence input across focus
changes, observer-triggered sequence timeout/cancellation, and ownership of
multi-event IME/paste streams when their destination changes. These are
investigation candidates, not additional confirmed findings in this pass.

Each retained fix has a failing reproduction against main, local source
review, and passing affected-suite coverage before the next change. The
continuation adds 15 tests: 14 fail against main; malformed-input recovery is
an existing-behavior control. Combined with the first pass, the PR adds 31
regression/control cases, including 27 defect reproductions against main.

## C4: Legacy Alt plus Unicode becomes ordinary text

The parser recognized ESC-prefixed Alt shortcuts only for ASCII. For `Alt+é`,
`Alt+中`, or `Alt+🙂`, it discarded ESC and emitted `TextInputEvent`, allowing
the character to be inserted into a field instead of reaching the shortcut
lane. The modifier now belongs to the entire UTF-8 scalar and survives split
reads and idle flushes once UTF-8 has begun. Lone ESC retains its existing
ambiguity timeout.

Tests cover all read boundaries for two-, three-, and four-byte characters,
truncated EOF, and recovery after malformed input. EOF preserves Alt on
replacement scalars; the next ordinary character never inherits the modifier.
All 120 parser tests passed after local review of decoder reset paths.

## C5: Focus ownership does not follow the provider

A manager could accept a node attached to another manager. Separately,
replacing `FocusManagerScope.manager` while retaining the same child left
controls, ancestor key detectors, focus traps, and exclusion bookkeeping
attached to the old manager. The new manager could have no usable controls
or no registered modal frontier.

Input eligibility now requires ownership by the queried manager and a
mounted element. Focus nodes and markers observe the existing identity-only
provider and transfer registration on replacement. Ordinary focus movement
does not repeat that ownership work. Rebinding preserves the activation order
of already-open sibling traps; unmount still releases the new registration.

All six new cases fail on main. Tests exercise replacement before and after
old-manager disposal, actual key dispatch, cross-session rejection, exclusion
notifications, trap transfer, and sibling activation order. The 246-test
focused integration run includes navigation, modal traversal, global-key
reparenting, key dispatch, and error containment.

## C6: Reentrant model listeners truncate paste transactions

`TextPasteDriver` invoked the model's synchronous edit notification before
recording transaction progress. A listener starting another paste could
replace the active session; the older invocation then cleared that newer
session or applied its own completion state. Reproductions lost the final
characters of the replacement paste. A further local review exposed a paste
arriving while a finish callback had itself started another paste.

Transaction bookkeeping now precedes model notification. The driver checks
its generation after edit callbacks, so retired invocations cannot clear a
replacement session. An incoming paste finishes accepted tails created during
the handoff before taking ownership itself. This retains the existing growing
batch policy and its linear-copying performance assertion.

Four regressions fail on main, covering the first step, a scheduled step,
explicit finish, and nested finish handoff. They assert complete payloads,
inactive final progress, and one undo transaction per paste. The shared driver
and both text controls passed 139 affected tests.

## Combined qualification

- The full `dart tool/fleury_dev.dart check` passed: **5,567 tests**, including
  534 web tests and 64 integration tests, with two existing skips. Package
  analyses and browser/dart2js smoke also passed.
- An earlier run failed the unchanged grapheme-scan timing ratio assertion
  under concurrent suite load (1,187 microseconds versus 136 microseconds;
  threshold 6x). The isolated nine-test suite and an unchanged full rerun
  passed. The failed attempt is retained and excluded from final qualification;
  no source, baseline, or threshold was changed to resolve it.
- The browser JavaScript remains **401,255 bytes, byte-identical to main**.
  Its regenerated source fingerprint is `f364e3c24abce927`.
- All **eight fast gates**, the **native terminal wire gate**, and the
  **live serve wire gate** passed. The latter covers dashboard, log, counter,
  and closed-loop input. Wire timing axes remain informational; no new
  performance gain is claimed.

Final qualification results and exact source/log hashes are recorded in
[the continuation evidence manifest](evidence/2026-09-07-core-correctness-continuation.json).
The full contributor check, eight fast gates, terminal wire gate, and live
serve gate all exited zero on the combined PR source.

The generated client is rebuilt from the final source. No benchmark baseline
or tolerance is changed. This is local review and automated qualification;
independent review, attended terminal/accessibility walkthroughs, and a
long-session memory soak remain separate evidence.
