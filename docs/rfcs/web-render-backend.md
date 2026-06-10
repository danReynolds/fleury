# RFC: Native Fleury web host

Status: proposed architectural specification
Decision: **DOM-first web host**
Spike: landed in `fleury_web`

Known spike files:

- `packages/fleury_web/lib/src/dom_grid/cell_grid_html.dart`
- `packages/fleury_web/test/cell_grid_html_test.dart`
- `packages/fleury_web/tool/spike_gallery.dart`

Companion RFC:

- `docs/rfcs/semantics-pipeline.md` — retained, geometry-bearing semantics
  pipeline required for excellent web accessibility, IME caret placement, and
  focus/AT coherence.

## 1. Summary

Fleury-owned web apps should render directly from Fleury's resolved
`CellBuffer`, not by serializing every frame to ANSI and feeding xterm.js.

The current web path is:

```text
widget tree -> CellBuffer -> AnsiRenderer -> xterm.js
```

The proposed web app path is:

```text
widget tree -> CellBuffer -> WebTuiHost -> DomGridSurface
```

This is a web host architecture, not only a renderer swap. The browser host
owns five independent responsibilities:

- visual presentation;
- browser input;
- cell metrics and resize;
- clipboard;
- accessibility/semantics.

DOM is the default visual backend because Fleury is a semantic TUI framework
with a bounded visible cell viewport, not a general terminal emulator with
unbounded scrollback. DOM gives Fleury the best browser product surface:
native text shaping, inspectable output, real links, CSS integration, and a
straight path to semantic DOM.

Canvas/WebGL remain an internal fallback behind the same visual surface
contract if measured DOM mutation/layout cost misses the frame budget.

## 2. Decision

Build a native `WebTuiHost` for Fleury-owned web apps.

Resolved positions:

- **Default visual surface:** retained DOM grid.
- **Fallback visual surface:** canvas/WebGL only if performance gates require
  it.
- **Accessibility surface:** separate semantic DOM, independent of the visual
  backend.
- **Input surface:** browser-native keyboard, pointer, paste, focus, and IME.
- **Scheduling:** browser frames are driven through `requestAnimationFrame`
  with explicit read/update/write separation.
- **Runtime reuse:** web should share Fleury's frame-loop orchestration with
  native rather than grow a third copy of `run_tui.dart`.
- **Damage reuse:** dirty row planning consumes Fleury's paint damage signal;
  fresh buffer comparison is a fallback/oracle, not the primary path.
- **Semantics dependency:** rich web accessibility depends on the retained,
  geometry-bearing semantics pipeline described in the companion RFC.
- **Testing:** the live DOM renderer and the HTML artifact renderer share one
  pure span model so VM tests cover the real role-walking logic.
- **Terminal transport:** xterm.js remains for arbitrary ANSI sessions such as
  `fleury serve` until Fleury has a structured remote frame protocol.

This revises the original RFC in these important ways:

1. The main seam is a **web host**, not only a frame presenter.
2. DOM is the **default measured implementation**, not an unconditional forever
   choice.
3. IME, metrics, clipboard, scheduling, and accessibility are **core host
   architecture**, not late polish after rendering.
4. The DOM renderer has a concrete hot-path contract: retained rows, shared span
   model, class/style caching, `textContent`, and `replaceChildren`; no
   `innerHTML` in the live path.
5. Dirty row planning reuses Fleury's existing paint damage pipeline instead of
   re-diffing the whole buffer by default.
6. Web and native runtime loops should converge on a shared `TuiRuntime` /
   `FrameLoop`.
7. The semantic DOM presenter is backed by a companion core semantics pipeline,
   not by the current debug-grade on-demand semantic snapshot alone.

## 3. Goals

- Remove xterm.js from the normal Fleury-owned web app render/input path.
- Preserve Fleury's existing widget, focus, pointer, text editing, clipboard,
  and semantics models.
- Make DOM the default visual surface only after browser performance and
  interaction gates pass.
- Keep the visual surface swappable so a future WebGL/canvas implementation can
  reuse input, metrics, clipboard, and semantics.
- Reuse native frame-loop correctness: scheduling, damage tracking,
  post-frame callbacks, scope mounting, and buffer swap semantics.
- Reuse paint damage as the authoritative dirty-region hint for DOM row
  updates.
- Keep the testable core of DOM rendering pure and VM-testable.
- Produce benchmark data through Fleury's normal benchmark/reporting workflow,
  not one-off manual observations.

## 4. Non-goals

- Do not replace xterm.js for arbitrary terminal sessions in this RFC.
- Do not emulate a full VT terminal in DOM.
- Do not expose a user-facing renderer picker.
- Do not claim Kitty/Sixel/iTerm2 image protocol support until a real web image
  capability exists.
- Do not rely on native browser selection inside the visual grid.
- Do not make browser accessibility depend on screen readers parsing visual row
  spans.
- Do not move web-only abstractions into `fleury` core until another host needs
  them.

## 5. Evidence and Constraints

The external research does not support "DOM because it is fastest." It supports
"DOM-first because Fleury is a semantic browser UI runtime with a bounded cell
viewport."

Important evidence:

- xterm.js keeps visual DOM rows `aria-hidden` and builds separate
  accessibility structures for screen-reader mode. That matches the required
  Fleury split between visual DOM and semantic DOM.
- xterm's DOM renderer retains row elements, replaces row children with
  generated spans, uses a width cache, applies renderer-controlled
  letter-spacing correction, and injects reusable CSS classes for common
  styles.
- xterm and VS Code terminal history are explicit that DOM can lose on raw
  large-grid performance. Excessive element creation, layout cost, and Unicode
  width drift are the main risks.
- Ratzilla, the closest public cell-buffer-to-web analog, describes WebGL2 as
  the high-performance backend, canvas as a Unicode-capable fallback, and DOM
  as the most compatible/accessibility-friendly but slowest large-grid backend.
- Canvas/WebGL pixels are not semantic HTML. A GPU visual layer still needs a
  parallel semantic DOM for accessible Fleury apps.
- Browser input is a subsystem. IME requires composition state, hidden textarea
  handling, event ordering care, and caret geometry for candidate-window
  placement.
- Dart's browser API direction is `package:web`/JS interop, not `dart:html`.

Conclusion: DOM is the right default for Fleury's web product. Canvas/WebGL is
a performance contingency, not the starting architecture.

## 6. Current Fleury Contracts

The browser host should satisfy these local contracts.

| Concern | Current contract |
| --- | --- |
| Frame output | `run_tui_web.dart` renders a `CellBuffer`, then currently diffs through `AnsiRenderer` into `WebTerminalDriver`. Native `run_tui.dart` builds a full next-frame `CellBuffer` and lets `AnsiRenderer` diff it against the previous frame. |
| Scheduling | Current web frames are coalesced with `scheduleMicrotask`; native runtime now has `FrameScheduler` for coalescing and optional caps. The web loop has drifted and should converge on shared runtime orchestration. |
| Cursor | `RenderTextInput` paints cursor style into the buffer; a separate visual cursor overlay is not required. |
| Caret geometry | IME placement still needs a public focused-caret rectangle; current cursor paint math is internal to text input rendering. |
| Selection | Selection is model-driven from cell-coordinate pointer events and painted back into the buffer. |
| Text input | Fleury already has `TextInputEvent`, `KeyEvent`, `PasteEvent`, and composing APIs; browser events should map into those. |
| Clipboard | `Clipboard.instance` is swappable; web should provide a browser implementation plus in-process fallback behavior. |
| Accessibility | Existing accessibility snapshots are text-first, rebuilt on demand, and geometry-less; rich web ARIA needs the retained geometry-bearing semantics pipeline in the companion RFC. |
| Protocol/image cells | `protocolAnchor` exists in cells, but current DOM rendering treats it as a placeholder, not a supported capability. |

## 7. Architecture Overview

```text
                          Browser event sources
                    keyboard / pointer / paste / resize
                                   |
                                   v
                              WebTuiHost
                                   |
        +--------------------------+--------------------------+
        |                          |                          |
   DomInputSource             CellMetrics              WebClipboard
        |                          |                          |
        v                          v                          v
   InputDispatcher            MediaQuery size          Clipboard.instance
        |
        v
   Fleury runtime
        |
        v
 owner.renderFrame(root, backBuffer)
        |
        v
   FramePlanner
        |
        +--------------------------+--------------------------+
        |                          |                          |
   FrameSurface              SemanticDomPresenter       Instrumentation
        |
        v
   DomGridSurface
        |
        v
   aria-hidden visual DOM grid
```

`WebTuiHost` owns orchestration. Each subcomponent has one job and a narrow
contract:

- `DomInputSource` emits Fleury `TuiEvent`s.
- `CellMetrics` owns measurement and cell-coordinate conversion.
- `FramePlanner` computes dirty rows and span models.
- `FrameSurface` applies visual output.
- `SemanticDomPresenter` applies semantic output.
- `WebClipboard` implements browser clipboard behavior behind
  `Clipboard.instance`.

## 8. Core Types

These types are proposed API shapes, not necessarily final public APIs. Keep
them private to `fleury_web` until proven.

### `WebTuiHost`

```dart
final class WebTuiHost {
  WebTuiHost({
    required FrameSurface frameSurface,
    required DomInputSource inputSource,
    required CellMetrics cellMetrics,
    required SemanticDomPresenter semantics,
    required WebClipboard clipboard,
    required BrowserFrameScheduler frameScheduler,
    required WebHostInstrumentation instrumentation,
  });

  Future<void> run(Widget Function() rootFactory);
  void requestFrame(FrameReason reason);
  Future<void> dispose();
}
```

Responsibilities:

- mount the Fleury root;
- install web clipboard before app code runs;
- wire input events into `InputDispatcher`;
- maintain front/back `CellBuffer`s;
- integrate browser sizing into `MediaQuery`;
- schedule frames through `BrowserFrameScheduler`;
- call visual and semantic presenters in the write phase;
- flush post-frame callbacks after DOM writes;
- expose instrumentation counters.

`WebTuiHost` should be a browser adapter over a shared runtime/frame-loop core,
not a third independent copy of the native loop. The extraction target is a
platform-agnostic `TuiRuntime`/`FrameLoop` that owns mount, scope stack, input
dispatch, front/back buffers, frame scheduling, buffer swap, and post-frame
callback timing. Native `runTui` and web `runTuiWeb` then inject platform
specifics: terminal sink or `FrameSurface`, driver events, flush scheduler,
debug layers, and host capabilities.

Until that extraction lands, the web host must explicitly preserve the native
contracts it depends on: `FrameScheduler` coalescing, paint damage handoff,
post-frame callback timing, and conservative full-diff behavior after layout
damage.

### `BrowserFrameScheduler`

`FrameScheduler` already knows how to coalesce frame requests and optionally cap
frame rate. The browser host should reuse that logic with a browser-specific
flush scheduler.

```dart
final class BrowserFrameScheduler {
  BrowserFrameScheduler({
    required Clock clock,
    required void Function(FrameReason reason) onFrame,
    Duration minFrameInterval = Duration.zero,
  });

  void requestFrame(FrameReason reason);
  void dispose();
}
```

Browser-specific flush behavior:

```text
if delay <= 0:
  requestAnimationFrame(flush)
else:
  Timer(delay, () => requestAnimationFrame(flush))
```

The web host must not flush visual DOM writes from a microtask. Microtask
coalescing was acceptable for ANSI writes; DOM writes need the browser paint
clock.

### `FrameSurface`

```dart
abstract interface class FrameSurface {
  CellSize get size;
  WebSurfaceCapabilities get capabilities;

  void present(
    CellBuffer previous,
    CellBuffer next,
    FramePresentationPlan plan,
  );

  void resize(CellSize size);
  Future<void> dispose();
}
```

`FrameSurface` is visual only. It does not own input, clipboard, metrics, or
semantics.

Do not expose terminal-specific capability names from this interface unless the
surface is adapting an existing terminal path. Prefer a web-native capability
shape:

```dart
final class WebSurfaceCapabilities {
  final ColorMode colorMode;
  final bool supportsTrueColor;
  final bool supportsSemanticLinks;
  final InlineImageCapability inlineImages;
  final bool supportsGlyphOverlay;
}

enum InlineImageCapability {
  none,
  domImage,
}
```

If existing Fleury internals currently require `TerminalCapabilities`, add an
adapter layer rather than making terminal terminology the long-term web host
contract.

For `DomGridSurface`, `supportsTrueColor` is always true. The surface reads
`CellStyle.foreground` and `CellStyle.background` through `toRgb()` directly;
it does not apply terminal `ColorMode` quantization.

### `FramePresentationPlan`

`FramePresentationPlan` is computed once by the host/planner and consumed by
visual surfaces.

```dart
final class FramePresentationPlan {
  final FrameReason reason;
  final bool fullRepaint;
  final CellSize size;
  final FrameDamage damage;
  final List<RowSpanModel> dirtyRowModels;
  final bool metricsChanged;
  final Duration frameStartedAt;
}

final class FrameDamage {
  final bool fullRepaint;
  final bool requiresFullDiff;
  final CellRect? dirtyBounds;
  final DirtyRows dirtyRows;
  final DamageSource source;
}

enum DamageSource {
  paintDamage,
  perRowPaintDamage,
  fullRepaint,
  verificationDiff,
}
```

Why compute this outside the surface:

- avoids each surface re-walking buffers differently;
- consumes Fleury paint damage once, before any presenter-specific work;
- gives tests one pure model to assert;
- records useful instrumentation in one place;
- keeps a future WebGL surface compatible with DOM planning data.

Primary dirty-row source:

1. use per-row / row-range paint damage once available;
2. otherwise derive conservative dirty rows from a measured renderer/presenter
   damage handoff once the benchmark evidence says it pays for itself;
3. use full repaint when layout invalidation, resize, protocol cells, or
   unknown damage make region hints unsafe;
4. use `compareRows(previous, next)` only as a verification mode, fallback, or
   parity oracle when damage is unavailable.

`XtermAnsiSurface` may ignore `dirtyRowModels` and continue using
`AnsiRenderer` while it exists as a temporary parity path.

### `RowSpanModel`

The row span model is the pure, shared rendering core.

```dart
final class RowSpanModel {
  final int row;
  final int cols;
  final List<CellSpanRun> runs;
}

final class CellSpanRun {
  final int startCol;
  final int widthCols;
  final String text;
  final CellStyle style;
  final CellRunKind kind;
  final WidthCorrection correction;
}

enum CellRunKind {
  text,
  wideText,
  emptyText,
  protocolPlaceholder,
}
```

The builder walks `CellRole`, not raw strings:

- `empty`: emits a space with default style;
- `leading`: emits the grapheme and owns its logical width;
- `continuation`: emits nothing;
- `protocolAnchor`: emits a placeholder unless a web capability exists;
- `protocolCovered`: emits nothing.

Both renderers consume this same model:

- `renderFrameHtml` for VM-tested artifacts;
- `DomGridSurface` for live browser nodes.

The live DOM path must not have a second, separate role-walking implementation.

## 9. Frame Lifecycle

DOM rendering needs explicit frame phases to avoid layout thrashing.

One browser frame is:

1. **Read phase**
   - drain pending `ResizeObserver`, font, DPR, and container invalidations;
   - read layout only through `CellMetrics`;
   - compute the new `CellSize`;
   - update pending focus/caret geometry reads.
2. **Runtime update phase**
   - update `MediaQuery` if size changed;
   - dispatch queued Fleury input events;
   - render the widget tree into the back `CellBuffer`;
   - take conservative paint damage from a measured renderer/presenter handoff;
   - derive dirty rows from damage;
   - build row span models only for dirty rows.
3. **Write phase**
   - mutate visual DOM through `FrameSurface.present`;
   - mutate semantic DOM through `SemanticDomPresenter.present`;
   - update hidden textarea position if caret geometry changed;
   - record instrumentation marks.
4. **Commit phase**
   - swap front/back buffers;
   - flush post-frame callbacks;
   - handle callbacks that request another frame.

Hard rules:

- `FrameSurface.present` must not perform layout reads.
- `SemanticDomPresenter.present` must not perform layout reads.
- `CellMetrics` is the only component that reads DOM geometry.
- Layout reads happen before writes in a frame.
- DOM writes happen under `requestAnimationFrame`.
- `ResizeObserver` callbacks mark metrics dirty and request a frame; they do
  not directly render.
- Browser event handlers (keyboard, pointer, paste, composition, clipboard,
  resize) **enqueue** input and `requestFrame`; they never mutate Fleury state
  or the DOM synchronously. Async sources (IME composition, clipboard
  callbacks) fire outside rAF, so synchronous mutation would re-enter or write
  during another frame's write phase. All effects land in the update phase.

This is an initial implementation requirement, not a late benchmark
optimization.

## 10. DOM Visual Surface Specification

### 10.1 DOM Shape

The visual grid is:

```html
<div class="fleury-screen" aria-hidden="true">
  <div class="fleury-row"></div>
  <div class="fleury-row"></div>
  ...
</div>
```

Rules:

- one retained row element per visible row;
- row elements are created on mount and resize only;
- row order is stable;
- visual grid has `aria-hidden="true"`;
- visual grid has `user-select: none`;
- pointer handling is owned by the host/input layer, not by individual spans.

### 10.2 Dirty Row Application

For each frame:

```text
for model in plan.dirtyRowModels:
  row = model.row
  nodes = domRowFactory.createNodes(model)
  rowElements[row].replaceChildren(...nodes)
```

Implementation requirements:

- use `document.createElement('span')`;
- use `span.textContent = run.text`;
- use `rowElement.replaceChildren(...)`;
- optionally use a `DocumentFragment` or a local array before replacement;
- never use `innerHTML` in the live hot path;
- never remove and re-append row elements for a normal frame;
- do not install per-cell event listeners.

`innerHTML` remains acceptable only for the static artifact renderer generated
from the shared span model.

Do not use a fresh full-buffer `compareRows(previous, next)` pass as the normal
dirty-row source. The planner consumes Fleury paint damage first, because paint
already knows what changed. Buffer comparison is useful as a debug assertion,
fallback, or parity oracle while the damage pipeline is being generalized.

Span pooling is optional. Do not add a pool until instrumentation shows element
allocation/GC is the bottleneck. The first contract is simpler: retained rows,
new spans for dirty rows, no parser, no row churn.

### 10.3 Span Merging

The span builder must merge adjacent cells when all merge-relevant properties
are equivalent:

- style identity after theme/inverse resolution;
- foreground/background class or truecolor style;
- text decorations;
- cursor/selection/focus state;
- link/hover state;
- width correction policy;
- run kind.

A row of default-style ASCII text should normally produce one span, not one
span per cell.

Do not merge:

- across wide grapheme boundaries;
- across protocol placeholders;
- across cursor cells if cursor styling affects the span;
- across cells with different width correction;
- across future semantic link boundaries if the visual span needs link hover
  styling.

### 10.4 Style Strategy

The renderer must not build large inline `style=""` strings per span per frame.

Use a hybrid style strategy:

- inject a stable `<style>` element for host/theme-level CSS;
- use CSS classes for default palette colors and common text attributes;
- use inline style only for truecolor RGB or rare dynamic values;
- cache resolved style output by `(CellStyle, themeVersion, selectionState)`;
- clear caches when font/theme/color mode changes.

Suggested classes:

```text
fleury-fg-N
fleury-bg-N
fleury-bold
fleury-dim
fleury-italic
fleury-underline
fleury-strike
fleury-inverse-resolved
fleury-cursor
fleury-selection
```

Truecolor cells can use inline `color:#rrggbb` and
`background-color:#rrggbb`, but the string should be cached in the style
resolver rather than rebuilt inside the row loop.

### 10.5 Selection Rendering

Fleury selection is model-driven and painted into the `CellBuffer`. The DOM
backend must not let native browser selection become the source of truth.

Default behavior:

- visual grid has `user-select: none`;
- pointer events map to Fleury `MouseEvent`s in cell coordinates;
- Fleury selection state paints selected cells back into the buffer.

Optional later optimization:

- a separate selection overlay layer may be added if painting selection into
  the text spans becomes too expensive or conflicts with contrast/a11y goals.

If an overlay is added, it must be derived from Fleury selection state and must
not replace the existing selection model.

### 10.6 Protocol and Images

The current DOM surface reports no inline image support.

Rules:

- `protocolAnchor` is rendered as an unsupported placeholder or omitted per
  capability policy;
- `protocolCovered` is skipped;
- Kitty/Sixel/iTerm2 escape compatibility is not claimed;
- a future `domImage` capability must define lifecycle, sizing, alt text,
  fallback text, and semantic exposure.

## 11. Cell Metrics and Alignment

`CellMetrics` is authoritative for browser geometry.

### 11.1 Measured Cell Box

```dart
final class MeasuredCellBox {
  final double cssCellWidth;
  final double cssCellHeight;
  final double cssCanvasWidth;
  final double cssCanvasHeight;
  final double devicePixelRatio;
  final int cols;
  final int rows;
}
```

Measurement rules:

- wait for `document.fonts.ready` before final measurement;
- measure the active font stack, size, weight, and line height;
- remeasure on font load, theme/font option changes, DPR changes, zoom changes,
  and container resize;
- set row height and line height from measured CSS pixels;
- set screen width/height from `cols * cssCellWidth` and
  `rows * cssCellHeight`;
- expose `cellForPoint(x, y) -> CellOffset` using cached measurements.

`ch` is allowed as an artifact fallback or sanity baseline. It is not the live
contract. The live contract is the measured cell box.

### 11.2 Natural Text Flow and Correction

Do not pin every cell to a separate pixel-width box. That destroys span merging
and creates unnecessary layout work.

Use this hierarchy:

1. For normal uniform runs, rely on natural monospace advance under the measured
   font.
2. Use renderer-controlled spacing correction when natural advance drifts from
   `widthCols * cssCellWidth`.
3. Use explicit inline-block width only for runs that require it: wide glyphs,
   fallback glyphs, protocol placeholders, or measured-deviation cases.

Clarification:

- Arbitrary user/global `letter-spacing` is banned.
- Renderer-controlled letter-spacing correction is allowed.

The width correction model should be explicit:

```dart
final class WidthCorrection {
  final WidthCorrectionKind kind;
  final double letterSpacing;
  final double? explicitWidth;
}

enum WidthCorrectionKind {
  none,
  rendererLetterSpacing,
  explicitRunWidth,
}
```

The span builder may merge only runs with compatible correction.

### 11.3 Width Cache

Measure text advance through a cache keyed by:

- grapheme text;
- font family;
- font size;
- font weight;
- italic;
- DPR-sensitive metrics version.

The cache exists for correction, not logical width determination. Fleury
already knows logical width from `CellRole.leading` and `CellRole.continuation`.

### 11.4 CSS Baseline

Base visual CSS should include:

```css
.fleury-screen,
.fleury-screen span {
  font-family: var(--fleury-font-family);
  font-size: var(--fleury-font-size);
  font-kerning: none;
  white-space: pre;
  tab-size: 1;
}

.fleury-row {
  overflow: hidden;
  height: var(--fleury-cell-height);
  line-height: var(--fleury-cell-height);
}
```

Ligatures should be disabled by default unless Fleury adds an explicit feature
for joined-character display. A grid renderer cannot let font ligatures change
column counts without an explicit correction policy.

## 12. Input Specification

`DomInputSource` maps browser events to Fleury events. It does not produce ANSI.

### 12.1 Hidden Textarea

Use a hidden/offscreen textarea or equivalent editable target:

- it receives keyboard input;
- it receives paste;
- it participates in IME composition;
- it can be repositioned near the caret for IME candidate windows;
- it is not used as the visible text model.

The textarea value should be treated as a transient input buffer. Fleury's text
editing state remains the source of truth.

### 12.2 Keyboard Mapping

Keyboard handling uses two channels:

- `keydown` for controls, navigation, shortcuts, modifiers, and repeat state;
- `beforeinput`/`input` or textarea delta for printable text.

Rules:

- do not emit duplicate printable text from both `keydown` and `input`;
- handle `KeyboardEvent.key`, `code`, `repeat`, and modifiers;
- treat `Dead` and `Unidentified` keys conservatively;
- preserve platform differences for Meta/Command, Ctrl, Alt/Option, and
  browser-reserved shortcuts;
- keep a browser key trace fixture for every mapping decision.

### 12.3 Composition

Add a `CompositionController`.

State machine:

```text
idle
  compositionstart -> composing
composing
  compositionupdate -> update composing text/range
  input before end -> buffer pending text if browser requires it
  compositionend -> commit or cancel
```

Responsibilities:

- track composition start/update/end;
- update Fleury composing ranges;
- avoid duplicate commits from browser-specific event ordering;
- position the textarea at the focused caret rectangle;
- handle browsers where `compositionend.data` is incomplete or unreliable.

IME support is a Phase 2 exit requirement, not a later polish item.

### 12.4 Pointer Mapping

Pointer events are converted to Fleury cell-coordinate `MouseEvent`s:

- pointer down/up;
- pointer move;
- drag with pointer capture;
- wheel/scroll;
- button and modifier state;
- touch/stylus if supported by the browser event model.

`CellMetrics.cellForPoint` is the only coordinate conversion path.

Open policy:

- whether hover `moved` events are emitted continuously or only while a button
  is down remains a performance/product decision.

### 12.5 Paste

Paste emits `PasteEvent(text)`.

Rules:

- prefer clipboard event text when available;
- prevent default insertion into the hidden textarea when Fleury consumes paste;
- preserve multiline text exactly;
- use the in-process clipboard fallback when browser clipboard access is
  unavailable.

## 13. Focus and Accessibility Coherence

This is a first-class risk area. The browser host has three related focus
models:

- browser focus, needed for keyboard/IME;
- Fleury focus, needed for app behavior;
- assistive-technology focus/virtual cursor, needed for screen readers.

Add a `WebFocusCoordinator`.

```dart
final class WebFocusCoordinator {
  SemanticNodeId? get activeSemanticNode;
  CellRect? get activeCaretRect;

  void handleBrowserFocusIn(WebFocusTarget target);
  void handleBrowserFocusOut(WebFocusTarget target);
  void handleSemanticActivation(SemanticNodeId id);
  void syncFromFleuryFocus(FocusSnapshot snapshot);
}
```

Initial model:

- keyboard capture normally stays on the hidden textarea;
- Fleury focus remains the source of truth for app focus;
- semantic DOM mirrors the focused/actionable state;
- semantic node activation dispatches Fleury focus/action events;
- after semantic activation, keyboard capture returns to the textarea unless a
  tested screen-reader flow requires otherwise.

The visual DOM grid remains `aria-hidden`.

## 14. Semantic DOM Presenter

`SemanticDomPresenter` projects Fleury semantics into a separate DOM tree.

Responsibilities:

- expose roles, labels, values, focus, and actions;
- expose app-level live regions only when a widget explicitly requires them;
- expose links from Fleury semantic/link data;
- avoid dumping the entire visual grid as a live terminal log;
- preserve stable semantic IDs for incremental updates;
- keep semantic updates synchronized with visual frame commits.

Implementation phases:

1. Minimal root and focused-node mirror.
2. Actionable controls and labels.
3. Text-editing semantics.
4. Link projection.
5. Rich live regions where framework semantics request them.

The semantic presenter consumes `AccessibilitySnapshot` initially if that is
the only available shape, but the architecture should allow a richer semantic
tree as the long-term input.

### 14.1 Coverage and fallback (no silent gaps)

`aria-hidden` on the visual grid plus a pure semantic projection means any
visible widget that contributes no semantic node is **invisible to assistive
technology, silently**. xterm.js can hide its visual rows precisely because its
accessibility tree reads the actual row text as a backstop; this design removes
that backstop. A framework whose differentiator is being *more* accessible than
a terminal must not ship a model that can be *less* complete than row-reading.

Coverage is therefore a requirement, not an emergent property:

- a low-priority text fallback projects the cell-region text for any visible
  region not covered by a richer semantic node (structured where possible,
  readable everywhere);
- a debug-time **semantic coverage audit** flags painted regions with no
  covering semantic node. The companion RFC's per-node `CellRect` makes this
  cheap: "visible cells covered by no node" is directly computable.

"Avoid dumping the whole grid as a live log" (above) is about *live-region
noise*, not about leaving content unreachable. The two must both hold:
no terminal-log spam, and no unreachable visible content.

## 15. Clipboard

`WebClipboard` is installed through `Clipboard.instance` before the app runs.

Requirements:

- call `navigator.clipboard.writeText` when available;
- require/record secure-context availability;
- report permission failures explicitly;
- preserve the existing in-process register fallback;
- avoid treating browser write failure as app-local copy failure when the
  fallback succeeds.

Clipboard reports should distinguish:

- system clipboard write succeeded;
- system clipboard denied/unavailable but in-process fallback stored text;
- both system and fallback failed.

## 16. Instrumentation

The browser host must emit structured timing and count data.

Per frame:

- frame reason;
- coalesced reasons;
- viewport size;
- dirty row count;
- dirty cell estimate;
- span count;
- DOM nodes created;
- rows replaced;
- style cache hits/misses;
- width cache hits/misses;
- metrics reads;
- runtime render time;
- span build time;
- DOM apply time;
- semantic apply time;
- total rAF frame time.

Where browser APIs allow it, also collect:

- layout/style recalculation time;
- long tasks;
- dropped/late frames;
- heap growth.

This data should feed the normal Fleury scoreboard/reporting path. Browser
renderer progress should not depend on one-off manual screenshots or console
timings.

## 17. Testing Strategy

### 17.1 Pure VM Tests

Move role walking and run merging into a pure span builder.

VM tests assert:

- visible text equals `CellBuffer.textInRange`;
- combining marks stay attached;
- ZWJ emoji stay intact;
- wide graphemes emit one run with `widthCols == 2`;
- continuation cells emit nothing;
- protocol covered cells emit nothing;
- styles resolve correctly;
- same-style runs merge;
- correction policies prevent unsafe merges;
- HTML artifact escaping is correct.

The string renderer is an adapter over the span model, not the primary logic.

### 17.2 Browser DOM Tests

Browser tests assert:

- retained row count is stable across frames;
- clean rows are not replaced;
- dirty rows use `replaceChildren`;
- live path does not use `innerHTML`;
- span `textContent` matches span model text;
- measured cell metrics produce expected row/screen dimensions;
- pointer coordinates map to expected cells;
- resize changes produce one coalesced Fleury resize/frame update.

Run through `dart test -p chrome` where sufficient; use Playwright where
browser APIs, screenshots, or cross-browser checks are needed.

### 17.3 Visual Tests

Add screenshot/pixel checks for:

- ASCII grid alignment;
- CJK wide glyph alignment;
- emoji/fallback glyph containment;
- box drawing;
- inverse/selection/cursor styling;
- DPR/zoom changes;
- long rows at `80x24`, `160x50`, and `300x100`.

Visual tests should compare geometry and alignment, not only pixels where font
rendering differs by platform.

### 17.4 Input Trace Tests

Record browser event traces and expected Fleury events for:

- printable text;
- navigation keys;
- shortcuts/modifiers;
- key repeat;
- paste;
- mouse down/up/drag/wheel;
- composition start/update/end.

IME automation is browser-sensitive. Where full automation is not reliable,
keep manual test scripts and browser-specific trace fixtures in the repo.

### 17.5 Accessibility Tests

Browser tests assert:

- visual grid is `aria-hidden`;
- semantic root exists;
- focused Fleury node is reflected in semantic DOM;
- actionable nodes expose role/name/state;
- link semantics project to anchors when supported;
- semantic updates are synchronized with visual commits.

Manual screen-reader verification remains required before claiming support.

## 18. Performance Gates

Run the DOM backend through the normal Fleury benchmark/reporting workflow.
Once the retained semantics pipeline is wired for web, benchmark the product
configuration with the semantic presenter active. Visual-only runs are useful
diagnostics, but they are not the release gate for an accessible web host.

Minimum scenarios:

- `80x24` normal app interaction;
- `160x50` large viewport;
- `300x100` stress viewport;
- no-op frame;
- single dirty cell;
- dirty row;
- full-frame churn;
- scroll-like row churn;
- cursor blink;
- text input burst;
- selection drag;
- resize burst.

Collect p50/p95:

- runtime render;
- span planning;
- DOM apply;
- semantic apply;
- semantic node diff/apply count;
- total browser frame;
- DOM node count;
- heap growth.

Suggested initial pass gate:

- the gate bounds **total frame time** (Dart runtime render + span planning +
  DOM apply + semantic apply + browser style/layout), not just the apply slice.
  Bounding apply+layout alone can pass while the Dart-side render slice on
  dart2js still blows the frame budget;
- at `160x50`, p95 total frame stays under roughly 8 ms;
- at `300x100` stress, p95 total frame stays under roughly 16 ms;
- no unbounded heap growth across sustained churn;
- input-to-paint latency remains within one browser frame for ordinary input.

Diagnose a miss by failure mode — they have different remedies:

- **apply/layout-bound** (DOM mutation or browser style/layout dominates):
  build `WebGlGridSurface` behind `FrameSurface`. Keep `DomInputSource`,
  `CellMetrics`, `SemanticDomPresenter`, and `WebClipboard` unchanged.
- **runtime-render-bound** (Dart build/layout/paint/plan dominates): WebGL does
  not help — the lever is the build target. Evaluate `dart2wasm`/WasmGC, which
  speeds Dart compute (DOM calls cross the JS boundary regardless of target, so
  WASM helps render, not apply). Instrumentation must separate the two slices so
  the miss is attributed correctly rather than reflexively answered with WebGL.

## 19. Core Runtime Dependencies

The DOM host design is sound only if it sits on the right core pipeline. A
review of current Fleury core found that the semantic subsystem is not yet built
for the web differentiator, while frame damage and scheduling already exist in
native and should be reused rather than re-derived. These are architecture
dependencies for a production-quality web host.

### R1: Retained, geometry-bearing semantics

Current state:

- `SemanticTree.fromElement` rebuilds semantics from an element walk on demand;
- production frames do not emit a semantic tree;
- `SemanticNode` has no `CellRect` / painted geometry;
- stable IDs are opt-in, with an element-hash fallback;
- text input caret geometry is computed during paint and discarded.

The web host's hardest open problems all need the same core capability:

- IME caret geometry;
- stable semantic IDs for incremental ARIA;
- focus/AT coherence;
- semantic updates synchronized with visual commits;
- cell-to-node mapping for selection/copy/inspection.

Dependency: implement the companion
`docs/rfcs/semantics-pipeline.md` proposal: a retained semantics owner with
stable identity, painted geometry, caret geometry, and node diffs produced as a
first-class frame output.

Web policy: semantics should be enabled by default for web hosts because
structured accessibility is a product differentiator. The cost must be
incremental and included in the browser performance gates. Native hosts can keep
semantics AT-gated or debug-gated.

Important caveat: "stable identity by default" does not solve unkeyed dynamic
list identity by magic. The semantics RFC must preserve explicit app keys as
the durable identity mechanism for reorderable or virtualized collections.

### R2: Reuse paint damage; add row granularity

Native currently avoids repainting clean `RenderRepaintBoundary` subtrees, but
it does not ship a paint-damage handoff into `AnsiRenderer`. A buffer-level
dirty-region probe was measured and reverted because it added local SB.6
overhead without materially improving the peer-facing catch-up axes.

Current damage is a single union `CellRect`. That is conservative but can be too
wide for DOM rows: changes on rows 1 and 50 become rows 1-50. Add per-row or
row-range damage so DOM can update exactly the affected rows and ANSI can also
tighten its dirty bounds.

Conservative layout damage still matters. Any future dirty-region handoff must
fall back to a full diff after layout-affecting changes; layout-animating apps
become the real worst case for the benchmark gate.

### R3: Extract shared `TuiRuntime` / `FrameLoop`

`run_tui_web.dart` is an older fork of native `run_tui.dart` orchestration and
has already drifted: it lacks the native `FrameScheduler`
coalescing. A production `WebTuiHost` should not become a third copy.

Dependency: extract a platform-agnostic runtime loop that owns:

- root mount/update;
- scope stack;
- input dispatch;
- front/back buffer lifecycle;
- frame scheduling;
- damage handoff;
- buffer swap;
- post-frame callback timing;
- debug hooks that are host-neutral.

Native and web then inject platform specifics:

- terminal ANSI sink vs browser `FrameSurface`;
- driver event source;
- flush scheduler (`scheduleMicrotask`/timer vs rAF);
- host capabilities;
- host-specific debug layers.

This keeps web aligned with native correctness as core evolves.

### R4: Preserve DOM truecolor fidelity

`CellBuffer` stores full-fidelity colors. ANSI quantization happens only inside
`AnsiRenderer` at encode time. The DOM surface bypasses ANSI and should render
`CellStyle.foreground` / `background` through `toRgb()` directly, with no
terminal color-mode quantization.

`WebSurfaceCapabilities` should advertise truecolor for the DOM path. Palette
classes are still useful for style caching, but they should be generated from
the web theme/style resolver, not from terminal downsampling.

### R5: Shared event semantics tests

Native input is bytes -> `InputParser` -> `TuiEvent`. Web input is DOM events ->
browser key map -> `TuiEvent`. These are two producers of the same framework
events and can drift.

Add shared golden tests at the `TuiEvent` level:

- navigation keys;
- printable text;
- modifiers and chords;
- repeat;
- paste;
- platform Meta/Ctrl/Alt behavior where the browser exposes it.

The web key map does not need to mimic terminal byte sequences, but it must
preserve Fleury event semantics.

## 20. Module Layout

Proposed package layout:

```text
packages/fleury/lib/src/runtime/
  tui_runtime.dart              # shared frame loop extracted from run_tui*
  frame_scheduler.dart          # reused with browser rAF flush strategy

packages/fleury/lib/src/rendering/
  frame_damage.dart             # per-row / row-range paint damage model

packages/fleury/lib/src/semantics/
  semantics_owner.dart          # retained geometry-bearing semantics pipeline
  semantic_diff.dart            # incremental node changes for presenters

packages/fleury_web/lib/src/host/
  web_tui_host.dart
  browser_frame_scheduler.dart  # rAF flush adapter over shared scheduler
  web_host_instrumentation.dart
  web_focus_coordinator.dart

packages/fleury_web/lib/src/presenter/
  frame_surface.dart
  frame_presentation_plan.dart
  dom_grid_surface.dart
  xterm_ansi_surface.dart        # temporary parity/legacy surface
  webgl_grid_surface.dart        # only if perf gate fails
  web_surface_capabilities.dart

packages/fleury_web/lib/src/dom_grid/
  cell_span_builder.dart         # pure CellBuffer -> RowSpanModel
  cell_grid_html.dart            # artifact/string adapter over span model
  dom_row_factory.dart           # RowSpanModel -> DOM nodes
  style_resolver.dart
  width_cache.dart

packages/fleury_web/lib/src/input/
  dom_input_source.dart
  browser_key_map.dart
  composition_controller.dart
  pointer_mapper.dart

packages/fleury_web/lib/src/metrics/
  cell_metrics.dart
  font_metrics.dart

packages/fleury_web/lib/src/semantics/
  semantic_dom_presenter.dart
  semantic_dom_model.dart

packages/fleury_web/lib/src/clipboard/
  web_clipboard.dart
```

Keep these private until the host proves stable. Export only the public
`runTuiWeb` entry point unless another package needs lower-level integration.
Core runtime/semantics files are listed as architectural targets; exact names
can change during the companion implementation RFCs.

## 21. Rollout Plan

### Phase 0: Spike

Status: done.

Current deliverables:

- pure `CellBuffer -> HTML` translation;
- fidelity tests;
- spike gallery artifact.

Spec follow-up:

- refactor the spike string renderer to consume `CellSpanBuilder` once the span
  model lands.

### Phase 1: Shared Runtime and Damage Handoff

Deliverables:

- shared `TuiRuntime` / `FrameLoop` extraction or a narrow intermediate adapter
  that guarantees the same contracts;
- browser rAF flush strategy wired through the shared `FrameScheduler` logic;
- web path consumes measured dirty-region hints and conservative full-diff flags;
- first per-row / row-range damage representation, or a documented adapter from
  current union bounds.

Exit gate:

- native and web share frame scheduling, buffer swap, damage handoff, and
  post-frame callback semantics;
- web no longer depends on the older microtask-only loop behavior.

### Phase 2: Host Skeleton and Visual DOM

Deliverables:

- `WebTuiHost`;
- `FrameSurface`;
- `FramePresentationPlan`;
- `CellSpanBuilder`;
- retained `DomGridSurface`;
- `CellMetrics`;
- minimal `SemanticDomPresenter` root;
- instrumentation counters.

Exit gate:

- a real Fleury app renders through DOM;
- visual DOM writes happen under rAF;
- frame phases preserve read/write separation;
- dirty rows use shared span model and `replaceChildren`;
- no xterm dependency for visual presentation of Fleury-owned app frames.

### Phase 3: Input, Resize, Clipboard, IME

Deliverables:

- `DomInputSource`;
- `BrowserKeyMap`;
- `CompositionController`;
- `PointerMapper`;
- `WebClipboard`;
- textarea/caret positioning hook;
- event trace tests.

Exit gate:

- real Fleury app is usable without xterm for render or input;
- paste, pointer, resize, and core keyboard paths work;
- IME composition path works in at least the primary supported browser;
- browser clipboard failure modes are visible and fallback behavior works.

### Phase 4: Retained Semantics, Focus, and Accessibility

Deliverables:

- retained semantics owner from the companion RFC;
- geometry-bearing semantic nodes;
- caret geometry from focused text input;
- `WebFocusCoordinator`;
- focused/actionable semantic nodes;
- semantic activation -> Fleury action/focus dispatch;
- link projection from semantic data;
- accessibility smoke tests.

Exit gate:

- visual grid remains hidden from assistive technology;
- semantic DOM exposes current focused app state;
- keyboard focus and semantic activation do not fight the hidden textarea;
- IME candidate-window placement consumes real caret geometry;
- manual screen-reader smoke passes for the supported v1 browser set.

### Phase 5: Benchmark Gate

Deliverables:

- browser benchmark harness;
- scoreboard integration;
- p50/p95 timing tables;
- DOM node/heap counters;
- stress scenarios.

Exit gate:

- DOM plus active semantic presenter passes the agreed frame budget; or
- the miss is clearly attributed to visual DOM mutation/layout, and
  `WebGlGridSurface` is approved as the fallback implementation.

### Phase 6: Harden and Retire Temporary Paths

Deliverables:

- make DOM the default for Fleury-owned web apps;
- remove `XtermAnsiSurface` once it stops catching unique regressions;
- keep xterm for arbitrary ANSI transport and `fleury serve`;
- document browser support and known limitations.

## 22. Review Checklist

Before implementation starts, reviewers should be able to answer:

- Is `WebTuiHost` the right ownership boundary?
- Should `FramePresentationPlan` compute dirty rows once, or should surfaces
  diff independently?
- Is the span model sufficient for protocol placeholders, selection, cursor,
  and future links?
- Is rAF scheduling compatible with Fleury's existing `FrameScheduler` and
  post-frame callback contract?
- Is the metrics/correction policy precise enough to avoid both drift and
  unnecessary DOM nodes?
- Is the hidden textarea/focus model plausible for screen readers and IME?
- Are the benchmark gates realistic for Fleury's intended web apps?
- Which browser set is v1 required to support?
- Is the shared runtime extraction sequenced before enough web work to prevent
  another divergent loop?
- Does the semantics companion RFC provide the geometry and identity guarantees
  needed by IME, focus, and ARIA?

## 23. Open Questions

- What public caret-geometry hook should focused text input expose for IME?
- Which semantic model should `SemanticDomPresenter` consume long term:
  current `AccessibilitySnapshot`, a richer semantic tree, or both?
- What are the canonical Fleury benchmark fixtures for the benchmark gate?
- What web capability should represent inline images/protocol cells, if any?
- Which browsers are required for v1 validation beyond Chromium?
- Should row-shift detection recycle/translate row nodes for scroll-like churn,
  or wait until perf data proves it necessary?
- Should a selection overlay be added early for contrast/selection efficiency,
  or should selection remain purely buffer-painted for v1?

## 24. References

- xterm.js DOM renderer:
  `https://raw.githubusercontent.com/xtermjs/xterm.js/master/src/browser/renderer/dom/DomRenderer.ts`
- xterm.js DOM row factory:
  `https://raw.githubusercontent.com/xtermjs/xterm.js/master/src/browser/renderer/dom/DomRendererRowFactory.ts`
- xterm.js width cache:
  `https://raw.githubusercontent.com/xtermjs/xterm.js/master/src/browser/renderer/dom/WidthCache.ts`
- xterm.js screen-reader design:
  `https://raw.githubusercontent.com/wiki/xtermjs/xterm.js/Design-Document:-Screen-Reader-Mode.md`
- xterm.js composition helper:
  `https://raw.githubusercontent.com/xtermjs/xterm.js/master/src/browser/input/CompositionHelper.ts`
- VS Code terminal renderer performance:
  `https://code.visualstudio.com/blogs/2017/10/03/terminal-renderer`
- Ratzilla backend notes:
  `https://docs.rs/ratzilla/latest/ratzilla/backend/index.html`
- Dart `package:web` migration:
  `https://dart.dev/interop/js-interop/package-web`
- MDN Clipboard API:
  `https://developer.mozilla.org/en-US/docs/Web/API/Clipboard/writeText`
- MDN ResizeObserver:
  `https://developer.mozilla.org/en-US/docs/Web/API/ResizeObserver`
- WAI-ARIA hiding semantics:
  `https://www.w3.org/WAI/ARIA/apg/practices/hiding-semantics/`
