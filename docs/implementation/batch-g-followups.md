# Batch G disposition

Status: 2026-09-29. This is the authoritative disposition of the pasted
“Batch G — needs Dan's input” report, including fixes merged in #282/#283 and
the remaining framework work based on main `13367b0f`. It records decisions and
scoped evidence, not a claim that every terminal or application is qualified.
No item below is waiting for Dan to choose an architecture.

## Behavioral fixes

| Issue | Resolution and regression evidence |
| --- | --- |
| Programmatic/autofocus reveal and half-visible ListView rows | FocusManager schedules the existing ancestor-aware reveal after layout. Pointer focus opts out. Eager and lazy ListView expose conservative limits from mounted, laid-out rows; no scan of offscreen rows. Tests cover autofocus, explicit requests, pointer stability and partial-row traversal. |
| Editing while a segmented paste arrives | `TextEditingController.beginPaste()` returns an anchored `TextEditingPaste`. The tail follows edits at the original insertion point, preserves a moved caret, and remains one paste undo alongside separate intervening edits. Undoing the paste cancels it. Reset/disposal drop pending history. Actual parser/widget tests cover fragmented UTF-8 and escape sequences, focus changes, deletion, repeated characters, undo/redo and reentrant edits. |
| Offscreen layout box contains visible overflow | Cached `RenderObject.paintOverflow` conservatively includes presented descendants and clips. Flex consults it before culling. Overflow remains visible when its parent box scrolls out of view; shrinking the overflow invalidates the cache. Custom render objects painting outside their layout must override `computePaintOverflow` and invalidate paint when those bounds change. |
| Lazy rows depend on the whole list's focus context | Each mounted lazy row gets a small builder element and its own context. A 10,000-row probe changes unrelated focus six times with zero row builds; changing that row's own focus rebuilds it. |
| ASCII borders appear as semantic text | Border cells carry decoration provenance through copies, clipping, cache replay, restyling and clearing. Ordinary Cells gain no field. Literal `+`, `-`, and `\|` remain text. The existing frame diff separately records provenance changes so visually identical border/text replacements refresh coverage without extra terminal output. |
| Floating content loses local inherited scopes | `OverlayEntry(owner: context)` links live scope lookup to its logical owner. Theme, commands and app models follow updates and GlobalKey moves. Floating descendants dispose before owner-provided models. Foreign/unmounted owners fail before insertion; an owner removed before the first floating build also removes its entry. First-party floating widgets use this ownership; their separate theme snapshots and forwarding listeners are removed. |
| Mutable logs, chart points and canvas painters remain stale | Updating a widget explicitly refreshes its data, including same-list/same-painter mutations. Reusing the same widget instance retains caching. Sparkline and Heatmap also track prior dimensions; mutable heatmap labels invalidate layout. LineChart also clamps its cursor after a range shrinks; BarChart tracks prior length for intrinsic layout. Tests cover mutable points, same-length log replacement, painter state and bar-list changes. |
| Command predicates polled on idle frames | Optional `AppCommand.availability` subscribes hints and semantic presentation to a Listenable. Observable predicates are cached for presentation until notification; dispatch always rechecks. Existing predicates without a source retain polling. Twenty idle frames evaluate no observable predicates; enable/disable updates hints and prevents stale invocation. |
| Unbounded DataTable silently builds an impractical layout | Default DataTable requires bounded height with an actionable debug assertion naming Expanded/SizedBox. `shrinkWrap: true` explicitly requests content height. A bounded 100,000-row regression constructs only visible cells. |
| Locale-specific keypad decimal disagrees with text/key-up | Associated Kitty text learns the printable decimal and the matching key-up retains its down identity. Flag-only/SS3 input uses `keypadDecimal`, defaulting to period; native drivers also read `FLEURY_KEYPAD_DECIMAL`. Invalid associated text is rejected before learning. |
| Missing public raw-input test path | `FleuryTester.sendTerminalBytes` owns a persistent InputParser, accepts fragmented reads, and dispatches complete events. `flush: true` explicitly resolves parser ambiguity. An injected `terminalParser` configures parser behavior. It does not emulate terminal negotiation or native driver timing. |

## Compatibility and authoring

These APIs are additive. Keypad aliases are deprecated but retained, including
the existing SpecialKey enum slots and wire version. Old keypad selectors match
canonical logical events only at the known matching keypad position; they do
not capture number-row keys. Use `KeyPosition` for physical keypad bindings or
ordinary logical characters/Enter/operators when location is irrelevant.

Unbounded DataTable layouts need an explicit choice:

```dart
Expanded(child: DataTable(
  rowCount: rows.length, columns: columns, cellBuilder: buildCell,
)) // bounded viewport
DataTable(
  rowCount: rows.length, columns: columns, cellBuilder: buildCell,
  shrinkWrap: true,
) // content height
```

For commands whose availability changes with a model:

```dart
AppCommand(
  id: const CommandId('save'),
  title: 'Save',
  availability: document,
  enabled: (_) => document.isDirty,
  run: (_) => save(),
)
```

The source must notify whenever an availability predicate's inputs change.
Omit it for an arbitrary predicate that cannot promise that contract. Invocation
remains a fresh check in both cases.

Use `OverlayEntry(owner: context, builder: ...)` for local floating content.
Omitting owner intentionally uses the host overlay's scopes for app-global
chrome. Rendering, input ancestry and ancestor-State lookup remain with the
physical overlay; only inherited scope lookup follows the logical owner.

Mutable chart/log/canvas inputs may be changed in place and supplied to a new
widget. For an unchanged expensive chart, retain the widget instance across
unrelated parent rebuilds. No O(n) comparison or revision counter is required.
Explicit `LogRegionSearchIndex.refresh` remains that index's invalidation API.

Bounded text controllers keep atomic paste admission through `paste`; streamed
transactions reject a non-null edit policy. The widgets retain their atomic
fallback for those controllers. Programmatic focus normally reveals after the
next frame; `requestFocus(reveal: false)` is available when reveal is unwanted.

## Performance decisions

- Keep causal event scheduling. Coalescing every event in an event-loop turn
  would place frames behind already-due timers. The report did not reproduce a
  correctness failure requiring that latency tradeoff.
- Paste history shares a pending tail only after an intervening edit creates
  history. Each retained snapshot is updated once, on undo or completion.
  Ordinary streams retain no additional history-tail text. The controller's
  existing 200-entry history cap still applies. A stress probe with a 64 KiB
  document, 200 intervening edits and sixteen 2 KiB tails reduced delivery from
  about 418 ms to 3 ms locally; completion was about 68 ms while other checks
  were running. That bounded worst-case history-copy cost remains explicit.
- New chart widgets refresh mutable data. A 10,000-point interactive chart
  measured roughly 2.6–5.5 ms per explicit refresh on this machine across runs;
  reusing the same widget measured 0.07–0.59 ms. These are diagnostic wall-clock
  samples, not portable performance promises.
- Lazy rows add one Element per mounted row, not per collection item. Overlay
  ownership adds listener/dependency work only for owned entries. Overflow
  metadata is cached and calculated only when culling needs it. Decoration
  changes are collected during the existing buffer comparison.

Reproduce the explicit cost probes with
`cd profiling && dart run bin/batch_g_cost_probe.dart`. The probes are diagnostic;
correctness and deterministic counters remain the merge gates.

### Allocation measurement

The old Dart 3.12.2 allocation-profile “accumulated” fields are a heap census,
not churn. A retained-then-discarded canary reported 4096 then 0 without reset.
See the [VM implementation](https://github.com/dart-lang/sdk/blob/3.12.2/runtime/vm/class_table.cc#L309-L388).
The historical `allocation_counter_probe.dart` preserves that reproduction.

Both allocation gates now count traced object creations in bounded synchronous
work windows using a dedicated UserTag. This measures **objects, not bytes**:
the public allocation-trace protocol has no per-sample allocation size. Classes
with no library metadata, VM-service classes and file-based harness classes are
excluded. The frame gate records all included classes and `package:fleury`
separately; the input gate traces and gates framework classes only. The service
client runs in a separate process so profiler traffic cannot exhaust the traced
VM's buffer. Each gate measures one bounded, tagged work window. The mandatory
`--profile-startup` flag preserves the recorded prefix when the buffer fills;
missing end guards then fail the run instead of permitting overwritten middle
samples to appear as a lower count. Trace samples are consumed independently of
buffer order.

`profiling/test/alloc_tools_test.dart` checks retained/discarded canaries,
collection inside the window, intentionally exhausted buffers, and independent
failure of both frame-allocation axes, input dispatch counts, and rejection of
an unsafe ring-buffer configuration. The canary forces objects to escape JIT
elimination. Launch manually with:

```sh
cd profiling
dart --deterministic --profiler --max-profile-depth=2 --profile-startup \
  --enable-vm-service=0 --disable-service-auth-codes \
  bin/allocation_trace_probe.dart
```

The baseline unit changes deliberately; old byte JSON is rejected. New
baselines come from the merged framework with the same new meter, followed by
a comparison of the changed framework: both measure 315.6 total / 197.0 framework
objects per frame and 6.0 framework objects per key on Dart 3.12.2. No regression
tolerance is relaxed.
This is a workload-specific allocation-count gate, not total heap bytes or an
unprofiled latency measurement. The VM's private `_collectAllGarbage` RPC is used
only by the SDK qualification canary.

## Resolved without a public break or architectural rewrite

- **CellBuffer.copyFrom/copyRectFrom:** retain the supported APIs. Internal
  compositing already uses `compositeRectFrom`; removal would add migration cost
  without correcting behavior.
- **GlobalKey/LayoutBuilder:** current moving/reclaiming regressions pass. No
  duplicate-key failure was reproduced from the report; retain the existing
  ownership model rather than introduce another build scope.
- **RenderText/RichText line breaker:** duplication is maintenance work, not a
  reproduced wrap defect. Preserve the optimized paths and existing Unicode,
  indentation, whitespace and span-style regressions. Consolidation is not a
  prerequisite for closing the reported bugs.
- **initState containment / takeException:** keep the current explicit failure
  and testing contracts. These were alternative API suggestions, not new bugs.
- **Idle-debug and reviewer-notes timing flakes:** both passed three local runs
  with four CPU workers active (about ten seconds per combined run). No failure
  was reproduced, so deadlines and assertions are unchanged. This is bounded
  stress evidence, not proof against every loaded machine; a future recurrence
  needs its process/frame trace rather than an assumed shared cause.

## Previously merged

#282 fixed repeated-key semantic IDs, Tabs body-navigation isolation, guarded
browser async errors, and tester frame pumping while semantic/command handlers
wait. Command nodes await their actual result; tests explicitly answer dialogs.

#283 added FileBrowser's parent-directory action, sticky paste claimant ownership,
early POSIX report disable, shared Flex/ScrollView compositing, and lazy semantics
plus view-change notifications across all affected collections. It also added
the declining-palette regression and fixed PTY suspend/backpressure checks.
`Semantics.stateBuilder`/`stateListenable` and `ListController.viewChanges` remain
the supported collection contract; see
[Built for agents](../agents-and-semantics.md#live-semantic-state-without-rebuilding-content).

## Qualification

Local validation includes 3,003 affected core tests (one skip), the full 1,462-test
widget suite, server regressions, six allocation-meter qualification tests,
wire/scenario gates and all eight fast performance gates (29.5 seconds locally).
The final PR records the final checks after cleanup.

The served-wire fixture now compiles its scenario kernel once during setup and
retains JIT execution for every session. This removes repeated source compiler
startup from the unchanged ten-second app-attachment deadline; failed captures
retain server diagnostics. All four live-socket scenarios passed three runs each.
This qualifies the socket/input path, not cold source-compilation latency. Hosted CI supplements those checks;
passing local tests does not replace live terminal/SSH, Windows or device testing.
