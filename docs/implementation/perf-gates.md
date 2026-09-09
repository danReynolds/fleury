# Performance regression gates

Fleury's hot paths are covered by a set of **regression gates** — deterministic
measurements with a baseline (or a structural invariant) that fail on a
regression. They exist because the perf pass found the machinery healthy; their
job is to keep it that way as the code moves.

**The one rule:** after a change that touches a gated path (table below), run
that gate and confirm it passes before you land. If the change *intends* to move
the number (a real optimization, or an accepted cost), re-baseline in the same
PR with `--update-baseline` so the new number is reviewed in the diff — never
loosen a tolerance to make red go away.

All gates run through the dev tool and exit non-zero on regression:

```sh
dart tool/fleury_dev.dart benchmark <gate> [--gate] [--update-baseline]
```

**Take inventory:** `dart tool/fleury_dev.dart benchmark --help` lists every
gate. **Run the whole fast suite in one shot** (serve-semantics, image-bench,
bundle-size, alloc-gate, input-alloc-gate, paint-gate, selection-gate,
runtime-gate — ~24s
measured, with a
pass/fail summary); CI runs this same suite on every push/PR:

```sh
dart tool/fleury_dev.dart benchmark gates
```

The heavier PTY/subprocess gates (`wire-gate`, `serve-wire-live`) are not in the
`gates` suite — run them explicitly when you touch their paths.

## The gates

| Gate | Protects | When to run (trigger) | Speed | Baseline |
| --- | --- | --- | --- | --- |
| `wire-gate` | Terminal ANSI **output bytes** (SB.1/6/9: startup, dashboard steady-state, untrusted-output encoding) | `lib/src/rendering/ansi_renderer.dart`, cell paint, any diff/cursor/SGR change | ~30s (PTY) | `profiling/wire_gate_baseline.json` |
| `alloc-gate` | Per-frame **allocation churn** (build → reconcile → layout → paint → diff) on **two axes**: `total` — every Dart-level allocation the frame makes, which is what the GC sees — and `project` — `package:fleury` classes only | `lib/src/widgets/framework.dart`, `lib/src/rendering/**`, anything on the per-frame path | ~10s (VM service) | `profiling/alloc_gate_baseline.json` |
| `input-alloc-gate` | Per-**key** `package:fleury` allocation churn (parser → dispatcher → session regularizer → binding/detector walk), driving a held key through lifecycle mode | `lib/src/input/**`, `lib/src/terminal/input_parser.dart`, `lib/src/runtime/input_dispatcher.dart`, `lib/src/widgets/key_bindings.dart`, `keyboard.dart`, `focus.dart` | ~5s (VM service) | `profiling/input_alloc_gate_baseline.json` |
| `paint-gate` | Paint-walk pruning as **exact repaint-boundary counters**: the real `ListView.builder`'s auto-boundaries prune a localized update to one repaint; Overlay entry boundaries engage adaptively (dashboard+floater fixtures — real leaf widgets in bespoke two-entry scaffolding); the **lazy-layer convention** (the real `Toaster` with zero toasts idles pure pass-through: `boundaryCount == 0`); full-invalidate staleness (`cached == 0` when everything is dirty). Paint-phase µs is recorded warn-only (measured with debug stats on — not a clean paint time) and never fails | `lib/src/rendering/**` (esp. `render_repaint_boundary.dart`, cell paint), `lib/src/widgets/overlay.dart`, `lib/src/widgets/list_view.dart`, any widget that mounts overlay entries (toasts, banners, dropdowns) | ~4s (dart-run startup dominates; the measurement is <0.5s) | `profiling/paint_gate_baseline.json` (counters exact, tolerance 0; structural invariants also enforced in-code, even under `--update-baseline`) |
| `selection-gate` | Default-on text **selection** driven through a **real `SelectionArea`** — press/drag/release, Ctrl+A, Ctrl+C, Esc, routed through a real `InputDispatcher` + `PointerRouter` against real painted geometry. Gated counters: chars a drag selects and copies, chars a select-all selects and copies, and the **highlight cells actually painted**. Structural invariants (a drag selects something; Esc clears the highlight to zero) hold even under `--update-baseline`. The per-frame µs a held selection adds is recorded **warn-only** (machine-dependent, and this path's per-frame allocation is JIT-sink-nondeterministic — a hard alloc gate would flap CI ~24×, so cost is surfaced, not gated) | `lib/src/widgets/selection/**`, `selectable_text_mixin.dart`, `selection_area.dart`, `pointer.dart`, the default-on wrap in `run_app.dart` | ~5s | `profiling/selection_gate_baseline.json` (counters exact, tolerance 0) |
| `runtime-gate` | The frame **program** end to end: real `runApp` sessions on a `FakeTerminalDriver`, driven by a fixed event script through the real `FrameDriver` → present. Gated counters: **frames rendered per event kind** (the runtime's own `FrameEvent.reason`), **frames the no-change gate skipped**, **bytes presented** (total and per frame). The only gate that can see a frame that is *owed and never scheduled*, or one nothing needed. Fixtures: an anchored float whose anchor stops painting must be hidden within 2 frames **and the retraction must be a one-shot, not a spin**; a 512 KiB paste must cost a logarithmic number of frames, not one per 2 KiB chunk. Those invariants hold even under `--update-baseline` | `lib/src/runtime/**` (esp. `frame_driver.dart`, `frame_scheduler.dart`, `run_app.dart`, `tui_frame_loop.dart`), the paint-pass retraction sweep in `render_object.dart`, `lib/src/editing/text_paste.dart` | ~3s (boots three apps) | `profiling/runtime_gate_baseline.json` (counters exact, tolerance 0) |
| `image-bench` | Inline-image encoder: **dedup** (0 B/frame static) + **zero-image fast path** (0 B) | `lib/src/terminal/terminal_image_encoder.dart`, `ansi_byte_budget.dart` image category | ~5s | structural (in code) |
| `serve-semantics-gate` | Semantics wire **anti-cliff**: diff stays flat in tree size (never falls off the 32 KiB DEFLATE cliff) | `lib/src/remote/remote_semantics.dart`, `SemanticsWireEncoder` | ~5s | structural (in code) |
| `serve-wire-live` | Live `fleury serve` **socket bytes** (plan + semantics) **+ input→paint latency** (G4): the `input-latency` scenario injects keys closed-loop — starting only after the initial paint **quiesces** — and enforces the structural invariant *every key answered by exactly one PLAN within the per-key timeout* (2s default, flag-tunable). A violated run (missed plan, unsolicited plan, dropped socket) is **discarded and retried**; the gate fails only when every run fails, with the message separating a reproducing input-path break from socket/infra drops. Its latency p50/p95 axes are **warn-only** (live-socket wall-clock), and its byte axes start warn-only too — promote them to gated once run-to-run variance is characterized | `lib/src/remote/**`, `lib/src/serve/**`, plan/wire codec, input dispatch on the served path | ~40s (boots serve) | `profiling/serve_wire_live_baseline.json` |
| `bundle-size` | Served-browser **first-load client** weight (`remote_client.dart.js`, raw + gzip) | `web/remote_client.dart` and its imports | ~2s (no recompile) | generous fixed threshold (512 / 160 KiB) |

## Diagnostics (not gates)

| Tool | Answers | Run |
| --- | --- | --- |
| `alloc-trace` | **Which call sites** produce the per-frame churn `alloc-gate` counts. Drives the same scenario, turns on the VM's per-class allocation tracing, and aggregates the stacks. Use it when the `total` axis goes red: the classes on top are `_List` and `_OneByteString`, which name no owner. Never fails; no baseline. | `dart tool/fleury_dev.dart benchmark alloc-trace [--class=_List,...] [--frames=N]` |

Trigger paths are a guide, not a lockout — if a change plausibly moves a number,
run the gate. When several apply, run them all; they're cheap.

## Baseline & SDK discipline

Baselines live next to the profiling tools (`profiling/*_baseline.json`) and are
committed. Two of the axes are **SDK-sensitive** and will drift if the Dart SDK
changes underneath a baseline:

- **`alloc-gate`** measures heap allocation, which shifts with VM object layout
  and list growth. Re-baseline (`--update-baseline`) after an SDK bump. It runs
  under `--deterministic` (the dev tool passes it): without that flag the
  background JIT can land an allocation-sinking tier mid-window at a
  nondeterministic frame and collapse the number — re-running it by hand
  without the flag can flake where the gate does not.
- **`bundle-size`** measures dart2js output, which drifts a few % per SDK — its
  threshold is deliberately generous to absorb that without flaking.

The **output-byte** gates (`wire-gate`, `serve-wire-live`) and the
**structural** gates (`image-bench`, `serve-semantics-gate`) are SDK-independent
— they measure terminal/socket bytes or invariant ratios, not heap.
(`serve-wire-live`'s input→paint latency axes are machine-dependent wall-clock
and warn-only by design, like `paint-gate`'s µs axes — they never fail the
gate; the structural one-key⟹one-plan invariant is what gates.)
**`paint-gate`'s counter axes are SDK- and machine-independent** (exact widget
fixture → exact per-frame integers); its paint-µs axes are machine-dependent
but warn-only, so they never flake the gate. **`runtime-gate` and
`selection-gate` are likewise counter-only on their gated axes** — frames,
characters, cells and presented bytes are exact functions of the fixture and
the script, so they neither flake nor drift with the SDK. `runtime-gate`
deliberately mutes tickers (`TickerMode(enabled: false)`) in its app subtrees:
a focused editor's caret blink is a real frame source, and a gate whose windows
raced a 500 ms timer would be worthless.

Regenerate a baseline only as a deliberate, reviewed step:

```sh
dart tool/fleury_dev.dart benchmark alloc-gate --update-baseline   # commit the JSON diff
```

## CI status

CI (`.github/workflows/check.yml`) runs `analyze + test + dart2js smoke` and
then the fast gate suite (`dart tool/fleury_dev.dart benchmark gates`):
serve-semantics-gate, image-bench, bundle-size, alloc-gate, input-alloc-gate,
paint-gate,
selection-gate, runtime-gate. A regression on those paths fails CI, not just a
local run. The
CI SDK is pinned (see check.yml), which keeps the SDK-sensitive axes stable:

- **`input-alloc-gate`** covers the axis `alloc-gate` structurally cannot: the
  per-frame gate never presses a key, so the parser, the press-record
  regularizer, the frame latch, and the deepest-first binding walk all sit
  outside its window. Same ±10% headroom and the same SDK-drift caveat. It
  runs the input path in **lifecycle mode** (`KeyboardCapabilities.full`)
  deliberately — under the legacy projection the session keeps no press
  records and the number would flatter us.
- **`alloc-gate`** gates two axes with different bands. `project`
  (`package:fleury` only) is byte-exact on a fixed SDK and keeps ±10% headroom
  for machine drift. `total` (every `dart:` / `package:` class) gets **±3%**,
  because it is the axis that can actually see a dart:core regression and a
  wide band wastes it. Classes with no library (VM-internal JIT artifacts, plus
  closure `Context`s that share that bucket) and `package:vm_service` are
  excluded from both.

  **Why the total axis exists.** The project axis alone is nearly blind: a
  framework frame allocates mostly dart:core — the lists, strings and iterators
  fleury code *creates* but does not *own*. The three fixes this axis shipped
  with moved the gate's scenario 103667 → 93764 B/frame total (−9.6%) while
  moving the project axis −2.4%, comfortably inside its tolerance — i.e. a gate
  watching only the project axis would have called all three nothing. Reverting
  either the width scan or the semantic-anchor pre-scan reads **+4.6% / +5.3%
  on total and +0.0% / +2.5% on project**: red on the new axis, green on the
  old one. On a border-heavy 120×40 dashboard, where box drawing makes the
  width path far hotter, the same fixes cut measured churn ~34%.

  **How the number is measured** (this is what makes ±3% safe rather than
  flaky). The RPC that resets the allocation counters *returns the profile it
  is clearing*, so the client-side JSON decode of that response lands inside
  the next measured window — and its size depends on what the previous window
  accumulated. With one reset the windows alternate by ~10%. The gate therefore
  **resets twice** (the second response covers only the first decode, so it is
  small and history-independent), **discards the first window** as measurement
  warm-up, and reports the **median of 5** further windows. Six consecutive
  runs against a fresh baseline then spanned −0.2% to +1.2% (the high end
  on a loaded machine) — ~2.5× headroom over the ±3% band, against regressions
  that read +4.6% and +5.3%. Do not widen the band without re-measuring both
  ends: at 4% the width-scan regression is only 0.6pp from passing.

  Two caveats worth knowing. One profile-response decode (~15 kB/frame at this
  window size) is still allocated inside every window and cannot be separated
  from the frame's churn by class, so the absolute number is inflated and
  relative deltas are damped ~15%. Read `total` as a regression detector
  against a baseline measured the same way, not as the absolute cost of a
  frame. And the gate's fixture is a plain-text dashboard: it under-represents
  box drawing, so it understates changes to the width path.

  If a deliberate SDK bump moves either axis past tolerance, re-baseline in the
  bump commit — never loosen the tolerance.
- **`paint-gate`**'s gated axes are exact counters (machine- and
  SDK-independent); its µs axes are warn-only by design.
- **`selection-gate`** gates exact counters (drag / select-all characters and
  cells, machine- and SDK-independent, tolerance 0); its per-frame µs cost is
  warn-only, for the same reason as paint-gate's µs — and because this path's
  allocation is JIT-sink-nondeterministic, so it is surfaced, never gated. It
  drives a real `SelectionArea` through real input: a gate that pokes the
  delegate directly stays green through every gesture, anchor, binding and
  clipboard defect (which is exactly what happened — see the launch audit's
  D3).
- **`runtime-gate`** covers the axis every other gate structurally cannot:
  nothing else runs `runApp` → `FrameDriver` → present, so a frame the runtime
  OWES and never schedules, a frame nothing needed, or a frame count that grows
  with the input rather than the change is invisible to a fully green board.
  Two P1s shipped that way and are now fixtures. Its counters are exact and
  machine-independent; it boots real apps, so it is the slowest member of the
  fast suite.
- **`bundle-size`**'s threshold is deliberately generous to absorb dart2js
  drift across SDK bumps.

The heavier PTY/subprocess gates (`wire-gate`, `serve-wire-live`) stay out of
CI — run them on demand when you touch their paths (a pre-release / nightly
cadence for them is tracked separately).
