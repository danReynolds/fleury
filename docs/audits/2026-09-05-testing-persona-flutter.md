# Testing DX review: simulated Flutter developer

2026-09-05. This is an independent simulated developer perspective, not feedback
from a recruited Flutter developer or a usability study. It reviews the proposed
API, current Fleury implementation, selected existing tests, and official Flutter
documentation. No production code or proposal text was changed. No tests were
executed for this review.

The reviewed proposal is [shared testing targets](../implementation/rfc-testing-controls.md),
especially lines 119–197, 264–353, and 393–418. The
[suite audit](2026-09-05-testing-controls-suite-audit.md) supplies coverage context;
its inventory is static evidence, not full-suite execution. The later chat
proposal also permits `tester.target(type: InvoiceEditor).button('Save')`.
That type selector is not yet present in the written API.

## Overall judgment

One target interface, ordinary controls inheriting semantics, exact matching,
strict single-target actions, explicit input APIs, and deterministic frame
progression make a strong foundation. An experienced Flutter developer would
recognize widget types, controlled widgets, parent-owned state, and explicit
pumping. The main adoption risks are familiar names with different completion
contracts and an unfinished bridge between widget scopes and semantic targets.

The number of roles is not the main problem. Some of Fleury's semantic roles
describe domain objects, while some ordinary control relationships are missing.
Those are different issues from whether a common tester target scales.

## 1. Must resolve before implementation: type selection crosses two trees

**Verified facts.** Fleury's [type finder](../../packages/fleury/lib/src/testing/finders.dart)
at lines 40–50 compares exact `runtimeType`; it does not perform subtype tests.
Its finders operate on Elements. The proposal at lines 131–164 currently searches
semantic descendants and gives every target `SemanticNode` snapshots. A composite
such as `InvoiceEditor` need not publish a semantic node of its own.

Flutter similarly documents exact-type matching and supplies a separate
`bySubtype` alternative. Keeping Fleury's `type:` exact would be familiar and
avoid silently changing existing finder behavior.
[Flutter byType](https://api.flutter.dev/flutter/flutter_test/CommonFinders/byType.html)

**Persona judgment.** The proposed chain is attractive:

```dart
final editor = tester.target(type: InvoiceEditor);
await editor.button('Save').press();
```

But the plan must define what `editor.snapshot`, `hasCount(1)`, and
`editor.press()` mean. One widget may expose zero, one, or many semantic nodes.
Selecting an editor must never activate its first enabled button. Adding
`type: InvoiceEditor, role: SemanticRole.button` also needs an explicit meaning;
ordinary AND filtering is insufficient when the criteria concern different
objects.

**Recommendation.** In the first version, make a type-only target a structural
scope. Count its matching widgets; require one widget before a child query;
require semantic selection before semantic state reads or actions. Do not infer
a primary control. Define combined type/role criteria as an explicit shorthand
for the corresponding scoped query, or reject that combination initially.
Preserve existing structural finders for Element and widget-state inspection.
This is a design recommendation, not an existing contract.

For the bridge, filter the already-published semantic tree by contributor
ownership inside the selected widget subtree. Do not independently construct
semantics from that subtree: doing so could bypass modal/route exposure policy.
[SemanticTree.elementById](../../packages/fleury/lib/src/semantics/semantics.dart)
at lines 653–664 maps nodes to contributors; synthetic DataTable rows and cells
share a widget contributor, so direct type equality on a semantic node's owner
cannot implement all scoped queries.

Acceptance examples should include a composite with no own semantics, two
Save buttons, hidden-route content, a keyed rebuild, and synthetic table rows.
Include a deliberate `target(type: InvoiceEditor).press()` failure showing the
next valid operation. Subtype syntax can remain deferred until needed.

## 2. Must teach and qualify: frame completion is familiar but not Flutter-equivalent

**Verified facts.** Proposal lines 280–290 await a semantic handler and then
complete one frame, without automatically advancing time or settling.
Fleury's [tester](../../packages/fleury/lib/src/testing/fleury_tester.dart)
at lines 328–370 documents synchronous `pump`: it does not yield to async work.
A duration advances ticker intervals. Lines 437–509 distinguish synchronous
`pumpAndSettle` from async `settle`, which yields to the real event loop and
returns after a configured run of idle steps.

Flutter's `pump(duration)` models a frame after a time gap, with fake-time
advancement in ordinary widget tests. Its async `pumpAndSettle` pumps until no
frames are scheduled; Flutter recommends explicit frame counts where possible.
These are related concepts, not identical clock or completion semantics.
[Flutter pump](https://api.flutter.dev/flutter/flutter_test/WidgetTester/pump.html),
[Flutter pumpAndSettle](https://api.flutter.dev/flutter/flutter_test/WidgetTester/pumpAndSettle.html)

**Persona judgment.** The single resulting frame is a useful convenience.
The more serious surprise is that awaiting an action waits for a custom
semantic handler's entire returned Future. If that handler awaits a save held
open by the test, `await button.press()` cannot reach the test's later
`request.complete()` line. A standard button starting work from a void callback
can have different observable completion despite looking the same in the test.

**Recommendation.** Keep the existing dispatch contract, but qualify a custom
async semantic contributor alongside the normal button. Show how to start and
retain its action Future, observe a controlled pending state after the required
frame, then complete the owned request and await the action. Do not promise all
pending states survive an awaited action: microtask work can finish while the
action itself is awaited. The implementation needs an executable example that
establishes the exact ordering.

Document `settle` as observing UI quiescence, not proving all requests are done:
an idle streak cannot establish whether an arbitrary future will later finish.
Use fixture-owned completion for deterministic application tests. Keep
`mountWidget` and `render` in the advanced frame-testing lane. The existing
[frame contract tests](../../packages/fleury/test/testing/frame_contract_test.dart)
at lines 118–128 already make the partial-phase distinction concrete. A clock
redesign or automatic eventual-state API is not required for this facade.

## 3. Must explain at first use: logical press is not Flutter's press or tap

**Verified facts.** Proposal lines 268–278 deliberately map target `press()` to
semantic activation and preserve explicit key/pointer input APIs. Flutter's
`press(finder)` sends pointer-down and returns a gesture; `tap` sends down/up.
Its semantic `performAction` is a separate API with an advertised-action check.
[Flutter press](https://api.flutter.dev/flutter/flutter_test/WidgetController/press.html),
[Flutter tap](https://api.flutter.dev/flutter/flutter_test/WidgetController/tap.html),
[Flutter performAction](https://api.flutter.dev/flutter/flutter_test/SemanticsController/performAction.html)

**Persona judgment.** `button('Save').press()` reads naturally as an application
operation, but familiarity alone does not establish pointer or keyboard
coverage. This is especially easy to miss when the same guide uses
`tester.press(KeySequence.ctrl.s)`.

**Recommendation.** Keep the receiver distinction and ordinary verb. Put a
one-sentence definition before the first example: the control's `press()` invokes
its published logical action and completes its resulting frame. Immediately
pair one logical test with a shortcut/input test of the same widget. Preserve
the plan's rule against automatic pointer/key fallback. Do not rename this
operation `tap` or `click` without implementing the corresponding input path.
Whether newcomers still mistake this for input proof is a real usability
question; a simulated persona cannot settle it.

## 4. Improve the examples: controlled widgets need an owner, but need not lose the clean API

**Verified facts.** Proposal lines 315–326 make `check()` verify the resulting
checked state, while `setValue()` only requests an operation. Current Fleury
[checkbox tests](../../packages/fleury_widgets/test/controls_test.dart) at
lines 318–355 capture a value and explicitly rebuild the controlled widget.
Flutter's Checkbox has the same parent-owned value pattern.
[Flutter Checkbox](https://api.flutter.dev/flutter/material/Checkbox-class.html)

**Persona judgment.** The `check()` postcondition is reasonable for behavior
tests, and exposing an ignored update is useful. However, the plan overstates
the need to drop to the low-level dispatcher for callback-contract tests. The
proposed shared API already offers a clean request without that postcondition:

```dart
await tester.checkbox('Wrap').setValue(true);
expect(changed, isTrue);
```

For a mounted owner that applies changes, the behavior test uses `check()` and
can assert `isChecked`. This distinction scales without another tester class,
an ignore-failure option, or a special controller adapter. Add both examples so
library authors do not conclude that custom widgets are second-class.

Text replacement should retain its similar distinction: `fill()` focuses and
requests a replacement; `setValue()` is intentionally value-only. Flutter's
`enterText` also focuses and replaces, while its custom text-connection path
requires explicit setup. Fleury's capability-based approach can be more uniform
for custom fields, provided filtering, validation, and focus effects remain
part of the shared contract.
[Flutter enterText](https://api.flutter.dev/flutter/flutter_test/WidgetTester/enterText.html)

Keep the plan's explicit outcome assertion for rejected or normalized values.
Do not quietly add a strict value postcondition to `fill` while supporting
NumberInput's rejection behavior. Three-state checkbox support, if introduced,
should add a meaningful mixed-state representation rather than interpreting
an absent checked state as unchecked; it does not require a new checkbox role.

## 5. Refine role families separately: count is acceptable; equivalent controls can still diverge

**Verified facts.** Fleury has 65 roles. Flutter splits semantic meaning between
its role enum and properties: button, textField, checked, mixed, multiline, and
toggled are properties, while comboBox, tabBar, tabPanel, columnHeader, and
radioGroup appear in the enum. Counting enums alone therefore understates
Flutter's semantic vocabulary.
[Flutter roles](https://api.flutter.dev/flutter/dart-ui/SemanticsRole.html),
[Flutter semantic properties](https://api.flutter.dev/flutter/semantics/SemanticsProperties-class.html)

Fleury already has a compatibility mapping in its
[web presenter](../../packages/fleury_web/lib/src/semantics/semantic_dom_presenter.dart)
at lines 509–571: command and approval map to ARIA button; patchFile maps to
listitem; toolCall and tokenMeter map to status. The proposed `button` alias
matches exactly `SemanticRole.button`, so it does not select command/approval
nodes merely because the web accessibility surface classifies them as buttons.
That is a real vocabulary difference, not proof that the richer role is useless.

**Persona judgment.** Ordinary widgets should expose predictable shared control
meaning. Additional roles are justified by distinct interaction or structural
meaning, not by Dart class names. Existing domain roles should not set a
precedent requiring custom app widgets to extend a core enum.

**Recommendation.** Review selection controls, tab relationships, radio groups,
and table headers first against actual widgets and consumer needs. Review
whether domain-role nodes should expose ordinary child controls or whether
their richer identity belongs in state/metadata; do not silently broaden
`button()` into a growing list of domain exceptions. Preserve wire/inspector
behavior until that separate review is complete.

Keeping textField/textArea distinct is not a major DX cost while `field()`
handles both. Adding a role should not add a target subclass or tester method.
Publish a short role-to-state/action table for control authors, including
unsupported-operation diagnostics. That gives custom controls a concrete
contract without requiring knowledge of every role.

## Small proposed example to carry forward

```dart
testWidgets('saves the customer', (tester) async {
  tester.pumpWidget(FleuryApp(home: InvoiceEditor(save: fakeSave)));

  final editor = tester.target(type: InvoiceEditor); // Exact widget scope.
  await editor.field('Customer').fill('Acme');
  await editor.button('Save').press(); // Logical action plus its frame.

  expect(savedCustomer, 'Acme');
});
```

This is illustrative proposed syntax, not a runnable existing test. The fixture
must define a completing save operation, `fakeSave`, and `savedCustomer`.
A second test should explicitly focus/type/press Ctrl+S to qualify the shortcut.
Neither path needs an InvoiceEditor role, an InvoiceEditorTester, or a widget
adapter. Before implementation, settle the structural-scope contract and prove
the async-handler ordering; the remaining findings mostly require better
examples, diagnostics, and a separately scoped taxonomy review.
