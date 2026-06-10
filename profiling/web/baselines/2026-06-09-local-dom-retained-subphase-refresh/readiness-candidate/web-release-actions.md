# Fleury Web Release Actions

- Generated at: `2026-06-09T22:05:40.060026Z`
- Bundle manifest: `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json`
- Readiness artifact: `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json`
- Command working directory: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`
- Remaining action count: `4`

These actions are generated from the readiness bundle. Complete them in dependency order, then require strict bundle verification and bundle-bound default preflights before changing web defaults.

## 1. verify-readiness-bundle

- Kind: `artifact-verification`
- Label: Verify generated and source-input bundle fingerprints

| Detail | Value |
| --- | --- |
| `bundleJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json |
| `strictRequired` | true |
| `jsonOutput` | true |
| `verificationScope` | generated-artifact-fingerprints, source-input-fingerprints, expected-source-input-path-coverage, command-working-directory-metadata, manual-evidence-latest-entry-fingerprints, threshold-review-release-action, manual-evidence-release-actions, generated-default-preflight-diagnostics, release-action-command-templates |
| `reviewerNextStep` | run after regenerate-readiness-bundle and require strictPass true |

**Command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json
```

**Root command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-readiness-bundle --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json
```

## 2. run-automated-web-host-tests

- Kind: `automated-validation`
- Label: Run retained DOM automated host tests
- Depends on: `verify-readiness-bundle`

| Detail | Value |
| --- | --- |
| `sourceInputGroup` | webAutomatedTestFiles |
| `automatedValidationJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json |
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
dart run tool/web_automated_validation.dart --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --strict --json
```

**Root command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-automated-validation --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --strict --json
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

## 3. run-default-preflight:make-dom-default

- Kind: `release-gate`
- Label: Run bundle-bound default preflight for make-dom-default
- Depends on: `verify-readiness-bundle`, `run-automated-web-host-tests`
- Target: `make-dom-default`

| Detail | Value |
| --- | --- |
| `targetId` | make-dom-default |
| `readinessJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json |
| `bundleJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json |
| `automatedValidationJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json |
| `strictRequired` | true |
| `jsonOutput` | true |
| `requiresBundleBinding` | true |
| `generatedPreviewStrictPass` | true |
| `generatedPreviewBundleBound` | false |
| `generatedPreviewDiagnosticOnly` | true |
| `verificationScope` | generated-artifact-fingerprints, source-input-fingerprints, expected-source-input-path-coverage, command-working-directory-metadata, readiness-json-path-binding, automated-validation-artifact |
| `reviewerNextStep` | run after bundle verification and require strictPass true before changing this default |

**Command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json
```

**Root command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-default-preflight --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=make-dom-default --strict --json
```

## 4. run-default-preflight:retire-temporary-paths

- Kind: `release-gate`
- Label: Run bundle-bound default preflight for retire-temporary-paths
- Depends on: `verify-readiness-bundle`, `run-automated-web-host-tests`
- Target: `retire-temporary-paths`

| Detail | Value |
| --- | --- |
| `targetId` | retire-temporary-paths |
| `readinessJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json |
| `bundleJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json |
| `automatedValidationJsonPath` | /Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json |
| `strictRequired` | true |
| `jsonOutput` | true |
| `requiresBundleBinding` | true |
| `generatedPreviewStrictPass` | true |
| `generatedPreviewBundleBound` | false |
| `generatedPreviewDiagnosticOnly` | true |
| `verificationScope` | generated-artifact-fingerprints, source-input-fingerprints, expected-source-input-path-coverage, command-working-directory-metadata, readiness-json-path-binding, automated-validation-artifact |
| `reviewerNextStep` | run after bundle verification and require strictPass true before changing this default |

**Command**

Run from: `/Users/dan/Coding/fleury-web-phase1/packages/fleury_web`

```sh
dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json
```

**Root command**

Run from: `/Users/dan/Coding/fleury-web-phase1`

```sh
dart run tool/fleury_dev.dart benchmark web-default-preflight --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --automated-validation=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --target=retire-temporary-paths --strict --json
```

