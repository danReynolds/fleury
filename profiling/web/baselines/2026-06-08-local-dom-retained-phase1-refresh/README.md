# 2026-06-08 local retained DOM Phase 1 refresh

Status: local candidate evidence for re-review, not a release gate.

This directory contains a fresh retained DOM web benchmark suite collected after
the Phase 1 cleanup, sparse damage, semantic replay, incremental semantic DOM,
and candidate-threshold clamp fixes. It supersedes the earlier local candidate
for review purposes, but it is still not an approved Phase 5/6 release
baseline.

## Commands

```sh
cd packages/fleury_web
dart run tool/web_frame_suite.dart --runs=3 --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --scoreboard=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/scoreboard.md --write-thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --timeout=60
dart run tool/web_frame_scoreboard.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/scoreboard.md --min-runs=3 --write-thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --threshold-headroom-percent=20 --threshold-min-headroom-ms=1 --threshold-min-headroom-percent=1 --require-comparable-environment --strict
dart run tool/web_threshold_review.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review-plan.md
dart run tool/web_semantic_coverage_audit.dart --input=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/semantic-coverage.md --max-fallback-cells=0 --strict
dart run tool/web_readiness_bundle.dart --captures=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh --manual=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual --output-dir=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate --thresholds=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --max-fallback-cells=0 --target-preset=primary --write-default-preflights --json
dart run tool/web_readiness_bundle.dart --verify=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --strict --json
```

The readiness-bundle command writes the synchronized release-action preflight
artifact pairs and `web-release-actions.md`. To exercise the strict
release-action gates directly, pass the bundle manifest so the preflight checks
both readiness and packet fingerprints:

```sh
dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=make-dom-default --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-make-dom-default.json --strict --json
dart run tool/web_default_preflight.dart --readiness=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json --bundle=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness-bundle.json --target=retire-temporary-paths --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.md --json-output=/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-default-preflight-retire-temporary-paths.json --strict --json
```

Both preflights currently strict-fail, as intended for candidate evidence.

If reviewers accept the candidate thresholds, promote them with reviewer
provenance rather than editing the policy by hand:

```sh
cd /Users/dan/Coding/fleury-web-phase1
fleury benchmark web-threshold-review --input=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.candidate.json --output=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/thresholds.json --json-output=profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/threshold-review.json --reviewed-by=REVIEWER --review-context="Chrome VERSION on PLATFORM, retained DOM Phase 1 refresh" --allow-over-budget-thresholds --review-note="Explain why these over-budget thresholds are acceptable for this reviewed baseline."
```

Manual plan/template artifacts were generated with:

```sh
dart run tool/web_manual_validation.dart --write-plan=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/plan.md --output=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/review.md
dart run tool/web_manual_validation.dart --write-template=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates/chrome-ime-macos.template.json --template-target=chrome-ime-macos
dart run tool/web_manual_validation.dart --write-template=/Users/dan/Coding/fleury-web-phase1/profiling/web/manual/templates/chrome-voiceover-macos.template.json --template-target=chrome-voiceover-macos
```

The generated plan and both manual target templates require reviewers to wait
for `data-fleury-manual-validation="ready"` before collecting manual evidence.
The intermediate `"mounted"` marker only proves host construction, not
first-frame presentation. The screen-reader target additionally records this as
the `manual-page-ready-semantic-host` check so standalone VoiceOver evidence
cannot skip retained-semantic-DOM readiness.
Passing evidence must include reviewer observation notes for each passed
required check. Blank notes or notes copied from the generated check
instructions are rejected by strict audit.

## Artifacts

- `*-run-*.json`: 33 Chrome captures, three per scenario.
- `scoreboard.md`: human-readable frame scoreboard.
- `thresholds.candidate.json`: generated candidate threshold policy with
  percentage gates clamped to `100.0`.
- `threshold-review-plan.md`: non-promoting threshold review packet with the
  candidate policy fingerprint and promotion command.
- `semantic-coverage.md`: human-readable semantic fallback audit.
- `readiness-candidate/scoreboard.json`: machine-readable scoreboard with the
  candidate threshold policy applied.
- `readiness-candidate/semantic-coverage.json`: machine-readable semantic
  fallback audit.
- `readiness-candidate/manual-validation-audit.json`: manual evidence audit.
- `readiness-candidate/web-readiness-bundle.json`: machine-readable manifest
  for the readiness and preflight artifact set.
- `readiness-candidate/web-release-actions.md`: human-readable release-action
  graph for the remaining threshold/manual/preflight work.
- `readiness-candidate/web-readiness.json` and `web-readiness.md`: combined
  readiness result.
- `readiness-candidate/web-default-preflight-make-dom-default.md` and
  `.json`: default flip preflight result.
- `readiness-candidate/web-default-preflight-retire-temporary-paths.md` and
  `.json`: temporary-path retirement preflight result.

## Summary

- Frame scoreboard: pass for three runs per scenario, comparable run
  environment, and generated candidate-threshold gates.
- Semantic coverage: pass with 33 captures, 912 measured frames, zero fallback
  frames, zero fallback cells, and zero fallback nodes.
- Readiness: fail, because the frame scoreboard uses
  `thresholds.candidate.json` rather than a reviewed threshold policy and no
  primary manual evidence entries exist yet for `chrome-ime-macos` and
  `chrome-voiceover-macos`.
- Damage sanity:
  - `noop-160x50` latest capture: 0 dirty rows, 0 replaced rows, 0 DOM nodes
    created, 0 semantic fallback cells.
  - `single-dirty-cell-160x50` latest capture: 1 dirty row, 1 replaced row, 1
    DOM node created, 0 semantic fallback cells.
  - `dirty-row-160x50` latest capture: 2 dirty rows, 2 replaced rows, 2 DOM
    nodes created, 0 semantic fallback cells.
- Performance signal: local over-budget behavior remains dominated by
  `runtimeRenderMs` and `semanticApplyMs`, not DOM apply. Median total-frame
  p95 ranges from `59.10 ms` for `noop-160x50` to `1193.40 ms` for
  `scroll-row-churn-160x50`; `stress-300x100` is still fully over budget.
- Semantic split signal: sparse scenarios use incremental semantic DOM
  mutation, but semantic presenter/diff/coverage costs still show large local
  variance. In the latest single-dirty capture, semantic DOM created/replaced
  max is 0, reused max is 1, and semantic presenter max is `229.8 ms`.

## Caveats

`thresholds.candidate.json` was generated from this same local run with default
headroom. It is a review starting point, not an approved release threshold
policy. Rename or copy reviewed values to `thresholds.json` and set
`reviewState` to `reviewed` only after the product/browser conditions and
target budgets are agreed. Because this candidate permits over-budget frames,
promotion must include `--allow-over-budget-thresholds` and a concrete
`--review-note=TEXT`; the reviewed policy and `threshold-review.json` summary
record that acknowledgement. Reviewed threshold policies must also include
non-empty `reviewedBy` and `reviewedAt` fields. The combined readiness gate
rejects candidate or provenance-free threshold policies by default.

The manual validation JSON files in `profiling/web/manual/templates` are
templates, not passing evidence, and files ending in `.template.json` are
ignored by audits. The combined readiness gate must stay red until those
templates are copied to non-template evidence files after real Chrome IME and
Chrome VoiceOver validation and review, with reviewer observations recorded for
the passed checks.

Until runtime, retained DOM, input/focus/clipboard, semantics projection, or
benchmark scenario code changes, this capture directory should be reused for
scoreboard/readiness iteration. Full Chrome recapture is reserved for those
behavioral changes or a final evidence refresh.
