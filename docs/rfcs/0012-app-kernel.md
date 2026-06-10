# RFC 0012: App Kernel

**Status:** Accepted with 2026-06-08 amendment
**Date:** 2026-05-31  
**Decision point for:** M1.3 `FleuryApp` shell, command registry, action
dispatch, status binding, command palette integration, and demo-app
implementation.

**Amendment, 2026-06-08:** The original registered-screen design was removed
from core after the DX review. `FleuryApp` remains the app-services shell for
commands, status, extensions, and app semantics. Tabs, sidebars, top-level
sections, and their controllers are ordinary app/widget state; they can expose
`SemanticRole.screen` nodes and register navigation commands, but Fleury no
longer provides `FleuryScreen`, `ScreenController`, or `ActiveScreenView`.

## 1. Summary

Fleury already has solid widget-level primitives: `Navigator`, `KeyBindings`,
`InputDispatcher`, focus scopes, overlays, `KeyHintBar`, `TuiBinding`, and a
widget-catalog `CommandPalette`. What is missing is the application layer that
turns those pieces into a coherent framework for building real apps.

This RFC proposes the **Fleury app kernel**: a small app-shell contract centered
on:

- `FleuryApp`
- command/action registry
- command scopes and shortcuts
- status model
- lifecycle hooks
- semantic contributions for commands, app-owned screen nodes, status, and
  active actions

The kernel should be small enough to implement in Phase 1, but strong enough
that the demo-app scenario can stop hand-wiring global shortcuts, command
palette entries, active screen state, and status display in every widget.

## 2. Motivation

The demo app in
[../implementation/demo-app-scenario.md](../implementation/demo-app-scenario.md)
needs app-scale structure:

- A sidebar that switches between Overview, Runs, Transcript, Logs, and
  Diagnostics.
- A command palette with commands like `Go to Runs`, `Start Fake Task`,
  `Cancel Active Task`, `Copy Selection`, `Run Terminal Diagnose`, and
  `Capture Debug Snapshot`.
- Keyboard shortcuts that are discoverable and scope-aware.
- A status area that reflects active task, diagnostics, screen, and capability
  fallback state.
- Semantic graph nodes for screens, commands, active actions, and status.
- Tests that can invoke commands directly instead of simulating every keystroke.

Today, `packages/fleury/example/chat_demo.dart` proves the primitives work, but
it also shows the gap: screen state, command palette entries, global bindings,
help text, focus behavior, and status are app-local conventions. Fleury needs a
canonical path.

## 3. Peer Lessons

- **Textual** makes app/screen actions and the command palette first-class.
  Commands can be contributed by the app, screens, or providers, and the
  command palette searches title/help metadata.
- **OpenTUI Keymap** treats named commands as stable app actions. Bindings point
  at named commands, command metadata powers query/palette behavior, and active
  layers depend on focus/mode/runtime state.
- **Flutter** separates keyboard activators from intents/actions. That
  separation is valuable, but the full `Shortcuts`/`Actions`/`Intent` ceremony
  is too heavy as Fleury's primary TUI path.
- **Bubble Tea** separates user events from asynchronous work through commands
  and messages. Fleury should borrow the discipline that I/O is structured and
  observable, but keep Dart/Flutter-style retained UI rather than a central
  Elm-style update loop.

The synthesis: Fleury should have named commands/actions with metadata,
scope-aware activation, direct programmatic invocation, and a discoverable
palette, while preserving the existing retained widget model.

## 4. Goals

- Provide a canonical `FleuryApp` shell for production TUIs.
- Leave screen/tab/sidebar identity in app-owned widgets instead of replacing
  `Navigator` or adding a second route system.
- Define command identity, metadata, enabled/visible state, shortcuts, and
  invocation.
- Let commands be contributed globally, by app-owned section predicates/scopes,
  and by focused subtrees.
- Let `KeyBindings` dispatch commands rather than duplicating callback logic.
- Let command palettes and key hint bars query active commands.
- Let tests invoke commands by ID.
- Expose app kernel state to the semantic app graph.
- Keep worker/process/effects details as an adjacent Phase 1 milestone, not
  packed into the first kernel.

## 5. Non-Goals

- Replacing `Navigator`.
- Creating a full state-management framework.
- Introducing ACP, provider protocols, tool-call schemas, or agent-specific
  command models.
- Creating a complete workflow engine.
- Implementing full replay.
- Replacing existing `KeyBindings`; the kernel should build on them.
- Requiring every app to use `FleuryApp`. Small examples can still call
  `runTui(const CounterApp())`.

## 6. Proposed Public Shape

Names are proposed, not final.

```dart
void main() => runTui(
  FleuryApp(
    title: 'Fleury Example Console',
    commands: [
      AppCommand(
        id: .goRuns,
        title: 'Go to Runs',
        shortcuts: const [KeyChord.ctrl.r],
        run: (_) => sections.activate('runs'),
      ),
      AppCommand(
        id: .startFakeTask,
        title: 'Start Fake Task',
        description: 'Start the deterministic demo worker',
        run: (ctx) => ctx.effects.startTask('fake-task'),
      ),
    ],
    status: (ctx) => [
      StatusItem.text('Section', value: sections.activeTitle),
      StatusItem.text(ctx.tasks.activeSummary),
      StatusItem.warning(ctx.capabilities.activeFallbackSummary),
    ],
    child: ExampleConsoleShell(sections: sections),
  ),
);
```

The app kernel is a shell and registry. Layout, app sections, tabs, sidebars,
and section retention remain ordinary widgets.

## 7. Core Types

```dart
final class CommandId {
  const CommandId(this.value);
  final String value;
}
```

```dart
final class AppCommand {
  const AppCommand({
    required this.id,
    required this.title,
    required this.run,
    this.description,
    this.category,
    this.shortcuts = const [],
    this.enabled = const CommandPredicate.always(),
    this.visible = const CommandPredicate.always(),
    this.semanticAction,
  });

  final CommandId id;
  final String title;
  final String? description;
  final String? category;
  final List<KeyChord> shortcuts;
  final CommandPredicate enabled;
  final CommandPredicate visible;
  final FutureOr<void> Function(CommandContext context) run;
  final SemanticAction? semanticAction;
}
```

`CommandPredicate` should be synchronous for v0. If enabled state requires async
work, the app should update ordinary state and rebuild.

```dart
abstract interface class CommandContext {
  FleuryAppController get app;
  NavigatorState? get navigator;
  FocusManager get focus;
  TuiBinding get binding;
}
```

## 8. `FleuryApp`

`FleuryApp` is a widget that installs app-kernel services into the tree:

- `FleuryAppController`
- `CommandRegistry`
- status provider
- app-level semantic contribution

It should not own every pixel. Apps still compose their own layout:

```dart
FleuryApp(
  commands: commands,
  child: ConsoleScaffold(
    sidebar: AppSidebar(),
    body: SectionView(controller: sections),
    statusBar: AppStatusBar(),
  ),
)
```

For simple apps, `FleuryApp.simple(home: ...)` can wrap `Navigator` and a
default command palette. But the demo app should use the explicit shell form
so the APIs are pressured.

## 9. App-Owned Sections And Navigator

The kernel should support two complementary navigation shapes:

1. **App-owned sections** for persistent top-level areas like Overview, Runs,
   Transcript, and Diagnostics. These can be implemented as tabs, sidebars,
   split panes, or any other widget composition.
2. **Navigator routes/modals** for push flows, dialogs, details, and transient
   overlays.

This avoids overloading `Navigator` as both a route stack and an app tab/screen
registry while also avoiding a Fleury-specific screen registry that duplicates
ordinary widget state.

App section controllers are responsible for active IDs, retention policy, and
navigation commands. Fleury's role is to make those commands discoverable and
to let apps expose screen semantics through ordinary `Semantics` nodes.

## 10. Commands And Actions

Commands are named app actions. They differ from raw key bindings:

| Concept | Purpose |
| --- | --- |
| `KeyBinding` | Low-level input routing for a subtree. |
| `AppCommand` | Named app operation with metadata, enabled state, semantic action, and optional shortcuts. |
| `CommandRegistry` | Active command discovery and invocation. |
| `CommandPalette` | UI over the active registry. |

Why this matters:

- Tests can call `tester.appCommands.invoke(.startFakeTask)`.
- The command palette can search metadata.
- `KeyHintBar` can show command labels.
- Semantics can expose commands and availability.
- Disabled commands remain discoverable when useful.

Command invocation result should distinguish:

- `completed`
- `disabled`
- `notFound`
- `failed(error, stackTrace)`

The command handler may return `Future<void>`, but async progress, cancellation,
and streamed output should be modeled through the worker/effects milestone.

## 11. Command Scopes

Commands can come from:

- app root
- active screen
- focused subtree
- overlay/modal route
- future plugin/domain packages

The active registry should be ordered by proximity and scope:

1. modal/overlay commands
2. focused subtree commands
3. active screen commands
4. app-global commands

If command IDs collide, the nearest active scope wins for invocation, but
diagnostics should report the collision. For launch, prefer unique IDs.

Proposed widget:

```dart
CommandScope(
  commands: [
    AppCommand(id: .copyRow, title: 'Copy Row', run: _copySelectedRow),
  ],
  child: RunsTable(),
)
```

`CommandScope` should also emit equivalent `KeyBinding`s for shortcuts so the
existing `InputDispatcher` remains the one keyboard path.

## 12. Command Palette Integration

The existing `fleury_widgets.CommandPalette` takes widget-local `Command`
objects. Phase 1 should add a registry-backed path:

```dart
CommandPalette.open(context);
```

`CommandPalette` should support both widget-local `Command` rows and
registry-backed `AppCommand` discovery.

The palette should show:

- title
- description/help
- shortcut
- enabled/disabled state
- category

It should run through `CommandRegistry.invoke(id)`, not call arbitrary list-row
callbacks directly.

## 13. Status Model

Status is a first-class app-kernel contribution, not a random footer string.

```dart
final class StatusItem {
  const StatusItem({
    required this.id,
    required this.label,
    this.value,
    this.severity = StatusSeverity.info,
    this.action,
  });

  final String id;
  final String label;
  final String? value;
  final StatusSeverity severity;
  final CommandId? action;
}
```

Status items should be:

- renderable by an `AppStatusBar`
- queryable by tests
- exposed in the semantic graph
- useful for diagnostics and debug capture

The demo app should use status for active screen, task progress, and
capability fallback summary.

## 14. Lifecycle

`FleuryApp` can expose small lifecycle hooks:

- `onInit(CommandContext context)`
- `onDispose(CommandContext context)`
- `onCommandError(CommandError error)`
- `onUnhandledError(Object error, StackTrace stackTrace)`

Do not make lifecycle hooks the primary state model. They are integration
points for setup/teardown and error policy. Stateful widgets remain the normal
place for local UI state.

## 15. Semantics

The app kernel must contribute semantic nodes for:

- app root
- child-derived active screen summary when apps expose screen semantic nodes
- command registry and active commands
- command enabled/disabled state
- shortcuts
- status items
- command errors

This is required for RFC 0011 and the demo-app tests.

## 16. Implementation Plan

1. Add core IDs and command types in `packages/fleury`.
2. Add `CommandRegistry` and `CommandScope` over existing focus/binding
   machinery.
3. Add `FleuryApp` inherited scope and `FleuryAppController`.
4. Add `AppStatusBar`/status model, or a minimal status provider consumed by
   the demo app.
5. Add registry-backed command palette adapter in `fleury_widgets` or core,
   depending on dependency direction.
6. Add semantic contributions for commands, child screen summaries, and status.
7. Prove the flow in `packages/fleury_example_console` with app-owned
   navigation state.

## 17. Open Questions

- Should `CommandRegistry` live in core while `CommandPalette` lives in
  `fleury_widgets`, or should a minimal palette live in core?
- Should `AppCommand.run` be allowed to return `Future<void>` in v0, or should
  async behavior go exclusively through the worker/effects model?
- How much default UI should `FleuryApp.simple` provide before the demo app
  hardens the shape?
- Should command IDs be strings, typed const objects, or generated enum-like
  values?

## 18. Acceptance Criteria

M0.3 is complete when:

- This RFC defines how `FleuryApp`, screens, commands, shortcuts, status,
  lifecycle, focus, navigation, and command palette compose.
- The RFC preserves existing `Navigator`, `KeyBindings`, and retained widget
  architecture.
- The demo-app scenario can map every required command and screen onto the
  proposed kernel.
- Open questions that block M1.3 are recorded in the implementation tracker.
