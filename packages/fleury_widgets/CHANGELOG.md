# Changelog

## 0.1.0

- `FormController.isBusy` reports the whole accepted submit attempt, including
  validation, so submit and Back actions can be guarded immediately. Field
  editing can still use `isSubmitting` to lock only after validation succeeds.
  Submission also cancels safely if a notification detaches its form.

- `Form.of(context)` now shares the `FormController` through a `Scope`, so a
  widget that reads it rebuilds when the controller notifies (submission
  state, errors) without a `ListenableBuilder`.

- `DataTable.selectedIndex` and `onSelectionChanged` support app-owned row
  selection, so filtering and sorting can update data and selection together
  without controller synchronization. Table dimensions stay widget-owned and
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
