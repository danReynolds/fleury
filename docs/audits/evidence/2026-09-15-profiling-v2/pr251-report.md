# Fleury profiling comparison

Status: **complete**. Lower timing is better. All timings are microseconds; these are not physical display latencies.

Sources: `{"baseline":"46c6e780a632dd88f7b6d828e33232f1845937ae","candidate":"2d44578c247e3de29ab742d518d7887b113bf8b7"}`

The interval resamples paired fresh-process summaries. It is exploratory evidence from this machine/session. Many metrics are reported without a multiple-comparison correction; reproduce interesting changes in a targeted run before making a performance claim. Change is computed within each pair, not from the two displayed medians.

| Scenario | Metric | Baseline median | Candidate median | Paired change | 95% interval | Assessment |
|---|---|---:|---:|---:|---|---|
| panes-16 | p50 | 29.0 | 29.0 | 0.0% | -3.3% to 0.0% | no clear change |
| panes-16 | p95 | 37.2 | 43.1 | 4.9% | -18.8% to 42.2% | no clear change |
| panes-40 | p50 | 46.0 | 46.0 | -2.1% | -2.2% to 2.2% | no clear change |
| panes-40 | p95 | 55.1 | 55.1 | -1.9% | -10.6% to 25.2% | no clear change |
| panes-96 | p50 | 82.0 | 82.0 | -1.2% | -2.4% to 2.4% | no clear change |
| panes-96 | p95 | 104.0 | 102.1 | -5.0% | -10.6% to 18.9% | no clear change |
| dashboard-leaf | p50 | 113.0 | 112.0 | 0.0% | -0.9% to 0.0% | no clear change |
| dashboard-leaf | p95 | 140.2 | 137.3 | -1.6% | -42.6% to 6.3% | no clear change |
| editor-leaf | p50 | 57.0 | 57.0 | 0.0% | -1.7% to 0.0% | no clear change |
| editor-leaf | p95 | 76.1 | 75.0 | -1.4% | -7.6% to 1.4% | no clear change |
| resize | p50 | 255.0 | 255.0 | -0.4% | -1.2% to 0.8% | no clear change |
| resize | p95 | 392.5 | 378.9 | -4.4% | -6.2% to 1.5% | no clear change |
| typing | p50 | 222.0 | 223.0 | 0.5% | -0.4% to 2.3% | no clear change |
| typing | p95 | 358.2 | 362.1 | -1.7% | -3.1% to 10.6% | no clear change |
| list | p50 | 1017.0 | 1034.0 | 2.0% | -1.0% to 3.0% | no clear change |
| list | p95 | 1269.2 | 1286.2 | 2.8% | -1.5% to 4.8% | no clear change |
| paste | p50 | 697.5 | 694.0 | -0.5% | -2.0% to 0.0% | no clear change |
| paste | p95 | 852.0 | 864.2 | 1.1% | -0.5% to 3.6% | no clear change |
| burst | p50 | 2125.0 | 2140.0 | -0.2% | -0.8% to 2.0% | no clear change |
| burst | p95 | 2512.3 | 2546.1 | 1.6% | -3.0% to 2.8% | no clear change |
| slow-output | p50 | 50.0 | 50.0 | 2.0% | -2.0% to 4.2% | no clear change |
| slow-output | p95 | 79.1 | 72.0 | -8.9% | -30.8% to 17.7% | no clear change |

Phase timings, all per-process summaries, p99, and raw input/frame samples are in report.json and runs/. Output counts, encoded bytes, batch drain times, correctness checks and process RSS are preserved per run. A slow-output dispatch checkpoint can precede output drain; inspect both.
