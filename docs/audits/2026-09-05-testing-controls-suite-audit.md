# Testing controls: suite audit

2026-09-05. Review input for the [implementation proposal](../implementation/rfc-testing-controls.md).
No production API or existing test was changed by this audit.

## Scope and evidence

The static pass parsed every owned `*_test.dart` file reported by `rg --files`
under `packages` and `website`: **404 files**, 149,583 source lines, and 4,904
test-registration call sites (2,838 `test`, 2,066 `testWidgets`). There were
zero parser diagnostics after enabling the repository's dot-shorthand syntax.
Registration sites inside loops count once; these are not executed-test totals.

This is a complete syntax inventory followed by detailed review of interaction,
semantics, input, control, form, navigation, identity, and application examples.
It is not a claim to have manually read every line or rerun the complete suite.
The inventory excludes four Dart peer-fixture suites and an archived audit
test. The 17 owned Dart support/fixture files were separately inventoried;
the core harness dependency boundary was inspected. Other test-tree artifacts
are fixtures, goldens, and support data, not additional owned JS/Rust suites.

The [inventory script](2026-09-05-testing-interaction-evidence/suite_inventory.dart)
emits raw AST records. The committed [inventory summary](2026-09-05-testing-interaction-evidence/suite_inventory.json)
records aggregate counts, every file's SHA-256, and every direct
`tester.invokeSemanticAction` call with its source line and arguments.
The scanner records syntax, not resolved receiver types or runtime coverage.

| Package/test tree | Files |
| --- | ---: |
| `packages/fleury` | 244 |
| `packages/fleury_widgets` | 81 |
| `packages/fleury_web` | 41 |
| `packages/samples` | 10 |
| `packages/storybook` | 8 |
| `packages/fleury_mcp` | 8 |
| `website/examples` | 6 |
| `packages/fleury_test` | 3 |
| `packages/fleury_git` | 1 |
| `packages/fleury_themes` | 1 |
| `packages/fleury_example_console` | 1 |

Selected source-call counts:

| Operation | Calls | Files |
| --- | ---: | ---: |
| Semantic invocation | 287 | 62 |
| `semantics()` | 677 | 92 |
| `sendKey` | 733 | 87 |
| `sendMouse` | 352 | 40 |
| `type` | 183 | 37 |
| `press` | 88 | 10 |
| `paste` | 33 | 5 |
| `invokeCommand` | 26 | 7 |
| `render` | 1,309 | 153 |
| `renderToString` | 471 | 99 |
| `matchesGolden` | 59 | 7 |

The semantic invocations name **49 distinct roles explicitly**, plus 48
node/ID-based invocations. They use all 17 current actions: activate 99,
setValue 52, open 23, submit 22, focus 20, copy 17, navigate 13, close 9,
select 9, increment 7, dismiss 5, clear 3, diagnose 2, cancel 2,
decrement 2, captureDebug 1, start 1.

The highest-volume semantic consumers include the example console (35),
documentation snippets (25), Select (14), controls (11), and both forms
showcases (9 each). This is broader than the testing guide's counter/editor.
110 files use at least one recorded key, text, paste, pointer, or key-lifecycle
input method. Those tests often intentionally exercise input routing.

## Fit of a shared target API

| Existing family | Recommended treatment | Representative evidence |
| --- | --- | --- |
| Counter, save/retry, buttons, editable fields | Use the new target API in behavior examples. Keep real state/callback assertions. | [guide tests](../../website/examples/test/testing_guide_test.dart), [snippet tests](../../website/examples/test/doc_snippets_test.dart) |
| Forms, validation, nested fields, custom composites | Shared `submit`, `fill`, focus and snapshots; no FormTester or per-field adapter. | [forms](../../packages/fleury_widgets/test/form_test.dart), [showcase](../../packages/storybook/test/forms_story_test.dart) |
| Select, MultiSelect, radio, switch, stepper, date, range | Same target, advertised actions and values; fix checkbox capability inconsistency before promising `check`. | [Select](../../packages/fleury_widgets/test/select_test.dart), [controls](../../packages/fleury_widgets/test/controls_test.dart), [range](../../packages/fleury_widgets/test/range_slider_test.dart) |
| Trees, table rows/cells, tabs, menus | Shared scope/identity and open/select/press/copy actions; preserve input-specific tests. | [tree](../../packages/fleury_widgets/test/tree_test.dart), [table](../../packages/fleury_widgets/test/data_table_test.dart), [tabs](../../packages/fleury_widgets/test/tabs_test.dart), [menu](../../packages/fleury_widgets/test/menu_test.dart) |
| Commands, tasks, logs, diagnostics, approvals, conversation and patch widgets | Same target and generic `perform(action)` for less common operations; retain command result/lifecycle assertions. | [console](../../packages/fleury_example_console/test/demo_console_test.dart), [command showcase](../../packages/samples/test/commands_showcase_test.dart) |
| Keyboard routing, spatial focus, drag, scrolling, undo, paste, composition, clipboard policy | Retain concrete input paths. A semantic operation cannot replace the behavior these tests establish. | [focus](../../packages/fleury_widgets/test/focus_traversal_dx_test.dart), [text area](../../packages/fleury/test/widgets/text_area_test.dart), [text input](../../packages/fleury/test/widgets/text_input_test.dart) |
| Frame phases, layout, pixels, goldens, animation, clipping, viewport geometry | Retain render/frame APIs and structural assertions. New actions may make setup easier, not replace evidence. | [frames](../../packages/fleury/test/testing/frame_contract_test.dart), [table virtualization](../../packages/fleury_widgets/test/data_table_test.dart) |
| Core semantic conformance, IDs, rejection statuses, protocol/DOM/remote/MCP, security, process lifecycle, pure units | Keep existing low-level APIs and assertions. Avoid migrating tests of the substrate to its new facade. | [identity](../../packages/fleury/test/semantics/semantic_identity_test.dart), [conformance](../../packages/fleury_widgets/test/semantic_contract_conformance_test.dart), [remote](../../packages/fleury/test/remote/serve_semantics_parity_test.dart) |

## Confirmed edge cases

Five focused runtime checks passed in the [edge probe](2026-09-05-testing-interaction-evidence/edge_contract_probe.dart);
the [receipt](2026-09-05-testing-interaction-evidence/edge_contract_probe.json)
records them. These establish existing behavior, not readiness of the new API.

1. **Checkbox state is not always its value.** A `MultiSelect` option exposes
   its option key as `value`, while `checked` is boolean. An option with value
   `red` can be checked. `isChecked`/`isUnchecked` must inspect `checked`;
   `hasValue(true)` is not a general checkbox assertion. See
   [option semantics](../../packages/fleury_widgets/lib/src/select.dart).
2. **MultiSelect lacks the desired-state capability.** Its checkbox options
   currently advertise focus and activation, but not `setValue`. A standalone
   Checkbox, Toggle, and Switch accept boolean values. Add boolean setting to
   MultiSelect's shared semantic contract, keeping the option key unchanged.
   Do not hide this with a tester branch for `MultiSelect` or a toggle fallback.
3. **Completed dispatch is not accepted value.** Select intentionally ignores
   an unknown option and reports completed dispatch. NumberInput similarly
   rejects invalid replacement through its normal controller listener.
   DatePicker tests pin invalid-date no-ops; DataTable and range controls can
   clamp values. General `setValue`/`fill` must preserve these behaviors and
   require outcome assertions. A future strict option-selection API would need
   an explicit accepted/rejected contract; it is outside this change.
4. **The guide's confirmation is currently a region.** `_DiscardDialog` uses
   a titled `Panel`, so `dialog('Discard changes?')` would not match it today.
   Use the real `Dialog` widget during guide migration and verify geometry.
   The probe also confirms covered editor controls disappear from the
   semantic tree while the modal is active. Preserve that shared navigation
   policy; the tester must not create its own hidden-route rules.
5. **Controlled widgets need a rebuilding owner.** A bare Checkbox with an
   `onChanged` recorder sends a callback but continues displaying the value
   passed by its parent. A desired-state `check` postcondition should expose
   that difference. Behavior tests use a host that applies the change; widget
   callback-contract tests keep low-level invocation and assert the callback.

## Additional acceptance cases revealed by the suite

- **Focus is observable behavior.** The new `fill` adds focus compared with
  bare semantic setting. Focus can clear errors, open completion UI, or
  replace controls. Validate capability/editability before focusing, require
  focus to succeed, then revalidate the same target within that operation.
  Abort on remount/retarget; do not fill a replacement accidentally. Across
  separate operations, a saved query intentionally resolves the current match.
- **Absence and multiplicity need an API.** Dialog dismissal, filtered rows,
  empty palettes, and missing text already appear in tests. Provide snapshots
  and a count matcher for zero/many results, with strict single-target actions.
  Missing a scope must be an error, not a passing empty-child assertion.
- **Virtualized rows do not exist until exposed.** The table's 100,000-row
  test uses `setValue(5000)` on the table to bring a row into its semantic
  window. Retain that explicit operation; never auto-scroll or manufacture
  offscreen nodes. Collection counts describe published semantic nodes, which
  can include headers, not the total application dataset.
- **RangeSlider value is context-sensitive.** Setting a scalar moves the
  active handle. Switching handles is currently keyboard-driven. Keep that
  contract explicit in generic examples; do not claim `setValue` is a universal
  replacement for a widget's whole value. A handle-specific semantic API is
  separate control DX work if direct two-handle automation is needed.
- **Read-only and redacted fields remain meaningful.** Generic editable-text
  actions may operate on NumberInput, PasswordInput, Autocomplete, and
  CompletionTextInput because they publish text-field semantics. Retain their
  filters, callbacks, form validation, composition, and redaction policies.
  Secret value assertions must not expose either the actual or expected secret
  through matcher diagnostics. Test persistence through a fixture-owned callback
  when the semantic value is intentionally redacted.
- **Opening, closing and submitting are requests.** A PopScope can veto a
  close; validation can reject submit. Keep an explicit assertion on the
  resulting UI. Do not turn every action into an implicit eventual-state wait.
- **Synthetic contributors and strict identity matter.** Table rows/cells
  share a contributor element; stable IDs, positional identities, reordering,
  duplicate labels, nested scopes, and disabled siblings are all real cases.
  Resolve a scoped target uniquely, then dispatch by its resolved ID through
  the existing contributor mapping. Never re-dispatch by a global label.
- **Core package ownership limits migration.** Its
  [test harness](../../packages/fleury/test/support/harness.dart) deliberately
  avoids a dev-dependency on `fleury_test` to prevent a publication cycle.
  Add the facade in `fleury_test`; test necessary core fixes with the existing
  core harness. Do not change imports across the 244 core test files.

## Result

The original three control-specific helpers fit the guide but are not a
sufficient general design. The updated proposal uses one live target type,
a common action vocabulary, shared assertions, and three optional selector
aliases. New widgets reuse their published semantics. The migration is
behavior-focused and preserves tests of actual input and framework contracts.
The full repository check remains a later implementation gate; this audit ran
only its focused probes, not the full suite.
