# MVP Completion Audit

**Status:** MVP implementation goal complete
**Date:** 2026-06-02
**Purpose:** Keep the current MVP state explicit before calling the broader
implementation goal complete.

## Summary

The local MVP implementation is complete for the scoped MVP cycle across the core
reactive framework, production widget toolkit, semantic/testing surfaces,
targeted debug capture, process/task workflows, extension seam, and proof-app
pressure harness.

The final MVP gate passed after the terminal evidence scope was narrowed to
Apple Terminal and tmux. iTerm2, Kitty, Ghostty, Alacritty, WezTerm, SSH,
M2.9 real Windows validation, Dune/`dune_cli`, `fleury_acp`, public
adoption/release collateral, full replay/devtools, and expanded public peer
comparisons are explicitly deferred from this MVP cycle.

## Locally Proven

- Phase 0 architecture guardrails and scenario lab are complete.
- Phase 1 clear-choice foundations are complete: semantic tree, text editing,
  `FleuryApp`, task/effect model, terminal diagnose/capability model,
  scenario benchmarks, DataTable, debug inspector, sanitized output, local
  distribution path, and proof app v0.
- Phase 2 production toolkit is locally strong: forms, logs, files, trees,
  search, JSON, diffs, code, Markdown, process panels, workflow widgets,
  component theme, accessibility/fallback, and targeted debug capture are
  implemented and exercised by tests/proof scenarios.
- Core/API stabilization is locally complete for the current audit pass:
  controller/runtime disposal rules now preserve final readable state while
  rejecting stale post-dispose mutation across app kernel, text, task/effects,
  output buffers, animations, selection/overlay, focus, scheduler/binding,
  input dispatch, debug capture, and fake terminal driver surfaces.
- M3.5 remote app/session, M3.6 semantic inspection protocol stability, M3.7
  render-engine/private boundary, and M3.8 static extension seam are complete
  for the MVP cycle.
- M3.9 has enough local governance and peer-fixture evidence for the MVP
  stopping point. Further peer parity, public comparison claims,
  real-terminal variance, and cross-machine runs are post-MVP.
- M2.12 is dispositioned for the MVP cycle: internal positioning, local
  distribution planning, and peer-scorecard skeletons exist; public docs,
  public comparison copy, launch collateral, docs site, and adoption metrics
  wait until API freeze.

## Latest Evidence

- `dart tool/fleury_dev.dart mvp-final-gate --write-report=docs/implementation/mvp-readiness-report.md`
  passed at the repo root on 2026-06-02. It ran the local RC gate and enforced
  the external MVP evidence gate.
- `dart tool/fleury_dev.dart check` passed at the repo root across
  `fleury`, `fleury_widgets`, `fleury_git`, and `fleury_example_console`.
  The gate includes package analysis, the local `fleury` non-integration
  suite, the integration-tagged `fleury` serve/shell fixtures run serially,
  the full local `fleury_widgets` test suite with 798 tests, the `fleury_git`
  tests, and the `fleury_example_console` proof-app scenario suite with 26
  tests.
- The RC validation pass found and corrected two local test-artifact issues:
  the command-palette golden now reflects the visible `Search…` placeholder,
  and the stale-handle integration test now uses a realistic full-gate timeout
  with explicit child-process cleanup on timeout.
- The final gate surfaced a process-heavy test scheduling issue: remote
  serve/shell integration fixtures and process-task fixtures can timeout under
  default full-suite parallel load. The RC gate now runs `fleury`
  non-integration tests first and then runs `integration`-tagged tests with
  `--concurrency=1`, preserving coverage while removing the false timeout
  mode.
- `dart test test/debug/debug_capture_test.dart test/terminal/fake_driver_test.dart test/runtime/run_tui_test.dart test/terminal/diagnostics_test.dart test/effects/process_task_test.dart test/effects/external_editor_test.dart test/widgets/selection/selection_demo_e2e_test.dart`
  passed in `packages/fleury` with 61 tests.
- `dart tool/fleury_dev.dart check --quick` passed at the repo root across
  `fleury`, `fleury_widgets`, `fleury_git`, and `fleury_example_console`.
- `dart tool/fleury_dev.dart mvp-readiness --write-report=docs/implementation/mvp-readiness-report.md`
  passed and generated the current combined external evidence report. It
  correctly reports `strictPass: true`, 2/2 MVP launch terminal targets ready,
  and 0/4 post-MVP Windows validation targets ready.
- `dart tool/fleury_dev.dart --dry-run mvp-final-gate --quick --write-report=docs/implementation/mvp-readiness-report.md`
  passed and showed the final gate sequence: local RC gate, external evidence
  scan, report write, and external evidence enforcement.
- `git diff --check` passed.
- Touched-file trailing-whitespace scan found no matches.
- Stale-name scan outside execution-journal validation prose found no matches
  for old framework or extraction names.

## Current Goal Result

- The scoped MVP implementation goal is complete.
- The final gate passed without `--skip-local`.
- The generated
  [mvp-readiness report](mvp-readiness-report.md) records `strictPass: true`,
  no remaining blockers, 2/2 MVP launch terminal targets ready, and Windows
  validation deferred out of MVP.
- The generated
  [terminal matrix collection plan](terminal-matrix-collection-plan.md) and
  [terminal matrix review packet](terminal-matrix-review-packet.md) record the
  current 2/2 ready-target state, exact capture commands, and review checklist.
  The non-generated
  [terminal matrix external handoff](terminal-matrix-external-handoff.md)
  records the post-MVP extended terminal matrix targets.

## Explicitly Deferred

- Dune/`dune_cli` flagship integration.
- `fleury_acp` package, ACP transport, ACP schemas, ACP-specific widgets, and
  ACP replay fixtures.
- Extended terminal matrix coverage for iTerm2, Kitty, Ghostty, Alacritty,
  WezTerm, and SSH.
- Real Windows validation on Windows Terminal, conhost, PowerShell, and IDE
  terminals. The generated [Windows validation plan](windows-validation-plan.md)
  and [Windows validation review packet](windows-validation-review-packet.md)
  remain the post-MVP capture/review path.
- Public adoption/release collateral: public package docs, public comparison
  copy, docs site, scaffolding, adoption metrics, and release collateral.
- Full replay/shareable replay artifacts and browser/devtools protocol.
- Expanded peer benchmarks, cross-machine variance, real-terminal peer runs,
  and public superiority comparison copy.
- Broad public distribution polish beyond the local launcher path.

## Audit Result

The overall implementation goal can be marked complete for the scoped MVP
cycle. Extended terminal validation, Windows validation, Dune/`dune_cli`,
`fleury_acp`, public adoption collateral, full replay/devtools, and expanded
peer benchmark/comparison work are intentionally deferred.
