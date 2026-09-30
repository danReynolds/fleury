# Performance

Fleury reduces rebuilds, virtualizes large datasets, and emits only changed
cells. A row selection should not rebuild a hundred-thousand rows, and an idle
app should not write bytes. A visual frame still paints a complete back buffer
and compares it with the previous frame; culling and repaint caches reduce the
work inside that paint pass.

This page describes those boundaries and the benchmarks that check them.

## The contract

Fleury's performance model has five practical goals:

| Promise | What should happen |
| --- | --- |
| Build and layout work are retained | `setState` queues dirty elements; clean builds and unchanged layout can be reused. Painting starts at the root, with culling and explicit repaint caches. |
| Output is damage-based | The terminal target writes changed cells as ANSI. The browser target applies changed cell ranges or DOM patches. |
| Large data is virtualized | Tables, trees, and lists bind the visible window instead of rebuilding the full dataset. |
| Streaming work stays scoped | Logs and subprocess output append incrementally. Markdown reuses complete parsed lines and reparses the appended tail; source replacements or parser-option changes rebuild the parse. |
| Idle is quiet | If nothing changed, Fleury should schedule no meaningful work and emit no frame output. |

Those promises come from the same architecture described in
[Overview](/architecture/overview/) and
[Architecture deep dive](/architecture/deep-dive/): a retained
widget/element/render/semantics pipeline that paints into a cell grid, then
hands changed cells to the active target.

## What the benchmarks protect

The benchmark suite is organized around the places terminal apps usually get
expensive:

| Concern | What it tells us |
| --- | --- |
| Startup and first paint | How much runtime overhead every app pays before the UI gets interesting. |
| Input latency | Whether text fields, paste, cursor movement, completions, and command entry stay responsive. |
| Large data navigation | Whether tables and trees stay tied to the virtualized visible window instead of dataset size. |
| Streaming text | Whether log, subprocess, and Markdown appends stay within their workload budgets, including parsing, layout, paint, and output. |
| Update cadence | Whether many independent widgets can tick without broad redraws. |
| Layout and resize churn | Whether Fleury recomputes only affected layout regions and recovers cleanly from terminal resizes. |
| App-shell churn | Whether overlays, command palettes, focus restoration, and transient UI creation stay cheap. |
| Wire and process cost | How many bytes, frames, CPU, and RSS a real terminal run consumes. |

The full scenario matrix and peer target rationale live in the
[benchmark index](https://github.com/danReynolds/fleury/blob/main/benchmarks/README.md).

## Driving an agent stays cheap, too

The same discipline carries to the [MCP agent surface](/guides/driving-with-agents/).
Reads are bounded: `get_ui` and action results use node and token budgets.
Id-to-node lookup uses a cached index for each tree revision, and
`wait_for_change` caps settling so an animating app can return without running
to its timeout. Legacy `2025-06-18` clients can subscribe to compact tree deltas;
current clients use revision-based `wait_for_change` because Fleury does not yet
advertise modern MCP streaming subscriptions.

The [June 29, 2026 baseline](https://github.com/danReynolds/fleury/blob/main/packages/fleury_mcp/benchmark/BASELINE.md)
measured a delta at about 0.3% of a full re-read, indexed lookup at about 477×
faster than a tree walk, and capped settling at about 3.7× faster than uncapped
settling on its 80-row fixture. Those are recorded measurements, not guarantees
for every app. CI enforces the baseline's stated thresholds, which allow timing
variance and do not require reproducing those exact speedups.

## How to inspect it

From a Fleury framework checkout:

```sh
fleury benchmark list
fleury benchmark local SB.6 --warmup=1 --iterations=3 --json
fleury benchmark profile SB.6 --warmup=1 --iterations=5
fleury benchmark wire sb6 --runs=3
fleury benchmark manifest --json
```

Use `local` runs to inspect Fleury's own frame, CPU, and memory behavior. Use
`profile` when a scenario needs VM service CPU or allocation detail. Use `wire`
runs when the question includes the terminal boundary: bytes written, frames
emitted, time to first byte, CPU, RSS, and peer fixtures under a real PTY.

## What results are for

Benchmark output should make the next engineering question clearer. Local and
profile runs show whether Fleury's own pipeline is staying proportional to the
change; wire runs, what happens at the terminal boundary; peer fixture runs, how
the same scenario behaves when expressed with other frameworks' natural APIs.

For durable comparisons, keep the fixture shape, terminal, machine, framework
versions, and repeated-run variance beside the result. That context makes the
captures useful for regression review, fixture-shape review, runtime-floor
analysis, and follow-up profiling.

The checked-in evidence supports a narrower claim than "fastest TUI
framework": Fleury keeps interactive work responsive and is competitive on
many matched terminal-wire workloads. Native peers retain an inherent startup
and RSS floor advantage, and a public cross-framework ranking requires fresh
peer versions, bare-metal repeated runs, and equivalent fixture shapes.
