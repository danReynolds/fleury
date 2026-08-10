# RFC 0021 — The pixel canvas tier

**Status:** IMPLEMENTED 2026-08-09 — P1–P4 all landed the same day, each
phase closed with a review that adjusted the next (the §2 "learning" notes
are those reviews' output).
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
- `auto` — resolve at build time from the confirmed surface capabilities.
  **P2 learning:** the widget layer reads the NEUTRAL `SurfaceCapabilities`,
  which deliberately hides protocol names — and the browser also reports
  placement support, so keying on "has placements" would have shipped
  empty-byte rasters to serve clients. Resolution therefore consults a new
  neutral bit, `SurfaceCapabilities.liveRasters` ("this surface can present
  per-frame raster placements"), true today exactly when the terminal
  confirmed Kitty graphics. iTerm2 (PNG-per-frame) and Sixel (re-rasterize)
  fail animation cadence and stay false; the serve surface flips its bit
  when P3's raster wire lands. Honest at every commit.

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
re-encode via `croppedBytes` where the encoder asks. Transmission format:
**P2 learning — PNG was never viable**: `InlineImage.bytes` is PNG by
contract and the core cannot encode one, so the raster lane
(`InlineImage.isRaster`: empty bytes + live `pixels()`) ships in P2, and
the Kitty presenter transmits it as raw RGBA (`f=32`), zlib level 1
(`o=z`). Measured on the busy-frame raster: 3.0ms/frame to compress,
66KiB compressed / 88KiB base64 — ~5.3MB/s at 60fps, and with the 5.0ms
raster the whole producer side is ~8ms of the 16.6ms frame budget.

### 2.6 Browser surface

**P3 learning — "placements already mirror" was FALSE for rasters**: the
serve wire ships file bytes and a raster has none. The shipped design:
`InlineImageFrame` gains a raster shape (id-length high bit + u16 dims;
file frames stay byte-identical to the old wire), the host compresses the
live RGBA once per frame (memoized so placement bounding, projected-fit
eviction, the ledger, and the transport all account the SAME true size —
the host/client ledger-identity invariant depends on it), and the client
inflates with the browser's native `DecompressionStream('deflate')`, blits
to a canvas, and publishes a data URL. Because raster ids are per-frame
and the decode is asynchronous, decode completion RE-APPLIES the current
placements — without that every frame's pixels would materialize just
after the only plan that referenced them, and never be seen. The client
declares `liveRasters=1` in INIT (additive, never version-inferred).
Rendering vector commands natively in a browser `<canvas>` stays rejected:
one renderer, one wire vocabulary.

### 2.7 Out of scope, v1 — and two known v1 properties

Sixel; `pixelScale`; bloom/post-processing beyond additive accumulation;
the kitty animation protocol (`a=t` frame updates — plain placement
replacement first, measured before optimized); z-order guarantees beyond
existing placement semantics; any change to glyph-tier rendering.

Two properties of the shipped v1, observed live and accepted:

- **Rasters paint above the text grid** (the placement layer's existing
  property, shared with `Image`): a text card overlapping a pixel canvas
  is pierced by lit strokes rather than covering them. Mostly-transparent
  rasters keep cards readable; proper z-interleaving is the deferred
  z-order work.
- **The first serve frame lands one decode behind** (~ms): the async
  inflate means a session's very first raster materializes just after its
  plan; at animation cadence every subsequent frame is covered by the
  decode-complete re-apply and the gap is imperceptible.

## 3. Phases — all complete

- **P1** ✅ — this document + `PixelSurface`. Measured: 5.0ms busy-frame
  raster (201fps headroom).
- **P2** ✅ — `pixels`/`auto` via the neutral `liveRasters` bit;
  placements with per-repaint ids; the kitty raw-RGBA+zlib lane (3.0ms +
  88KiB b64 per busy frame).
- **P3** ✅ — reordered by the P2 review: encoder round-trip + eviction
  proof + sustained gate (796µs/f, 13.5KB/f) FIRST, then the serve raster
  wire (§2.6), full client path green in real Chrome.
- **P4** ✅ — `asteroids --turbo` (auto: pixels on Kitty terminals AND the
  serve browser, braille elsewhere — never blank); verified live over
  serve: antialiased glowing rocks, additive halos, the vector-CRT ship.
