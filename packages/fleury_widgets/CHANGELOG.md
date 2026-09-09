## 0.1.0

- `NumberInput` forwards `enabled` and `readOnly` to the inner `TextInput`,
  matching `PasswordInput`, `CompletionTextInput`, and `TextArea`. Disable with
  those flags — `onChanged: null` does not disable numeric entry.
- `Autocomplete` forwards `enabled`, `readOnly`, and `validationError` to the
  inner `TextInput`, matching `PasswordInput`, `CompletionTextInput`, and
  `TextArea`. Disabled and read-only fields do not open the suggestion menu.
- Inspector/viewer rows (`CodeView`, `DiffView`, `LogRegion`, `MessageList`,
  `TaskGraph`, and `TerminalOutputRegion` via `LogRegion`) advertise
  `SemanticAction.select` for browse/selection. Handlers only move
  `currentIndex`; `activate` / tester `.press()` stay reserved for open/run.
  Prefer tester `.select()` when the action only changes selection.

- `Button` and `ButtonVariant` moved into core. This package continues to
  reexport them unchanged. Core buttons and companion value controls share
  one internal focus/activation implementation.

- Collection controllers use `initialIndex` for their constructor seed and
  `currentIndex` for the live browsing cursor. DataTableController uses
  `initialRowIndex` and `initialColumnIndex` with its existing live properties.
  Explicit null row cursors stay unset; omitted row cursors default to zero.
  Log and message tail-following controls the viewport independently of that cursor.
- NumberInput.initialValue and FileBrowser.initialDirectory are one-time seeds;
  parent rebuilds preserve edits and navigation. NumberInput rejects a seed
  alongside an external controller. FileBrowserController.openDirectory handles
  later navigation and exposes currentDirectory to observers.
- FileBrowser and SearchPanel honor incoming controller cursors on mount and
  replacement. Tables, tabs, data tables, and file browsers reject multiple active
  owning views; normal deactivation and reattachment remain supported.
- JsonView uses `defaultExpandedDepth` for its continuing expansion fallback.
  Tree.initialExpandedDepth remains a one-time seed.
- Text editing wrappers emit `onChanged` for user and semantic edits, including
  numeric normalization and choosing a completion. Programmatic writes notify
  controller listeners instead. See `docs/widget-state-ownership.md` for migration.

- MessageListController and LogRegionController separate the enabled `followTail`
  policy from read-only `isFollowing`, and expose `atBottom` and `unseenCount`.
  `jumpToIndex` preserves selection, and following incoming output no longer
  selects each new row. `scrollToBottom` catches up and enables following.
  Semantic state now includes both the policy and whether it is currently active.

- `FormController.isBusy` reports the whole accepted submit attempt, including
  validation, so submit and Back actions can be guarded immediately. Field
  editing can still use `isSubmitting` to lock only after validation succeeds.
  Submission also cancels safely if a notification detaches its form.

- `Form.of(context)` now shares the `FormController` through a `Scope`, so a
  widget that reads it rebuilds when the controller notifies (submission
  state, errors) without a `ListenableBuilder`.

- `DataTable.currentRowIndex` and `onFocusedItemChanged` support a parent-owned
  row cursor, so filtering and sorting can update data and cursor together
  without controller synchronization. This replaces `selectedIndex` and
  `onSelectionChanged`; the parent must accept requests through a rebuild.
  Table dimensions stay widget-owned and
  update atomically before controller listeners are notified.

- MultiSelect options expose a boolean semantic `setValue` action alongside
  toggling, so tests and other semantic consumers can request a desired checked
  state without changing the option key or dispatching duplicate callbacks.
- Tree branches publish the shared `expanded` state as well as tree metadata.

Initial public release.

- **Render objects derive geometry.** The catalog's render objects override
  `performPaint(buffer, offset)`; `RenderTable` declares its pinned-header and
  scrolled-body placement through core's geometry contract so its rows
  hit-test and expose semantic bounds without paint-time recording (RFC 0024).
- **`WidgetRoles`.** The catalog's domain semantic roles (`patchReview`,
  `toolCall`, `messageList`, `message`, `approval`, …) live here rather than in
  core's `SemanticRole`, each declaring the core role it projects through. Match
  them exactly like core roles: `tester.semantics().byRole(WidgetRoles.toolCall)`.
  Bases reproduce the previous ARIA projections, with three deliberate
  changes: `ConversationNavigator` wraps its rows in a `list` node so each
  `conversation` is a valid list item, `TraceTimeline` and `FileMentionPicker`
  now project as lists, and `ToolCallCard` announces as a polite live region.
- **Unified control styling.** Buttons, toggles, choices, selectors, steppers,
  sliders, date/color pickers, and input wrappers now use their ordinary
  `style` property for both `CellStyle(...)` and `CellStyle.interactive(...)`.
  Per-control `errorStyle` properties are replaced by the `invalid` state, and
  `FleuryWidgetTheme.controlFocusStyle` / `disabledStyle` move to
  `ThemeData.interactiveStyle`.

- `CanvasContext.drawLine` gains `width:` — stroke thickness in sub-cell
  pixels (visual weight survives bounds changes), rasterized as a stamped
  round brush: gap-free diagonals, rounded caps and joints, cached per
  width, and `width: 1` is byte-identical to the old hairline. This is the
  primitive behind two-pass neon glow (wide dim halo under a narrow bright
  core — per-cell color resolves last-drawn-wins), showcased by the
  rebuilt Neon Asteroids sample: glowing outlines, tracer bullets,
  shockwave rings, impact screen-shake, and a cabinet bezel.
