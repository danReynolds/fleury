# Performance

Fleury is built to stay cheap as apps get busy. The performance story is
architectural — a few decisions in the core — rather than micro-optimizations
bolted on after the fact.

## Retained mode, incremental everything

Many terminal UIs are immediate-mode: every frame, your code re-describes the
whole screen and the framework redraws it. Fleury keeps a *retained* tree —
widgets, elements, and render objects. A `setState` marks one subtree
dirty; only that path rebuilds, re-lays-out, and re-paints. The rest of the tree
is reused untouched. A button label changing doesn't re-lay-out the table next
to it.

## Diff to the cells, not the screen

Layout and paint produce a grid of cells. The terminal target diffs the new grid
against the previous one and emits **only the cells that changed** as ANSI — no
full repaints. A frame with no changes emits nothing at all, so an idle app
costs nothing, and a busy app pays only for what actually moved.

## Data widgets are windowed

The data widgets — `DataTable`, `TreeTable`, lists — build only the rows that
are actually on screen. A hundred-thousand-row table costs about what a
screenful costs; scrolling rebinds the visible window instead of rebuilding the
dataset. Large, text-shaped data is a first-class case, not a cliff.

## The browser wire is a patch stream

When you stream an app to a browser with [`fleury serve`](/architecture/serving-and-embedding/),
the server doesn't ship repaints. Each frame is encoded as compact **cell-range
patches** against a shared style table, varint-packed, so a live, churning app
stays small over a socket. The [semantics tree](/architecture/agents-and-semantics/)
rides the same wire.

## Measured against peers, not asserted

Fleury is benchmarked against current releases of the frameworks people actually
reach for using scenario harnesses, not a synthetic leaderboard. The benchmark
matrix covers the conventional pressure points for terminal apps: startup and
first paint, input latency, large data navigation, streaming logs and Markdown,
dashboard update cadence, layout invalidation, resize churn, command-palette
churn, process output, wire bytes, CPU, and RSS. Peer comparisons are run from
matching source fixtures and need fixture parity plus repeated hardware runs
before they support public superiority claims.

## How to inspect it

The public docs intentionally describe the model and measurement surface rather
than publishing a static "faster than X" table. From a Fleury framework checkout:

```sh
fleury benchmark list
fleury benchmark local SB.6 --warmup=1 --iterations=3 --json
fleury benchmark wire sb6 --runs=3
fleury benchmark manifest --json
```

Use `fleury benchmark list` for the current scenario catalog, `local` runs for
Fleury-only CPU/RSS/frame-cost work, and `wire` runs for real-PTY peer fixtures.
The full scenario matrix and peer target rationale live in the
[benchmark index](https://github.com/danReynolds/fleury/blob/main/benchmarks/README.md).
Treat peer numbers as publishable only when the fixture shape, terminal, machine,
and repeated-run variance are all documented beside the result.

The framework also ships a built-in profiling surface, so you can inspect
rebuild, layout, paint, and frame costs in your own app.
