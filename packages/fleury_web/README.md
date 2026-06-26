# Fleury Web

Run [fleury](../fleury) apps in a browser through the retained DOM host:

- **`mountApp`** runs Fleury-owned apps through the retained DOM host:
  Fleury paints into a `CellBuffer`, browser frames flush under
  `requestAnimationFrame` with an asynchronous timer fallback for embedded
  browser surfaces that lack rAF, dirty rows update retained DOM row elements,
  browser input is queued into the shared runtime loop, clipboard uses the
  browser API with fallback behavior, and a separate semantic DOM mirrors the
  app for accessibility.

The retained DOM host is the normal development target for Fleury-owned web
apps. The serve/remote paths reuse the same core runtime contracts behind their
own hosts.

## How it works

fleury's core (`package:fleury/fleury_core.dart`) and host SPI
(`package:fleury/fleury_host.dart`) are free of `dart:io`, so they compile to
JavaScript. This package imports the host SPI and supplies the missing browser
platform pieces:

- **Runtime and frame loop:** `runTuiSurface` shares Fleury's `TuiRuntime`
  framework-service/root lifecycle, `FrameScheduler`, and `TuiFrameLoop`
  buffer/damage lifecycle with native hosts.
- **Visual DOM:** `DomGridSurface` retains one row element per visible row and
  replaces only dirty row children with spans built from the shared span model.
- **Metrics:** `DomCellMetrics` is the only component that reads browser
  layout. Event-time coordinate mapping uses the last completed measurement.
- **Input:** `DomInputSource` maps keyboard, text, composition, paste, pointer,
  and wheel browser events into queued Fleury `TuiEvent`s.
- **Clipboard:** `WebClipboard` writes through the browser clipboard API and
  falls back to Fleury's in-process clipboard state when browser access is
  unavailable.
- **Semantics:** `SemanticDomPresenter` projects Fleury semantics into a
  separate accessibility DOM. Visual rows stay `aria-hidden`, so
  `mountApp` keeps semantics enabled for product use and requires
  `allowInaccessibleDiagnostics: true` before callers can disable them for
  focused local performance diagnostics.
- **Instrumentation:** `RecordingWebHostInstrumentation`,
  `tool/web_frame_capture.dart`, `tool/web_frame_report.dart`, and
  `tool/web_frame_scoreboard.dart` produce browser frame captures, strict
  report gates, repeated-run scoreboards, semantic coverage audits, and manual
  browser validation packets.

## Run the retained DOM demo

```sh
dart pub get
dart compile js web/dom_demo.dart -o web/dom_demo.dart.js

# serve the web/ directory with any static file server, e.g.:
dart pub global activate dhttpd
dart pub global run dhttpd --path web
# then open http://localhost:8080/dom_demo.html
```

You'll get a retained DOM Fleury app with browser input, state updates,
semantic status, a semantic action, and a selectable-text DOM surface.

## Run the counter demo

```sh
dart pub get
dart compile js web/main.dart -o web/main.dart.js

# serve the web/ directory with any static file server, e.g.:
dart pub global activate dhttpd
dart pub global run dhttpd --path web
# then open the printed http://localhost:8080
```

You'll get a focused counter you can drive with the arrow keys, mounted into a
plain host `<div>` through the retained DOM host.

## Capture retained DOM frame metrics

```sh
dart run tool/web_frame_capture.dart --scenario=normal-80x24 --output=/tmp/fleury-web.json
dart run tool/web_frame_report.dart --input=/tmp/fleury-web.json --json
dart run tool/web_frame_scoreboard.dart --input=../../profiling/web --output=../../profiling/web/scoreboard.md --json-output=../../profiling/web/scoreboard.json
dart run tool/web_frame_suite.dart --runs=5 --output-dir=../../profiling/web/baselines/2026-06-08-dom-retained --scoreboard=../../profiling/web/baselines/2026-06-08-dom-retained/scoreboard.md --scoreboard-json=../../profiling/web/baselines/2026-06-08-dom-retained/scoreboard.json --write-thresholds=../../profiling/web/baselines/2026-06-08-dom-retained/thresholds.candidate.json
dart run tool/web_threshold_review.dart --input=../../profiling/web/baselines/2026-06-08-dom-retained/thresholds.candidate.json --write-plan=../../profiling/web/baselines/2026-06-08-dom-retained/threshold-review-plan.md
dart run tool/web_semantic_coverage_audit.dart --input=../../profiling/web --output=../../profiling/web/semantic-coverage.md --json-output=../../profiling/web/semantic-coverage.json --max-fallback-cells=0
dart run tool/web_manual_validation.dart --write-plan=../../profiling/web/manual/plan.md
dart run tool/web_manual_validation.dart --input=../../profiling/web/manual --output=../../profiling/web/manual/review.md --json-output=../../profiling/web/manual/manual-validation-audit.json --strict
dart run tool/web_readiness.dart --scoreboard=../../profiling/web/baselines/web-frame-scoreboard.json --semantic-audit=../../profiling/web/baselines/web-semantic-coverage.json --manual-audit=../../profiling/web/manual/manual-validation-audit.json --threshold-review=../../profiling/web/baselines/threshold-review.json --json-output=../../profiling/web/baselines/web-readiness.json --strict
dart run tool/web_readiness_bundle.dart --captures=../../profiling/web/baselines/2026-06-08-dom-retained --manual=../../profiling/web/manual --output-dir=../../profiling/web/baselines/2026-06-08-dom-retained/readiness --thresholds=../../profiling/web/baselines/2026-06-08-dom-retained/thresholds.json --threshold-review=../../profiling/web/baselines/2026-06-08-dom-retained/threshold-review.json --max-fallback-cells=0 --write-default-preflights --strict
dart run tool/web_default_preflight.dart --readiness=../../profiling/web/baselines/2026-06-08-dom-retained/readiness/web-readiness.json --bundle=../../profiling/web/baselines/2026-06-08-dom-retained/readiness/web-readiness-bundle.json --target=make-dom-default --json-output=../../profiling/web/baselines/2026-06-08-dom-retained/readiness/web-default-preflight-make-dom-default.json --strict
dart run tool/web_frame_suite.dart --scenarios=normal-80x24,large-160x50 --runs=3
dart run tool/web_threshold_review.dart --input=../../profiling/web/baselines/2026-06-08-dom-retained/thresholds.candidate.json --output=../../profiling/web/baselines/2026-06-08-dom-retained/thresholds.json --json-output=../../profiling/web/baselines/2026-06-08-dom-retained/threshold-review.json --expect-input-fingerprint=FNV1A64_FROM_REVIEW_PLAN --reviewed-by=REVIEWER --review-context="Chrome VERSION on PLATFORM, retained DOM product baseline" --allow-over-budget-thresholds --review-note="Explain any accepted over-budget thresholds."
dart run tool/web_frame_suite.dart --runs=3 --thresholds=../../profiling/web/baselines/2026-06-08-dom-retained/thresholds.json --max-semantic-uncovered-cells=0
```

Captures include Fleury per-frame slices for runtime render plus runtime
build/layout/paint subphases, dirty-row diff fallback, span building, DOM
apply, semantic apply, and total frame time, plus optional Chrome/CDP browser
counters such as layout/style/task duration, JS heap, and DOM node counts.
They also record run environment metadata such as Chrome version, Dart version,
OS version, headless/headful mode, warmup steps, requested steps, and frame
budget.
When runtime build/layout/paint subphase timings are present, dominant-slice
classification uses those subphases instead of the aggregate
`runtimeRenderMs`; older captures without subphase data still fall back to the
aggregate runtime render slice.
The suite runner forwards threshold flags into a strict repeated-run scoreboard
so calibrated baseline values can become CI-style gates. Repeated suites require
comparable run-environment metadata by default; pass
`--no-require-comparable-environment` only for legacy capture analysis.
By default, `web_frame_suite.dart` compiles the browser benchmark page once into
a temporary page directory and reuses it for every capture in the suite. Pass
`--no-compile-once` only when debugging capture setup or compile isolation.
For scenario-specific gates, pass `--thresholds=PATH` to `web_frame_scoreboard`,
`web_frame_suite`, or `web_readiness_bundle`. The policy is JSON with optional
global defaults and per-scenario overrides:

```json
{
  "schemaVersion": 1,
  "kind": "fleuryWebFrameThresholds",
  "reviewState": "reviewed",
  "reviewedBy": "reviewer-name",
  "reviewedAt": "2026-06-08T12:00:00Z",
  "reviewContext": "Chrome 127 on macOS, retained DOM Phase 1 baseline",
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

The merge order is CLI gate flags, then policy `defaults`, then
`scenarios[scenarioId]`, so a reviewed policy can set product thresholds while
ad hoc CLI values remain useful for local plumbing checks.
To draft a policy from repeated captures, pass `--write-thresholds=PATH` to
`web_frame_scoreboard` or `web_frame_suite`. The generated file is marked
`reviewState: candidate`; it uses observed per-scenario aggregate maxima plus
configurable headroom, and includes a captured-environment summary with a
suggested review context when capture metadata is available. Use
`web_threshold_review.dart` or
`fleury benchmark web-threshold-review` after human review to promote the
candidate into `thresholds.json` without recapturing browser frames. Pass
`--write-plan=PATH` before promotion to generate a non-promoting Markdown packet
with the candidate fingerprint, scenario thresholds, review checklist, and
promotion command template. When the candidate policy has
`generatedFrom.captureEnvironment.reviewContextHint`, the plan uses that
captured browser/platform context by default while still requiring a reviewer
name before promotion. `--review-context-hint=TEXT` is reserved for overriding
that context or filling it for legacy candidate files that do not carry captured
environment metadata. The generated promotion command
also carries `--expect-input-fingerprint=<candidate fingerprint>`; keep that
argument when promoting so a candidate file changed after review fails before
writing reviewed output. The promotion command rejects the literal reviewer
placeholder and generic browser/platform placeholders; replace them with
concrete reviewer and captured-environment values before writing a reviewed
policy. If any scenario threshold allows over-budget frames, promotion also
requires `--allow-over-budget-thresholds` plus a concrete
`--review-note=TEXT` explaining why those thresholds are acceptable for the
reviewed baseline. When used with `--write-plan` alone, `--json-output=PATH`
only seeds the generated promotion command's summary path; it does not write
the summary or require promotion provenance. Pass `--json-output=PATH` during
promotion to keep a `threshold-review.json` summary next to the reviewed
threshold policy. The summary records the candidate input path and fingerprint,
reviewed-policy fingerprint, generated-from metadata, scenario IDs, and any
explicit over-budget threshold acknowledgement. The
reviewed file used for readiness must set
`reviewState: reviewed`, `reviewedBy`, `reviewedAt`, and `reviewContext`;
candidate policies and
reviewed policies without provenance/context are rejected by the readiness gate
unless explicitly relaxed for local diagnostics. Phase 6 readiness also
requires every scored scenario to match an explicit `scenarios[scenarioId]`
threshold entry by default; a defaults-only policy is useful for local plumbing
checks, but it is not precise enough to claim product readiness unless run with
`--no-require-scenario-thresholds`.
The semantic coverage audit reports how often visible text needed the
low-priority fallback bridge because no richer geometry-bearing semantic node
covered it. That keeps the accessibility backstop visible while reviewers
decide which widgets need richer first-party semantics. When fallback is
non-zero, the audit includes `topFallbackCaptures` overall and per scenario so
reviewers can open the exact capture files that drove the coverage gap.
The readiness audit consumes reviewed JSON artifacts from the frame scoreboard,
semantic coverage audit, and manual validation audit. It intentionally gates on
machine-readable JSON rather than Markdown so Phase 6 defaulting has an
auditable evidence chain. The frame scoreboard must have been generated from a
reviewed threshold policy with per-scenario threshold entries by default.
Reviewed threshold policies must also have a matching `threshold-review.json`
promotion summary; `web_readiness.dart` derives the sibling file next to the
threshold policy unless `--threshold-review=PATH` is supplied. The readiness
audit compares the summary `outputPolicyFingerprint` with the
`thresholdPolicyFingerprint` reported by the frame scoreboard, so editing
`thresholds.json` after promotion requires regenerating the promotion summary
and scoreboard evidence. It also verifies the summary `inputPath` and
`inputPolicyFingerprint` against the candidate policy that was reviewed, so
changing `thresholds.candidate.json` after plan generation requires
regenerating the plan before promotion.
Use `--json-output=PATH` when running `web_frame_scoreboard.dart`,
`web_semantic_coverage_audit.dart`, `web_manual_validation.dart`, or
`web_readiness.dart` directly so strict failures still leave durable
machine-readable diagnostics. Manual validation audits ignore template files
ending in `.template.json` and the generated `manual-validation-audit.json`
file, but any other malformed or non-entry JSON file under the manual evidence
directory is reported as invalid evidence and fails strict readiness.
The readiness bundle tool generates those JSON artifacts from an existing
capture directory and reviewed manual evidence directory, then runs the
combined readiness audit over the generated bundle. It asks each underlying
gate tool to write its JSON artifact through `--json-output`, validates those
files, and writes `web-readiness-bundle.json` as the artifact manifest. The
manifest includes `artifactFingerprints` for the generated scoreboard,
semantic audit, manual validation plan, manual audit, readiness JSON/Markdown,
and default-preflight artifacts, so review packets can detect stale files even
when paths are unchanged. The manifest also includes
`sourceInputFingerprints` for the
capture JSON files, manual evidence JSON files, selected-target manual
template JSON files, manual validation page source/HTML/served JS and browser
smoke test source, retained web implementation Dart files, retained web
automated host test files, Fleury core package Dart files, package-local
readiness/release tool Dart files, the root `fleury benchmark` launcher,
package configuration files, threshold policy, and
threshold-review summary that existed when the bundle was
generated. When a threshold review plan exists next to the policy, the bundle
fingerprints that plan too and reports whether the plan input fingerprint is
current, stale, or missing in the threshold-review action details. Its input
block records the manual target scope as `targetPreset` plus `targetIds` when
explicit targets are used, plus the `commandWorkingDirectory` that
package-relative generated commands expect. Generated follow-up commands
preserve the selected target scope. Remaining release actions include
structured details for downstream
artifact refresh, bundle verification, automated retained-host validation JSON,
and default-preflight gates, including
the relevant input/output paths, strict/json expectations, bundle-binding
requirements, and reviewer next steps.
Add `--write-default-preflights` to also write the `make-dom-default` and
`retire-temporary-paths` Markdown/JSON preflight artifact pairs next to
`web-readiness.json`. These generated preflight artifacts are readiness-bound
diagnostic snapshots rather than bundle-bound final gates; their JSON records
`diagnosticOnly: true`, `finalGateRequiresBundle: true`, and
`finalGateRequiresAutomatedValidation: true`. The bundle manifest records
`defaultPreflightBundleBound: false` and
`defaultPreflightFinalGateRequiresBundle: true`, while release-action commands
run the final preflights with `--bundle=...`. `remainingReleaseActions` lists
the final bundle verification, an automated retained-host validation command
that writes `web-automated-validation.json`, and bundle-bound default
preflight commands when preview preflights were generated, even if readiness
itself is green. The generated preflight actions depend on the automated-test
action and pass `--automated-validation=...`, so reviewers have one ordered
graph from source/artifact verification through retained-host test execution
to persisted evidence and the release gate. When readiness is still blocked,
the same list also
includes the
threshold review, manual evidence, regeneration, and verification commands
still needed before a release action can pass. It also
lists manual template preparation when required templates are missing, invalid,
or stale; current templates are instead reported on the per-target manual
evidence actions with template fingerprints. Templates are considered current
only when they match the selected target's expected metadata, target-specific
technology, manual validation page, ready signal, accepted status values,
manual page commands, smoke command, and serve note, target-specific page
signals, required environment keys, blank provenance fields, required check IDs, and exact
generated check instructions.
That target/template contract is shared by the manual validation tool and the
readiness bundle so generated starter commands cannot disagree with bundle
freshness.
Manual evidence actions also
report whether the no-overwrite starter evidence file exists. Missing starter
files get a `web_manual_validation.dart --write-starter` command against the
target template; existing starter files are fingerprinted and treated as edit
targets instead of emitting a command that would fail the no-overwrite guard.
The starter command validates that the template still matches the current
target metadata, review instructions, required environment keys, provenance
blanks, and required checks before writing evidence. Manual evidence actions
also include a non-runnable provenance command template that can fill
`reviewedBy`, `capturedAt`, and `environment.browserVersion` on an existing
starter without changing target/check status. They also include the manual
validation page build/serve commands, browser smoke command, and the strict
audit command to run after review. Where a command is generated for release
work, the action also carries the equivalent repo-root `fleury benchmark
web-manual-validation` command for template preparation or refresh, starter
creation, provenance update, and strict audit. Threshold-review
actions mark promotion command templates as non-runnable until the reviewer
placeholder is replaced. When captured environment metadata is available, the
action also includes `suggestedReviewContext`, pre-fills the review-context
argument in the plan and promotion command templates, and still asks the
reviewer to verify that context before promotion. The suggestion is derived
from the action's `captureEnvironment` summary plus `reviewContextHint` from
the scoreboard's captured Chrome, Dart, platform, headless, and frame-budget
metadata. Bundles with remaining actions write
`web-release-actions.md`, a human-readable rendering of that action graph with
dependencies, blockers, details, commands, and the command working directory
repeated beside each command block.
The repo-level launcher mirrors these release actions: use
`fleury benchmark web-threshold-review --write-plan=...` or
`fleury benchmark web-threshold-review --input=... --output=...` from the root
threshold-review command blocks when planning or promoting reviewed thresholds,
`fleury benchmark web-manual-validation --write-templates=...`,
`--write-template=...`, `--write-starter=...`, `--update-provenance=...`,
`--update-page-signal=...`, `--update-check=...`, or `--strict` from the root
manual-validation command blocks when preparing templates, creating starters,
filling reviewed provenance, recording individual page-signal and check
observations, or auditing manual evidence,
`fleury benchmark web-automated-validation --json-output=... --strict` to
produce the retained-host automated validation artifact, then pass that file to
`fleury benchmark web-default-preflight --automated-validation=...` or rely on
the sibling `web-automated-validation.json` default.
Pass `--completion-audit=PATH` to `web_readiness_bundle.dart` or
`fleury benchmark web-readiness-bundle` when a review packet needs a compact
machine-readable summary of architecture-review readiness, release-evidence
readiness, final release readiness, default-flip readiness, remaining blockers,
and phase evidence. The `completionScopes` block separates the fast review
scope from release scopes: `architectureReview` can be ready while
`releaseEvidence` and `releaseDefault` still list deferred gate/action IDs.
Scope action lists distinguish `remainingReleaseActionIds` from
`satisfiedCurrentEvidenceActionIds`, so a current candidate packet can show
strict bundle verification or automated retained-host validation as green
without treating human review/manual evidence as complete.
`releaseEvidenceReady` means strict readiness, strict bundle verification, and
retained-host automated validation have passed; `releaseReady`
stays false until the bundle-bound `make-dom-default` and
`retire-temporary-paths` preflights have also passed. The completion audit is
written beside the packet but is not added to
`web-readiness-bundle.json`; keeping it outside the manifest avoids making the
manifest fingerprint depend on a status artifact that itself depends on the
manifest.
	To re-check an existing review packet without regenerating any
	evidence, run `web_readiness_bundle.dart --verify=PATH --strict`;
verification recomputes both generated artifact fingerprints and source-input
fingerprints, confirms the recorded `commandWorkingDirectory` matches the
package cwd used by the verifier, and checks manifest summaries plus generated
release actions against the indexed JSON artifacts. That manifest check also
binds latest manual-evidence entry fingerprints, threshold-review action
commands, manual-evidence action commands, generated diagnostic preflight
metadata, and release-action command templates. For capture, manual,
template, manual page, retained web implementation, retained web automated
tests, Fleury core, readiness/release tool, root launcher, package
configuration, threshold-policy, threshold-review, and
threshold-review-plan inputs, strict verification also recomputes the expected
current input path set and fails if an expected file was omitted from the
manifest. It fails if any indexed file, expected source input, required
metadata, or manifest field is missing or has drifted. Strict verification also
requires `artifacts.manualPlan`, so readiness packets cannot drop the
reviewer-facing manual validation plan while still passing the bundle
integrity check.
Before making retained DOM the default or retiring temporary web transport
paths, run `web_default_preflight.dart` or
`fleury benchmark web-default-preflight` against the generated
`web-readiness.json`. The preflight does not rerun capture work; it turns the
strict readiness artifact into an explicit release-action gate for
`make-dom-default` or `retire-temporary-paths`. Final release-action checks are
bundle-bound by default: the preflight infers sibling
`web-readiness-bundle.json` and `web-automated-validation.json` files next to
`web-readiness.json`, or you can pass `--bundle=PATH` and
`--automated-validation=PATH` explicitly. The preflight verifies the
`web-readiness-bundle.json` artifact/source-input fingerprints and expected
source-input path coverage, including retained web implementation, retained web
automated tests, Fleury core, readiness/release tool, and package configuration
sources, manifest summary fields, and generated release-action graph, then
confirms the readiness JSON belongs to that bundle. It also verifies that the
automated validation artifact strict-passed the canonical retained DOM browser
and VM test commands, still matches the current `webAutomatedTestFiles` source
fingerprints, and was produced from the package cwd. It also checks the bundle's
recorded
`commandWorkingDirectory` against the package cwd, matching
`web_readiness_bundle.dart --verify`. Use `--allow-unbundled` only for local
readiness-only diagnostics; that mode is not a release gate. Unbundled
preflight JSON/Markdown now marks itself `diagnosticOnly: true` and records the
inferred final bundle and automated-validation artifact paths reviewers must use
for the release gate.
`--frames` controls driven benchmark steps; captures still report the actual
measured frame count, including post-frame work caused by a step.

For docs, tooling, threshold-review, and readiness-audit changes, regenerate
scoreboards or readiness bundles from existing captures. Re-run Chrome capture
or the full suite only when runtime, retained DOM, input/focus/clipboard,
semantics projection, benchmark scenario behavior, or final evidence needs new
browser observations. When a full suite is required, keep the default
compile-once mode so the run pays the Dart-to-JavaScript compile cost once
instead of once per capture.

Default capture and suite output goes under `profiling/web/runs/`, which is
generated and ignored. Promote reviewed evidence by passing an explicit
`--output` or `--output-dir` under `profiling/web/baselines/`; those promoted
artifacts are intentionally visible to git.

## Manual validation

The retained DOM manual validation page exercises the real DOM host, browser
input source, hidden textarea, semantic DOM presenter, semantic action
dispatch, and safe-link projection:

```sh
dart test -p chrome test/manual_validation_page_test.dart
dart compile js web/manual_validation.dart -o web/manual_validation.dart.js
dart pub global activate dhttpd
dart pub global run dhttpd --path web
```

Run the browser smoke test before collecting evidence; it confirms the retained
DOM page reaches its ready marker and exposes the required semantic/input
projection in Chrome. Open `manual_validation.html` from that local server.
The page sets
`data-fleury-manual-validation="mounted"` after retained DOM host construction
and upgrades it to `"ready"` only after the first retained DOM frame is
recorded. Start manual checks only after `document.body` reports
`data-fleury-manual-validation="ready"`; `"mounted"` does not prove first-frame
presentation.
The same page also exposes manual-evidence provenance on the document body:
`data-fleury-manual-browser-version`, `data-fleury-manual-platform`,
`data-fleury-manual-user-agent`, and `data-fleury-manual-page`. It mirrors that
metadata into a semantic status node so the evidence page can be checked through
the retained semantics path as well as through DOM attributes. Use the browser
version attribute as the source for `--browser-version` after confirming the
intended primary browser is the one used for the manual session.

Use `tool/web_manual_validation.dart` to generate the current checklist, create
JSON evidence templates, and strict-audit reviewed entries. Pass
`--write-templates=<dir>` to prepare one `<target-id>.template.json` file per
selected target, or use `--write-template=<path> --template-target=<id>` for a
single target. The explicit v1 preset currently has no required manual browser
targets; `primary` remains a compatibility alias for that scoped release set.
The `chrome-ime-macos` and `chrome-voiceover-macos` targets remain available
through explicit `--target=...` flags or `--target-preset=all` for future IME
and screen-reader validation. Manual evidence belongs under
`profiling/web/manual/` because it is a release-gate or roadmap evidence
artifact, not a generated benchmark run. Passing entries must
include concrete reviewer and environment provenance, including non-placeholder
`reviewedBy`, `capturedAt`, `environment.browserVersion`,
`environment.fleuryWebPage`, and the target-specific `inputMethod` or
`assistiveTechnology`. Browser, platform, and assistive-technology values must
match the audited target, and placeholder browser-version values are rejected.
`capturedAt` must parse as ISO-8601, and `environment.fleuryWebPage` must be
`manual_validation.html`.
Generated templates and release-action details list the required page
provenance attributes under `reviewInstructions.provenanceAttributes` and
`manualPageProvenanceAttributes`, so stale templates that predate the browser
metadata contract are rejected before review.
Use `--update-provenance=<evidence.json> --template-target=<id>
--reviewed-by=<reviewer> --captured-at=now --browser-version=<Chrome version>`
to fill only provenance fields on a starter or copied evidence file. This
helper intentionally does not change the top-level status or required-check
statuses, so the strict audit still fails until the reviewer records the actual
manual observations.
Use `--update-page-signal=<evidence.json> --template-target=<id>
--signal-id=<required-page-signal-id> --signal-status=pass
--observed-value=<expected-value> --signal-notes=<reviewer observation>` to
record one required page signal without hand-editing JSON. The helper validates
the evidence contract before and after the edit, requires the observed value to
match the target's expected signal value for pass updates, and rejects copied
template descriptions for passed signals.
Use `--update-check=<evidence.json> --template-target=<id>
--check-id=<required-check-id> --check-status=pass
--check-notes=<reviewer observation>` to update one required check without
hand-editing JSON. The helper validates the evidence contract before and after
the edit, rejects copied template notes for passed checks, and can set the
top-level evidence status with `--entry-status=pass` only after the reviewer has
recorded all required page signals and checks.
Readiness release actions render package-local and repo-root manual-validation
commands for template preparation or refresh, starter creation, provenance
updates, per-page-signal updates, per-check updates, and strict audit. Strict
bundle verification rejects stale generated manual command templates.
Every passed required page signal must carry `observedValue` equal to the
signal's expected value, and every passed required check must carry reviewer
observation notes. Strict audit rejects missing observed page signals, blank
notes, and notes copied verbatim from the generated check instruction, so a
copied starter file cannot pass by changing statuses alone.
Keep generated templates named `*.template.json` and keep the generated
`manual-validation-audit.json` at that exact file name. The audit ignores those
files, but treats any other broken JSON, wrong artifact kind, or entry without
`targetId` as invalid evidence so stale or half-copied files cannot be hidden.
Generated templates carry a `target` block and `reviewInstructions` block with
the repo-relative manual page command working directory, page commands, local
URL, browser smoke command, exact serve note, and `requiredPageSignals` so a
copied starter file
remains self-describing outside the release-action Markdown. Readiness bundles
treat older templates without that metadata, stale serve prose, stale page
signals, or stale check instructions as stale and regenerate them before manual
evidence collection.
For each target with evidence, the audit records the latest evidence file,
timestamp, reviewer, and `latestEntryFingerprint`; the combined readiness JSON
carries those fields under `manualEvidence` so final review packets can point
to the exact manual evidence content that was audited.
