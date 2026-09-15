# Fleury profiling comparison

Status: **complete**. Lower timing is better. All timings are microseconds; these are not physical display latencies.

Sources: `{"baseline":"46c6e780a632dd88f7b6d828e33232f1845937ae","candidate":"46c6e780a632dd88f7b6d828e33232f1845937ae"}`

The interval resamples paired fresh-process summaries. It is exploratory evidence from this machine/session. Many metrics are reported without a multiple-comparison correction; reproduce interesting changes in a targeted run before making a performance claim. Change is computed within each pair, not from the two displayed medians.

| Scenario | Metric | Baseline median | Candidate median | Paired change | 95% interval | Assessment |
|---|---|---:|---:|---:|---|---|
| panes-40 | p50 | 46.0 | 48.0 | 2.1% | 0.0% to 4.3% | no clear change |
| panes-40 | p95 | 60.1 | 57.0 | -1.8% | -15.5% to 4.1% | no clear change |
| resize | p50 | 254.5 | 254.0 | 0.0% | -1.0% to 0.6% | no clear change |
| resize | p95 | 377.2 | 369.1 | -3.5% | -8.2% to 6.3% | no clear change |
| typing | p50 | 221.0 | 222.0 | 0.5% | -3.1% to 1.8% | no clear change |
| typing | p95 | 345.5 | 343.1 | -0.7% | -3.9% to 8.6% | no clear change |
| list | p50 | 1013.5 | 1022.0 | 0.8% | -1.0% to 1.0% | no clear change |
| list | p95 | 1269.0 | 1271.9 | 0.3% | -1.1% to 1.2% | no clear change |
| burst | p50 | 2133.0 | 2129.5 | 0.7% | -1.3% to 1.8% | no clear change |
| burst | p95 | 2515.2 | 2526.0 | -0.3% | -2.5% to 3.7% | no clear change |
| slow-output | p50 | 50.0 | 50.0 | 0.0% | -3.8% to 2.0% | no clear change |
| slow-output | p95 | 106.0 | 85.0 | -20.0% | -40.5% to 16.4% | no clear change |

Phase timings, all per-process summaries, p99, and raw input/frame samples are in report.json and runs/. Output counts, encoded bytes, batch drain times, correctness checks and process RSS are preserved per run. A slow-output dispatch checkpoint can precede output drain; inspect both.
