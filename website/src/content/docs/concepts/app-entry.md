---
title: App entry points
description: runApp and mountApp — how a widget tree starts running in a terminal or a browser.
---

A Fleury program is a widget tree handed to a host entry function. Use `runApp`
when the tree runs in a terminal, and `mountApp` when a dart2js bundle mounts it
inside a browser element. For a real app, make that root a `FleuryApp`: it owns
the app-wide theme, command/status scopes, and route stack while the host owns
terminal or browser services.

`fleury serve` is a third deployment path: it streams a native app to a browser
as a local preview/debug bridge. It is not another widget-tree entry point.

## `runApp` — the terminal

The default. Lives in `package:fleury/fleury.dart` and drives a real terminal:

```dart
import 'package:fleury/fleury.dart';

void main() => runApp(
  const FleuryApp(title: 'My app', home: MyHomeScreen()),
);
```

`runApp` takes a **widget instance** and returns a `Future<AppExit>` that completes
after the app exits and the terminal has been restored. `AppExit` distinguishes
an orderly request from an unclaimed process signal so the caller can choose its
own exit code. On startup `runApp` acquires the terminal and switches it into
interactive mode (raw input, the alternate screen, hidden cursor), mounts your
tree, paints the first frame, and then renders again after every input event and
every `setState`. On exit — `Ctrl-C`, or your handler asking to stop — it restores
the terminal to exactly how it found it.

The options you'll actually reach for:

```dart
runApp(
  const FleuryApp(title: 'My app', home: MyHomeScreen()),
  onEvent: (event) {
    // Inspect every input event before the framework re-renders.
    // Return an ExitRequested to quit cleanly; null lets it through.
    return null;
  },
  globalBindings: [
    KeyBinding(KeyChord.ctrl.q, onEvent: (_) => requestExit(), label: 'Quit'),
  ],
)
```

`mode` (a `TerminalMode`, default `TerminalMode.interactive`) controls the raw-
mode/alt-screen/mouse setup; `enableHotReload` (default `true`) wires up state-
preserving hot reload under the Dart VM. Because `runApp` depends on `dart:io`,
it's exported from `fleury.dart` — *not* from the web-safe `fleury_core`.

For a small one-screen program, passing the screen directly is still valid:
`runApp(const StatusScreen())`. Use `FleuryApp` as soon as the program has an
app-wide theme, commands/status, extensions, or more than one screen.

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
same traversal behavior:

```dart
FleuryApp(
  title: 'Status monitor',
  theme: ThemeData.dark(),
  home: DashboardScreen(),
)
```

App-wide commands can be passed through `commands:`; route-local actions belong
in a `CommandScope` beside the screen that owns them. See
[Navigation and commands](/guides/navigation/#commands-that-navigate) for a
complete, compile-checked pattern.

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
defaults when `theme` is omitted; see [Theming](/guides/theming/) for app-wide
and local themes.

## `mountApp` — the browser

To run the **same widget tree** client-side in a browser, compile to JavaScript
with `dart2js` and call `mountApp` from `package:fleury_web/fleury_web.dart`.
It paints into a retained DOM cell grid and — this is the part that matters for
agents and accessibility — mirrors the tree into a **semantic DOM** by default:

```dart
import 'package:fleury/fleury_core.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;

void main() {
  final host = web.document.getElementById('app')!;
  mountApp(
    () => const FleuryApp(title: 'My app', home: MyHomeScreen()),
    into: host,
  );
}
```

Two host-API differences from `runApp` worth flagging:

- It takes a **widget factory** (`() => const MyApp()`), not an instance.
- It returns a `Future<MountedApp>` (a handle to the running surface), not
  `void`.

The host element must have an explicit size and a monospace font, or the grid
measures zero cells and paints nothing:

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
`fleury serve` instead — it runs your native app and streams the frames to a thin
client. That's local development tooling, not an entry point;
[Serving and embedding](/architecture/serving-and-embedding/) covers when to
embed versus serve.
