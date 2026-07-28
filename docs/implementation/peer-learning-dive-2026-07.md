# Peer Learning Dive — Candidate Backlog (2026-07)

**Status:** Reference / candidate backlog — not scheduled work.
**Date:** 2026-07-22
**Provenance:** Source-level architecture study of five peers (nocterm, Ink,
Textual, Ratatui, OpenTUI) — reading real source + docs to extract *techniques
and design approaches* Fleury should adopt, adapt, push further, or deliberately
reject. Complements [`peer-scorecards.md`](peer-scorecards.md) (which tracks
versions + scenario **benchmarks**); this doc tracks **techniques**.

## How to read this

Fleury already has a deep strategy — the "Seven Engines," twelve workstreams,
and per-peer *ecosystem lessons* in
[`leading-reactive-tui-roadmap.md`](../leading-reactive-tui-roadmap.md), plus
RFCs and §26 open decisions. So this backlog is written as a **delta**: each
item is cross-referenced to the existing roadmap/RFC/§26 item it sharpens, and
tagged honestly.

**Honesty note:** much of what a fresh peer read surfaces, Fleury has already
considered. The dive's real value is (a) the *implementation mechanism* behind a
roadmap line ("learn from Textual's CSS" → the actual algorithm), (b) evidence
for the §26 open decisions, (c) **convergence** signal (when ≥2 independent
peers land on the same idea), and (d) the *push-further* angle where Fleury's
semantics + multi-surface + oracle engine turns a borrowed idea into a
differentiated one. Where an item is already an RFC or a deliberate deferral,
this doc says so rather than re-selling it as new.

Delta tags: **NEW** (not in roadmap) · **PLANNED** (roadmap/RFC wants it; dive
adds mechanism) · **PARTIAL** (Fleury has a version; dive adds an extension) ·
**REJECT** (not for Fleury; lesson banked).

---

## P1 — highest leverage

### 1. Scrollback / inline mode — commit finished output out of the live diff
**Peers:** Ink `<Static>`, OpenTUI split-scrollback (both organize their *entire*
design around it). **Tag: PLANNED (deferred) — this is [RFC 0016](../rfcs/0016-inline-mode.md).**

**What it is.** Two shapes of terminal app: *alt-screen* (Fleury today — own the
whole screen, nothing persists) vs *inline* (render at the prompt in the normal
buffer; finished content flows up into the terminal's real scrollback —
selectable, copyable, survives exit — with a live region pinned below). The
enabling mechanic is **insert-above / static interleaving**: permanent lines are
committed above a pinned live region and *evicted from the per-frame layout+diff*
(Ink `<Static>`, Ratatui `Terminal::insert_before`). This is the Claude-Code /
Codex-CLI transcript shape.

**Honest status.** RFC 0016 already explored this (2026-07-05), documented the
mechanism, sketched the design (~2–3 weeks), weighed the *full* peer landscape
(it knew inline is "unanimous at the top of the field"), and **deliberately
deferred** it with decision triggers. The dive does **not** discover a gap — it
*corroborates* RFC 0016 and maps to its **trigger #2** ("launch marketing targets
the Ink/agent-CLI audience"), which is live given the positioning work this month.

**The counter-case (from RFC 0016 §4, still stands).** Fleury's full-screen
app-owned transcript (`packages/samples/lib/src/agent_tui.dart`, the "Crush"
shape) does things inline **structurally cannot**: mutable history
(collapse/expand/re-render finished blocks), perfect resize re-wrap, in-place
search/filter, no viewport-height ceiling, sidebars/panels. Inline's
committed-to-scrollback content is *frozen* and mangles on resize. Inline is
**market coverage**, not a correction.

**Push-further (what the RFC's sketch under-weights).** Both peers commit *dumb
bytes/pixels*. Fleury can commit a finished row across **all surfaces at once and
keep it semantically live**: bytes → terminal scrollback; the row's **semantics
node** → accessible DOM / MCP transcript (an agent/AT can still query finished
turns that have left the live diff); web/served → a real scrollable DOM list +
sticky composer (no scrollback constraint). And an **oracle** can assert the
invariant Ink only hopes for — "a committed row is byte-identical in scrollback
to what it last rendered live, never repainted" (Ink's fragile
`previousStaticNode` bookkeeping exists precisely because replay is a known
failure mode).

**Synergy.** RFC 0016 §6 notes the terminal IME-caret fix (P2 #7) shares the
"presenter owns post-frame cursor state" plumbing — land the caret first; it lays
inline's foundation.

**Cheap adjacent win (do regardless — RFC 0016 §7).** Exit-persistence for
alt-screen apps: print the final frame / transcript tail into the normal buffer
after the alt-screen pops. ~1 day, no inline machinery, closes the single biggest
practical loss of full-screen agent CLIs.

**Cost:** deep (~2–3 weeks for real inline; ~1 day for exit-persistence).
**Where:** presenter/driver layer (`AnsiRenderer` relative addressing, an
`InlineFramePresenter`, a `printAbove`/static sink); transcript widgets
(`terminal_output_region.dart`, `message_list.dart`).
**Decision for Dan:** has RFC 0016 trigger #2 fired? If not, do the exit-
persistence win now and keep inline deferred.

### 2. Theming system — derived tokens + named palettes + component recipes
**Peers:** Textual (algorithmic derivation — the crown jewel), nocterm (named
palettes), Ink `@inkjs/ui` + Textual (component-part recipes). **Tag: PLANNED
(Workstream I / §26) — dive adds the mechanism.** Four peers converge.

**What it is.** Textual's `ColorSystem.generate()` (`design.py`) turns ~12 base
colors + flags into *hundreds* of tokens by color math: shade ramps
(`-lighten/darken-1..3`), **contrast-aware `text-*`** (auto black/white on any
bg), muted blends, and per-component tokens (scrollbar / cursor / footer /
markdown-h1..6). 14 themes ship as *just color dicts*. nocterm ships recognizable
palettes (nord/dracula/catppuccin/gruvbox) as `const`s. Ink/Textual let a widget
declare named internal **parts** (`COMPONENT_CLASSES = {"bar--complete"}`) that a
theme restyles without the widget exposing child widgets.

**Fleury delta (corrected 2026-07-22).** Fleury's role system is arguably
*better designed* than the peers' — a deliberately lean 9-role `ColorScheme`,
nullable = terminal-default (transparency), and **NO_COLOR attribute-pairing**
(cues survive when color is stripped; no peer's theming does this). It also
**already has component-part theming**: `FleuryWidgetTheme`
(`fleury_widgets/.../component_theme.dart`) is a ~35-slot extension
(data/progress/code/diff/markdown/log/switch parts). So the genuine gaps are
narrower than a fresh read suggests: **named palettes** (ships dark/light only),
**contrast-aware derivation** (a custom `surface` needs a hand-picked legible
`foreground` today; nothing derives it), and parts are flat `CellStyle` constants
rather than prop/variant-conditional. Derivation is pure computation → fits the
two-surface model (same tokens feed terminal cells and the web DOM/ARIA).
**Tension to respect:** Textual's *hundreds* of tokens fights Fleury's stated
"deliberately lean" stance — so **derive internally from a lean ~9–12 base**,
don't expose Material-sized sprawl to authors. The sharp high-value slice is
*named palettes + contrast-aware derivation (+ a WCAG contrast oracle)*, not a
wholesale cascade rebuild. Resolves §26 "CellStyle vs component-theme
expressiveness" → **both**.

**Push-further.** Emit tokens as **typed Dart** (`ThemeTokens`, dart2js
tree-shakes unused). A **WCAG contrast oracle** in CI asserts `text-*` legibility
— impossible for any peer (needs the a11y tree). Expose the active token set
through **semantics** so an MCP agent can read/drive `$accent`.

**Cost:** medium (generator is quick; token catalog + palette pack + component
registry is the medium part). **Where:** `packages/fleury/lib/src/.../theme.dart`
+ a `color_system.dart`; tokens consumed by `rendering/` paint and the serve/web
DOM emitters.

### 3. `fleury_riverpod` — first-party reactive state as a thin binding
**Peer:** nocterm `nocterm_riverpod`. **Tag: NEW / answers §26** ("first-party
state package vs `Inherited`+adapters").

**What it is.** ~530 lines total: `export 'package:riverpod'` + a `ProviderScope`
(`UncontrolledProviderScope extends InheritedComponent`) + a `context.watch/read/
listen` extension + a `ProviderDependencies` subscription tracker wired into the
element lifecycle (reuse still-watched subs on rebuild, auto-close dropped ones,
close all on unmount) — reproducing Flutter-Riverpod's auto-dispose on the
`InheritedElement` machinery Fleury already has.

**Fleury delta.** Fleury ships only `ChangeNotifier`/`Listenable`. Riverpod's core
is UI-agnostic, so the binding transfers almost verbatim. Answers the §26 open
decision with a concrete recipe: **do the thin binding, don't reimplement.**

**Push-further.** Expose the `ProviderContainer` as an **MCP debug/agent surface**
(enumerate providers/values/dependency-edges; drive `invalidate`/`refresh` as
SemanticActions) — a riverpod-devtools-over-MCP no TUI framework has. Factor the
subscription tracker into a reusable `ElementSubscriptionTracker` seam so
signals/beacon bind through the same helper.

**Cost:** quick-win. **Where:** new `packages/fleury_riverpod`; a small
`ElementSubscriptionTracker` in `framework.dart`.

### 4. `containsTextOnce` — exactly-once test oracle
**Peer:** nocterm `ContainsTextOnce`. **Tag: NEW / quick-win — targets a known
bug** ([[fleury-scroll-garble-diff-bug]] class).

**What it is.** A matcher asserting text appears **exactly once**, built to catch
"stale content painted at an old offset alongside fresh content at the new one";
its mismatch dumps every occurrence's coordinates + the full render.

**Fleury delta.** `fleury_test` has `matchesGolden` but no exactly-once
assertion. ~20 lines turns the whole scroll-garble regression class into a
one-line guard.

**Push-further.** Assert exactly-once at the **semantics** layer too (one node
with label X — catches duplicate-emit a cell scan misses), and promote "no
text/semantic node appears at two positions unless intended" to a standing
**oracle invariant** run across the corpus, not only where a human remembered.

**Cost:** quick-win. **Where:** `packages/fleury_test/lib/src/` + an oracle
invariant.

---

## P2 — high value, feeds work already on the books

### 5. Unify command/keymap registry with SemanticActions
**Peers:** OpenTUI `@opentui/keymap`, Textual `@on` + command-palette Provider.
**Tag: PLANNED — [RFC 0018](../rfcs) keybinding redesign.**

OpenTUI's keymap is a host-agnostic engine: priority focus-scoped layers,
branch-aware multi-key sequences, a Neovim-style exact-vs-prefix timeout
resolver, and **lint-style diagnostics** (dead / shadowed / reachable bindings).
Textual's `@on(Message, "#selector")` routes events filtered by selector on the
source widget; its command palette is an open `Provider` surface (theme-switching
*is* a provider). **The unifier (the real prize):** source the command palette,
the **MCP agent tool list**, and meaning-based tests from *one* `SemanticActions`
registry. Feeds RFC 0018; the diagnostics graph and timeout resolver are worth
copying wholesale. **Cost:** medium. **Where:** `lib/src/input/keymap/` + the MCP
action registry.

### 6. Pixel→cell quadrant reducer (fills the 3D/graphics gap)
**Peer:** OpenTUI `drawSuperSampleBuffer` (`buffer.zig`). **Tag: NEW / fills a
stated gap.**

Sample a 2×2 pixel block per cell → pick 2 colors + the quadrant glyph
(`▄▀▘▝▖▗▚▞█`) best matching light/dark sub-pixels = **2× resolution using only
Unicode + 24-bit color**. It is *pure arithmetic* — no GPU, no native code — so it
fits pure-Dart and runs identically on **both** surfaces (OpenTUI's 3D is
server-only). Feed a software-rasterized / charting / three-dart pixel grid → a
`RawImage`/`Canvas3D` widget. **Push-further:** the reduced chart carries a
**semantic label** ("bar chart, Q4 highest") agents/AT can read; gate under
paint/alloc gates. **Cost:** medium. **Where:** `lib/src/rendering/pixel_to_cell.dart`.

### 7. IME caret via a per-frame active-cursor
**Peer:** Ink `useCursor`. **Tag: PARTIAL — targets a flagged gap**
([[fleury-expert-assessment]] #1; also RFC 0016 §6 foundation).

A per-frame "active cursor" the focused editable sets, emitted as a real
cursor-move *after* the CellBuffer flush, dirty-tracked ("only emit if set since
last render") to avoid ghost carets. **Push-further:** drive it from the focused
editable's **semantics** (caret offset/bounds it already knows) → one source
feeds terminal cursor + web contenteditable + accessible DOM. **Land this before
inline (#1)** — shared presenter/cursor plumbing. **Cost:** quick–medium.
**Where:** input/IME + frame presenter.

### 8. Out-of-process semantic devtools console
**Peers:** Textual `textual console`, nocterm socket/logs, Ink (React-DevTools
envy). **Tag: PLANNED — [`devtools-plan.md`](devtools-plan.md).**

A second terminal / browser panel over a socket streaming logs + **events /
messages / worker activity** in filterable verbosity groups (a TUI owns stdout;
`package:stdio` fd-capture is the plumbing). **Push-further (the differentiator):**
don't tail logs — stream the **live semantics tree + reconciliation/damage/frame-
timing** over the *same serve binary channel* → a Flutter-DevTools-class inspector
(tree views + damage overlay via semantic `bounds`) that doubles as an **agent-
trace viewer** (semantics = the MCP surface). **Cost:** medium. **Where:** a
`fleury console` subcommand + a debug channel in `lib/src/remote/`.

---

## P3 — cheap wins, grab opportunistically

- **Post-paint cell-effects layer** (Ratatui `tachyonfx`, OpenTUI `post/`) —
  declarative timed effects (fade/dissolve/sweep) over the `CellBuffer`.
  Push-further: **suppress for the semantics tree** so agents/AT see stable
  content while humans see animation; applies to both surfaces. **NEW.**
- **`Style`-as-patch with add/sub modifiers** (Ratatui) — a nested style can
  *remove* an inherited bold, not just last-writer-wins. Verify Fleury's current
  merge. **PARTIAL/quick-win.**
- **`live` animation refcount** (OpenTUI) — run the continuous frame loop *only*
  when a `live` node exists; else pure event-driven (zero idle CPU). Cleaner than
  always-on tickers. **NEW/quick-win.**
- **Colors-carry-intent** (OpenTUI) — thread rgb / indexed / **terminal-default**
  intent through the cell color; `default` emits `\x1b[39m/49m` (honors the user's
  theme) and maps to CSS `currentColor` on web. **PARTIAL/quick-win.**
- **`reactive()` refresh-flags + `data_bind`** (Textual) — a field that encodes
  its own repaint/layout/recompose consequence; `data_bind(Parent.x)` one-way
  flow; `toggle_class` state→style. Push-further: refresh flags drive the
  damage/alloc gates → reactivity provably minimal. **NEW-ergonomics.**
- **Benchmark sticky-PR-comment** (nocterm) — green/red delta table on every PR
  across gated + non-gated benches (Fleury *enforces* gates; steal only the
  visibility). Push-further: put **oracle deltas** (cells / semantic nodes changed
  vs main) in the same comment. **PARTIAL/quick-win.**
- **`fleury_lints` custom_lint assists** (nocterm) — wrap-with, convert
  stateful↔stateless, and a lint others can't: **flag interactive widgets missing
  a `semanticLabel`/role**; warn on raw `AnsiColor` where a role exists. **NEW/deep.**
- **Generalized `suspendTerminal`** (Ink) — Fleury has editor-specific handoff;
  generalize to wrap *any* child process (git/fzf/less/build) with the exhaustive
  mode-restore checklist + a scoped/disposable API. **PARTIAL.**
- **`aria-*` author spelling + semantics linearization** (Ink) — adopt web-
  identical `aria-role`/`aria-state` sugar (familiar to web devs *and* LLMs) +
  ship a plain-text fold of the semantics tree (`--screen-reader` + agent-readable
  snapshot). Push-further: Fleury's tree has **actions**, so the text surface is
  *interactive* and diffable — Ink's is lossy/one-way. **PARTIAL.**
- **Constraint-solver layout vocabulary** (Ratatui) — adopt the
  `Constraint::{Min,Max,Length,Percentage,Ratio,Fill}` *vocabulary* over a simple
  allocator (~80% of Cassowary's expressiveness cheaply) as a `ConstraintRow`
  alongside flex. **NEW.**

---

## Convergences (highest-confidence — ≥2 independent peers)

1. Commit finished output to real scrollback (P1 #1) — Ink + OpenTUI.
2. A real theming system (P1 #2) — Textual + nocterm + Ink.
3. One command registry → palette + MCP + tests (P2 #5) — OpenTUI + Textual.
4. Safely expose the cell buffer for custom paint / pixel→cell / effects — Ratatui
   + OpenTUI + Ink.
5. Out-of-process inspector fed by the tree (P2 #8) — Textual + nocterm + Ink.
6. No heavyweight plugin API; stabilize a widget-authoring seam + curated
   discovery — Ratatui + Ink (validates the roadmap non-goal).
7. **Route every borrowed feature through semantics** — the universal push-further
   no peer can follow (none has a semantics tree).

## Validations (peers confirm Fleury's bets — no action)

- **Web architecture:** nocterm + OpenTUI + Ink all lack an accessible-DOM web path
  (ANSI→xterm or nothing) → Fleury's client-side DOM + semantic DOM is a generation
  ahead (three independent confirmations).
- **Meaning-based tests:** Ink + OpenTUI are stuck on brittle char-frame snapshots →
  Fleury's semantic assertions win.
- **Perf:** nocterm reports; Fleury enforces (merge-blocking gates).
- **Native core:** OpenTUI validates pure-Dart (native ⇒ no WASM ⇒ no browser ⇒
  no a11y).
- **Ticker/animation, cell-diff granularity, focus, DEC 2026 sync:** already
  present and at-or-ahead of Ink.

## §26 open decisions this dive answers

- *First-party state package vs Inherited+adapters?* → **thin binding** (P1 #3).
- *CellStyle vs component-theme expressiveness?* → **both** (P1 #2).
- *Render islands public API?* → **yes**, via a stable widget-authoring seam
  (Ratatui) + the `Canvas` escape hatch — how third-party ecosystems form.
