# The Fleury Architecture Story

**Status:** Internal architecture narrative (graduates to public docs at API
freeze)
**Last evidence refresh:** 2026-06-11 (perf/arch campaign close)

This is the canonical account of fleury's architecture: the world it was
built for, the shape of the system, how it got that shape, what it took
from and learned against its peers, and the measured evidence behind every
claim. Companion docs: [why-fleury](implementation/why-fleury.md)
(positioning), [peer-scorecards](implementation/peer-scorecards.md)
(standings + claims language),
[core-api-dx-audit-readiness](implementation/core-api-dx-audit-readiness.md)
(what comes next), and the
[execution log](implementation/web-rfc-execution-log.md) (the full
measurement trail).

## The state of the world (2026)

Terminals stopped being a niche render target. The dominant new TUI
workloads are agent consoles, dev-tool dashboards, and LLM-output surfaces
— applications, not utilities. That changes the architectural requirements
in four specific ways:

1. **Incrementality is mandatory.** App-scale screens update continuously;
   work must be proportional to what changed, not to screen size.
2. **Machines are users.** Agents drive terminal UIs now. A UI that can
   only be screen-scraped from ANSI bytes is opaque to its fastest-growing
   user base. The UI needs a queryable, actionable semantic structure.
3. **Untrusted output is the default.** The common case is rendering
   subprocess and LLM output. Escape-sequence injection, clipboard/link
   policy, and redaction are framework concerns, not app afterthoughts.
4. **The terminal is one surface.** The same app increasingly needs to
   render into a browser (dashboards, remote sessions, docs) without a
   second implementation.

The peer landscape solves for older constraints. Ratatui (Rust) is
immediate-mode: rebuild the whole view every frame, diff double buffers —
minimal, fast floors, everything else app-owned. Bubble Tea v2 (Go) is the
Elm architecture: one model, one update function, one view-to-string —
unbeatable simplicity, whole-view rebuilds, no structure behind the
string. Textual (Python) is the mature app framework: widget DOM, CSS,
compositor, workers — the breadth bar, on an interpreter floor, with
queries but no semantics contract. Ink (React/Node) is React reconciled to
line-based stdout — familiarity for scrollback CLIs, weak full-screen.
OpenTUI (Zig core, TypeScript bindings) bets on a native buffer behind a
bridge. Nocterm (Dart) offers Flutter-style surface syntax without the
machinery underneath. None of the six has a semantics tree; none has a
capability/sanitization contract; none renders a second surface from the
same pipeline.

## The architecture

Fleury is a retained-mode, multi-tree reactive UI framework compiled to a
single Dart AOT binary, rendering to terminals (ANSI bytes) and browsers
(retained DOM) from one pipeline.

Four trees, each with a distinct job:

- **Widget tree** — immutable configuration. Throwaway value objects, so
  equality means "nothing changed": `const` subtrees, configuration
  -equivalence pruning, and whole-frame skips fall out of this layer.
- **Element tree** — identity and state. The durable spine that survives
  rebuilds. State lives here without app-authored plumbing; reconciliation
  decides the minimal dirty path. This is the layer peers' benchmark
  fixtures hand-implement (selection, undo, focus state as app code).
- **Render tree** — layout and paint over a cell grid. Persistent identity
  is what change-tracking hangs on: the frame damage tracker attaches at
  its root, `RepaintBoundary` isolates cache painted cells, scroll
  detection turns row movement into buffer moves.
- **Semantics tree** — derived, incrementally updated, machine-readable
  structure: roles, state, actions. Flushed off the visual frame
  (deferred, coalesced, force-flushed before semantic actions) so it costs
  the frame budget nothing. This is the agent/testing surface.

The frame pipeline: state change → rebuild dirty subtree → layout → paint
into a cell buffer (damage-tracked to the row) → backend. The native
backend diffs cell buffers and emits byte-accounted ANSI (C0 cursor moves,
gap write-through with SGR deltas measured against the cursor-move cost,
synchronized-output wrapping skipped under 48 bytes, scroll reuse as
`SU`). The web backend applies the same damage to retained DOM rows (span
rebuild, row moves for scrolls) with a semantic DOM presenter beside it.
Both backends sit behind one host SPI; a divergence oracle asserts the two
surfaces render the same tree.

Around the pipeline: an app kernel (typed command registry, focus, status,
palette), a capability/security contract (terminal capability detection
with policy-gated degradation; sanitize-by-default for untrusted output;
clipboard/link/image policies; redaction hooks), an effects/task layer
(controllers, cooperative long-work with progress/cancel), and a testing
story that queries semantics rather than scraping bytes.

The architecture maintains itself with verification machinery, not hope:
a 300-frame byte-equivalence oracle (diff output reproduces full repaint),
the semantic divergence oracle (retained semantics match a from-scratch
build), a web readiness gate with promoted thresholds, and a wire byte
gate against a committed baseline. Incremental layers that can drift get
oracles; perf that can regress gets gates.

## How it got this shape

**Origin: Flutter's three trees, taken seriously.** The starting decision
was to adopt the widget/element/render split — not Flutter's surface
syntax, the actual machinery. Cells replaced pixels; constraints-down,
sizes-up layout stayed; repaint boundaries stayed; the semantics tree
pattern stayed and was promoted from accessibility feature to primary
differentiator. Divergences from Flutter's API were treated as bugs
unless deliberate (the 2026-06 DX audits closed the accidental ones).

**Terminal-native adaptations.** Byte budgets replaced GPU budgets: the
renderer accounts for every escape byte, and the benchmark suite
classifies emitted bytes (content/SGR/cursor/sync/session) so encoding
overhead is a measured axis. Capability variance (terminals differ in
everything) became a typed contract with degradation policy instead of
feature-detection folklore. Untrusted output became a default-on
sanitization layer because the modern workload demanded it.

**The 2026-06 perf/arch campaign** (full trail in the execution log)
hardened the bones: frame state de-globalized to per-runtime trackers;
semantics moved off the visual frame; frame skip for no-work frames;
scroll reuse shared between backends; banded row damage; the
byte-accounted styled-gap encoder; a web backend taken from
seconds-per-frame to sub-budget; and a closing pass that measured every
floor (boot, RSS, retained heap, allocation churn) rather than asserting
it. One environmental discovery mattered as much as any code: the
original toolchain ran under Rosetta, and every pre-campaign benchmark
was emulated. All standing evidence is native-stack, 3-run medians.

## Influences and lessons from peers

- **Flutter** — the architecture itself: three trees, repaint boundaries,
  semantics layering, deferred accessibility flush. The lesson taken was
  structural, and the proof it transferred is below.
- **Ratatui** — the adversarial benchmark. Immediate mode is the null
  hypothesis ("retained trees are overhead"); beating it on wire
  efficiency is what makes the retained claim defensible. Its runtime
  floors (2 MiB, instant boot) remain the honest ceiling Dart cannot
  reach; fleury documents the floor instead of chasing it.
- **Bubble Tea / Elm** — the simplicity benchmark. TEA's near-zero
  per-frame protocol constants exposed fleury's bookkeeping floor on
  near-empty frames and directly motivated the small-diff sync skip. The
  counter-lesson runs the other way: TEA's whole-view rebuild is why its
  10k-character textarea moves the cursor in 718 ms where fleury's takes
  0.8 ms. Simplicity and incrementality trade; fleury chose incrementality
  and minimized the tax.
- **Textual** — the maturity bar and one genuine import: its DataTable
  virtualization beat fleury's TreeTable *fixture*, which became the
  lazy-provider API lesson now recorded for the core audit (and the
  search-index diet already landed from it).
- **Ink/React** — confirmation that reconciliation-to-lines serves
  scrollback CLIs, not dense full-screen apps; no architectural import.
- **OpenTUI** — a negative result worth keeping: a native core behind a
  language bridge showed no wire advantage in any shared scenario. The
  whole pipeline is the unit of performance, which validates fleury's
  single-runtime choice.
- **Nocterm** — the controlled experiment. Same language, same runtime
  floors, Flutter-style API without damage tracking, paint isolation, or
  semantics: 8–30x slower on app-shaped operations. The machinery, not
  the syntax, is the architecture.

## The evidence (important callouts)

All native-stack, 3-run medians. Wire standings:
`profiling/caps/2026-06-11-final` (+ `2026-06-11-sb11-postdiet2` for the
TreeTable re-run); web: `profiling/web/baselines/2026-06-10-arm-native`.

| Callout | Result | Why it matters architecturally |
| --- | --- | --- |
| Wire standings vs 6 peers, 12 scenarios | 8 push-leading, 2 parity, 2 catch-up (both causally explained) | Leads bytes/frame/FPS against every peer including Rust and Zig |
| Retained vs immediate mode (vs ratatui) | Leads bytes, bytes/frame, FPS on SB.3/6/7/12 | The damage tracker out-emits rebuild-everything-and-diff |
| App-shaped latency (SB.2 editing) | cursor-move p95 0.8 ms vs Bubble Tea 718 ms | The element tree: state survives, only the dirty path rebuilds |
| Same-runtime control (vs nocterm) | 8–30x faster on counter/editor/table/log ops | Isolates machinery from language: same Dart floors, no damage spine |
| Web backend frame cost | Worst scenario 8.5 ms p95 at 300x100; 0% over 60fps budget on all 11 scenarios (inherited: up to 2.7 s) | One damage spine drives a second surface to sub-budget |
| Browser-inclusive end-to-end | ≤ 11.5 ms (CDP-traced, real frame pipeline) | No peer publishes browser-inclusive numbers at all |
| Update granularity, measured at the heap | ~85 cells rewritten/frame on a 13,200-cell grid; ~20 KB/frame churn | Damage discipline confirmed at the allocation level, not inferred |
| Startup decomposition | 2.5 ms fleury-attributable (first byte 0.5 ms); warm AOT floor ~15–17.5 ms | The TTFB gap vs Rust is the runtime floor, not the framework |
| Memory decomposition | Retained framework heap 85 KB; +3.3 MiB over the 13.8 MiB AOT floor for a minimal app | The retained architecture retains almost nothing |
| TreeTable index (post-diet) | At 100k rows: live heap −12 MB, build −19%, fuzzy −49%; SB.11 CPU −25%, fps 4.3→7.5 | Index stores one text blob + spans; rows materialize on demand |
| Semantics cost | Semantic apply 0.0 ms on the visual frame (deferred flush); divergence oracle green | The differentiator is free at frame time and verified correct |

The honest column, kept honest: SB.9 and SB.11 remain "catch up" — SB.9's
byte delta is fixture surface area over a verified byte-minimal encoder,
SB.11's RSS is its fixture's eager 100k node maps (fixtures are not
slimmed to move their own rows). SB.1's overhead *ratio* is structurally
unflattering (23 absolute bytes of steady-state overhead against 9 bytes
of content). RSS/CPU/TTFB absolutes vs Rust are runtime floor, measured
and documented. The scoreboard bands RSS/CPU within runtime class and
excludes session lifecycle bytes from the overhead axis — methodology
changes applied symmetrically to every participant, changing no standing.

Public claims language lives in
[peer-scorecards](implementation/peer-scorecards.md) and should be quoted
from there, not paraphrased upward.

## Costs accepted (the trade ledger)

1. **A bookkeeping floor on near-empty frames.** A retained tree cannot
   match TEA's per-frame constants when a frame is nine bytes of content.
   Minimized (sync skip), measured (~23 bytes absolute), accepted.
2. **A verification tax.** Incremental layers demanded their own oracles
   and gates. The architecture's correctness is maintained machinery, not
   a free property — that machinery is part of the architecture.
3. **Imported intuitions that backfire.** Flutter/DOM habits like keyed
   row "recycling" measure ~2x slower here because they defeat damage
   tracking and scroll reuse. The anti-patterns are documented where they
   bite (`RepaintBoundary` docs); the perf folklore is part of the DX
   surface and still growing.

## What the architecture still owes

Recorded, owned, and deliberately not hand-waved: an off-main-thread
story for heavy work (cooperative yielding is not parallelism; Textual's
workers are ahead); an integrated devtools/inspector workflow; IME and
screen-reader evidence (parked); the windowed-rows/render-island decision
for data widgets; and the API freeze itself — the
[core API/DX audit](implementation/core-api-dx-audit-readiness.md) is the
next body of work. None of these are foundation changes; the foundation
is measured, gated, and closed.
