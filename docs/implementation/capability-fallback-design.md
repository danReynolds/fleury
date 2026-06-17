# Capability Fallback — Design Analysis

**Date:** 2026-06-11 (P0b from the DX re-audit; answers "how should we
think about fallbacks — can this be generalized, or is it per-widget
code?")
**Status:** Design recommendation for maintainer ratification. No code
in this pass.

## The reframe: "capability fallback" is three different problems

The re-audit's headline — 3/57 widgets with capability handling — reads
as one giant rollout. Reading the machinery shows it is three problems
with three different right homes, two of which are already solved:

### 1. Style fidelity (color) — centralized, ALREADY DONE

The ANSI renderer already downsamples every emitted color through the
`quantizeColor` cascade (truecolor → indexed-256 → ANSI-16) based on
detected `ColorMode`. Widgets emit `RgbColor` and trust the renderer;
`MediaQueryData.colorMode` exists for the rare widget that pre-quantizes
(image dithering). **This is the industry-standard shape** — Rich and
Lip Gloss do exactly this — and it means 100% of the catalog already has
color fallback with zero widget code. No rollout exists here.

The residual color question is narrower and UX-level: a widget whose
*information* is color (ColorPicker swatches, heatmap intensity) is
meaningless on a mono terminal even with perfect quantization. That is
a per-widget design decision (show hex values, show density glyphs),
and only a handful of widgets have it.

### 2. Behavioral capabilities — per-widget by nature, ALREADY DONE

Clipboard writes, OSC-8 hyperlinks, image protocols, mouse: these are
*behaviors* with widget-specific fallback UX (DataTable shows a copy
result message; MarkdownText shows the URL inline; Image picks a glyph
renderer). The `resolveCapabilityRequirement` API exists for exactly
this, and the three widgets using it are the three widgets with
behavioral needs. **3/57 is not 5% coverage of one contract — it is 3/3
coverage of the behavioral contract.** Rolling requirement plumbing into
the other 54 widgets would be the messy outcome to avoid: most widgets
have no behavior to gate.

### 3. Glyph repertoire — the real gap, and it generalizes well

Fifteen widgets draw Unicode that can degrade on limited
terminals/fonts: braille canvases (charts, sparklines), block elements
(gauges, heatmaps, half-block buffers), box drawing (borders,
separators), and ornaments (`›`, `▸`, `─`). Today there is no glyph
capability detection at all and no fallback anywhere.

**Field practice, honestly:** colors-fallback is universal; box-drawing
substitution is classic (ncurses ACS, Rich's legacy-Windows box
substitution); but braille/block sub-cell graphics fallback is NOT
standard — Textual and friends simply require UTF-8. So matching the
field means box-drawing substitution plus documented UTF-8 assumptions;
going tiered on sub-cell graphics would exceed standard practice and is
cheap for us for a structural reason:

**The 15 widgets share a handful of painting primitives.** Charts don't
each draw braille; they use `braille.dart`, `half_block_buffer.dart`,
`quadrant_buffer.dart`, `digits.dart`, and shared ramp/border constants.
Teach the *primitives* the fallback and the widgets inherit it:

- Add a detected `GlyphTier { unicode, ascii }` to
  `TerminalCapabilities` (env-derived to start: `TERM=dumb|linux`,
  non-UTF-8 `LANG`/`LC_*` → ascii; else unicode — same passive
  philosophy as the rest of detection) and surface it as one new
  `MediaQueryData` field, exactly like `colorMode`.
- Each shared primitive gets an ascii rendering: block ramps
  (`▁▂▃▄▅▆▇█` → ` .:-=+*#%`), braille plotting falls back to
  block/ascii density (the primitive owns the resolution change),
  box-drawing/ornament constants get ascii equivalents (`─│┌┐` →
  `-|++`, `›` → `>`).
- Widgets do nothing unless their *information design* changes per tier
  (the ColorPicker/heatmap class), which is the small per-widget
  remainder — single digits of widgets, each a deliberate design, not
  plumbing.

This is the same layering philosophy that already worked twice: colors
degrade in the renderer (widgets ignorant), images degrade in the
protocol picker (one widget owns it). Glyphs degrade in the primitives
(widgets ignorant), and `MediaQuery` is already the delivery vehicle.

## What NOT to do

- Do not roll `resolveCapabilityRequirement` into 54 widgets — most
  have no behavior to gate, and per-widget glyph requirements would
  duplicate what the primitives can decide once.
- Do not auto-substitute glyphs cell-by-cell in the renderer — unlike
  color quantization, glyph substitution changes geometry and density
  (braille is 2x4 dots per cell); only the primitive that drew it can
  re-plot honestly. The renderer cascade is the wrong layer.
- Do not block on real-terminal matrix evidence — tier detection ships
  env-derived (passive) first, consistent with `fleury diagnose`;
  active probing stays the post-MVP terminal-matrix work.

## Proposed work, scoped

1. `GlyphTier` detection + `MediaQueryData.glyphTier` (core; small).
2. Ascii tiers in the shared primitives: ramps, braille→density
   fallback, box/ornament constant tables (one module each; tests are
   golden renders per tier).
3. The deliberate per-widget pass for color-as-information widgets
   (ColorPicker, heatmaps): tier-aware value display. Short list,
   design-reviewed individually.
4. Re-audit metric replaced: report behavioral coverage (3/3), style
   fallback (centralized, 100%), glyph-tier primitive coverage (N/M
   primitives), instead of the misleading single percentage.

Storybook gets a `glyphTier: ascii` toggle so every widget's fallback is
demoable — which also makes the contract visible to contributors adding
new widgets.

## Open questions for the maintainer

- Two tiers or three? (`unicode | ascii` vs splitting
  braille-capable from basic-unicode. Recommendation: start with two;
  the third has no reliable passive detection signal.)
- Should `GlyphTier` be overridable per-app (a `MediaQuery` wrapper is
  free) and per-user (an env var like `FLEURY_ASCII=1`)? Recommendation:
  both — the env override doubles as the accessibility/compat escape
  hatch and makes support triage trivial.
