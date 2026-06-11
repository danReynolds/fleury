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

## The landscape, and why a new framework

Six frameworks define the field today. Each is genuinely good at what it
set out to be — the gaps only show up when you hold them against the four
requirements above.

| Framework | Stack | The model, in a sentence | At its best | Where it stops |
| --- | --- | --- | --- | --- |
| Ratatui | Rust, single binary | Immediate mode: rebuild the view every frame, diff buffers | Tiny footprint, instant start, total control | Everything above drawing is app code — state, focus, testing, accessibility |
| Bubble Tea v2 | Go, single binary | Elm architecture: one model, one update function, one view-to-string | The cleanest mental model in the field, and the best ecosystem | Every update rebuilds the whole view; no structure behind the string |
| Textual | Python | Widget DOM with CSS and a compositor | The most complete app framework: widgets, theming, devtools, docs | Interpreter-bound; rich structure for humans, no contract for machines |
| Ink | React on Node | React reconciled to lines of stdout | Instant familiarity; ideal for streaming CLI output | Line-oriented — dense full-screen apps fight it |
| OpenTUI | Zig core, TypeScript API | Components over a native buffer, across a language bridge | Native-core ambition, proven inside a real product (OpenCode) | The bridge hands back what the core wins |
| Nocterm | Dart AOT, single binary | Flutter-style widget API | The familiar surface for Flutter developers | The syntax without the machinery: no damage tracking, no semantics |

The case for a new framework was never that any of these is bad. It is
that the four requirements are structural, and structure does not
retrofit. A semantics tree needs a real tree to derive from — there is
nothing to attach one to in a view that is a string, or a buffer
repainted from scratch each frame. Security-by-default has to *be* the
paint path, not a wrapper around it. A second render surface requires
that "what the UI is" and "how it gets emitted" were separated from the
beginning. The one UI architecture with all of those joints already
existed — Flutter's — and nobody had built it for terminals with the
machinery intact. Dart AOT made it shippable the way terminal users
expect, as one static binary. That was the bet.

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

## What this buys a developer

The architecture is the means; this is the offer it exists to make.

**Build the way a million Flutter developers already build.** Declarative
widget composition, `setState`, controllers, `const` optimization — the
mental model transfers wholesale, and divergences from Flutter are
treated as bugs unless deliberate. With hot reload: fleury attaches a
reassemble handler (`ext.fleury.reassemble`) so a running TUI rebuilds
in place on save, terminal state intact — edit-and-see, in a terminal.

**Start from an app-grade catalog, not a box of parts.** Forty-plus
widgets including the data-heavy ones peers make you build — tables and
trees proven at 100k rows, log regions, markdown/code/diff views — and a
set shaped for what terminal apps are becoming: message lists, approval
prompts, patch review, conversation navigation, process panels, command
palette. Text editing is engine-grade: grapheme-correct, selection and
undo, paste policy, completion seams, configurable keymaps.

**Ship apps machines can drive.** The semantics layer means tests query
roles, state, and actions instead of scraping bytes — and so can agents.
The same structure that makes the test suite readable makes every fleury
app automatable by default, with a protocol adapter (ACP) scoped as a
fast-follow package rather than a rewrite.

**Trust the output path.** Subprocess and LLM output is sanitized by
default; clipboard, links, and images are policy-gated; redaction has
hooks; terminal capabilities are detected and degrade by contract rather
than by accident. Suspend (Ctrl+Z), subprocess handoff, and crash paths
restore the user's terminal — the unglamorous correctness that decides
whether a TUI feels professional.

**Run it anywhere a binary runs, and beyond the terminal.** One static
AOT executable — boots in ~20 ms, no runtime to install — plus the same
app rendering into a browser as a first-class DOM target, and a remote
driver for serving an app session over a socket. Long work runs as
tasks with progress and cancellation; effects are structured, not
ad hoc.

**Develop with instruments on.** Headless testing against a fake
terminal, semantic assertions, debug capture, `fleury diagnose --json`
for capability triage, and the benchmark/gate harness this document's
evidence comes from — the same rigor the framework holds itself to is
available to apps.

(Scope honesty: Windows has a driver but validation is deferred
post-MVP; IME and screen-reader evidence is parked; see
"What the architecture still owes.")

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

## What we took from each

- **Flutter** — the largest debt by far: the machinery itself. The tree
  separation, repaint boundaries, and semantics layering described above
  are Flutter's joints, rebuilt for cells. Not the syntax; the
  structure.
- **Bubble Tea** — frugality as a discipline. Its per-frame protocol
  cost is near zero, and that number set fleury's bar: it is the direct
  reason tiny updates skip the synchronized-output wrapper today. Its
  ecosystem is also the standing proof that taste and cohesion, not
  features, drive adoption in this space.
- **Ratatui** — the evidence bar. It made buffer-diff efficiency table
  stakes and benchmark rigor the norm; fleury's measure-first culture is
  in part an answer to it.
- **Textual** — the definition of "complete," and one concrete import:
  its data tables beat fleury's tree table at 100k rows because its API
  makes lazy data the easy path. We took the lesson — the tree-search
  index now keeps one shared text blob instead of per-row copies (12 MB
  less live heap, fuzzy search twice as fast at that scale), and
  provider-style row building is queued as the default API shape.
- **Ink** — the reminder that mental-model familiarity is adoption
  fuel. Fleury reads as Flutter for the same reason Ink reads as React:
  on purpose.
- **OpenTUI** — a caution rather than an import: a native core behind a
  language bridge showed no wire advantage on any shared workload. The
  pipeline, not the kernel, is the unit of performance.

## How we differentiated

Four statements, each carrying the one measurement that earns it.

**Work proportional to change — proven against the hardest opponent.**
The safe bet going in was that immediate-mode Rust would own raw wire
throughput and a managed-runtime retained tree would chase it. Measured
natively, fleury emits fewer bytes per frame and sustains higher frame
rates than ratatui on nearly every shared workload. The mechanism is the
point: immediate mode redraws everything and diffs the result to
*recover* what changed; the damage tracker never forgot, so the
unchanged screen is never painted at all. Under continuous churn, a
13,200-cell grid rewrites about 85 cells a frame. Knowing-what-changed
beats being-fast-at-everything — and that result retires the oldest
objection to retained UI in terminals.

**State with a home.** A keystroke in a 10,000-character editor costs
fleury 0.8 ms. The same operation on the Elm-architecture peer measured
718 ms. Nothing in that gap is Go versus Dart; it is O(whole view)
versus O(changed path) — the element tree doing its job. The peers'
own benchmark fixtures argue the same point from the other side: they
hand-implement selection, undo, and focus as app code, because their
architectures have nowhere to keep state the app didn't build itself.

**The machinery is the moat — and it is separable from the language.**
Nocterm shares fleury's language, runtime floors, and surface syntax,
and measures 8–30x slower on app-shaped operations: same Dart, no
damage spine. OpenTUI has the native core and not the pipeline, and
shows no advantage. Together they isolate the claim cleanly: not the
language, not the syntax — the machinery.

**Structure no peer has.** Fleury is the only framework in the field
with a semantics tree — agents and tests query roles, state, and
actions instead of scraping ANSI — the only one with a capability and
sanitization contract built into the default paint path, and the only
one rendering terminal and browser from the same pipeline with an
oracle asserting the two surfaces agree. All of it ships as a single
AOT binary, which only the systems-language peers can otherwise say.

## Keeping ourselves honest

The claims above are measured, and so are the places where the
measurements favor someone else. (All evidence native-stack, 3-run
medians: wire standings in `profiling/caps/2026-06-11-final`, web in
`profiling/web/baselines/2026-06-10-arm-native`.)

**TEA's simplicity is a real architectural virtue.** On a counter app
emitting nine content bytes, Bubble Tea's near-zero per-frame constants
make fleury's tree bookkeeping look heavy as a ratio (the absolute cost
is ~23 bytes). We trimmed the tax where it was real — tiny diffs no
longer pay the synchronized-output wrapper — and accepted the floor that
remains: a retained tree cannot match a string diff's constants on
near-empty frames. For single-purpose micro-CLIs that trade favors TEA;
fleury's bet is that terminal apps are becoming real applications, where
the editor result above shows the trade inverting by three orders of
magnitude.

**Rust's runtime floors are not contestable.** Ratatui boots in
single-digit milliseconds and idles at ~2 MiB; Dart AOT's warm floor is
~15–17 ms and ~14 MiB. We measured the floors instead of arguing with
them: fleury's own share is 2.5 ms of startup (first byte at 0.5 ms) and
85 KB of retained heap — the framework adds almost nothing to what the
runtime costs. Startup and footprint claims are scoped to
managed-runtime peers, where fleury leads everywhere measured.

**Lessons we paid for:**

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
  was proven byte-minimal from transcripts (the byte gap that remained
  on one subprocess-output workload traced to the benchmark fixture
  rendering more live regions, not to encoder waste), and the RSS "diet"
  found 85 KB of retained framework heap — nothing to diet. Both times
  the honest output was a documented verdict, not a patch. The
  discipline cuts both ways: it also found the real wins (the index
  diet, the sync skip).
- **The toolchain can lie at the process level.** Every pre-campaign
  benchmark — ours and the harness's — ran under Rosetta translation
  without anyone noticing, inflating tails by whole multiples. The fix
  (pinning the native stack) mattered more than most optimizations. The
  evidence discipline that followed — 3-run medians, oracles for
  incremental layers, byte gates for the encoder — is now part of the
  architecture, because numbers you can't trust are worse than no
  numbers.

The standings, in one sentence: fleury pushes leading on 8 of 12 wire
scenarios against every peer including the Rust and Zig ones, holds
parity on 2, and trails on 2 for fully-explained fixture-and-floor
reasons — with public claims language maintained in
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
