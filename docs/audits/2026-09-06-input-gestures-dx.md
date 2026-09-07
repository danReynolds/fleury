# Input and gestures DX audit

Date: 2026-09-06. Audited main: `c8fb31242022a24ac1195efde343e5921df2409b`
(testing guide/API PR #221). Worktree: `/tmp/fleury-input-gestures-dx`, branch
`codex/input-gestures-dx`. The findings below record the pre-implementation
baseline. The approved changes are now implemented on top of main `bb2e10b8`;
see [implementation and validation](2026-09-06-input-gestures-implementation.md).
Retained probes intentionally describe the old API and behavior.

## Recommendation

Keep `GestureDetector`, `MouseRegion`, ordinary controls, and explicit terminal
mouse opt-in. Improve pointer ownership and lifecycle, make text editing work
with the mouse, and give position-aware callbacks consistent local coordinates.
Then teach the result through three small, complete interactive examples.

The problems below are observable framework behavior, not just missing prose.
The existing 14-test pointer suite passes while these gaps remain.

## 1. Make focus and editing follow the click

### Confirmed findings

- **Browser click-to-focus is broken.** `InputDispatcher._dispatchMouse` starts
  its smallest-area search with `1 << 62`. That evaluates to zero in dart2js,
  so no positive-area candidate can win. The assembled `mountApp` Chrome probe
  routes a left down at cell `(2, 1)` inside the second field's `20x1` rectangle.
  The node is focusable and the click is not absorbed, but focus stays on the
  first field. The same fixture succeeds in the VM tester, both bare and inside
  `FleuryApp`. This explains the earlier guide observation more precisely than
  attributing it to TextInput lacking its own focus callback.
- **Caret placement and editing selection are absent.** In the VM, clicking
  column 2 of `abcdef` focuses TextInput but keeps its caret at offset 6.
  Typing `X` produces `abcdefX`. TextArea similarly stays at the end of
  `first\nsecond`, and a drag leaves its editing selection collapsed.
- **Focus can go behind the clicked control.** An overlapping front detector
  receives its tap, but the equally sized focus node behind it wins focus.
  The focus search uses rectangle area and attachment order, independently
  of the pointer router's visual hit order.
- **Focus ignores partial clipping.** A tall focusable inside a viewport at
  rows 2–4 receives a click at row 0, where it is clipped out. `FocusNode.rect`
  checks for some visibility, then returns the full bounds; the dispatcher
  tests against those full bounds.
- **Empty TextInput has an intrinsic one-cell hit area** under loose width
  constraints. TextArea fills bounded width. A fixed-width parent already
  solves this, as used by Preferences; this did not cause that demo's browser
  focus failure. Decide a consistent field-sizing contract explicitly.

### Proposed change

Use the presented render hit path for focus and pointer actions, respecting
clipping, front-to-back order, focus traps, and ExcludeFocus. Remove the numeric
sentinel. Ensure the harness and both production hosts exercise the same rule.

Have TextInput and TextArea own click-to-caret, drag selection, Shift-click
extension, and word/line selection. Use the renderers' actual text geometry:
horizontal/vertical scrolling, grapheme boundaries, wide cells, obscured input,
and read-only/disabled policies. Keep editing selections independent from the
app's selection/copy layer. Set the intended caret before focus presentation can
scroll the field to its old caret.

For sizing, prefer filling a finite available width and intrinsic width when
unbounded, consistent with TextArea; validate Row/Column layouts before changing
the default. This is a deliberate layout decision, separate from the focus fix.

Evidence: `packages/fleury/lib/src/runtime/input_dispatcher.dart:309`,
`packages/fleury/lib/src/widgets/focus.dart:204`,
`packages/fleury/lib/src/widgets/text_input.dart:1467`,
`packages/fleury/lib/src/widgets/text_area.dart:638`.

## 2. Finish or cancel every gesture reliably

### Confirmed findings

- A control setting `pressed = true` in `onTapDown` and clearing it in
  `onTapUp` stays pressed after release outside. `onTapUp` is sent to the
  release location, not the press owner; there is no tap-cancel callback.
- `onDragUpdate` alone misses the first movement. Down → one move → up calls
  no update at all. Every drag consumer must duplicate work in onDragStart.
- A left down followed by a right up fires the left tap. The release's button
  is not checked against the captured button.
- `onTapDown` runs for every mouse button. A right click on RangeSlider changes
  `(20, 80)` to `(20, 53)` in the probe.
- The browser's `pointercancel` clears only DomInputSource's state. It emits
  nothing to the core router, leaving a custom widget pressed; a later up can
  still activate the canceled tap. The existing browser cancellation test checks
  source event translation, not downstream gesture cleanup.
- Browser `pointerleave` restores the CSS cursor but emits no surface-exit
  event. MouseRegion remains hovered after leaving the embedded surface.

### Proposed change

Define one captured sequence owner with explicit completion and cancellation.
Pair gesture-level tap down with tap up or tap cancel; pair drag start with end
or cancel. Deliver the first actual movement to onDragUpdate, even when no
onDragStart was supplied. Keep the original press position and button available.

Propagate pointer cancellation and surface leave from the browser. Handle known
authority loss in native hosts (terminal focus loss, suspend/handoff, shutdown)
without invoking unmounted widgets. Check multiple-button/chorded input and
release-outside behavior at the host boundary. Browser coordinate clamping
currently maps outside points back onto the edge cell; review that mapping so
capture retains genuine outside positions and release-outside can cancel.

Make the tap family primary-button gestures; keep raw pointer-down reporting
explicit for controls that need all buttons. Migrate RangeSlider, Scrollbar,
SelectionArea, list/table consumers, and their tests together.

Evidence: `packages/fleury/lib/src/widgets/pointer.dart:309`, `:359`, `:385`;
`packages/fleury_web/lib/src/input/dom_input_source.dart:631`, `:721`;
`packages/fleury_web/lib/src/metrics/dom_cell_metrics.dart:183`.

## 3. Make position-aware callbacks easy to compose

### Confirmed findings

The API mixes no-argument callbacks, `(col, row)`, `(col, row, modifiers)`, and
PointerDownDetails. Only down has a details object. Positions are all global.
A detector inset by 10 columns reports down at 11, start at 12, and update at 14;
a component expecting its own coordinates must discover and subtract its origin.

RangeSlider and Scrollbar maintain private render-geometry handles for this
conversion. The guide's `_dividerCol = col` example hides this requirement and
also hides the difference between a press origin and the first movement.

### Proposed public shape (illustrative, not implemented)

Keep zero-argument `onTap` for the common action case. Position-aware callbacks
take details with `localPosition`, `globalPosition`, `button`, and `modifiers`;
drag details also carry `delta` and the press origin. Use CellOffset/cell units.
Consolidate the legacy down variants instead of adding another parallel family.

```dart
GestureDetector(
  onDragUpdate: (details) => setState(() {
    dividerCol = (dividerCol + details.delta.col).clamp(8, 40);
  }),
  child: handle,
)
```

This component can move inside padding or a panel without changing its handler.
Exact type names and the compatibility migration belong in implementation review.

Peer references support these ingredients: [Flutter's DragUpdateDetails](https://api.flutter.dev/flutter/gestures/DragUpdateDetails-class.html)
has local/global positions and delta; [Textual mouse events](https://textual.textualize.io/api/events/#textual.events.MouseEvent)
provide relative/screen offsets, delta, and modifiers. [Flutter tap cancellation](https://api.flutter.dev/flutter/widgets/GestureDetector/onTapCancel.html)
and [React pointer events](https://react.dev/reference/react-dom/components/common#pointerevent-handler)
make interrupted interactions explicit. These are comparators for the proposed
contract, not a reason to copy their entire event APIs.

## 4. Make nested hover and scrolling compose

### Confirmed findings

- Entering an inner MouseRegion emits `outer exit` even though the pointer is
  still inside the outer region. The router retains only one hovered listener.
  A hoverable row containing hoverable controls therefore loses its own state.
- An inner ScrollView at its bottom consumes the wheel and leaves a scrollable
  parent stationary. `edgeBehavior: bubble` currently governs keys only; wheel
  callbacks return void and the router picks the topmost matching callback.

### Proposed change

Track the hovered ancestor path, with deliberate occlusion boundaries, and
diff it for enter/exit. Reconcile it when presentation changes and when the
pointer leaves the surface. [Flutter MouseRegion](https://api.flutter.dev/flutter/widgets/MouseRegion-class.html)
and React's nested enter/leave examples are useful comparisons.

Let a wheel handler report whether it used the event. At an edge, continue to
an ancestor when the configured edge behavior allows it; retain explicit
containment for a modal or self-contained pane. Share the visible hit path so
unhandled events do not accidentally reach an obscured sibling. Custom wheel
handling should be reachable through the ordinary pointer widget surface rather
than requiring callers to obtain and pass a PointerRouter manually.

## Implementation and guide sequence

1. Fix shared hit/focus rules, cancellation, button pairing, first drag updates,
   and browser event forwarding. Add VM and assembled browser regressions.
2. Consolidate event details and migrate existing pointer consumers. Implement
   text pointer editing, then hover ancestry and wheel edge handoff.
3. Rewrite the guide around three source-paired live demos:
   - A small editable form: click to place a caret, select text, and use Tab.
   - A resizable two-pane view: drag a handle, release outside, resize by keys.
   - A hoverable list with child controls and nested scrolling.
4. Keep terminal mouse setup visible and small. Explain that `mouseMotion`
   enables hover when needed. Link to the existing keyboard and testing guides.
   Keep detailed lifecycle contracts in API docs; show input behavior beside
   the source and a physical-input test. Semantic press/fill tests remain useful
   for application behavior but do not establish pointer routing correctness.

Validate ordinary taps, secondary clicks, modifier clicks, clipped/overlapping
controls, nested controls, one-movement and canceled drags, pointer capture,
surface leave/re-entry, focus loss, disabled/read-only fields, scrolled text,
graphemes/wide cells, and wheel boundaries. Include an actual native terminal
pass and both local/served browser hosts; the current audit's executed host
evidence is Chrome mountApp plus the VM dispatcher, not a real TTY session.
Run the existing input, selection, focus, widget, browser, and performance gates
after implementation, followed by production guide build and live demo review.

## Reproductions and validation

- `2026-09-06-input-gestures-evidence/probe.dart` and `probe.json`: 13 focused
  VM fixture scenarios, using actual FleuryTester dispatch. Includes both bare
  and FleuryApp text fixtures, clipping, overlap, coordinates, nested wheel,
  and right-click RangeSlider behavior.
- `2026-09-06-input-gestures-evidence/browser_probe_test.dart` and
  `browser-probe.log`: three Chrome cases. Two characterize the observed cancel/
  leave bugs; one intentionally asserts expected click-to-focus and fails on
  current main. Instrumentation confirms the JavaScript sentinel is zero and
  the routed coordinate, target bounds, focusability, and absorption are correct.
- Existing `packages/fleury/test/widgets/pointer_test.dart`: all 14 tests pass.
  Those tests establish existing covered behavior; they do not cover these gaps.
- No framework or guide implementation has been changed. Browser probe execution
  uses a temporary copy under fleury_web/test because Dart's browser runner does
  not serve a suite outside the package root. Its canonical source is retained
  with this audit.
