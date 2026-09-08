# Widget interaction consistency audit

Date: 2026-09-07  
Status: DataTable and ListView follow-ups approved and implemented; other public widget renames remain proposals  
Inspected checkout: `codex/lists-scrolling-dx`, framework commit `d0120106`, with the existing uncommitted lists guide revision.

## Approved DataTable follow-up

The user approved this narrower design after discussing focus versus selection.
It supersedes the DataTable naming recommendation in the baseline audit below;
it does not approve renaming every collection callback.

- **Row mode:** `onFocusedItemChanged(row)` reports browsing to a different row.
  `onSelect(row)` confirms on completed click, Enter, or semantic selection.
  Choosing the same row again still calls `onSelect`.
- **Cell mode:** `onRangeChanged(range)` reports actual range changes.
  `onAction(row)` runs a row command on Enter, completed double-click, or
  semantic press. Single click and Space select a cell; Shift-click or
  Shift-arrow extends a range. Plain arrows move the cursor without changing
  the selected range. After plain navigation, Shift-arrow starts from the cursor.
- `DataTableController.currentRowIndex` and `currentColumnIndex` replace
  `selectedIndex` and `selectedColumnIndex`. `selectionRange`, `selectCell`,
  and `moveSelection` remain explicit range operations. Controller writes do
  not emit user-interaction callbacks.
- Wheel scrolling moves only the viewport. An explicit controller/navigation
  request reveals the cursor again, including when its index is unchanged.
- `onSort` and `onCopy` retain their responsibilities. No public `onActivate`
  callback is introduced. Constructor assertions reject callbacks for the wrong mode.
- Semantic state exposes `currentRowIndex`, `currentColumnIndex`, and
  `currentColumnId`; focus and range selection have separate flags on cells.

All repository callers were migrated. The reference uses two source-backed live
examples in `website/examples/lib/datatable_rows.dart` and `datatable_cells.dart`.
The existing lists guide revision remains in this worktree.

Review caught and fixed cursor reveal after controller replacement, double-click
continuity across ordinary column-list rebuilds, redirection by preview callbacks,
and clipped outcome labels in the browser embeds. Regression coverage includes
cancelled/replaced pointer targets, independent range copying, repeated choices,
semantic focus/select/press, viewport retention, and bounded rendering.

Validation: 1,209 widget tests passed (one pre-existing skip); 92 sample tests
passed; all 88 documentation tests and the production site build passed.
The migrated samples, console, profiling drivers, and docs examples analyze
without errors or warnings. The widget package has four pre-existing lint infos.
Physical Chrome verification passed row choices, keyboard browsing, wheel scrolling,
cell ranges, Enter, double-click, and cancelled drag via `tool/verify_datatable.cjs`.
The console's 25 workflow tests also passed. The wider docs browser suite passed
33 tests and failed three unrelated form/catalog checks. All three reproduce on
base commit `d0120106` in `/tmp/fleury-datatable-baseline-d0120106`:
`form.basic mounts its form and field semantics`,
`formerly source-only web widgets mount as live examples`, and
`forms.project exposes validation and a successful typed submit`.
Logs: `/tmp/fleury-datatable-examples-browser-suite.log` and
`/tmp/fleury-datatable-baseline-browser.log`. These remain separate follow-up work.


## Approved ListView migration

The user subsequently approved migrating ListView before updating the list guide.
This supersedes the ListView names in the baseline audit below.

- `onActivate` becomes `onSelect`: Enter and a completed click choose the item,
  including repeated choices. Pointer cancellation still prevents selection.
- `onSelectionChanged` becomes `onFocusedItemChanged`: user browsing to a
  different item updates a preview without choosing it.
- `ListController.selectedIndex` becomes `currentIndex`: a remembered cursor
  independent of keyboard focus and viewport. Programmatic writes and scrolling
  emit neither user callback. A changed index requests reveal; assigning the
  same index remains a no-op, and `jumpToIndex` explicitly controls the viewport.
- `selectionActive` becomes `highlightCurrentItem`; the item builder's boolean
  is named `highlighted`. This visual override does not take keyboard focus.

All repository ListView/ListController callers and tests use the new APIs.
Composite widgets retain their own existing public callback and controller
names; their internal list calls have been migrated. No compatibility aliases
retain the ambiguous ListView names. The core changelog records the migration.

The guide's five paired source/test/live examples remain. The task browser now
shows Current, Showing, a preview, and the last opened task. Arrows update the
preview; click or Enter opens a task; Go to 25 moves the cursor from code;
Scroll to 500 moves only the viewport. Repeating Go to 25 after scrolling away
also reveals the same current item. Reordering demonstrates stable current-item
identity and a persistent highlight while the button owns focus.

Validation for the ListView migration:

- Core widget suite: 1,132 passed. After the final test vocabulary cleanup,
  all 112 list/controller regressions passed again.
- Widget suite: 1,209 passed, one existing skip. Storybook (43), samples (92),
  and console (25) passed. Migrated packages analyze without errors or warnings;
  core, widgets, and profiling retain existing informational lints.
- All 88 documentation tests and two API-export checks passed. The production
  website build generated 144 pages and regenerated the API reference and demos.
- Chrome tests passed the task-list workflow, essential demo content, and
  landing-page embed sizes. This is the focused three-test browser run, not a
  rerun of the broader suite's known form/catalog failures recorded above.
- `tool/verify_lists_guide.cjs` passed all five live guide demos with physical
  pointer/keyboard input: cursor/preview versus choice, independent scrolling,
  repeated Go to 25, reordering, document edges, and pausing/resuming the log.
  Source/test tabs and the full-source disclosure also passed. Screenshots were
  inspected at the actual guide size; all task outcomes fit within the embed.

Logs: `/tmp/fleury-list-core-widget-tests.log`,
`/tmp/fleury-list-final-core-tests.log`, `/tmp/fleury-list-widgets-tests.log`,
`/tmp/fleury-list-storybook-tests.log`, `/tmp/fleury-list-console-tests.log`,
`/tmp/fleury-list-samples-tests.log`, `/tmp/fleury-list-website-build.log`,
`/tmp/fleury-list-browser-tests.log`, and
`/tmp/fleury-list-guide-browser-verification.log`.

## Second guide dogfood pass

The user requested a selectable first example, shorter source lines, direct
Focused/Selected labels, a clearer edge demo, and removal of the follow-tail
section from the general guide. The guide now contains four live demos:

- A three-row file list with arrow focus and completed-click/Enter selection.
- The large task list reports Focused and Selected explicitly. When a button
  takes keyboard focus, the label says "Focused: outside list" while Current
  retains the remembered row.
- Keyed reordering retains its existing behavior. The guide explains that the
  default highlight follows list focus; the override retains the marker while
  the reorder button owns focus.
- A four-row ScrollView over eight numbered lines shows the visible range,
  TOP/MIDDLE/BOTTOM, an outlined pane, and where keyboard focus moved.

The source panes use more width and the example files use narrower formatting.
Follow-tail remains implemented and tested but is no longer a general-guide
section. No framework contract changed during this pass.

The user's automatic key lookup suggestion is sound with unique stable keys.
`itemKeyBuilder` maps index to key; resolving a remembered key to a new index
requires a reverse lookup. Fleury can create that lookup by scanning all keys,
with O(itemCount) work at reconciliation. The existing optional data-identity
pair instead lets callers preserve bounded lazy work through a map or another
cheap lookup. Proposed follow-up, not implemented: allow `itemKeyBuilder`
alone with an automatic reverse index; retain `findChildIndexCallback` as the
explicit fast path. Cache invalidation must account for in-place data mutations
and callback captures; callback identity alone is not a data-change signal.

Validation for the second guide pass: all nine example tests and 89 docs tests
passed, plus the two API-export checks and the three focused Chrome tests.
The production build generated 144 pages. Physical Chrome verification passed
all four guide demos, source/test tabs, and a check that the displayed source
fits its panes without forced wrapping at the reviewed 1426px viewport. The
first-list and edge-demo screenshots were visually inspected. Logs:
`/tmp/fleury-lists-dogfood-tests.log`, `/tmp/fleury-lists-dogfood-build.log`,
`/tmp/fleury-lists-dogfood-chrome-tests.log`, and
`/tmp/fleury-lists-dogfood-browser.log`.

## Baseline audit (before the approved follow-ups)

## Decision

Fleury needs a shared vocabulary for **focus, selection, value changes, and invoking an action**. It does not need every widget to treat every input identically.

The audit changes the earlier recommendation to replace `ListView.onActivate` with `onItemPressed` everywhere. That name fits a command list, but a table click currently selects a row while Enter invokes it. Renaming the callback alone would promise an interaction the table does not provide.

Recommended callback vocabulary:

| Intent | Public API | Contract |
| --- | --- | --- |
| Invoke a command control | `onPressed` | Button or menu command; independent of mouse versus keyboard. |
| Invoke a collection item's primary action | `onActivate(item)` | Open/run/accept the current item; distinct from moving selection. |
| Move a collection's selected row | `onSelectionChanged` | Selection notification, never an implicit command invocation. |
| Preview a candidate before committing | `onHighlightChanged` | Where the widget actually exposes a separate preview, as Select does. |
| Change a control's value | `onChanged(value)` | Checkbox, text, numeric and choice values. Controlled widgets request an owner update. |
| Submit an entry or form | `onSubmit` | Accept entered content, including validation where the form owns it. |

Retain meaningful domain outcomes such as `onCopy`, `onCancel`, `onDecision`, `onPick`, `onCompletionAccepted`, and command `onInvoke`. Their names describe more than a physical input. `Autocomplete.onSelect` is a committed choice, unlike a table's misleading use of `onSelect` for an independent row command.

Do not add a parallel callback on every widget. Controllers remain the way to observe owned state where one already exists. `onSelectionChanged` and `onChanged` must document whether programmatic controller changes notify; the audit does not propose changing TextInput's established notification contract.

## Current behavior matrix

The public API inventory was checked against event handlers and existing tests. This is a source audit of the interaction families, not proof of every widget/input/platform combination.

| Family | Navigation / selection | Enter or equivalent | Completed mouse click | Current application callback |
| --- | --- | --- | --- | --- |
| Button | Focus | Enter/Space invoke | Invoke | `onPressed` |
| ToastAction | Global shortcut; no focusable action control | Configured shortcut invokes; toast also exposes semantic activate | **Action label has no pointer handler** | `onPressed` |
| MenuItem | Highlight an entry | Invoke leaf or open submenu | Same primary operation | `onSelect` for leaf commands |
| CommandPaletteItem | Highlight filtered command | Invoke command | Invoke command | `onInvoke` |
| ListView | Arrows select; wheel moves viewport | Invoke selected item | Select/focus on down, invoke on completed click | `onSelectionChanged`, `onActivate` |
| Table, DataTable | Arrows select; **wheel also changes selection** | Invoke selected row | **Select only**; DataTable header clicks request sorting | `onSelect`; DataTable also has `onSort` |
| Tree, TreeTable | Move row; Left/Right expand/collapse | Toggle branch or invoke leaf | Same branch/leaf operation | `onSelect` for leaves only |
| SearchPanel | Browse results | Invoke result | Invoke result | `onActivate` |
| FileBrowser | Browse entries | Enter directory or invoke file | Same primary operation | `onDirectoryChanged`, `onActivate` for files |
| ContextPanel, ConversationNavigator, TraceTimeline | Browse items/events | Invoke selected item | Invoke item | `onSelect` |
| PatchReview | Browse file rows | Jump diff to file and invoke optional file callback | Same primary operation | `onSelectFile` |
| FilePicker, FileMentionPicker | Browse entries/results | Enter directory or commit file/mention choice | Same primary operation | `onSelect`, `onPick` respectively |
| Select | Popup highlight is separate from value | Open popup or commit highlighted option | Open trigger or commit clicked option | `onHighlightChanged`, `onChanged` |
| Autocomplete | Move suggestion highlight; keep input focus | Accept suggestion when completion handles the key | Accept suggestion | Text `onChanged`, option `onSelect` |
| MultiSelect | Move highlighted option | Enter/Space toggle option | Toggle clicked option | `onChanged(Set)` |
| Checkbox, Toggle, Switch, Radio | Focus | Enter/Space changes value | Changes value | `onChanged` |
| RadioGroup | Arrows move focus **and change value** | Invoke focused radio | Choose radio | `onChanged` |
| Tabs | Arrows immediately switch selected tab/content | No separate confirmation needed | Switch tab/content | `TabController.index` |
| ColorPicker | Arrows move preview cursor | Enter/Space commit color | Commit clicked color | `onChanged` |
| DatePicker | Arrows immediately change date | Consumes Enter; date already committed | Choose date | `onChanged` |
| RangeSlider, Stepper | Arrows update value | Stepper accepts buffered numeric entry; otherwise Enter bubbles | Adjust value; slider also supports drag | `onChanged` |
| TextInput, PasswordInput, NumberInput, CompletionTextInput | Edit text/value; completion may intercept acceptance | Submit or accept completion according to input mode | Position caret / select text | `onChanged`, `onSubmit`, completion callback where supported |
| TextArea | Edit and select text | Defined by editing keymap, including multiline/chat behavior | Position caret / select text | `onChanged`, optional `onSubmit` |
| Form | Descendant controls retain their own behavior | Form submission runs validation before callback | Explicit submit control reaches form controller | `onSubmit` |
| CodeView, DiffView, LogRegion, MessageList, TaskGraph | Select a line/row for inspection/copy | No independent application row command | Select row through list interaction | `onCopy`; row semantic `activate` currently only selects |
| JsonView | Select/navigate nodes, expand/collapse containers | Built-in tree navigation | Built-in navigation | `onCopy`; node semantics omit ordinary selection |

Low-level `GestureDetector.onTap*`, `MouseRegion.onHover/onScroll`, key handling, outside-tap handlers, and text-selection callbacks describe physical events or their own state. They should keep those meanings. Passive rendering surfaces and lifecycle callbacks are outside this naming migration.

## Findings and proposed changes

### 1. Several callbacks named “select” actually invoke an action

`Table.onSelect`, `DataTable.onSelect`, `Tree.onSelect`, `TreeTable.onSelect`, `ContextPanel.onSelect`, `ConversationNavigator.onSelect`, and `TraceTimeline.onSelect` do not report arrow-key selection changes. They report a separate command. `PatchReview.onSelectFile` has the same naming problem.

Propose `onActivate` for those collection actions, using the same shape as ListView, SearchPanel, and FileBrowser. Use `onActivateFile` for PatchReview's named file action. Rename `MenuItem.onSelect` to `onPressed`, matching a Button command. Preserve tree and file-browser built-in branch/directory behavior; their callbacks concern leaves/files and must say so. FilePicker's `onSelect` is a genuine committed picker outcome and need not join the collection-command rename.

Evidence: `table.dart:317`, `data_table.dart:917`, `tree.dart:200`, `tree_table.dart:1175`, `context_panel.dart:389`, `conversation_navigator.dart:531`, `trace_timeline.dart:404`, `patch_review.dart:530`, `menu.dart:24`. Widget files without a package prefix here are under `packages/fleury_widgets/lib/src/`.

### 2. Pointer selection and invocation need an explicit policy

ListView and tree controls invoke on a completed primary click. Table and DataTable select on a click, then require Enter or a semantic action for the row callback. Table's existing test explicitly protects this distinction. DataTable also uses clicks and Shift-clicks for cell/range selection.

Preserve table click-to-select in a naming cleanup. A later interaction change must provide a deliberate mouse affordance for the row command (for example double-click or an explicit action) without making cell/range selection invoke commands. This is a behavior decision, not a safe mechanical rename. Do not add a general activation-policy framework solely for this audit.

For command widgets, all supported invocation paths must share the same logical handler and eligibility checks. Invoke once on a completed click or accepted key, never merely on pointer down; canceled gestures must not invoke. This does not prevent selection/focus on pointer down, which ListView deliberately supports.

Evidence: core `packages/fleury/lib/src/widgets/list_view.dart:881` and `:947`; `table.dart:526`; `data_table.dart:1005`; existing `table_test.dart:442` and `data_table_test.dart:627`.

### 3. Semantic action names are not a reliable contract yet

There are three concrete mismatches:

- CodeView, DiffView, LogRegion, MessageList and TaskGraph expose `activate` to do only selection. Their items need `select`; an unrelated action must not be required just to select a line.
- ContextPanel, TraceTimeline, ConversationNavigator, SearchPanel, PatchReview and FileMentionPicker expose `submit` on the collection root to invoke its current item, while their actionable rows expose `activate`. A test changes from `.submit()` to `.press()` depending on whether it targets the container or row. CommandPalette also exposes root `submit` for command invocation. Standardize the collection primary action on `activate`; actual query-input submission can still invoke that same handler.
- Tree and TreeTable items have selected state but offer only open/close for branches and activate for actionable leaves. JsonView similarly exposes expansion/copy without ordinary node selection. They need a way to select without opening or invoking.

Define the existing semantic verbs in `SemanticAction` and tester API documentation:

- `focus`: focus the addressed control. A compound control may have an automatic selection-follow-focus policy, but the addressed node must actually become focused.
- `select`: change selection. For a choice widget this can commit the selected value; for a browsable row it must not run an independent open/run command.
- `activate` / tester `.press()`: invoke the control's primary action. This remains logical input, not a synthetic mouse click.
- `submit`: submit entered content or a form.
- `open` / `close`: explicit expansion or opening/closing where supported.
- `setValue`, `check`, `uncheck`: retain the existing requested-value versus desired-state contracts. They are not aliases for pressing a key repeatedly.

A normal custom widget composed of existing controls inherits those contracts. A custom semantic control advertises the operations it actually supports; it needs no new tester class or new role just for a callback name.

Evidence: `code_view.dart:501,658`, `diff_view.dart:535,678`, `log_region.dart:475,904`, `message_list.dart:402,564`, `task_graph.dart:335,486`, `context_panel.dart:415`, `trace_timeline.dart:430`, `conversation_navigator.dart:571`, `search_panel.dart:445`, `patch_review.dart:556`, `file_mention_picker.dart:540`, `command_palette.dart:519`, `tree.dart:377`, `tree_table.dart:1510`, `json_view.dart:797`; tester mapping in `packages/fleury_test/lib/src/fleury_target.dart:306`.

### 4. Advertised semantic capabilities disagree with real behavior

An inactive tab advertises `SemanticAction.focus`. Its handler focuses the tab strip but leaves its index unchanged; only the selected tab reports focused. Consequently `tester.target(role: SemanticRole.tab, label: 'Two').focus()` throws “Focus was refused” when tab One is selected.

Fix the advertised operation. Given the existing automatic tab switching on arrow navigation, focusing a specific tab should focus and select that tab, using the same tab-selection helper. Merely focusing the whole strip belongs to a group/root target. This is a concrete defect, independently of callback naming preferences.

Evidence: `tabs.dart:227-250`; tester focus postcondition at `packages/fleury_test/lib/src/fleury_target.dart:315`; reproduced by temporary probe below.

PatchReview has the inverse problem. Its built-in Enter/click action jumps to the chosen file in the diff even without `onSelectFile`. But both row activation and root submission are advertised only when that optional callback exists. A test or accessibility adapter cannot invoke the built-in jump without an otherwise unnecessary callback. Advertise capabilities based on the operation being available, not merely on an optional observer callback. This was also reproduced in a temporary probe.

Evidence: `patch_review.dart:520-530,599,613,747`.

### 5. Table scrolling still changes selection

The new ListView contract separates scrolling from selected-item movement. Table and DataTable still implement wheel scrolling by assigning `controller.selectedIndex`. Scrolling therefore changes the item an ensuing Enter action invokes, even though scrolling did not invoke its callback itself.

Extend viewport/selection separation to both table implementations. Do not treat suppressing `onSelect` as sufficient: the selected item changed. This is a separate framework change with controller, visible-range, hit-testing, range-selection and rendering implications.

Evidence: `table.dart:274`, `data_table.dart:1046`; explicit current-behavior tests at `table_test.dart:453` and `data_table_test.dart:595`.

### 6. Toast actions are not clickable

ToastAction has an `onPressed` callback and an accented visible action label. The label is rendered as Text without a pointer handler or focusable action control. Only the configured shortcut and the notification's semantic activate handler invoke it. Make the visible action a real command control using the same dismissal/invocation path, while retaining the global shortcut. Verify that dismissing first and invoking once works for all three routes.

Evidence: `toaster.dart:208-245,267-300,318-329`. This is a source finding; no new physical pointer reproduction was run for Toaster in this audit.

## What should remain different

- RadioGroup, Tabs and DatePicker apply arrow navigation immediately. Select and ColorPicker have a separate candidate/confirmation phase. A universal “arrows only preview; Enter commits” rule would regress working controls.
- Choosing the current option may deliberately report a choice again, while a desired-state operation may be a no-op. Do not globally deduplicate all callbacks as part of this work.
- Tree branches expand and directories open internally; their application callbacks need not fire for those built-in operations.
- Form submission, text completion acceptance and menu commands have different lifecycle/validation requirements. Sharing a word must not bypass them.
- `active` currently has differing state meanings (ListView's builder flag includes focus; Tabs uses it for the selected tab). Clarify local docs when touched; a framework-wide styling rename is outside this proposal.

## Proposed implementation sequence

1. Approve the vocabulary and table interaction policy. Do not bundle a single-click table behavior change into a callback rename.
2. Fix inactive-tab focus, PatchReview's missing built-in action capability, and the toast action's missing pointer affordance. Define semantic selection/activation/submission contracts. Add focused regressions for advertised capabilities and tests proving that selecting does not invoke an independent row command.
3. Migrate misleading collection `onSelect` callbacks and MenuItem to the chosen names, updating framework call sites, examples, tests and API docs. Reuse existing payload/result types unless their names also make a false promise; do not add duplicate permanent callback surfaces.
4. Extend viewport/selection separation to Table and DataTable as its own change, with wheel-then-Enter and range-selection regressions.
5. Show the distinction in two small source/test/live guide demos: browse versus invoke a task, and select versus invoke a table row. Keep the full matrix in this audit/API reference rather than the guide introduction.

## Validation performed

- 341 existing tests passed across 19 relevant `fleury_widgets` test files, covering tables, trees, controls, tabs, menu, choice widgets and action collections. Log: `/tmp/fleury-interaction-audit-tests.log`.
- 70 existing ListView tests passed. Log: `/tmp/fleury-interaction-audit-list-tests.log`.
- Three temporary characterization probes passed by reproducing the current behavior: inactive-tab `focus()` refuses its advertised operation; DataTable click only selects while Enter / semantic press invoke; PatchReview's built-in diff jump works without a callback but is not advertised. Probe: `/tmp/fleury-interaction-audit-probe_test.dart`; log: `/tmp/fleury-interaction-audit-probes.log`.

These passing tests confirm the audit observations; several explicitly encode the behavior proposed for change. No framework fixes, API migration, browser interaction verification, full repository suite or CI run is claimed for this audit.


## Approved simplification: current-row cue and keyed lookup

This supersedes the highlight override and callback fast-path proposals above.
The user approved removing `highlightCurrentItem` and `findChildIndexCallback`.
The builder's `highlighted` argument now identifies the current row even when
keyboard focus is elsewhere. `autofocus` and FocusNode still own keyboard focus.

`itemKeyBuilder` is the only keyed-list input. ListView captures every key and
builds one reverse map on mount and each parent-supplied widget update. Current
row, viewport anchor, and sparse mounted elements share that snapshot. Key scans
cost O(itemCount) time and space; row creation and layout remain lazy. Cursor and
viewport-only updates reuse the snapshot. Duplicate offscreen keys are rejected,
and in-place mutations with the same builder closure still refresh on update.
MessageList now uses this shared lookup instead of maintaining its own map.

Initial positioning already uses `ListController(currentIndex: n)`: reveal the
clamped current row on first layout, without selection callbacks or focus changes.
An explicit viewport request or follow-tail policy takes precedence. Keep that
single state owner rather than adding an overlapping `initialSelectedIndex`.
The large-list guide demo starts at task 25 and keeps Selected at None.

Peer context: Textual ListView has initial_index for its highlighted row; Ratatui
ListState.with_selected initializes the highlighted item and rendering reveals it.
Flutter ListView has no built-in selection and ScrollController initializes a
pixel offset. React Aria ListBox initializes selection with defaultSelectedKeys;
its selection state has different semantics from Fleury's explicit onSelect choice.

Validation for this simplification:
- 1,136 core widget tests and 1,209 higher-level widget tests passed (one existing
  skip). The focused list/controller run passed 116 tests.
- The guide build passed 89 documentation tests, two export checks, both browser
  compilations, and all 144 pages. Example analysis was clean; widget analysis
  retained four pre-existing informational diagnostics.
- Three focused Chrome example tests passed. The physical browser guide check
  passed all four demos, including the initial task-25 marker, reordering,
  persistent highlighting, edge behavior, source/test tabs, and source fit.
- Key regressions cover offscreen duplicates, in-place data changes with a stable
  callback, bounded row creation, no key rescans on cursor/viewport updates,
  initial reveal without focus or selection, clamping, and explicit viewport
  precedence. The duplicate-key error path releases initialized resources cleanly.

Receipts: /tmp/fleury-simple-core-widgets.log,
/tmp/fleury-simple-widgets-final.log, /tmp/fleury-simple-guide-build.log,
/tmp/fleury-simple-guide-chrome.log, /tmp/fleury-simple-guide-browser.log.
