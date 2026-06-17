# Fleury web benchmark artifacts

`fleury benchmark web-capture` and `fleury benchmark web-suite` write generated
browser evidence here.

- `runs/` is the default generated scratch bucket and is ignored by git. It is
  for local iteration, CI workspaces, and ad hoc repeated captures. Suite runs
  write both `scoreboard.md` and `scoreboard.json` under the run directory.
- `baselines/` is for intentionally promoted evidence. Use it only after the
  run conditions, browser version, scenario set, and threshold meaning are
  clear enough that the captures should be reviewed or compared later.
- `manual/` is for reviewed manual browser validation evidence. These
  entries are not generated benchmark runs; they record the manual gates that
  browser automation cannot fully prove.

Capture JSON records run environment metadata. Repeated suites require
comparable environment signatures by default, so a strict scoreboard can fail
when runs mix browser versions, Dart versions, operating systems, headless
mode, frame budgets, warmup counts, or requested step counts.
Suite runs compile the browser benchmark page once by default and reuse that
page for each capture, which keeps full retained-DOM baselines from paying the
Dart-to-JavaScript compile cost repeatedly. Use `--no-compile-once` only for
diagnosing capture setup or compile isolation.
Per-frame timing also keeps dirty-row diff fallback separate from span
building, so unbounded damage scans are visible as Dart-side work instead of
being folded into retained DOM apply time.

Store reviewed performance thresholds as JSON next to the promoted capture set,
for example `profiling/web/baselines/2026-06-08-dom-retained/thresholds.json`.
The scoreboard merges CLI gates, policy `defaults`, and then
`scenarios[scenarioId]`, so the checked-in policy is the release contract and
CLI flags are only fallback plumbing knobs. Supported policy fields are
`maxTotalFrameP95Ms`, `maxDomApplyP95Ms`, `maxSemanticApplyP95Ms`,
`maxOverBudgetPercent`, and `maxSemanticUncoveredCells`:

```json
{
  "schemaVersion": 1,
  "kind": "fleuryWebFrameThresholds",
  "reviewState": "reviewed",
  "reviewedBy": "reviewer-name",
  "reviewedAt": "2026-06-08T12:00:00Z",
  "reviewContext": "Chrome 127 on macOS, retained DOM product baseline",
  "defaults": {
    "maxTotalFrameP95Ms": 16.67,
    "maxOverBudgetPercent": 0,
    "maxSemanticUncoveredCells": 0
  },
  "scenarios": {
    "large-160x50": {
      "maxTotalFrameP95Ms": 25,
      "maxDomApplyP95Ms": 8
    }
  }
}
```

Use `--write-thresholds=PATH` to generate a candidate policy from the observed
capture aggregates before review:

```sh
fleury benchmark web-scoreboard --input=profiling/web/baselines/2026-06-08-dom-retained --min-runs=5 --require-comparable-environment --write-thresholds=profiling/web/baselines/2026-06-08-dom-retained/thresholds.candidate.json
```

The candidate uses each scenario's observed aggregate maxima with default
headroom of 20 percent, at least 1 ms for timing gates and 1 percentage point
for over-budget gates. Adjust with `--threshold-headroom-percent`,
`--threshold-min-headroom-ms`, and `--threshold-min-headroom-percent`. It also
records a captured-environment summary under
`generatedFrom.captureEnvironment` when run metadata is available, including a
`reviewContextHint` for threshold review. Once the
candidate has been reviewed against the intended product/browser conditions,
promote it to the release policy without recapturing browser frames. Use
`--write-plan=PATH` first to create a non-promoting Markdown packet with the
candidate fingerprint, scenario thresholds, review checklist, and promotion
command template:

```sh
fleury benchmark web-threshold-review --input=profiling/web/baselines/2026-06-08-dom-retained/thresholds.candidate.json --write-plan=profiling/web/baselines/2026-06-08-dom-retained/threshold-review-plan.md
fleury benchmark web-threshold-review --input=profiling/web/baselines/2026-06-08-dom-retained/thresholds.candidate.json --output=profiling/web/baselines/2026-06-08-dom-retained/thresholds.json --json-output=profiling/web/baselines/2026-06-08-dom-retained/threshold-review.json --expect-input-fingerprint=FNV1A64_FROM_REVIEW_PLAN --reviewed-by=REVIEWER --review-context="Chrome VERSION on PLATFORM, retained DOM product baseline"
```

Only the reviewed `thresholds.json` should be passed through `--thresholds=...`
in readiness gates. Keep `threshold-review.json` next to it as the durable
promotion summary. In a plan-only run, `--json-output=PATH` only embeds that
future summary path in the generated promotion command; it does not write the
summary until promotion fields are supplied. When the candidate policy has
`generatedFrom.captureEnvironment.reviewContextHint`, plan generation uses that
captured context by default. Use `--review-context-hint=TEXT` only to override
that context or to fill it for legacy candidates that lack captured environment
metadata. Keep the generated
`--expect-input-fingerprint=<candidate fingerprint>` argument when promoting;
the tool refuses to write reviewed thresholds if the candidate file no longer
matches the reviewed plan. Reviewed policies must include
`reviewState: reviewed`, plus non-empty `reviewedBy`, `reviewedAt`, and
`reviewContext`
fields. The Phase 6
readiness audit fails by default when the frame scoreboard was generated from a
missing, non-reviewed, provenance-free, or context-free threshold policy. The
threshold promotion tool rejects the literal reviewer placeholder and generic
browser/platform placeholders, so generated plans are safe to keep in review
packets without being accidentally promotable as-is.

Use `fleury benchmark web-semantic-audit` on the same capture directory to
quantify semantic fallback reliance. A zero-fallback audit means visible text
in the captured frames was covered by richer geometry-bearing semantic nodes;
non-zero fallback is still readable through the backstop, but it identifies
widgets or scenarios that need semantic backfill before accessibility claims.
The audit JSON and Markdown include `topFallbackCaptures` so reviewers can
jump directly to the captures with the largest fallback footprint.

Use `fleury benchmark web-manual-validation` to generate the manual validation
plan, create JSON templates for each selected target, and strict-audit reviewed
manual entries. `--write-templates=DIR` writes one
`<target-id>.template.json` file per selected target. Use
`--target-preset=v1` for the current release evidence set. That v1 preset has
no required manual browser targets; `primary` remains a compatibility alias for
that scoped gate. The `chrome-ime-macos` and `chrome-voiceover-macos` targets
remain available through explicit `--target=...` flags or
`--target-preset=all` for future IME and screen-reader validation. A passing
manual entry
must include concrete reviewer provenance and the real test environment:
non-placeholder `reviewedBy`, `capturedAt`, `environment.browser`,
`environment.browserVersion`, `environment.platform`,
`environment.fleuryWebPage`, and the target-specific `inputMethod` or
`assistiveTechnology` field. Browser, platform, and assistive-technology values
must match the audited target, and placeholder browser-version values are
rejected. `capturedAt` must parse as ISO-8601, and `environment.fleuryWebPage`
must be `manual_validation.html`.
Reviewed entries must also fill `observedPageSignals` with `status: "pass"`
and an `observedValue` matching every target-required page signal, such as the
ready marker and IME caret-position marker. Passed required checks still need
reviewer observation notes rather than copied template prose.
Use `--update-provenance=PATH` to fill reviewer, capture-time, and browser
version metadata on an existing starter without changing target/check status.
Use `--update-page-signal=PATH --signal-id=<required-page-signal-id>
--signal-status=pass --observed-value=<expected-value>
--signal-notes=<reviewer observation>` to record one required page signal. The
page-signal helper validates the entry before and after writing, requires a
matching observed value for passed signals, and rejects copied template prose
for passed signal notes.
Use `--update-check=PATH --check-id=<required-check-id> --check-status=pass
--check-notes=<reviewer observation>` to record one observed manual check. The
check helper validates the entry before and after writing and rejects copied
template prose for passed checks.
Template files ending in `.template.json` and the generated
`manual-validation-audit.json` are ignored by manual audits. Any other
malformed JSON, wrong artifact kind, or entry without `targetId` under the
manual evidence directory is reported as invalid evidence and fails strict
manual readiness. For reviewed entries, the audit records the latest evidence
file and `latestEntryFingerprint`; combined readiness carries those
fingerprints in `manualEvidence` so reviewers can tie the Phase 6 gate to the
exact manual evidence content.

Examples:

```sh
fleury benchmark web-suite --runs=3
fleury benchmark web-suite --runs=5 --output-dir=profiling/web/baselines/2026-06-08-dom-retained --scoreboard=profiling/web/baselines/2026-06-08-dom-retained/scoreboard.md --scoreboard-json=profiling/web/baselines/2026-06-08-dom-retained/scoreboard.json
fleury benchmark web-scoreboard --input=profiling/web/baselines/2026-06-08-dom-retained --output=profiling/web/baselines/2026-06-08-dom-retained/scoreboard.md --json-output=profiling/web/baselines/2026-06-08-dom-retained/scoreboard.json
fleury benchmark web-scoreboard --input=profiling/web/baselines/2026-06-08-dom-retained --write-thresholds=profiling/web/baselines/2026-06-08-dom-retained/thresholds.candidate.json
fleury benchmark web-threshold-review --input=profiling/web/baselines/2026-06-08-dom-retained/thresholds.candidate.json --write-plan=profiling/web/baselines/2026-06-08-dom-retained/threshold-review-plan.md
fleury benchmark web-threshold-review --input=profiling/web/baselines/2026-06-08-dom-retained/thresholds.candidate.json --output=profiling/web/baselines/2026-06-08-dom-retained/thresholds.json --json-output=profiling/web/baselines/2026-06-08-dom-retained/threshold-review.json --expect-input-fingerprint=FNV1A64_FROM_REVIEW_PLAN --reviewed-by=REVIEWER --review-context="Chrome VERSION on PLATFORM, retained DOM product baseline"
fleury benchmark web-scoreboard --input=profiling/web/baselines/2026-06-08-dom-retained --thresholds=profiling/web/baselines/2026-06-08-dom-retained/thresholds.json --strict
fleury benchmark web-semantic-audit --input=profiling/web/baselines/2026-06-08-dom-retained --output=profiling/web/baselines/2026-06-08-dom-retained/semantic-coverage.md --json-output=profiling/web/baselines/2026-06-08-dom-retained/semantic-coverage.json --max-fallback-cells=0 --strict
fleury benchmark web-manual-validation --write-plan=profiling/web/manual/plan.md
fleury benchmark web-manual-validation --write-templates=profiling/web/manual/templates --target-preset=v1
fleury benchmark web-manual-validation --write-template=profiling/web/manual/templates/chrome-ime-macos.template.json --template-target=chrome-ime-macos
fleury benchmark web-manual-validation --update-provenance=profiling/web/manual/evidence/chrome-ime-macos.review.json --template-target=chrome-ime-macos '--reviewed-by=<reviewer>' --captured-at=now '--browser-version=<Chrome version used for manual validation>'
fleury benchmark web-manual-validation --update-page-signal=profiling/web/manual/evidence/chrome-ime-macos.review.json --template-target=chrome-ime-macos --signal-id=<required-page-signal-id> --signal-status=pass --observed-value=<expected-value> '--signal-notes=<reviewer observation>'
fleury benchmark web-manual-validation --update-check=profiling/web/manual/evidence/chrome-ime-macos.review.json --template-target=chrome-ime-macos --check-id=<required-check-id> --check-status=pass '--check-notes=<reviewer observation>'
fleury benchmark web-manual-validation --input=profiling/web/manual --output=profiling/web/manual/review.md --json-output=profiling/web/manual/manual-validation-audit.json --strict
```

For the Phase 6 readiness gate, keep reviewed JSON artifacts alongside the
human-readable Markdown. The reviewed threshold policy must include explicit
per-scenario entries for the scored product scenarios; defaults-only policies
are accepted only when a local diagnostic run explicitly passes
`--no-require-scenario-thresholds`. Keep the `threshold-review.json` promotion
summary in sync with `thresholds.json`; readiness compares the summary
`outputPolicyFingerprint` with the frame scoreboard's
`thresholdPolicyFingerprint`, so hand-editing a reviewed policy requires a new
promotion summary and regenerated scoreboard. Readiness also verifies the
summary `inputPath` and `inputPolicyFingerprint` against the candidate policy
that was reviewed, so changing `thresholds.candidate.json` after plan
generation requires regenerating the plan before promotion.

```sh
fleury benchmark web-scoreboard --input=profiling/web/baselines/2026-06-08-dom-retained --min-runs=3 --require-comparable-environment --thresholds=profiling/web/baselines/2026-06-08-dom-retained/thresholds.json --json-output=profiling/web/baselines/2026-06-08-dom-retained/scoreboard.json --strict
fleury benchmark web-semantic-audit --input=profiling/web/baselines/2026-06-08-dom-retained --max-fallback-cells=0 --json-output=profiling/web/baselines/2026-06-08-dom-retained/semantic-coverage.json --strict
fleury benchmark web-manual-validation --input=profiling/web/manual --json-output=profiling/web/manual/manual-validation-audit.json --strict
fleury benchmark web-readiness --scoreboard=profiling/web/baselines/2026-06-08-dom-retained/scoreboard.json --semantic-audit=profiling/web/baselines/2026-06-08-dom-retained/semantic-coverage.json --manual-audit=profiling/web/manual/manual-validation-audit.json --threshold-review=profiling/web/baselines/2026-06-08-dom-retained/threshold-review.json --json-output=profiling/web/baselines/2026-06-08-dom-retained/web-readiness.json --strict
```

The equivalent packaged command writes a `web-readiness-bundle.json` manifest,
the machine-readable readiness inputs, bundled manual validation plan, Markdown
readiness report, and synchronized default/retirement preflight artifact pairs
under one directory.
The manifest includes `artifactFingerprints` for each generated artifact other
than the manifest itself, including default-preflight JSON/Markdown files, so a
reviewer can confirm the packet has not drifted after generation. It also
records `sourceInputFingerprints` for the source capture JSON, manual evidence
JSON, manual validation page source/HTML/served JS and browser smoke test
source, retained web implementation Dart files, Fleury core package Dart files,
package-local readiness/release tool Dart files, the root `fleury benchmark`
launcher, package configuration files, threshold policy, and threshold-review
files that existed at generation time. If
`threshold-review-plan.md` exists next to the threshold policy, the bundle
fingerprints it as a source input and reports whether its embedded input
fingerprint still matches the candidate threshold policy. The input block also
records manual target scope, and generated follow-up commands preserve explicit
`--target` filters instead of widening them to the default preset.
`remainingReleaseActions` summarizes the final bundle verification and
bundle-bound default preflight commands whenever preview default-preflight
artifacts were generated. Those preview artifacts are diagnostics only: their
JSON records `diagnosticOnly: true` plus the final bundle and automated
validation paths that must be used for the release gate. If readiness is still
blocked, the same list also
includes the external review/manual-evidence steps and follow-up commands
needed to prepare templates, collect reviewed evidence, refresh the packet, and
verify it. Manual evidence actions carry the manual validation page build,
serve, and browser smoke commands so reviewers can prepare and preflight the
same page before manual checks. They also carry package
and repo-root provenance/check-update command templates so reviewers can update
evidence one field group at a time without hand-editing JSON. Manual evidence
actions only include no-overwrite starter commands while the selected
`*.review.json`
starter file is missing; once a starter exists, the action fingerprints it and
tells the reviewer to fill the existing file. Threshold-review actions include
a `captureEnvironment` summary and
`reviewContextHint` from the captured Chrome/Dart/platform/headless/frame-budget
metadata, so reviewers do not have to infer review context from raw captures.
When that hint is present, the generated plan and promotion command templates
pre-fill `--review-context` from the captured run while leaving
`--reviewed-by=<reviewer>` as the required human replacement before promotion.
Bundles with remaining actions also write `web-release-actions.md` so reviewers
can read that action graph without digging through the manifest JSON:

```sh
fleury benchmark web-readiness-bundle --captures=profiling/web/baselines/2026-06-08-dom-retained --manual=profiling/web/manual --output-dir=profiling/web/baselines/2026-06-08-dom-retained/readiness --thresholds=profiling/web/baselines/2026-06-08-dom-retained/thresholds.json --threshold-review=profiling/web/baselines/2026-06-08-dom-retained/threshold-review.json --max-fallback-cells=0 --write-default-preflights --completion-audit=docs/implementation/web-rfc-completion-audit.json --strict
fleury benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-08-dom-retained/readiness/web-readiness-bundle.json --strict --json
fleury benchmark web-default-preflight --readiness=profiling/web/baselines/2026-06-08-dom-retained/readiness/web-readiness.json --bundle=profiling/web/baselines/2026-06-08-dom-retained/readiness/web-readiness-bundle.json --target=make-dom-default --strict --json
```

`--completion-audit=PATH` writes a compact, machine-readable RFC status artifact
from the generated bundle plus strict bundle verification. It is useful for
architecture re-review because it separates architecture-review readiness from
release-evidence readiness and final release readiness. `releaseEvidenceReady`
can become true once strict readiness, strict bundle verification, and automated
retained-host validation have all passed, but `releaseReady`,
`defaultFlipReady`, and `temporaryPathRetirementReady` stay false until the final
bundle-bound preflights pass rather than merely diagnostic preflight snapshots.
The nested `completionScopes` object gives reviewers a direct machine-readable
answer for whether the branch is ready for architecture re-review, which
release-evidence actions are still outstanding, and which default/retirement
preflight gates remain deferred. Each release scope reports both
`remainingReleaseActionIds` and `satisfiedCurrentEvidenceActionIds`, which keeps
already-green current-packet checks separate from human or final-gate work that
still remains.

The bundle verifier checks generated artifact fingerprints, source input
fingerprints, expected source-input path coverage, package
command-working-directory metadata, and manifest consistency between
`web-readiness-bundle.json`, the indexed JSON artifacts, and the generated
release-action graph. Strict verification recomputes the current expected
source/evidence path sets for capture, manual, template, manual page,
implementation, tooling, package configuration, and threshold inputs, then
fails if an expected path is missing from the manifest. It also requires
`artifacts.manualPlan` to keep the human manual-validation plan bound into the
packet, and it cross-checks manual-evidence latest-entry fingerprints,
threshold/manual release-action commands, generated diagnostic preflight
metadata, and release-action command templates. The bundle-bound default
preflight verifies the same packet integrity plus the `artifacts.readinessJson`
path before evaluating the release action.
Use it as the final `make-dom-default` or `retire-temporary-paths` gate after
the packet has passed strict readiness.

For tooling, documentation, threshold-review, and readiness-audit changes, reuse
the promoted capture directory and regenerate scoreboards or readiness bundles
from existing JSON. Re-run `web-capture` or `web-suite` only when changes touch
the browser runtime, retained DOM presenter, input/focus/clipboard path,
semantics projection, benchmark scenario behavior, or when producing a final
evidence refresh. When recapturing a suite, keep the default compile-once mode
unless the purpose of the run is to debug compile/page setup.
