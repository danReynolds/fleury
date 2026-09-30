## 0.1.0

- **Esc denies an `ApprovalPrompt`.** Shown with `present`, Esc used to pop the
  dialog without calling `onDecision`; it now makes the deny decision, the same
  as the prompt's semantic cancel. An inline prompt also denies on Esc instead
  of passing the key on.
- `KeyHintBar` inside a dialog shows only the bindings that can fire there: key
  hint resolution stops at a modal `KeyBindings` scope, as dispatch does.
- `FilePicker` keeps its cursor and listing when a parent rebuild passes a new
  but equivalent `filter` or `source`: a new filter re-filters the listing it
  already read, and a new source re-reads the directory, keeping the cursor on
  the same entry when it's still listed.
- Copies strip every control character. CR, LF and TAB become spaces, as on
  screen; other controls become U+FFFD, and an escape sequence collapses to one.
  `LogRegion` sources and `MessageList` authors are sanitized too.
- `Form`'s semantic submit action reports an `onSubmit` error through the
  runtime instead of dropping it.
- `Bar.stacked` with no segments paints nothing instead of throwing.
- `ColorPicker` marks no swatch as committed for an off-palette value, and its
  semantics describe the actual value.
- `Select`: pressing a disabled option no longer moves the highlight onto it or
  stops the arrow keys and Enter from working; the open list reports its
  highlight as it moves.
- `Autocomplete`: a click on a suggestion picks it. The press used to take
  focus from the field, which closed the list before the click completed.
- `Menu`, `FilePicker` and `CommandPalette`: pressing a row with no action (a
  disabled item or command, a menu separator, a link) no longer moves the
  highlight onto it or stops the arrow keys and Enter from working.
- `JsonView` draws a row cut by `maxLineLength` as cut, ending in `…`. An
  unselected cut row used to show its whole value after part of the label.
- `Image` in half-block mode draws a transparent top pixel as empty instead of
  in the terminal's default text color.
- A pinned `Panel` keeps tracking focus, so unpinning it shows current chrome.
- `Panel.focused` pins only the border and title. The panel's semantic region
  reports focus exactly while focus is inside it, so a panel pinned `true` no
  longer tells agents and assistive technology it has focus, and one pinned
  `false` no longer hides focus inside it.

- **Breaking:** `FileBrowser` and `FilePicker` read directories through a
  `FileSource` and report `FileEntry` values, so both run in the browser.
  Natively they default to `LocalFileSource`, the local disk; in a browser,
  pass a source such as `MemoryFileSource`. `FileBrowserEntry` and
  `FileBrowserEntryType` are now `FileEntry` and `FileEntryType`,
  `FileBrowser.entityFilter` is `entryFilter`, and `FilePicker.onSelect` and
  `filter` receive a `FileEntry` instead of a `dart:io` `File` or
  `FileSystemEntity`.
- `LogRegion`, `TerminalOutputRegion`, and `WorkflowSnapshot` are exported from
  `fleury_widgets_web.dart`; none of them needed `dart:io`. A test now walks the
  web barrel's imports so `dart:io` can't reach it: dart2js compiles `dart:io`
  code, which only fails when it runs.
- **Layout contract:** DataTable requires bounded height by default. Place it in
  Expanded/SizedBox or opt into `shrinkWrap: true` for content height.
- New LogRegion, LineChart, BarChart, Sparkline, Heatmap and Canvas widgets refresh mutable inputs,
  even when list/painter identity is unchanged. Reuse an unchanged widget
  instance to retain expensive paint caches. Shrinking chart data clamps the
  active cursor.
- First-party dropdowns, menus, tooltips, color pickers and toasts inherit live
  scopes from their logical owner and disappear when that owner unmounts.

- FileBrowser exposes a clickable, semantic parent-directory action in its
  existing separator row, including empty and unreadable directories.
- Collection widgets read viewport semantics lazily without rebuilding their
  content after scrolling. Selection, filtering, expansion, explicit refresh,
  and public controller notifications retain their behavior. The shared adapter
  uses `ListController.viewChanges`; no private core imports are needed.

- Tabs handle Left/Right and Home/End only while the tab strip has focus.
  Navigation bubbling from controls in a tab body no longer switches tabs or
  loses focus. Explicit Alt+digit and Ctrl+PageUp/PageDown shortcuts still work.

- **Breaking:** `Dialog` and `CommandPalette` no longer carry a semantic
  dismiss action of their own. A presented dialog's or palette's route
  advertises dismiss and honors `barrierDismissible` and `PopScope`; their
  own action bypassed both and could pop a page they were shown inline in.
  Dismiss through the route node (`role: SemanticRole.route`).
- A `CommandPalette` shown inline on a page no longer pops the page after
  running a command; a presented palette still closes.
- A `CommandButton` or palette row whose command throws is reported to
  runApp's error overlay. Activating one through semantics is a press: it
  reports `failed` for a command that throws, `unsupported` for one that
  turned disabled, hidden or gone since it built, and doesn't wait on the
  command. A palette row asks whether its command can run when chosen, so a
  stale row leaves the palette open. `CommandPaletteItem.onInvoke` may throw
  `SemanticActionDeclined` to decline.
- `FileBrowser` keeps its keys working in an empty or unreadable directory:
  Left and Backspace climb to the parent again.
- `FileBrowser` reads a directory when it opens it or on
  `FileBrowserController.reload()`, not on every parent rebuild; an inline
  `entryFilter` no longer re-reads the disk and resets the cursor. A new
  `entryFilter` applies at once to the entries already read, as `FilePicker`'s
  `filter` does. Toggling `showHidden`, changing the query or the
  `entryFilter`, or a reload keeps the selected entry, wherever it lands. The
  display order is kept until the entries or the filter change.
- `Image` no longer re-decodes when its parent rebuilds with the same
  source, an animated image keeps playing across rebuilds, and a static
  image is painted once rather than resampled every frame. After
  `ImageSource.evictFile` or `evictAll`, a rebuilt `Image.file` reads the
  file again.
- Markdown emphasis follows CommonMark's flanking rules: `snake_case`,
  `__init__` and `a * b * c` stay text instead of losing characters.
  Emphasis nests (`*use **only** this*`), `***both***` is bold and italic,
  and a paragraph of delimiters that never close parses in linear time.
- `JsonView` builds its rows once per document and expansion, not on every
  build, and `SearchPanel` ranks its results once per query. A parent that
  rebuilds `JsonView(value:)` hands a new document, so data it changed in
  place shows.
- Toasts, tooltips, autocomplete and completion lists, and the color
  picker's hex entry paint the theme where their owner sits; under a light
  app they painted the dark fallback. `Select` and `Menu` follow a theme
  change while open.
- `Tree`'s own semantic node follows the cursor (current index, selected
  key, visible range) through arrow keys, typeahead, clicks and scrolling,
  rebuilding alone: no row rebuilds for it.
- `TreeTable`'s cursor stays on its node when an expand or collapse above
  it, a filter, or new roots rebuild the rows; when the node leaves the
  rows it moves to the nearest ancestor still shown, including after two
  such changes before a frame. Enter and copy act on the node the user
  picked.
- The library's controls (`Select`, `MultiSelect`, `DatePicker`, `Stepper`,
  `RangeSlider`, `FilePicker`, `ColorPicker`, `Autocomplete`,
  `CompletionTextInput` and others), `SearchPanel`, `ConversationNavigator`
  and `FileMentionPicker` rebuild only when their own focus changes, not on
  every focus move.
- `DiffView` measures its line-number gutter once per document.
- `LineChart` collects its cursor positions only when it is interactive,
  and a chart behind a `RepaintBoundary` with an unchanged series list no
  longer repaints for its default palette.
- A `git format-patch` email signature (`-- `) after the last hunk no longer
  parses as a deletion.

- `LogRegion` no longer does work proportional to the whole log on every
  build: the unfiltered view order allocates nothing, and row-id validation
  re-checks the rows it already validated by equality and hashes only new
  ones. An append to a 100k-entry log with ids costs about 5 ms instead of
  29-36 ms.
- **Breaking:** `MarkdownView(markdown:)` no longer parses in its constructor;
  the view parses its `markdown` source and keeps the result while the source
  is unchanged. An appended source (streaming) re-parses only from its last
  line, so a token appended to a 200 KB document costs about 2 ms instead of
  38 ms, and a rebuild with unchanged text re-parses nothing. `document` is
  null for `MarkdownView.new`; `MarkdownView.document` is unchanged.
  `MarkdownText` renders incrementally the same way and reuses unchanged rows.
- `LogRegion` and `MessageList` start with the cursor on the newest entry and
  keep it there while following, so Ctrl+C copies what the view is showing
  instead of the first entry. `LogRegionController` and
  `MessageListController` default `initialIndex` to `ListController.natural`.
- **Breaking:** the deprecated `Command` alias is removed; use
  `CommandPaletteItem`.
- `FormController.submit()` returns false when the submit callback leaves a
  mounted, enabled field with an error. Callback updates and temporarily locked
  controls are applied before this final check, which focuses the invalid field.
  Temporarily disabling a control preserves its validation feedback state so
  reenabling it can recheck updated values; `clearErrors()` still resets it.
- `FormController.validate(autofocus: false)` displays errors without moving
  focus or scrolling. The default remains true; concurrent validation calls
  focus the first invalid field when any caller requests autofocus.

- `ImageSource.decoded` accepts optional prepared `encodedPng` bytes for static
  images, avoiding PNG encoding during the first placement paint. Callers must
  supply matching pixels and PNG bytes and keep both immutable while mounted.

- Forms refresh revealed validation after field and control updates, including
  programmatic choice changes and rules that read another registered field.
  Named and inline validators behave consistently; cleared errors stay hidden.
- First-invalid focus reveals the control and, when it fits, its error through
  enclosing vertical or horizontal `ScrollView`s after layout.
- Custom form fields can attach `field.focusNode` without managing another
  node. Focus diagnostics now check attachment rather than constructor syntax.

- The reexported core `Button` now takes `text` or `child`, exactly one, instead
  of `label`. Companion controls and examples use the renamed core argument;
  `CommandButton.label` remains its optional command-title override.

- `Toaster.show` returns an idempotent `ToastHandle`, accepts an optional `id`
  for replacement in place, and supports `persistent: true` without an expiry
  timer. Old handles/timers cannot dismiss replacements. `Toaster.maxToasts`
  optionally bounds retained toasts by evicting the oldest without queuing.
  `ToastHandle.isActive` reports whether the exact toast is still retained.
  Messages wrap within their available width; existing calls keep stacking.

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

- `Table` wheel/viewport scroll no longer assigns `controller.currentIndex` (ListView / DataTable parity). Keyboard navigation still reveals the cursor; `onFocusedItemChanged` reports user cursor moves.
- Interactive `Table` mirrors DataTable/FileBrowser/SearchPanel copy:
  `TableCopyOptions`, `TableCopyResult`, `exportTableRows`, Ctrl+C /
  `SemanticAction.copy`, and `onCopy`. Composition cells export via
  `tableCellText`, which reads `Text.data` — a cell built from any other
  widget exports as an empty field. Tree copy remains deferred to `TreeTable`.
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
