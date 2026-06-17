# Fleury Web Threshold Review Plan

- Input: `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json`
- Input fingerprint: `fnv1a64:5e05148220c729cd`
- Review state: `candidate`
- Scenario count: `11`
- Candidate generated at: `2026-06-09T12:34:03.738655Z`
- Capture run count: `33`
- Source metric: `maxCaptureP95PerScenario`
- Threshold headroom: `20.0%`, minimum `1.0ms`
- Capture input: `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh`
- Review context hint: `Browser Chrome/148.0.7778.217, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline`

## Review Checklist

- Confirm the capture input represents the agreed product/browser configuration.
- Confirm every release scenario has an explicit threshold entry.
- Inspect total-frame thresholds separately from DOM and semantic apply thresholds.
- Check runtime build/layout/paint subphase availability before using this review to choose a Dart-side optimization path.
- Check over-budget thresholds for scenarios with intentionally slow frames.
- Confirm semantic uncovered-cell thresholds remain zero unless an accessibility exception is reviewed.
- Record reviewer, timestamp, and product/browser context before promotion.

## Runtime Subphase Timing Availability

Runtime build/layout/paint subphase samples are unavailable for 11 of 11 scenarios. This policy still gates total frame, DOM apply, and semantic apply thresholds, but it should not be used to decide whether Dart work is build-, layout-, or paint-bound for scenarios without subphase samples. Regenerate captures with runtime subphase timing before making that optimization call.

| Scenario | Build | Layout | Paint |
| --- | --- | --- | --- |
| cursor-blink-80x24 | missing | missing | missing |
| dirty-row-160x50 | missing | missing | missing |
| full-frame-churn-160x50 | missing | missing | missing |
| large-160x50 | missing | missing | missing |
| noop-160x50 | missing | missing | missing |
| normal-80x24 | missing | missing | missing |
| resize-burst | missing | missing | missing |
| scroll-row-churn-160x50 | missing | missing | missing |
| single-dirty-cell-160x50 | missing | missing | missing |
| stress-300x100 | missing | missing | missing |
| text-input-burst-80x24 | missing | missing | missing |

## Scenario Thresholds

| Scenario | Frames / steps | Extra frames | Max frames/step | Total frame p95 ms | DOM apply p95 ms | Semantic apply p95 ms | Over budget % | Semantic uncovered cells |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| cursor-blink-80x24 | 72 / 72 | 0 | 1.0 | 1078.2 | 31.68 | 285.72 | 100.0 | 0 |
| dirty-row-160x50 | 96 / 96 | 0 | 1.0 | 864.97 | 30.0 | 374.16 | 97.5 | 0 |
| full-frame-churn-160x50 | 72 / 72 | 0 | 1.0 | 2692.08 | 41.52 | 1379.17 | 100.0 | 0 |
| large-160x50 | 96 / 96 | 0 | 1.0 | 499.69 | 18.48 | 232.08 | 100.0 | 0 |
| noop-160x50 | 72 / 72 | 0 | 1.0 | 87.84 | 1.1 | 17.16 | 35.0 | 0 |
| normal-80x24 | 72 / 72 | 0 | 1.0 | 466.56 | 23.28 | 177.6 | 95.0 | 0 |
| resize-burst | 72 / 36 | 36 | 2.0 | 949.92 | 49.09 | 444.6 | 100.0 | 0 |
| scroll-row-churn-160x50 | 96 / 96 | 0 | 1.0 | 2411.65 | 207.96 | 656.28 | 100.0 | 0 |
| single-dirty-cell-160x50 | 96 / 96 | 0 | 1.0 | 285.48 | 15.72 | 166.68 | 100.0 | 0 |
| stress-300x100 | 48 / 48 | 0 | 1.0 | 3578.64 | 273.97 | 1559.16 | 100.0 | 0 |
| text-input-burst-80x24 | 120 / 60 | 60 | 2.0 | 408.85 | 19.44 | 119.4 | 87.0 | 0 |

## Over-Budget Thresholds

This candidate permits over-budget frames in 11 scenarios. Promotion requires `--allow-over-budget-thresholds` and a concrete `--review-note=TEXT` that explains why those thresholds are acceptable for this reviewed baseline.

| Scenario | Extra frames | Max frames/step | Total frame p95 ms | Over budget % |
| --- | ---: | ---: | ---: | ---: |
| cursor-blink-80x24 | 0 | 1.0 | 1078.2 | 100.0 |
| dirty-row-160x50 | 0 | 1.0 | 864.97 | 97.5 |
| full-frame-churn-160x50 | 0 | 1.0 | 2692.08 | 100.0 |
| large-160x50 | 0 | 1.0 | 499.69 | 100.0 |
| noop-160x50 | 0 | 1.0 | 87.84 | 35.0 |
| normal-80x24 | 0 | 1.0 | 466.56 | 95.0 |
| resize-burst | 36 | 2.0 | 949.92 | 100.0 |
| scroll-row-churn-160x50 | 0 | 1.0 | 2411.65 | 100.0 |
| single-dirty-cell-160x50 | 0 | 1.0 | 285.48 | 100.0 |
| stress-300x100 | 0 | 1.0 | 3578.64 | 100.0 |
| text-input-burst-80x24 | 60 | 2.0 | 408.85 | 87.0 |

## Promotion Command

This command is intentionally not runnable as written: replace the reviewer placeholder and any generic browser/platform values before promotion.

```sh
dart run tool/web_threshold_review.dart \
  --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json \
  --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.json \
  --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review.json \
  --expect-input-fingerprint=fnv1a64:5e05148220c729cd \
  '--reviewed-by=<reviewer>' \
  '--review-context=Browser Chrome/148.0.7778.217, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline' \
  --allow-over-budget-thresholds \
  '--review-note=<why these over-budget thresholds are acceptable for this reviewed baseline>'
```
