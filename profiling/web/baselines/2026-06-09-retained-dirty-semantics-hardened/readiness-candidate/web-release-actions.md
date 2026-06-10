# Fleury Web Release Actions

- Generated at: `2026-06-10T02:59:47.034909Z`
- Bundle manifest: `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-readiness-bundle.json`
- Readiness artifact: `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-readiness.json`
- Command working directory: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`
- Remaining action count: `6`

These actions are generated from the readiness bundle. Complete them in dependency order, then require strict bundle verification and bundle-bound default preflights before changing web defaults.

## 1. review-threshold-policy

- Kind: `human-review`
- Label: Review and promote per-scenario web thresholds
- Blocking checks: `frameScoreboard`
- Blockers: `frame scoreboard threshold policy reviewState is candidate; expected reviewed`, `threshold review plan is missing; run planCommand before review`

| Detail | Value |
| --- | --- |
| `candidateThresholdPolicyPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/thresholds.candidate.json |
| `reviewedThresholdPolicyPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/thresholds.json |
| `thresholdReviewPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/threshold-review.json |
| `thresholdReviewPlanPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/threshold-review-plan.md |
| `currentReviewState` | candidate |
| `currentThresholdPolicyFingerprint` | fnv1a64:31221901e96a24c3 |
| `expectedInputFingerprint` | fnv1a64:31221901e96a24c3 |
| `captureEnvironment` | {"scenarioCount":11,"scenarioWithEnvironmentCount":11,"comparableScenarioCount":11,"allScenariosComparable":true,"chromeBrowser":"Chrome/149.0.7827.102","operatingSystem":"macos","operatingSystemVersion":"Version 26.2 (Build 25C56)","dartVersion":"3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on \"macos_x64\"","headless":true,"frameBudgetMs":16.67,"requestedFrames":[24,32,12,16,20],"warmupFrames":8,"reviewContextHint":"Browser Chrome/149.0.7827.102, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on \"macos_x64\", headless=true, frameBudgetMs=16.67, retained DOM product baseline"} |
| `candidateReviewContextHint` | Browser Chrome/149.0.7827.102, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline |
| `planCommandUsesCandidateCapturedContext` | true |
| `suggestedReviewContext` | Browser Chrome/149.0.7827.102, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline |
| `overBudgetThresholdScenarioCount` | 11 |
| `overBudgetThresholdScenarios` | [{"id":"cursor-blink-80x24","maxTotalFrameP95Ms":141.84,"maxOverBudgetPercent":70.0},{"id":"dirty-row-160x50","maxTotalFrameP95Ms":74.4,"maxOverBudgetPercent":22.5},{"id":"full-frame-churn-160x50","maxTotalFrameP95Ms":1200.84,"maxOverBudgetPercent":95.0},{"id":"large-160x50","maxTotalFrameP95Ms":68.28,"maxOverBudgetPercent":26.25},{"id":"noop-160x50","maxTotalFrameP95Ms":40.2,"maxOverBudgetPercent":15.0},{"id":"normal-80x24","maxTotalFrameP95Ms":394.56,"maxOverBudgetPercent":100.0},{"id":"resize-burst","maxTotalFrameP95Ms":1319.64,"maxOverBudgetPercent":100.0},{"id":"scroll-row-churn-160x50","maxTotalFrameP95Ms":759.6,"maxOverBudgetPercent":100.0},{"id":"single-dirty-cell-160x50","maxTotalFrameP95Ms":77.16,"maxOverBudgetPercent":30.0},{"id":"stress-300x100","maxTotalFrameP95Ms":1686.0,"maxOverBudgetPercent":100.0},{"id":"text-input-burst-80x24","maxTotalFrameP95Ms":204.84,"maxOverBudgetPercent":57.0}] |
| `overBudgetAcknowledgementRequired` | true |
| `commandTemplateRunnable` | false |
| `commandTemplatePlaceholders` | [{"name":"reviewer","argument":"--reviewed-by","placeholder":"<reviewer>","description":"human reviewer name or handle"},{"name":"reviewNote","argument":"--review-note","placeholder":"<why these over-budget thresholds are acceptable for this reviewed baseline>","description":"explicit justification for accepting thresholds that allow over-budget frames"}] |
| `reviewerNextStep` | replace commandTemplate placeholders, verify suggestedReviewContext if present, and keep --allow-over-budget-thresholds only after explicitly accepting the over-budget scenarios in --review-note |
| `thresholdReviewPlanStatus` | missing |

**Plan command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_threshold_review.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/thresholds.candidate.json --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/threshold-review-plan.md
```

**Root plan command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-threshold-review --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/thresholds.candidate.json --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/threshold-review-plan.md
```

**Command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_threshold_review.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/thresholds.candidate.json --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/thresholds.json --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/threshold-review.json --expect-input-fingerprint=fnv1a64:31221901e96a24c3 '--reviewed-by=<reviewer>' '--review-context=Browser Chrome/149.0.7827.102, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline' --allow-over-budget-thresholds '--review-note=<why these over-budget thresholds are acceptable for this reviewed baseline>'
```

**Root command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-threshold-review --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/thresholds.candidate.json --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/thresholds.json --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/threshold-review.json --expect-input-fingerprint=fnv1a64:31221901e96a24c3 '--reviewed-by=<reviewer>' '--review-context=Browser Chrome/149.0.7827.102, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline' --allow-over-budget-thresholds '--review-note=<why these over-budget thresholds are acceptable for this reviewed baseline>'
```

## 2. regenerate-readiness-bundle

- Kind: `artifact-refresh`
- Label: Regenerate the readiness bundle from reviewed evidence
- Depends on: `review-threshold-policy`

| Detail | Value |
| --- | --- |
| `captureDir` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened |
| `manualDir` | /Users/dan/Coding/fleury-web-phase1/profiling/web/manual |
| `outputDir` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate |
| `bundleJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-readiness-bundle.json |
| `readinessJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-readiness.json |
| `thresholdPolicyPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/thresholds.json |
| `thresholdReviewPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/threshold-review.json |
| `maxFallbackCells` | 0 |
| `targetPreset` | v1 |
| `completionAuditPath` | /Users/dan/Coding/fleury-web-phase1/docs/implementation/web-rfc-completion-audit.json |
| `writeDefaultPreflights` | true |
| `strictRequired` | true |
| `jsonOutput` | true |
| `reviewerNextStep` | run after human-review and manual-validation dependencies pass |

**Command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/thresholds.json --threshold-review=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/threshold-review.json --max-fallback-cells=0 --target-preset=v1 --write-default-preflights --completion-audit=/Users/dan/Coding/fleury-web-phase1/docs/implementation/web-rfc-completion-audit.json --strict --json
```

**Root command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-readiness-bundle --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/thresholds.json --threshold-review=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/threshold-review.json --max-fallback-cells=0 --target-preset=v1 --write-default-preflights --completion-audit=/Users/dan/Coding/fleury-web-phase1/docs/implementation/web-rfc-completion-audit.json --strict --json
```

## 3. verify-readiness-bundle

- Kind: `artifact-verification`
- Label: Verify generated and source-input bundle fingerprints
- Depends on: `regenerate-readiness-bundle`

| Detail | Value |
| --- | --- |
| `bundleJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-readiness-bundle.json |
| `strictRequired` | true |
| `jsonOutput` | true |
| `verificationScope` | generated-artifact-fingerprints, source-input-fingerprints, expected-source-input-path-coverage, command-working-directory-metadata, manual-evidence-latest-entry-fingerprints, threshold-review-release-action, manual-evidence-release-actions, generated-default-preflight-diagnostics, release-action-command-templates |
| `reviewerNextStep` | run after regenerate-readiness-bundle and require strictPass true |

**Command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-readiness-bundle.json --strict --json
```

**Root command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-readiness-bundle --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-readiness-bundle.json --strict --json
```

## 4. run-automated-web-host-tests

- Kind: `automated-validation`
- Label: Run retained DOM automated host tests
- Depends on: `verify-readiness-bundle`

| Detail | Value |
| --- | --- |
| `sourceInputGroup` | webAutomatedTestFiles |
| `automatedValidationJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-automated-validation.json |
| `browserTestFileCount` | 9 |
| `vmTestFileCount` | 4 |
| `fixtureFileCount` | 1 |
| `browserTestFiles` | test/browser_frame_flush_scheduler_test.dart, test/cell_metrics_test.dart, test/dom_grid_surface_test.dart, test/dom_input_source_test.dart, test/dom_input_trace_fixture_test.dart, test/run_tui_surface_test.dart, test/run_tui_web_dom_test.dart, test/semantic_dom_presenter_test.dart, test/web_clipboard_test.dart |
| `vmTestFiles` | test/frame_presentation_test.dart, test/web_focus_coordinator_test.dart, test/web_host_instrumentation_test.dart, test/web_public_api_boundary_test.dart |
| `fixtureFiles` | test/fixtures/browser_input_traces.dart |
| `requiredPass` | true |
| `verificationScope` | retained-dom-host-assembly, browser-frame-flush-scheduling, browser-input-trace-replay, semantic-dom-projection, clipboard-and-focus-adapters, public-api-boundary |
| `reviewerNextStep` | run after strict bundle verification and require the generated JSON artifact to strict-pass before changing web defaults |

**Command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_automated_validation.dart --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-automated-validation.json --strict --json
```

**Root command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-automated-validation --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-automated-validation.json --strict --json
```

**Browser test command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart test -p chrome test/browser_frame_flush_scheduler_test.dart test/cell_metrics_test.dart test/dom_grid_surface_test.dart test/dom_input_source_test.dart test/dom_input_trace_fixture_test.dart test/run_tui_surface_test.dart test/run_tui_web_dom_test.dart test/semantic_dom_presenter_test.dart test/web_clipboard_test.dart
```

**VM test command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart test test/frame_presentation_test.dart test/web_focus_coordinator_test.dart test/web_host_instrumentation_test.dart test/web_public_api_boundary_test.dart
```

## 5. run-default-preflight:make-dom-default

- Kind: `release-gate`
- Label: Run bundle-bound default preflight for make-dom-default
- Depends on: `regenerate-readiness-bundle`, `verify-readiness-bundle`, `run-automated-web-host-tests`
- Target: `make-dom-default`

| Detail | Value |
| --- | --- |
| `targetId` | make-dom-default |
| `readinessJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-readiness.json |
| `bundleJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-readiness-bundle.json |
| `automatedValidationJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-automated-validation.json |
| `strictRequired` | true |
| `jsonOutput` | true |
| `requiresBundleBinding` | true |
| `generatedPreviewStrictPass` | false |
| `generatedPreviewBundleBound` | false |
| `generatedPreviewDiagnosticOnly` | true |
| `verificationScope` | generated-artifact-fingerprints, source-input-fingerprints, expected-source-input-path-coverage, command-working-directory-metadata, readiness-json-path-binding, automated-validation-artifact |
| `reviewerNextStep` | run after bundle verification and require strictPass true before changing this default |

**Command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json
```

**Root command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-default-preflight --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json
```

## 6. run-default-preflight:retire-temporary-paths

- Kind: `release-gate`
- Label: Run bundle-bound default preflight for retire-temporary-paths
- Depends on: `regenerate-readiness-bundle`, `verify-readiness-bundle`, `run-automated-web-host-tests`
- Target: `retire-temporary-paths`

| Detail | Value |
| --- | --- |
| `targetId` | retire-temporary-paths |
| `readinessJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-readiness.json |
| `bundleJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-readiness-bundle.json |
| `automatedValidationJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-automated-validation.json |
| `strictRequired` | true |
| `jsonOutput` | true |
| `requiresBundleBinding` | true |
| `generatedPreviewStrictPass` | false |
| `generatedPreviewBundleBound` | false |
| `generatedPreviewDiagnosticOnly` | true |
| `verificationScope` | generated-artifact-fingerprints, source-input-fingerprints, expected-source-input-path-coverage, command-working-directory-metadata, readiness-json-path-binding, automated-validation-artifact |
| `reviewerNextStep` | run after bundle verification and require strictPass true before changing this default |

**Command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json
```

**Root command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-default-preflight --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-retained-dirty-semantics-hardened/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json
```

