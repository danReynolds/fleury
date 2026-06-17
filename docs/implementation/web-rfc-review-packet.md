# Fleury Web RFC Review Packet

Status: ready for architecture re-review, not a release gate.
Updated: 2026-06-09
Worktree: `codex/fleury-web-phase1`

Use this packet as the first reviewer entry point for the web RFC
implementation. It summarizes the code-backed architecture, the latest local
candidate evidence, and the remaining empirical gates. The deeper phase map is
in [web-rfc-phase-audit.md](web-rfc-phase-audit.md), and the chronological
implementation record is in
[web-rfc-execution-log.md](web-rfc-execution-log.md).

The current machine-readable completion status is in
[web-rfc-completion-audit.json](web-rfc-completion-audit.json). It is the
compact artifact to use when deciding whether this branch is architecture
review-ready, release-evidence-ready, final-release-ready, default-flip-ready,
or still blocked on external evidence. `releaseEvidenceReady` means strict
readiness plus retained-host automated validation are green; `releaseReady`
still requires the final bundle-bound default and retirement preflights.
The nested `completionScopes` block makes the intended fast review boundary
explicit: `architectureReview` can be ready for re-review while
`releaseEvidence` and `releaseDefault` remain blocked and list their deferred
gate/action IDs. Release scopes also report
`satisfiedCurrentEvidenceActionIds`, so strict bundle verification and
automated retained-host validation can be credited when they pass without
implying that human threshold review, final default preflights, or deferred
IME/assistive-technology review is done.
Regenerate it from the readiness bundle command with
`--completion-audit=docs/implementation/web-rfc-completion-audit.json`; it is not
fingerprinted inside `web-readiness-bundle.json`, so the manifest remains the
source of truth for generated artifact and source-input integrity.

## Review Decision Requested

Review whether the retained DOM web host is architecturally sound enough to
continue toward Phase 6 evidence collection.

The review should not approve a DOM default flip yet. Defaulting remains gated
on reviewed per-scenario thresholds, a strict readiness pass, and strict
bundle-bound default/retirement preflights. IME and VoiceOver are now
explicitly follow-up validation focuses rather than current default-flip
prerequisites. The explicit v1 manual-validation target set is empty;
`primary` remains a compatibility alias for older commands. The
`chrome-ime-macos` and `chrome-voiceover-macos` targets remain available
through explicit `--target=...` flags or `--target-preset=all`.

## Architecture Under Review

- `package:fleury/fleury_host.dart` is the browser/native host SPI. It
  re-exports the app-facing core plus host-only scheduler, runtime, frame-loop,
  damage, input-dispatch, and semantic-update contracts; those host primitives
  no longer leak through `fleury_core.dart` or the native `fleury.dart`
  umbrella.
- `TuiRuntime` owns shared framework lifecycle: build owner, focus manager,
  binding, pointer router, root mount/update/unmount, post-frame flush, and
  render entry.
- `TuiFrameLoop` owns coalesced frame scheduling and damage handoff for native,
  xterm-compatible web, and retained DOM web hosts.
- Native `runTui`, xterm-compatible `runTuiWeb`, and retained DOM
  `runTuiSurface` all use the shared runtime spine while keeping host-specific
  input, presentation, transport, and cleanup policy outside the core runtime.
- Browser frame scheduling remains host-owned: retained DOM hosts prefer
  `requestAnimationFrame`, but `browserFrameFlushScheduler` falls back to an
  asynchronous timer flush when rAF is absent or unusable so partial embedded
  browser surfaces do not strand the first retained DOM frame.
- The package barrel exports `runTuiWebDom` plus its returned
  `TuiSurfaceHost` handle, but keeps the lower-level `runTuiSurface` assembly
  function and DOM presenter/input/metrics internals private to the package
  while the host proves out.
- `runTuiWebDom` keeps retained semantics enabled for product use. Because the
  visual grid is `aria-hidden`, `semanticsEnabled: false` now throws unless the
  caller also passes `allowInaccessibleDiagnostics: true`; supplying a semantic
  root while disabling semantics is rejected as inconsistent.
- `FramePresentationPlan` is the backend-neutral presentation boundary:
  dirty-row data and cell spans feed the retained DOM presenter today and leave
  room for a future WebGL grid if DOM apply becomes the measured bottleneck.
- Browser layout reads are isolated to `DomCellMetrics.measure()` in the host
  read phase. A VM boundary test scans retained web source and fails if visual
  presentation, semantic presentation, input, or focus code starts using
  browser layout-read APIs directly.
- Protocol/image cells are capability-honest: the DOM surface still reports
  `InlineImageCapability.none`, and both live DOM and static HTML render
  protocol anchors as explicit unsupported inline-image placeholders with
  machine-readable `data-fleury-cell-kind` and `data-fleury-unsupported`
  attributes.
- `DomInputSource`, browser input trace fixtures, textarea caret placement,
  clipboard wiring, focus coordination, semantic presentation, and manual
  validation templates form the browser host layer above that presentation
  boundary.

## Current Recommendation

Keep the DOM path explicit and continue with DOM-first evidence collection.

The latest local captures do not show DOM apply as the dominant failure mode.
The expensive slices are still Dart-side runtime work and semantic apply
variance, so a WebGL rewrite would be premature. The evidence surface now splits
runtime render into build/layout/paint subphases for new captures, while old
captures still fall back to the aggregate `runtimeRenderMs` label. That gives
the next reviewed capture enough detail to separate an apply-bound miss from a
Dart-render-bound miss before choosing WebGL or WASM. Unbounded dirty-row buffer
diff is also timed separately from span building so conservative damage
fallback cost is visible as Dart-side work.

## Code Status

| Area | Status | Review Focus |
| --- | --- | --- |
| Shared runtime and frame loop | Landed | Is `TuiRuntime` narrow enough, and are host lifetimes still host-owned? |
| Native/xterm convergence | Landed | Does `runTuiWeb` keep only terminal transport/presentation concerns? |
| Retained DOM host | Landed | Are setup, disposal, generated-root cleanup, late rAF / no-rAF fallback, clipboard restore, input cleanup, no-layout-read boundaries, and the standalone retained DOM demo robust? |
| Input/clipboard/IME harness | Landed except real IME evidence | Are browser event mappings and trace fixtures representative enough for Phase 3? |
| Semantics/focus/accessibility | Automated backstop landed; VoiceOver manual evidence deferred | Are semantic coverage, focus coordination, and ARIA projection sufficient for current web scope while screen-reader support is handled as a follow-up? |
| Benchmark/readiness tooling | Landed | Are split counters, threshold policy provenance, and readiness gates strict enough? |
| Default/retirement preflight | Landed; not passing yet | Are default flips impossible without reviewed readiness evidence? |

## Latest Candidate Evidence

Primary local candidate directory:

`profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh`

Contents:

- 33 Chrome captures: 11 scenarios, three runs per scenario.
- `scoreboard.md`: human-readable frame scoreboard.
- `scoreboard.json`: machine-readable frame scoreboard produced by the suite.
- `thresholds.candidate.json`: generated candidate threshold policy.
- `threshold-review-plan.md`: non-promoting human review packet for the
  candidate threshold policy.
- `readiness-candidate/scoreboard.json`: strict scoreboard with candidate
  thresholds applied.
- `readiness-candidate/semantic-coverage.json`: strict zero-fallback semantic
  audit.
- `readiness-candidate/manual-validation-plan.md`: bundled manual validation
  plan for the selected target set.
- `readiness-candidate/manual-validation-audit.json`: manual evidence audit.
- `readiness-candidate/web-readiness-bundle.json`: machine-readable manifest
  for the readiness and preflight artifact set.
- `readiness-candidate/web-release-actions.md`: human-readable release-action
  graph generated from the failing readiness bundle.
- `readiness-candidate/web-readiness.json` and `web-readiness.md`: combined
  Phase 6 readiness result.
- `readiness-candidate/web-default-preflight-make-dom-default.md` and
  `.json`: default flip preflight result over the same readiness artifact.
- `readiness-candidate/web-default-preflight-retire-temporary-paths.md` and
  `.json`: temporary-path retirement preflight result over the same readiness
  artifact.

This baseline refresh includes runtime build/layout/paint subphase samples for
every scenario, so `threshold-review-plan.md` no longer contains the runtime
subphase availability warning that appeared on older repeated captures.

The readiness bundle was regenerated with `--write-default-preflights`, so
`web-readiness-bundle.json` indexes the readiness artifact plus the
default/retirement preflight artifact pairs produced from the same
`web-readiness.json`. It also records `artifactFingerprints` for the generated
scoreboard, semantic audit, manual validation plan, manual audit, readiness
reports, and preflight artifacts, so reviewers can detect stale files inside
the packet. The strict
release-action preflight commands remain the final gates before changing
defaults or removing temporary paths.
The bundle also records `sourceInputFingerprints` for source capture files,
manual evidence files, selected-target manual template files, manual validation
page source/HTML/served JS and browser smoke test source, retained web
implementation Dart files, retained web automated host test files, Fleury core
package Dart files, package-local readiness/release tool Dart files, the root
`fleury benchmark` launcher, package configuration files, and threshold-policy
inputs that existed at generation time.
The manual evidence directory may include pending starter evidence files such
as `chrome-ime-macos.review.json` and `chrome-voiceover-macos.review.json`;
they are fingerprinted source inputs so stale files stay visible, but they are
not part of the current v1 release evidence scope unless an explicit manual
target is selected.
Because `threshold-review-plan.md` exists in this packet, the bundle also
fingerprints it and the threshold-review action reports whether the plan's
embedded input fingerprint matches the current candidate threshold policy. The
generated promotion command carries that same value as
`--expect-input-fingerprint`, so a candidate policy changed after review fails
before writing reviewed threshold output. New candidate threshold policies also
carry `generatedFrom.captureEnvironment.reviewContextHint`; standalone
threshold-review plans use that captured hint by default when no
`--review-context-hint` override is supplied.
The bundle input records manual target scope, and generated action commands
preserve explicit `--target` filters instead of widening to the primary preset.
It also records the package `commandWorkingDirectory` required by generated
`dart run tool/...` commands, and `web-release-actions.md` renders that cwd in
the packet header and beside each generated command block.
Bundle verification recomputes generated artifact and source-input
fingerprints, including retained web and Fleury core implementation source
fingerprints, retained web automated host test fingerprints, plus
readiness/release tool and package configuration
fingerprints, checks expected source-input path coverage, checks the
command-working-directory metadata, and validates the manifest summaries plus
final release-action graph against the indexed JSON artifacts. For capture,
manual, template, manual page, implementation, automated-test, tooling, package
configuration, and threshold inputs, verification now fails if the current
expected file set contains a path omitted from `sourceInputFingerprints`. It
also requires
`artifacts.manualPlan`, so the bundled human manual-validation plan cannot be
omitted from the manifest. A hand-edited `web-readiness-bundle.json` can
therefore fail verification even when the external artifacts still hash
correctly.
`remainingReleaseActions` is the machine-readable next-step list for final
bundle verification and bundle-bound preflight checks whenever preview
default-preflight artifacts were generated. While this packet remains red, it
also includes threshold review and packet regeneration. Explicit manual-target
packets additionally include manual template preparation and manual evidence
capture. `web-release-actions.md` renders that same list for reviewers with
each action's dependencies, blockers, details, and concrete commands. Preview
preflight packets also include
`run-automated-web-host-tests`, which points at the fingerprinted
`webAutomatedTestFiles` source-input group, renders the canonical Chrome and VM
test commands, and writes `web-automated-validation.json`; bundle-bound
default preflight actions depend on that action and pass the generated
validation artifact through `--automated-validation=...`. The
threshold-review action includes a `captureEnvironment`
summary and `reviewContextHint` derived from the captured Chrome/Dart/platform
metadata that produced the candidate thresholds. When present, that hint is
copied into `suggestedReviewContext` and the generated `--review-context`
argument for promotion command templates. Current candidate policies also carry
that captured context themselves, so generated plan commands rely on the
candidate input by default instead of passing a redundant
`--review-context-hint`; the reviewer placeholder still must be replaced before
promotion. The promotion template also includes
the plan's expected candidate fingerprint, and the tool refuses promotion if
the loaded candidate no longer matches it. For plan-only threshold-review runs,
`--json-output` only names the future `threshold-review.json` promotion summary
inside the generated command template; it is written only during promotion.
Manual
template preparation is emitted when selected templates are missing, invalid,
or fail the same target-specific freshness contract used by starter evidence
creation. That contract now lives in one shared internal registry consumed by
both tools, including target-specific `requiredPageSignals` such as the IME
hidden-textarea caret-positioned signal. Manual
evidence actions report whether the target starter evidence file exists.
Missing starters get a `web_manual_validation.dart --write-starter` command
for creating the reviewed JSON file from the target template without
overwriting an existing starter file; existing starters are fingerprinted and
treated as edit targets. That command validates the template's current target
metadata, review instructions, environment keys, provenance blanks,
target-specific page signals, required check IDs, and exact generated check
instructions before writing evidence. Manual evidence actions also carry a
non-runnable provenance command template for filling `reviewedBy`,
`capturedAt`, and `environment.browserVersion` on the starter without changing
target/check status, plus the manual validation page build, static-server
setup, serve, and browser smoke commands so reviewers can prepare and preflight
the browser page from the same release-action packet. It is followed by the
strict audit command, which rejects
placeholder reviewer and browser-version provenance, blank notes on passed
checks, missing observed page-signal values, and notes copied verbatim from the
generated check instruction.
Template-preparation actions and manual evidence actions also include
repo-root manual-validation commands via
`fleury benchmark web-manual-validation`, covering template preparation or
refresh, starter creation, provenance update, and strict audit. Strict bundle
verification treats those generated manual command fields as manifest fields so
they cannot drift from the package-local command.
Threshold-review actions mark placeholder command templates as non-runnable
until the reviewer placeholder is replaced and any suggested review context has
been verified. The threshold promotion tool also rejects the literal reviewer
placeholder and generic browser/platform placeholders, so generated review
packets are not accidentally promotable as-is. Threshold-review actions render
both package-local and repo-root plan/promotion command templates, and strict
bundle verification treats those root command templates as generated manifest
fields. Regeneration,
verification, and default-preflight actions also expose structured detail fields
for their paths, strict/json expectations, verification scope, and
bundle-binding requirements so tools can consume the action graph without
parsing shell snippets.

Before re-review, run:

```sh
fleury benchmark web-readiness-bundle --verify=profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-readiness-bundle.json --strict --json
fleury benchmark web-automated-validation --json-output=profiling/web/baselines/2026-06-09-local-dom-retained-subphase-refresh/readiness-candidate/web-automated-validation.json --strict --json
```

That verifier recomputes every recorded generated-artifact and source-input
fingerprint in the packet, verifies expected source-input path coverage,
verifies the recorded package command cwd, and fails if an indexed
JSON/Markdown file, expected source input, or required metadata is missing or
stale. Expected healthy packet counters include `metadataMismatchCount: 0`,
`missingMetadataCount: 0`, and `missingSourceInputCount: 0`. The automated
validation command writes the durable browser/VM test artifact consumed by the
bundle-bound default-preflight gate.

Runnable retained DOM demo:

- `packages/fleury_web/web/dom_demo.html`
- `packages/fleury_web/web/dom_demo.dart`

This page exercises the retained DOM host directly without xterm. It covers
browser input through the hidden textarea, retained visual DOM, semantic DOM,
state updates, and semantic status/action projection. The legacy
`web/index.html` page remains the xterm-compatible demo until Phase 6. Browser
test coverage in `test/dom_demo_test.dart` imports the demo source and verifies
the retained DOM page's render, input, and submit path with a deterministic
frame flush. The page sets `data-fleury-dom-demo="mounted"` after host
construction and upgrades it to `"ready"` only after the first retained DOM
frame is recorded. The demo and manual validation page tests use distinct
explicit host IDs so they can run together without sharing the fallback
`#fleury-app` namespace.

Manual validation page:

- `packages/fleury_web/web/manual_validation.html`
- `packages/fleury_web/web/manual_validation.dart`

This page is the source for real IME evidence collection and the future
screen-reader follow-up. It
sets `data-fleury-manual-validation="mounted"` after retained DOM host
construction and upgrades it to `"ready"` only after the first retained DOM
frame is recorded. Browser coverage in `test/manual_validation_page_test.dart`
imports the page source and verifies the marker transition, absence of xterm
DOM, semantic root/textbox/button/link/status projection, safe-link attributes,
semantic action-to-status updates, and positioned hidden-textarea caret
metadata needed before the manual IME checklist can validate candidate-window
placement in a real browser. It also exercises the production browser
scheduler with `requestAnimationFrame` unavailable and verifies the page still
reaches the retained DOM `"ready"` marker.
The page now also writes `data-fleury-manual-browser-version`,
`data-fleury-manual-platform`, `data-fleury-manual-user-agent`, and
`data-fleury-manual-page` onto `document.body`, and exposes the same browser /
platform / page metadata through a retained semantic status node. Manual
evidence reviewers should use that browser-version attribute as the value for
the provenance helper after confirming the page is running in the intended
primary browser.
`runTuiSurface` also has browser coverage for frame-time presentation failure:
the original frame error is rethrown, the host is marked disposed, resources
and clipboard state are cleaned up best-effort, and later frame requests are
ignored.

Generated manual validation plans and evidence templates now require reviewers
to wait for `data-fleury-manual-validation="ready"` before starting checks. The
manual validation command can generate roadmap target templates with explicit
`--target=chrome-ime-macos`, `--target=chrome-voiceover-macos`, or
`--target-preset=all` arguments, while keeping unfinished templates ignored by
audits through the `*.template.json` suffix. Generated templates intentionally
leave `capturedAt` blank so copied evidence cannot accidentally pass with the
template preparation time as the manual validation time. Templates also carry
structured `target` metadata and
`reviewInstructions`, including the repo-relative manual page command working
directory, build command, static-server setup command, serve command, and local
page URL, plus the exact serve note and target-specific `requiredPageSignals`,
the exact body-level provenance attributes, so copied starter files remain
self-describing; readiness bundles now classify older minimal templates, stale
serve prose, stale page signals, stale provenance attributes, or stale check
instructions as stale.
Reviewers can use `web_manual_validation.dart --update-provenance` to update
only provenance fields on copied/starter evidence; the helper does not mark the
target or checks as passed. They can then use
`web_manual_validation.dart --update-page-signal` to record one required page
signal at a time with a matching observed value and reviewer observation notes,
then `web_manual_validation.dart --update-check` to record one required check
at a time. Passing evidence must fill `observedPageSignals` with the expected
observed values and replace starter checklist prose with reviewer observation
notes on every passed required check; changing statuses to `pass` while
leaving missing page-signal observations, blank notes, copied page-signal
descriptions, or copied generated check instructions keeps the target in
`needsReview`.
The generated packet also renders the equivalent root launcher commands, so
reviewers can prepare templates, create starters, fill provenance, record
page signals and per-check observations, and run the strict audit from repo
root without
translating paths by hand.
Strict bundle verification now checks the generated release-action graph
itself: threshold action commands, explicit manual action commands when
present, manual-evidence latest-entry fingerprints, diagnostic preflight
metadata, and command templates must stay in sync with the indexed JSON
artifacts.
Failed explicit-manual-target readiness bundles surface
`prepare-manual-evidence-templates` only when required templates are missing,
invalid, or stale; when templates are current, per-target manual evidence
actions report `templateStatus: current` plus the template fingerprint and
proceed directly to evidence collection. The generated text treats `"mounted"`
as host construction only, not as evidence that the first retained DOM frame
has presented. The VoiceOver follow-up target also includes an explicit
`manual-page-ready-semantic-host` check, so standalone screen-reader evidence
will still need to prove the retained semantic DOM host is ready and xterm is
absent before accessibility claims can pass. The combined readiness
JSON includes per-target manual diagnostics under
`failingTargetDetails`, including required check counts and missing check IDs.
Once manual evidence exists, it also carries `manualEvidence` entries with the
latest evidence file, capture time, reviewer, and `latestEntryFingerprint` for
each in-scope target, so final review can bind manual approval to exact evidence
content.
The Markdown readiness report mirrors those details in a Manual Target
Diagnostics table, so the Phase 6 gate explains exactly which current manual
evidence is absent without requiring reviewers to open the nested manual audit
first.
The default preflight preserves those failed readiness details in persisted
JSON and mirrors the manual target table in its Markdown output. The readiness
bundle can now regenerate both `make-dom-default` and `retire-temporary-paths`
artifact pairs from the same readiness JSON, so the final gates remain
explainable without hand-synchronizing reports. Those generated preflight
artifacts are readiness-bound diagnostic snapshots because bundle-bound
generation would create a circular fingerprint dependency; their JSON marks
`diagnosticOnly: true` and records the final bundle/automated-validation paths
that reviewers must use. The final release-action preflight commands remain
bundle-bound with `--bundle=...`; direct preflight invocations also infer
sibling `web-readiness-bundle.json` by default and report missing or stale
bundle artifacts as blockers unless `--allow-unbundled` is used for diagnostics
only. Final preflights verify artifact fingerprints, source-input fingerprints,
expected source-input path coverage, package command-working-directory
metadata, and the readiness JSON path.

Candidate result:

- Frame scoreboard passes against generated candidate thresholds and comparable
  run-environment checks. The current candidate scoreboard reports
  `thresholdPolicyFingerprint` and `thresholdPolicyScenarioCount`, so the
  eventual reviewed threshold promotion summary will be tied to the exact
  policy content used by the scoreboard.
- Semantic coverage passes with zero fallback frames, cells, and nodes.
- Runtime subphase coverage is present in all 11 scenarios, so the current
  local packet can distinguish runtime-build, runtime-layout, and runtime-paint
  slices rather than falling back to aggregate `runtimeRenderMs`.
- Readiness correctly fails because threshold policy review state is still
  `candidate`; IME evidence remains a roadmap target rather than a v1
  readiness blocker.

Selected signal:

- `noop-160x50`: 0 dirty rows, 0 replaced rows, 0 created DOM nodes, and
  0 semantic fallback cells in the latest capture.
- `single-dirty-cell-160x50`: 1 dirty row, 1 replaced row, 1 created DOM node,
  and 0 semantic fallback cells in the latest capture.
- Median total-frame p95 ranges locally from `92.80 ms` for `noop-160x50` to
  `832.10 ms` for `scroll-row-churn-160x50`.
- Dominant p95 slices remain Dart-side or semantic in this baseline:
  `semanticApplyMs` dominates most scenario runs, `runtimeBuildMs` dominates
  two of three `stress-300x100` runs, and `runtimePaintMs` dominates two of
  three `scroll-row-churn-160x50` runs. DOM apply remains a secondary slice
  rather than the measured reason to switch to WebGL.

## Remaining Release Gates

- Review the existing `threshold-review-plan.md` against the agreed
  product/browser conditions, then promote reviewed per-scenario threshold
  values with reviewer, timestamp, and review-context provenance, and persist
  the `threshold-review.json` promotion summary next to `thresholds.json`.
  Because the current candidate allows over-budget frames, promotion must also
  pass `--allow-over-budget-thresholds` and a concrete `--review-note=TEXT`;
  the reviewed policy and promotion summary record the acknowledged scenario
  IDs.
  The summary's `outputPolicyFingerprint` must match the frame scoreboard's
  `thresholdPolicyFingerprint`; otherwise Phase 6 readiness treats the summary
  as stale.
- Regenerate the readiness bundle with the reviewed threshold policy.
- Require `web-readiness --strict` to pass.
- Require `web-default-preflight --target=make-dom-default --strict` to pass
  with `--bundle=...` before changing the package default.
- Require `web-default-preflight --target=retire-temporary-paths --strict` to
  pass with `--bundle=...` before removing the xterm-compatible fallback/demo
  path.

## Efficient Validation Cadence

Use the fast loop for review edits, docs, threshold promotion, and readiness
composition:

```sh
dart analyze <changed files>
dart test <focused VM/tool tests>
git diff --check
```

Use focused Chrome tests when code touches browser lifecycle, retained DOM
presentation, input, focus, clipboard, semantics, or benchmark capture behavior:

```sh
cd packages/fleury_web
dart test -p chrome test/run_tui_web_test.dart
dart test -p chrome test/run_tui_surface_test.dart
```

Avoid full `web_frame_suite` recapture unless one of these changed:

- runtime render behavior;
- retained DOM presentation or span planning;
- browser input/focus/clipboard behavior;
- semantic tree or semantic DOM projection;
- benchmark scenario definitions;
- final evidence refresh conditions.

For threshold review, readiness bundles, semantic audits, and default preflight
checks, reuse the existing candidate capture directory. These steps operate on
JSON artifacts and do not need another browser run.

## Re-Review Checklist

- [ ] `fleury_host.dart` is accepted as the explicit shared host SPI, with
      `TuiRuntime` narrow enough to avoid a browser abstraction leak.
- [ ] `FramePresentationPlan` is accepted as the DOM/WebGL handoff boundary.
- [ ] DOM remains the explicit v1 browser path until Phase 6 gates pass.
- [ ] Benchmark counters are sufficient to distinguish runtime-render-bound,
      dirty-row-diff-bound, span-build-bound, semantic-apply-bound,
      DOM-apply-bound, and layout-bound failures.
- [ ] Candidate thresholds are reviewed under agreed browser/product
      conditions before promotion.
- [ ] `web-readiness-bundle --verify=... --strict` passes over the candidate
      review packet.
- [ ] Manual IME evidence remains required and cannot be replaced by generated
      templates or trace fixtures.
- [ ] Default and retirement preflights are run only after strict readiness
      passes, and final release-action preflights include `--bundle=...`.
