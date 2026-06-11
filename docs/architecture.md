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

## What the benchmarks actually taught us

The full standings live in the scoreboards; quoting them all here would
bury the signal. These are the results that shaped the architecture's
story — the upsets, the losses worth respecting, and the lessons we paid
for. (All native-stack, 3-run medians; wire evidence in
`profiling/caps/2026-06-11-final`, web in
`profiling/web/baselines/2026-06-10-arm-native`.)

### Three results we would have bet against

**The retained tree out-emits immediate-mode Rust.** Going in, the safe
money said ratatui — the field's performance-credibility peer, a
systems language, the leanest possible library — would own raw wire
throughput, and fleury's goal would be "respectably close." The opposite
happened: fleury leads bytes, bytes-per-frame, and FPS on nearly every
shared scenario. The reason is architectural, not heroic optimization.
Immediate mode rebuilds the whole view every frame and diffs buffers to
recover what changed; the damage tracker never forgets what changed in
the first place, so the unchanged 99% of the screen is never painted at
all — confirmed at the allocation level, where a 13,200-cell grid under
churn rewrites ~85 cells a frame. Knowing-what-changed beat
being-fast-at-everything. That result is what makes the retained-mode
bet defensible against its oldest objection.

**Three orders of magnitude on a text editor.** Bubble Tea is a
well-built framework with the cleanest mental model in the field, and on
a 10k-character editor its cursor-move p95 measured 718 ms to fleury's
0.8 ms. Nothing in that gap is Go vs Dart; it is the Elm architecture
paying O(entire view) per keystroke while the element tree pays
O(changed path). Architecture determines the *shape* of the work, and no
amount of language speed buys back a shape that redoes everything. The
same structural story repeated in every peer fixture that had to
hand-implement selection, undo, and focus state as app code — the
element tree is the layer the others don't have.

**The native-core peer showed no native advantage.** OpenTUI's Zig
buffer core behind a TypeScript bridge — on paper the
"best of both worlds" design — trailed fleury on every shared wire axis.
The pipeline, not the kernel, is the unit of performance; a fast core
behind a bridge inherits the bridge. Nocterm closes the loop from the
other side: same language, same runtime floors, Flutter-style API
without the damage spine underneath, 8–30x slower on app-shaped
operations. Between them, the two Dart-adjacent comparisons isolate the
claim cleanly: the machinery is the architecture; the syntax and the
language are not.

### Where peers genuinely win, and what we did about it

**TEA's simplicity is a real architectural virtue.** On a counter app
emitting nine content bytes, Bubble Tea's near-zero per-frame protocol
constants make fleury's tree bookkeeping look heavy as a ratio (the
absolute cost is ~23 bytes). We trimmed the tax where it was real — tiny
diffs no longer pay the synchronized-output wrapper — and accepted the
floor that remains: a retained tree cannot match a string diff's
constants on near-empty frames, and for single-purpose micro-CLIs that
trade favors TEA. Fleury's bet is that terminal apps are becoming real
applications, where the trade inverts by orders of magnitude (see the
editor above).

**Rust's runtime floors are not contestable.** Ratatui boots in
single-digit milliseconds and idles at ~2 MiB; Dart AOT's warm floor is
~15–17 ms and ~14 MiB. We measured the floors instead of arguing with
them: fleury's own share is 2.5 ms of startup (first byte at 0.5 ms) and
85 KB of retained heap — the framework adds almost nothing to what the
runtime costs. Startup and footprint claims are scoped to
managed-runtime peers, where fleury leads everywhere measured.

**Textual beat us where maturity matters — and we imported the lesson.**
Its DataTable virtualization outperformed fleury's TreeTable fixture at
100k rows: the framework whose API makes lazy data the easy path wins,
regardless of engine speed. The first half of that lesson already landed
(the search index now retains one shared text blob plus spans instead of
per-row rows-and-text: −12 MB live, fuzzy queries 2x faster, SB.11 CPU
−25%); the second half — provider-style row building as the default API
shape — is queued for the core audit. The best architectural import of
the campaign came from the Python peer, not the systems-language ones.

### Lessons we paid for

- **Flutter intuitions can be anti-patterns here.** Keyed-row
  "recycling" — the standard DOM/Flutter pattern for moving lists —
  measured ~2x *slower* than letting positional rebuild repaint, because
  keyed boundaries turn every moved row into a reconciled subtree and
  defeat both the damage tracker and scroll reuse. Boundaries are for
  expensive content that stays put. Living close to Flutter means
  inheriting folklore that must be unlearned, and the framework now
  documents the trap where it bites (`RepaintBoundary` docs).
- **Measure the floor before chasing the gap.** Twice, the "obvious"
  optimization target dissolved under measurement: the cursor encoder
  was proven byte-minimal from transcripts (the remaining SB.9 delta is
  fixture surface area, not waste), and the RSS "diet" found 85 KB of
  retained framework heap — nothing to diet. Both times the honest
  output was a documented verdict, not a patch. The discipline cuts both
  ways: it also found the real wins (the index diet, the sync skip).
- **The toolchain can lie at the process level.** Every pre-campaign
  benchmark — ours and the harness's — ran under Rosetta translation
  without anyone noticing, inflating tails by whole multiples. The fix
  (pinning the native stack) mattered more than most optimizations. The
  evidence discipline that followed — 3-run medians, oracles for
  incremental layers, byte gates for the encoder — is now part of the
  architecture, because numbers you can't trust are worse than no
  numbers.

The bottom line on standings, in one sentence: fleury pushes leading on
8 of 12 wire scenarios against every peer including the Rust and Zig
ones, holds parity on 2, and trails on 2 for fully-explained
fixture-and-floor reasons — with public claims language maintained in
[peer-scorecards](implementation/peer-scorecards.md), to be quoted, not
paraphrased upward.

## Costs accepted (the trade ledger)

1. **A bookkeeping floor on near-empty frames.** A retained tree cannot
   match TEA's per-frame constants when a frame is nine bytes of content.
   Minimized (sync skip), measured (~23 bytes absolute), accepted.
2. **A verification tax.** Incremental layers demanded their own oracles
   and gates. The architecture's correctness is maintained machinery, not
   a free property — that machinery is part of the architecture.
3. **Imported intuitions that backfire.** Proximity to Flutter brings
   folklore that must be unlearned (the keyed-recycling lesson above);
   the perf folklore is part of the DX surface and still growing.

## What the architecture still owes

Recorded, owned, and deliberately not hand-waved: an off-main-thread
story for heavy work (cooperative yielding is not parallelism; Textual's
workers are ahead); an integrated devtools/inspector workflow; IME and
screen-reader evidence (parked); the windowed-rows/render-island decision
for data widgets; and the API freeze itself — the
[core API/DX audit](implementation/core-api-dx-audit-readiness.md) is the
next body of work. None of these are foundation changes; the foundation
is measured, gated, and closed.
