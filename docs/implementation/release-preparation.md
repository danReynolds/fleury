# Fleury 0.1 release preparation

**Reviewed:** October 4, 2026. **Qualification baseline:** `882c6642`.
**Disposition:** ready for a scoped public 0.1 launch after the final terminal
walkthrough and publication checks below. No packages or release tags were
published during this assessment.

## Scope and package boundaries

The terminal launch target is modern UTF-8, xterm-compatible POSIX terminals.
Windows remains a preview; the extended real-terminal matrix remains incomplete.
The browser embedding package is supported by compile/browser tests. `fleury
serve` is a development preview, not a hardened public hosting layer. Native
Sixel remains experimental.

| Package | Version | Relationship to Fleury |
| --- | --- | --- |
| `fleury` | 0.1.0 | Framework, bundled widgets/themes, and CLI |
| `fleury_test` | 0.1.0 | Development-only testing helpers; `fleury: ^0.1.0` |
| `fleury_mcp` | 0.1.0 | Optional agent executable; exact `fleury: 0.1.0` |
| `fleury_web` | 0.1.0 | Optional browser host; exact `fleury: 0.1.0` |

MCP and web use Fleury's lockstep wire. Their exact requirements are intentional;
do not widen them just to suppress Pub's dependency-range warning. Ordinary apps
need only `fleury`, plus `fleury_test` for tests.

## Evidence at the qualification baseline

- [Main CI](https://github.com/danReynolds/fleury/actions/runs/37092867896)
  passed analysis, package/integration tests, hot reload, repaint-cache checks,
  performance/scenario gates, native Linux/macOS PTY checks, and fresh-project
  smoke tests. Windows scaffold tests do not establish native terminal support.
- [Docs CI](https://github.com/danReynolds/fleury/actions/runs/37092867884)
  checked the live Pad compiler before successfully deploying the site.
- RK [#95](https://github.com/danReynolds/release-kit/pull/95), merged as
  `16dbfc7`, staged all four packages together using Dart 3.13.5. A second
  `rk stage --json` run restored the same four stages. Both exited zero with
  no problems and only the two expected `RK-PUB-012` exact-pin warnings.
- Each staged package archive retained its original pubspec and excluded
  `pubspec_overrides.yaml`, `pubspec.lock`, and `.dart_tool` files. This proves
  local package preparation, not public registry authentication or installation.
- 301 focused tests passed locally on Dart 3.12.2: overlay ownership, lazy-list
  state and semantic identity, text layout, input parsing, DataTable height,
  LogRegion, Sparkline, mutable-data refresh, and focus/scroll rebuild behavior.
- `dart tool/fleury_dev.dart mvp-readiness --strict --json` passed, but it reads
  the two June 2 Terminal.app/tmux captures. Both are `readyForReview`, not a
  fresh acceptance of this candidate. All four Windows targets remain deferred.

The [September core sweep](../audits/2026-09-23-core-sweep.md#october-4-reconciliation)
records the landed fixes and remaining performance/input-report limitations.
The [docs launch audit](../audits/2026-09-30-docs-launch-readiness.md) records
its resolved findings. Earlier milestone reports retain historical evidence;
they do not supersede qualification of the final release commit.

## Preparation changes

The release instructions now lead with pub.dev installation, with a shared Git
fallback while publication is pending. MCP setup uses the app's development
dependency so pub resolves the matching framework. Stale audit statuses and
release-config tag comments have been reconciled without widening support claims.

Local validation of this preparation change passed 153 Dart documentation tests,
28 JavaScript tests, the production site build (163 pages), 925 internal links
and anchors across the edited site pages, and 26 audit regression tests covering
DataTable height, collection metrics, and mutable-data refresh. Formatting,
`git diff --check`, and all 19 local audit/release-document links also passed.
This supplements the baseline evidence; repeat staging after committing the
package README changes.

## Before publication

- [ ] Merge the release-preparation changes and verify CI for the final commit.
  The evidence above is tied to the baseline, not automatically to later edits.
- [ ] Refresh the walkthrough in Terminal.app and inside tmux at that commit:
  create/run an app, edit and hot reload while preserving state, resize narrow
  and wide, type/paste, navigate by keyboard and mouse, suspend/resume, and quit.
  Check that the shell restores correctly and receives no stray mouse reports.
  Record the commit, SDK, terminal, results, and remaining fallbacks. Capture
  capabilities with `dart tool/fleury_dev.dart terminal-matrix
  --label=macos-terminal-release-0.1.0` and the corresponding
  `--label=tmux-terminal-release-0.1.0` from inside tmux. Review captures using
  the [terminal review packet](terminal-matrix-review-packet.md); the diagnostic
  alone does not replace the interaction walkthrough.
- [ ] Run `rk stage --json` from a clean checkout of the final commit using RK
  with #95 or later. Confirm four complete stages and only the two intended
  exact-pin warnings. README/config changes require new stage identities.
- [ ] Review `rk plan` and publish with `rk release` in a terminal. Omit the unit
  to process the whole stack in dependency order. Review the exact-pin warnings
  explicitly. Staging uses local dependencies; publication still waits for
  dependencies to become publicly available.
- [ ] Verify all four 0.1.0 packages on pub.dev and the `fleury-v0.1.0` and
  `fleury_web-v0.1.0` tags. MCP and testing have no tag target in `release.toml`.
  Verify the tag-triggered Pad workflow and its live compiler check complete.

## Immediately after publication

- [ ] From a fresh temporary `PUB_CACHE`, run `dart pub global activate fleury`,
  invoke the installed `fleury create` in a directory outside the checkout,
  and run `dart analyze`, `dart test`, and `dart compile exe bin/run_app.dart`.
  Use no Git/path dependency overrides. Launch the result in a real terminal.
- [ ] In that hosted app, add `fleury_mcp` as a dev dependency and exercise a
  read/action cycle through `dart run fleury_mcp -- dart run bin/run_app.dart`.
  Check a minimal `fleury_web` embed resolves and compiles with hosted packages.
- [ ] Remove the temporary “Before the first publication” notice from Getting
  started and the corresponding tutorial sentence. Keep the Git installation
  section for unreleased changes. Verify the deployed getting-started journey
  and live Pad against the published release.

Keep these items open until their actual results are recorded. Neither a
successful stage nor the historical MVP gate establishes public-install or
current real-terminal acceptance.
