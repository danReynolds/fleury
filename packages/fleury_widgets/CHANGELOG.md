# Changelog

## 0.1.0

Initial public release.

- **`WidgetRoles`.** The catalog's domain semantic roles (`patchReview`,
  `toolCall`, `messageList`, `message`, `approval`, …) live here rather than in
  core's `SemanticRole`, each declaring the core role it projects through. Match
  them exactly like core roles: `find.byRole(WidgetRoles.toolCall)`.
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
