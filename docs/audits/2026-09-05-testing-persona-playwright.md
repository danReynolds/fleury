# Testing DX review: Playwright developer persona

2026-09-05. This is an independent simulated developer perspective, not feedback
from a recruited developer or measured usability research. The persona is an
experienced Playwright user who values reusable locators, dependable actions,
clear failures, and custom controls. Recommendations below are design judgments.

Reviewed the [proposal](../implementation/rfc-testing-controls.md),
[suite audit](2026-09-05-testing-controls-suite-audit.md), current enum and
dispatch implementation, strict tester tests, Select/MultiSelect semantics,
the guide's editor, and the web semantic projection. Also considered the latest
chat proposal to add `type:` to the same target interface; that addition is not
yet specified in the RFC. No production changes or broad test runs were made.

## Overall judgment

One reusable target with shared operations is a strong direction. Twelve
operations on that type are not an API explosion. The unresolved cost is the
number of meanings a reader must infer: which tree a query searches, which
semantic category a control exposes, and what awaiting an action guarantees.
Resolve those contracts before growing the convenience surface.

## Ranked findings

### 1. Must resolve: a widget type identifies a component, not necessarily one semantic node

The proposed `tester.target(type: InvoiceEditor).button('Save').press()` reads
well. But a type query and semantic query have different matching units. Existing
`byType` matches an element's exact runtime type; an editor can contain zero,
one, or many semantic nodes. Synthetic table rows can share one contributor
element. The current RFC's `SemanticNode get snapshot` cannot automatically
describe every uniquely selected widget.

Counterexample: an editor initially contains only a Save button. If
`target(type: InvoiceEditor).press()` picks its sole semantic descendant, adding
a status message changes an apparently valid action into an ambiguity. Selecting
the first actionable descendant would make this still more surprising.

My preferred initial rule: a type target establishes a structural component
scope; an action or semantic snapshot requires an explicit semantic selection
within it. Do not infer a component's action from its descendants. If direct
`target(type: Button).press()` is desired, first define a stable association to
the component's own published semantic root, independent of child count.

Specify four cases before implementation: no matching widget, two matching
widgets, one widget with no semantics, and one widget with several semantic
roots. A count of type matches counts widgets; a count of role matches counts
semantic nodes. A pure structural target must not silently reinterpret its
`snapshot`/`snapshots` as descendant semantic results.

Scope should follow actual exposed-tree membership and contributor ancestry,
not component ownership guesses. A popup presented elsewhere in the tree need
not be a descendant of its opener. Demonstrate selecting that dialog from the
tester root. Playwright chaining narrows to a rendered subtree; it does not
promise that everything conceptually owned by a component is inside that
subtree. [Playwright locator scoping](https://playwright.dev/docs/locators#matching-inside-a-locator)

### 2. Must decide before promising portability: ordinary role queries currently differ across surfaces

The current web presenter maps `command` and `approval` to ARIA `button`,
`patchFile` to `listitem`, and `toolCall`/`tokenMeter` to `status`. The RFC's
`button('Approve')` selects only the exact Fleury `button` role. Therefore a
control exposed as `approval` can be found as a button through Playwright on
the projected DOM but not through Fleury's proposed button shortcut. This is
a concrete discrepancy, not merely an aesthetic objection to 65 enum entries.

Source: [web role projection](../../packages/fleury_web/lib/src/semantics/semantic_dom_presenter.dart).
Playwright's role locator queries the element's accessible role and name.
[Role locators](https://playwright.dev/docs/locators#locate-by-role)

I would prefer a consistent common UI category, with richer domain information
retained separately where useful. That is a shared semantic-model decision;
do not quietly add a special union only to `tester.button`. If a taxonomy change
is deferred, clearly state that Fleury role queries use its richer enum and do
not reproduce the web projection, with an approval example showing the gap.

The higher-priority additions are selection and grouping concepts that our
existing controls need: assess combobox/listbox/option, tab collection/panel,
and radio grouping against actual behavior. Adding a role must improve generic
interpretation of state or relationships; it should not merely name another
widget class. Per-widget tester classes would not solve this issue.

### 3. Must teach and qualify: immediate actions are acceptable, but async completion is a separate axis

I support no implicit waiting, scrolling, or fake-time advancement in this
in-process harness. It makes pending-state and animation tests precise.
Playwright waits for relevant actionability conditions, and its locator
assertions normally retry; those are useful browser contracts, not requirements
Fleury must copy. [Actionability](https://playwright.dev/docs/actionability),
[assertions](https://playwright.dev/docs/test-assertions)

However, “one frame” does not explain how long `await target.press()` takes.
The RFC awaits the semantic handler, then pumps. The current guide explicitly
starts saving with `unawaited(save())`, while a custom semantic handler may
return its persistence future. The same apparent press can therefore finish
while saving is pending or remain pending until the save completes.

Counterexample: a custom button returns a future backed by a test Completer.
The test awaits `.press()` and only then intends to assert Saving and complete
the request. It hangs at the first await. This is not fixed by documenting
that Fleury does not settle automatically.

Keep shared dispatch's handler-awaiting behavior unless a separate consumer
audit justifies changing it. Add a tested example retaining the action future,
waiting for a controlled handler-start signal, pumping to observe the pending
UI, completing the request, and then awaiting the action. Distinguish that
advanced recipe from the ordinary app-owned background save example.

Likewise define `press` at first use as a logical action. A Playwright developer
must not infer mouse hit testing or key routing from it. Keeping actual key,
pointer, paste, and rendering tests is essential; the audit correctly identifies
those as different evidence.

### 4. Must improve: stable labels are part of widget DX, not a finder workaround

The RFC's exact, case-sensitive matching is a reasonable simple default. It
differs from Playwright's default role-name substring matching, which can be
made exact. Document the rule; do not accumulate fallback matching modes to
hide poorly named controls. [Playwright name matching](https://playwright.dev/docs/api/class-locator#locator-get-by-role)

The concrete issue is Select: absent `semanticLabel`, its semantic label falls
back to the current option label. A saved query for a button labelled Red stops
matching after selecting Blue. The source already separates the current value
from an optional stable purpose label; the guide should consistently supply
the latter, for example Color.

Source: [Select semantics](../../packages/fleury_widgets/lib/src/select.dart).

Prefer role plus a stable human-facing purpose label for ordinary behavior
tests. Use an explicit stable semantic ID when identity deliberately needs to
survive localization or copy changes. Do not promise that generated positional
IDs survive arbitrary tree changes. The existing SemanticNodeId documentation
already distinguishes those identities.

Defer regular-expression selectors until representative tests need them. First
test label changes, duplicate labels in different scopes, stable IDs across
rebuilds, and labels that differ only by whitespace or case. Failure output
should expose the actual matching rule and nearby labels.

### 5. Recommended change: desired-state operations should return when the desired state already exists

The RFC requires enabled state and `setValue` capability before returning from
an already-correct `check`/`uncheck`. Playwright instead returns early when a
checkbox is already in the requested state, before actionability checks; it
verifies the resulting state when it changes it.
[Playwright check](https://playwright.dev/docs/api/class-locator#locator-check)

I would change Fleury's ordering: resolve exactly one target and require a
meaningful checked state; if it is already correct, return without a dispatch.
Otherwise require enabled state and the setter capability, dispatch once,
pump, and verify the result. This is a persona recommendation, not a statement
that the present proposal is broken.

Counterexample: a mandatory preference is already checked and disabled. Setup
that ensures it is checked should succeed. A test proving that users may change
it should separately assert availability. Requiring permission to make a
change that is unnecessary makes `check` read less like a desired-state helper.

Preserve the important distinctions already in the RFC: checked state is not
the option's value; no toggle fallback; ignored change requests fail the
postcondition; bare controlled widgets need a rebuilding owner for behavior
tests. The proposed MultiSelect setter correction belongs in shared widget
semantics, not a tester-specific branch.

Keep `setValue` lower-level and require outcome assertions for rejected or
normalized values. A future strict option-selection operation may be useful,
but should wait for an accepted/rejected value contract rather than guessing
success from completed dispatch.

### 6. Preserve, with acceptance examples: one target, immediate observations, and strict diagnostic errors

The single-target API, query re-resolution between actions, immutable historical
snapshots, strict cardinality, and bounded redacted diagnostics are the strongest
parts of the plan. A new custom button should publish ordinary semantics and
need no testing adapter. I would keep the three selector aliases and the shared
operations; adding more aliases by widget count would reduce predictability.

Observations should remain explicit: `snapshot` reads current state once,
storing it makes a historical value, and matchers resolve the live query now.
Count zero is the clean absence assertion. Preserve errors for missing parent
scopes and for missing/ambiguous nodes in state matchers, including negation.

Acceptance errors should distinguish the failing stage: two InvoiceEditor
widgets; one editor but no matching Save button; one matching button that is
disabled; one button without activation; a handler exception; or a checked
postcondition that remained false. Show the whole scope path and actual
capabilities. This matters more to a Playwright adopter than reducing the
number of methods from twelve to eight.

## Preferred small example

This remains proposed syntax, with type used explicitly as component scope:

```dart
final editor = tester.target(type: InvoiceEditor);
await editor.field('Customer').fill('Acme');
await editor.checkbox('Send receipt').check();
await editor.button('Save').press();

// Matchers observe the current state immediately.
expect(editor.button('Save'), isDisabled);

// A presented dialog is selected where it exists in the exposed tree.
final dialog = tester.target(
  role: SemanticRole.dialog,
  label: 'Invoice saved',
);
expect(dialog, hasCount(1));
await dialog.button('Done').press();
expect(dialog, hasCount(0));
```

The component, labels, and workflow above are illustrative. A production guide
should show their actual widget source and runnable test together. Implementation
can proceed once type/scope observation rules and the common-role boundary are
decided; broad locator operators, browser-style auto-wait, and per-widget
drivers can remain deferred.
