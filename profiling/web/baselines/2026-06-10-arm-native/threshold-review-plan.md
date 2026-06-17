# Fleury Web Threshold Review Plan

- Input: `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-10-arm-native/thresholds.candidate.json`
- Input fingerprint: `fnv1a64:c302fd6d810a24a6`
- Review state: `candidate`
- Scenario count: `11`
- Candidate generated at: `2026-06-10T20:19:53.788115Z`
- Capture run count: `33`
- Source metric: `maxCaptureP95PerScenario`
- Threshold headroom: `20.0%`, minimum `1.0ms`
- Capture input: `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-10-arm-native`
- Review context hint: `Browser Chrome/149.0.7827.102, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline`

## Review Checklist

- Confirm the capture input represents the agreed product/browser configuration.
- Confirm every release scenario has an explicit threshold entry.
- Inspect total-frame thresholds separately from DOM and semantic apply thresholds.
- Check runtime build/layout/paint subphase availability before using this review to choose a Dart-side optimization path.
- Check over-budget thresholds for scenarios with intentionally slow frames.
- Confirm semantic uncovered-cell thresholds remain zero unless an accessibility exception is reviewed.
- Record reviewer, timestamp, and product/browser context before promotion.

## Runtime Subphase Timing Availability

Runtime build/layout/paint subphase samples are unavailable for 1 of 11 scenarios. This policy still gates total frame, DOM apply, and semantic apply thresholds, but it should not be used to decide whether Dart work is build-, layout-, or paint-bound for scenarios without subphase samples. Regenerate captures with runtime subphase timing before making that optimization call.

| Scenario | Build | Layout | Paint |
| --- | --- | --- | --- |
| noop-160x50 | missing | missing | missing |

## Scenario Thresholds

| Scenario | Frames / steps | Extra frames | Max frames/step | Total frame p95 ms | DOM apply p95 ms | Semantic apply p95 ms | Over budget % | Semantic uncovered cells |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| cursor-blink-80x24 | 192 / 192 | 0 | 1.0 | 4.3 | 1.4 | 0.0 | 0.0 | 0 |
| dirty-row-160x50 | 192 / 192 | 0 | 1.0 | 2.9 | 1.21 | 0.0 | 0.0 | 0 |
| full-frame-churn-160x50 | 192 / 192 | 0 | 1.0 | 5.9 | 1.31 | 0.0 | 0.0 | 0 |
| large-160x50 | 192 / 192 | 0 | 1.0 | 1.6 | 1.11 | 0.0 | 0.0 | 0 |
| noop-160x50 | 192 / 192 | 0 | 1.0 | 1.2 | 0.0 | 0.0 | 0.0 | 0 |
| normal-80x24 | 192 / 192 | 0 | 1.0 | 2.41 | 1.21 | 0.0 | 0.0 | 0 |
| resize-burst | 384 / 192 | 192 | 2.0 | 3.0 | 1.3 | 0.0 | 0.0 | 0 |
| scroll-row-churn-160x50 | 192 / 192 | 0 | 1.0 | 6.36 | 1.2 | 0.0 | 0.0 | 0 |
| single-dirty-cell-160x50 | 192 / 192 | 0 | 1.0 | 2.5 | 1.2 | 0.0 | 0.0 | 0 |
| stress-300x100 | 192 / 192 | 0 | 1.0 | 10.32 | 1.4 | 0.0 | 0.0 | 0 |
| text-input-burst-80x24 | 384 / 192 | 192 | 2.0 | 3.9 | 1.2 | 0.0 | 0.0 | 0 |

## Promotion Command

This command is intentionally not runnable as written: replace the reviewer placeholder and any generic browser/platform values before promotion.

```sh
dart run tool/web_threshold_review.dart \
  --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-10-arm-native/thresholds.candidate.json \
  --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-10-arm-native/thresholds.json \
  --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-10-arm-native/threshold-review.json \
  --expect-input-fingerprint=fnv1a64:c302fd6d810a24a6 \
  '--reviewed-by=<reviewer>' \
  '--review-context=Browser Chrome/149.0.7827.102, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline'
```
