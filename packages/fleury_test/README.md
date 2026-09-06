# fleury_test

Deterministic widget tests for [Fleury](https://github.com/danReynolds/fleury).
Keep the testing package in development dependencies so `package:test`, matcher,
and golden-file support stay out of the application's production dependencies.

During the pre-release Git installation, use the same checkout as your app:

```yaml
dev_dependencies:
  fleury_test:
    git:
      url: https://github.com/danReynolds/fleury.git
      path: packages/fleury_test
  test: ^1.26.3
```

Keep the `fleury` dependency override from the
[getting-started guide](https://danreynolds.github.io/fleury/getting-started/).

Mount a real widget, find its control, and check the result:

```dart
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('edits the customer', (tester) async {
    final customer = TextEditingController();
    addTearDown(customer.dispose);
    tester.pumpWidget(TextInput(
      controller: customer,
      semanticLabel: 'Customer',
    ));

    await tester.field('Customer').fill('Acme');
    expect(customer.text, 'Acme');
    expect(tester.field('Customer'), isFocused);
  });
}
```

`testWidgets` creates and disposes a fresh tester. `pumpWidget` completes the
first frame. Mount `FleuryApp(title: ..., home: ...)` explicitly when a screen
needs application navigation or other app scopes.

## Select components and controls

```dart
final editor = tester.target(type: InvoiceEditor);
await editor.field('Customer').fill('Acme');
await editor.checkbox('Send receipt').check();
await editor.button('Save').press();
expect(editor.button('Save'), isDisabled);
```

A custom `InvoiceEditor` needs no role or tester adapter. Type/key-only targets
are widget scopes: they support child queries and counts, but have no implicit
semantic snapshot or action. Types match exact runtimeType. Use `key` with or
without type for repeated components. Combining type/key with role/label is
shorthand for a widget scope followed by a semantic query.

`button`, `field`, and `checkbox` return the same `FleuryTarget`. Other roles use
`target(role: SemanticRole.dialog, label: 'Discard changes?')`. Labels match
exactly and case-sensitively; choose a stable purpose label, independent of a
control's changing value. `Select.semanticLabel` names its trigger;
`Autocomplete.fieldSemanticLabel` names its input and `semanticLabel` its menu.

Semantic child queries search strict descendants. Within a widget scope they
include published nodes contributed by that widget and its descendants. They
preserve hidden-route/modal exclusions; a popup mounted elsewhere needs a root
query. Widget queries start from a root or another widget scope, not a semantic
node. Existing byType/byKey/text/byPredicate finders remain available for widget
and Element inspection.

The role parameter matches exact role names, including package-declared roles
such as `SemanticRole('reviewApproval', base: SemanticRole.button)`. A base
describes projection, not query inheritance: `WidgetRoles.approval` projects to
a browser button but does not match `SemanticRole.button` here.

## Act and observe

| Operation | Contract |
| --- | --- |
| `press()` | Invoke logical activation, not mouse or keyboard input. |
| `focus()` | Request and verify focus on the same control. |
| `fill(text)` | Focus and request text replacement; preserve filtering and validation. |
| `check()` / `uncheck()` | Ensure checked state. Already-correct state is a no-op, even when disabled. |
| `setValue(value)` | Request an update without focusing; widgets can normalize, clamp, or reject it. |
| `open`, `close`, `select`, `submit`, `copy` | Request the corresponding advertised action. |
| `perform(action)` | Dispatch another advertised semantic action. |

Actions resolve one current match, await its handler, then complete one frame.
They do not retry, advance animation time, or settle. Use `tester.press(keys)`,
`type`, `paste`, and pointer APIs when actual input behavior is under test.

`field` recognizes `state.textEditable`, with textField/textArea as compatible
defaults when that property is absent. Custom editable controls can opt in;
filling still requires enabled/non-read-only state and focus/setValue support.
A field remounted during focus is rejected before text reaches its replacement.

Use `hasCount(n)`, `isEnabled`, `isDisabled`, `isFocused`, `isChecked`,
`isUnchecked`, and `hasValue(valueOrMatcher)`. State matchers require one control;
negation never hides missing/ambiguous matches. Redacted values fail without
printing expected or actual secrets; assert a fixture-owned callback instead.

`target.count` counts widgets for structural queries or published nodes for
semantic queries. `target.snapshot` reads one semantic node;
`target.snapshots` returns an immutable list of semantic matches. Retained
snapshots are historical; queries resolve afresh. Every parent scope must
match once, even when asserting zero children. Virtualized-node counts are not
dataset sizes.

Controlled widgets need a rebuilding owner for `check()` postconditions. A
callback-contract test can instead use `setValue(true)` and assert its callback.

## Frames and asynchronous work

`pumpWidget` and `pump` complete build, layout, paint, and post-frame callbacks.
`pump(duration)` advances Fleury tickers, not ordinary Dart timers.
`pumpAndSettle()` progresses finite animation frames. `await settle()` yields to
the event loop until the UI stays quiet; it cannot prove a service request ended.
Control async work with fixture-owned callbacks and Completers.

If a custom semantic handler returns a pending Future, retain the action Future,
await a fixture-owned handler-start signal, pump and inspect the pending UI,
complete the request, then await the action. An app-owned save started separately
by a void callback can remain pending after `press()` returns. The
[Testing guide](https://danreynolds.github.io/fleury/guides/testing/) pairs both
shapes with widget source and executable tests.

Set `viewportSize` before mounting when initial size matters.
`render(size: ...)` resizes and updates MediaQuery. Rendering produces a snapshot
without advancing time or running post-frame callbacks. Framework tests can use
`mountWidget`, `owner.flushBuild()`, and `render` for individual phases.

## Low-level contracts and golden files

The result-returning semantic API remains available for rejection tests:

```dart
final result = await tester.invokeSemanticAction(
  SemanticAction.activate,
  role: SemanticRole.button,
  label: 'Save',
  allowFailure: true,
);
expect(result.status, SemanticActionInvocationStatus.disabled);
```

`matchesGolden` reads files under `test/goldens/`. Missing files fail. Create or
update a baseline with `FLEURY_UPDATE_GOLDENS=1 dart test`, then review its diff.

Benchmarks and tools that intentionally avoid `package:test` can use the
package-neutral `package:fleury/fleury_test_support.dart` harness.
