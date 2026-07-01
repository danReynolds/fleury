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
we learned from the frameworks that shaped this field, how the
architecture came together, and the measurements that surprised us —
including one where we'd have bet against ourselves.

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

Six frameworks define the field, each excellent at what it set out to
be, and each shaped fleury in some way.

| Framework | Stack | The model, in a sentence | At its best |
| --- | --- | --- | --- |
| Ratatui | Rust, single binary | Immediate mode: rebuild the view every frame, diff buffers | Tiny footprint, instant start, total control |
| Bubble Tea v2 | Go, single binary | Elm architecture: one model, one update function, one view-to-string | The cleanest mental model in the field, and the best ecosystem |
| Textual | Python | Widget DOM with CSS and a compositor | The most complete app framework: widgets, theming, devtools, docs |
| Ink | React on Node | React reconciled to lines of stdout | Instant familiarity; ideal for streaming CLI output |
| OpenTUI | Zig core, TypeScript API | Components over a native buffer, across a language bridge | Native-core ambition, proven inside a real product (OpenCode) |
| Nocterm | Dart AOT, single binary | Flutter-style widget API | The familiar surface for Flutter developers |

So why build another one? Because the four requirements above are
*day-one decisions*, and we wanted all four from day one. We wanted a
semantics tree, which needs a persistent widget tree to derive from. We
wanted untrusted-output safety to *be* the paint path, not a layer over
it. We wanted the terminal and the browser as two backends of one
pipeline, which means "what the UI is" and "how it gets emitted" have to
be separated from the first commit. Those wants pointed at an
architecture rather than a feature list — and the architecture with all
of those joints already existed in Flutter's three trees. Dart AOT could
ship it the way terminal users expect: as one static binary. That was
the bet.

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
  keystroke rebuild one dirty path instead of the world, and what gives
  application state — focus, selection, undo — a durable home the app
  doesn't have to build for itself.
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
Both hosts assemble the same building blocks (`TuiFrameLoop`, the
presentation planner, the span builder) and an oracle in the test suite
asserts the two surfaces render the same tree. (A single extracted frame
driver owning the choreography end-to-end is designed in the pipeline
program RFC and lands with the web render backend.)

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

Future<void> main() => runApp(const StatusApp());

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
widgets, including the data-heavy ones — tables and trees proven at
100k rows, log regions, markdown, code and diff views —
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
- **OpenTUI** — a lesson we took seriously before writing much code:
  performance lives in the whole pipeline, not in any single fast layer.
  A native core can only be as fast as the path that feeds it.

## Performance: where fleury lands

First the picture, then the stories. Everything below comes from our
benchmark harness — three runs, medians, real PTYs, a native toolchain,
equivalent scenario fixtures per framework — and the harness, fixtures,
and transcripts ship in the repo. Regressions are gated: the build fails
if frame cost or bytes-per-frame move.

In absolute terms: interactive updates render in well under a
millisecond — a keystroke in a 10,000-character editor costs 0.8 ms —
and the heaviest stress scenario we run (full-screen churn on a 300×100
grid, in the browser backend) holds 8.5 ms, comfortably inside a 60 fps
budget, with zero over-budget frames across the suite. A fleury binary
goes from launch to first frame in about 20 ms, of which the framework's
own share is 2.5 ms. A minimal app idles around 17 MB, nearly all of it
the runtime's baseline — the framework itself retains 85 KB. And on the
wire — the bytes a TUI actually sends the terminal — fleury measures at
or ahead of the most efficient renderers in the field on most workloads,
including the systems-language ones.

No single number is the point. The point is that the architecture holds
up under measurement on every axis a framework controls, and sits where
you'd expect on the axes the runtime controls. Three of those
measurements taught us something worth sharing.

**Retained mode pays for itself on the wire.** Going in, we treated the
damage-tracking machinery as a tax we'd gladly pay for the developer
model — we assumed the leanest immediate-mode renderers set a
wire-efficiency bar we could only approach. Measured natively against
the best of the field, the assumption ran backwards: fleury emitted
fewer bytes per frame and sustained higher frame rates on most shared
workloads. The mechanism is the interesting part: a renderer that
rebuilds each frame must diff the result to *recover* what changed,
while the damage tracker never forgot — so the unchanged screen is never
painted at all. Under continuous churn, a 13,200-cell grid rewrites
about 85 cells a frame. For us, that settled retained UI's oldest open
question in terminals: the machinery isn't a tax, it's the engine.

**Keystrokes that follow the change, not the document.** A cursor move
in a 10,000-character editor costs fleury 0.8 ms, and the cost tracks
what changed rather than how much is on screen — the element tree doing
its job. Rebuilding the whole view per update is a perfectly reasonable
trade for small tools, and several great frameworks make it; the element
tree is what removes that trade for applications, the same way it did
for Flutter on phones.

**The machinery, not the language, is where the performance lives.**
Every measurement we took pointed the same way: wire efficiency and
latency track how much a framework's update pipeline knows about change,
far more than they track its implementation language. That conviction is
why our effort went into the spine — damage tracking, paint isolation,
scroll reuse, byte accounting — rather than into micro-optimizing any
single layer, and it's why we'd expect the same architecture to pay off
in any language that hosts it.

**And the browser target held up.** The same damage pipeline drives the
retained DOM backend, with browser-inclusive end-to-end latency under
12 ms — measured through the real browser frame pipeline, not just our
own timers. Browser-inclusive frame numbers are rare in this space;
we'd like to help make them normal.

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
applications, where work-that-follows-change wins by a widening margin
as screens grow.

**Rust's runtime floors are not contestable.** Ratatui boots in
single-digit milliseconds and idles at ~2 MiB; Dart AOT's warm floor is
~15–17 ms and ~14 MiB. We measured the floors instead of arguing with
them: fleury's own share is 2.5 ms of startup (first byte at 0.5 ms) and
85 KB of retained heap — the framework adds almost nothing to what the
runtime costs. Our startup and footprint claims are scoped to
managed-runtime peers, where fleury leads everywhere we measured.

**And two lessons we paid for:**

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
The full scenario-by-scenario standings — including the two workloads
where fleury trails today, and exactly why — live with the benchmark
harness in the repo. We'd rather you read those than a summary line
here; the per-scenario detail is where comparisons stay honest.

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
