# Fleury Web Readiness Audit

Generated at `2026-06-09T13:35:36.343928Z`.

Strict pass: `false`.

| Check | Status | Artifact | Blockers |
| --- | --- | --- | --- |
| Frame performance scoreboard | FAIL | `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/scoreboard.json` | frame scoreboard threshold policy reviewState is candidate; expected reviewed |
| Semantic coverage audit | pass | `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/semantic-coverage.json` | - |
| Manual IME and screen-reader validation | FAIL | `/Users/dan/Coding/fleury-web-phase1/profiling/web/baselines/2026-06-08-local-dom-retained-phase1-refresh/readiness-candidate/manual-validation-audit.json` | manual validation audit strictPass is not true<br>manual validation passed 0 of 2 targets<br>needsReviewTargets: chrome-ime-macos, chrome-voiceover-macos<br>manual evidence provenance blockers: chrome-ime-macos: reviewedBy, capturedAt, environment.browserVersion; chrome-voiceover-macos: reviewedBy, capturedAt, environment.browserVersion<br>failing manual targets: chrome-ime-macos, chrome-voiceover-macos |

## Manual Target Diagnostics

| Target | Status | Checks | Missing Checks |
| --- | --- | --- | --- |
| chrome-ime-macos | needsReview | 0/6 | manual-page-loads-dom-host<br>keyboard-capture-focused<br>composition-start-update-visible<br>composition-end-commits-once<br>candidate-window-near-caret<br>typing-continues-after-composition |
| chrome-voiceover-macos | needsReview | 0/7 | manual-page-ready-semantic-host<br>visual-grid-hidden<br>semantic-root-exposed<br>focused-textbox-announced<br>semantic-action-works<br>keyboard-capture-restored<br>safe-link-announced |
