# Fleury Web Threshold Review Plan

- Input: `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/thresholds.candidate.json`
- Input fingerprint: `fnv1a64:31221901e96a24c3`
- Review state: `candidate`
- Scenario count: `11`
- Candidate generated at: `2026-06-10T02:55:47.425036Z`
- Capture run count: `33`
- Source metric: `maxCaptureP95PerScenario`
- Threshold headroom: `20.0%`, minimum `1.0ms`
- Capture input: `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened`
- Review context hint: `Browser Chrome/149.0.7827.102, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline`

## Review Checklist

- Confirm the capture input represents the agreed product/browser configuration.
- Confirm every release scenario has an explicit threshold entry.
- Inspect total-frame thresholds separately from DOM and semantic apply thresholds.
- Check runtime build/layout/paint subphase availability before using this review to choose a Dart-side optimization path.
- Check over-budget thresholds for scenarios with intentionally slow frames.
- Confirm semantic uncovered-cell thresholds remain zero unless an accessibility exception is reviewed.
- Record reviewer, timestamp, and product/browser context before promotion.

## Scenario Thresholds

| Scenario | Frames / steps | Extra frames | Max frames/step | Total frame p95 ms | DOM apply p95 ms | Semantic apply p95 ms | Over budget % | Semantic uncovered cells |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| cursor-blink-80x24 | 72 / 72 | 0 | 1.0 | 141.84 | 15.96 | 46.32 | 70.0 | 0 |
| dirty-row-160x50 | 96 / 96 | 0 | 1.0 | 74.4 | 2.9 | 42.96 | 22.5 | 0 |
| full-frame-churn-160x50 | 72 / 72 | 0 | 1.0 | 1200.84 | 79.93 | 177.84 | 95.0 | 0 |
| large-160x50 | 96 / 96 | 0 | 1.0 | 68.28 | 2.1 | 37.8 | 26.25 | 0 |
| noop-160x50 | 72 / 72 | 0 | 1.0 | 40.2 | 5.1 | 1.1 | 15.0 | 0 |
| normal-80x24 | 72 / 72 | 0 | 1.0 | 394.56 | 38.52 | 202.56 | 100.0 | 0 |
| resize-burst | 72 / 36 | 36 | 2.0 | 1319.64 | 43.56 | 365.16 | 100.0 | 0 |
| scroll-row-churn-160x50 | 96 / 96 | 0 | 1.0 | 759.6 | 41.04 | 123.12 | 100.0 | 0 |
| single-dirty-cell-160x50 | 96 / 96 | 0 | 1.0 | 77.16 | 2.6 | 19.08 | 30.0 | 0 |
| stress-300x100 | 48 / 48 | 0 | 1.0 | 1686.0 | 148.08 | 397.92 | 100.0 | 0 |
| text-input-burst-80x24 | 120 / 60 | 60 | 2.0 | 204.84 | 13.33 | 70.56 | 57.0 | 0 |

## Over-Budget Thresholds

This candidate permits over-budget frames in 11 scenarios. Promotion requires `--allow-over-budget-thresholds` and a concrete `--review-note=TEXT` that explains why those thresholds are acceptable for this reviewed baseline.

| Scenario | Extra frames | Max frames/step | Total frame p95 ms | Over budget % |
| --- | ---: | ---: | ---: | ---: |
| cursor-blink-80x24 | 0 | 1.0 | 141.84 | 70.0 |
| dirty-row-160x50 | 0 | 1.0 | 74.4 | 22.5 |
| full-frame-churn-160x50 | 0 | 1.0 | 1200.84 | 95.0 |
| large-160x50 | 0 | 1.0 | 68.28 | 26.25 |
| noop-160x50 | 0 | 1.0 | 40.2 | 15.0 |
| normal-80x24 | 0 | 1.0 | 394.56 | 100.0 |
| resize-burst | 36 | 2.0 | 1319.64 | 100.0 |
| scroll-row-churn-160x50 | 0 | 1.0 | 759.6 | 100.0 |
| single-dirty-cell-160x50 | 0 | 1.0 | 77.16 | 30.0 |
| stress-300x100 | 0 | 1.0 | 1686.0 | 100.0 |
| text-input-burst-80x24 | 60 | 2.0 | 204.84 | 57.0 |

## Promotion Command

This command is intentionally not runnable as written: replace the reviewer placeholder and any generic browser/platform values before promotion.

```sh
dart run tool/web_threshold_review.dart \
  --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/thresholds.candidate.json \
  --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/thresholds.json \
  --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/threshold-review.json \
  --expect-input-fingerprint=fnv1a64:31221901e96a24c3 \
  '--reviewed-by=<reviewer>' \
  '--review-context=Browser Chrome/149.0.7827.102, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline' \
  --allow-over-budget-thresholds \
  '--review-note=<why these over-budget thresholds are acceptable for this reviewed baseline>'
```
