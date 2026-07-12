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
bundle-size, alloc-gate, paint-gate — ~11s measured, with a pass/fail
summary); CI runs this same suite on every push/PR:

```sh
dart tool/fleury_dev.dart benchmark gates
```

The heavier PTY/subprocess gates (`wire-gate`, `serve-wire-live`) are not in the
`gates` suite — run them explicitly when you touch their paths.

## The gates

| Gate | Protects | When to run (trigger) | Speed | Baseline |
| --- | --- | --- | --- | --- |
| `wire-gate` | Terminal ANSI **output bytes** (SB.1/6/9: startup, dashboard steady-state, untrusted-output encoding) | `lib/src/rendering/ansi_renderer.dart`, cell paint, any diff/cursor/SGR change | ~30s (PTY) | `profiling/wire_gate_baseline.json` |
| `alloc-gate` | Per-frame **`package:fleury` allocation churn** (build → reconcile → layout → paint → diff) | `lib/src/widgets/framework.dart`, `lib/src/rendering/**`, anything on the per-frame path | ~10s (VM service) | `profiling/alloc_gate_baseline.json` |
| `paint-gate` | Paint-walk pruning as **exact repaint-boundary counters**: the real `ListView.builder`'s auto-boundaries prune a localized update to one repaint; Overlay entry boundaries engage adaptively (dashboard+floater fixtures — real leaf widgets in bespoke two-entry scaffolding); the **lazy-layer convention** (the real `Toaster` with zero toasts idles pure pass-through: `boundaryCount == 0`); full-invalidate staleness (`cached == 0` when everything is dirty). Paint-phase µs is recorded warn-only (measured with debug stats on — not a clean paint time) and never fails | `lib/src/rendering/**` (esp. `render_repaint_boundary.dart`, cell paint), `lib/src/widgets/overlay.dart`, `lib/src/widgets/list_view.dart`, any widget that mounts overlay entries (toasts, banners, dropdowns) | ~4s (dart-run startup dominates; the measurement is <0.5s) | `profiling/paint_gate_baseline.json` (counters exact, tolerance 0; structural invariants also enforced in-code, even under `--update-baseline`) |
| `image-bench` | Inline-image encoder: **dedup** (0 B/frame static) + **zero-image fast path** (0 B) | `lib/src/terminal/terminal_image_encoder.dart`, `ansi_byte_budget.dart` image category | ~5s | structural (in code) |
| `serve-semantics-gate` | Semantics wire **anti-cliff**: diff stays flat in tree size (never falls off the 32 KiB DEFLATE cliff) | `lib/src/remote/remote_semantics.dart`, `SemanticsWireEncoder` | ~5s | structural (in code) |
| `serve-wire-live` | Live `fleury serve` **socket bytes** (plan + semantics) **+ input→paint latency** (G4): the `input-latency` scenario injects keys closed-loop — starting only after the initial paint **quiesces** — and enforces the structural invariant *every key answered by exactly one PLAN within the per-key timeout* (2s default, flag-tunable). A violated run (missed plan, unsolicited plan, dropped socket) is **discarded and retried**; the gate fails only when every run fails, with the message separating a reproducing input-path break from socket/infra drops. Its latency p50/p95 axes are **warn-only** (live-socket wall-clock), and its byte axes start warn-only too — promote them to gated once run-to-run variance is characterized | `lib/src/remote/**`, `lib/src/serve/**`, plan/wire codec, input dispatch on the served path | ~40s (boots serve) | `profiling/serve_wire_live_baseline.json` |
| `bundle-size` | Served-browser **first-load client** weight (`remote_client.dart.js`, raw + gzip) | `web/remote_client.dart` and its imports | ~2s (no recompile) | generous fixed threshold (512 / 160 KiB) |

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
but warn-only, so they never flake the gate.

Regenerate a baseline only as a deliberate, reviewed step:

```sh
dart tool/fleury_dev.dart benchmark alloc-gate --update-baseline   # commit the JSON diff
```

## CI status

CI (`.github/workflows/check.yml`) runs `analyze + test + dart2js smoke` and
then the fast gate suite (`dart tool/fleury_dev.dart benchmark gates`):
serve-semantics-gate, image-bench, bundle-size, alloc-gate, paint-gate. A
regression on those paths fails CI, not just a local run. The CI SDK is
pinned (see check.yml), which keeps the SDK-sensitive axes stable:

- **`alloc-gate`** has ±10% headroom for machine drift on a fixed SDK. If a
  deliberate SDK bump moves it past tolerance, re-baseline in the bump
  commit — never loosen the tolerance.
- **`paint-gate`**'s gated axes are exact counters (machine- and
  SDK-independent); its µs axes are warn-only by design.
- **`bundle-size`**'s threshold is deliberately generous to absorb dart2js
  drift across SDK bumps.

The heavier PTY/subprocess gates (`wire-gate`, `serve-wire-live`) stay out of
CI — run them on demand when you touch their paths (a pre-release / nightly
cadence for them is tracked separately).
