# Fleury 0.1.0 release qualification

**Published:** October 5, 2026. **Release commit:**
[`8f5c33ca`](https://github.com/danReynolds/fleury/commit/8f5c33cad593ed210cb1f8c078e53b1088552c6f).
All four packages are public on pub.dev. The release preparation merged in
[PR #307](https://github.com/danReynolds/fleury/pull/307).

## Packages and tags

| Package | Version | Relationship to Fleury |
| --- | --- | --- |
| [fleury](https://pub.dev/packages/fleury/versions/0.1.0) | 0.1.0 | Framework, bundled widgets/themes, and CLI |
| [fleury_test](https://pub.dev/packages/fleury_test/versions/0.1.0) | 0.1.0 | Development-only testing helpers; `fleury: ^0.1.0` |
| [fleury_mcp](https://pub.dev/packages/fleury_mcp/versions/0.1.0) | 0.1.0 | Optional agent executable; exact `fleury: 0.1.0` |
| [fleury_web](https://pub.dev/packages/fleury_web/versions/0.1.0) | 0.1.0 | Optional browser host; exact `fleury: 0.1.0` |

The annotated `fleury-v0.1.0` and `fleury_web-v0.1.0` tags both resolve to the
release commit. MCP and testing have no tag target in `release.toml`.

MCP and web use Fleury's lockstep wire. Their exact requirements are intentional;
the two corresponding `RK-PUB-012` dependency-range warnings were explicitly
accepted during publication. Ordinary apps need only `fleury`, plus
`fleury_test` for tests.

## Publication and consumer evidence

RK 0.1.13 at `45b39e8a`, including release-kit
[PR #95](https://github.com/danReynolds/release-kit/pull/95), staged and published
the stack in dependency order using Dart 3.12.2. The release completed without
problems or unfinished targets. Final public status also passed.

- All four downloaded public archives match their staged SHA-256 hashes.
  Archived pubspecs, READMEs, changelogs, and library sources match the release
  checkout. Local overrides, lockfiles, caches, and Git metadata are excluded.
- A new temporary `PUB_CACHE` outside the repository activated the hosted
  `fleury 0.1.0` CLI and generated an app without Git or path overrides.
  Analysis, generated tests, and native AOT compilation passed.
- The hosted native app rendered, incremented through keyboard input, and exited
  cleanly inside an isolated tmux PTY. Terminal modes, cursor visibility, and
  mouse modes restored correctly.
- Adding hosted `fleury_mcp 0.1.0` to that app passed the real stdio MCP handshake,
  UI inspection, semantic button activation, and observation of the updated count.
- A separate minimal app resolved hosted `fleury` and `fleury_web 0.1.0`, passed
  analysis, and compiled to JavaScript. Chromium verified the first frame, mouse
  and keyboard input, semantic activation, and updated rendering without page
  errors.

The first-publication notices are removed from the installation, tutorial, and
testing guides after the successful public-install checks. The Git installation
path remains available for unreleased changes.

## Runtime and deployment qualification

The release commit changes only changelogs and package READMEs from `b7c4e9c`.
Runtime files are identical to the qualified and deployed build.

- [Runtime baseline CI](https://github.com/danReynolds/fleury/actions/runs/37362146668)
  passed all eight jobs: framework analysis/tests, browser/integration checks,
  hot reload, repaint-cache checks, performance/scenario gates, native Linux/macOS
  PTY checks, and fresh-project smoke tests.
- [Release-commit CI](https://github.com/danReynolds/fleury/actions/runs/37377800014)
  records the automatic rerun for the documentation-only release commit.
- [Release docs deployment](https://github.com/danReynolds/fleury/actions/runs/37377800098)
  passed its site build, deployment, and live Pad compiler check.
- The deployed Pad compiler is revision `fleury-pad-staging-00021-hoy`, build
  `292860c2d73490b5`, from `b7c4e9c`. Its image passed 11 API tests, all 129 guide
  projects, shutdown/checkpoint recovery, stalled-worker recovery, and startup
  fault injection before promotion. A published-site compile and state-preserving
  reload passed; the progress bar completed after the preview acknowledged it.
- Tag-triggered Pad image verification is tracked for
  [fleury-v0.1.0](https://github.com/danReynolds/fleury/actions/runs/37378473113) and
  [fleury_web-v0.1.0](https://github.com/danReynolds/fleury/actions/runs/37378614740).
  Automated Cloud Run deployment is disabled; the runtime-equivalent image was
  already deployed and verified directly.

## Supported scope and remaining qualification

Native launch support targets modern UTF-8, xterm-compatible POSIX terminals.
Windows remains a preview; scaffold CI does not establish native Windows terminal
support. The extended physical-terminal matrix remains incomplete. October 5
native PTY/tmux and fish dogfooding passed after the slow-start reload fix;
physical Terminal.app clipboard, mouse, and rendering acceptance is not inferred
from those automated checks.

Browser embedding is covered by compile/browser tests. `fleury serve` is a
development preview, not a hardened public hosting layer. Native MCP attachment
is local development tooling, not production shared-session authorization.
Native Sixel remains experimental.

The [September core sweep](../audits/2026-09-23-core-sweep.md#october-4-reconciliation)
records remaining performance/input-report limitations. The
[docs launch audit](../audits/2026-09-30-docs-launch-readiness.md) records resolved
findings. Earlier readiness reports are historical evidence, not substitutes for
these release and public-consumer checks.
