# Workstream: Adoption, Distribution, And Ecosystem

## Purpose

Make Fleury easy to discover, evaluate, install, compare, and adopt once the
core product is credible.

## Current State

- Fleury has internal strategy docs, implementation trackers, and RFCs.
- A first source-linked peer scorecard skeleton exists for Nocterm,
  Bubble Tea v2, Textual, OpenTUI, Ratatui, and Ink.
- It does not yet have public positioning, distribution, a docs site,
  showcase, contributor process, or evidence-backed public comparison.
- The example subpackage is the current-cycle demo app.
- A repo-local launcher now gives developers stable local commands for
  bootstrapping, demo-app runs, examples, CLI passthrough, quick checks, local
  path activation, and standalone CLI compilation.
- An internal [Why Fleury?](../why-fleury.md) positioning draft now names the
  launch wedge, concrete peer-facing wins, claims that are ready, and claims
  still blocked on peer or terminal evidence.
- Dune/`dune_cli` is the later flagship app commitment after core confidence
  is higher.
- Peer benchmark expansion is frozen for the MVP after the SB.5 variance
  checkpoint. Maintain existing evidence only when it protects a core/API
  decision; public comparison pages and additional peer fixtures wait until
  post-MVP API stability.
- M2.12 is dispositioned for the MVP cycle: internal positioning, local
  distribution planning, and peer-scorecard scaffolding are enough for now.
  Public docs, public comparison copy, docs site, scaffolding, adoption
  metrics, and release collateral are deferred until API freeze.

## Target Capabilities

- Clear "Why Fleury?" positioning against Nocterm, Bubble Tea v2, Textual,
  OpenTUI, Ratatui, and Ink.
- Peer scorecards updated at regular checkpoints.
- Time-to-first-app path for a new developer.
- Distribution plan for pub.dev, standalone binaries, Homebrew, and npm
  wrapper once the APIs are ready.
- Showcase led first by the example subpackage, then Dune/`dune_cli`, then
  third-party apps.
- Contributor and RFC process that does not burden early implementation.

## Milestone Checklist

- [x] ADE.1 Write "Why Fleury?" positioning.
  - Intent: Explain why developers should choose Fleury.
  - Acceptance: Page names three concrete wins against Nocterm, three against
    Bubble Tea v2, and the role of the example demo app and later
    Dune/`dune_cli` flagship.
  - Evidence: [Why Fleury?](../why-fleury.md).
  - Notes: Lead with developer-visible wins, not internal cell architecture.
    Keep this internal until peer runs and real-terminal evidence are stronger.

- [x] ADE.2 Define distribution plan.
  - Intent: Make future adoption concrete without doing release work too early.
  - Acceptance: Plan covers pub.dev packages, standalone binaries,
    Homebrew, npm wrapper, `create-fleury-app`, docs site, example app run
    path, and later Dune/`dune_cli` install path.
  - Evidence:
    [local distribution path](../local-distribution-path.md),
    [workspace README](../../../README.md),
    [repo-local launcher](../../../tool/fleury_dev.dart),
    [demo app README](../../../packages/fleury_example_console/README.md).
  - Notes: Public release work stays deferred, but the local path and future
    distribution tracks are now explicit.

- [x] ADE.3 Create first peer scorecard skeleton.
  - Intent: Track the moving target rather than comparing against stale peers.
  - Acceptance: Scorecards include current Nocterm, Bubble Tea v2, Textual,
    OpenTUI, Ratatui, and Ink where relevant.
  - Evidence: [Peer scorecards](../peer-scorecards.md).
  - Notes: Ongoing maintenance still happens at phase boundaries or when a
    peer ships a major release.

- [ ] ADE.4 Define adoption metrics.
  - Intent: Know whether Fleury is being chosen.
  - Acceptance: Phase scorecards include downloads, third-party apps,
    benchmark targets, time-to-first-app, flagship-app usage, and contributor
    signals.
  - Evidence: Pending post-MVP.
  - Notes: Deferred until API freeze. Treat early numbers as targets to
    calibrate, not vanity metrics.

## Implementation Notes

- Adoption work should not replace product superiority, but it must become
  first-class before public launch.
- The first scorecard is a source snapshot and comparison skeleton, not a
  launch verdict. Move claims into public positioning only after tests,
  scenario benchmarks, or demo-app evidence exists.
- Do not restart peer-comparison work as adoption work during MVP. The current
  cycle should spend evidence time on core API stability, local scenario
  benchmarks, demo-app pressure, and terminal correctness.
- The example subpackage is the first marketing/demo surface because it
  shows Fleury capabilities under controlled app pressure. Dune/`dune_cli`
  becomes the stronger product evidence later.
- Distribution can be planned early and executed when the APIs are stable
  enough not to embarrass the framework.
- Public adoption work should restart after API freeze or when an external
  launch date needs concrete collateral, not as a prerequisite for the current
  MVP completion call.
- The local launcher intentionally avoids a root workspace dependency for now.
  It reduces command-memory overhead while package boundaries are still moving.

## Risks And Open Questions

- Public launch too early could freeze weak APIs.
- Public launch too late could let Nocterm or another peer occupy the Dart
  TUI narrative.
- Adoption targets need adjustment once real usage begins.

## Acceptance Evidence

- [Why Fleury?](../why-fleury.md).
- [Local distribution path](../local-distribution-path.md).
- [Peer scorecards](../peer-scorecards.md).
- Pending post-MVP adoption scorecard.
