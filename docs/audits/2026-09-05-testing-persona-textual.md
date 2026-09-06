# Testing DX review: a Textual developer adopting Fleury

2026-09-05. Simulated developer persona, not an interview or measured usability study. The perspective is an experienced Textual author building keyboard-heavy tools and custom compound widgets. Findings below distinguish observed code/API facts from design judgment. This review changes no production code or proposal.

Reviewed the shared-target RFC, suite audit, current semantic enum, first testing-guide examples, actual focus/table/editor tests, semantic coverage consumer, and DOM accessibility projection. The latest chat proposal adds `target(type: InvoiceEditor)` as a structural scope before semantic selection; that addition is not yet reflected in the RFC signatures or its snapshot model. Official Textual documentation and source were checked for this review. No Fleury tests were executed for this design review.

## Overall assessment

One reusable target with common operations is a good direction. It can be easier to maintain than acquiring widget instances and calling their individual APIs. For a TUI developer, the strongest benefit is reliable control identity and useful errors while layouts and custom implementations change.

The main unfinished work is not choosing a final number of roles. It is making structural scopes, logical operations, actual input, and completion boundaries predictable. The first two findings should be settled before implementation. The remaining findings should become explicit acceptance cases or separately tracked DX work.

## 1. High priority: a custom component must be a usable scope without inventing a semantic root

**Observed.** Textual queries accept a widget type or selector, and queries on a widget search its descendants. This gives a custom editor a natural testing boundary without a semantic annotation. Its `query_one` documentation describes returning the first matching widget, whereas Fleury deliberately proposes strict uniqueness; Fleury should preserve that stronger test default. [Textual DOM queries](https://textual.textualize.io/guide/queries/)

Fleury's current structural finders return elements and match types by exact `runtimeType`, while the RFC's new target searches semantic descendants and exposes only `SemanticNode` snapshots. These are different result domains. The chat example is attractive, but cannot be implemented merely by adding a `type` parameter to the existing semantic query. [Finders, lines 40–46 and 136–144](/Users/dan/Coding/fleury/packages/fleury/lib/src/testing/finders.dart:40), [RFC, lines 119–164](/Users/dan/Coding/fleury/docs/implementation/rfc-testing-controls.md:119)

**Persona judgment.** `tester.target(type: InvoiceEditor).button('Save')` is exactly the sort of local, readable composition I would want. Requiring the editor to add `Semantics(role: region)` solely to make that test work would be an unnecessary authoring tax. A custom canvas or keyboard surface should also remain testable using its real input path when it has no semantic actions.

**Before implementation.** Specify that a structural match can establish a scope with no semantic root. Child semantic queries use published semantic nodes associated with that subtree and preserve active-route/modal exposure rules. Do not infer that the composite itself is pressable because it happens to contain one button. Define what `snapshot`, `snapshots`, and `hasCount` mean for a type-only target; their current semantic-only contracts are incomplete for this case. Preserve exact type matching unless deliberately changing it, and provide a key-based way to distinguish repeated editors without forcing new semantic IDs onto them.

Acceptance examples should include a custom composite with zero, one, and several semantic roots; two instances with repeated Save labels; a remounted editor; a synthetic table contributor inside the editor; and a hidden editor beneath a modal. No tester adapter or new role should be required.

## 2. High priority: show keyboard input alongside logical press at the first example

**Observed.** Textual's Pilot separates simulated keys from simulated mouse clicks. The click API uses a widget/selector as a coordinate origin; occlusion can cause a click to hit another widget. Separately, `Button.press()` posts its logical pressed message or schedules its action, and returns without acting when disabled or not displayed. These are not interchangeable promises. [Pilot API](https://textual.textualize.io/api/pilot/), [Button source](https://github.com/Textualize/textual/blob/main/src/textual/widgets/_button.py)

Fleury's RFC correctly keeps semantic press separate from keyboard/pointer input. Its actual focus suite proves spatial traversal and Tab order through real keys; the table suite proves PageDown scrolling and Enter selection. The guide currently gives the distinction in prose after the semantic counter and later demonstrates Ctrl+S. [RFC, lines 266–278](/Users/dan/Coding/fleury/docs/implementation/rfc-testing-controls.md:266), [focus test, lines 77–104](/Users/dan/Coding/fleury/packages/fleury_widgets/test/focus_traversal_dx_test.dart:77), [table test, lines 475–519](/Users/dan/Coding/fleury/packages/fleury_widgets/test/data_table_test.dart:475), [guide, lines 95–99 and 145–160](/Users/dan/Coding/fleury/website/src/content/docs/guides/testing.mdx:95)

**Persona judgment.** Logical `button('Save').press()` reads naturally, but a TUI author's first interpretation may include focus and Enter handling. Prose alone makes it easy to miss that a broken key handler can coexist with a passing logical test. I would keep the verb and make the difference visible immediately with two short counter tests: one invokes the control, one presses Enter on the initially focused control. The existing autofocus counter makes this inexpensive to teach.

**Before implementation.** Make paired logical/input examples part of guide acceptance, and protect a representative key/focus test from migration. Keep the strict failure policy for semantic operations; do not copy Textual's silent disabled return into the test facade. A semantic selector should eventually be usable with a genuine pointer operation, but a pointer helper can remain separate work. Renaming semantic press to click would misstate its behavior.

## 3. High priority: make pending asynchronous actions demonstrable for custom semantic controls

**Observed.** The RFC awaits the semantic handler and then completes a frame. Its one-frame rule is explicitly not a promise that the handler finishes promptly. Work launched separately by a void callback may remain pending, whereas a custom handler returning the service future keeps the target operation pending. The existing editor uses `unawaited(save())`; its pending-save example therefore demonstrates only the former shape. [RFC, lines 280–290](/Users/dan/Coding/fleury/docs/implementation/rfc-testing-controls.md:280), [editor source, lines 90 and 111–121](/Users/dan/Coding/fleury/website/examples/lib/testing_guide.dart:90), [pending-save test, lines 46–109](/Users/dan/Coding/fleury/website/examples/test/testing_guide_test.dart:46)

Textual teaches an event-processing pause when posted messages have not yet been handled. That is a recognizable concept for this persona, but does not establish that a background service finished. Fleury should retain its more explicit ownership model rather than copying a generic pause everywhere. [Textual testing guide](https://textual.textualize.io/guide/testing/#pausing-the-pilot)

**Persona judgment.** I could write `await save.press()` followed by `request.complete()` and unintentionally wait forever with a custom semantic contributor. The same-looking control then behaves differently from the introductory Button example because of callback ownership. The RFC acknowledges this; the examples need to make it usable.

**Before implementation.** Add a custom asynchronous contributor fixture whose handler returns a controlled future. Document and verify the supported sequence for starting the action, exposing pending UI, completing the request, and finally awaiting the action. If the current harness cannot provide that sequence cleanly, resolve that completion contract before advertising custom async actions as equally convenient. Do not add automatic settling or service polling to hide the distinction. This is an acceptance gap, not evidence that the existing dispatcher is incorrect.

## 4. Medium priority: useful role contracts matter more than parity with a role catalog

**Observed.** The enum mixes general UI concepts and rich domain concepts. The DOM presenter already projects several rich roles into ordinary ARIA roles: `patchFile` becomes `listitem`; `toolCall` and `tokenMeter` become `status`. Semantic coverage also treats domain containers differently from readable content. This is an existing inspection/accessibility boundary, not simply accidental unused names. [Enum, lines 40–105](/Users/dan/Coding/fleury/packages/fleury/lib/src/semantics/semantics.dart:40), [DOM role projection, lines 509–571](/Users/dan/Coding/fleury/packages/fleury_web/lib/src/semantics/semantic_dom_presenter.dart:509), [coverage, lines 263–288](/Users/dan/Coding/fleury/packages/fleury/lib/src/semantics/semantic_coverage.dart:263)

The suite audit found a more immediate inconsistency: MultiSelect options claim checkbox meaning and expose checked state, yet lack the boolean setting capability offered by other checkbox-like controls. The RFC addresses this in shared widget semantics rather than a tester workaround. [Suite audit, lines 89–105](/Users/dan/Coding/fleury/docs/audits/2026-09-05-testing-controls-suite-audit.md:89), [RFC, lines 313–331](/Users/dan/Coding/fleury/docs/implementation/rfc-testing-controls.md:313)

**Persona judgment.** A TUI author is likely to care more that every checkable option can be operated predictably than whether the enum has 30 or 65 entries. Rich roles may help inspect domain tools; they should not become a requirement for each custom widget. A `comboBox`/`listBox`/`option` distinction is worth evaluating for real selection widgets, but adding those names without consistent state, actions, and child relationships would increase learning cost without improving testing.

**Before implementation.** Keep the MultiSelect correction and add a small contract matrix for the roles exercised by the first helpers. Document their states, operations, and rejection behavior. **Defer** domain-role removal and broader role expansion to a consumer-aware taxonomy audit. Do not drop inspection information just to match a browser vocabulary, and do not treat widget-class names as role admission criteria.

## 5. Medium priority: virtualized collection tests are expressible but still obscure

**Observed.** The table test first establishes that row 5000 is absent from the published tree, then calls table `setValue(5000)` to select and reveal it. Out-of-range indices clamp. Separate keyboard tests verify that PageDown moves the viewport and selection. The proposed facade preserves that same scalar operation. [Table tests, lines 166–223](/Users/dan/Coding/fleury/packages/fleury_widgets/test/data_table_test.dart:166), [RFC, lines 238–248](/Users/dan/Coding/fleury/docs/implementation/rfc-testing-controls.md:238)

**Persona judgment.** `runs.setValue(5000)` is not self-explanatory as selection and reveal. It also means a supposedly observational setup step changes selection. A common target removes boilerplate, but does not by itself make this contract intuitive. This is a real DX issue exposed by the guide/audit, and should not be dismissed because the existing tests are expressible.

**Before implementation.** Keep the example explicit about index, selection side effect, published window, and clamping; assert the selected key as well as visible range. Scope the row lookup after revealing it, and state that semantic counts are neither total dataset size nor necessarily data-row counts. **Defer** a shared collection navigation/reveal operation until its contract has been checked across table, tree, and list. Do not add auto-scrolling to the finder or invent offscreen semantic nodes.

## 6. Medium priority: make unsupported operations an approachable custom-widget path

**Observed.** The same FleuryTarget proposes 12 operations, with runtime capability checks. Even `fill` requires a particular role family plus focus and value capabilities, and desired-state checking has a stronger postcondition than plain `setValue`. The RFC already promises capability-specific diagnostics. [RFC, lines 166–197](/Users/dan/Coding/fleury/docs/implementation/rfc-testing-controls.md:166), [operation contracts, lines 294–331](/Users/dan/Coding/fleury/docs/implementation/rfc-testing-controls.md:294)

**Persona judgment.** A shared class is simpler than a growing family of driver classes, but autocomplete alone cannot teach which operations apply. For custom authors, a failed `field.fill(...)` needs to distinguish wrong role, missing focus handler, read-only state, and focus refusal. Otherwise “custom controls work too” feels clean only in the happy-path screenshot.

**Before implementation.** Treat a sample diagnostic as a reviewed artifact: include the full query and scope, resolved role, failed precondition, and advertised actions. Add one source/test example of a custom contributor with the required state and handlers, next to an ordinary composite that needs no new semantics. Keep role-specific state on snapshots rather than adding a matcher or driver for every property. **Defer** extra selector aliases and adapter registries until repeated application examples justify them.

## Preferred API examples

These use the proposed API, not current production syntax. The custom editor is a structural scope and does not need its own semantic root:

```dart
final editor = tester.target(type: InvoiceEditor);

await editor.field('Customer').fill('Acme');
await editor.button('Save').press();
expect(savedInvoice.customer, 'Acme');
```

A separate test exercises the shortcut after putting editing focus in a known place:

```dart
final editor = tester.target(type: InvoiceEditor);

await editor.field('Customer').focus();
tester.type('Acme');
tester.press(KeySequence.ctrl.s);
await tester.settle(); // Fixture-owned save completes immediately.
expect(savedInvoice.customer, 'Acme');
```

The first test validates the logical operation; the second validates the shortcut from an editing context. Focus traversal gets its own test using Tab/arrow keys; explicitly focusing a field does not prove that users can navigate to it.

## Preserve and defer

Preserve one target type, three optional selector aliases, strict uniqueness, fresh resolution, scoped diagnostics, no availability-based identity guesses, published semantic state, controlled async fixtures, and genuine input/rendering coverage. These are valuable improvements independent of a role taxonomy cleanup.

Settle structural-scope observation and action rules, demonstrate pending custom handlers, and make first-guide input boundaries visible before implementing the public facade. Implement the already-identified MultiSelect semantic correction with the helpers. Track collection reveal ergonomics and domain-role projection separately; do not expand the initial tester surface merely to claim complete parity with another framework.
