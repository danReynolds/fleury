# Proposal and implementation plan: shared testing targets

Status: implemented, 2026-09-05; qualification is recorded in the implementation
receipt linked below. This revision incorporates the complete test-file inventory,
developer persona feedback, and the decision to limit control-specific APIs.

See the [implementation receipt](../audits/2026-09-05-testing-targets-implementation.md)
for delivered behavior, review corrections, validation, and existing failures.

Recommend **one `FleuryTarget` type**, a common set of operations, and three
small selector aliases: `button`, `field`, and `checkbox`. A new widget should
normally require zero additions to the tester. The core semantic tree,
capabilities, state, and dispatch remain shared with other consumers.

The [suite audit](../audits/2026-09-05-testing-controls-suite-audit.md) inventories
404 owned test files and all 287 direct semantic-invocation sites. Those calls
span 49 explicitly named roles and all 17 existing actions. Three separate
control drivers would not be a sufficient general testing design.

Peer findings below come from official documentation/source inspected on
2026-09-05. They are API comparisons, not measured usability results or a
cross-framework benchmark. Local evidence is bound to the current dirty
checkout through the inventory's HEAD and per-file hashes.

## What the peers teach us

The useful comparison separates target selection, interaction, observation,
and waiting. A semantic selector does not determine the interaction path.

| Peer | Representative API | Actual boundary | Lesson for Fleury |
| --- | --- | --- | --- |
| React Testing Library with user-event | `await user.click(screen.getByRole('button', {name: 'Save'}))` | Semantic DOM selection followed by simulated input interactions. `user-event` models event sequences and interactability, beyond dispatching one event. | Keep meaningful selection; expose an ordinary interaction verb. React itself does not supply this testing API. [user-event](https://testing-library.com/docs/user-event/intro/) |
| Flutter | `await tester.tap(find.text('Save'))` | Pointer down/up at the target's center; a missed hit warns by default. Rebuilding is separately controlled by pumping. | Make input promises concrete. Do not call a semantic callback a tap. [tap](https://api.flutter.dev/flutter/flutter_test/WidgetController/tap.html), [interaction recipe](https://docs.flutter.dev/cookbook/testing/widget/tap-drag) |
| Flutter semantics | `tester.semantics.performAction(finder, action)` | Explicit operation on a semantic node, with an advertised-action check by default. | Preserve a general semantic API for tests that intentionally exercise that contract. [performAction](https://api.flutter.dev/flutter/flutter_test/SemanticsController/performAction.html) |
| Textual | `await pilot.click('#save')`; `await pilot.press('enter')`; `app.query_one('#save', Button).press()` | Pilot distinguishes mouse clicks from keys. The widget's own `press()` performs a logical button operation. Its source returns without acting when disabled or not displayed. | There is precedent for logical `Button.press()`. For Fleury's test facade, silent failure would be a poor default. [Pilot](https://textual.textualize.io/api/pilot/), [Button](https://textual.textualize.io/widgets/button/#textual.widgets.Button.press), [source](https://github.com/Textualize/textual/blob/main/src/textual/widgets/_button.py) |
| Playwright | `await page.getByRole('button', {name: 'Save'}).click()` | A locator resolves the current element for each action. Clicks have visibility, stability, event-reception, and enabled checks with bounded waiting. | Borrow reusable queries, strict uniqueness, and specific failure explanations. Evaluate waiting separately for an in-process harness. [locators](https://playwright.dev/docs/locators), [actionability](https://playwright.dev/docs/actionability) |
| Ink testing library | `stdin.write('x')`; `lastFrame()` | Drives the React TUI's input stream and reads rendered output. | A small surface is approachable, but rendered text alone gives less control-state information than Fleury already has. This is a comparison of the documented library surface. [API](https://github.com/vadimdemedes/ink-testing-library#api) |
| Nocterm | `await tester.sendKey(LogicalKey.space)`; `expect(tester.terminalState, containsText('Count: 1'))` | Its introductory component test drives a key and asserts terminal output. | The first test has little conceptual overhead. Keep Fleury's first example comparably concrete. This does not establish the limits of Nocterm's full API. [package example](https://pub.dev/packages/nocterm#testing) |
| Bubble Tea / teatest | `tm.Send(message)`; `teatest.WaitFor(...)`; `tm.FinalModel(...)` | Drives a program with messages and observes output or final model state. Final-model/output waits concern program termination. | Name precisely what a wait observes. These are the documented `x/exp/teatest` APIs; no v2 parity claim. [package API](https://pkg.go.dev/github.com/charmbracelet/x/exp/teatest) |
| Ratatui | `Terminal::new(TestBackend::new(...))`, draw, snapshot | Tests rendering in process. Its guide separately describes PTY coverage for input and application lifecycle. | Keep behavioral, visual, and terminal-input evidence distinct. [testing recipe](https://ratatui.rs/recipes/testing/snapshots/) |

Two further details are especially relevant. Testing Library distinguishes an
immediate required match, optional absence, and an asynchronous eventual match;
its single-target queries reject duplicates. It also provides `within` for
selection inside a specific container. Fleury needs the same clarity about
cardinality and scope, without copying the entire query-name family.
[Queries](https://testing-library.com/docs/queries/about/),
[within](https://testing-library.com/docs/dom-testing-library/api-within/).

Text replacement also deserves an explicit verb. Flutter's `enterText` focuses
an editable widget and replaces its content. Playwright distinguishes filling
text from key input and offers checkbox operations that express the desired
state. Fleury should distinguish replacement, typing, and pasting too.
[Flutter enterText](https://api.flutter.dev/flutter/flutter_test/WidgetTester/enterText.html),
[Playwright actions](https://playwright.dev/docs/input).

## Granularity decision

Use the same target for standard widgets, compound controls, synthetic table
rows, and custom semantic contributors. A role identifies a kind of UI element;
it does not imply a dedicated Dart tester class. Methods check the target's
published capabilities and relevant state at runtime. A common target may
therefore expose a method that a particular match does not support; the failure
must name the requested operation and the available capabilities.

This resembles Playwright's shared `Locator`, whose same type offers click,
fill, check, and scoped queries. Testing Library uses common DOM queries and
user-event operations; Flutter uses general finders with tester operations.
They do not require a test-driver class for each application widget.
[Playwright Locator](https://playwright.dev/docs/api/class-locator),
[Testing Library](https://testing-library.com/docs/user-event/intro/),
[Flutter WidgetTester](https://api.flutter.dev/flutter/flutter_test/WidgetTester-class.html).

The three aliases are selection conveniences, not separate implementations:

```dart
tester.button('Save')
// Same FleuryTarget as:
tester.target(role: SemanticRole.button, label: 'Save')
```

`field` matches nodes with `state.textEditable == true`, with textField/textArea
as backward-compatible defaults when that state is absent. This includes
NumberInput, PasswordInput, and Autocomplete. `checkbox`
selects exactly the checkbox role. There is no initial `dialog`, `table`,
`tree`, `slider`, or other widget-specific selector. Each is already reachable
through `target`. App-owned helpers can compose these selectors if repetition
in a particular application warrants it.

## Role vocabulary and custom widgets

The initial audit examined a 65-entry enum. Main has since adopted an open
`SemanticRole` value type and moved catalog roles into `WidgetRoles` (PR #215).
This implementation uses that current vocabulary without changing its identity
or projection contract. A package may declare
`SemanticRole('reviewApproval', base: SemanticRole.button)` and query it with
the same `target` method; role queries match the exact name, independently of
the base used for presentation.

Many widget classes share one role; a composite can expose several child roles;
layout-only widgets may need no semantic node at all. A custom SaveButton built
from Button inherits button semantics. A custom invoice editor normally contains
ordinary fields and buttons and can be scoped by its widget type. Neither needs
a new role or a tester plugin. App-specific identity belongs in IDs/keys; a new
role should describe a distinct meaning for consumers, not merely name a class.

Acceptance coverage includes a custom composite, a custom primitive reusing a
core role, and a declared role with a core base. Role-vocabulary migration and
wire compatibility are owned by the already-merged role work, not this facade.

Role-based selection is conventional in React Testing Library, which queries
the rendered DOM's standard roles rather than React component class names.
A custom component returning a native button inherits that button role.
Explicit ARIA on a custom primitive describes behavior; it does not implement
the keyboard behavior for the author.
[ByRole](https://testing-library.com/docs/queries/byrole/),
[WAI guidance](https://www.w3.org/WAI/ARIA/apg/practices/read-me-first/).

Flutter supports semantic roles, but its ordinary widget-testing finders also
query text, keys, widget instances, and widget types without requiring semantic
annotations. Fleury already has byType, byKey, text, byPredicate, and
descendantOf. Preserve them for structural tests and existing input/rendering
paths; semantic targets are an additional behavior-facing interface. Finding
a widget by type does not itself give it a semantic action handler.
[Flutter finders](https://docs.flutter.dev/cookbook/testing/widget/finders),
[byType](https://api.flutter.dev/flutter/flutter_test/CommonFinders/byType.html),
[existing Fleury finders](../../packages/fleury/lib/src/testing/finders.dart).

## Public surface

All root selector methods below are also available on `FleuryTarget`.
Widget type/key queries establish structural scopes; semantic queries select
published controls inside those scopes or descendants of another semantic node.

```dart
FleuryTarget target({
  Type? type,
  Key? key,
  SemanticRole? role,
  String? label,
  SemanticNodeId? id,
});

FleuryTarget button(String label);
FleuryTarget field(String label);
FleuryTarget checkbox(String label);
```

`target` requires at least one selector criterion. Semantic criteria combine with AND;
labels match exactly and case-sensitively. These are reusable queries, not
immediate references to a node or widget state. Scoping is available for every
role. IDs reuse the existing semantic-ID contract rather than a new test-ID
scheme. No public general query language is introduced.

`type` matches exact runtimeType, and `key` matches widget keys. Together they
identify one structural scope. Mixed structural/semantic criteria are shorthand
for an explicit type/key scope followed by a semantic query. Nested structural
queries search strict widget descendants. Semantic queries within a structural
scope include nodes contributed by the scope itself and its descendants, but
only from the application's published tree; hidden routes are never re-exposed.
Popups mounted elsewhere require a new root query. A semantic scope searches
strict semantic descendants. Switching from a semantic scope back to widget
queries is rejected; use a root/type scope for widget inspection.

A type/key-only target supports child selection and `count` (matching widgets).
It does not infer a semantic root or an action from its children. Semantic state
reads and actions require a semantic child selection. Existing structural
finders still provide Element/widget inspection. `count` on a semantic target
counts published nodes; it is not a dataset size. Every parent scope must match
exactly once, even for a zero-count child assertion.

A target has two observation getters:

```dart
SemanticNode get snapshot;       // Exactly one current match.
List<SemanticNode> get snapshots; // All current matches; immutable snapshots.
int get count;                   // Widget matches or semantic-node matches.
```

Both resolve afresh when read. Stored snapshots remain historical values.
Actions and `snapshot` reject zero/multiple matches. `snapshots` allows
zero/many, while its parent scope must still resolve uniquely. Missing a
scope never becomes a passing empty-child assertion. No implicit first-match,
availability-based disambiguation, or fallback to visible text.

Use one generic dispatcher and a bounded vocabulary of shared operations:

```dart
Future<void> perform(SemanticAction action, {Object? payload});
Future<void> setValue(Object? value);
Future<void> press();
Future<void> focus();
Future<void> open();
Future<void> close();
Future<void> select();
Future<void> submit();
Future<void> copy();
Future<void> fill(String text);
Future<void> check();
Future<void> uncheck();
```

These 12 methods belong to one target, not twelve control classes. `press`
maps only to semantic activation. Focus/open/close/select/submit/copy map only
to their corresponding action; setValue carries the existing payload. The
named direct operations account for 251 of the 287 semantic call sites; this
is a vocabulary-fit count, not a recommendation to migrate 251 contract tests.
`perform` covers navigate, increment/decrement, dismiss, clear, start/cancel,
and diagnostics without adding another tester method for each specialized
workflow. Add another shared convenience only when repeated real examples
justify it. Adding a widget alone is not sufficient justification.

This intentionally gives up compile-time restriction of `fill` to a dedicated
field-target class. Real availability already depends on runtime enabled,
read-only, and advertised-action state. Runtime capability checks allow custom
controls to participate without widget-class inspection or an adapter registry.
Dart still checks the String argument of fill and the enum argument of perform.

## Examples including less common controls

The counter remains small:

```dart
testWidgets('adds one', (tester) async {
  tester.pumpWidget(const Counter());
  await tester.button('Add one').press();
  expect(tester.exists(text('Count: 1')), isTrue);
});
```

A tree uses the same target, scope, and action machinery:

```dart
final project = tester.target(role: SemanticRole.tree, label: 'Project tree');
final source = project.target(role: SemanticRole.treeItem, label: 'src');

await source.open();
await project.target(role: SemanticRole.treeItem, label: 'b.dart').press();
expect(source.snapshot.expanded, isTrue);
```

Tabs and form submission require no new tester classes:

```dart
await tester.target(role: SemanticRole.tab, label: 'Run').select();
await tester.target(role: SemanticRole.form).submit();
```

A dropdown's trigger has a button role today. Its value operation can select
an option without opening the menu. The test explicitly checks the outcome:

```dart
final color = tester.target(role: SemanticRole.button, label: 'Color');
await color.setValue('Blue');
expect(color, hasValue('Blue'));
```

An offscreen table row first needs to enter its published semantic window:

```dart
final runs = tester.target(role: SemanticRole.table, label: 'Runs');
await runs.setValue(5000); // Existing table contract: select/reveal row index.
expect(runs.snapshot.state.visibleRangeStart, lessThanOrEqualTo(5000));
expect(runs.snapshot.state.visibleRangeEnd, greaterThanOrEqualTo(5000));
```

This uses the table's published visible range. Selection exposes the row;
the finder does not scroll automatically.

A specialized operation still benefits from the same selection and errors:

```dart
final diagnostic = tester.target(role: SemanticRole.diagnostic);
await diagnostic.perform(SemanticAction.diagnose);
```

The uncommon case is slightly longer to spell, but keeps the same query,
scoping, state, and completion model. A custom control that publishes the
button role and activation already works with `button(...).press()`. A
component with no usable semantics can still be exercised through existing
input/rendering APIs; adding meaningful shared semantics is preferable to a
private tester adapter.

## Operation contracts

### Logical actions and input coverage

`press` invokes semantic activation exactly once through the existing strict
dispatcher. It never accesses `Button.onPressed` or chooses between mouse,
Enter, and semantic dispatch. It tests the logical operation. It does not
prove hit testing, key bindings, hover/down/up events, or terminal decoding.
`focus` dispatches the focus action and verifies that the target obtained
focus; focus refusal must fail rather than silently redirect subsequent keys.

Keep `tester.press(KeySequence.ctrl.s)`, `sendKey`, `type`, `paste`,
`sendMouse`, hold/release and input-batch APIs for their existing purposes.
Do not overload tester.press with an Object target. Keep pointer convenience
work separate until bounds, clipping, and hit-test diagnostics justify it.

A successful dispatched action completes one resulting frame with `pump()`.
It does not advance fake time, retry, or implicitly settle. The semantic
handler itself is awaited; a handler that returns a long-running future will
therefore keep the operation pending. Application work started separately by
a void callback may outlive the action. Use controlled Completers for pending
states; an awaited call can naturally allow short microtask work to finish.

Open, close, submit, and setValue request the advertised operation. A PopScope
may veto close; validation may reject submit; widgets may normalize, clamp,
or reject a value. Success means dispatch completed, not that a requested
application outcome occurred. Assertions remain essential. Existing
`allowFailure: true` result/status tests stay on the low-level API; no general
force or ignore-failure option is added to targets.

### Text replacement

`fill(text)` requires the shared text-editable semantic contract, enabled/non-read-only state, and focus
and setValue capabilities. Check them before side effects. Focus, revalidate
the same live target, replace through its existing semantic handler, then
complete the frame. It preserves filtering, callbacks, validation, and secret
redaction. NumberInput can reject an invalid replacement; fill does not
bypass that behavior or promise a matching final value.

Focus may rebuild a component. Across separate actions a query can resolve a
replacement; within this composite operation a remount or changed target must
fail before text is sent. Use the current semantic contributor/ID to verify
continuity during this one operation, not a retained reference across tests.
A control that refuses focus must not be filled under a promise of focused
input. `setValue` remains available for an intentional value-only operation.

Fill does not test per-key editing, paste normalization/chunking, undo grouping,
IME composition, or completion acceptance. Those tests retain actual input.

### Boolean desired state

`check`/`uncheck` use the published **checked** state and boolean setValue
capability. They support controls with boolean checked state, including
checkbox and toggle roles, without assuming that `value` is boolean. Require
one target and a non-null checked state. Already-correct state is a no-op,
including when disabled or lacking a setter. Otherwise require enabled state
and setValue support, send the bool once, complete the frame, and
verify the resulting checked state. No activate/select fallback.

A controlled widget needs an owner that applies onChanged and rebuilds. If it
merely records the callback, the postcondition fails with the observed state;
its callback-contract test can use `setValue(true)` and assert the callback. A
radio that only supports activation is operated with press, not uncheck.

The first implementation must add boolean setValue to MultiSelect checkbox
options in the widget's shared semantics. Keep their existing option-key value,
disabled behavior, focus/selection conventions, and form notifications. Reuse
one desired-state update path; do not introduce a test-specific workaround.

### State assertions and diagnostics

Retain package:test. Initial target-aware matchers:

- `hasCount(n)` for absence, a single match, or a collection.
- `isEnabled`, `isDisabled` for current availability.
- `isChecked`, `isUnchecked` for checked state, never value truthiness.
- `isFocused` for the actual focus contract.
- `hasValue(expected)` for the published value, accepting ordinary matchers.

Single-target state matchers require exactly one target. Negation must not
turn a missing/ambiguous target into a passing state assertion. A target with
no checked state cannot pass isUnchecked. Other observations such as selected,
expanded, validationError, and domain metadata remain available on snapshot.
Do not mirror every SemanticState property with a bespoke matcher.

Retain the full query/scope in errors. Reuse bounded, redacted tree diagnostics;
never log a fill/setValue payload. A value matcher on a redacted target must
avoid printing both the actual value and the expected secret. Do not inspect
private controllers to recover a redacted value. Test persistence through a
fixture-owned callback when necessary.

## Migration and implementation sequence

1. **Shared query foundation in fleury_test.** Add one FleuryTarget/resolver,
   target selector and three aliases, descendant scopes, snapshots and strict
   diagnostics. Resolve a scope uniquely and dispatch by the resulting node's
   ID, never by an unscoped label. Reuse existing semantic querying and
   contributor mapping. Avoid a second query engine, public selector DSL,
   subclass hierarchy, widget registry, or runtime/clock implementation.
2. **Common action layer.** Implement perform and the direct action aliases,
   with strict capability checks and one-frame completion. Cover both ordinary
   Semantics and synthetic DataTable contributors. Keep existing neutral core
   result contracts and fleury_test's strict low-level facade intact.
3. **Composite actions and necessary semantic correction.** Implement fill
   with focus continuity checks and check/uncheck with state postconditions.
   Add boolean setValue to MultiSelect's semantic option nodes. Ensure repeated
   desired-state updates do not emit duplicate form/change notifications.
   Do not rename core roles/actions or change remote wire statuses to make
   invalid Select values throw in this change.
4. **Shared matchers.** Implement the seven matchers above using the same
   resolver. Cover zero/many, scope failures, negation, checked versus value,
   and redacted diagnostics. Keep assertions immediate.
5. **Representative adoption.** Migrate the testing guide and its real
   counter/editor tests; keep the Ctrl+S path on keys. Change its titled Panel
   confirmation to the real Dialog widget before demonstrating dialog scope.
   Add representative generic-target examples/tests for a tree, tabs, form
   submission, Select values, MultiSelect, and a virtualized DataTable. Migrate
   application behavior assertions where this improves intent; do not sweep
   the entire repository or rewrite semantic-conformance tests.
6. **Documentation and qualification.** Show widget source, test code, and
   live demo together. Explain semantic meaning and logical/input coverage at
   first use, then introduce generic targets before specialized examples.
   Explain package:test matchers and pump/render/settle before relying on them.
   Run the gates below and update the public package docs/changelog.

The core test harness intentionally avoids a fleury_test dependency so the
packages can publish without a cycle. Keep new facade code/tests in
`packages/fleury_test`; core semantic fixes use the existing core harness.

## Acceptance and validation gates

- Query reuse after rebuild/remount; changed labels and stable IDs; keyed
  reorders and positional identities; duplicate labels with one disabled;
  missing/ambiguous/nested scopes; contributor-backed rows/cells; use after
  tester disposal. Single-target actions never pick first or infer availability
  to resolve identity. Collection snapshots are immutable and scoped.
- Direct action dispatch exactly once, including failure/unsupported/disabled
  outcomes and throwing/async handlers. No automatic input fallback. A custom
  semantic-only button works without a Dart Button class. A logical operation
  cannot substitute for the explicit key/pointer regression tests.
- Layout-time children and semantic window changes visible after the action's
  frame. Pending Completers remain observable; no fake-time advance or hidden
  settle. A vetoed close or invalid form does not become an automatic wait.
- Fill across plain, multiline, numeric, password, autocomplete and custom
  editable controls; real callbacks/validation; read-only/disabled rejection;
  focus denial/remount; no secret output; normal filtering preserved.
- Check/uncheck across controlled hosts, Checkbox/Toggle/Switch, and
  MultiSelect option nodes; initially correct states; no duplicate callbacks;
  ignored change requests; missing checked state; no value/key confusion.
- Count/state/value matchers with missing targets, duplicates, missing scope,
  negation, and redaction. Unexposed virtual rows are absent, not searched for
  by automatic scrolling; counts are semantic nodes, not dataset rows.
- Route/modal tests preserve the shared active-route exposure policy. The
  migrated guide's actual dialog is found by role/title and retains focus
  restoration and its verified rendered layout.

Run format/analyze for touched packages and focused new tests first. Then run
fleury_test, affected fleury_widgets suites, the relevant core semantic/frame
and navigation suites, and the application/example tests being migrated.
Run the MultiSelect capability addition through semantic conformance and
applicable shared semantic presenter/remote parity tests. Generate docs/demo
outputs before checking the guide in the browser, including source/test tabs,
scoped dialog, keyboard flow, layout, and examples at the relevant viewport.
Finally run the repository's `dart tool/fleury_dev.dart check` contributor gate.
Known baseline failures must be reproduced and reported separately; none of
these future gates is claimed to have run during this design audit.

## Boundaries and remaining design judgments

Recommended decisions for review are: one common target rather than typed
control drivers; the three selector aliases above; a shared action vocabulary;
strict immediate actions; and observed-state postconditions specifically for
check/uncheck. The runtime-capability tradeoff is intentional and matches the
open-ended nature of custom semantic controls.

Defer broad gesture helpers, automatic waits/scrolling, a public query DSL,
widget adapters, per-widget tester classes, strict select-option acceptance,
and a two-handle range-slider API. The current tests remain expressible with
existing input and generic semantic APIs. Those deferred items are distinct
DX opportunities, not reasons to enlarge this facade before implementation.

Reconsider logical press as the first-demo default if readers continue to
reasonably interpret it as mouse/keyboard proof after its concise definition.
That decision would require a genuine pointer helper; renaming semantic
activation to click would not solve it.

## Historical design evidence

The earlier [button probe](../audits/2026-09-05-testing-interaction-evidence/button_probe.dart)
passed five checks: root replacement, ambiguity, a custom semantic button,
frame completion, and controlled save/failure/retry. Its local ProposedButton
class is an initial feasibility sketch, not the proposed class architecture.
The new [edge probe](../audits/2026-09-05-testing-interaction-evidence/edge_contract_probe.dart)
passed five existing-contract checks documented in the suite audit. Neither
implements or qualifies the complete target API.

These probes captured the pre-implementation contract and are retained as
historical evidence. Use the maintained [target tests](../../packages/fleury_test/test/target_test.dart),
[widget integration tests](../../packages/fleury_widgets/test/testing_targets_test.dart),
and [guide tests](../../website/examples/test/testing_guide_test.dart) to validate
the implemented API. See the [PR review receipt](../audits/2026-09-05-testing-pr-review.md)
for current validation.

Relevant code: [test facade](../../packages/fleury_test/lib/src/fleury_tester.dart),
[harness](../../packages/fleury/lib/src/testing/fleury_tester.dart),
[semantics](../../packages/fleury/lib/src/semantics/semantics.dart),
[controls](../../packages/fleury_widgets/lib/src/controls.dart),
[Select/MultiSelect](../../packages/fleury_widgets/lib/src/select.dart).
