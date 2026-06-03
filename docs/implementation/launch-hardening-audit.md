# Launch Plan Hardening Audit

**Status:** Planning audit  
**Date:** 2026-05-31  
**Purpose:** Record the five-pass validation performed before implementation
begins, and capture the decisions that make the launch plan tighter.

## Pass 1: Launch Scope And Deferrals

**Validated assumption:** Fleury launch should prove a robust reactive TUI
framework, not every long-term research bet.

**Refinement:**

- Keep semantic graph, app kernel, text editing, terminal
  capability/security, DataTable, diagnostics, benchmarks, and the example
  subpackage proof-app slice in launch scope.
- Defer full replay, broad accessibility, Windows depth, public launch polish,
  plugin ecosystem, and `fleury_acp` implementation.
- Keep only debug/replay hook points in launch scope so future replay is not
  blocked by missing instrumentation.

## Pass 2: Peer And Market Assumptions

**Validated assumption:** The market is moving quickly enough that Fleury must
benchmark current peers, not stale versions.

**Research signals:**

- Bubble Tea v2 raised the bar with the Cursed Renderer, synchronized
  rendering, richer keyboard support, inline images, and OSC52 clipboard over
  SSH.
- Nocterm is the direct Dart peer with Flutter-like components, hot reload,
  testing, and an early ecosystem.
- OpenTUI is the native-core frontier, with a Zig core and TypeScript bindings.
- Dart distribution is viable through standalone executables and packaging
  tools, but should be made visible before public launch.

**Refinement:**

- Maintain peer scorecards for Nocterm, Bubble Tea v2, Textual, OpenTUI,
  Ratatui, and Ink.
- Treat performance as scenario-relative: raw render throughput may not be
  Fleury's first win, while retained ergonomics, semantic tests, diagnostics,
  selection, and example-app proof can be.

## Pass 3: Architecture And Package Boundaries

**Validated assumption:** The existing package layout supports the intended
split.

**Repo facts:**

- `packages/fleury` owns the core runtime.
- `packages/fleury_widgets` owns higher-level general widgets.
- `packages/fleury_web` already exists as a browser/xterm driver surface.
- A future sibling package such as `packages/fleury_acp` can be added without
  coupling ACP to core.

**Refinement:**

- Fleury core must stay protocol-neutral.
- ACP transport, schemas, protocol models, ACP-specific widgets, and ACP
  replay fixtures belong in `fleury_acp`, not launch scope.
- General widgets stay in core or `fleury_widgets` only when useful outside a
  single protocol.

## Pass 4: Proof App Then Dune/`dune_cli`

**Validated assumption:** Dune was already intended as a real consumer in
earlier RFCs, but this implementation cycle should prove the framework first
through an example subpackage before moving to Dune/`dune_cli`.

**Refinement:**

- The Phase 1 proof-app slice should be narrow and product-shaped:
  sidebar/navigation, streamed content, composer/input, commands, status,
  output/log regions, selection, one dense data surface, capability fallbacks,
  diagnostics, and debug capture hooks.
- Tool calls, approvals, ACP, and full replay are useful future pressure
  tests, but should not block the example-proof cycle.
- Dune/`dune_cli` should follow once the example subpackage proves the core
  widgets and framework pieces are working well through tests.

## Pass 5: Milestones, Cuts, And Acceptance

**Validated assumption:** The roadmap needs hard cut rules to stay shippable.

**Refinement:**

- Phase 0 starts with the example proof-app scenario, then remains capped at
  three architecture RFCs: semantic graph, app kernel, and capability/security.
- Phase 1 requires adapter-readiness, not ACP implementation.
- Phase 2 can add targeted debug-capture/replay prototypes only if example or
  Dune/`dune_cli` bugs require them.
- Full replay, shareable replay artifacts, broad public launch polish,
  plugins, and `fleury_acp` are explicitly deferred until after launch
  foundations are stable.

## Sources Used

- Bubble Tea v2 announcement: <https://charm.land/blog/v2/>
- Nocterm package page: <https://pub.dev/packages/nocterm>
- OpenTUI home: <https://opentui.com/>
- Dart compile docs: <https://dart.dev/tools/dart-compile>
- cli_pkg package page: <https://pub.dev/packages/cli_pkg>
- Textual testing guide: <https://textual.textualize.io/guide/testing/>
- Ratatui widgets recipe: <https://ratatui.rs/recipes/widgets/>
- Ink README: <https://github.com/vadimdemedes/ink>
