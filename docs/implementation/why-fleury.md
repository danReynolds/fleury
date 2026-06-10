# Why Fleury

**Status:** Internal positioning draft
**Milestone:** M2.12 MVP adoption positioning and public-scope disposition
**Last source refresh:** 2026-06-01

## Purpose

Define the adoption argument Fleury should be able to make when the framework is
ready to launch. This is not public copy yet. It is the evidence-backed internal
positioning target that product, docs, benchmarks, and the demo app should make
true.

## Short Answer

Fleury is for Dart developers who want to build serious terminal applications
with a Flutter-style retained UI model, but who also need production TUI
foundations that go beyond component rendering:

- app-scale screens, commands, status, and package extensions;
- semantic testing and inspectable app state;
- strong text input, forms, completion, selection, copy, and redaction;
- data-heavy widgets for tables, logs, trees, documents, diffs, code, and
  workflow surfaces;
- task/process orchestration with progress, cancellation, output safety, and
  terminal handoff;
- terminal capability diagnostics and compatibility evidence;
- scenario benchmarks that measure app-shaped behavior instead of only
  microbenchmarks.

The launch pitch should be:

> Flutter-style Dart ergonomics for building production terminal apps, with
> first-class semantics, commands, tasks, data widgets, safety, diagnostics, and
> benchmark evidence.

## Who Should Choose Fleury

Fleury should be the clear choice when the app is:

- a developer tool, agent workflow, operations console, test runner, deployment
  tool, code review surface, local database console, log explorer, or data-heavy
  terminal app;
- large enough to need screens, global and screen-local commands, status,
  semantic tests, async tasks, and safe subprocess output;
- written by a team that wants Dart's static typing, async model, pub packages,
  and `dart compile exe` distribution path;
- expected to survive real terminals, narrow windows, untrusted output, and
  regression tests.

Fleury is not trying to beat every peer on every axis at launch. It should beat
the field for a specific modern category: retained, reactive, testable,
data-heavy terminal applications with strong app semantics.

## Three Concrete Wins Against Nocterm

Nocterm is the closest Dart peer. Its current package page describes a
Flutter-like Dart TUI framework with stateful components, `setState`, layout
widgets, hot reload, widget-style tests, ecosystem packages, and apps built with
it. That means Fleury cannot win by saying "Flutter-like in Dart"; Nocterm
already says that.

Fleury's launch wins against Nocterm should be:

1. **App kernel, not just widgets.** Fleury has `FleuryApp`, app-owned section
   patterns, scoped commands, status items, command palette integration, key
   hints, semantic command nodes, and typed app extensions. The pitch is
   production app structure: commands can drive shortcuts, palette rows, status
   actions, semantic actions, and tests through the same registry while tabs,
   sidebars, and sections remain ordinary app/widget state.
2. **Semantic app graph as a developer-visible testing and automation surface.**
   Fleury exposes roles, labels, values, actions, focus, selection, capability
   state, redaction state, diagnostics, and inspectable snapshots. Tests and
   future adapters can query meaning instead of scraping terminal cells.
3. **Production toolkit plus benchmark evidence.** Fleury now has measured
   scenarios for text editing, 100k-row tables, log tailing, streaming markdown,
   dashboard updates, resize storms, overlays, subprocess/output safety,
   TreeTable, demo-app journeys, and layout dirtiness. The claim is not "more
   widgets"; it is data/workflow widgets with semantics, copy/export, safety,
   and app-shaped baselines.

Claims still needing peer evidence:

- Equivalent Nocterm scenario runs for counter, text input, table/list, resize,
  and streaming output.
- Side-by-side code ergonomics for a multi-screen app with command palette,
  tasks, diagnostics, and semantic tests.

## Three Concrete Wins Against Bubble Tea v2

Bubble Tea is mature, tasteful, and ecosystem-backed. Fleury should respect it as
the Go/Charm benchmark rather than positioning against it as a low-level
renderer.

Fleury's launch wins against Bubble Tea v2 should be:

1. **Retained UI without a central update loop.** Dense apps can be expressed as
   persistent widgets, controllers, screens, commands, and stateful components
   instead of manually threading model/update/view message plumbing through every
   feature.
2. **Typed semantic tests over terminal meaning.** Bubble Tea apps can test model
   behavior and output, but Fleury's semantic graph gives tests a stable way to
   invoke commands, select nodes by role/action/state, and inspect app meaning
   across widgets, dialogs, process panels, data tables, and diagnostics.
3. **Integrated app toolkit for developer workflows.** Fleury's first-party
   widgets and controllers cover forms, completion input, data tables, tree
   tables, logs, markdown, JSON, diffs, code, process panels, approval prompts,
   task graphs, trace timelines, file pickers, and workflow snapshots with
   common semantics/copy/safety conventions.

Claims still needing peer evidence:

- Equivalent Bubble Tea/Bubbles code for the demo-app workload.
- Terminal taste and raw renderer comparisons against Bubble Tea v2's current
  renderer stack.

## Three Concrete Wins Against The Broader Field

### Against Textual

Textual is the mature full-app framework reference. Fleury should not claim
greater breadth at launch. Fleury's wedge is Dart, static typing, Flutter-style
retained ergonomics, semantic tests, and package-shaped integrations for teams
already in Dart or wanting standalone Dart binaries.

### Against OpenTUI

OpenTUI is strong on native rendering, terminal features, JavaScript/TypeScript
bindings, screen modes, custom streams, renderer events, and terminal protocol
surface. Fleury should not claim raw renderer superiority without peer runs.
Fleury's wedge is app semantics, typed Dart APIs, commands/tasks/status as an app
kernel, and a protocol-neutral widget toolkit.

### Against Ratatui

Ratatui is the Rust performance and explicit-rendering standard. Fleury's wedge
is a retained reactive framework instead of a low-level immediate UI library:
less app architecture to invent, more built-in semantics/testing, and more
first-party workflow/data widgets.

### Against Ink

Ink wins React familiarity and npm distribution. Fleury's wedge is terminal-first
full-screen app correctness: focus, commands, data widgets, terminal diagnostics,
safe output, and semantic tests designed for dense developer tools rather than
React CLI composition alone.

## Demo App And Dune Roles

The example subpackage demo app is the current-cycle evidence vehicle. It
should remain internal/product-shaped rather than polished marketing:

- prove `FleuryApp` screens, commands, status, command palette, key hints, and
  app extensions;
- prove text input, completion, history, forms, selection, copy, redaction, and
  semantic actions;
- prove DataTable, TreeTable, LogRegion, MarkdownView, JsonView, DiffView,
  CodeView, ProcessPanel, diagnostics, debug capture, workflow widgets, and
  scenario benchmarks;
- keep Dune/`dune_cli` out of this cycle until the core toolkit is reliable.

Dune/`dune_cli` should become the flagship after the demo app has stabilized the
framework. The launch story can say Fleury is being built toward a real product,
but the current evidence should come from the demo app, tests, and benchmarks.

## Launch-Ready Claims

These are acceptable internal launch claims once current validation remains
green:

- Fleury provides Flutter-style retained UI in Dart for terminal apps.
- Fleury includes app-kernel primitives: screens, commands, status, command
  palette integration, key hints, typed extensions, and tester invocation.
- Fleury exposes semantic roles, state, and actions for testing, inspection, and
  future adapters.
- Fleury has first-party text editing, data, document, log, process, workflow,
  diagnostics, and debug-capture surfaces.
- Fleury measures app-shaped workloads through scenario benchmarks.
- Fleury is protocol-neutral at launch; ACP belongs in a fast-follow
  `fleury_acp` package.

## Claims Not Yet Ready

Do not claim these externally until evidence exists:

- "Best TUI framework overall." Use this as an internal ambition, not launch
  copy.
- Faster than Nocterm, Textual, OpenTUI, Ratatui, Bubble Tea, or Ink on raw
  rendering. Current evidence is internal Fleury baselines, not peer runs.
- Strong real-terminal compatibility across the launch matrix. M2.10 still needs
  reviewed real-terminal entries.
- Mature public ecosystem. Package docs, scaffolding, release process, third-party
  apps, and `fleury_acp` remain future work.
- Dune/`dune_cli` as demo. It is the later flagship, not this cycle's evidence.

## Evidence Links

- [Peer scorecards](peer-scorecards.md)
- [Scenario benchmark lab](scenario-benchmark-lab.md)
- [Demo-app scenario](demo-app-scenario.md)
- [Terminal compatibility matrix](terminal-compatibility-matrix.md)
- [Local distribution path](local-distribution-path.md)
- [Launch hardening audit](launch-hardening-audit.md)
- [Adoption/distribution workstream](workstreams/adoption-distribution-ecosystem.md)

## Source Snapshot

Registry/source refresh on 2026-06-01:

- Nocterm `0.6.0`: <https://pub.dev/packages/nocterm>
- Bubble Tea `v2.0.7`: <https://github.com/charmbracelet/bubbletea>
- Textual `8.2.7`: <https://textual.textualize.io/>
- OpenTUI `0.3.1`: <https://opentui.com/docs/core-concepts/renderer/>
- Ratatui `0.30.0`: <https://ratatui.rs/>
- Ink `7.0.5`: <https://www.npmjs.com/package/ink>

Refresh command:

```sh
node - <<'NODE'
(async () => {
  const sources = [
    ['Nocterm', 'https://pub.dev/api/packages/nocterm', data => data.latest?.version],
    ['Bubble Tea', 'https://api.github.com/repos/charmbracelet/bubbletea/releases/latest', data => data.tag_name],
    ['Textual', 'https://pypi.org/pypi/textual/json', data => data.info?.version],
    ['OpenTUI', 'https://registry.npmjs.org/%40opentui%2Fcore', data => data['dist-tags']?.latest],
    ['Ratatui', 'https://crates.io/api/v1/crates/ratatui', data => data.crate?.newest_version],
    ['Ink', 'https://registry.npmjs.org/ink', data => data['dist-tags']?.latest],
  ];
  for (const [name, url, pick] of sources) {
    const response = await fetch(url, {headers: {'User-Agent': 'fleury-positioning-refresh'}});
    const data = await response.json();
    console.log(`${name}: ${pick(data)} (${url})`);
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
NODE
```
