# Fleury DX Peer Assessment

**Date:** 2026-06-08
**Status:** Current-state assessment from local source + official peer docs
**Frame:** Move from perf back to developer experience, with enough peer context
to decide what should become Fleury's next leading edge.

## Executive Read

Yes, Fleury is in a good enough performance state to shift the main product
attention to DX/ergonomics. The benchmark work did not surface an architecture
smoking gun that should block that move, and the current DX surface is now the
larger competitive lever.

The high-level read:

- Fleury is already unusually strong for a TUI framework on framework shape,
  testability, semantic inspection, terminal correctness primitives, and
  batteries-included widgets.
- Fleury is not yet as clean as Flutter or Textual on the "new developer gets
  productive in one sitting" path: examples, docs, app templates, inspector-like
  tooling, and API consistency are the weak spots.
- The biggest peer-leading opportunity is not "more widgets." It is a coherent
  modern TUI developer loop: Flutter-like authoring, Textual-grade app tooling,
  first-class semantic testing/automation, capability-aware terminal fallbacks,
  and benchmark/profiling commands that stay part of normal development.

## Method

This assessment used three cycles:

1. **Local Fleury inventory.** Reviewed current public barrels, README examples,
   test exports, widget catalog, command tooling, demo app usage, and the June 3
   DX cohesion audit.
2. **Peer research.** Checked current official docs or package pages for Ink,
   Bubble Tea/Bubbles/Huh, Textual, Ratatui, Flutter, OpenTUI, and Nocterm.
3. **Synthesis.** Compared the frameworks across component availability, public
   APIs, reactivity, app lifecycle, input/focus, async/process work, styling,
   terminal capability handling, testing, devtools, documentation, and
   distribution.

Sources are linked in [Peer Sources](#peer-sources).

## Current Fleury Surface

| Area | Current Fleury evidence | Read |
| --- | --- | --- |
| Authoring model | `Widget`, `StatefulWidget`, `State`, `BuildContext`, keys, reconciliation, inherited widgets, render objects, constraints, `setState`, focus, navigation, overlay. | Strong. This is the main Flutter-inspired bet and it is real in the public API. |
| App shell | `FleuryApp`, `FleuryAppController`, `AppCommand`, `CommandRegistry`, `CommandScope`, status bar, command palette integration, and app-owned navigation in the demo console. | Strong capability, cleaner after removing the framework screen registry. The demo console uses it heavily; the core quick start does not. |
| Core widgets | Layout, text, rich text, text input/area, scroll, focus, key bindings, gestures/mouse, navigator, overlay, future/stream/listenable builders, animations, theme. | Strong for a TUI core. Flutter muscle-memory compatibility needs tightening where names imply Flutter parity. |
| Widget catalog | Inputs/forms, tables, tree table, file browser, command palette, dialogs, toasts, charts, markdown/code/diff/json/log/message/task/process views, image/canvas drawing. | Very strong breadth, especially for developer-tool TUIs. Broader than Ink/Bubbles/Ratatui core; competitive with Textual for TUI-specific widgets. |
| Reactivity/state | `setState`, `ChangeNotifier`, `Listenable`, inherited dependencies, `FutureBuilder`, `StreamBuilder`, task controllers, command results. | Strong base. Needs a clearer blessed app-state story and naming parity around `ListenableBuilder`. |
| Testing | `package:fleury/fleury_test.dart` exposes `testWidgets`, `FleuryTester`, finders, text goldens, semantic inspection, accessibility snapshots, debug capture, byte budget helpers. | Peer-leading candidate. Comparable shape to Flutter testing, more terminal-specific than most TUI peers. |
| Tooling | `dart tool/fleury_dev.dart` covers local examples, checks, demo app, terminal matrix, MVP gates, benchmarks, profiling, scoreboards, CLI build/activation. | Powerful internal tooling. Not yet polished as a user-facing `fleury` CLI with create/doctor/devtools flows. |
| Perf/profiling | Scenario benchmarks, peer wire runs, benchmark manifests, variance files, scoreboard generation, profiler command surface. | Strong enough to inform decisions. This should remain a gate, not the main current product focus. |
| Terminal correctness | Capability detection, diagnostics, terminal probes, width resolution, sanitizer, fake/native drivers, capability requirement types. | Architecturally strong. Prior DX audit found propagation uneven across the widget catalog. |
| Semantics/accessibility | Semantic tree, roles/actions/state, inspection snapshots, accessibility snapshots, app/command/screen semantics. | One of the strongest differentiators. Needs better demos and inspectable output so developers feel it quickly. |
| Docs/examples | Core quick start, testing docs, animation docs, widget catalog README, demo console, benchmark docs. | Adequate but fragmented. Missing the canonical "build a multi-screen Fleury app" path. |

## Peer Comparison Matrix

Scores are directional DX scores, not product quality scores.

| Axis | Fleury | Leading peer(s) | Assessment |
| --- | ---: | --- | --- |
| Flutter-style retained authoring | 4 | Flutter, Nocterm | Fleury is close enough that divergences hurt. Tighten compatibility where a class borrows Flutter naming. |
| TUI component breadth | 5 | Textual, Flutter | Fleury's first-party developer-tool widgets are a real advantage. Keep expanding through use-case pressure, not generic catalog padding. |
| Component API consistency | 3 | Flutter, Textual | Many patterns are good individually, but copy/export/controller/theme/capability contracts still need a consistency pass. |
| App lifecycle/navigation/commands | 4 | Textual, Flutter | Fleury has the right primitives. It needs a small canonical app example and cookbook. |
| Reactivity/state clarity | 4 | Flutter, Ink/React, Textual | `setState`/Listenable/inherited/task controllers are strong. Textual's reactive attributes and React hooks are easier to explain quickly. |
| Input/focus/key handling | 4 | Textual, Bubble Tea, Ratatui ecosystem | Fleury has integrated focus/key primitives. More recipes are needed for command palettes, modal flows, and text-heavy apps. |
| Async/process work | 4 | Textual, Bubble Tea | Task controllers and process/log widgets are strong. The "how to structure async work" story should be more explicit. |
| Styling/theming | 3 | Flutter, Textual, Charm | Fleury has Theme and widget theme types. Catalog propagation and documented recipes lag the leaders. |
| Terminal capability handling | 4 | Ratatui, OpenTUI | Fleury has unusually good architecture here. Catalog fallback propagation must catch up before calling it peer-leading. |
| Testing/goldens/semantics | 5 | Flutter, Textual | This is already a top-tier Fleury DX pillar. Semantic testing can be made peer-leading with better examples and tools. |
| Devtools/inspection | 2 | Flutter, Textual | Fleury has debug capture and terminal/profiling tools, but not an inspector/console/devtools experience. |
| Documentation/onboarding | 3 | Flutter, Textual, Bubble Tea | The pieces exist, but they are not sequenced for a newcomer. This is the fastest high-impact improvement area. |
| Scaffolding/lints/assists | 2 | Flutter, Nocterm, Textual | Fleury lacks a polished create/doctor/lints/IDE assist story. Nocterm is the local Dart peer to watch here. |
| Web/remote story | 3 | OpenTUI, Textual, Flutter | Fleury has a web package direction, but it is not yet the stable developer-facing story. |

## Peer Notes

### Flutter

Flutter is the DX gold standard for the inspiration Fleury chose: huge widget
catalog, hot reload, devtools, inspector, performance tooling, testing,
goldens, integration testing, and a mature cookbook. Fleury does not need to
match Flutter's full ecosystem, but when it borrows Flutter names, developers
will expect Flutter signatures and conventions.

Implication for Fleury: preserve the Flutter-shaped core, but remove avoidable
uncanny-valley mismatches. Use terminal-specific features as additions, not
surprises.

### Textual

Textual is the strongest full-app TUI peer. It has documented widgets, screens,
bindings/actions, command palette, workers, reactive attributes, headless tests,
snapshot testing, devtools console, live CSS editing, and a clear app structure.

Implication for Fleury: Textual is the peer to benchmark against for app-scale
DX and devtools, not just rendering performance.

### Bubble Tea, Bubbles, and Huh

Bubble Tea wins by being extremely easy to explain: `Init`, `Update`, `View`.
Bubbles and Huh make common app pieces approachable: inputs, viewport, list,
forms, prompts, timers, file picker, and accessible forms.

Implication for Fleury: Fleury can be more powerful, but should copy the
clarity. The command/app/task patterns need short recipes that make common
flows obvious.

### Ink

Ink's strength is React compatibility. Its docs lean on "if you know React, you
know Ink," and the real adoption signal is strong: major CLI products use it.
The core is not a huge batteries-included TUI app framework.

Implication for Fleury: Fleury can win on integrated terminal app surfaces, but
Ink is a reminder that authoring familiarity can beat catalog depth. Flutter
muscle memory is Fleury's analogous advantage, so it must be treated carefully.

### Ratatui

Ratatui is a lower-level Rust rendering/UI library with strong performance,
buffer diffing, layout primitives, and explicit terminal lifecycle control. It
does not include input handling or a full app framework by default.

Implication for Fleury: keep low-level escape hatches and terminal truth strong,
but do not compete with Ratatui by becoming lower-level. Fleury's advantage is
the higher-level app loop.

### OpenTUI

OpenTUI is a modern high-performance entrant with a native core, TypeScript
bindings, React/Solid plugins, Yoga layout, rich text/code/diff components,
animations, and explicit renderer modes for alternate screen, main screen, and
split footer.

Implication for Fleury: OpenTUI is a serious modern-DX/performance peer. Fleury
should answer with Dart/Flutter ergonomics, semantic testing, terminal
capability correctness, and a credible web/remote story.

### Nocterm

Nocterm is the closest Dart/Flutter-shaped peer: `runApp`, components, state,
layout, hot reload, testing, bloc support, lints, and IDE assists.

Implication for Fleury: Fleury appears broader and more app-framework oriented,
but Nocterm may feel smoother to Flutter developers if its naming, lints, and
assists are more familiar. Fleury should not ignore that.

## Where Fleury Is Strong

| Strength | Why it matters | Peer posture |
| --- | --- | --- |
| Flutter-shaped core in Dart | Developers can transfer mental models for widgets, state, layout, inherited dependencies, testing, animation, and hot reload. | Stronger than most TUI peers; closest peer is Nocterm. |
| Large first-party widget catalog | Fleury already has the kind of app widgets real developer tools need: tables, logs, markdown, diff, code, tasks, command palettes, file surfaces, and charts. | Stronger than Ink/Ratatui core/Bubbles breadth; competitive with Textual for TUI-specific use cases. |
| Semantic tree and test integration | Tests, accessibility, and agents can inspect and operate apps through roles, labels, actions, and state rather than brittle screen text. | Potentially peer-leading. Needs better demos and inspector UX. |
| Terminal correctness architecture | Capability detection, probes, width resolution, sanitization, native/fake drivers, and benchmark gates are a more serious terminal story than many high-level frameworks expose. | Strong, but catalog fallback propagation must improve. |
| Benchmark/profiling harness | Perf decisions can be tied to repeatable local scenarios and peer wire captures. | Strong for a young framework; keep it as a release gate. |
| Demo app coverage | The example console proves the app kernel, command palette, widgets, process/log surfaces, and many workflows are usable together. | Strong evidence, but hidden from first-contact onboarding. |

## Where Fleury Is Weak

| Weakness | Current evidence | Priority |
| --- | --- | --- |
| Newcomer path is fragmented | Core README starts with a counter. The app-kernel demo exists in `fleury_example_console`, but there is no small canonical multi-screen app tutorial in the core package. | P0 |
| Flutter uncanny-valley mismatches | `ListenableBuilder` now has the Flutter-shaped `listenable:` path. The old screen-controller mismatch was resolved by removing the framework-level screen concept rather than adding aliases. Remaining mismatches should be found through exported API audits and demo-app usage. | P1 |
| Devtools lag leaders | Fleury has debug capture, semantic inspection, terminal matrix, and benchmark commands, but not a Flutter/Textual-style inspector/console/devtools workflow. | P1 |
| Tooling is internal-shaped | `dart tool/fleury_dev.dart` is powerful, but user-facing flows should be `fleury create`, `fleury doctor`, `fleury test`, `fleury benchmark`, `fleury inspect`, and documented templates. | P1 |
| Catalog contracts need consistency | The June 3 DX audit found uneven propagation for capability fallback, theming, copy/export, sanitization, and disposal. Current exports show many good copy/export/controller types, but this still deserves a dedicated contract-refresh pass. | P1 |
| State/reactivity story is implicit | The primitives exist, but there is no concise "use setState for local, ChangeNotifier for shared, TaskController for async, commands for app actions" guide. | P1 |
| Lints/assists/scaffolding are absent | Nocterm has `nocterm_lints`; Flutter has analyzer assists and project templates. Fleury has no comparable authoring guardrails yet. | P2 |
| Web/remote story is not yet stable onboarding | `fleury_core` is platform-agnostic and `fleury_web` exists, but it is not yet presented as a stable developer flow. | P2 |

## Priority DX Plan

### P0: Fix The First-Hour Developer Loop

1. Add a small canonical app-kernel example under `packages/fleury/example/`.
   It should show `FleuryApp`, two or three screens, app commands, screen
   commands, status items, command palette, semantic test, and one async task.
2. Write a "Build a multi-screen Fleury app" guide and link it from the core
   README before the advanced demo console.
3. Keep the highest-confidence Flutter compatibility fixes landed and guarded:
   - `ListenableBuilder(listenable: ...)`, keeping `animation:` as a legacy
     alias if needed.
   - no framework `ScreenController`; apps use ordinary controllers, tabs,
     sidebars, `Navigator`, and commands.
4. Add a concise state/reactivity guide:
   - local UI state: `State.setState`
   - shared model state: `ChangeNotifier`/`ListenableBuilder`
   - app navigation/actions: `FleuryApp` + `AppCommand`
   - async work: `TaskController`/`DebouncedTaskController`
   - external streams: `StreamBuilder`

Acceptance gate: a new developer can build and test a small command-driven app
without reading source files outside examples/docs.

### P1: Productize The Differentiators

1. Make semantic inspection visible:
   - readable `SemanticInspectionSnapshot.debugTree()` / `toString()`
   - `SemanticTree.debugTree()` and `FleuryTester.semanticTreeDebugString()`
     for direct test failure output
   - example test that invokes semantic actions
   - richer `SemanticInspectionSnapshot.single(...)` failure messages that
     include the query and current semantic tree
   - later CLI/debug command that prints semantic tree summaries
2. Promote internal tooling into user-facing CLI flows:
   - `fleury doctor`
   - `fleury create`
   - `fleury test` or documented `dart test` wrappers
   - `fleury benchmark`
   - `fleury inspect`
3. Add a lightweight devtools loop:
   - screen/render tree summary
   - semantic tree summary
   - focus tree
   - terminal capability report
   - last-frame byte/layout stats
4. Refresh the widget-catalog contract matrix and roll out the existing good
   patterns. The current pass is tracked in
   [Widget API ergonomics audit](widget-api-ergonomics-audit-2026-06-08.md):
   - controller ownership/disposal
   - copy/export result APIs
   - capability fallback
   - theme consumption
   - untrusted text sanitization

Acceptance gate: the framework's claimed differentiators are easy to demo in
five minutes and are enforced by tests or contract checks.

### P2: Make Fleury Feel Mature

1. Add `fleury_lints` or analyzer checks for common mistakes:
   - introducing framework-owned app sections where ordinary widget state,
     `Navigator`, or scoped commands would be clearer
   - missing controller disposal for externally owned controllers
   - capability-sensitive widgets without fallback declarations
   - uncategorized commands/status items in app-kernel code
2. Add templates:
   - counter
   - multi-screen app
   - log/process monitor
   - data table dashboard
   - chat/agent console
3. Build a searchable widget gallery, ideally backed by real Fleury examples.
4. Decide the stable web/remote story and document it once it is real enough to
   support.

Acceptance gate: Fleury has the same kind of "obvious next command" developer
experience that Flutter, Textual, and Nocterm are aiming at.

## Strategic Take

Fleury should move from perf to DX/ergonomics now, with perf staying as a
scoreboard gate. The next wins are not low-level architecture rewrites. They are
developer-loop wins:

1. Make Flutter familiarity exact where possible.
2. Make the app-kernel path easy to discover.
3. Turn semantic inspection from hidden architecture into visible DX.
4. Promote the existing internal tooling into a user-facing CLI.
5. Roll out catalog contracts so the broad widget surface feels coherent.

That would position Fleury differently from each peer:

- More batteries-included than Ink and Bubble Tea core.
- More app/DX oriented than Ratatui.
- More Flutter-familiar than Textual and OpenTUI.
- More semantic/test/capability-aware than Nocterm if Fleury productizes those
  advantages quickly.

## Peer Sources

- [Flutter widget catalog](https://docs.flutter.dev/reference/widgets)
- [Flutter hot reload](https://docs.flutter.dev/tools/hot-reload)
- [Flutter DevTools](https://docs.flutter.dev/tools/devtools)
- [Flutter inspector](https://docs.flutter.dev/tools/devtools/inspector)
- [Flutter testing overview](https://docs.flutter.dev/testing/overview)
- [Flutter widget testing cookbook](https://docs.flutter.dev/cookbook/testing/widget/introduction)
- [Textual docs](https://textual.textualize.io/)
- [Textual widgets](https://textual.textualize.io/widgets/)
- [Textual testing](https://textual.textualize.io/guide/testing/)
- [Textual devtools](https://textual.textualize.io/guide/devtools/)
- [Textual command palette](https://textual.textualize.io/guide/command_palette/)
- [Textual reactivity](https://textual.textualize.io/guide/reactivity/)
- [Textual actions](https://textual.textualize.io/guide/actions/)
- [Textual workers](https://textual.textualize.io/guide/workers/)
- [Bubble Tea](https://github.com/charmbracelet/bubbletea)
- [Bubbles](https://github.com/charmbracelet/bubbles)
- [Huh](https://github.com/charmbracelet/huh)
- [Ink](https://github.com/vadimdemedes/ink)
- [Ratatui](https://ratatui.rs/)
- [Ratatui docs.rs API docs](https://docs.rs/ratatui/latest/ratatui/)
- [OpenTUI](https://opentui.com/)
- [OpenTUI renderer docs](https://opentui.com/docs/core-concepts/renderer/)
- [OpenTUI React plugin](https://opentui.com/docs/plugins/react/)
- [Nocterm package](https://pub.dev/packages/nocterm)
