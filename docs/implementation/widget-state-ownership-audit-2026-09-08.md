# Widget state ownership audit

Date: 2026-09-08  
Status: convention implemented; validation receipts below  
Checkout: `codex/lists-scrolling-dx`, `d0120106` plus the existing ListView/DataTable and guide changes.

## Implementation

The approved convention is implemented across the core and widget packages,
repository callers, tests, API documentation, and guides. The durable contract
and breaking-name migration are in [Widget state ownership](../widget-state-ownership.md).

- NumberInput and FileBrowser now use genuine one-time seeds. FileBrowser has
  an explicit controller `openDirectory` command for later navigation.
- Supplied FileBrowser/SearchPanel cursors survive mount and replacement.
  Navigation constructors use `initialIndex` / `initialOffset`; live browsing
  properties use `currentIndex`. DataTable retains row/column-specific names.
- Nullable collection cursors distinguish default zero from explicit null.
  Tail following controls the viewport without silently choosing the cursor.
- Text callbacks report editing interactions, including semantic input, paste,
  history, and completion. Programmatic writes notify controller listeners and
  form state without echoing interaction callbacks through every observing field.
- Viewport controllers reject simultaneous owners, detach on deactivation,
  and support reattachment and GlobalKey moves. Pending writes do not clamp
  against the previous view's stale dimensions.
- JsonView uses `defaultExpandedDepth` for its continuing fallback policy;
  Tree retains the one-time `initialExpandedDepth` seed.
- The state guide demonstrates controlled values and controllers. The lists
  guide opens its task demo at row 25 and shows browsing, choosing, and scrolling.

Nineteen permanent ownership regressions cover seed/rebuild/remount behavior,
controller replacement, null cursors, callbacks and writeback, shared text views,
second-owner rejection, reattachment, and a GlobalKey move. Existing editing,
collection, wrapper, console, and Storybook tests were migrated as well.

The sections below retain the **pre-migration audit** and its original evidence;
API names, source line numbers, and observed behavior there describe that baseline.

## Original conclusion

Most widgets already fit two useful ownership models: parent-owned values and
widget/controller-owned state. Application code and user input writing the same
controller is sound: there is one authoritative value. The problematic cases
reapply a seed, overwrite an incoming controller, or use the same name for
different lifecycle behavior.

Keep both models. Fix the concrete ownership violations before doing broad
naming changes. No framework or guide behavior was changed for this audit.

## Accepted convention (original proposal)

| API shape | Owner and contract |
| --- | --- |
| `value` / `values` with `onChanged` | The parent owns the committed value. An interaction requests a new value; the parent must supply it on rebuild. Do not keep an independent committed copy. |
| Widget `initialValue`, `initialDirectory`, `initialExpandedDepth` | Seed widget-owned state once per State lifetime. Ordinary rebuilds never reapply the seed. A new key deliberately creates new state. |
| Optional `controller` | The supplied controller is authoritative for the state it represents. Without one, the widget creates and disposes its own controller. Application commands and interactions update that same state. |
| Controller constructor seeds | Used once when constructing the controller. Prefer `initialIndex` / `initialOffset` for navigation; mutable getters/setters retain their live names. |
| Live policy/configuration | Use a name that describes the continuing policy, such as `followTail` or `defaultExpandedDepth`. It may change on rebuild. It must not masquerade as `initial*`. |

A widget can have different owners for different state: a controlled selected
value alongside an internal popup cursor or an unfinished editing buffer is
legitimate. A controller need not own every piece of a composite widget.

Do not add a `value`, an `initialValue`, and a controller to every widget just
for symmetry. Where a widget accepts a seed and a controller for the same state,
prefer rejecting conflicting inputs rather than silently ignoring the seed.
Keep established `TextEditingController(text: ...)`: its constructor already
clearly initializes a new editing session and owns more than a scalar value.

List usage:

```dart
// Create once in State.
final list = ListController(initialIndex: 24);

// The list and application use the same live controller.
ListView.builder(controller: list, /* ... */);
list.currentIndex = 99;
```

`currentIndex` is the remembered browsing row. Its initial value should be
revealed on mount, subject to valid-item clamping and explicit viewport policy.
It neither takes keyboard focus nor emits `onSelect`. A completed click or Enter
is a choice event; it does not create a second persistent selected index.

### Notifications and lifecycle

- Proposed input rule: widget `onChanged`, `onFocusedItemChanged`, and choice
  callbacks describe interactions; controller listeners observe state changes
  from any origin. Semantic test/agent actions still count as interactions.
  Text editing currently deliberately differs; changing that requires the
  explicit migration described below.
- A supplied replacement controller brings its own state. Detach the old
  listeners, adopt the incoming state, and dispose only internally owned objects.
- Removing a controller currently creates fresh internally owned state in the
  inspected editing and collection widgets. Document this as a reset, not a
  promise to copy the outgoing controller. Keep controller ownership stable
  during ordinary editing; do not add automatic state transfer in this cleanup.
- Controllers holding one host's viewport metrics or row count should reject
  attachment to a second owning view. Value-only controllers may deliberately
  support multiple views. Observers and an associated scrollbar are not second
  owning views.
- For nullable row cursors, explicit `null` should mean no current row. Omitted
  defaults, empty data, clamping, and follow-tail policy must be specified
  separately. Do not force nullability on tabs or cells where it has no meaning.

## Original inventory

The source audit covered the public core/widget directories and 23 editing,
collection, and form controller classes. It inspected constructor seeds,
`initState`, `didUpdateWidget`, controller writes/listeners, and callback paths.
The probes below exercise selected divergences; they are not an exhaustive
lifecycle test suite or a performance/browser audit.

| Widgets / controllers | Current ownership | Recommendation |
| --- | --- | --- |
| Checkbox, Toggle, Switch, Radio, RadioGroup | Parent-owned `value` (Radio: `groupValue`) + callback | Keep. |
| Select, MultiSelect | Parent-owned value(s); internal popup/highlight state | Keep the separation. |
| Stepper, RangeSlider, DatePicker, ColorPicker | Parent-owned value; local entry/candidate state where needed | Keep. A browsing candidate or unfinished entry is distinct from the committed value. |
| TextInput, TextArea, PasswordInput, Autocomplete, CompletionTextInput | External or internally owned TextEditingController | Keep ownership; review callback origin below. |
| NumberInput | TextEditingController, or internal text seeded by `initialValue` | Stop reapplying the seed on rebuild. |
| ListView / ListController | Controller owns cursor and viewport | Constructor `initialIndex`; retain live `currentIndex`. |
| ScrollView / ScrollController | Controller owns offset and viewport metrics | Constructor `initialOffset`; retain live `offset`. |
| Tabs / TabController | `initialIndex` seeds live `index` | Already a clear model. Keep tab-specific naming. |
| Table / TableController | Live browsing cursor named `selectedIndex` | Align browsing terminology and default cursor with ListView. |
| DataTable / DataTableController | Live `currentRowIndex` / `currentColumnIndex`; separate selected cell range | Constructor `initialRowIndex` / `initialColumnIndex`; keep range selection distinct. |
| CodeView, ContextPanel, ConversationNavigator, DiffView, FileMentionPicker, MarkdownView, PatchReview, TaskGraph, TraceTimeline controllers | Constructor and live property named `selectedIndex`, delegating to ListController's browsing cursor | Align row cursor seeds to `initialIndex` and live state to `currentIndex` when migrating the remaining collection APIs. |
| JsonViewController, TreeTableController | Same cursor convention, plus explicit expansion sets | Align cursor names; make expansion seed/default behavior explicit. |
| LogRegionController, MessageListController | Nullable constructor index chooses first row or a tail sentinel according to follow policy | Separate explicit no-cursor from default/tail policy; avoid adding niche controls to the general guide. |
| FileBrowser / FileBrowserController | Widget owns directory; controller owns cursor | Honor incoming cursor; make `initialDirectory` one-time. |
| SearchPanel | Query TextEditingController and result ListController | Honor incoming result cursor on mount/replacement. Query changes can still deliberately reset results. |
| FilePicker | Internal directory seeded once; internal list | Keep the seed contract. No controller addition needed solely for symmetry. |
| Tree | Internal cursor and expansion set seeded once | Keep `initialExpandedDepth` as a seed. |
| Form / FormController / FormField | Controller coordinates validation/submission; application and field widgets own values | Keep. Existing single-host attachment check is a useful precedent. |
| TextHistoryController, TextCompletionController | History data/commands and completion-session commands | Keep distinct responsibilities; no reason to invent a generic scalar value interface. |

TextCompletionController's `selectedIndex` / `selectedOption` also identify the
current suggestion, before acceptance. Include those names in the eventual
browsing-cursor migration while retaining its `open` / `update` / `close` commands.

Supporting widgets do not all need one of the input APIs. FutureBuilder and
StreamBuilder seed `initialData` once; Overlay seeds `initialEntries` once.
Navigator reconciles `home` content without resetting its route stack; explicit
navigation methods own stack changes. Panel's optional `focused` is a visual
override of detected focus. Render-only data/configuration, action buttons,
transient menus/tooltips, and selection scopes should retain their natural
contracts rather than acquire unnecessary controllers.

## Pre-migration divergences

### 1. NumberInput reapplies `initialValue`

Seed 1, edit to 7, then rebuild the same widget with `initialValue: 9`: the field
becomes 9. Rebuilding with the unchanged seed would leave the edit alone, so this
is neither a true controlled value nor a one-time seed. The reset also suppresses
`onChanged`. With an external controller, the seed is silently ignored instead.

Source: `packages/fleury_widgets/lib/src/number_input.dart:149`.
Fix: seed only on state creation; use controller commands or deliberate remount
for later resets. Check callers relying on reactive `initialValue` before migrating.

### 2. FileBrowser and FilePicker disagree about `initialDirectory`

Mount each with directory A, then rebuild with B. FileBrowser navigates to B;
FilePicker stays in A. FileBrowser's directory lives in widget state, not in its
controller.

Sources: `file_browser.dart:229`, `file_picker.dart:80` in the widget package.
Fix: both names mean a seed. If ongoing application-driven directory navigation
is needed, provide an explicit navigation command on FileBrowser's controller.
Simply renaming the prop to `directory` while keeping independently mutable
internal navigation would not establish a controlled contract.

### 3. FileBrowser and SearchPanel discard supplied controller state

FileBrowserController seeded at row 2 ends at row 0 on first mount because
directory loading unconditionally resets the cursor. SearchPanel similarly
overwrites a supplied ListController at row 2; replacing it with a controller
at row 1 also resets to 0. FileBrowser's replacement path resets too.

Sources: `file_browser.dart:218,229,268,330`, `search_panel.dart:277,305,377`.
Fix: adopt and clamp supplied state on mount/replacement. Preserve separate,
explicit reset policy for actual query or directory changes. ConversationNavigator
and FileMentionPicker already distinguish initial preservation from later resets.

### 4. JsonView's initial depth is a continuing default

Changing JsonView.initialExpandedDepth from 0 to 2 reveals previously collapsed
content without an explicit expansion override. Tree.initialExpandedDepth ignores
the same change after mount. JsonView computes its fallback from the prop each
build; its explicit expanded/collapsed sets take precedence.

Sources: `json_view.dart:140,528`, `tree.dart:99,120`.
Recommendation: preserve the useful JSON fallback policy but name it
`defaultExpandedDepth`. Keep Tree's one-time seed named `initialExpandedDepth`.
This is a justified behavior difference made explicit by naming.

### 5. Callback origin differs intentionally

Writing `textController.text` fires TextInput.onChanged. Writing
`list.currentIndex` does not fire ListView.onFocusedItemChanged. TextInput's docs
explicitly promise callbacks for all text mutations; TextArea and editing
wrappers follow this model. List/DataTable interaction callbacks exclude controller
writes. This is a public contract difference, not an accidental missing listener.

Sources: `packages/fleury/lib/src/widgets/text_input.dart:611,975`,
`list_view.dart` interaction handlers, and `packages/fleury_widgets/lib/src/data_table.dart`.
Recommendation: move toward interaction callbacks plus all-origin controller
listeners. Treat text as a separate behavior migration: preserve notifications
for typing, paste, completion, history, and semantic edits; audit model writeback
and form subscribers. Do not implement this as an incidental rename or suppress
every controller-backed edit, since ordinary editing uses the controller too.

### 6. Null/default cursor semantics are inconsistent

ListController retains an explicit null cursor. TableController initially retains
null too, but Table overwrites it with zero when mounted with nonempty rows.
FileBrowserController and TreeTableController turn null into zero at construction.
LogRegion and MessageList also use null to choose their default/tail behavior.

Sources: controller constructors in `list_view.dart:73`, `table.dart:33,207`,
`file_browser.dart:78`, `tree_table.dart:728`, `log_region.dart:144`, `message_list.dart:124`.
Recommendation: specify omitted default separately from explicit null; make
adding a default controller behaviorally neutral. Include empty-to-nonempty data
and pending pre-attachment requests in the eventual regression cases.

### 7. Shared viewport controller silently accepts incompatible hosts

Two mounted ListViews with 4 and 100 rows accept the same ListController. Its
single `itemCount` becomes 100 even though one view has only 4 rows. This is not
a multi-position model. ScrollController likewise exposes one offset/metrics set.

Sources: `list_view.dart:680`, `scroll_view.dart:217`; compare FormController's
explicit one-host guard in `packages/fleury_widgets/lib/src/form.dart:83`.
Fix: reject a second owning viewport and verify detach/reattach. Do not apply a
blanket one-view restriction to value-only TextEditingController sharing.

## Suggested migration order

1. Fix reapplied seeds and discarded incoming cursors, with focused regression
   tests for edits, rebuilds, controller replacement, and data changes. Settle
   whether FileBrowser needs a navigation command before removing its existing
   prop-driven navigation path.
2. Align navigation constructor names and remaining browsing-cursor terminology;
   specify null/default behavior and enforce single-owner viewport attachment.
   Migrate repository callers, tests, and reference docs together. Keep real
   selected values, text ranges, cell ranges, and active-tab state distinct.
3. Handle text callback origin as an explicit compatibility decision and migration.
   This is broader than the list constructor clarification.
4. Teach the convention through two small guide examples: a controlled checkbox
   and a list whose initial row, user navigation, and controller command are visible.
   Keep the detailed lifecycle matrix in contributor/reference documentation.

## Pre-migration evidence

Nine temporary characterization tests passed on 2026-09-08. They confirm the original
behavior, including undesirable behavior; they should not be copied unchanged
into permanent regression tests.

| Probe | Observed result |
| --- | --- |
| NumberInput edited 7, rebuilt with seed 9 | Value becomes 9; callback list contains only 7. |
| Initial directory A changed to B | FileBrowser shows B; FilePicker still shows A. |
| FileBrowser controller starts at 2 | Controller becomes 0 on mount. |
| SearchPanel supplied indexes 2, then replacement 1 | Both become 0. |
| Expansion depth 0 changed to 2 | JsonView expands; Tree retains its original collapsed state. |
| Programmatic text and list cursor writes | Text callback fires; list browsing callback does not. |
| Remove external text controller holding a draft | New internal field is empty; old external controller retains its draft. |
| Explicit null index seeds | List/Table constructors retain null; FileBrowser/TreeTable choose 0. Table then replaces null on mount. |
| Share one controller between two lists | Both mount; the one metrics object reports the second list's count. |

Historical probe archived at `/tmp/fleury-widget-state-audit-pre-migration.dart`.
Receipt: `/tmp/fleury-widget-state-audit.log`. It characterizes the old API and is
not an executable regression for the migrated API.
Command, from `packages/fleury_widgets`:

```sh
dart test .dart_tool/widget_state_audit_test.dart --reporter expanded
```

The original source-audit phase did not change production tests or run a full
suite/browser check. The implementation validation is recorded below; earlier
guide/interaction evidence remains in `widget-interaction-consistency-audit-2026-09-07.md`.


## Implementation validation

Validation ran in this checkout after `dart tool/fleury_dev.dart bootstrap`.
The full `check` run passed all package analysis, core, tester, widgets, themes,
git, and console suites. It then stopped at Storybook's old assertion that the
current-row marker disappears when keyboard focus leaves the list. That
assertion was migrated to the approved persistent-marker behavior; all 43
Storybook tests passed. The remaining `check` commands were then run in their
original order without repeating completed suites.

| Check | Result / receipt |
| --- | --- |
| Bootstrap and package analysis | Passed; `/tmp/fleury-ownership-bootstrap.log`, `/tmp/fleury-ownership-check.log`. |
| Core, tester, widgets, themes, git, console | 3,325 / 52 / 1,219 / 7 / 4 / 25 passed respectively; two existing skips across core/widgets. |
| Storybook | 43 passed; `/tmp/fleury-ownership-storybook-final.log`. |
| Web VM/Chrome, samples, MCP | 534 / 92 / 151 passed; `/tmp/fleury-ownership-check-remaining.log`. |
| Guide/API/snippet tests and browser test runner | 87 and 2 passed; same remaining-check receipt. |
| Final ownership and focused follow-ups | 9 core ownership tests; 31 widget ownership/tab tests; 40 semantics tests. Receipts: `/tmp/fleury-ownership-core-new-final.log`, `/tmp/fleury-ownership-tabs-final.log`, `/tmp/fleury-ownership-semantics-final.log`. |
| Browser-safe JS compilation | Passed in both the repository gate and site build. |
| Website production build | Passed, 144 pages; `/tmp/fleury-ownership-site-build-final.log`. |
| Physical browser dogfood | Four guide demos passed; `/tmp/fleury-ownership-browser.log`. Verified initial row, independent browsing/selection/viewport, click and Enter, keyed reorder, edge focus escape/containment, source fit and tabs. |
| Formatting / whitespace | 118 changed Dart files required no formatting changes; `git diff --check` passed. |

The final lifecycle follow-up also checks that detached table/tab/data-table
controllers retain an index command until a larger replacement view mounts.
It fixed TabController clamping such commands to stale dimensions. Completion
semantic metadata was migrated to `completionCurrentIndex` and verified in the
semantics suite. Screenshot inspection confirmed visible current/selected
states and numbered edge markers in the browser demos.

Terminal integration: 63 tests passed in the full integration run; its only
failure was the embedded remote-client source fingerprint. Rebuilding with
`dart tool/fleury_dev.dart build-remote-client` updated that fingerprint, and the
freshness/compilation regression then passed (1 test). The generated JS bytes
were unchanged. Receipts: `/tmp/fleury-ownership-check-remaining.log`,
`/tmp/fleury-ownership-remote-client-build.log`, and
`/tmp/fleury-ownership-remote-client-final.log`. All 64 integration cases are
therefore covered by passing results after reconciliation; no integration case
was skipped to bypass a failure.

All required repository check suites, the site build, and the physical guide
checks now have passing results. These are local validation receipts, not PR
review or merge claims. The guide preview returned HTTP 200 on port 4332.
