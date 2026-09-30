---
title: App entry points
description: runApp and mountApp — how a widget tree starts running in a terminal or a browser.
---

A Fleury program is a widget tree handed to a host entry function. Use `runApp`
when the tree runs in a terminal, and `mountApp` when a dart2js bundle mounts it
inside a browser element. For a real app, make that root a `FleuryApp`: it owns
the app-wide theme, command/status scopes, and route stack while the host owns
terminal or browser services.

`fleury serve` is not a third entry point. It streams a native app's frames to
a browser as a local development preview; the app itself still starts with
`runApp`.

## `runApp` — the terminal

The default. Lives in `package:fleury/fleury.dart` and drives a real terminal:

```dart title="bin/run_app.dart"
import 'package:fleury/fleury.dart';

void main(List<String> args) => runApp(
  const FleuryApp(title: 'My app', home: MyHomeScreen()),
  args: args,
  mode: const TerminalMode(mouse: true),
);
```

`MyHomeScreen` is the screen inside the shell. A project made with
`fleury create my_app` instead defines `MyApp` in `lib/app.dart`, which builds its
`FleuryApp`; its entrypoint passes `const MyApp()` directly to `runApp`. Keep
that one shell when changing or replacing the screen.

`runApp` takes a **widget instance** and returns a `Future<AppExit>` that completes
after the app exits and the terminal has been restored. `AppExit` distinguishes
an orderly request from an unclaimed process signal or unhandled Ctrl+C so the
caller can choose its own exit code. On startup `runApp` acquires the terminal and, by default, switches
to raw input and the alternate screen with a hidden cursor. It mounts your
tree, paints the first frame, and then renders again after every input event and
every `setState`. On exit — unhandled `Ctrl+C` or `exitApp()` — it restores
terminal modes and returns control to the caller.

[Shutdown and signals](/fleury/guides/shutdown-and-signals/) shows how to finish
the UI, clean up resources, and preserve interrupt exit codes.

The options you'll actually reach for:

```dart
runApp(
  const FleuryApp(title: 'My app', home: MyHomeScreen()),
  mode: const TerminalMode(mouse: true),
  onEvent: (event) {
    // Observe events after widget dispatch and default Ctrl+C handling.
    // Return EventHandled to claim a signal, or ExitRequested to finish.
    return null;
  },
)
```

`mode` chooses `TerminalMode.fullScreen()` (the default) or
`TerminalMode.inline(rows: ...)`. Both leave mouse input off unless you pass
`mouse: true`, as the generated `bin/run_app.dart` does with
`TerminalMode(mouse: true)`; without it, clicks never reach
`GestureDetector` or buttons. For hover, use `mouseMotion: true`, which also
enables clicks. Forward `main`'s `args` to `runApp` so app arguments survive
supervised `dart run` startup and hot restart. `enableHotReload` (default `true`) wires up state-
preserving hot reload under the Dart VM. Because `runApp` depends on `dart:io`,
it's exported from `fleury.dart` — *not* from the web-safe `fleury_core`.

For a small one-screen program, passing the screen directly is still valid:
`runApp(const StatusScreen())`. A bare root has no `Navigator`, so it also
skips the Tab and arrow focus traversal that routes install (see below). Use
`FleuryApp` as soon as the program has an app-wide theme, commands/status,
extensions, more than one screen, or more than one focusable control.

## Full-screen or inline?

Full-screen is the default: the UI fills the terminal viewport and earlier
shell output reappears when it exits. It suits editors, dashboards, and other
workspaces. For a picker or setup step within a command, inline reserves rows in
the main buffer so earlier output remains available:

```dart
await runApp(
  app, // Your root widget.
  mode: const TerminalMode.inline(rows: 14, mouse: true),
  enableHotReload: false,
);
// Print the result here, after the live region has been cleared.
```

The example turns hot reload off so the code around `runApp`, such as printing
the result, runs once. With hot reload on, a plain `dart run` runs startup code
in two processes, and each hot restart runs the completion code again; see
[Hot reload](/fleury/guides/hot-reload/#keep-startup-work-inside-the-app).

Both modes use the same widgets and input model. Inline currently supports
native macOS/Linux terminals with cursor reporting; its height is explicit.
[Full-screen and inline UIs](/fleury/guides/terminal-modes/) compares the live
experience, explains the terminal buffers, and covers sizing, results, and
subprocess handoff.

## Host services and the app shell

The host entrypoints install shared target services around whatever root you
provide:

- a **`MediaQuery`** carrying the surface's cell size (rebuilt on resize),
- the **focus manager**, so focus can be requested and observed,
- **pointer routing**, so `GestureDetector` / `MouseRegion` receive mouse events,
- an **`Overlay`** for app-owned floating layers such as tooltips, and
- target capabilities, input, semantics, and scheduling.

The native terminal host additionally installs captured-output, debug-shell,
and runtime-error presentation services. The browser embed deliberately omits
those native-only layers.

The host deliberately does not own app navigation or theming. `FleuryApp` puts
its app scopes above a `Navigator`, so every pushed or presented route sees the
same theme, command registry, status controller, shortcuts, extensions, and
data sources. Those Navigator routes also install directional and Tab focus
traversal. A bare root can add its own `FocusTraversalGroup` when it needs the
same traversal behavior. The common case needs none of that:

```dart
FleuryApp(
  title: 'Status monitor',
  theme: ThemeData.dark(),
  home: DashboardScreen(),
)
```

App-wide commands can be passed through `commands:`; route-local actions belong
in a `CommandScope` beside the screen that owns them. The
[app-shell example](https://github.com/danReynolds/fleury/blob/main/packages/fleury_widgets/example/app_shell_demo.dart)
shows both scopes together. [Commands](/fleury/guides/commands/)
develops that model through buttons, shortcuts, palettes, and availability;
[Key handling](/fleury/guides/focus-and-keyboard/) covers lower-level,
keyboard-specific interaction.

Choose exactly one root mode:

- `home:` is the normal app path. `FleuryApp` creates and owns the route stack,
  with `home` as its first screen.
- `child:` is the custom-shell path. Fleury installs the app scopes but no
  `Navigator`; your child owns any navigation topology it needs. If the shell
  exposes app-wide root navigation, give it one top-level Navigator and nest
  pane-local stacks beneath that root.

For example, a workspace with its own fixed sidebar can place an explicit
Navigator in the content pane:

```dart
FleuryApp(
  title: 'Workspace',
  child: Row(
    children: [
      const SizedBox(width: 18, child: Text('Workspace')),
      const Expanded(child: Navigator(home: HomeScreen())),
    ],
  ),
)
```

Do not pass both `home` and `child`. `Theme.of(context)` still returns sensible
defaults when `theme` is omitted; see [Theming](/fleury/guides/theming/) for app-wide
and local themes.

## `mountApp` — the browser

To run the **same widget tree** client-side in a browser, compile to JavaScript
with `dart2js` and call `mountApp` from `package:fleury_web/fleury_web.dart`.
It paints into a retained DOM cell grid and — this is the part that matters for
agents and accessibility — mirrors the tree into a **semantic DOM** by default:

```dart title="web/main.dart"
import 'package:fleury/fleury_core.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  final host = web.document.getElementById('app')!;
  await mountApp(
    () => const FleuryApp(title: 'My app', home: MyHomeScreen()),
    into: host,
  );
}
```

Two host-API differences from `runApp` worth flagging:

- It takes a **widget factory**, as the `() => const FleuryApp(...)` above
  shows. For a generated app whose `MyApp` already builds the shell, use
  `() => const MyApp()`.
- Its future completes as soon as the app is **mounted**, with a `MountedApp`
  handle to the running surface (call `dispose()` on it to unmount). The future
  from `runApp` completes only when the app **exits**.

The host element needs an explicit size, or the grid measures zero cells and
paints nothing. It also needs a monospace font, or the cells misalign:

```html
<div id="app" style="width:80ch;height:24em;font-family:monospace"></div>
```

This is the path the live examples throughout these docs use: each embedded
surface is a real Fleury tree compiled with `dart2js` and mounted with
`mountApp`. Small isolated widget examples intentionally do not need a
`FleuryApp` shell.

## Which one?

| Target | Entry function | Takes |
|---|---|---|
| Terminal, native | `runApp` | a widget instance, usually `FleuryApp(...)` |
| Browser, embedded | `mountApp` | a widget factory and `into:` host element |

To preview a native app in a browser *without* compiling it yourself, reach for
`fleury serve` instead. Spawn mode launches a native app per browser connection;
bridge mode attaches an app you start yourself. Both stream its frames to the
browser. File access, process execution, and log collection happen on the
machine running that native app. Browser embeds can still display files through
a browser-safe `FileSource` and logs through `LogRegion`; they supply their own
data instead of reading the host's disk or processes.

Serve is local development tooling, not an entry point;
[Serving and embedding](/fleury/architecture/serving-and-embedding/) covers when to
embed versus serve.
