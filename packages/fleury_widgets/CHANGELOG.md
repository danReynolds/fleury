# Changelog

## Unreleased

- **Breaking: `KeyHintBar`'s `globalBindings` parameter is removed**, following
  the removal of `runApp`'s `globalBindings` in `fleury`. App-wide shortcuts
  now live in an outermost `KeyBindings`, so they are already in the focus
  chain the hint bar reads — there is nothing left to pass in by hand.

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
