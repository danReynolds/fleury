# Fleury Web Threshold Review Plan

- Input: `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json`
- Input fingerprint: `fnv1a64:e0d3572d6b421cf7`
- Review state: `candidate`
- Scenario count: `11`
- Candidate generated at: `2026-06-09T14:25:45.901379Z`
- Capture run count: `33`
- Source metric: `maxCaptureP95PerScenario`
- Threshold headroom: `20.0%`, minimum `1.0ms`
- Capture input: `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh`
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
| cursor-blink-80x24 | 72 / 72 | 0 | 1.0 | 525.6 | 10.8 | 136.56 | 100.0 | 0 |
| dirty-row-160x50 | 96 / 96 | 0 | 1.0 | 460.2 | 2.5 | 456.0 | 78.75 | 0 |
| full-frame-churn-160x50 | 72 / 72 | 0 | 1.0 | 883.56 | 37.45 | 209.88 | 100.0 | 0 |
| large-160x50 | 96 / 96 | 0 | 1.0 | 363.6 | 10.68 | 234.48 | 86.25 | 0 |
| noop-160x50 | 72 / 72 | 0 | 1.0 | 127.2 | 1.11 | 24.73 | 25.0 | 0 |
| normal-80x24 | 72 / 72 | 0 | 1.0 | 198.96 | 12.6 | 127.33 | 75.0 | 0 |
| resize-burst | 72 / 36 | 36 | 2.0 | 527.64 | 30.84 | 124.68 | 100.0 | 0 |
| scroll-row-churn-160x50 | 96 / 96 | 0 | 1.0 | 1135.8 | 44.65 | 858.0 | 100.0 | 0 |
| single-dirty-cell-160x50 | 96 / 96 | 0 | 1.0 | 477.0 | 5.9 | 417.36 | 78.75 | 0 |
| stress-300x100 | 48 / 48 | 0 | 1.0 | 1569.6 | 31.56 | 1536.48 | 100.0 | 0 |
| text-input-burst-80x24 | 120 / 60 | 60 | 2.0 | 363.72 | 16.08 | 127.57 | 84.0 | 0 |

## Over-Budget Thresholds

This candidate permits over-budget frames in 11 scenarios. Promotion requires `--allow-over-budget-thresholds` and a concrete `--review-note=TEXT` that explains why those thresholds are acceptable for this reviewed baseline.

| Scenario | Extra frames | Max frames/step | Total frame p95 ms | Over budget % |
| --- | ---: | ---: | ---: | ---: |
| cursor-blink-80x24 | 0 | 1.0 | 525.6 | 100.0 |
| dirty-row-160x50 | 0 | 1.0 | 460.2 | 78.75 |
| full-frame-churn-160x50 | 0 | 1.0 | 883.56 | 100.0 |
| large-160x50 | 0 | 1.0 | 363.6 | 86.25 |
| noop-160x50 | 0 | 1.0 | 127.2 | 25.0 |
| normal-80x24 | 0 | 1.0 | 198.96 | 75.0 |
| resize-burst | 36 | 2.0 | 527.64 | 100.0 |
| scroll-row-churn-160x50 | 0 | 1.0 | 1135.8 | 100.0 |
| single-dirty-cell-160x50 | 0 | 1.0 | 477.0 | 78.75 |
| stress-300x100 | 0 | 1.0 | 1569.6 | 100.0 |
| text-input-burst-80x24 | 60 | 2.0 | 363.72 | 84.0 |

## Promotion Command

This command is intentionally not runnable as written: replace the reviewer placeholder and any generic browser/platform values before promotion.

```sh
dart run tool/web_threshold_review.dart \
  --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.candidate.json \
  --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/thresholds.json \
  --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/threshold-review.json \
  --expect-input-fingerprint=fnv1a64:e0d3572d6b421cf7 \
  '--reviewed-by=<reviewer>' \
  '--review-context=Browser Chrome/149.0.7827.102, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline' \
  --allow-over-budget-thresholds \
  '--review-note=<why these over-budget thresholds are acceptable for this reviewed baseline>'
```
