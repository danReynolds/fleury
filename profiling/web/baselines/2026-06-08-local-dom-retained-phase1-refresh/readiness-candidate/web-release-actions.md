# Fleury Web Release Actions

- Generated at: `2026-06-09T13:35:28.923802Z`
- Bundle manifest: `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json`
- Readiness artifact: `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json`
- Command working directory: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`
- Remaining action count: `8`

These actions are generated from the readiness bundle. Complete them in dependency order, then require strict bundle verification and bundle-bound default preflights before changing web defaults.

## 1. review-threshold-policy

- Kind: `human-review`
- Label: Review and promote per-scenario web thresholds
- Blocking checks: `frameScoreboard`
- Blockers: `frame scoreboard threshold policy reviewState is candidate; expected reviewed`

| Detail | Value |
| --- | --- |
| `candidateThresholdPolicyPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json |
| `reviewedThresholdPolicyPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.json |
| `thresholdReviewPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review.json |
| `thresholdReviewPlanPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review-plan.md |
| `currentReviewState` | candidate |
| `currentThresholdPolicyFingerprint` | fnv1a64:5e05148220c729cd |
| `expectedInputFingerprint` | fnv1a64:5e05148220c729cd |
| `captureEnvironment` | {"scenarioCount":11,"scenarioWithEnvironmentCount":11,"comparableScenarioCount":11,"allScenariosComparable":true,"chromeBrowser":"Chrome/148.0.7778.217","operatingSystem":"macos","operatingSystemVersion":"Version 26.2 (Build 25C56)","dartVersion":"3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on \"macos_x64\"","headless":true,"frameBudgetMs":16.67,"requestedFrames":[24,32,12,16,20],"warmupFrames":2,"reviewContextHint":"Browser Chrome/148.0.7778.217, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on \"macos_x64\", headless=true, frameBudgetMs=16.67, retained DOM product baseline"} |
| `suggestedReviewContext` | Browser Chrome/148.0.7778.217, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline |
| `overBudgetThresholdScenarioCount` | 11 |
| `overBudgetThresholdScenarios` | [{"id":"cursor-blink-80x24","maxTotalFrameP95Ms":1078.2,"maxOverBudgetPercent":100.0},{"id":"dirty-row-160x50","maxTotalFrameP95Ms":864.97,"maxOverBudgetPercent":97.5},{"id":"full-frame-churn-160x50","maxTotalFrameP95Ms":2692.08,"maxOverBudgetPercent":100.0},{"id":"large-160x50","maxTotalFrameP95Ms":499.69,"maxOverBudgetPercent":100.0},{"id":"noop-160x50","maxTotalFrameP95Ms":87.84,"maxOverBudgetPercent":35.0},{"id":"normal-80x24","maxTotalFrameP95Ms":466.56,"maxOverBudgetPercent":95.0},{"id":"resize-burst","maxTotalFrameP95Ms":949.92,"maxOverBudgetPercent":100.0},{"id":"scroll-row-churn-160x50","maxTotalFrameP95Ms":2411.65,"maxOverBudgetPercent":100.0},{"id":"single-dirty-cell-160x50","maxTotalFrameP95Ms":285.48,"maxOverBudgetPercent":100.0},{"id":"stress-300x100","maxTotalFrameP95Ms":3578.64,"maxOverBudgetPercent":100.0},{"id":"text-input-burst-80x24","maxTotalFrameP95Ms":408.85,"maxOverBudgetPercent":87.0}] |
| `overBudgetAcknowledgementRequired` | true |
| `commandTemplateRunnable` | false |
| `commandTemplatePlaceholders` | [{"name":"reviewer","argument":"--reviewed-by","placeholder":"<reviewer>","description":"human reviewer name or handle"},{"name":"reviewNote","argument":"--review-note","placeholder":"<why these over-budget thresholds are acceptable for this reviewed baseline>","description":"explicit justification for accepting thresholds that allow over-budget frames"}] |
| `reviewerNextStep` | replace commandTemplate placeholders, verify suggestedReviewContext if present, and keep --allow-over-budget-thresholds only after explicitly accepting the over-budget scenarios in --review-note |
| `thresholdReviewPlanStatus` | current |
| `thresholdReviewPlanInputFingerprint` | fnv1a64:5e05148220c729cd |

**Plan command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_threshold_review.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review-plan.md '--review-context-hint=Browser Chrome/148.0.7778.217, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline'
```

**Root plan command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-threshold-review --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review-plan.md '--review-context-hint=Browser Chrome/148.0.7778.217, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline'
```

**Command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_threshold_review.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.json --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review.json --expect-input-fingerprint=fnv1a64:5e05148220c729cd '--reviewed-by=<reviewer>' '--review-context=Browser Chrome/148.0.7778.217, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline' --allow-over-budget-thresholds '--review-note=<why these over-budget thresholds are acceptable for this reviewed baseline>'
```

**Root command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-threshold-review --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.json --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review.json --expect-input-fingerprint=fnv1a64:5e05148220c729cd '--reviewed-by=<reviewer>' '--review-context=Browser Chrome/148.0.7778.217, OS macos OS version Version 26.2 (Build 25C56), Dart 3.12.1 (stable) (Tue May 26 01:02:21 2026 -0700) on "macos_x64", headless=true, frameBudgetMs=16.67, retained DOM product baseline' --allow-over-budget-thresholds '--review-note=<why these over-budget thresholds are acceptable for this reviewed baseline>'
```

## 2. collect-manual-evidence:chrome-ime-macos

- Kind: `manual-validation`
- Label: Collect reviewed manual web evidence for chrome-ime-macos
- Blocking checks: `manualValidation`
- Blockers: `manual validation audit strictPass is not true`, `manual validation passed 0 of 2 targets`, `needsReviewTargets: chrome-ime-macos, chrome-voiceover-macos`, `manual evidence provenance blockers: chrome-ime-macos: reviewedBy, capturedAt, environment.browserVersion; chrome-voiceover-macos: reviewedBy, capturedAt, environment.browserVersion`, `failing manual targets: chrome-ime-macos, chrome-voiceover-macos`
- Target: `chrome-ime-macos`
- Status: `needsReview`

| Detail | Value |
| --- | --- |
| `requiredCheckCount` | 6 |
| `passedRequiredCheckCount` | 0 |
| `missingCheckIds` | manual-page-loads-dom-host, keyboard-capture-focused, composition-start-update-visible, composition-end-commits-once, candidate-window-near-caret, typing-continues-after-composition |
| `templatePath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates/chrome-ime-macos.template.json |
| `templateStatus` | current |
| `templateFingerprint` | fnv1a64:2acd82e8d787287d |
| `manualValidationPage` | web/manual_validation.html |
| `requiredEvidencePage` | manual_validation.html |
| `manualPageCommandWorkingDirectory` | packages/fleury_web |
| `manualValidationReadySignal` | document.body data-fleury-manual-validation="ready" |
| `manualPageSmokeCommand` | dart, test, -p, chrome, test/manual_validation_page_test.dart |
| `manualPageLocalUrl` | http://localhost:8080/manual_validation.html |
| `manualPageServeNote` | Run manualPageServeSetupCommand if dhttpd is not active, keep manualPageServeCommand running, open http://localhost:8080/manual_validation.html from that local server, and start checks only after the ready signal. |
| `manualPageProvenanceAttributes` | data-fleury-manual-browser-version, data-fleury-manual-platform, data-fleury-manual-user-agent, data-fleury-manual-page |
| `requiredPageSignals` | [{"id":"retained-dom-ready","selector":"body","attribute":"data-fleury-manual-validation","expectedValue":"ready","description":"The manual validation page has presented its first retained DOM frame."},{"id":"ime-caret-positioned","selector":"textarea","attribute":"data-fleury-caret-state","expectedValue":"positioned","description":"The hidden textarea is positioned at the focused Fleury caret for IME candidate windows."}] |
| `evidenceDirectory` | /Users/dan/Coding/fleury-web-phase1/profiling/web/manual/evidence |
| `starterEvidencePath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/manual/evidence/chrome-ime-macos.review.json |
| `starterEvidenceStatus` | exists |
| `starterEvidenceFingerprint` | fnv1a64:2acd82e8d787287d |
| `suggestedEvidencePath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/manual/evidence/chrome-ime-macos-YYYY-MM-DD.json |
| `starterOverwritePolicy` | fail-if-destination-exists |
| `provenanceCommandRunnable` | false |
| `provenanceCommandPlaceholders` | [{"name":"reviewer","argument":"--reviewed-by","placeholder":"<reviewer>","description":"human reviewer name or handle"},{"name":"browserVersion","argument":"--browser-version","placeholder":"<Chrome version used for manual validation>","description":"Chrome version from the browser used for the manual session"}] |
| `reviewerNextStep` | replace provenanceCommandTemplate placeholders during or after the manual session, fill required checks in starterEvidencePath, then run auditCommand |

**Manual page build command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart compile js web/manual_validation.dart -o web/manual_validation.dart.js
```

**Manual page smoke command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart test -p chrome test/manual_validation_page_test.dart
```

**Manual page serve setup command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart pub global activate dhttpd
```

**Manual page serve command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart pub global run dhttpd --path web
```

**Provenance command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_manual_validation.dart --update-provenance=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/evidence/chrome-ime-macos.review.json --template-target=chrome-ime-macos '--reviewed-by=<reviewer>' --captured-at=now '--browser-version=<Chrome version used for manual validation>'
```

**Root provenance command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-manual-validation --update-provenance=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/evidence/chrome-ime-macos.review.json --template-target=chrome-ime-macos '--reviewed-by=<reviewer>' --captured-at=now '--browser-version=<Chrome version used for manual validation>'
```

**Audit command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json --strict
```

**Root audit command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-manual-validation --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json --strict
```

## 3. collect-manual-evidence:chrome-voiceover-macos

- Kind: `manual-validation`
- Label: Collect reviewed manual web evidence for chrome-voiceover-macos
- Blocking checks: `manualValidation`
- Blockers: `manual validation audit strictPass is not true`, `manual validation passed 0 of 2 targets`, `needsReviewTargets: chrome-ime-macos, chrome-voiceover-macos`, `manual evidence provenance blockers: chrome-ime-macos: reviewedBy, capturedAt, environment.browserVersion; chrome-voiceover-macos: reviewedBy, capturedAt, environment.browserVersion`, `failing manual targets: chrome-ime-macos, chrome-voiceover-macos`
- Target: `chrome-voiceover-macos`
- Status: `needsReview`

| Detail | Value |
| --- | --- |
| `requiredCheckCount` | 7 |
| `passedRequiredCheckCount` | 0 |
| `missingCheckIds` | manual-page-ready-semantic-host, visual-grid-hidden, semantic-root-exposed, focused-textbox-announced, semantic-action-works, keyboard-capture-restored, safe-link-announced |
| `templatePath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates/chrome-voiceover-macos.template.json |
| `templateStatus` | current |
| `templateFingerprint` | fnv1a64:531bf23a21090ef0 |
| `manualValidationPage` | web/manual_validation.html |
| `requiredEvidencePage` | manual_validation.html |
| `manualPageCommandWorkingDirectory` | packages/fleury_web |
| `manualValidationReadySignal` | document.body data-fleury-manual-validation="ready" |
| `manualPageSmokeCommand` | dart, test, -p, chrome, test/manual_validation_page_test.dart |
| `manualPageLocalUrl` | http://localhost:8080/manual_validation.html |
| `manualPageServeNote` | Run manualPageServeSetupCommand if dhttpd is not active, keep manualPageServeCommand running, open http://localhost:8080/manual_validation.html from that local server, and start checks only after the ready signal. |
| `manualPageProvenanceAttributes` | data-fleury-manual-browser-version, data-fleury-manual-platform, data-fleury-manual-user-agent, data-fleury-manual-page |
| `requiredPageSignals` | [{"id":"retained-dom-ready","selector":"body","attribute":"data-fleury-manual-validation","expectedValue":"ready","description":"The manual validation page has presented its first retained DOM frame."}] |
| `evidenceDirectory` | /Users/dan/Coding/fleury-web-phase1/profiling/web/manual/evidence |
| `starterEvidencePath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/manual/evidence/chrome-voiceover-macos.review.json |
| `starterEvidenceStatus` | exists |
| `starterEvidenceFingerprint` | fnv1a64:531bf23a21090ef0 |
| `suggestedEvidencePath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/manual/evidence/chrome-voiceover-macos-YYYY-MM-DD.json |
| `starterOverwritePolicy` | fail-if-destination-exists |
| `provenanceCommandRunnable` | false |
| `provenanceCommandPlaceholders` | [{"name":"reviewer","argument":"--reviewed-by","placeholder":"<reviewer>","description":"human reviewer name or handle"},{"name":"browserVersion","argument":"--browser-version","placeholder":"<Chrome version used for manual validation>","description":"Chrome version from the browser used for the manual session"}] |
| `reviewerNextStep` | replace provenanceCommandTemplate placeholders during or after the manual session, fill required checks in starterEvidencePath, then run auditCommand |

**Manual page build command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart compile js web/manual_validation.dart -o web/manual_validation.dart.js
```

**Manual page smoke command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart test -p chrome test/manual_validation_page_test.dart
```

**Manual page serve setup command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart pub global activate dhttpd
```

**Manual page serve command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart pub global run dhttpd --path web
```

**Provenance command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_manual_validation.dart --update-provenance=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/evidence/chrome-voiceover-macos.review.json --template-target=chrome-voiceover-macos '--reviewed-by=<reviewer>' --captured-at=now '--browser-version=<Chrome version used for manual validation>'
```

**Root provenance command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-manual-validation --update-provenance=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/evidence/chrome-voiceover-macos.review.json --template-target=chrome-voiceover-macos '--reviewed-by=<reviewer>' --captured-at=now '--browser-version=<Chrome version used for manual validation>'
```

**Audit command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_manual_validation.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json --strict
```

**Root audit command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-manual-validation --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --target-preset=primary --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/manual-validation-audit.json --strict
```

## 4. regenerate-readiness-bundle

- Kind: `artifact-refresh`
- Label: Regenerate the readiness bundle from reviewed evidence
- Depends on: `review-threshold-policy`, `collect-manual-evidence:chrome-ime-macos`, `collect-manual-evidence:chrome-voiceover-macos`

| Detail | Value |
| --- | --- |
| `captureDir` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh |
| `manualDir` | /Users/dan/Coding/fleury-web-phase1/profiling/web/manual |
| `outputDir` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate |
| `bundleJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json |
| `readinessJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json |
| `thresholdPolicyPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.json |
| `thresholdReviewPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review.json |
| `maxFallbackCells` | 0 |
| `targetPreset` | primary |
| `writeDefaultPreflights` | true |
| `strictRequired` | true |
| `jsonOutput` | true |
| `reviewerNextStep` | run after human-review and manual-validation dependencies pass |

**Command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.json --threshold-review=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --strict --json
```

**Root command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-readiness-bundle --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.json --threshold-review=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --strict --json
```

## 5. verify-readiness-bundle

- Kind: `artifact-verification`
- Label: Verify generated and source-input bundle fingerprints
- Depends on: `regenerate-readiness-bundle`

| Detail | Value |
| --- | --- |
| `bundleJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json |
| `strictRequired` | true |
| `jsonOutput` | true |
| `verificationScope` | generated-artifact-fingerprints, source-input-fingerprints, expected-source-input-path-coverage, command-working-directory-metadata |
| `reviewerNextStep` | run after regenerate-readiness-bundle and require strictPass true |

**Command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json
```

**Root command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-readiness-bundle --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json
```

## 6. run-automated-web-host-tests

- Kind: `automated-validation`
- Label: Run retained DOM automated host tests
- Depends on: `verify-readiness-bundle`

| Detail | Value |
| --- | --- |
| `sourceInputGroup` | webAutomatedTestFiles |
| `automatedValidationJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json |
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
dart run tool/web_automated_validation.dart --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --strict --json
```

**Root command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-automated-validation --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --strict --json
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

## 7. run-default-preflight:make-dom-default

- Kind: `release-gate`
- Label: Run bundle-bound default preflight for make-dom-default
- Depends on: `regenerate-readiness-bundle`, `verify-readiness-bundle`, `run-automated-web-host-tests`
- Target: `make-dom-default`

| Detail | Value |
| --- | --- |
| `targetId` | make-dom-default |
| `readinessJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json |
| `bundleJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json |
| `automatedValidationJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json |
| `strictRequired` | true |
| `jsonOutput` | true |
| `requiresBundleBinding` | true |
| `generatedPreviewStrictPass` | false |
| `generatedPreviewBundleBound` | false |
| `verificationScope` | generated-artifact-fingerprints, source-input-fingerprints, expected-source-input-path-coverage, command-working-directory-metadata, readiness-json-path-binding, automated-validation-artifact |
| `reviewerNextStep` | run after bundle verification and require strictPass true before changing this default |

**Command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json
```

**Root command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-default-preflight --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json
```

## 8. run-default-preflight:retire-temporary-paths

- Kind: `release-gate`
- Label: Run bundle-bound default preflight for retire-temporary-paths
- Depends on: `regenerate-readiness-bundle`, `verify-readiness-bundle`, `run-automated-web-host-tests`
- Target: `retire-temporary-paths`

| Detail | Value |
| --- | --- |
| `targetId` | retire-temporary-paths |
| `readinessJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json |
| `bundleJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json |
| `automatedValidationJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json |
| `strictRequired` | true |
| `jsonOutput` | true |
| `requiresBundleBinding` | true |
| `generatedPreviewStrictPass` | false |
| `generatedPreviewBundleBound` | false |
| `verificationScope` | generated-artifact-fingerprints, source-input-fingerprints, expected-source-input-path-coverage, command-working-directory-metadata, readiness-json-path-binding, automated-validation-artifact |
| `reviewerNextStep` | run after bundle verification and require strictPass true before changing this default |

**Command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json
```

**Root command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-default-preflight --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json
```

