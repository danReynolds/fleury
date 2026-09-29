# Batch G follow-ups

Status: review draft, 2026-09-29. Based on main `34e6b68b` and the pasted
"Batch G — needs Dan's input" report. This is the current disposition of that
report, not a release qualification checklist. Public exports and the wire
version are unchanged.

## Implemented in this batch

| Issue | Result | Evidence |
| --- | --- | --- |
| FileBrowser cannot leave an empty/unreadable directory with mouse or semantics | A parent-directory button occupies the existing blank separator row. File indices and total height stay unchanged. | Empty/missing-directory semantic activation and mouse regressions; 26 FileBrowser tests. |
| Paste tail follows a focus move into another field | The dispatcher retains the first accepting claimant. Detached/replaced/ineligible owners cannot spill their tail into a new field; orphaned segments are ignored. | Actual TextInput/TextArea controllers retain one undo across a focus change; claimant removal/replacement and mismatched IDs covered. |
| Terminal reports remain enabled during asynchronous teardown | Enqueue mouse/focus/paste disables before the runtime's first teardown await, and at driver restore/suspend/handoff entry. Keep protocol-stack restoration ordered, leave a borrowed terminal alone, and never drain typeahead. | Lifecycle/suspend/inline suites, synchronous shutdown and reentry tests. This narrows the window; it cannot retract reports already in flight over SSH. |
| Flex and ScrollView use inconsistent scratch compositors | Both use `CellBuffer.compositeRectFrom` for cells and images. A wide glyph at the right clip becomes `?`, preserving the adjacent sibling. | 26 Flex/ScrollView tests; paint and wire gates pass. |
| Palette command can decline after the palette closes | Added the missing regression. Availability depends on the palette still being open, so the row passes its check and the registry declines after the pop. The press reports unsupported and never runs the command. | Palette suite passes; no production change needed. |
| Collection metrics rebuild rows | **CodeView pilot only:** update semantics in a small NotifierBuilder and retain the content widget. Public notifications, selection, explicit refresh and controller subclass dispatch remain intact. | 20 wheel steps: 180 redundant source-row reads before, 0 after. Aggregate/row semantics and copy behavior pass. |

The CodeView pilot introduces an explicitly private bridge between the first-party
packages, plus notification classification in its controller. It is here as a
concrete alternative for the collection decision below; it does not fix the other
13 wrappers.

## Performance and DX decisions

### Allocation measurement

This is a measurement defect, not evidence that input allocation got cheaper.
Dart 3.12.2's `ClassTable::AllocationProfilePrintJSON` iterates the heap and writes
the **same** current object count/size to `instancesAccumulated`/`accumulatedSize`
and `instancesCurrent`/`bytesCurrent`. Reset updates a timestamp; it does not
provide cumulative churn counters. See the
[Dart VM implementation](https://github.com/dart-lang/sdk/blob/3.12.2/runtime/vm/class_table.cc#L309-L388)
and [service handler](https://github.com/dart-lang/sdk/blob/3.12.2/runtime/vm/service.cc#L4453-L4482).

The unchanged input gate measured 215.4 B/key in one run. A diagnostic run that
collected before the final reading measured 15.8 B/key: KeyEvent went from 1113
to 5 instances, InputBatch from 1065 to 0, and _PressRecord from 1110 to 1. The
production workload did not change. Another ordinary gate run reported 105.0
B/key. These are heap-timing effects, not improvements to lock into a baseline.

Both `input-alloc-gate` and `alloc-gate` use this API. A standalone SDK canary is
included, independent of either workload:

```sh
cd profiling
dart --deterministic --enable-vm-service=0 --disable-service-auth-codes \
  bin/allocation_counter_probe.dart
```

The canary retains 4096 objects, reads their accumulated count, releases them,
and collects again without a reset. Locally it reported **4096 then 0** on Dart
3.12.2. Exit 64 means the cumulative-count premise
failed. It does not change existing CI or baselines.

**Recommendation:** replace the measurement before rebaselining. Validate any
replacement with retained/discarded canaries and planted allocations, including
GC inside the measured window. Per-class allocation tracing is an attribution
candidate, but it changes profiling overhead and requires checking trace-buffer
loss and byte accounting before calling it a deterministic gate. Making current
gates fail closed is honest but would turn CI red until the replacement lands.
That workflow cost is a decision, not something hidden by loosening tolerances.

### Collection semantics rollout

Affected remaining wrappers: DiffView, FileBrowser, LogRegion, JsonView,
MessageList, TaskGraph, PatchReview, FileMentionPicker, TraceTimeline, TreeTable,
ContextPanel, ConversationNavigator and SearchPanel. Tree already isolates its
semantic updates; its zero-row-rebuild regression passes.

- **Keep the public API unchanged:** extend the demonstrated CodeView split one
  widget at a time. Preserve selection/filter/expansion notifications and test
  viewport semantics plus explicit refresh. Cost: more wrapper and notification
  plumbing, and a private dependency between packages.
- **Add lazy semantic state:** a callback evaluated when semantics are read can
  remove the metrics-driven wrapper rebuilds with less repeated code. Cost: a
  public API addition and a documented callback lifecycle/purity contract.

Recommendation: choose the intended semantic-state API before spreading the
private bridge. The CodeView pilot makes the benefit and maintenance cost
reviewable. The attempted bulk structural rewrite was rejected by automatic
approval review and was not applied; only this narrower, tested change exists.

### Input latency and editing behavior

| Decision | Benefit | Cost / recommendation |
| --- | --- | --- |
| Coalesce all events in one event-loop turn | One render for a burst of N events | Frames yield behind already-due timers. Keep current causal scheduling until this latency tradeoff is accepted. |
| Move the caret or edit the original field while paste is still arriving | Keep a single paste transaction and insertion anchor | Current `finish()` drains accepted chunks, but later segments can start a second undo at the new caret. Sticky focus ownership alone does not solve this. Choose anchor transformation versus deferring intervening edits; deferring edits changes responsiveness, and buffering the whole paste changes memory behavior. |
| Locale-specific keypad decimal | Key meaning agrees with committed text | Associated text can identify comma vs period on capable terminals; flag-1-only input cannot supply the locale. Choose a layout/configuration contract and preserve matching key-up identity. |

### Public contracts and maintenance

| Item | Implication | Recommendation |
| --- | --- | --- |
| Unbounded DataTable height | A new debug failure breaks currently accepted layouts | Decide on the bounded-height contract and provide an error naming the required SizedBox/Expanded placement. |
| Mutating LogRegion/chart/canvas collections in place | Identity caching can freeze existing apps; validating every element costs O(n) | Choose immutable/new-list or revision ownership explicitly before adding identity-based skips or assertions. Include LineSeries points in the decision. |
| Remove obsolete keypad KeyCode values | Source break plus enum-index wire change | Coordinate removal with a wire-version bump and replacements for aliases, labels and positional twins. |
| Remove CellBuffer.copyFrom/copyRectFrom | Public API break despite few internal callers | Do not remove merely as cleanup in this batch. |
| FleuryTester.sendTerminalBytes | Additive public test API | Decide its supported parser/driver semantics before exporting the existing test helper. |
| Observable command availability | Removes reported 25–70 microseconds/frame predicate polling at 50–100 commands | Requires a new invalidation contract; existing arbitrary predicates must not become stale. Those timings are from the report, not newly measured here. |
| Flutter-style takeException / different initState error containment | Changes test and failure semantics | Alternatives from the earlier review, not new reproduced bugs. Keep the existing contract in this batch. |

### Structural work requiring performance or behavior qualification

- **Overflow paint culling:** an offscreen layout box can contain visible overflow.
  A conservative paint-bounds contract lets Flex retain culling; simply painting
  every offscreen subtree risks a substantial regression. Clipping Stack by
  default changes visible application behavior. Measure the metadata approach
  against deep/offscreen content before choosing.
- **ASCII border semantics:** decoration provenance must survive cache replay,
  clipping, compositing, clearing and overwrites. Per-cell metadata changes
  buffer memory and hot loops; guessing from `+`, `-`, `|` would hide real text.
- **Overlay scope ownership:** Theme is forwarded, but commands/layout and other
  inherited scopes need logical owner parenting. A portal-style implementation
  changes lifetime/dependency ownership; test moves, disposal and inherited
  updates before extending the widget contract.
- **Lazy-row Focus.of:** rows built with the ListView element still subscribe to
  the broad focus scope. A per-Focus inherited dependency can narrow rebuilding,
  but adds scope/lifetime bookkeeping and needs a large-list focus-change probe.

## Verified or still open

- **Already merged in #282:** repeated-key semantic IDs, Tabs body-navigation
  isolation, guarded browser async errors, and tester frame pumping while
  semantic/command handlers wait. Command nodes still await their actual result;
  a test must explicitly answer a dialog it opened.
- **GlobalKey/LayoutBuilder:** existing regressions for moving into/out of a
  LayoutBuilder and reclaiming a child while its builder stays mounted pass on
  this base. No duplicate-GlobalKey failure reproduced by those cases. Do not
  impose a new build-scope architecture based only on the older report; retain
  any additional failing tree as a distinct reproducer.
- **Focus reveal / ListView half-visible items:** still require targeted work.
  PR #278 is still open at `bc0f12e6` and owns adjacent native/focus/reveal changes; reconcile against it
  before introducing another reveal path. Programmatic/autofocus reveal must
  distinguish pointer focus so a click does not move content under the pointer.
- **Shared RenderText/RichText line breaker:** consolidation remains useful;
  this report names duplication rather than a newly reproduced wrapping error.
- **Two timing flakes:** the idle-debug test passed alone in 6 seconds and the
  reviewer-notes capture test passed alone in 2 seconds. This does not clear
  their reported CPU-load flakiness. Preserve a failing loaded-run trace before
  changing deadlines. The reviewer-notes path uses passive diagnose with no
  frame timing, so do not assume its root cause matches the debug timer test.

## Local validation

- 98 input/paste tests; real fields, ownership invalidation and one-step undo.
- 87 terminal lifecycle/suspend/inline tests, including synchronous reentry.
- 124 list/runtime/reparenting tests; 26 Flex/ScrollView tests.
- 84 FileBrowser/CodeView/palette/focus-scope tests.
- Targeted analysis clean; formatting and `git diff --check` clean.
- Paint, runtime, wire, scenario, semantics, selection, image and bundle gates
  pass. The allocation gates exited green but are **unqualified**, as above.
- No baseline or tolerance was changed. These checks do not replace live
  terminal/SSH qualification or a valid allocation-churn measurement.

The initial fast-gate run caught a missing import while the CodeView pilot was
being edited. The affected gates were rerun successfully after correction.
Optional hosted CI is not the local development feedback loop for this draft.
