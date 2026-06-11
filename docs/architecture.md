# Fleury: Flutter's architecture, rebuilt for the terminal

**Status:** Draft launch post for the Flutter and TUI developer
communities. Holds until API freeze; the editor's note at the end lists
internal links to convert on publish.

Terminals are having their best decade since the eighties. Agent
consoles, dev-tool dashboards, LLM chat surfaces, deploy monitors — the
fastest-growing category of new terminal programs aren't utilities, they
are *applications*, with the screen complexity, input handling, and
update rates that word implies. We've spent the past months building and
measuring fleury, a retained-mode UI framework for the terminal (and,
it turns out, the browser) that starts from a simple bet: the
architecture this moment needs already exists — it's Flutter's — and
nobody had built it for terminals with the machinery intact.

This post is the story of that bet: what changed about terminals, what
the existing frameworks solve and where they stop, what we took from
each of them, and the measurements that surprised us — including one
where we'd have bet against ourselves.

## What changed about terminals

Four requirements define a 2026 terminal app framework, and none of them
mattered much five years ago:

1. **Incrementality is mandatory.** App-scale screens update
   continuously; the work per frame has to be proportional to what
   changed, not to how big the screen is.
2. **Machines are users now.** Agents drive terminal UIs. An interface
   that can only be screen-scraped from ANSI bytes is opaque to its
   fastest-growing user base. The UI needs queryable structure — roles,
   state, actions — not just cells.
3. **Untrusted output is the default.** The common case is rendering
   subprocess and LLM output. Escape-sequence injection, clipboard and
   link policy, redaction — these are framework concerns now, not app
   afterthoughts.
4. **The terminal is one surface.** The same app increasingly needs to
   show up in a browser — dashboards, remote sessions, demos — without a
   second implementation.

## The landscape

Six frameworks define the field, and each is genuinely good at what it
set out to be. The gaps only show up when you hold them against those
four requirements.

| Framework | Stack | The model, in a sentence | At its best | Where it stops |
| --- | --- | --- | --- | --- |
| Ratatui | Rust, single binary | Immediate mode: rebuild the view every frame, diff buffers | Tiny footprint, instant start, total control | Everything above drawing is app code — state, focus, testing, accessibility |
| Bubble Tea v2 | Go, single binary | Elm architecture: one model, one update function, one view-to-string | The cleanest mental model in the field, and the best ecosystem | Every update rebuilds the whole view; no structure behind the string |
| Textual | Python | Widget DOM with CSS and a compositor | The most complete app framework: widgets, theming, devtools, docs | Interpreter-bound; rich structure for humans, no contract for machines |
| Ink | React on Node | React reconciled to lines of stdout | Instant familiarity; ideal for streaming CLI output | Line-oriented — dense full-screen apps fight it |
| OpenTUI | Zig core, TypeScript API | Components over a native buffer, across a language bridge | Native-core ambition, proven inside a real product (OpenCode) | The bridge hands back what the core wins |
| Nocterm | Dart AOT, single binary | Flutter-style widget API | The familiar surface for Flutter developers | The syntax without the machinery: no damage tracking, no semantics |

The case for a new framework was never that any of these is bad. It's
that the four requirements are *structural*, and structure doesn't
retrofit. A semantics tree needs a real tree to derive from — there is
nothing to attach one to in a view that's a string, or a buffer
repainted from scratch each frame. Security-by-default has to *be* the
paint path, not a wrapper around it. A second render surface requires
that "what the UI is" and "how it gets emitted" were separated from the
beginning. The one UI architecture with all of those joints already
existed — Flutter's three trees — and Dart AOT could ship it the way
terminal users expect: as one static binary. That was the bet.

## The architecture

If you know Flutter, you know fleury's shape; if you've never touched
Flutter, here's the part worth knowing. The framework keeps *four*
trees, each with one job:

- **The widget tree** is immutable configuration — cheap, throwaway
  descriptions of what the UI should look like. Because widgets are
  values, equality means "nothing changed": `const` subtrees and
  configuration checks prune rebuilds, and frames with no work get
  skipped entirely.
- **The element tree** is identity and state — the durable spine that
  survives rebuilds. Your `setState` lives here. It's what lets a
  keystroke rebuild one dirty path instead of the world, and it's the
  layer other frameworks make you hand-build (more on that below).
- **The render tree** does layout and paint over a cell grid —
  constraints down, sizes up, exactly like Flutter but with cells
  instead of pixels. Its persistent identity is what change-tracking
  hangs on: a damage tracker records which rows actually changed,
  repaint boundaries cache cells for subtrees that didn't, and scroll
  detection turns moving content into buffer moves instead of repaints.
- **The semantics tree** is the machine-readable shadow of your UI —
  roles, state, actions — updated incrementally and flushed *off* the
  visual frame so it costs the frame budget nothing. Tests query it.
  Agents drive it. It's Flutter's accessibility-tree idea, promoted to a
  headline feature, because the terminal's newest users are programs.

From a state change, the pipeline runs: rebuild the dirty subtree →
layout → paint into a damage-tracked cell buffer → backend. The terminal
backend diffs cell buffers and emits byte-frugal ANSI — it accounts for
every escape byte, writes through small gaps when that's cheaper than
moving the cursor, and skips the synchronized-output wrapper when a diff
is tiny. The web backend applies the *same damage* to retained DOM rows.
Both sit behind one host interface, and an oracle in the test suite
asserts the two surfaces render the same tree.

Around that pipeline sits the app layer: a typed command registry, focus
and overlay management, a capability contract (terminals differ in
everything; fleury detects what yours can do and degrades by policy, not
by accident), sanitize-by-default handling of untrusted output, and a
task layer for long work with progress and cancellation.

And because a framework this incremental can drift subtly, fleury keeps
itself honest mechanically: a byte-equivalence oracle proves the diffed
output reproduces a full repaint, a semantics oracle proves the
incremental tree matches a from-scratch build, and perf gates fail the
build if frame cost or bytes-per-frame regress. The verification
machinery is part of the architecture.

Here's what it looks like — if you've written Flutter, you've already
written this:

```dart
import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

Future<void> main() => runTui(const StatusApp());

class StatusApp extends StatefulWidget {
  const StatusApp({super.key});

  @override
  State<StatusApp> createState() => _StatusAppState();
}

class _StatusAppState extends State<StatusApp> {
  var _tick = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _tick++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('uptime: ${_tick}s'),
          const SizedBox(height: 1),
          ProgressBar(value: (_tick % 60) / 60),
        ],
      ),
    );
  }
}
```

## What this buys you

**Build the way a million Flutter developers already build.**
Declarative composition, `setState`, controllers, `const` optimization —
the mental model transfers wholesale, and where fleury diverges from
Flutter we treat it as a bug unless it's deliberate. With hot reload: a
running TUI rebuilds in place on save, terminal state intact.
Edit-and-see, in a terminal.

**Start from an app-grade catalog, not a box of parts.** Forty-plus
widgets, including the data-heavy ones peers make you build — tables and
trees proven at 100k rows, log regions, markdown, code and diff views —
and a set shaped for what terminal apps are becoming: message lists,
approval prompts, patch review, conversation navigation, process panels,
a command palette. Text editing is engine-grade: grapheme-correct,
selection and undo, paste policy, completion seams, configurable
keymaps.

**Ship apps machines can drive.** Tests query roles, state, and actions
instead of scraping bytes — and so can agents. The same structure that
makes the test suite readable makes every fleury app automatable by
default, with an agent-protocol adapter scoped as a follow-up package
rather than a rewrite.

**Trust the output path.** Subprocess and LLM output is sanitized by
default; clipboard, links, and images are policy-gated; redaction has
hooks. Suspend (Ctrl+Z), subprocess handoff, and crash paths restore the
user's terminal — the unglamorous correctness that decides whether a TUI
feels professional.

**Run it anywhere a binary runs — and beyond the terminal.** One static
AOT executable, ~20 ms to first frame, no runtime to install. The same
app renders into a browser as a first-class DOM target, and a remote
driver can serve an app session over a socket.

**Develop with the instruments on.** Headless testing against a fake
terminal, semantic assertions, debug capture, `fleury diagnose --json`
for capability triage — the same rigor the framework holds itself to is
available to your app.

(Scope honesty: Windows has a driver but validation is still ahead of
us, and IME/screen-reader support is on the roadmap, not in the box.)

## What we took from each peer

Fleury exists because of this field, not in spite of it.

- **Flutter** — the largest debt by far: the machinery itself. The tree
  separation, repaint boundaries, and semantics layering are Flutter's
  joints, rebuilt for cells. Not the syntax; the structure.
- **Bubble Tea** — frugality as a discipline. Its per-frame protocol
  cost is near zero, and that number set our bar: it's the direct reason
  tiny updates skip the synchronized-output wrapper today. Its ecosystem
  is also the standing proof that taste and cohesion, not feature lists,
  drive adoption in this space.
- **Ratatui** — the evidence bar. It made buffer-diff efficiency table
  stakes and benchmark rigor the norm; our measure-first culture is in
  part an answer to it.
- **Textual** — the definition of "complete," and one concrete import:
  its data tables beat our tree table at 100k rows because its API makes
  lazy data the easy path. We took the lesson — our tree-search index
  now keeps one shared text blob instead of per-row copies (12 MB less
  live heap, fuzzy search twice as fast at that scale), and
  provider-style row building is becoming the default API shape.
- **Ink** — the reminder that mental-model familiarity is adoption fuel.
  Fleury reads as Flutter for the same reason Ink reads as React: on
  purpose.
- **OpenTUI** — a caution rather than an import: a native core behind a
  language bridge showed no wire advantage on any shared workload. The
  pipeline, not the kernel, is the unit of performance.

## The measurements that surprised us

Everything here is from our native-toolchain benchmark harness — three
runs, medians, real PTYs, every framework driven through equivalent
scenario fixtures. The harness and transcripts ship in the repo.

**The retained tree out-emits immediate-mode Rust.** Going in, the safe
money said ratatui — a systems language, the leanest possible library —
would own raw wire throughput, and our retained tree would chase it. The
opposite happened: fleury emits fewer bytes per frame and sustains
higher frame rates on nearly every shared workload. The mechanism is the
point: immediate mode redraws everything and diffs the result to
*recover* what changed; the damage tracker never forgot, so the
unchanged screen is never painted at all. Under continuous churn, a
13,200-cell grid rewrites about 85 cells a frame. Knowing-what-changed
beats being-fast-at-everything — and it retires the oldest objection to
retained UI in terminals.

**Three orders of magnitude on a keystroke.** A cursor move in a
10,000-character editor costs fleury 0.8 ms. The same operation on the
Elm-architecture peer measured 718 ms. Nothing in that gap is Go versus
Dart — it's O(whole view) versus O(changed path), the element tree doing
its job. The peers' own benchmark fixtures argue the same point from the
other side: they hand-implement selection, undo, and focus as app code,
because their architectures have nowhere to keep state the app didn't
build itself.

**The machinery is separable from the language — and it's the part that
matters.** Nocterm shares fleury's language, runtime floors, and surface
syntax, and measures 8–30x slower on app-shaped operations: same Dart,
no damage spine. OpenTUI has the native core and not the pipeline, and
shows no advantage. Together they isolate the claim: not the language,
not the syntax — the machinery.

**And the browser target held up.** The same damage pipeline drives
retained DOM rows to 0% over-budget frames across every web scenario,
with browser-inclusive end-to-end under 12 ms. No terminal framework
publishes browser-inclusive frame numbers; we'd like that to change.

## Keeping ourselves honest

The claims above are measured, and so are the places where the
measurements favor someone else.

**Bubble Tea's simplicity is a real architectural virtue.** On a counter
app emitting nine content bytes, its near-zero per-frame constants make
our tree bookkeeping look heavy as a ratio (the absolute cost is ~23
bytes). We trimmed the tax where it was real and accepted the floor that
remains: a retained tree cannot match a string diff's constants on
near-empty frames. For single-purpose micro-CLIs, that trade favors
Bubble Tea. Our bet is that terminal apps are becoming real
applications, where the keystroke result above shows the same trade
inverting by three orders of magnitude.

**Rust's runtime floors are not contestable.** Ratatui boots in
single-digit milliseconds and idles at ~2 MiB; Dart AOT's warm floor is
~15–17 ms and ~14 MiB. We measured the floors instead of arguing with
them: fleury's own share is 2.5 ms of startup (first byte at 0.5 ms) and
85 KB of retained heap — the framework adds almost nothing to what the
runtime costs. Our startup and footprint claims are scoped to
managed-runtime peers, where fleury leads everywhere we measured.

**And three lessons we paid for:**

- **Flutter intuitions can be anti-patterns here.** Keyed-row
  "recycling" — the standard DOM/Flutter pattern for moving lists —
  measured ~2x *slower* than letting positional rebuild repaint, because
  keyed boundaries turn every moved row into a reconciled subtree and
  defeat both the damage tracker and scroll reuse. Boundaries are for
  expensive content that stays put. Living close to Flutter means
  inheriting folklore that sometimes must be unlearned; we document the
  traps where they bite.
- **Measure the floor before chasing the gap.** Twice, the "obvious"
  optimization target dissolved under measurement: our cursor encoding
  was proven byte-minimal from transcripts (the gap we'd been chasing
  traced to a benchmark fixture, not encoder waste), and a planned
  memory diet found 85 KB of retained framework heap — nothing to diet.
  Both times the honest output was a documented verdict, not a patch.
- **The toolchain can lie at the process level.** Every early benchmark
  — ours and the harness's — ran under Rosetta translation without
  anyone noticing, inflating tail latencies by whole multiples. Pinning
  the native stack mattered more than most optimizations. The evidence
  discipline that followed — medians, oracles, regression gates — is now
  part of the architecture, because numbers you can't trust are worse
  than no numbers.

Where do the standings land? Fleury pushes leading on 8 of 12 wire
scenarios against every peer including the Rust and Zig ones, holds
parity on 2, and trails on 2 for reasons we can name precisely (a
fixture that renders more live regions than its peer equivalent, and a
fixture whose data representation we won't slim just to move our own
score).

## The trades we accepted

1. **A bookkeeping floor on near-empty frames.** Minimized, measured
   (~23 bytes), accepted. Simplicity-first architectures keep this win.
2. **A verification tax.** Incremental layers demanded their own oracles
   and gates. The architecture's correctness is maintained machinery,
   not a free property — and we consider that machinery part of the
   design.
3. **Imported intuitions that backfire.** Proximity to Flutter brings
   folklore that must be unlearned; the perf folklore is part of the DX
   surface and still growing.

## What's next

The foundation is measured, gated, and closed; the work ahead is
surface. An API-consistency audit before freeze (capability fallback and
copy/export contracts rolled out across the full catalog), an integrated
devtools workflow, off-main-thread execution for heavy work, Windows
validation, IME and screen-reader support, and the public release
itself. If you build terminal apps — or you're a Flutter developer who
has wanted to — we'd like fleury to be the framework you'd have built,
and we'd like to hear where it isn't yet.

---

*Editor's note (strip on publish): internal companions are
[why-fleury](implementation/why-fleury.md) (positioning),
[peer-scorecards](implementation/peer-scorecards.md) (standings + the
exact public claims language),
[core-api-dx-audit-readiness](implementation/core-api-dx-audit-readiness.md)
(the audit), and the
[execution log](implementation/web-rfc-execution-log.md) (full
measurement trail). Wire evidence:
`profiling/caps/2026-06-11-final`; web evidence:
`profiling/web/baselines/2026-06-10-arm-native`.*
