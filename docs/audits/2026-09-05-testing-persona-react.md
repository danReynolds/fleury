# Testing DX persona review: React Testing Library and user-event

2026-09-05. This is a simulated developer perspective, not interviews or measured usability research. The reviewer adopts the expectations of a developer comfortable with React Testing Library and user-event, then tests those expectations against Fleury's source and proposal. Source inspection and official documentation verification only; no production tests or implementation changes were made.

Reviewed the [proposal](../implementation/rfc-testing-controls.md), [suite audit](2026-09-05-testing-controls-suite-audit.md), guide, actual controls, selected tests, and the web semantic presenter. The latest chat proposal adds `type:` to the same target interface; that addition is not yet in the written proposal and is evaluated as an unresolved design change.

## Judgment

Keep one reusable target with strict actions and a few aliases. The role count is not the main DX problem. The important gaps are where a developer cannot predict what a selector means: widget scope versus semantic node, control name versus changing value, editable fields versus their eventual more precise roles, and Fleury roles versus their browser projection.

The current design is close enough to specify and prototype. Resolve findings 1–3 before freezing the interface; findings 4–6 primarily constrain documentation, qualification, and follow-up work.

## 1. High: type scoping needs a contract before it joins the semantic interface

**Observed fact.** The proposal defines every target as a semantic query with a `SemanticNode` snapshot and semantic descendants ([proposal:131](../implementation/rfc-testing-controls.md#L131)). Existing type finders instead match element `runtimeType` exactly ([finders:40](../../packages/fleury/lib/src/testing/finders.dart#L40)). An application composite may have no semantic node, or contribute multiple descendants. Select mounts its popup through an overlay ([Select:200](../../packages/fleury_widgets/lib/src/select.dart#L200)).

**Persona judgment.** This reads well:

```dart
final editor = tester.target(type: InvoiceEditor);
await editor.button('Save').press();
```

But I cannot infer what `editor.snapshot`, `editor.press()`, or `target(type: InvoiceEditor, role: button)` mean. Does a type select one component, its first semantic root, or every semantic node underneath it? Does its popup count as underneath it? One target class does not eliminate these decisions.

**Before implementation.** Specify type matching, structural cardinality, structural-to-semantic scoping, whether a scope includes its root, and what observations/actions on a type-only target allow. Do not silently choose a descendant's primary action. Prefer explicit chaining in examples; reject an undefined mixed selector rather than assigning it an accidental meaning. Type scoping should intersect the published semantic tree, preserving hidden-route exclusions. An overlay that is outside the selected subtree should require a new root query unless an explicit ownership relationship is part of the contract.

Keep type selection available for component integration tests. Lead application behavior examples with role and name when they are sufficient. Testing Library binds `within` to a concrete DOM container; it does not imply React ownership scoping. [Official within documentation](https://testing-library.com/docs/dom-testing-library/api-within/)

## 2. High: predictable names matter more than additional selector conveniences

**Observed fact.** Button publishes its visible label directly ([controls:870](../../packages/fleury_widgets/lib/src/controls.dart#L870)). TextInput uses `semanticLabel`, then placeholder ([TextInput:1582](../../packages/fleury/lib/src/widgets/text_input.dart#L1582)). Select uses `semanticLabel`, then its current option label, and also exposes that option label as value ([Select:343](../../packages/fleury_widgets/lib/src/select.dart#L343)). Autocomplete's `semanticLabel` names its suggestion menu; `fieldSemanticLabel` names the field ([Autocomplete:58](../../packages/fleury_widgets/lib/src/autocomplete.dart#L58)).

**Persona judgment.** I would naturally write `Autocomplete(semanticLabel: 'Customer')` and then `tester.field('Customer')`. That does not name the field under the current contract. I could also retain `tester.button('Red')` for an unnamed Select, set its value to Blue, and find that my reusable query no longer matches. The resolver is behaving correctly; the control's identity is poorly expressed.

**Before implementation.** Publish a short naming table for built-in controls, and require representative examples to name a field's purpose independently of its value. Decide whether Autocomplete's naming props should change or remain with conspicuous documentation. Do not compensate with fuzzy label matching or fallback to visible text. Preserve exact matching and duplicate failures.

Testing Library's role queries use the accessible name, which may come from a form label or button content. Its query guidance distinguishes names from placeholders and values. Fleury can retain the word `label`, but it must say that this means the node's semantic name, not arbitrary nearby text. [ByRole](https://testing-library.com/docs/queries/byrole/), [query guidance](https://testing-library.com/docs/queries/about/)

## 3. High: coordinate field/fill with the role taxonomy before hard-coding the two-role family

**Observed fact.** `field` currently means textField/textArea, and `fill` explicitly requires those roles ([proposal:80](../implementation/rfc-testing-controls.md#L80), [proposal:296](../implementation/rfc-testing-controls.md#L296)). NumberInput builds TextInput ([NumberInput:278](../../packages/fleury_widgets/lib/src/number_input.dart#L278)). Autocomplete currently publishes a text field plus menu/menuItem suggestions ([Autocomplete:292](../../packages/fleury_widgets/lib/src/autocomplete.dart#L292)). The discussion proposes assessing comboBox/listBox/option and more precise numeric roles.

**Persona judgment.** A future accessibility improvement must not make `field('Customer').fill('Acme')` stop working simply because Autocomplete acquired a comboBox role. Conversely, accepting every `setValue` target would incorrectly treat sliders and tables as editable text.

**Before implementation.** Define the exact semantic property that makes something an editable text target, including how role and advertised capabilities participate. Prove the rule with TextInput, TextArea, PasswordInput, NumberInput, editable autocomplete, and a select-only dropdown. No new widget-specific tester class is necessary. Either keep the initial role family explicitly provisional, or settle the near-term role changes and update the field contract together.

Combobox is a justified candidate because it expresses input with an associated choice popup and distinguishes editable from select-only behavior. Not every menu or group of checkboxes should be renamed to a listbox: inspect the actual interaction first. [WAI combobox pattern](https://www.w3.org/WAI/ARIA/apg/patterns/combobox/), [WAI listbox pattern](https://www.w3.org/WAI/ARIA/apg/patterns/listbox/)

## 4. Medium: document the two role vocabularies; do not remove domain information merely to match ARIA

**Observed fact.** Fleury already has an explicit web projection: command and approval map to browser button; patchFile to listitem; toolCall and tokenMeter to status; textField/textArea to textbox ([presenter:509](../../packages/fleury_web/lib/src/semantics/semantic_dom_presenter.dart#L509)). The proposed `button` alias matches the exact Fleury button role. Therefore a browser role query and an in-process Fleury role query do not necessarily select the same set of nodes.

**Persona judgment.** This is more significant than whether there are 30 or 65 enum values. A React developer expects `getByRole('button')` to mean the accessible button category. Fleury currently exposes a richer internal vocabulary, which can be valuable to agents and inspectors but needs a clear boundary.

**Before implementation.** State whether `role:` always means the exact internal Fleury role. Make that visible in failures and a compact role reference. Do not quietly add inheritance or make `button` search every role that maps to ARIA button. Testing Library itself matches roles literally rather than through an inheritance hierarchy. [ByRole](https://testing-library.com/docs/queries/byrole/)

**Defer.** Decide whether general UI category plus domain metadata would improve this model after auditing consumers. The existing projection is evidence of an intentional boundary, not evidence that all domain roles are unnecessary. Adding conventional missing roles should include state, relationships, dispatch behavior, and the web mapping, not just enum entries.

## 5. Medium: logical press is useful, but user-event users will overestimate its input coverage

**Observed fact.** The plan explicitly defines `press` as one semantic activation and `fill` as focused semantic replacement; it preserves real keys and pointer APIs ([proposal:266](../implementation/rfc-testing-controls.md#L266)). The revised guide already explains this near the first example and retains Ctrl+S ([guide:95](../../website/src/content/docs/guides/testing.mdx#L95)). Select's existing test intentionally changes the value without mounting its popup ([test:151](../../packages/fleury_widgets/test/select_test.dart#L151)).

**Persona judgment.** `await button.press()` looks like a user interaction. In user-event, interactions model multiple events plus interactability checks. Fleury's operation proves a narrower semantic contract, even when the application outcome is the same. [user-event introduction](https://testing-library.com/docs/user-event/intro/)

**Keep.** Deterministic logical actions, one resulting frame, strict disabled/unsupported failures, no adaptive pointer/key fallback, and separate actual input tests.

**Before guide adoption.** Include one adjacent example that focuses a control, sends the relevant key, and asserts the same outcome; explicitly identify what it additionally tests. Include a dropdown workflow that opens and selects an option, rather than teaching only direct setValue. Keep the existing input suites from the audit. A future pointer convenience can remain separate work.

## 6. Medium: strict scopes and absence are good; teach query lifetime and async lifetime with failure examples

**Observed fact.** The proposal's `snapshot` is strict, `snapshots` supports zero/many, missing parents fail, and actions re-resolve their query ([proposal:153](../implementation/rfc-testing-controls.md#L153)). Matchers preserve duplicate/missing failures under negation and redact secrets ([proposal:333](../implementation/rfc-testing-controls.md#L333)). Actions do not retry or settle arbitrary application work ([proposal:280](../implementation/rfc-testing-controls.md#L280)).

**Persona judgment.** This is a strong, small surface. I do not need get/query/find name families, but I do need to see that `final save = ...` stores a query, not a node, and that `await save.press()` does not wait for a separately started request. Testing Library distinguishes immediate required matches, optional absence, and eventual queries explicitly. [Query cardinality and waiting](https://testing-library.com/docs/queries/about/)

**Before guide adoption.** Show two identically labelled buttons disambiguated by a named scope, then a controlled async completion followed by an outcome assertion. Include failures for a missing parent scope and two matching parent components. Do not solve repeated labels by adding `.first()` or filtering away disabled matches.

**Defer.** Regex labels, a full selector DSL, generic retries, and one matcher per state property. Existing direct snapshots and explicit application completion are adequate for the first implementation.

## Small API I would be comfortable adopting

Proposed syntax; not an implemented API. This example assumes the application publishes a form named Invoice and a field named Customer, and its fixture-owned save callback records the result synchronously.

```dart
final invoice = tester.target(role: SemanticRole.form, label: 'Invoice');
final customer = invoice.field('Customer');
final save = invoice.button('Save');

await customer.fill('Acme');
expect(customer, hasValue('Acme'));
expect(save, isEnabled);
await save.press();
expect(savedCustomer, 'Acme');
```

For component integration tests, the first line can become `tester.target(type: InvoiceEditor)` once finding 1 is specified. The child selectors, operations, and assertions stay the same. For an overlay dialog, resolve a new root `target(role: SemanticRole.dialog, label: 'Discard changes?')` and scope its buttons there, rather than assuming the dialog is a descendant of the editor that opened it.

The essential bar is predictable selectors and precise action promises. It is compatible with a small common target API and a substantial shared role vocabulary.
