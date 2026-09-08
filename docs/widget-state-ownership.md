# Widget state ownership

Each piece of state has one authoritative owner. A widget may own a popup
cursor while its parent owns the committed value; those are different states.

## Public API convention

| Shape | Contract |
| --- | --- |
| `value` / `values` + `onChanged` | Parent-owned value. Interactions request changes; the parent supplies the next value. |
| Widget `initial*` argument | Seed internal state once per State lifetime. Later rebuilds do not reapply it. A new key creates new state. |
| Optional `controller` | The supplied controller owns its live state. Without one, the widget creates and disposes an internal controller. Both input and application code update that same state. |
| Navigation controller constructor `initialIndex`, `initialOffset` | Initial cursor/offset; runtime properties remain `currentIndex` and `offset`. DataTable uses `initialRowIndex` / `initialColumnIndex` and live `currentRowIndex` / `currentColumnIndex`. Tabs retains its live `index`. |
| Continuing configuration such as `followTail`, `defaultExpandedDepth` | A live policy, not a seed. Rebuilding with a new policy applies it. |

Keep simple controlled controls simple. Do not add controllers to checkboxes or
all three shapes to every widget. Reject a seed plus a controller for the same
state rather than silently ignoring one. `TextEditingController(text: ...)`
retains its established constructor; it initializes a complete editing session.

## Interaction and observation

Input `onChanged`, browsing `onFocusedItemChanged`, and choice callbacks report
interactions. Keyboard, pointer, and semantic actions share the same contract.
Direct controller writes notify controller listeners and update observing views
and form state, but do not emit an input interaction callback. Rejected edits and
cursor-only text moves do not emit `onChanged`.

Text widgets emit after the editing operation, using the accepted text. This
includes delayed paste chunks, history, completion, undo, redo, and composition.
If two fields share a text controller, an edit updates both displays but only
the originating field emits its interaction callback. Callback writeback does
not create another interaction event.

`currentIndex` is a remembered browsing cursor. Moving it reveals its row but
does not take keyboard focus or choose it. Actual selected values and text/cell
ranges remain distinct. Completion/history browsing uses the same current-item
terminology. Tab `index` represents the active tab.

## Lifetime and attachment

Create external controllers once in State and dispose them with their owner.
A replacement controller brings its own state; detach listeners from the old
one and never dispose a caller-owned controller. Removing an external controller
creates fresh internal state; there is no implicit transfer of the old draft.

A controller holding one viewport's metrics or row count has one active owning
view. List, scroll, table, data-table, tab, and file-browser controllers reject
simultaneous owners. Deactivation releases the attachment; activation acquires
it again, including GlobalKey moves. A scrollbar or listener is an observer,
not a second owning view. TextEditingController can deliberately synchronize
multiple fields because it owns a value rather than one viewport's metrics.

Nullable row cursors default to zero. Explicit null means no current row.
Mounting/clamping respects that null. Tail following controls the viewport and
does not silently choose a different starting cursor. Supply `initialIndex`
when a log or transcript should also start its cursor on a particular entry.

## Migration notes

- ListController constructor `currentIndex:` becomes `initialIndex:`.
- Collection controller constructor `selectedIndex:` becomes `initialIndex:`;
  its live `selectedIndex` becomes `currentIndex`. Text history/completion also
  use `currentIndex`; completion exposes `currentOption`, `focusOption`, and
  `moveCurrent` before `accept` commits a suggestion. Semantic completion state
  uses `completionCurrentIndex` instead of `completionSelectedIndex`.
- ScrollController constructor `offset:` becomes `initialOffset:`.
- DataTableController constructor `currentRowIndex:` / `currentColumnIndex:`
  become `initialRowIndex:` / `initialColumnIndex:`.
- JsonView's continuing expansion fallback becomes `defaultExpandedDepth`.
  Tree.initialExpandedDepth remains a one-time seed; explicit JSON expansion
  overrides continue to win over the fallback.
- NumberInput.initialValue and FileBrowser.initialDirectory no longer reset on
  rebuild. NumberInput rejects a non-null seed alongside a controller.
- FileBrowserController.openDirectory(path) navigates an attached browser.
  The controller exposes currentDirectory and notifies listeners; the widget's
  onDirectoryChanged callback reports navigation interactions only.
- Text onChanged no longer observes programmatic controller writes. Move
  all-origin subscriptions to controller listeners; retain onChanged for edits.

The [ownership audit](implementation/widget-state-ownership-audit-2026-09-08.md)
records the original divergences and regression scenarios. The public guide
demonstrates the convention with a controlled checkbox and a navigable task list.
