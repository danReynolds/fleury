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
bundle-size, alloc-gate, paint-gate — ~10s, with a pass/fail summary):

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
| `paint-gate` | Paint-walk pruning as **exact repaint-boundary counters**: ListView auto-boundaries prune a localized update to one repaint; Overlay entry boundaries engage adaptively; the **lazy-layer convention** (an idle app — Toaster mounted, zero toasts — is pure pass-through: `boundaryCount == 0`); full-invalidate staleness (`cached == 0` when everything is dirty). Paint-phase µs is recorded warn-only, never fails | `lib/src/rendering/**` (esp. `render_repaint_boundary.dart`, cell paint), `lib/src/widgets/overlay.dart`, `lib/src/widgets/list_view.dart`, any widget that mounts overlay entries (toasts, banners, dropdowns) | ~5s | `profiling/paint_gate_baseline.json` (counters exact, tolerance 0; structural invariants also enforced in-code, even under `--update-baseline`) |
| `image-bench` | Inline-image encoder: **dedup** (0 B/frame static) + **zero-image fast path** (0 B) | `lib/src/terminal/terminal_image_encoder.dart`, `ansi_byte_budget.dart` image category | ~5s | structural (in code) |
| `serve-semantics-gate` | Semantics wire **anti-cliff**: diff stays flat in tree size (never falls off the 32 KiB DEFLATE cliff) | `lib/src/remote/remote_semantics.dart`, `SemanticsWireEncoder` | ~5s | structural (in code) |
| `serve-wire-live` | Live `fleury serve` **socket bytes** (plan + semantics), real serve subprocess + WS client | `lib/src/remote/**`, `lib/src/serve/**`, plan/wire codec | ~30s (boots serve) | `profiling/serve_wire_live_baseline.json` |
| `bundle-size` | Served-browser **first-load client** weight (`remote_client.dart.js`, raw + gzip) | `web/remote_client.dart` and its imports | ~2s (no recompile) | generous fixed threshold (512 / 160 KiB) |

Trigger paths are a guide, not a lockout — if a change plausibly moves a number,
run the gate. When several apply, run them all; they're cheap.

## Baseline & SDK discipline

Baselines live next to the profiling tools (`profiling/*_baseline.json`) and are
committed. Two of the axes are **SDK-sensitive** and will drift if the Dart SDK
changes underneath a baseline:

- **`alloc-gate`** measures heap allocation, which shifts with VM object layout
  and list growth. Re-baseline (`--update-baseline`) after an SDK bump.
- **`bundle-size`** measures dart2js output, which drifts a few % per SDK — its
  threshold is deliberately generous to absorb that without flaking.

The **output-byte** gates (`wire-gate`, `serve-wire-live`) and the
**structural** gates (`image-bench`, `serve-semantics-gate`) are SDK-independent
— they measure terminal/socket bytes or invariant ratios, not heap.
**`paint-gate`'s counter axes are SDK- and machine-independent** (exact widget
fixture → exact per-frame integers); its paint-µs axes are machine-dependent
but warn-only, so they never flake the gate.

Regenerate a baseline only as a deliberate, reviewed step:

```sh
dart tool/fleury_dev.dart benchmark alloc-gate --update-baseline   # commit the JSON diff
```

## CI status

Today CI (`.github/workflows/check.yml`) runs `analyze + test + dart2js smoke`
and **no perf gates** — these are run locally, on demand, by whoever (human or
agent) touches a gated path. See the repo `CLAUDE.md` "Performance gates"
section, which points agents here.

Wiring gates into CI is tracked separately; the blocker is that CI pins
`sdk: stable` (floating), so an SDK bump would flake the SDK-sensitive gates
(and already flakes `remote_client_asset_test`). The intended sequence: pin the
CI SDK → add a `perf-gates` job running the fast/deterministic gates
(`serve-semantics-gate`, `image-bench --gate`, `bundle-size --gate`,
`paint-gate --gate` — SDK-safe already, its gated axes are exact counters —
then `alloc-gate --gate` once the SDK is pinned) → keep the heavier
PTY/subprocess gates (`wire-gate`, `serve-wire-live`) on a pre-release or
nightly cadence.
