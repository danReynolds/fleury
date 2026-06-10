# Fleury Roadmap: Leading Reactive TUI Framework

**Status:** Strategy and execution plan  
**Date:** 2026-05-31  
**Scope:** Fleury core, widget catalog, runtime, testing, terminal drivers, and developer-tool use cases  

**Active execution tracker:** Use
[docs/implementation/README.md](implementation/README.md) for milestone
checklists, workstream notes, implementation evidence, and decision tracking.

## 1. Executive Thesis

Fleury should aim to be the best framework for production terminal
applications, not only the best Dart TUI framework.

The target product is a retained, reactive, Flutter-style framework that
combines:

- Flutter-style local state, composition, layout, testing, and hot reload.
- Textual-style app structure, commands, screens, workers, devtools, and
  full-screen application ergonomics.
- Ratatui-style performance discipline and data-heavy widget coverage.
- Bubble Tea and Charm-style product taste for CLI workflows, forms, and
  approachable APIs.
- prompt_toolkit-level text input, editing, completion, and keymap depth.
- Notcurses/ncurses-level respect for terminal protocols, Unicode,
  capabilities, cleanup, and degradation.

The core bet:

> Terminal apps are becoming richer, more stateful, and more central to
> developer workflows, especially for AI agents, observability, operations,
> deployment, database tools, and code review. Existing frameworks are strong
> in individual dimensions, but no framework yet provides a best-in-class
> synthesis of modern reactive UI, serious terminal correctness, serious input
> editing, rich data widgets, async process workflows, deterministic testing,
> and app-scale structure.

Fleury can fill that gap.

## 2. North Star

Fleury should make this feel normal:

- Build a terminal application the way a Flutter developer builds a GUI app.
- Ship dense, keyboard-first, data-heavy workflows without building all
  focus, command, modal, input, and rendering infrastructure manually.
- Trust text input, tables, lists, logs, markdown, selection, clipboard,
  images, keybindings, async tasks, terminal resize, SSH/tmux, and cleanup.
- Test the app deterministically without a real terminal.
- Profile and debug the app from inside the terminal.
- Degrade gracefully when capabilities are missing.

The long-term positioning:

> Fleury is a Flutter-style framework for production terminal applications:
> reactive, testable, fast, terminal-correct, and batteries-included for
> data-heavy developer tools and agent workflows.

### Demo App Strategy

Fleury should be developed against real application pressure, not only toy
examples.

For this implementation cycle, the proof surface is an **example subpackage**
inside the Fleury workspace. It should exercise the core framework like a real
app while staying independent from Dune's product schedule.

The later flagship product is **Dune through a future `dune_cli` app**. Dune
should become the primary public proof surface after the core widgets and app
framework are stable through examples, tests, and benchmarks.

This changes the roadmap discipline:

- Framework primitives should first be validated in the example subpackage.
- The example subpackage should mimic real developer-tool pressure:
  navigation, commands, text input, data views, logs/output, selection,
  capability fallback, diagnostics, and benchmark fixtures.
- Dune/`dune_cli` should begin only after the example subpackage proves the
  core widgets and framework pieces work together.
- Dune remains the later flagship commitment; the example subpackage is the
  current-cycle proof harness.

The current-cycle proof slice should stay narrow: sidebar/navigation,
streamed content, composer/input, status, commands, selection, output/log
regions, and at least one dense data surface. Tool-call, approval,
protocol-specific agent flows, Dune integration, and full replay are future
pressure tests, not current-cycle blockers.

### Why Dart, Honestly

Dart is not the default language for CLI frameworks. Go, Rust, Python, and
TypeScript have stronger existing TUI ecosystems. Fleury should not hide that.

The Dart bet is still defensible:

- Dart gives Fleury a Flutter-shaped mental model without depending on
  Flutter's engine.
- Hot reload can make terminal app iteration feel unusually fast.
- `dart compile exe` gives a credible standalone-binary distribution story.
- Sound null safety and strong async primitives are a good fit for structured
  developer tools.
- Dart/Flutter-adjacent developers can serve as the first natural audience,
  with Dune becoming the later flagship path.

The tradeoff is real:

- Most CLI builders are not Dart developers today.
- The package ecosystem for terminal apps is smaller than Go, Rust, Python,
  or TypeScript.
- Fleury must win on product capability, not only language affinity.

Therefore the launch pitch should not be "Dart TUI framework" alone. It
should be "semantic, replayable, capability-aware developer-tool TUIs with
Flutter-style ergonomics," with Dart as the implementation advantage.

## 3. Current Position

Fleury already has credible foundations:

- Flutter-shaped widget/element/state model.
- Cell-based render objects, constraints, buffers, and ANSI diffing.
- Focus, keybindings, pointer routing, navigator, overlay, media query, and
  theme primitives.
- `runTui` runtime with terminal lifecycle management, output capture, debug
  shell plumbing, hot reload, and cleanup.
- Testing via `FleuryTester`, fake drivers, input simulation, and golden text
  assertions.
- Lazy `ListView.builder`, repaint boundaries, animation scheduler, and
  benchmark records.
- A higher-level widget package with tables, trees, tabs, command palette,
  controls, pickers, charts, heatmaps, image rendering, markdown, toasts, and
  dialogs.

The important gaps are also clear:

- Text input is not yet best-in-class.
- There is no complete app shell abstraction.
- Commands, actions, shortcuts, status bars, menu bars, and global command
  discovery are not yet unified.
- Data widgets exist, but not yet as a production data framework.
- Async workers, subprocesses, progress, cancellation, and stream binding are
  not first-class.
- Terminal capability probing and compatibility policy are incomplete.
- Dirty layout/paint propagation now has a conservative foundation, benchmark
  proof, and a first audited paint-only split; the remaining performance work
  is broader widget-package setter auditing under scenario pressure.
- Styling and theming are clean but not yet expressive enough to rival the
  best product-oriented terminal frameworks.
- Agent/developer-tool-specific primitives are not yet first-class.

## 4. Ecosystem Lessons

### Ratatui

Primary reference: <https://ratatui.rs/>

What it does well:

- Fast immediate-mode rendering.
- Clear terminal buffer model.
- Strong layout primitives.
- Useful built-in widgets: table, list, chart, gauge, tabs, canvas, calendar,
  sparkline, scrollbar.
- Explicit application loops and async examples.
- Rust performance culture and scenario benchmarks.

What Fleury should learn:

- Treat performance as an engineering discipline with scenario benchmarks.
- Make data-heavy widgets central, not secondary.
- Keep rendering primitives direct and predictable.
- Offer enough low-level escape hatches for users building unusual terminal
  tools.

Gap Fleury can fill:

- Ratatui users assemble a lot of app architecture themselves. Fleury can give
  retained reactive composition, local state, focus, commands, routes, async
  workers, and tests out of the box.

### Textual

Primary reference: <https://textual.textualize.io/>

What it does well:

- Full application framework, not just widgets.
- Screens, widgets, reactive state, CSS, command palette, actions, key
  bindings, workers, timers, testing, and devtools.
- Strong built-in widgets such as data tables, text areas, tree views,
  markdown, logs, progress, tabs, and option lists.
- Mature app lifecycle and event model.

What Fleury should learn:

- `App`/`Screen`/`Action`/`Worker` are not optional if the goal is app-scale
  productivity.
- Testing and devtools should be framework features, not examples.
- Command palette and keyboard discovery should be structural.
- Background work and UI updates need a safe, first-class model.

Gap Fleury can fill:

- Offer a lighter, Flutter-style retained UI model with compile-time types and
  Dart ergonomics.
- Avoid CSS complexity as the primary styling model while still offering
  expressive themes.
- Be more terminal-protocol explicit and testable at the cell level.

### Bubble Tea, Bubbles, Lip Gloss, Huh

Primary references:

- <https://github.com/charmbracelet/bubbletea>
- <https://github.com/charmbracelet/bubbles>
- <https://github.com/charmbracelet/lipgloss>
- <https://pkg.go.dev/github.com/charmbracelet/huh>

What they do well:

- Approachable Elm-style architecture.
- Excellent terminal product taste.
- Strong inputs, text areas, tables, spinners, progress, forms, and styling.
- CLI-friendly workflows and graceful prompt-style interactions.
- Ecosystem coherence across rendering, styling, forms, and components.

What Fleury should learn:

- The default visual and interaction design matters.
- Forms deserve first-class treatment.
- Styling should be pleasant without being heavyweight.
- Simple CLIs and full-screen apps should share a continuum.

Gap Fleury can fill:

- Complex Bubble Tea apps often require manual message routing, focus
  management, and component orchestration. Fleury can make that declarative
  and retained.

### Ink

Primary reference: <https://github.com/vadimdemedes/ink>

What it does well:

- Leverages a mental model developers already know: React.
- Component composition, hooks, flexbox, testing, and npm ecosystem fit.
- Good for modern CLIs and agent-style tools.

What Fleury should learn:

- Familiarity is a real feature.
- A reactive component model lowers adoption friction.
- Full-screen apps and command output should not be separate worlds.

Gap Fleury can fill:

- Be more full-screen-app-native, terminal-capability-aware, and data-widget
  oriented than the typical React-for-CLI stack.

### prompt_toolkit

Primary reference: <https://python-prompt-toolkit.readthedocs.io/>

What it does well:

- Serious input editing.
- Completions, suggestions, validation, search, key bindings, mouse support,
  async support, full-screen apps, layout containers, and Unicode handling.
- Emacs/Vi-style keymap depth.

What Fleury should learn:

- Text input is a framework-defining primitive.
- Serious terminal apps need editing behavior that users can trust.
- Completion, validation, history, and selection should be part of the core
  model, not one-off widgets.

Gap Fleury can fill:

- Put prompt_toolkit-grade input inside a Flutter-style reactive app
  framework with rich widgets and deterministic tests.

### ncurses and Notcurses

Primary references:

- <https://invisible-island.net/ncurses/>
- <https://github.com/dankamongmen/notcurses>

What they do well:

- Deep terminal protocol experience.
- Robust alternate screen, color, mouse, wide character, forms, menus, panels,
  and cleanup primitives.
- Notcurses adds modern Unicode, graphics, images/video, Sixel/Kitty
  awareness, direct mode, and terminal interrogation.

What Fleury should learn:

- Terminal compatibility is product quality.
- Unicode, grapheme clusters, double-width characters, terminal probing,
  image cleanup, clipboard, suspend/resume, and broken-terminal recovery must
  be designed, not patched in later.

Gap Fleury can fill:

- Bring this seriousness to a modern reactive framework rather than a lower
  level C-style API.

### Nocterm

Primary references:

- <https://pub.dev/packages/nocterm>
- <https://nocterm.dev/>
- <https://github.com/Norbert515/nocterm>

What it does well:

- Closest Dart peer.
- Flutter-like components, state, navigation, text fields, selection, images,
  themes, web/socket pieces, hot reload, and tests.
- More mature public package surface today.

What Fleury should learn:

- Do not assume Dart developers will choose Fleury for internals.
- Visible wins must be performance, robustness, ergonomics, app widgets, input,
  and production workflows.

Gap Fleury can fill:

- Become the more complete production app framework with better data widgets,
  stronger app shell, stronger input, stronger diagnostics, and clearer
  terminal compatibility guarantees.

## Second Research Pass: Validated Findings

This section updates the plan after a deeper pass over adjacent frameworks,
current issue trackers, agent-terminal tools, and protocol-shaped workflow
systems. The main conclusion is sharper than the first roadmap:

> Fleury should not compete by being a nicer widget library. Fleury should
> compete by being the first terminal application framework that combines a
> Flutter-style developer experience with semantic inspection, progressive
> interaction modes, serious text/data engines, structured effects, terminal
> capability contracts, and deterministic replay.

### What Changed

The challenge pass changed several priorities:

- The semantic tree is no longer a speculative bet. It is the backbone for
  tests, accessibility, prompt fallback, devtools, replay, remote mirrors,
  agent operation, and debugging.
- Prompt mode and full-screen mode should not be separate products. They are
  different projections of the same interaction model.
- Terminal capability handling must be developer-visible. Components should
  declare requirements and fallbacks, not silently hope the terminal behaves.
- Text editing and data virtualization are not widget work. They are core
  engines that determine whether the framework feels serious.
- Replay is not just a devtools feature. It affects how effects, workers,
  time, subprocesses, input, resize, and rendering should be modeled.
- Agent workflows are not only a future niche. They are a concrete forcing
  function for streaming markdown, diffs, approvals, tool calls, file
  references, process logs, permissions, cancellation, and inspection.
- Security around terminal output belongs in the foundation. Raw ANSI,
  subprocess output, OSC 52 clipboard writes, OSC 8 links, images, markdown,
  secrets, and logs all need policies.

### Peer Signal Highlights

**OpenTUI** shows where the frontier is moving: a fast native core, component
architecture, flexbox layout, and multiple reconcilers. Its issue tracker also
shows the real cost of frontier terminal rendering: accessibility, IME,
graphemes, shutdown cleanup, debug ergonomics, overlays, and protocol edge
cases remain hard.

**Terminal.Gui** demonstrates the value of a broad application toolkit:
tables, tree views, text editing, theming, mouse, keyboard, file browsers,
wizards, and inline/full-screen modes. Its open issues reinforce that layout
invalidation, redraw cost, and editor depth remain long-term framework
problems even in mature GUI-like TUIs.

**tview and tcell** show the Go ecosystem split that Fleury should internalize:
rich widgets are valuable, but they sit on protocol foundations for Unicode,
mouse, colors, keyboard handling, and portable cell rendering.

**Bubble Tea, Bubbles, Huh, and Lip Gloss** show the best CLI product taste:
Elm-style updates, reusable prompt components, declarative styles, accessible
prompt aspirations, and approachable APIs. Their issues also show that
inline/full-screen boundaries, native text selection, subprocess handoff,
scrollback preservation, renderer artifacts, and accessibility are visible
developer pain.

**Textual** remains the strongest reference for full app structure: apps,
screens, widgets, CSS, commands, workers, timers, testing, devtools, and rich
data widgets. Its active issues show that mature app frameworks still struggle
with DataTable behavior, Unicode measurement, CSS complexity, worker limits,
markdown performance, and accessibility.

**Ink** proves that React-style terminal UI can win adoption in serious CLI
tools, including AI/developer CLIs. Its renderer and scrollback issues show
that a familiar reactive mental model is not enough without strong terminal
lifecycle policy.

**prompt_toolkit** sets the bar for text input depth: multiline editing,
completion, search, selection, key bindings, bracketed paste, Unicode width,
history, buffers, and style.

**Notcurses** sets the high-end terminal ambition: rich color, images, video,
sprites, Unicode, keyboard protocol support, capability fallback, and
aggressive use of advanced terminal features.

**Agent Client Protocol, Codex-style agents, Gemini CLI, Crush, and OpenCode**
show that agent UIs are converging around session state, prompt turns, tool
calls, plans, permission requests, diffs, terminal output, cancellation, and
progress. Fleury should treat those as product primitives, not just example
apps.

### Implications For Fleury

Fleury's strongest path is to become a system of coordinated engines:

- A semantic app graph that describes intent above cells.
- A retained reactive UI and render engine that keeps Flutter-style ergonomics.
- A text/editing engine deep enough for real developer tools.
- A data/virtualization engine for tables, logs, trees, code, markdown, and
  diffs.
- A workflow/effects engine for subprocesses, workers, permissions, progress,
  cancellation, and replay.
- A terminal capability engine that makes features and fallbacks explicit.
- A devtools/testing/replay engine that makes complex TUIs inspectable.

The framework should still feel like Flutter at the API layer. Underneath,
however, it should be designed less like a widget catalog and more like a
small operating environment for terminal applications.

## Refined Architecture: Seven Engines

Fleury should be planned as seven engines with clear boundaries. This does
not mean seven packages immediately. It means every major feature should know
which engine owns its correctness.

### Engine 1: Semantic App Graph

Purpose:

- Maintain an inspectable model of roles, labels, values, focus, selection,
  commands, routes, regions, tables, text fields, dialogs, progress, errors,
  diffs, logs, tool calls, and capability requirements.
- Exist above terminal cells and below user-facing tests/devtools.

Developer-visible win:

- Tests query by role and state rather than brittle screen text.
- Devtools explain the app structure, not just the last frame.
- Accessibility and prompt fallback have a source of truth.
- Agent and automation tools can operate on structured actions.

Launch gate:

- `FleuryTester` can query semantic nodes for buttons, fields, tables, dialogs,
  commands, focus, selection, and validation errors.
- The debug inspector shows the semantic graph beside the widget/render tree.
- A simple form can render as a full-screen UI and as prompt-mode flow using
  the same semantic definition.

### Engine 2: Reactive UI And Render

Purpose:

- Preserve the Flutter-style widget, element, state, inherited dependency,
  layout, render object, repaint, and golden-test model.
- Diff terminal frames efficiently while allowing low-level render islands for
  extremely hot widgets.

Developer-visible win:

- Developers get a familiar retained reactive API.
- Common widgets compose predictably.
- Heavy widgets can be fast without forcing every user into low-level code.

Launch gate:

- Scenario benchmarks cover table scrolling, log tailing, markdown streaming,
  text editing, dashboard updates, resize storms, and overlay churn.
- Dirty layout/paint propagation avoids full-tree work for common updates.
- First-party render islands still expose semantics, focus, hit testing, copy,
  theme, and tests.

### Engine 3: Text And Editing

Purpose:

- Provide a pure editing model for grapheme-indexed text, selection, undo,
  redo, history, completion, keymaps, paste, clipboard, password policy,
  multiline editing, and future IME/composition hooks.

Developer-visible win:

- Text fields feel trustworthy in shells, forms, search boxes, prompts,
  command palettes, code views, chat inputs, and config editors.

Launch gate:

- Single-line and multiline fields share the same `TextEditingValue` model.
- Unicode, emoji, CJK, double-width, combining marks, and bracketed paste are
  covered by model tests.
- Emacs-style defaults and optional Vi-style editing are possible without
  forking the widget.

### Engine 4: Data And Virtualization

Purpose:

- Own large tables, trees, logs, markdown streams, code views, JSON views,
  diffs, file browsers, search, filtering, sorting, selection, fixed headers,
  frozen columns, and copy/export.

Developer-visible win:

- Fleury becomes the obvious choice for dense developer tools rather than
  only nice prompts.

Launch gate:

- `DataTable`, `TreeTable`, `LogView`, `DiffView`, `CodeView`, and
  `MarkdownView` have stable keyboard, mouse, selection, clipboard, search,
  and virtualization behavior.
- 100k-row and high-rate streaming scenarios remain responsive under
  benchmarks.
- Data widgets expose semantic rows, cells, regions, selections, and actions.

### Engine 5: Effects, Workflow, And Process

Purpose:

- Model async work, subprocesses, streams, timers, network calls, permission
  requests, cancellation, progress, background workers, output capture, and
  lifecycle cleanup.

Developer-visible win:

- Developer tools can orchestrate real work without ad hoc isolate/process
  plumbing in every app.

Launch gate:

- Workers and subprocesses report typed progress, output, errors, and
  cancellation.
- Effects can be recorded in a replay log for tests.
- Terminal suspension, external editor handoff, process output, and raw-mode
  restoration are covered by tests and examples.

### Engine 6: Terminal Capability And Security

Purpose:

- Own capability probing, terminal profiles, tmux/SSH awareness, color
  degradation, image protocols, keyboard protocol support, mouse modes,
  clipboard policy, link policy, raw ANSI sanitization, secret redaction,
  cleanup, and diagnostic output.

Developer-visible win:

- Apps can explain why a feature is enabled, degraded, or disabled.
- Developers can debug terminal-specific bugs with `fleury diagnose`.
- Untrusted process output is safer by default.

Launch gate:

- Components can declare required, preferred, and optional capabilities.
- The runtime can produce a machine-readable capability report.
- Raw ANSI, OSC 52 clipboard, OSC 8 links, image output, and subprocess logs
  have explicit policies and tests.

### Engine 7: Replay, Devtools, And Testing

Purpose:

- Record and replay input, resize, fake time, worker events, subprocess
  events, capability profiles, semantic snapshots, frame timing, and rendered
  frames.

Developer-visible win:

- Complex TUI bugs become reproducible.
- Performance regressions become measurable.
- Tests can assert behavior at semantic, layout, and frame levels.

Launch gate:

- A failing scenario can emit structured debug capture with enough context to
  write a regression test.
- Later replay artifacts can run headlessly and reproduce semantic state and
  rendered frames.
- Inspector views expose focus, commands, semantics, dirty regions, effects,
  and frame timing.

## 5. Product Principles

1. **Developer-visible wins over internal elegance.** Architecture matters
   only when it produces obvious performance, reliability, or API wins.

2. **Retained reactive by default.** Fleury should preserve the Flutter-like
   experience: widgets, state, context, inherited dependencies, keys, layout,
   and tests.

3. **Terminal-native below the API.** Cells, graphemes, colors, buffers,
   capabilities, escape sequences, raw mode, SSH, tmux, resize, and cleanup
   are framework responsibilities.

4. **Input is a foundation.** If text editing feels weak, the whole framework
   feels weak.

5. **Data-heavy apps are first-class.** Tables, trees, logs, diffs, markdown,
   JSON, file browsers, and search are central to terminal apps.

6. **Async work is structural.** Terminal developer tools are mostly process
   and network orchestration.

7. **Measure scenarios, not vibes.** Performance goals should be tied to real
   app workloads.

8. **Composability beats one-off widgets.** A command palette, form field, or
   table should compose with focus, keybindings, theme, testing, selection,
   overlays, and accessibility/fallback behavior.

9. **Prompt mode and full-screen mode should share primitives.** Fleury should
   support the continuum from a single prompt to a full app.

10. **Agent workflows are a native use case.** Streaming markdown, tool calls,
    approvals, diffs, traces, and task state should be easy.

## 6. Workstream A: Text, Editing, and Input

### Goal

Build the best terminal text editing stack in any reactive TUI framework.

### Current State

`TextInput` and `TextArea` exist, but `TextInput` currently documents
important limitations: code-unit cursor positions, no selection ranges, no
horizontal scroll, and limited editing behavior.

### Target Capabilities

- `TextEditingValue`, `TextSelection`, `TextRange`, and grapheme-indexed
  editing.
- Single-line and multiline fields sharing the same editing model.
- Horizontal scrolling and vertical scrolling.
- Soft wrap and hard wrap.
- Selection ranges via keyboard and mouse.
- Shift-arrow, word movement, line movement, home/end variants, page
  movement.
- Clipboard cut/copy/paste, paste policy hooks, and bracketed paste handling.
- Undo/redo.
- History navigation.
- Completion and suggestions.
- Validation and formatting.
- Password/secret fields with paste and clipboard policy.
- Emacs and Vi keymap presets as optional modes.
- Search within text areas.
- IME-aware future extension points where the terminal supports them.

### Concrete Deliverables

1. `TextEditingValue` model.
2. Grapheme cursor/selection engine with CJK and emoji tests.
3. `EditableText` core render/edit widget.
4. `TextField` built on `EditableText`.
5. `TextArea` rebuilt on the same core.
6. Completion overlay primitive.
7. Input validator/formatter layer.
8. Keyboard shortcut presets.
9. Text editing golden and fuzz tests.

### Acceptance Criteria

- Cursor never splits a grapheme cluster.
- Double-width characters render, select, delete, and copy correctly.
- Long single-line fields keep cursor visible.
- Multiline fields handle selection across wrapped and unwrapped lines.
- Paste can be accepted, transformed, rejected, or handled by the app.
- Editing behavior is deterministic in `FleuryTester`.
- Fleury text input is at least competitive with Nocterm, Bubbles, and
  prompt_toolkit on common editing workflows.

## 7. Workstream B: App Kernel

### Goal

Make Fleury feel like a complete application framework, not a widget library.

### Target Capabilities

- `FleuryApp`
- `Screen`
- App lifecycle hooks
- Route/screen registry
- `Command`
- `CommandRegistry`
- `Action`
- `ShortcutMap`
- Global command palette
- Menu/status/footer bars
- Modal host
- Toast host
- Focus policy
- Theme root
- Error boundary
- App services scope
- Suspend/resume handling

### API Sketch

```dart
void main() => runTui(
  FleuryApp(
    title: 'Deploy Console',
    theme: ThemeData.dark(),
    commands: [
      Command('deploy.run', label: 'Run deploy', action: DeployAction()),
      Command('logs.open', label: 'Open logs', action: OpenLogsAction()),
    ],
    shortcuts: {
      .ctrl.shift.p: 'app.commandPalette',
      .ctrl.c: 'app.cancel',
      .ctrl.l: 'logs.open',
    },
    home: const DeployScreen(),
  ),
);
```

### Acceptance Criteria

- Global shortcuts are discoverable and testable.
- Command palette operates over the app command registry.
- Screens can define local commands and override shortcuts.
- Modal scopes correctly suppress or allow globals.
- Status/footer bars can show active bindings without manual wiring.
- Errors render in-app where possible and still clean up the terminal.

## 8. Workstream C: Forms and Prompt Continuum

### Goal

Make Fleury excellent for both full-screen forms and simple prompt flows.

### Target Capabilities

- `Form`
- `FormField<T>`
- Built-in fields: text, password, number, select, multi-select, checkbox,
  radio, date, file, path, color, slider, range, confirm.
- Validation, async validation, field dependencies, dynamic options.
- Wizard/page flow.
- Draft state and reset.
- Submit/cancel lifecycle.
- Accessible non-full-screen fallback prompt mode.
- Themeable error, hint, help, and disabled states.

### Why This Matters

Many terminal tools are form-driven: deploy prompts, config editors, database
connection setup, scaffolding flows, auth/device flows, issue creation, and AI
approval gates. Charm's Huh shows that forms are a product surface, not a
miscellaneous widget category.

### Acceptance Criteria

- Complex forms require little custom focus/keybinding code.
- Validation and error display are uniform across fields.
- A full-screen form can degrade to a sequential prompt flow.
- Forms can be tested without a terminal.

## 9. Workstream D: Data and Developer-Tool Widgets

### Goal

Own dense developer-tool workflows.

### Target Widgets

- `DataTable`
- `TreeTable`
- `LogView`
- `JsonView`
- `YamlView`
- `DiffView`
- `CodeView`
- `MarkdownView`
- `FileBrowser`
- `SearchPanel`
- `TraceTimeline`
- `TaskList`
- `ProcessPanel`
- `MetricsPanel`
- `InspectorPane`

### DataTable Requirements

- Virtualized rows.
- Stable row keys.
- Sort, filter, search, and selection.
- Column resize, hide/show, and pin/freeze.
- Fixed header.
- Optional fixed left columns.
- Row details/expansion.
- Copy/export selected rows.
- Async data source.
- Loading, empty, error, and partial states.
- Keyboard and mouse parity.

### LogView Requirements

- Tail-follow with opt-out when user scrolls up.
- Search and highlight.
- Severity filtering.
- Copy range.
- Pause/resume.
- Timestamp and structured field support.
- Streaming without unbounded memory growth.

### DiffView and CodeView Requirements

- Syntax highlighting hooks.
- Line numbers.
- Hunks.
- Inline comments/annotations.
- Search.
- Copy selection.
- Large-file virtualization.

### Acceptance Criteria

- 10k-row tables remain interactive.
- Streaming logs remain smooth under steady append.
- Searching large visible datasets feels immediate.
- Widgets compose with selection, clipboard, focus, theme, tests, and
  command palette.

## 10. Workstream E: Async Work, Processes, and Effects

### Goal

Make background work a first-class framework concept.

### Target Capabilities

- `Worker<T>`
- `WorkerController`
- `WorkerBuilder`
- Cancellable tasks.
- Restartable tasks.
- Debounced tasks.
- Stream binding.
- Progress binding.
- Retry policy.
- Error surfaces.
- Subprocess execution.
- Stdout/stderr capture.
- Exit status handling.
- Long-running process panels.
- Safe UI updates from async callbacks.

### API Sketch

```dart
final deploy = Worker<void>(
  label: 'Deploy',
  run: (context, signal) async {
    await for (final line in runProcess(['deploy'], signal: signal)) {
      context.logs.append(line);
    }
  },
);
```

### Acceptance Criteria

- Cancelling a task is safe and visible.
- Process output cannot corrupt the terminal.
- Worker state is easy to bind into widgets.
- Errors show useful stack/context and do not strand raw mode.
- Async tests can advance time and stream events deterministically.

## 11. Workstream F: Terminal Compatibility and Capability Contract

### Goal

Turn terminal weirdness into a Fleury advantage.

### Target Capabilities

- Native Windows driver.
- Active capability probing.
- `fleury diagnose`.
- Terminal compatibility matrix.
- Color mode detection and fallback.
- Clipboard fallback: platform tools, OSC 52, disabled policy.
- Image protocol detection and cleanup: Kitty, iTerm2, Sixel, Unicode.
- Keyboard protocol detection: Kitty keyboard, modifyOtherKeys, fallback.
- Mouse protocol detection.
- Bracketed paste handling.
- SSH/tmux/Zellij awareness.
- Suspend/resume.
- Crash-safe cleanup.
- Non-interactive fallback handling.

### Acceptance Criteria

- A user can run `fleury diagnose` and understand what will work.
- Apps can branch on capabilities without parsing environment variables.
- Terminal cleanup is idempotent and reliable after errors.
- CI can exercise fake-driver compatibility cases.
- Real-terminal smoke tests cover at least macOS Terminal, iTerm2, WezTerm,
  Ghostty, Alacritty, Windows Terminal, tmux, and SSH.

## 12. Workstream G: Rendering and Performance

### Goal

Make Fleury visibly fast on real workloads.

### Current Strengths

- Cell-level ANSI diffing.
- Batched sink writes.
- Buffer reuse.
- Lazy `ListView.builder`.
- Repaint boundaries with bounding-box blits.
- Same-constraint render-object layout caching with upward dirty propagation.
- Benchmark history and profiling discipline.

### Target Capabilities

- Dirty layout propagation.
- Dirty paint propagation.
- Render subtree invalidation.
- Scenario benchmark harness.
- Frame budget warnings.
- Debug panel frame timeline.
- Optional paint flashing and rebuild flashing.
- Large-table virtualization.
- Large-text virtualization.
- Efficient style runs and SGR emission.
- Resize storm coalescing.
- Animation frame policy for slow terminals.

### Scenario Benchmarks

- 200x60 live dashboard at 30 fps.
- 10k-row table scroll and search.
- 100k-line log tail with search.
- Streaming markdown chat transcript.
- Fast typing in long single-line field.
- Multiline editing with selection.
- Image repaint and cleanup.
- Resize storm.
- Modal open/close over a busy app.
- SSH latency simulation.

### Acceptance Criteria

- Benchmarks are app-shaped, not only microbenchmarks.
- Regression thresholds are defined for each scenario.
- Frame timing can be inspected in-app.
- Small state changes avoid unnecessary expensive work.
- Fleury can honestly claim top-tier perceived performance for production
  terminal apps, even if Rust immediate-mode libraries remain faster in raw
  microbenchmarks.

## 13. Workstream H: Devtools and Testing

### Goal

Make Fleury the easiest TUI framework to test, inspect, and debug.

### Current Strengths

- `FleuryTester`
- Fake terminal driver
- Golden text rendering
- Debug shell
- Frame timing events
- Paint flash support
- Output capture

### Target Capabilities

- Widget tree inspector.
- Focus tree inspector.
- Keybinding/command inspector.
- Layout bounds overlay.
- Dirty/rebuild/paint counters.
- Event log.
- Terminal capability viewer.
- Golden update tooling.
- Scenario test harness.
- Browser/devtools bridge.
- Snapshot serializer for bug reports.
- Input fuzzing for parsers and text fields.

### Acceptance Criteria

- A complex app can be tested without spawning a terminal.
- A failing layout/input/render bug can be reproduced from a serialized
  snapshot.
- Debug tools have negligible cost when disabled.
- Developers can inspect focus, commands, frame cost, and terminal
  capabilities from inside the app.

## 14. Workstream I: Styling, Theme, and Product Taste

### Goal

Make attractive terminal apps easy without copying CSS wholesale.

### Target Capabilities

- Expanded `ThemeData` tokens.
- Component themes.
- Border, surface, semantic color, status, and selection tokens.
- Built-in palettes.
- Density settings.
- Responsive breakpoints by cell size.
- Style composition helpers.
- `Style` or `CellStyle` ergonomics inspired by Lip Gloss.
- Consistent disabled, focused, hovered, selected, active, error, warning,
  success, and loading states.

### Principle

Fleury should not make CSS the main mental model. The default should remain
Flutter-style composition and theming. But styling must be expressive enough
that apps do not look like raw debug output unless they choose to.

### Acceptance Criteria

- Core widgets look coherent out of the box.
- Custom themes can be applied app-wide.
- Focus and selection states are visually consistent.
- High-contrast and reduced-animation modes are easy.

## 15. Workstream J: Agent and Developer Workflow Primitives

### Goal

Make Fleury the natural framework for the next generation of agentic and
developer-tool TUIs.

### Target Widgets and Services

- `MessageList`
- `StreamingMarkdown`
- `ToolCallCard`
- `ApprovalPrompt`
- `PatchReview`
- `TraceTimeline`
- `TokenMeter`
- `ContextPanel`
- `TaskGraph`
- `CommandRunner`
- `FileMentionPicker`
- `ModelStatusBar`
- `ConversationNavigator`

### Why This Matters

Modern terminal UIs are moving beyond simple prompts. Agent CLIs need dense
mixed media: streaming markdown, code blocks, diffs, file trees, tool calls,
approvals, logs, traces, subprocesses, and live status. Existing frameworks
can build these, but few make them first-class.

### Acceptance Criteria

- A high-quality agent console can be built mostly from framework widgets.
- Streaming markdown does not reflow or flicker excessively.
- Tool calls and approvals are keyboard-first and testable.
- Diff/code views support review workflows, not only display.

## 16. Workstream K: Agent Adapter Readiness And `fleury_acp`

### Goal

Make Fleury launch agent-adapter ready, while keeping ACP transport, protocol
models, and ACP-specific widgets out of core and scoped to a fast-follow
`fleury_acp` package.

### Target Capabilities

- Fleury core exposes protocol-neutral foundations: semantic nodes,
  structured actions, commands, effects, progress, terminal output regions,
  selection/copy, replay hooks, and capability/security policy.
- General-purpose widgets such as markdown, logs, diffs, code, progress, data
  views, command runners, and output regions live in core or `fleury_widgets`
  only when useful outside ACP.
- `fleury_acp` owns ACP transport, schema/version handling, ACP protocol
  models, ACP-specific widgets, and ACP replay fixtures.
- Fleury core never imports ACP schemas or JSON-RPC concepts.
- Dune/`dune_cli` can adopt `fleury_acp` later if ACP support is needed.

### Why This Matters

Agent UIs are where terminal applications are moving fastest, but Fleury
should not make a young protocol part of launch scope. The stronger
architecture is to launch the general foundations that make deep protocol
packages possible, then let `fleury_acp` prove that extension model.

The example subpackage should validate Fleury's core developer-tool
primitives first. Dune/`dune_cli` can later become the public flagship and
only pull in `fleury_acp` if ACP support is needed for the product.

### Acceptance Criteria

- Fleury launch requirements identify the adapter-ready primitives
  `fleury_acp` needs.
- `fleury_acp` has a clear package boundary and does not block Fleury launch.
- ACP-specific widgets are scoped to `fleury_acp`.
- Reusable non-ACP widgets remain protocol-neutral and can serve Dune,
  developer tools, and other domain packages.

## 17. Workstream L: Adoption, Distribution, and Ecosystem

### Goal

Make Fleury not only technically strong, but easy to discover, try, compare,
install, and adopt.

### Target Capabilities

- Clear positioning against Nocterm, Bubble Tea v2, Textual, OpenTUI, Ink, and
  Ratatui.
- Moving-target peer scorecards updated at regular checkpoints.
- Simple first-run path for a new developer to create and run a Fleury app.
- Distribution story for Dart packages, standalone binaries, Homebrew, and
  npm wrappers when the framework is ready for external users.
- Showcase shelf led first by the example subpackage, then Dune/`dune_cli`,
  then third-party apps.
- Contributor process, issue labels, RFC flow, and onboarding docs once APIs
  are ready for outside contribution.

### Why This Matters

A framework becomes leading when developers choose it. Fleury needs visible
reasons to be chosen, not only strong internals. The first reasons should be
concrete: a serious example app, Dune as the later flagship,
agent-adapter readiness, semantic testing, capability-aware widgets,
selection, and scenario benchmarks.

### Acceptance Criteria

- A "Why Fleury?" page can name three concrete wins against Nocterm and three
  concrete wins against Bubble Tea v2.
- A peer scorecard compares Fleury against current versions of Nocterm,
  Bubble Tea v2, Textual, OpenTUI, and Ratatui.
- A developer can create and run a counter app quickly once distribution work
  begins.
- The example subpackage is maintained as the first showcase-quality demo app,
  with Dune/`dune_cli` promoted later when the core is proven.

### Active Execution Artifacts

The implementation tracker owns the operational details for this workstream:

- [Execution journal](implementation/execution-journal.md) records the
  chronological implementation memory: changes, findings, validation, and next
  steps.
- [Demo-app scenario](implementation/demo-app-scenario.md) defines the
  current-cycle example subpackage and the Phase 1 proof slice.
- [Scenario benchmark lab](implementation/scenario-benchmark-lab.md) defines
  app-shaped workloads, target metrics, fixtures, peer comparison targets, and
  candidate thresholds.
- [Prototype-first tracks](implementation/prototype-first-tracks.md) defines
  narrow prototype scenarios for progressive modes, debug capture/future
  replay, effects/workers, and subprocess handoff.
- [Agent adapter boundary](implementation/agent-adapter-boundary.md) defines
  launch adapter-readiness requirements and the fast-follow `fleury_acp`
  package boundary.
- [RFC 0011: Semantic app graph](rfcs/0011-semantic-app-graph.md) defines the
  first architecture gate for semantic testing, inspection, and future
  automation.
- [RFC 0012: App kernel](rfcs/0012-app-kernel.md) defines `FleuryApp`, screens,
  commands, shortcut scopes, status, lifecycle, and command palette integration.
- [RFC 0013: Capability and security contract](rfcs/0013-capability-security-contract.md)
  defines capability requirements, fallback policy, JSON diagnostics, and
  safe defaults for untrusted terminal output.
- [Peer scorecards](implementation/peer-scorecards.md) track the moving target
  across Nocterm, Bubble Tea v2, Textual, OpenTUI, Ratatui, and Ink.
- [Scope cut list](implementation/cut-list.md) defines what to drop first for
  1-2 engineer, 3-4 engineer, and 5+ engineer realities.
- [`fleury_acp` fast-follow package](implementation/workstreams/fleury-acp-fast-follow.md)
  tracks ACP-specific package boundaries and fast-follow work.
- [Adoption, distribution, and ecosystem](implementation/workstreams/adoption-distribution-ecosystem.md)
  tracks installation, public positioning, showcase, and contributor work.

## 18. Roadmap Phases

### Phase 0: Architecture Guardrails And Scenario Lab

Objective: decide the contracts that would be expensive to retrofit after
large widget and app-shell work, without turning Phase 0 into months of RFC
writing.

Deliverables:

1. Example subpackage demo-app scenario spec.
   - Define the first realistic workflow that will prove Fleury: sidebar
     navigation, streamed content, composer/input, commands, status, data
     views, output/log regions, selection, capability fallbacks, and debug
     capture hooks.
   - Use this scenario as the forcing function for the Phase 0 RFCs and Phase 1
     implementation slice.

2. Semantic app graph RFC.
   - Roles, labels, values, commands, focus, selection, tables, dialogs,
     validation, progress, errors, routes, and capability requirements.

3. App kernel RFC.
   - Define `FleuryApp`, screens, command registry, actions, shortcut scopes,
     status binding, command palette structure, and app lifecycle.

4. Capability and security contract RFC.
   - Components declare required, preferred, and optional capabilities plus
     fallback behavior.
   - Define first-pass policy for raw ANSI, OSC 52 clipboard, OSC 8 links,
     image output, subprocess output, markdown, and secret redaction.

5. Scenario benchmark lab.
   - Time-to-counter app, text editing composer stress, 100k-row table,
     streaming log, streaming markdown, dashboard updates, resize storm,
     overlay churn, subprocess handoff, and demo-app journey.
   - Include moving-target peer comparisons against current Nocterm,
     Bubble Tea v2, Textual, OpenTUI, Ratatui, and Ink where feasible.

6. Prototype-first tracks for progressive modes, replay, and workflow effects.
   - Do not freeze these as RFCs until the example subpackage and Phase 1
     prototypes reveal the surviving shape.

7. Agent adapter and `fleury_acp` package boundary.
   - Define what Fleury launch must expose for a fast-follow ACP package:
     semantic actions, effects, progress, output regions, debug/replay hook
     points, capability/security policy, and reusable non-protocol widgets.

Exit criteria:

- The core contracts are small enough to implement, but rich enough that
  semantic testing, prompt fallback, debug/replay hooks, and capability-aware
  widgets can share them.
- The example subpackage has a concrete Phase 1 demo-app scenario.
- Phase 0 has not expanded beyond the three architecture RFCs: semantic app
  graph, app kernel, and capability/security contract.

### Phase 1: Clear-Choice Foundations

Objective: close the gaps that would block a serious developer from choosing
Fleury over Nocterm, Textual, Bubble Tea, or Ink for a new app.

Deliverables:

1. Semantic tree v0 in core, tester, and inspector.
2. Text editing v2.
3. `FleuryApp` shell with commands, shortcuts, command palette, and status
   binding.
4. Example subpackage demo app v0 running on Fleury.
5. Agent-adapter readiness boundary for fast-follow packages such as
   `fleury_acp`; no ACP transport or ACP-specific widgets in launch scope.
6. Worker/task model with structured status, cancellation, output, and future
   replay hook points.
7. Terminal diagnose and capability model.
8. Scenario benchmark harness with peer baseline snapshots.
9. DataTable v1 with virtualization, sorting, selection, search, fixed
   headers, copy, and semantic cells.
10. Debug inspector additions for focus, commands, semantics, dirty regions,
   effects, and frame timing.
11. Sanitized output pipeline for untrusted subprocess/log/markdown content.
12. Initial distribution path for trying Fleury examples locally.

Exit criteria:

- A developer can build a dense, keyboard-first app with strong text input,
  commands, workers, data tables, terminal diagnostics, semantic tests, and
  visible performance metrics.
- The example subpackage demonstrates Fleury's strongest early differentiators:
  semantic testing, selection, adapter-ready workflow primitives, command
  structure, capability diagnostics, and rich developer-tool surfaces.
- Fleury has a written comparison against current Nocterm and Bubble Tea v2
  that names concrete wins and gaps.

### Phase 2: Production App Toolkit

Objective: make Fleury the fastest route to dense production terminal apps.

Deliverables:

1. Forms framework with shared full-screen, inline, and prompt-mode rendering.
2. LogView, JsonView, DiffView, CodeView, MarkdownView.
3. TreeTable, FileBrowser, and SearchPanel.
4. ProcessPanel, CommandRunner, and terminal output regions.
5. Theme/component theme expansion.
6. Dune/`dune_cli` first integration slice after the core framework is proven.
7. Optional `fleury_acp` fast-follow package if Dune/`dune_cli` later needs
   ACP integration.
8. Accessibility and fallback model built from semantic nodes.
9. Windows driver.
10. Active capability probes and real-terminal compatibility tests across
   macOS Terminal, iTerm2, Kitty, Ghostty, Alacritty, WezTerm, Windows
   Terminal, SSH, and tmux.
11. Targeted debug-capture and replay-hook prototype if example or
    Dune/`dune_cli` testing exposes bugs that require it.
12. Public-facing adoption assets once the product and APIs are credible:
    package docs, "Why Fleury?", peer comparisons, showcase, and distribution
    docs.

Exit criteria:

- Fleury can support production developer tools with forms, logs, files,
  diffs, code, markdown, process orchestration, real-terminal diagnostics, and
  replayable bugs.

### Phase 3: Ecosystem Leadership

Objective: move beyond parity with peers and define the next generation of
terminal app development.

Deliverables:

1. Agent workflow widget suite v2.
2. Dune/`dune_cli` as a maintained flagship showcase.
3. Terminal devtools protocol and browser/devtools bridge.
4. Snapshot/replay debugging with shareable artifacts.
5. Remote app/session story.
6. Stable semantic inspection protocol for automation and AI agents.
7. Optional high-performance engine boundary for render/data hot paths.
8. Plugin/extension story for widgets, commands, themes, data sources, and
   workflow integrations.
9. Cross-framework comparative benchmarks and showcase apps.

Exit criteria:

- Fleury is not just easier than peer frameworks. It enables terminal apps
  that are easier to test, inspect, replay, operate remotely, adapt to
  terminal capabilities, and integrate with agent/developer workflows.

## 19. Immediate Next Implementation Sequence

1. Write RFC: semantic app graph.
   - Define roles, labels, values, focus, commands, selection, validation,
     table regions, dialog regions, progress, errors, routes, and capability
     requirements.

2. Write RFC: `FleuryApp`, commands, actions, and shortcuts.
   - Define app shell, screens, command registry, shortcut scopes, status
     binding, command palette structure, lifecycle, and demo-app needs.

3. Write RFC: capability and security contract.
   - Define required/preferred/optional capabilities, terminal profiles,
     fallback behavior, ANSI sanitizer, OSC policy, image policy, link policy,
     markdown policy, subprocess output policy, and secret redaction.

4. Write example subpackage demo-app scenario spec.
   - Use the example app as the forcing function for sidebar navigation,
     streamed content, composer/input, commands, data views, output/log
     regions, selection, capability fallbacks, and debug capture.

5. Add moving-target peer scorecard.
   - Compare against current Nocterm, Bubble Tea v2, Textual, OpenTUI, and
     Ratatui; record versions, claims, gaps, and benchmark targets.

6. Add scenario benchmark harness.
   - Include text editing, table scrolling, log tailing, streaming markdown,
     dashboard updates, resize storms, overlay churn, subprocess handoff, and
     streaming content/logs.

7. Implement semantic tree v0.
   - Start with Button, Text, TextInput, TextArea, Table, Dialog, Navigator,
     Progress, and Command.
   - Expose semantic queries in `FleuryTester`.
   - Add inspector output for semantic nodes.

8. Write RFC: text editing v2.
   - Define `TextEditingValue`, selection, grapheme indexing, keymaps,
     clipboard, undo, completion, paste policy, password policy, and field
     APIs.

9. Implement pure text model and tests.
   - Cover graphemes, emoji, CJK, combining marks, wide characters, selection,
     word movement, undo, paste, history, and multiline behavior before
     touching widgets.

10. Replace `TextInput` internals with `EditableText`.
   - Preserve public API where possible, add richer APIs behind it.

11. Implement command registry and app shell.
   - Wire key hint/status bar into active command scope.

12. Define `fleury_acp` fast-follow package boundary.
   - Keep ACP transport, schemas, protocol models, and ACP-specific widgets
     out of Fleury launch while ensuring core primitives can support the
     package later.

13. Build `DataTable` v1 as a semantic render island.
   - Virtualized rows, stable keys, selection, sort, filter/search, fixed
     header, copy, semantic rows/cells, and benchmark coverage.

14. Add `Worker`, process, and effect-log primitives.
   - Include cancellation, progress, captured output, permissions, subprocess
     handoff, and future replay hook points.

15. Build `fleury diagnose`.
   - Make terminal capabilities visible, machine-readable, and testable.

16. Build the example subpackage demo app v0.
   - Use it as the real forcing function for streamed content, data views,
     logs, commands, cancellation, semantics, diagnostics, and selection.

17. Add debug/replay hook points, not full replay.
   - Capture enough input, resize, fake time, worker status, terminal profile,
     and semantic snapshots to support future replay without promising
     shareable replay artifacts at launch.

## 20. Definition of "Leading"

Fleury should be considered leading when the following are true:

- It is faster and easier to build a complex full-screen terminal app in
  Fleury than in Textual, Bubble Tea, Ink, or Nocterm for a developer who is
  comfortable with reactive UI.
- Text input and forms are trusted enough for production tools.
- Data-heavy widgets handle real datasets without bespoke app code.
- Async tasks and subprocesses are natural to bind into UI.
- Terminal behavior is predictable across common terminals.
- Tests can cover most UI behavior without a real terminal.
- Debugging a Fleury app is easier than debugging equivalent apps in peer
  frameworks.
- Performance claims are backed by scenario benchmarks.
- Semantic tests, debug capture hooks, and capability diagnostics make complex
  bugs inspectable instead of anecdotal; full replay can mature after launch.
- A meaningful subset of apps can degrade from full-screen UI to inline or
  prompt-mode interaction without being rewritten.
- Agent/developer workflows are first-class: tool calls, approvals, diffs,
  logs, plans, permissions, and cancellation have framework-level primitives.
- Components declare capability requirements and security policies, so
  advanced terminal features fail predictably.
- The example subpackage proves Fleury's launch scope under realistic app
  pressure, and Dune/`dune_cli` later demonstrates it under product pressure.
- Agent-adapter readiness is a visible launch differentiator, while ACP
  support ships separately through a fast-follow `fleury_acp` package if a
  later product needs it.
- Published scorecards compare Fleury against current Nocterm, Bubble Tea v2,
  Textual, OpenTUI, and Ratatui on capability, ergonomics, and scenario
  performance.
- The framework feels cohesive: widgets, commands, focus, navigation, theme,
  async, terminal capabilities, and testing all fit together.

## 21. Non-Goals for the Next Phase

Avoid these until the core is stronger:

- Chasing every widget category before text/input/app shell/data foundations
  are excellent.
- Recreating Flutter source compatibility.
- Making CSS the primary styling model.
- Optimizing microbenchmarks that do not affect scenario performance.
- Adding plugins before extension points are proven inside first-party
  widgets.
- Marketing/release work as a substitute for product superiority.
- Splitting the seven engines into separate packages before implementation
  proves the boundaries.
- Promising native terminal screen-reader behavior beyond what current
  terminals can reliably support.

## 22. Assumptions To Challenge

The roadmap above is intentionally ambitious, but it still inherits many
assumptions from current TUI frameworks. If Fleury is meant to move the
category forward, these assumptions need to be challenged directly.

### Assumption: Flutter-style reactive UI is the final model

Flutter-style retained UI is the right starting point for Fleury because it
gives developers local state, composition, context, layout, testing, and a
familiar mental model.

But the best next-generation TUI may need more than widgets:

- A semantic command graph.
- A semantic data model for tables, logs, diffs, and forms.
- A replayable event/effect model.
- A protocol-level representation that can drive terminal, browser, remote,
  test, and accessibility surfaces.
- Hybrid retained/immediate regions for extremely hot surfaces.

Challenge:

> Fleury should not stop at "Flutter for the terminal." It should become a
> workflow framework that happens to have a Flutter-style UI layer.

### Assumption: The terminal screen is the product

Most frameworks optimize for drawing cells. That is necessary, but
increasingly insufficient. Modern terminal apps also need:

- Inspectability.
- Replayability.
- Automation.
- Remote operation.
- Browser mirrors.
- Accessibility summaries.
- Structured state export.
- Collaboration and handoff.

Challenge:

> Fleury should treat the cell buffer as one projection of an application,
> not the whole application.

This implies a durable semantic layer above rendered cells. A button should
not only paint text and borders; it should have identity, role, enabled state,
command binding, focus behavior, tooltip/help, test selector, and possibly
accessibility text. A table should expose rows, columns, sort state, filters,
selection, and viewport. A tool-call card should expose status, command,
stdout/stderr, approval state, and retry/cancel actions.

### Assumption: Full-screen TUI and CLI prompts are separate categories

Today, prompt libraries, full-screen app frameworks, and command output
renderers are often separate stacks. That division is a historical artifact,
not a user need.

Challenge:

> Fleury should support a progressive interaction continuum:
> one prompt, multi-step wizard, inline rich command output, embedded panel,
> full-screen app, remote/browser mirror, and recorded replay should share
> primitives.

This could become a major differentiator. A deployment flow could start as
plain prompts in CI, become an inline status UI in a local terminal, and open
as a full-screen operations console when needed.

### Assumption: Terminal compatibility is a runtime detail

Most frameworks expose terminal quirks as incidental bugs: colors wrong here,
mouse broken there, images not cleaning up elsewhere.

Challenge:

> Fleury should make terminal compatibility a product surface.

Capability negotiation, diagnostics, fallback policy, and per-terminal
behavior should be explicit and testable. Apps should be able to say:

- "This view requires keyboard disambiguation."
- "This image can degrade to half-blocks."
- "This workflow can run in prompt fallback mode."
- "This clipboard action requires confirmation over SSH."
- "This terminal cannot safely display this feature."

### Assumption: Performance means lower-level rendering

Ratatui and lower-level libraries will likely keep winning raw microbenchmarks.
That does not mean Fleury cannot win perceived performance for complex apps.

Challenge:

> Fleury should optimize for end-to-end interaction latency, not only render
> speed.

Perceived speed includes:

- Input-to-paint latency.
- Stable layout under streaming updates.
- No flicker.
- No unnecessary scroll jumps.
- Fast search/filter.
- Responsive cancellation.
- Smooth resize.
- Bounded memory under long-running streams.
- Predictable performance under SSH/tmux.

This argues for scenario benchmarks and UI workload budgets, not only render
microbenchmarks.

### Assumption: Widgets are the main distribution unit

Widgets matter, but production apps need reusable workflows:

- "Pick a file."
- "Approve this patch."
- "Inspect this JSON response."
- "Tail this process."
- "Review this diff."
- "Configure this service."
- "Run this task graph."

Challenge:

> Fleury should ship workflow primitives, not only visual widgets.

The strongest libraries in the next wave may be not just `Button`, `Table`,
and `TextInput`, but `ApprovalFlow`, `CommandRunner`, `PatchReview`,
`TraceExplorer`, `DeployWizard`, and `AgentConsole`.

### Assumption: Accessibility is impossible or irrelevant in terminals

Terminals are hard for accessibility, but ignoring the issue will keep TUIs
second-class.

Challenge:

> Fleury should define an accessibility and fallback story for terminal apps,
> even if the first version is pragmatic.

Possible first-class concepts:

- Semantic roles and labels.
- Text summaries of complex widgets.
- Plain prompt fallback mode.
- Copy/export of visible semantic state.
- Screen-reader-friendly non-alt-screen mode.
- High contrast and reduced motion.
- Keyboard-only as the default interaction model.

### Assumption: AI/agent workflows are just another app category

Agent UIs are a stress test for TUI frameworks: streaming text, markdown,
code, diffs, approvals, logs, tool calls, cancellations, background tasks,
filesystem references, and live errors all mixed together.

Challenge:

> Fleury should treat agent workflows as a proving ground for the framework's
> core abstractions.

If Fleury can make a high-quality agent console easy, it will likely be good
for many other developer tools too.

## 23. Under-Researched Areas

These areas need more investigation before locking long-term architecture.

### Accessibility and semantic terminal UI

Open questions:

- What can terminal apps realistically expose to screen readers today?
- How do alt-screen apps behave with common assistive technologies?
- What conventions do accessible CLI tools use for fallback?
- Can Fleury maintain a semantic tree that powers tests, screen summaries,
  automation, and plain-mode fallback?

Recommended research:

- Screen-reader behavior with common terminals.
- Accessibility practices in CLI/prompt tools.
- Browser accessibility analogs for Fleury's web/remote surface.
- How Textual, Ink, and prompt libraries handle labels, roles, and fallback.

### Terminal capability negotiation beyond environment variables

Open questions:

- Which probes are safe, fast, and reliable across terminals?
- How should Fleury avoid hangs or bad responses from broken terminals?
- How should apps declare capability requirements?
- Can diagnostics produce stable bug-report artifacts?

Recommended research:

- Kitty keyboard and graphics protocols.
- Sixel/iTerm2 image behavior and cleanup.
- OSC 52 clipboard policies in local, SSH, tmux, and Zellij sessions.
- Cursor position / pixel-size / cell-size reports.
- Terminal behavior under multiplexers and remote sessions.

### Hybrid retained/immediate rendering

Open questions:

- Should huge tables/logs/code views be retained widgets, immediate render
  islands, or something in between?
- Can a retained widget tree delegate a hot region to a specialized renderer
  without breaking hit testing, selection, tests, or accessibility?
- What API should custom high-performance surfaces implement?

Recommended research:

- Ratatui's widget/state patterns.
- Textual's data table and virtualized widgets.
- Editor renderers for large text buffers.
- Browser virtual scrolling and retained/immediate hybrid systems.

### Text editing engine depth

Open questions:

- How far should Fleury go toward editor-grade behavior?
- Should keymaps be pluggable at the editing-engine level?
- How should completions, suggestions, snippets, masks, validation, and
  history compose?
- What is the right representation for grapheme-indexed text ranges?

Recommended research:

- prompt_toolkit internals.
- Readline/editline behavior.
- Editor keymaps: Emacs, Vi, VS Code-like shortcuts.
- Unicode segmentation and terminal display width edge cases.

### Collaboration, remote sessions, and replay

Open questions:

- Should Fleury apps be remotely viewable/controlable by design?
- Can a session be recorded and replayed deterministically?
- Can a failure report include enough semantic state to reproduce a bug?
- What is the line between a terminal UI and a lightweight app protocol?

Recommended research:

- Terminal session recorders.
- Browser mirrors for terminal apps.
- CRDT/collaborative console tools.
- Snapshot testing and deterministic event logs.

### Security and untrusted output

Open questions:

- How should Fleury handle untrusted logs, subprocess output, markdown,
  ANSI escape sequences, OSC links, images, and clipboard writes?
- How should secrets be redacted in logs, replay files, crash reports, and
  debug panels?
- What are safe defaults for command runners and agent tool calls?

Recommended research:

- ANSI injection vulnerabilities.
- OSC 8 links and OSC 52 clipboard risks.
- Terminal escape sanitization.
- Secret redaction patterns in developer tools.

### Distribution and startup latency

Open questions:

- How important is single-binary distribution?
- How fast must startup be for prompt-like use cases?
- Does Dart AOT provide an acceptable deployment story across platforms?
- What packaging conventions make terminal apps feel native?

Recommended research:

- Dart AOT startup and binary size.
- Packaging for Homebrew, Scoop, apt, npm wrappers, and standalone binaries.
- How Go/Rust/Python/Node TUI tools are distributed in practice.

## 24. Category-Expanding Bets

These are not required for initial parity, but they are the ideas most likely
to push Fleury beyond today's TUI category.

### Bet 1: Semantic UI Tree

Every meaningful widget should expose semantic state in addition to painted
cells:

- Role.
- Label.
- Value.
- Enabled/disabled state.
- Focus state.
- Selection state.
- Commands/actions.
- Test identity.
- Accessibility summary.
- Copy/export behavior.

Uses:

- Better tests.
- Accessibility.
- Automation.
- Debug inspector.
- Remote/browser mirrors.
- Snapshot/replay.
- AI agents controlling or inspecting TUIs.

This could become Fleury's equivalent of Flutter's semantics tree, adapted to
terminal workflows.

### Bet 2: Progressive UI Modes

A Fleury component should be able to render in multiple modes:

- Prompt mode.
- Inline command-output mode.
- Full-screen TUI mode.
- Browser/xterm mode.
- Recording/replay mode.
- Test mode.
- Accessibility/plain-text summary mode.

This would erase the hard boundary between prompt libraries and TUI
frameworks.

### Bet 3: Replayable Runtime

Fleury should eventually be able to record:

- Terminal capabilities.
- Initial app state hooks.
- Input events.
- Resize events.
- Timer ticks.
- Worker/process events.
- Frame timing.
- Semantic snapshots.

Then replay a session deterministically in tests or a debug viewer. This would
be unusually powerful for TUI debugging.

### Bet 4: First-Class Workflow Graphs

Many developer tools are not just screens; they are workflows with tasks,
dependencies, logs, approvals, retries, and cancellations.

Fleury could provide a workflow graph model that powers:

- Deploy flows.
- CI/task runners.
- Agent tool execution.
- Database migrations.
- Multi-step setup/configuration.
- Batch jobs.

The UI would be a projection of a typed workflow state machine.

### Bet 5: Agent-Native Surfaces

Instead of treating agent UIs as examples, make them first-class:

- Streaming message list.
- Markdown/code streaming with stable layout.
- Tool-call cards.
- Approval prompts.
- Patch review.
- File mentions.
- Context/token meters.
- Trace timelines.
- Background task graph.
- Model/session status.

If this is done well, Fleury becomes highly relevant to where terminal UI
development is heading.

### Bet 6: Capability-Aware Components

Components should be able to declare and negotiate capability needs:

```dart
Image(
  source: file,
  preferredProtocols: [ImageProtocol.kitty, ImageProtocol.sixel],
  fallback: ImageFallback.halfBlock,
)
```

More broadly:

- Rich mode when capabilities exist.
- Degraded mode when they do not.
- Prompt/plain mode in CI or inaccessible environments.
- Diagnostics explaining the chosen mode.

This turns terminal inconsistency into an explicit design axis.

### Bet 7: Hybrid Performance Islands

For extremely hot surfaces, expose a controlled way to build render islands
that bypass general widget overhead while preserving integration:

- Hit testing.
- Focus.
- Selection.
- Semantics.
- Testing.
- Theming.
- Commands.

Candidate widgets:

- DataTable.
- LogView.
- CodeView.
- DiffView.
- Canvas.
- StreamingMarkdown.

This gives Fleury a path to Ratatui-class performance where it matters
without abandoning retained reactive app structure.

### Bet 8: Structured Effects

Side effects should be observable, cancellable, and testable:

- Processes.
- Network calls.
- Timers.
- File watchers.
- Agent tool calls.
- Clipboard writes.
- Notifications.
- Terminal probes.

Instead of each widget/app inventing effect lifecycles, Fleury can provide a
structured effect runtime that integrates with workers, debug panels, replay,
and teardown.

### Bet 9: Terminal DevTools Protocol

Fleury could define a local protocol for inspecting and controlling a running
TUI:

- Widget tree.
- Semantic tree.
- Focus tree.
- Command registry.
- Active workers.
- Frame timeline.
- Logs.
- Terminal capabilities.
- Snapshot capture.
- Replay export.

This could power in-terminal panels, browser devtools, and automated bug
reports.

### Bet 10: AI-Inspectable Apps

If Fleury has a semantic tree, command registry, and replayable state,
AI agents could interact with Fleury apps through structured actions rather
than brittle screen scraping.

This is no longer only speculative. Agent tools already need structured
session state, permissions, diffs, tool calls, and progress. Fleury can make
that structure available through the framework instead of forcing apps and
agents to rediscover it through screen scraping.

## 25. Updated Immediate Research Spikes

These are no longer optional curiosity spikes. They are Phase 0 de-risking
work that should happen before broad widget expansion, because each one could
change the shape of core APIs.

1. **Semantic tree spike**
   - Add semantic metadata to a small set of widgets: Button, TextField,
     Table, Dialog.
   - Expose it in `FleuryTester`.
   - Verify it helps tests and debug inspection.

2. **Text engine spike**
   - Build pure grapheme-indexed edit model with selection, undo, word
     movement, and CJK/emoji tests.
   - Do not start with rendering.

3. **Progressive form spike**
   - One form definition rendered both as full-screen widgets and sequential
     prompt mode.
   - Validate whether prompt/full-screen sharing is realistic.

4. **Replay spike**
   - Record input, resize, fake time, worker events, and golden frames for a
     small app.
   - Replay deterministically in a test.

5. **Capability negotiation spike**
   - Implement safe probing for a small capability set.
   - Produce `fleury diagnose --json`.
   - Test in fake driver and at least two real terminals.

6. **Hybrid render island spike**
   - Prototype a virtualized table/log render object with semantics and hit
     testing.
   - Compare against normal widget composition.

7. **Agent console spike**
   - Build a realistic streaming agent transcript with markdown, code blocks,
     tool calls, approvals, and patch diff.
   - Use it to pressure-test layout stability, scrolling, selection,
     cancellation, security policy, semantics, and performance.

8. **Security and untrusted output spike**
   - Feed subprocess output containing raw ANSI, OSC 52 clipboard sequences,
     OSC 8 links, huge lines, malformed UTF-8, markdown links, image escapes,
     and secret-shaped content through the render pipeline.
   - Define what is allowed by default, what requires opt-in, what is
     stripped, what is escaped, and what is redacted.

9. **IME and composition spike**
   - Determine what Fleury can support today for CJK input and composition
     across common terminals.
   - At minimum, design the text engine so composition state can be added
     without replacing the editing model.

## Research Signals Used In This Update

This roadmap update is grounded in framework documentation plus issue-tracker
signals where the same categories of pain repeat across ecosystems.

### Official Docs And Readmes

- Ratatui: <https://ratatui.rs/> and widget list in
  <https://github.com/ratatui/ratatui/tree/main/ratatui-widgets>
- Textual: <https://textual.textualize.io/> and
  <https://github.com/Textualize/textual>
- Bubble Tea: <https://github.com/charmbracelet/bubbletea>
- Bubbles: <https://github.com/charmbracelet/bubbles>
- Huh: <https://github.com/charmbracelet/huh>
- Lip Gloss: <https://github.com/charmbracelet/lipgloss>
- Ink: <https://github.com/vadimdemedes/ink>
- prompt_toolkit: <https://github.com/prompt-toolkit/python-prompt-toolkit>
- Notcurses: <https://github.com/dankamongmen/notcurses>
- OpenTUI: <https://opentui.com/docs/getting-started> and
  <https://github.com/anomalyco/opentui>
- Terminal.Gui: <https://github.com/gui-cs/Terminal.Gui>
- tview: <https://github.com/rivo/tview>
- tcell: <https://github.com/gdamore/tcell>
- gocui: <https://github.com/jroimartin/gocui>
- Agent Client Protocol: <https://agentclientprotocol.com/>
- OpenAI Codex CLI: <https://github.com/openai/codex>
- Gemini CLI: <https://github.com/google-gemini/gemini-cli>
- Charm Crush: <https://github.com/charmbracelet/crush>
- OpenCode: <https://github.com/anomalyco/opencode>

### Issue Signal Themes

- Accessibility remains unresolved even in strong frameworks:
  Textual issue <https://github.com/Textualize/textual/issues/2425>,
  Bubble Tea issue <https://github.com/charmbracelet/bubbletea/issues/780>,
  Huh issue <https://github.com/charmbracelet/huh/issues/611>, and OpenTUI
  issue <https://github.com/anomalyco/opentui/issues/423>.
- Unicode, width, graphemes, and IME are recurring correctness risks:
  Textual issue <https://github.com/Textualize/textual/issues/5243>,
  Ratatui issue <https://github.com/ratatui/ratatui/issues/1745>, and OpenTUI
  issues <https://github.com/anomalyco/opentui/issues/942> and
  <https://github.com/anomalyco/opentui/issues/1113>.
- Inline/full-screen boundaries, scrollback, output handoff, and terminal
  lifecycle are visible user pain: Bubble Tea issues
  <https://github.com/charmbracelet/bubbletea/issues/162>,
  <https://github.com/charmbracelet/bubbletea/issues/616>,
  <https://github.com/charmbracelet/bubbletea/issues/1275>, and
  <https://github.com/charmbracelet/bubbletea/issues/1571>; Ink issue
  <https://github.com/vadimdemedes/ink/issues/935>.
- Data-heavy widgets are differentiators but also failure points:
  Textual DataTable issues such as
  <https://github.com/Textualize/textual/issues/1884>,
  <https://github.com/Textualize/textual/issues/5273>, and
  <https://github.com/Textualize/textual/issues/6426>; Ratatui issue
  <https://github.com/ratatui/ratatui/issues/1004>.
- Debugging, shutdown cleanup, resize handling, and advanced protocol support
  are hard even in native-core frameworks: OpenTUI issues
  <https://github.com/anomalyco/opentui/issues/777>,
  <https://github.com/anomalyco/opentui/issues/904>,
  <https://github.com/anomalyco/opentui/issues/1038>, and
  <https://github.com/anomalyco/opentui/issues/1112>.
- Agent UIs increasingly have protocol-shaped objects rather than plain text:
  Agent Client Protocol prompt-turn and tool-call docs at
  <https://agentclientprotocol.com/protocol/prompt-turn> and
  <https://agentclientprotocol.com/protocol/tool-calls>.

## 26. Open Design Decisions

- Should the command/action model use Flutter terminology (`Intent`,
  `Action`, `Shortcuts`) or simpler TUI terminology (`Command`,
  `CommandRegistry`, `ShortcutMap`)?
- Should Fleury include a first-party state package, or rely on `Inherited`
  primitives plus adapters for Riverpod/provider-like libraries?
- How much style expressiveness should live in `CellStyle` vs component
  themes?
- Should forms live in core or `fleury_widgets`?
- Should agent workflow widgets be a separate package?
- What is the minimum Windows support needed before calling the terminal
  compatibility story complete?
- How should prompt-mode fallback compose with full-screen widgets?
- Which semantic node fields must be stable public API at launch, and which
  can remain internal while the model matures?
- How much of replay must be in Phase 1 versus deferred to Phase 2 devtools?
- What is the boundary between a widget, a workflow primitive, and an app
  service?
- Should high-performance render islands be public API or reserved for
  first-party widgets?
- Can Fleury define a stable app inspection protocol without overcommitting
  too early?
- How should capability requirements interact with theming and graceful
  degradation when advanced colors, images, mouse, clipboard, or keyboard
  protocols are unavailable?
- Which policy escape hatches should trusted local apps receive without
  weakening strict defaults for untrusted output?

## 27. Guiding Implementation Standard

For every new primitive, answer these questions before implementation:

1. What peer framework strength are we absorbing?
2. What developer-visible gap does this close?
3. How does it compose with focus, commands, theme, selection, clipboard,
   testing, and terminal capabilities?
4. What scenario benchmark or golden test proves it works?
5. What is the smallest API that can survive long-term?
6. What behavior must be terminal-native rather than Flutter-like?
7. Does this help Fleury become category-leading, or only peer-complete?
8. Does this preserve room for semantic inspection, replay, accessibility,
   and progressive prompt/full-screen modes?
9. What semantic nodes, actions, values, errors, and capability requirements
   does it expose?
10. What happens when the terminal lacks the ideal capabilities?
11. What is the security policy for untrusted text, links, clipboard writes,
   images, subprocess output, and secrets?
12. Can an agent or automated test operate it through structured actions
   rather than screen scraping?

If a feature does not improve production app development, terminal
robustness, or measurable developer ergonomics, defer it.
