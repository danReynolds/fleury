# Lists and scrolling DX audit

Date: 2026-09-07. Baseline: merged main, `944f7fb71e9b99ec6644b797ecbb1d4b6ecc09b8`.
Status: items 1–3 approved and implemented on `codex/lists-scrolling-dx`.
The user declined `ListView.items`: keep `ListView(children: ...)` and the
index-based lazy builder. Optional semantic row-label hooks remain unapproved
and are not a prerequisite for the rewrite; evaluate any need through concrete
guide examples. The existing guide has received contract corrections and is
now demonstrated by five source-backed live examples. The later ListView naming
migration is recorded in the widget interaction audit and the addendum below.

The lazy list foundation is useful: eager/builder/separated construction,
variable-height layout, bounded mounting, item-index jumps, keyed reconciliation,
controller ownership, and an integrated scrollbar. The largest problems are the
contracts between viewport movement, selection, activation, and following output.
Several surprises are explicitly encoded in the existing tests. Passing those
tests is evidence of the baseline, not evidence that the DX is already right.

## Evidence

Read the list, controller, eager/lazy renderers, scroll view, scrollbar, pointer
dispatch, guide, and representative message/log/search/file consumers. Ran:

- 134 existing core list/controller/scroll/scrollbar/pointer tests: passed.
- 63 existing message, log, search, and file-browser tests: passed.
- 11 new VM audit probes: passed, reproducing the observations below. These
  deliberately asserted baseline behavior, including defects.

Those temporary baseline probes were replaced by maintained desired-behavior
regressions in `packages/fleury/test/widgets/list_view_dx_test.dart`. The numbered
observations below describe the baseline, not the implemented behavior.

1. Explicit `ListController(selectedIndex: null)` mounts with selection 0.
2. Clearing selection after mount enters scroll-only mode, but clicking a row
   silently enables selection again.
3. One wheel tick changes selection 0 to 1 and fires `onSelectionChanged`, while
   the five-row viewport remains at items 0 through 4.
4. A row activates on pointer-down. Dragging and releasing outside cannot cancel
   the action because it already happened.
5. `jumpToIndex(10)` shows items 10 through 14. An unrelated parent rebuild pulls
   the viewport back to items 0 through 4, where the unchanged selection lives.
6. Dragging/clicking the scrollbar away from a followed tail leaves `atBottom`
   and `pinToBottom` true. The next append pulls the reader back to the bottom.
7. An eight-line item in a five-row viewport shows lines 0 through 4. A wheel
   tick skips to the next item; lines 5 through 7 are unreachable that way.
8. A controller listener sees the old visible range when a jump is requested.
   The final range is written during layout without another notification.
9. A plain navigable `ListView` of `Text` rows has no list/listItem semantic
   targets for the fluent testing interface.
10. With controller selection 2, the builder receives false for its `selected`
    boolean on row 2 when the list is unfocused. It actually means active
    selection styling, not logical selection.
11. Control experiment: an ordinary row `GestureDetector` using down for
    selection/focus and `onTap` for activation survives selection, focus, and
    parent rebuilds between down and up in the current VM renderer.

These probes do not qualify a new implementation on browser or served-terminal
transports. In particular, the old press-time activation workaround mentions
served rebuilds; native browser and served sessions remain required regression
checks when changing it.

## 1. Separate viewport movement from selection

**Required correction; highest priority.**

The renderer currently ensures selection visibility on every layout. A pending
jump suppresses that behavior for one layout only. `MessageListController` and
`LogRegionController` already compensate by changing selection when jumping;
other controller wrappers and `Scrollbar.list` use the core jump directly.

Proposed behavior:

- Wheel and scrollbar move the viewport without changing selection or focus.
- A programmatic jump remains in place across unrelated rebuilds, appends while
  paused, and layout changes. Selection movement explicitly requests reveal;
  merely having a selection does not override a user's viewport position.
- Arrow navigation keeps its useful TUI cursor behavior. After independent
  scrolling, moving the cursor reveals the newly selected item. Clicking a
  visible row selects that row.
- `atBottom` describes the viewport, including partial visibility within a tall
  row. It must not mean "the selected index is the last item."
- Publish changed viewport metrics after layout, once per completed frame,
  without invoking application callbacks inside layout or causing rebuild loops.
  This also addresses the equivalent readback issue in `ScrollController`.

Following output should use viewport position and explicit intent. Proposed
controller vocabulary:

```dart
final log = ListController(followTail: true);

log.jumpToIndex(20);  // Read history; pause automatic following.
log.jumpToBottom();   // Return to the end; resume if followTail is enabled.
log.followTail = false; // Disable automatic following altogether.
```

`followTail` is the policy; read-only `isFollowing` reports whether it is
currently following. Scrolling away pauses it; returning to the end resumes it
only when the policy is enabled. Turning the policy off stays off. This replaces
the hidden, permanently latched follow-capable state behind `pinToBottom`.
Turning the policy on explicitly catches up. A normal list's `jumpToBottom()`
must not silently turn it into a live feed.

Keep `unseenCount` scoped to appended items in an ordered feed. It is not a
general collection-diff or unread-message system. Preserve the existing keyed
rolling-window handling and distinguish prepends from new arrivals.

Sources: `list_view.dart:149`, `:215`, `:824`, renderer selection-visibility
passes; `scrollbar.dart:46`; `message_list.dart:157`; `log_region.dart:177`;
`scroll_view.dart:107`.

## 2. Make all content in a tall row reachable

**Required renderer capability; largest implementation risk.**

The source explicitly documents no scrolling within an item. Existing tall-row
tests establish that layout does not wedge, but do not establish that users can
read all the content. The guide's variable-height and chat/log claims need this
stronger behavior.

Maintain an item anchor plus a row offset within that item. Wheel and scroll-only
keyboard movement can then reveal every line. Preserve the anchor identity and
offset through prepends and reorders, clamp sensibly after width/height changes,
and keep a growing final item pinned when following. Separators and clipping must
remain correct. Keep item-index jumps and lazy mounting; this does not require a
pixel-based scrolling engine or measuring every offscreen item.

For selectable lists, arrows continue to choose items; wheel movement can inspect
the interior of a selected tall item. For scroll-only lists, arrows move by rows
and page keys move by viewport. Scrollbar item-range geometry may remain an
approximation for unmeasured variable-height data, but its movement and end-state
must be truthful, including the single-tall-item case.

Do this as a separately reviewable renderer change. Acceptance includes every
line of an oversized row being reachable, partial-row pointer/semantic geometry,
viewport resize, growing last item, and preserved bounded work on a 10k-item list.

## 3. Make selection and activation deliberate

**Required interaction correction; small public API addition.**

- Select and focus on primary down; call `onActivate` on completed click or
  Enter. Cancel activation when the pointer leaves the target, the gesture is
  cancelled, or the original item is removed/replaced. Preserve identity through
  harmless rebuilds and resolve a moved item's current index before calling it.
- Keep single-click activation for existing menu/picker behavior. A new global
  double-click policy is not needed for this pass. Nested controls must perform
  their own action without also activating the list row.
- Add declarative `selectable: false` for passive lists/logs. It disables the row
  selection behavior for mouse and keyboard while retaining viewport input and
  interactivity of child controls. It should not require clearing a controller
  after the first frame.
- Honor explicit null initial selection. Keep the ordinary navigable-list
  default of selecting its first item, but distinguish that default from a
  caller deliberately choosing no current selection. No-selection and
  non-selectable are separate: the former can select later; the latter cannot.
- Keep logical selection and its active visual cue distinct. The existing
  builder boolean should be named/documented as `active`, without silently
  changing its meaning and breaking built-in styling. The controller remains
  the source of logical selection. A broader builder-state object is not needed
  just to repair the guide's terminology.

Sources: `list_view.dart:357`, `:631`, `:861`; pointer dispatch `pointer.dart:398`
through the release/cancellation handling.

## 4. Add a convenient data-backed list with semantic row labels

**Collection constructor declined by the user.** The constructor sketch below
is retained as review history, not planned implementation. The independent
semantic row-label idea can be reassessed if the guide demonstrates a concrete
gap with the existing APIs.

The existing forward/reverse identity callbacks are a sound low-level contract.
Keep them for sparse or very large data sources. For an ordinary in-memory list,
the framework can build the reverse map once for a new data snapshot instead of
requiring each app to maintain two mappings and translate indices in callbacks.

Proposed API shape (not yet implemented; inferred item type):

```dart
ListView.items(
  items: tasks,
  itemKey: (task) => task.id,
  itemLabel: (task) => task.title,
  onSelectionChanged: (task) => preview(task),
  onActivate: (task) => openTask(task),
  itemBuilder: (context, task, active) => Text(
    task.title,
    style: active ? theme.selectionStyle : CellStyle.none,
  ),
)
```

This constructor still builds widgets lazily. Indexing the supplied collection
costs O(n) time and memory for a new data snapshot; that cost must be explicit.
Take a stable snapshot or otherwise detect supported mutations: caching only by
List identity is wrong when a caller mutates the same List in place. Validate
duplicate keys. Do not promise persistence of widget-local state after lazy
unmount; persistent draft state belongs with the data owner.

An explicit item label lets Fleury expose the row behavior it already owns:
selected state, selection, focus, and activation when supported. Reuse existing
`SemanticRole.list` / `listItem` and `target(...).select()` / `.press()` operations.
No new role vocabulary or bespoke list tester is necessary. Match by semantic
label for behavior, by widget type/key for structure. Data identity and a human
label remain different contracts; do not infer a label from `toString()` or
require labels to be unique globally.

The label hook is opt-in for the low-level builder too. Existing composite rows
with their own semantics must retain their roles/actions without duplicate
interactive targets. It does not make an offscreen, unmounted row magically
queryable: scroll to it before asserting visible behavior.

Selection callbacks remain user events. Controller/model changes should update
observers, but should not masquerade as clicks. When a selected item is removed,
keep the existing successor/last-survivor fallback and make the resulting state
available to a preview; guide code must not mirror a stale index in local state.

## Peer comparison

- Flutter's [ListView.builder](https://api.flutter.dev/flutter/widgets/ListView/ListView.builder.html)
  also requires a reverse index callback to preserve row state when order changes.
  Our existing low-level API is defensible. The convenience constructor is an
  improvement for callers that already have the whole collection, not a reason
  to remove the efficient builder path. Flutter puts row interactions in widgets
  such as [ListTile](https://api.flutter.dev/flutter/material/ListTile-class.html),
  whereas Fleury's ListView itself owns cursor navigation and row activation.
- [React Aria ListBox](https://react-aria.adobe.com/ListBox) supports data objects,
  item IDs, explicit selection modes, and controlled selection by keys. Its
  semantics distinguish simple options from rows containing interactive children.
  That supports a convenient data/identity path, but does not justify importing
  its entire collection or selection-policy API into Fleury.
- [Textual ListView](https://textual.textualize.io/widgets/list_view/) distinguishes
  highlighted items from activation messages. Fleury already makes that useful
  distinction with selection and activation callbacks; their pointer behavior
  should respect the difference.
- [TanStack Virtual's chat guide](https://tanstack.com/virtual/latest/docs/chat)
  treats following as an end-of-viewport behavior, preserving a reader's position
  through history prepends and following growth only when already at the end.
  This is a better comparison for logs than coupling following to selection.

These comparisons inform the proposal; they are not claims that every peer has
identical click, focus, or selection defaults.

## Implementation and guide sequence

1. Separate scrolling, selection reveal, following, and metric observation.
   Migrate built-in list consumers and remove their compensating selection writes.
2. Add partial-row scrolling in a separately reviewable change; retain keyed
   reconciliation and bounded mounting guarantees.
3. Correct click completion/cancellation and explicit selection initialization;
   add the passive-list option. Verify native browser and served-terminal paths.
4. Keep the existing constructors. Evaluate any remaining semantic row-label
   friction in guide examples; propose a concrete change only if needed.
5. Rewrite the guide using actual shared example source and executable tests:
   a task list with preview; a filter/reorder that preserves identity; a live log
   showing follow/pause/return and a tall entry; a small composed ScrollView demo.
   Each demo introduces one useful behavior. Pair widget and test files with the
   running demo; use the existing run-test presentation where applicable.
6. User dogfoods the guide before final review/merge.

Keep eager/builder/separated, ScrollView, integrated scrollbars, ownership and
disposal, and edge bubbling. Explain bounded layout beside the first example.
Show mounted-row state lifecycle alongside the changing-data example. Move
mechanical callback contracts and API inventories into reference documentation.

No horizontal scrolling, multi-selection, drag reordering, pagination framework,
sliver architecture, new collection controller hierarchy, or Button.builder work
is proposed here. Those are independent capabilities, not prerequisites for
making these existing list workflows reliable and teachable.


## Implemented scope and migration

- Wheel, scrollbar, and programmatic viewport commands leave logical selection
  unchanged. Keyboard selection explicitly reveals the chosen row; a pointer
  selection keeps the already-visible row under the pointer.
- `followTail` enables the policy. `isFollowing` reports active following;
  `atBottom` reports the viewport. Message and log controllers expose these same
  distinctions and no longer change selection to compensate for reverted jumps.
  `pinToBottom` remains deprecated for migration, including explicit catch-up.
- A shared eager/lazy layout tracks an item anchor and an offset in terminal
  rows. Oversized items and growing last items remain readable. Painting, input
  bounds, and semantic bounds are clipped to the viewport. Lazy probing leaves
  only the final visible rows mounted.
- Explicit null selection stays null; `selectable: false` remains passive through
  pointer input and controller writes. Primary down selects/focuses; completed
  click and Enter activate. Keyed reorder resolves the clicked item's current
  index, and removal or cancellation prevents activation.
- `active` names the builder's existing focus-dependent highlight boolean.
  Controller metric changes notify after layout rather than during layout.
- Existing tests, MessageList, LogRegion, the demo console, agent sample, and
  guide snippets have been migrated to the new contracts. Following appends
  preserve the selected message and its metadata rather than selecting each
  incoming message.

### Native input reproduction

The shared fixture is `packages/fleury/test/fixtures/list_interaction_widget.dart`.
It runs through both `mountApp` and the served native `runApp` path. Compile the
web entry from the `fleury_web` package:

```sh
dart compile js test/fixtures/list_interaction_web.dart -o /tmp/list-fixture/main.dart.js -O1
```

Serve that output with a page containing `<div id="app"></div>`, fixed dimensions
and a monospace font, and `<script src="main.dart.js"></script>`. From the core
package, run:

```sh
dart run bin/fleury.dart serve --port=4342 --spawn dart run test/fixtures/list_interaction_app.dart
```

Run the retained regression script with Playwright installed (or supply
`PLAYWRIGHT_MODULE` and `CHROME_EXECUTABLE`):

```sh
node tool/verify_list_interactions.cjs http://127.0.0.1:4341 http://127.0.0.1:4342
```

It sends native mouse/keyboard input through Chrome, verifies a parent rebuild
between down and up, cancels a release outside, reads all eight lines of a tall
item through wheel movement, and checks the scrollbar and outside clipping.
This is local Chrome/served-app evidence; it does not claim OS-terminal mouse
qualification on every terminal emulator.

### Validation receipts (2026-09-07)

- Contributor analysis: no errors or warnings across the configured packages;
  core's final analysis retains 13 pre-existing informational diagnostics.
- Final core unit suite: 3,310 passed, one skipped. This includes the list
  regression suites, repaint-boundary checks, and lazy mounting at 10k items.
- Final widget suite: 1,200 passed, one skipped. The demo console's 25 tests also
  pass after migrating selected-message expectations.
- Remaining contributor suites passed: fleury_test (52), themes (7), git (4),
  storybook (43), web VM/Chrome (534), samples (92), MCP (151), documentation (78),
  and the browser guide runner (2). Documentation dart2js compilation passed.
- Serial core integration batch: 63 passed; one hot-reload test was interfered
  with by this task's concurrent regeneration of remote_client_asset.dart. Its
  watcher saw that save before its intended marker edit. The exact failed test
  passed in a separate run with source files stable. No timeout or expectation
  was weakened. The initial all-in-one check had also stopped on consumer
  expectations; the remaining commands and corrected consumers were rerun.
- Both native Chrome fixtures passed the retained pointer/keyboard script on the
  final code: direct browser runtime and served native app.
- All eight fast performance gates passed on final code with unchanged baselines:
  serve semantics, images, bundle size, allocation, input allocation, paint,
  selection, and runtime.

Local logs: `/tmp/fleury-lists-final-core.log`,
`/tmp/fleury-lists-final-widgets.log`, `/tmp/fleury-lists-demo-recheck.log`,
`/tmp/fleury-lists-check-00.log` through `-11.log`,
`/tmp/fleury-lists-reload-recheck.log`,
`/tmp/fleury-lists-final-native-browser.log`,
`/tmp/fleury-lists-final-perf.log`.

- The terminal output-byte gate also passed (SB1, SB6, SB9), retaining its
  baselines. Receipt: `/tmp/fleury-lists-wire-gate.log`.

### Guide dogfood revision (2026-09-07)

The browser review found the guide still relied on isolated API snippets. The
revision replaces those with five focused widgets shared by the live registry,
source tabs, and executable tests: row-owned file buttons, a large task browser
with selection/scroll commands, keyed reordering, a document with switchable
edge containment, and a following log with append/grow controls. The old
standalone task implementation now imports that same task browser.

The introduction is two sentences. Enter/click behavior is explained before
`onActivate` appears. Controller, identity, edge, and following behavior is
visible in the examples instead of introduced through API inventory tables.
Each source tab has a focused excerpt plus the complete file, with actual source
and test filenames. Both documentation and contributor checks run the guide's
eight widget tests.

No framework API was changed during this guide revision. The scrollbar remains
cell-quantized; a short track over a large collection therefore jumps by many
items per pointer cell. A continuous browser thumb would need a separate design.
Flutter has `findChildIndexCallback(Key)`, but its forward mapping comes from
child widget keys rather than a separate `itemKeyBuilder`. Fleury's separate data
identity supports preserving selection and the viewport without constructing an
offscreen widget. The guide demonstrates both row-owned button actions and the
list-owned keyboard cursor; it does not present those as identical to Flutter's
ListView/ListTile split.

Validation for the guide revision:

- Eight guide widget tests passed, including paused growth and following an
  entry taller than its viewport.
- Source, registry, and test analysis passed without diagnostics.
- The updated `lists.tasks` Chrome regression passed.
- `tool/verify_lists_guide.cjs` passed using native Chrome clicks, keys, and wheel
  input against the actual guide preview. It covers all five demos plus source
  and test tabs. Browser frame heights were increased after browser inspection caught
  clipped status lines and controls at the guide's real font metrics.
- Final `npm run build` passed: 86 Dart documentation tests, two export checks,
  both dart2js bundles, and all 144 site pages. Log:
  `/tmp/fleury-lists-guide-build-final.log`.

### Focus and selection naming migration (2026-09-07)

The user approved replacing ListView's `onActivate` with `onSelect`,
`onSelectionChanged` with `onFocusedItemChanged`, `ListController.selectedIndex`
with `currentIndex`, and `selectionActive` with `highlightCurrentItem`. The
builder boolean is `highlighted`. The baseline and earlier revision receipts
above retain their historical vocabulary; they do not describe the current names.

All list callers and tests are migrated. The guide's task browser distinguishes
browsing/preview, choosing/opening, and viewport movement with visible outcomes.
The reorder demo preserves the current item's identity and shows the visual
highlight independently of keyboard focus. See
`widget-interaction-consistency-audit-2026-09-07.md` for the migration contract
and current validation.
