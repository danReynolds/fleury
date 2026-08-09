# RFC 0021 — The pixel canvas tier

**Status:** ACCEPTED 2026-08-09 (direction approved by Dan in session; this
document records the decisions). Implementation phased P1–P4.
**Depends on:** the `CanvasMarker` ladder and `drawLine(width:)` (PR #193),
the inline-image placement architecture (`InlineImage`/`InlineImagePlacement`
in the cell buffer, the placement-diffing `TerminalImageEncoder`, the serve
`<img>` overlay), and the startup image-protocol probe.

## 1. What this is

`Canvas` today rasterizes a `CanvasPainter`'s vector commands onto glyph
tiers (braille/halfBlock/quadrant/sextant/octant — sub-cell dots and blocks,
one color per cell). This RFC adds a **pixels** tier: the same painter
rasterized onto an RGBA buffer — antialiased strokes, per-pixel color,
additive glow — delivered to the terminal as an inline-image placement over
the canvas's cell rect, exactly the lane the `Image` widget already rides.

The painter abstraction is the whole point: **no app code changes between
tiers.** A `Canvas` picks intent with one word.

## 2. Decisions

### 2.1 Enum growth: `pixels` and `auto`

`CanvasMarker` gains:

- `pixels` — always rasterize; on a surface with no pixel-capable image
  protocol the canvas falls back to `braille` (a canvas must never be
  blank because the terminal is old).
- `auto` — resolve at build time from the confirmed surface capabilities:
  `ImageProtocol.kitty` or `.iterm2` → `pixels`; anything else → `braille`.
  Sixel is deliberately excluded in v1 (lossy palette, slow encode, small
  audience); revisit only with evidence.

Authors declare intent, and the two intents are distinct on purpose:
fidelity-is-the-point content (charts, maps) picks `auto`; texture-is-the-
point content (the asteroids showcase) stays pinned to a glyph tier and
exposes `pixels` behind an explicit flag if at all. The framework never
silently changes a canvas's aesthetic.

### 2.2 Width is in canonical sub-cell units

`drawLine(width:)` shipped defined in braille-dot units. That definition is
now canonical across every tier: a tier scales stroke width by its own
vertical density relative to braille's 4 rows/cell (pixels tier: ×
`pixelsPerCellY / 4`). A painter tuned on braille keeps its proportions
under `auto` — width semantics must not change out from under a painter
when the tier resolves differently.

### 2.3 Raster resolution

v1 fixes the raster at **8×16 pixels per cell** (≈4× braille density,
matching the typical 1:2 cell aspect). A `pixelScale` knob is explicitly
deferred: it multiplies encode cost and no consumer has asked.

### 2.4 The rasterizer is ours and small

Pure Dart, no dependencies (`dart:ui` does not exist off Flutter;
`package:image`'s drawing is general-purpose and slow for this shape).
`PixelSurface`: an RGBA `Uint8List`, cleared per frame, drawn with
signed-distance capsule strokes (per-segment bounding box, smoothstep edge
coverage — antialiasing and rounded caps/joints fall out of the math) and
**additive** blending, which is what makes overlapping neon strokes and
halo passes physically glow instead of overwriting. Budget: the asteroids
field is ~40 segments/frame over a ~1600×880 raster; bbox-bounded SDF work
is a few million pixel ops/second at 60fps — comfortable for the VM.
Measured at P1: ~5.0ms per busy frame (6 rocks double-passed, 40 sparks, 8
tracers) on the full 1600×880 raster — 3× the 60fps budget before the
encoder spends a byte, so the sustained-throughput question is entirely
the encoder's (P2/P3).

### 2.5 Placement lifecycle

One `InlineImage` per `RenderCanvas`, stable id for the render object's
lifetime, `pixels()` supplier returning the current raster. Frame-to-frame
updates ride the encoder's existing placement diffing; damage-bounded
re-encode via `croppedBytes` where the encoder asks. Transmission format
v1: whatever the encoder does today (PNG). If P2 profiling shows PNG
encode dominating the frame budget, the kitty raw-RGBA + zlib format is
the sanctioned fix — an encoder change, invisible above it.

### 2.6 Browser surface

Placements already mirror to the serve client's image overlay; the pixel
canvas inherits web parity with zero new wire surface. Rendering the
vector commands natively in a browser `<canvas>` (shipping draw commands
over the wire) is explicitly rejected for v1: it is a second renderer and
a second wire vocabulary to keep honest.

### 2.7 Out of scope, v1

Sixel; `pixelScale`; bloom/post-processing beyond additive accumulation;
the kitty animation protocol (`a=t` frame updates — plain placement
replacement first, measured before optimized); z-order guarantees beyond
existing placement semantics; any change to glyph-tier rendering.

## 3. Phases

- **P1** — this document + `PixelSurface` (rasterizer, headless tests).
- **P2** — `CanvasMarker.pixels`/`auto`; `RenderCanvas` records the
  placement; capability resolution; FakeTerminal tests; encode profiling.
- **P3** — serve parity verification at animation cadence; a sustained-
  throughput gate (image-bench covers single encodes only).
- **P4** — `asteroids --turbo` (marker: auto), captures, guide, CHANGELOG.

Each phase lands independently useful; the investment can stop after any
of them without stranded work.
