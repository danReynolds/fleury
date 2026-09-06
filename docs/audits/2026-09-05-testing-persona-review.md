# Testing DX: developer persona review

2026-09-05. Design feedback on the proposed shared testing targets and semantic
role vocabulary. These are simulated developer perspectives, not recruited
developers, interviews, measured usability results, or a framework benchmark.
The reviewers inspected the proposal, selected current source/tests, and official
documentation for their reference frameworks. They did not implement the facade
or execute the Fleury suite.

## Review brief and inputs

Each reviewer independently evaluated selection, actions, observations, waiting,
custom widgets, and role granularity. They were asked for concrete counterexamples,
things to preserve, changes needed before implementation, and work to defer.
The parent supplied the same recent design context and corrected source pointers;
agreement between these reviews is design evidence, not independent human validation.

- [Current proposal](../implementation/rfc-testing-controls.md).
- [Suite inventory and focused contract audit](2026-09-05-testing-controls-suite-audit.md).
- [React Testing Library / user-event persona](2026-09-05-testing-persona-react.md).
- [Flutter persona](2026-09-05-testing-persona-flutter.md).
- [Textual persona](2026-09-05-testing-persona-textual.md).
- [Playwright persona](2026-09-05-testing-persona-playwright.md).

The latest chat proposal adds `tester.target(type: InvoiceEditor)` to the same
interface as role/label selection. The written RFC currently has only semantic
criteria and `SemanticNode` snapshots. Reviewers treated this discrepancy as an
unfinished design contract, not as an implemented feature or a regression.

## Results across the four perspectives

All four support a common target interface and oppose expanding the tester by
adding a driver for every widget. All four identified the structural-scope gap
and the need to distinguish logical actions from actual input. None treats the
65-entry role count alone as a reason to shrink the enum.

| Perspective | Most useful additional emphasis |
| --- | --- |
| React Testing Library | Stable purpose labels and an editable-field contract that survives more precise roles. |
| Flutter | Exact type matching, explicit frame/async boundaries, and clean callback tests using generic setValue. |
| Textual | Show keyboard evidence immediately; prioritize consistent capabilities; record opaque collection navigation. |
| Playwright | Internal/browser role-query differences and desired-state no-op behavior deserve explicit decisions. |

## Verified design gaps

### Structural scope and semantic target are different things

An InvoiceEditor widget may expose zero, one, or several semantic nodes. A type
query must not require that component to invent a semantic region merely to be
testable. The intended composition remains attractive:

```dart
final editor = tester.target(type: InvoiceEditor);
await editor.field('Customer').fill('Acme');
await editor.button('Save').press();
```

Before implementing it, specify type-only counting, semantic observations,
direct actions, exact-type matching, keys for repeated components, mixed
type/role criteria, root inclusion, and overlay boundaries. A composite's
`press()` must not silently choose a child button.

The existing [type finder](../../packages/fleury/lib/src/testing/finders.dart)
matches exact runtimeType. [SemanticTree.elementById](../../packages/fleury/lib/src/semantics/semantics.dart)
maps published nodes to their contributors, including synthetic table rows
that share a contributing widget. Scope filtering must preserve published
route/modal exclusions. Constructing a new semantic tree from an isolated
widget subtree could expose nodes excluded from the application's current tree.

### Stable names and editable-control contracts need to move together

The React review identified two concrete naming surprises:

- Select falls back to its current selected option as its semantic label;
  a query using that label can stop matching after the value changes.
- Autocomplete's `semanticLabel` names its suggestion menu, while
  `fieldSemanticLabel` names its text input.

Exact matching is appropriate, but examples and built-in naming contracts
should identify a control's purpose independently of its changing value.
Do not compensate with fuzzy fallback rules.

The proposed `field`/`fill` contract is restricted to textField/textArea roles.
Introducing a more precise editable combobox or numeric role must not
accidentally remove an otherwise valid text-editing operation. Define the
editable-text contract using the relevant role, state, and capabilities; generic
setValue alone is insufficient because sliders and tables expose it too.

### Action and asynchronous completion promises need executable examples

Logical press is readable and can retain semantic activation plus its resulting
frame. It does not establish keyboard routing, pointer hit testing, or focus
traversal. Pair it with a real Enter/shortcut example on the same control at
first use, and preserve existing input-focused regression tests.

The proposal awaits a semantic handler's returned Future. A custom handler
returning a held-open save Future therefore keeps `await target.press()` pending;
a normal Button that starts separate async work may return before the save.
Qualify both shapes, including the sequence that starts an action, observes
pending UI, completes fixture-owned work, and awaits the action. An idle UI is
not proof that every external request has finished.

### Internal roles and browser roles already differ

The [web presenter](../../packages/fleury_web/lib/src/semantics/semantic_dom_presenter.dart)
already projects richer Fleury roles onto ARIA categories. Examples include
command/approval to button, patchFile to listitem, and toolCall/tokenMeter to
status. The proposed `button()` shortcut matches only the exact internal button
role. Consequently browser and in-process role queries can select different sets.

Document this boundary and audit the useful control meaning of domain nodes.
Neither removing domain roles based on enum size nor quietly broadening
`button()` with a growing exception list is an adequate design rule. Preserve
existing inspection/wire information during any separate taxonomy migration.

## Additional feedback worth retaining

- **Controlled callback tests can keep the common facade.** Flutter's reviewer
  pointed out that `checkbox(...).setValue(true)` followed by a callback
  assertion already expresses a request without check()'s state postcondition.
  The plan need not send every callback-contract test to raw semantic dispatch.
- **Collection navigation remains awkward.** Textual's reviewer flagged
  `table.setValue(5000)` as an opaque spelling for selecting and revealing a
  clamped row index. Record this as collection DX work; retain explicit
  selection/window assertions while designing a shared operation later.
- **Diagnostics are part of the custom-widget interface.** Review failures for
  missing/ambiguous scopes, unavailable actions, read-only fields, denied focus,
  and missing checked state alongside successful examples. Each should show
  the requested operation, scope, matched role, and relevant capabilities,
  while preserving redaction.

## A real design disagreement: an already-checked disabled control

The current RFC requires enabled state and setter capability even when check()
would make no change. The Playwright persona recommends checking the observed
state first, following [Playwright's documented ordering](https://playwright.dev/docs/api/class-locator#locator-check):

```dart
await tester.checkbox('Required policy').check();
```

If this control is already checked and disabled, the persona argues that ensuring
the requested state should succeed without dispatch. Availability would be a
separate assertion when the test needs to prove that the user can change it.
The stricter RFC instead treats check() as an interaction request whose
availability must always be established.

Parent assessment: prefer the desired-state interpretation, because check()
already differs from press() by promising an observed state and avoiding
duplicate changes. Still require one match and a meaningful checked state;
when a change is required, preserve enabled/capability checks, single dispatch,
frame completion, and the postcondition. Record this as a proposed revision,
not a unanimous reviewer recommendation or an implemented behavior.

## Proposed disposition

Keep one reusable target, a few selector aliases, strict unique actions, fresh
resolution, shared semantic dispatch, redacted errors, and explicit input APIs.
Do not add per-widget tester classes or an adapter registry.

Revise the target/scope model, naming examples, editable-control contract, and
completion examples before considering the facade specification ready to
implement. Keep the already identified MultiSelect desired-state capability
correction in the implementation scope. Assess new roles together with their
actual widget behavior and consumers. Broad role removal, automatic waiting,
automatic scrolling, and a large gesture surface remain separate decisions.

The role review should distinguish a missing generic UI concept from existing
domain information. Selection/grouping roles are candidates for useful additions;
rich role removal needs an actual consumer reason. If the current role model is
retained initially, document exact internal-role matching and the web projection
gap. Do not claim cross-surface selector equivalence.

The RFC and production files are unchanged by this persona review. The reports
are review inputs and recommendations, not newly accepted implementation contracts.
