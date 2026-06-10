# Fleury Web Default Preflight

Generated at `2026-06-09T13:35:38.809262Z`.

Target: `retire-temporary-paths`.

Allow temporary web transport paths to be retired after retained DOM readiness.

Readiness artifact: `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/web-readiness.json`.

Readiness bundle required: `false`.

Bundle bound: `false`.

Automated validation required: `false`.

Automated validation bound: `true`.

Strict pass: `false`.

| Check | Status | Blockers |
| --- | --- | --- |
| Phase 6 readiness | FAIL | Frame performance scoreboard: frame scoreboard threshold policy reviewState is candidate; expected reviewed<br>Manual IME and screen-reader validation: manual validation audit strictPass is not true; manual validation passed 0 of 2 targets; needsReviewTargets: chrome-ime-macos, chrome-voiceover-macos; manual evidence provenance blockers: chrome-ime-macos: reviewedBy, capturedAt, environment.browserVersion; chrome-voiceover-macos: reviewedBy, capturedAt, environment.browserVersion; failing manual targets: chrome-ime-macos, chrome-voiceover-macos |
| Automated retained host validation | pass | - |

## Manual Target Diagnostics

| Target | Status | Checks | Missing Checks |
| --- | --- | --- | --- |
| chrome-ime-macos | needsReview | 0/6 | manual-page-loads-dom-host<br>keyboard-capture-focused<br>composition-start-update-visible<br>composition-end-commits-once<br>candidate-window-near-caret<br>typing-continues-after-composition |
| chrome-voiceover-macos | needsReview | 0/7 | manual-page-ready-semantic-host<br>visual-grid-hidden<br>semantic-root-exposed<br>focused-textbox-announced<br>semantic-action-works<br>keyboard-capture-restored<br>safe-link-announced |
