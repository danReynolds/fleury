# Fleury Web RFC Phase Audit

Status: implementation review checkpoint
Updated: 2026-06-09
Worktree: `codex/fleury-web-phase1`

This audit maps the web-render-backend RFC phase gates to the implementation
currently in the Phase 1 worktree. It distinguishes code-backed automated
coverage from empirical gates that still require calibrated browser runs or
manual browser validation.

## Summary

The branch now contains the automated architecture spine for the DOM-first web
host:

- shared runtime ownership through `TuiRuntime` plus frame-loop and damage
  handoff through `TuiFrameLoop`;
- rAF-backed `FrameScheduler` integration for browser hosts, with an
  asynchronous timer fallback when `requestAnimationFrame` is unavailable;
- retained DOM visual surface over `FrameSurface` and `FramePresentationPlan`;
- source-level layout-read guard that keeps browser geometry reads isolated to
  `DomCellMetrics.measure()` in the host read phase;
- explicit unsupported inline-image placeholders for protocol cells while the
  DOM surface continues to advertise no inline-image support;
- browser metrics, input trace replay, clipboard, caret geometry, semantics,
  and focus coordination;
- product-safe retained semantics defaults: disabling `runTuiWebDom` semantics
  requires `allowInaccessibleDiagnostics: true` because the visual grid is
  `aria-hidden`;
- browser capture/report/scoreboard tooling with optional CDP counters and
  semantic coverage fallback audits;
- per-scenario benchmark threshold policy support plus candidate policy
  generation for reviewed release gates;
- manual browser validation plan/template/audit tooling;
- combined Phase 6 readiness audit tooling over reviewed frame, semantic, and
  manual evidence artifacts plus a default/retirement preflight over the
  resulting readiness JSON;
- readiness bundle tooling that generates those JSON artifacts from existing
  capture and manual-evidence directories.

It is not yet a release claim. The remaining hard gates for the current v1
release scope are empirical:

- calibrated repeated scenario captures under agreed product/browser
  conditions;
- agreed per-scenario performance threshold values captured in a reviewed
  threshold policy for strict benchmark gates.

IME and VoiceOver/screen-reader validation are intentionally not part of the
current v1 release gate. They remain available as explicit follow-up targets
once the team is ready to validate native browser behavior rather than only the
automated DOM/input/semantic backstops.

## Phase Status

| Phase | Automated Status | Evidence | Remaining Gate |
| --- | --- | --- | --- |
| Phase 1: Shared Runtime and Damage Handoff | Landed | `package:fleury/fleury_host.dart`, `TuiRuntime`, `TuiFrameLoop`, native `run_tui.dart`, xterm `run_tui_web.dart`, retained DOM `run_tui_surface.dart`, `browserFrameFlushScheduler`, no-rAF scheduler fallback, `FrameScheduler`, `TuiDirtyRows` | None known in code; `TuiRuntime` is intentionally narrow and leaves terminal/browser presentation, input-source lifetimes, debug UI, and semantics policy host-owned. |
| Phase 2: Host Skeleton and Visual DOM | Landed | `runTuiSurface`, `runTuiWebDom`, public `TuiSurfaceHost` handle, `FrameSurface`, `FramePresentationPlan`, `CellSpanBuilder`, `DomGridSurface`, `DomCellMetrics`, `SemanticDomPresenter`, `WebHostInstrumentation` | DOM is explicit, not the package default. The RFC Phase 6 default flip remains later. |
| Phase 3: Input, Resize, Clipboard, IME | Automated path, trace fixtures, and manual evidence harness landed | `DomInputSource`, `keyEventFromBrowser`, composition handling, `browser_input_traces.dart`, `dom_input_trace_fixture_test.dart`, pointer/wheel mapping, `WebClipboard`, textarea caret positioning, queued input tests, `web/manual_validation.dart`, `web_manual_validation.dart`, `chrome-ime-macos` target template | No current release blocker; reviewed primary-browser IME evidence is a follow-up validation target before claiming IME support. |
| Phase 4: Retained Semantics, Focus, Accessibility | Automated backstop and coverage audit landed; VoiceOver manual evidence deferred | `SemanticsOwner`, retained no-op semantic stats, semantic bounds, semantic fallback coverage, `SemanticDomPresenter`, `WebFocusCoordinator`, queued semantic activation, safe link projection, `web_semantic_coverage_audit.dart`, `web/manual_validation.dart`, `web_manual_validation.dart`, explicit `chrome-voiceover-macos` follow-up target | No current release blocker; manual screen-reader smoke is a follow-up accessibility focus, and semantic coverage audit results only cover captured widget states. |
| Phase 5: Benchmark Gate | Instrumentation, repeated-capture workflow, strict threshold gates, per-scenario threshold policy support, candidate threshold policy generation, promoted local candidate baseline, tightened capture accounting, corrected local baseline, semantic no-op optimization, post-optimization baseline, artifact retention policy, comparable run-environment gate, semantic fallback audit, runtime subphase accounting, and compile-once suite reuse landed | `web_frame_capture.dart`, `web_frame_suite.dart`, `web_frame_report.dart`, `web_frame_scoreboard.dart`, `web_semantic_coverage_audit.dart`, `profiling/web/.gitignore`, `profiling/web/README.md`, `profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh`, scenario catalog, `fleuryWebFrameThresholds` policy files, `--write-thresholds`, strict report gates, strict suite scoreboard gates, run-environment signatures, semantic fallback gates, CDP layout/style/task/heap/DOM counters, `/tmp/fleury_web_baseline_tight_BE8BTN/scoreboard.md`, `/tmp/fleury_noop_semantic_retained_smoke.json`, `/tmp/fleury_web_baseline_post_semantics_cO1oqK/scoreboard.md`, `/tmp/fleury_env_capture_smoke.json`, `/tmp/fleury_env_scoreboard_smoke` | Review the local candidate baseline against agreed product/browser conditions, convert candidate thresholds into reviewed per-scenario values, and investigate runtime build/paint plus semantic-apply variance before pass/fail release claims. |
| Phase 6: Harden and Retire Temporary Paths | Readiness guard, artifact bundler, automated validation artifact, default/retirement preflight, and local readiness-candidate bundle landed; default flip not started | `web_readiness.dart`, `web_readiness_bundle.dart`, `web_automated_validation.dart`, `web_default_preflight.dart`, `fleury benchmark web-readiness`, `fleury benchmark web-readiness-bundle`, `fleury benchmark web-automated-validation`, `fleury benchmark web-default-preflight`, `profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate`, xterm-compatible `runTuiWeb` remains available and documented as legacy/demo transport | Requires reviewed thresholds, strict readiness pass, and strict default preflight before making DOM the default or retiring temporary paths. |

## Review Checklist

Reviewers should focus on these architectural questions before more surface area
is added:

- Is the narrow `TuiRuntime` boundary the right host-neutral owner for
  framework services and root lifecycle, while leaving platform presentation
  and input-source policy to native/web hosts?
- Is `FramePresentationPlan` sufficiently backend-neutral for a future WebGL
  grid, especially the dirty-row and span-model boundaries?
- Are the semantics and focus boundaries correct enough to leave VoiceOver as a
  focused follow-up instead of blocking the current web milestone?
- Do the capture/report/scoreboard artifacts expose the right counters to
  distinguish runtime-build-bound, runtime-layout-bound, runtime-paint-bound,
  dirty-row-diff-bound, span-build-bound, semantic-apply-bound,
  DOM-apply-bound, and browser-layout-bound failures?
- Is keeping `runTuiWebDom` explicit until Phase 6 the right rollout posture?

## Verification Snapshot

Latest verification recorded in
`docs/implementation/web-rfc-execution-log.md` includes:

- `cd packages/fleury && dart analyze`
- `cd packages/fleury_web && dart analyze`
- `cd packages/fleury_web && dart test`
- `cd packages/fleury_web && dart test -p chrome`
- `cd packages/fleury && dart test test/semantics/semantics_test.dart`
- `cd packages/fleury && dart test test/tool/terminal_matrix_tool_test.dart`
- smoke `web_frame_capture`, `web_frame_report`, and `web_frame_scoreboard`
  runs over a real headless Chrome capture
- smoke `web_frame_suite` run over a real headless Chrome capture plus strict
  scoreboard generation
- smoke `web_frame_suite` run with permissive strict total-frame and semantic
  coverage gates, producing a scoreboard gate `pass`
- focused browser smokes confirming tightened capture accounting: input steps
  count post-frame work as actual frames while normal steps remain one frame
  per step
- corrected full local `web_frame_suite --runs=3` baseline over 11 scenarios,
  producing 33 captures, 912 measured frames over 816 driven steps, and a
  strict min-run scoreboard under `/tmp/fleury_web_baseline_tight_BE8BTN`
- promoted local retained DOM candidate baseline under
  `profiling/web/baselines/2026-06-08-local-dom-retained`, producing 33
  captures across 11 scenarios, a candidate threshold policy, a passing
  candidate-threshold scoreboard, and readiness-candidate artifacts; local
  performance remains runtime-render/semantic-apply dominated rather than
  DOM-apply dominated
- retained semantic no-op smoke over `noop-160x50`, showing retained semantic
  node counts with zero fallback loss and semantic apply time dropping to
  1.3 ms by the third retained frame
- post-optimization full local `web_frame_suite --runs=3` baseline under
  `/tmp/fleury_web_baseline_post_semantics_cO1oqK`, again producing 33
  captures, 912 measured frames over 816 driven steps, zero uncovered semantic
  cells, no DOM-dominant scenario, and a `noop-160x50` semantic p95 median
  improvement from 505.2 ms to 27.0 ms against the corrected baseline
- web benchmark artifact retention policy: generated defaults now write under
  ignored `profiling/web/runs/`, while intentionally reviewed evidence is
  promoted under visible `profiling/web/baselines/`
- web suite artifact pairing: repeated retained DOM suites now write
  `scoreboard.json` next to `scoreboard.md` by default, with
  `--scoreboard-json=PATH` available for explicit reviewed evidence layouts
- run-environment metadata and comparable-environment strict gate: new captures
  record Chrome/Dart/OS/headless/frame-budget/run-step metadata, and strict
  scoreboards can require one complete environment signature per scenario
- per-scenario threshold policy support: `web_frame_scoreboard.dart`,
  `web_frame_suite.dart`, `web_readiness_bundle.dart`, and root benchmark
  launchers accept `--thresholds=PATH` with policy `defaults` plus
  `scenarios[scenarioId]` overrides
- shared runtime extraction: `TuiRuntime` now owns the shared `BuildOwner`,
  `FocusManager`, `TuiBinding`, `PointerRouter`, root mount/update/unmount
  lifecycle, post-frame flush, and render entry point used by native
  `runTui`, xterm-compatible `runTuiWeb`, and retained DOM `runTuiSurface`
- host SPI boundary: `package:fleury/fleury_host.dart` now re-exports
  `fleury_core.dart` plus the shared scheduler, runtime, frame-loop, damage,
  input-dispatch, and semantic-update contracts used by native and browser
  hosts; `fleury_core.dart` and `fleury.dart` no longer export those host-only
  primitives directly
- candidate threshold policy generation: `web_frame_scoreboard.dart`,
  `web_frame_suite.dart`, and root benchmark launchers accept
  `--write-thresholds=PATH` with configurable headroom so promoted captures can
  produce a reviewable draft `fleuryWebFrameThresholds` policy
- semantic coverage audit: `web_semantic_coverage_audit.dart` and
  `fleury benchmark web-semantic-audit` report fallback frames/cells/nodes and
  can strict-gate fallback reliance for reviewed capture directories; audit
  JSON/Markdown now includes top fallback capture diagnostics for coverage
  backfill review
- manual validation harness: `web/manual_validation.dart`,
  `web/manual_validation.html`, `web_manual_validation.dart`, and
  `fleury benchmark web-manual-validation` generate manual browser
  checklists, batch JSON evidence templates via `--write-templates=DIR`, and
  strict manual-evidence audits; `--json-output` can persist the manual audit
  JSON even when strict manual evidence is still incomplete
- browser scheduler fallback: `browserFrameFlushScheduler` now falls back to an
  asynchronous timer flush when `requestAnimationFrame` is unavailable or
  unusable, with Chrome coverage for both the direct scheduler path and the
  manual validation page reaching its retained DOM ready marker without rAF
- browser input trace fixture replay: `browser_input_traces.dart` covers
  navigation keys, shortcut repeat, printable text, paste, IME commit/cancel,
  pointer down/drag/up, and wheel up/down; `dom_input_trace_fixture_test.dart`
  replays those traces in Chrome against `DomInputSource`
- Phase 6 readiness audit: `web_readiness.dart` and
  `fleury benchmark web-readiness` combine reviewed frame-scoreboard,
  semantic-coverage, and manual-validation JSON artifacts into one strict gate;
  a local default-path smoke correctly reports missing reviewed artifacts with
  `strictPass: false`; the scoreboard, semantic coverage, manual validation,
  and readiness tools can all persist their JSON artifacts with `--json-output`
  even when strict gates fail
- Phase 6 readiness bundle: `web_readiness_bundle.dart` and
  `fleury benchmark web-readiness-bundle` generate the scoreboard, semantic
  coverage, bundled manual validation plan, manual validation audit, and
  readiness JSON/Markdown artifacts from existing evidence directories without
  duplicating gate math; the bundle now
  asks each underlying gate tool to write its own JSON artifact and then
  validates that artifact before composing the manifest; with
  `--write-default-preflights`, the same bundle refresh also writes the
  default/retirement preflight Markdown/JSON artifact pairs from the generated
  `web-readiness.json`; the bundle also persists
  `web-readiness-bundle.json` as the machine-readable manifest for the artifact
  set, with `artifactFingerprints` for generated evidence files other than the
  manifest itself and `sourceInputFingerprints` for the capture, manual
  evidence, selected-target manual template, manual validation page
  source/HTML/served JS plus browser smoke test source, retained web
  implementation Dart files, retained web automated host test files, Fleury
  core package Dart files, package-local readiness/release tool Dart files, the
  root `fleury benchmark` launcher, package configuration files,
  threshold-policy, and threshold-review inputs that existed at generation
  time; threshold review
  plans are fingerprinted when present and
  classified as current, stale, missing, or missing-input-fingerprint in the
  threshold-review action details; the manifest input records manual target
  scope plus command working directory; generated follow-up commands preserve
  explicit target filters and render their required working directory beside
  each command block;
  strict verification also cross-checks manual-evidence latest-entry
  fingerprints, threshold/manual release-action commands, generated diagnostic
  preflight metadata, and release-action command templates;
  bundles with generated preview preflights include `remainingReleaseActions`
  for final bundle verification and bundle-bound preflight commands, while
  blocked bundles also include threshold review, manual evidence, regeneration,
  and verification steps; threshold-review actions summarize the captured
  Chrome/Dart/platform/headless/frame-budget environment and include a
  `reviewContextHint` for reviewer provenance; when available, that hint is
  copied into `suggestedReviewContext` and the generated plan/promotion
  `--review-context` arguments while the reviewer placeholder remains required;
  manual template preparation is included only when templates are missing,
  invalid, or stale, while current templates are
  reported with per-target fingerprints; template freshness is target-specific
  and covers metadata, technology labels, manual page command instructions,
  smoke command, serve note, target-specific page signals, environment keys,
  page-level provenance attributes, provenance blanks, required check IDs, and
  exact generated check instructions through a shared registry consumed by the
  manual tool and readiness bundle; manual
  evidence actions report missing/existing starter evidence state, emit a
  no-overwrite `web_manual_validation.dart --write-starter` command only when
  the starter file is missing, and fingerprint existing starter files as edit
  targets; the starter command validates template target metadata, review
  instructions, provenance blanks, and required checks before writing evidence;
  manual evidence actions also include a non-runnable
  `web_manual_validation.dart --update-provenance` command template for filling
  reviewer, capture-time, and browser-version provenance without marking
  checks passed; they also include a non-runnable
  `web_manual_validation.dart --update-page-signal` command template for
  recording one required page signal at a time with an expected observed value
  and reviewer observation notes; they also include a non-runnable
  `web_manual_validation.dart --update-check` command template for recording one
  observed required check at a time; manual evidence actions also include the
  manual validation page build, static-server setup, serve, browser smoke, and
  strict audit commands; regeneration,
  verification, and default-preflight actions
  include structured details for input/output paths, strict/json expectations,
  verification scope, and bundle-binding requirements;
  failed bundles write
  `web-release-actions.md` so the same action graph, including the package cwd
  needed by generated `dart run tool/...` commands, is reviewable without
  opening the manifest JSON;
  `--verify=PATH --strict`
  recomputes those fingerprints and the expected source-input path set over an
  existing bundle so review packets can be checked for missing or stale
  generated artifacts, omitted or stale source evidence, and
  command-working-directory metadata without rerunning capture or readiness
  generation
- Phase 6 default/retirement preflight: `web_default_preflight.dart` and
  `fleury benchmark web-default-preflight` consume `web-readiness.json` and
  fail retained DOM default flips or temporary-path retirement unless strict
  readiness has already passed; final release-action checks are bundle-bound by
  default, inferring sibling `web-readiness-bundle.json` and
  `web-automated-validation.json` unless explicit paths are passed, so they
  verify packet fingerprints, retained-host automated validation evidence, and
  ensure the readiness JSON is the one indexed by the readiness bundle;
  `--allow-unbundled` is kept only for readiness-only diagnostics, and
  generated unbundled preview artifacts mark themselves `diagnosticOnly: true`
  while recording the final bundle/automated-validation paths
- local default/retirement preflight artifacts:
  `readiness-candidate/web-default-preflight-make-dom-default.{md,json}` and
  `readiness-candidate/web-default-preflight-retire-temporary-paths.{md,json}`
  both strict-fail over the current candidate readiness artifact with detailed
  manual target diagnostics
- local readiness-candidate bundle over
  `profiling/web/baselines/2026-06-08-local-dom-retained`: frame scoreboard
  and semantic coverage pass, while readiness remains false because reviewed
  `chrome-ime-macos` manual evidence is missing
- refreshed local retained DOM Phase 1 candidate baseline under
  `profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh`:
  33 captures across 11 scenarios, 912 measured frames, comparable
  run-environment pass, candidate-threshold scoreboard pass, strict
  zero-fallback semantic audit pass, and readiness still false because the
  threshold policy is still `reviewState: candidate` and real reviewed evidence
  is missing for `chrome-ime-macos`
- refreshed runtime-subphase retained DOM candidate baseline under
  `profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh`:
  33 captures across 11 scenarios, 912 measured frames, comparable
  run-environment pass, candidate-threshold scoreboard pass, strict
  zero-fallback semantic audit pass, runtime build/layout/paint subphase
  samples present for every scenario, and readiness still false only because
  the threshold policy is still `reviewState: candidate` and real reviewed
  evidence is missing for `chrome-ime-macos`
- reviewed-threshold readiness gate: machine-readable scoreboards now expose
  `thresholdPolicyReviewState`, and Phase 6 readiness requires
  `reviewState: reviewed` by default so candidate threshold policies cannot
  become release claims accidentally
- reviewed-threshold provenance/context gate: reviewed threshold policies must
  carry `reviewedBy`, `reviewedAt`, and `reviewContext` metadata before
  default Phase 6 readiness can pass
- scenario-threshold readiness gate: default Phase 6 readiness now requires
  every frame scenario to match an explicit threshold-policy scenario entry,
  so a defaults-only reviewed policy cannot accidentally claim product
  readiness; `--no-require-scenario-thresholds` is reserved for local
  diagnostics
- threshold review promotion tooling: `web_threshold_review.dart` and
  `fleury benchmark web-threshold-review` promote candidate threshold policies
  to reviewed `thresholds.json` artifacts with reviewer/timestamp provenance,
  without recapturing browser frames or hand-editing policy metadata;
  `--write-plan=PATH` creates a non-promoting Markdown review packet before
  promotion, candidate policies with captured environment metadata prefill the
  plan's suggested browser/platform context, `--review-context-hint=TEXT`
  remains available as an override or legacy-candidate fallback,
  `--json-output=PATH` on a plan-only run only names
  the future promotion summary in the generated command template, and the
  promotion summary can now be persisted as `threshold-review.json` with
  `--json-output` during promotion; generated promotion commands include
  `--expect-input-fingerprint=<candidate fingerprint>` so a candidate policy
  changed after review cannot be promoted from a stale plan
- threshold review summary gate: default Phase 6 readiness now requires a
  matching `threshold-review.json` summary for reviewed threshold policies,
  and verifies output path, reviewer, timestamp, review context, and scenario
  count against the frame scoreboard metadata
- threshold policy fingerprint gate: threshold review summaries now record
  candidate input path plus candidate and reviewed policy fingerprints, frame
  scoreboards report the threshold policy fingerprint they loaded, and Phase 6
  readiness rejects a stale promotion summary whose
  `outputPolicyFingerprint` no longer matches the scoreboard's
  `thresholdPolicyFingerprint` or whose `inputPolicyFingerprint` no longer
  matches the candidate policy named by the summary
- validation cadence: docs now distinguish fast artifact-only iteration
  (scoreboards, semantic audits, threshold review, readiness bundles) from
  browser recapture, which is reserved for runtime/presenter/input/semantics
  behavior changes or final evidence refreshes
- compile-once benchmark cadence: `web_frame_suite.dart` now compiles the
  browser benchmark page once into a temporary page directory and reuses it for
  all captures in the suite by default; `--no-compile-once` remains available
  for diagnostics
- manual evidence template hardening: generated templates now live under
  `profiling/web/manual/templates/`, files ending in `.template.json` are
  ignored by audits, and real evidence should be copied to non-template JSON
  files after validation; templates now include structured `target` metadata
  and `reviewInstructions`, including target-specific `requiredPageSignals`,
  and readiness bundles mark older minimal templates, stale serve prose, stale
  page signals, or stale check instructions as stale
- manual evidence timestamp provenance hardening: generated templates leave
  `capturedAt` blank, forcing reviewed evidence copied from a template to
  record the actual validation time before strict manual readiness can pass
- manual evidence invalid-file gate: manual validation audits ignore only
  `*.template.json` files and the generated `manual-validation-audit.json`;
  any other malformed JSON, wrong artifact kind, or entry without `targetId`
  is reported as invalid evidence and prevents strict manual readiness
- manual evidence fingerprinting: valid manual evidence entries now produce
  `latestEntryFingerprint` values in the per-target audit, and combined
  readiness carries latest manual evidence file/timestamp/reviewer/fingerprint
  details under `manualEvidence`
- reviewed-manual provenance gate: manual validation targets cannot strict-pass
  with status/checks alone; each evidence entry must include reviewer,
  parseable ISO timestamp, browser version, the `manual_validation.html` page,
  and target-specific IME or assistive-tech environment metadata
- reviewed-manual page-signal observation gate: passed manual validation entries
  must record `observedPageSignals` with `status: "pass"` and matching
  `observedValue` for every target-required page signal, including the retained
  DOM ready marker and the IME caret-position marker where applicable
- reviewed-manual observation gate: passed manual checks must include reviewer
  observation notes; blank notes or notes copied verbatim from the generated
  check instruction are rejected, so starter files cannot pass by flipping
  statuses without recording what the reviewer actually observed
- manual target-match gate: manual validation entries must match the audited
  target browser/platform, and screen-reader entries must match the target
  assistive technology, so wrong-browser evidence cannot satisfy the Chrome
  primary-browser gates
- manual readiness diagnostics: combined Phase 6 readiness now carries
  manual `missingTargets`, `needsReviewTargets`, and per-target provenance
  blockers in machine-readable check details so reviewers can distinguish
  missing evidence from incomplete reviewed evidence
- manual target check diagnostics: combined Phase 6 readiness now carries
  per-target manual `failingTargetDetails` with required check counts and
  missing/failed/blocked check IDs, so the readiness JSON directly exposes the
  IME 0/6 backstop state
- manual target Markdown diagnostics: `web-readiness.md` mirrors those
  per-target manual check details in a Manual Target Diagnostics table for
  human review packets
- default preflight detail preservation: `web_default_preflight.dart` now
  preserves failed readiness check details in persisted preflight JSON and
  mirrors manual target diagnostics into Markdown, so `make-dom-default` and
  `retire-temporary-paths` gates stay explainable at the final release-action
  layer
- synchronized preflight artifact generation: `web_readiness_bundle.dart` and
  `fleury benchmark web-readiness-bundle` accept `--write-default-preflights`
  so release-action evidence packets can regenerate both preflight artifact
  pairs alongside the readiness JSON without rerunning browser captures
- machine-readable completion audit: the same bundle command accepts
  `--completion-audit=PATH` to write a compact RFC status artifact that derives
  phase status, architecture-review readiness, release-evidence readiness,
  final release readiness, default-flip/temporary-path blockers, manual evidence
  state, default-preflight proof state, and remaining release-action status from
  the generated bundle plus strict bundle verification; its `completionScopes`
  block keeps the architecture-review scope separate from release evidence and
  default/retirement scopes so the branch can be re-reviewed without implying a
  DOM default flip, and separates remaining release action IDs from
  already-satisfied current-packet action IDs
- default-preflight binding metadata: readiness bundles now mark generated
  default preflight artifacts as `defaultPreflightBundleBound: false` and
  `defaultPreflightFinalGateRequiresBundle: true`, making clear that generated
  artifacts are diagnostic snapshots while final release-action preflights still
  run with `--bundle=...`; generated preview JSON also records
  `diagnosticOnly: true`, `finalGateRequiresBundle: true`, and
  `finalGateRequiresAutomatedValidation: true`; the preflight tool infers a
  sibling bundle by default, reports missing/stale bundle artifacts as release
  blockers, and requires `--allow-unbundled` for diagnostics-only readiness
  checks; the
  remaining-release action graph now emits those final preflight commands
  whenever preview preflight artifacts are generated, even if strict readiness
  is already green; the same graph now inserts
  `run-automated-web-host-tests` between strict bundle verification and the
  bundle-bound default preflights, with one command that writes
  `web-automated-validation.json` plus separate Chrome and VM command detail
  tied to the fingerprinted `webAutomatedTestFiles` source-input group; those
  bundle-bound preflights now require the automated validation artifact and
  verify generated artifact fingerprints, source-input fingerprints and
  expected source-input path coverage including retained web implementation,
  retained web automated host tests, Fleury core, readiness/release tool, and
  package configuration files,
  command-working-directory metadata, required manual-plan manifest binding,
  manifest summary/action consistency, and readiness JSON path binding
- root release-command hardening: `fleury benchmark` catalog/help examples now
  show reviewed threshold inputs for readiness bundles, bundle-bound default
  preflights, shell-safe threshold review placeholders, and machine-readable
  placeholder metadata for non-runnable review command templates; readiness
  bundle release actions also expose repo-root threshold review plan/promotion
  commands, downstream regenerate/verify/preflight detail metadata, and
  repo-root manual-validation commands for template preparation or refresh,
  starter creation, provenance update, and strict audit, with regression
  coverage in `terminal_matrix_tool_test.dart` and
  `web_readiness_bundle_tool_test.dart`
- threshold promotion placeholder enforcement: `web_threshold_review.dart`
  rejects the literal reviewer placeholder and generic browser/platform
  placeholders during promotion, while non-promoting review plans still render
  those placeholders and now warn that the command is intentionally not runnable
  as written
- over-budget threshold acknowledgement: `web_threshold_review.dart` now
  refuses to promote a candidate whose scenario thresholds allow over-budget
  frames unless the reviewer passes `--allow-over-budget-thresholds` and a
  concrete `--review-note=TEXT`; the reviewed policy and promotion summary
  record the acknowledged scenario IDs
- candidate threshold policy precision fix: generated
  `maxOverBudgetPercent` values now clamp at `100.0` after headroom, with
  regression coverage in `web_frame_scoreboard_tool_test.dart`
- refreshed damage evidence from the Phase 1 candidate baseline:
  `noop-160x50` latest capture retained 0 dirty rows / 0 replaced rows / 0
  DOM nodes created / 0 semantic fallback cells; `single-dirty-cell-160x50`
  latest capture retained 1 dirty row / 1 replaced row / 1 DOM node created /
  0 semantic fallback cells
- refreshed performance evidence from the Phase 1 candidate baseline:
  local over-budget behavior remains runtime and semantic-apply dominated
  rather than DOM-apply dominated; the latest runtime-subphase baseline ranges
  from `noop-160x50` at 92.80 ms to `scroll-row-churn-160x50` at 832.10 ms,
  while `stress-300x100` remains fully over budget locally and is now mostly
  runtime-build dominated
- focused post-baseline damage smoke under
  `/tmp/fleury_web_damage_smoke_after_semantics_zUt1WY`: `noop-160x50`
  retained 0 dirty rows / 0 replaced rows / 0 semantic fallback cells, and
  `single-dirty-cell-160x50` retained 1 dirty row / 1 replaced row / 0
  semantic fallback cells after the sparse row-diff and RepaintBoundary
  semantic replay fixes
- incremental semantic DOM and split semantic timing smoke under
  `/tmp/fleury_web_semantic_counters_smoke_2N18cb`: `single-dirty-cell-160x50`
  showed 1 semantic updated node, 0 semantic DOM element creations, 1 retained
  semantic DOM element reuse, 2 semantic DOM attributes set, 0 fallback cells,
  and split timing fields for tree build, coverage, diff, presenter, and focus
  sync
- capture-tool cleanup hardening smoke under
  `/tmp/fleury_web_capture_exit_smoke_qp7HEo`: short
  `single-dirty-cell-160x50` capture exited with code 0 after writing JSON,
  with no remaining `web_frame_capture.dart` process
- repeated cleanup suite smoke under
  `/tmp/fleury_web_suite_cleanup_smoke_DcZ4UT`: 11 one-run retained DOM
  scenario captures, 304 measured frames, strict comparable-environment
  scoreboard generation, strict zero-fallback semantic audit, and no remaining
  capture/suite process after completion
- retained DOM wrapper cleanup: `runTuiWebDom` now removes generated visual and
  semantic root elements when the returned `TuiSurfaceHost` is disposed, while
  lower-level host resources still dispose through `runTuiSurface`
- web public API boundary coverage: the production barrel intentionally exports
  `runTuiWebDom`, returned `TuiSurfaceHost`, `runTuiWeb`, and selected
  instrumentation/focus diagnostics while keeping `runTuiSurface`,
  `DomGridSurface`, `DomInputSource`, `SemanticDomPresenter`, and
  `DomCellMetrics` package-owned
- retained DOM no-layout-read guard: `test/web_public_api_boundary_test.dart`
  scans `lib/src` for browser layout-read APIs and allows them only in
  `DomCellMetrics`, preventing frame presentation, semantic presentation,
  input, and focus code from adding synchronous layout reads outside the host
  read phase
- retained DOM demo page: `web/dom_demo.html` and `web/dom_demo.dart` provide a
  runnable no-xterm demo for the explicit retained DOM path, while
  `web/index.html` remains the legacy xterm bridge demo until Phase 6;
  `test/dom_demo_test.dart` browser-loads the demo source and verifies retained
  DOM render/input/submit behavior with a deterministic frame flush, including
  a `mounted` to `ready` marker transition after the first presented frame
- manual validation page readiness: `web/manual_validation.dart` now exposes a
  frame-backed `mounted` to `ready` marker transition, and
  `test/manual_validation_page_test.dart` verifies the retained DOM frame, no
  xterm DOM, semantic root/textbox/button/link/status projection, safe-link
  attributes, positioned hidden-textarea caret metadata, and semantic
  action-to-status behavior before real manual evidence is
  collected; the same browser smoke test source is now fingerprinted in
  readiness bundles with the manual validation page files
- manual validation page provenance: the manual page now writes browser
  version, platform, user-agent, and page-name attributes on `document.body`
  and exposes the same browser/platform/page metadata through a semantic status
  node; browser smoke coverage asserts those attributes before manual evidence
  collection, and readiness release actions surface the exact required
  provenance-attribute list so stale templates cannot hide missing browser
  metadata
- manual evidence provenance hardening: `web_manual_validation.dart` now rejects
  placeholder reviewer and browser-version provenance, so copied starter files
  cannot pass strict readiness by filling placeholders instead of real review
  data; readiness release actions render package-local and repo-root
  manual-validation commands for template preparation or refresh, starter
  creation, provenance update, per-check update, and strict audit, and strict
  bundle verification rejects stale generated manual command fields
- retained DOM frame-failure cleanup: `runTuiSurface` now marks the returned
  host disposed and runs best-effort cleanup if a frame-time presentation
  failure escapes the scheduler; browser coverage verifies the original frame
  error is rethrown, host resources and clipboard state are restored, and later
  frame requests are ignored
- browser page test isolation: retained DOM demo and manual validation page
  browser tests now use distinct explicit host IDs, so they can run together
  without sharing the fallback `#fleury-app` host namespace
- generated manual validation readiness instructions:
  `web_manual_validation.dart` now tells reviewers to wait for
  `data-fleury-manual-validation="ready"` before starting checks, and generated
  evidence templates include frame-backed readiness requirements plus
  self-contained manual page command working directory, build, browser smoke,
  static-server setup, serve, and local URL instructions for the IME page-load
  target; the VoiceOver semantic-host target remains available for the follow-up
  accessibility pass
- `git diff --check`
