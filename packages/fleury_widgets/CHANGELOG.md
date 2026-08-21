# Changelog

## Unreleased

- **Unified control styling.** Buttons, toggles, choices, selectors, steppers,
  sliders, date/color pickers, and input wrappers now use their ordinary
  `style` property for both `CellStyle(...)` and `CellStyle.state(...)`.
  Per-control `errorStyle` properties are replaced by the `invalid` state, and
  `FleuryWidgetTheme.controlFocusStyle` / `disabledStyle` move to
  `ThemeData.controlStyle`.

- `CanvasContext.drawLine` gains `width:` — stroke thickness in sub-cell
  pixels (visual weight survives bounds changes), rasterized as a stamped
  round brush: gap-free diagonals, rounded caps and joints, cached per
  width, and `width: 1` is byte-identical to the old hairline. This is the
  primitive behind two-pass neon glow (wide dim halo under a narrow bright
  core — per-cell color resolves last-drawn-wins), showcased by the
  rebuilt Neon Asteroids sample: glowing outlines, tracer bullets,
  shockwave rings, impact screen-shake, and a cabinet bezel.

## 0.1.0

Initial public release.
