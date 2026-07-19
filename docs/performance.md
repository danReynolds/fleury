# Performance

For Fleury, "performance" means keeping work proportional to the change the app
made, not to the size of the whole screen or dataset. A dashboard tick should
not repaint the app shell. A row selection should not rebuild a hundred-thousand
rows. An idle app should not write bytes.

This page describes that contract, then points to the benchmarks that check
whether the implementation is still honoring it.

## The contract

Fleury's performance model has five practical promises:

| Promise | What should happen |
| --- | --- |
| Dirty work stays local | `setState` marks one part of the retained tree dirty; unrelated widgets, layout, and paint are reused. |
| Output is damage-based | The terminal target writes changed cells as ANSI. The browser target applies changed cell ranges or DOM patches. |
| Large data is virtualized | Tables, trees, and lists bind the visible window instead of rebuilding the full dataset. |
| Streaming work stays scoped | Logs and subprocess output append incrementally. Markdown currently reparses the accumulated document on each append, while retained updates and damage-based output keep unrelated regions out of the frame work. |
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
| Streaming text | Whether logs and subprocess output append cheaply, and whether Markdown's current full-document parse-on-append remains inside its explicit workload budget without broad repaint work. |
| Update cadence | Whether many independent widgets can tick without broad redraws. |
| Layout and resize churn | Whether Fleury recomputes only affected layout regions and recovers cleanly from terminal resizes. |
| App-shell churn | Whether overlays, command palettes, focus restoration, and transient UI creation stay cheap. |
| Wire and process cost | How many bytes, frames, CPU, and RSS a real terminal run consumes. |

The full scenario matrix and peer target rationale live in the
[benchmark index](https://github.com/danReynolds/fleury/blob/main/benchmarks/README.md).

## Driving an agent stays cheap, too

The same discipline carries to the [MCP agent surface](/guides/driving-with-agents/).
Reads are bounded — `get_ui` and every action result are node-capped and
token-trimmed, so a large screen can't blow an agent's context. Change delivery is
incremental: a host that subscribes to the tree gets a **delta** — only the
changed node ids — when the UI settles, ~0.3% of a full re-read on a busy
dashboard. Id→node lookup is O(1) per revision (~477× vs a full tree walk), and
the settle behind `wait_for_change` is capped so a continuously-animating app
returns promptly (~3.7× faster than running to its timeout). A committed benchmark
and a perf gate hold these numbers against regression.

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
