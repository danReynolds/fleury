---
title: Hot reload
description: Save a file and the running terminal app updates in place — state, focus, and scroll intact. Out of the box, in any editor, plus hot restart from the debug shell.
---

Fleury supports **stateful hot reload**: save a changed source file and the
running terminal app updates in place — widget state, focus, and scroll
positions survive. It works in any editor with the Dart VM's code swapping
and Fleury's development supervisor.

## Quick start

From your app's project directory:

```sh
fleury run
```

Without a globally installed CLI, use `dart run fleury run`. The launcher
starts your app once with the VM service enabled, watches the package's
sources (`lib/`, `bin/`, and local path dependencies), and reloads on save.
Both the installed CLI and a compiled Fleury CLI can supervise a source app;
you need the Dart SDK installed to run that app.

The launcher finds your entrypoint in `bin/`. To choose one explicitly and
pass arguments, put VM options before the script and app arguments after it:

```sh
fleury run --enable-asserts bin/run_app.dart --profile=local
```

Try it: increment a counter or focus an input, change a label in `build`,
and save. The frame updates while state and focus stay where you left them.

Reload outcomes appear in the [debug shell](/fleury/guides/debugging/)
(`Ctrl+G`): successful reloads in **Logs**, failed saves in **Errors**.
**If the compiler reports a syntax or type error, fix it and save again.**
The app keeps its previous code and state until the next successful reload.
Restarting does not fix a compilation error.

Plain `dart run bin/run_app.dart` also supports reload on save. It starts the
supervisor from inside `runApp`, compiling the app twice and running startup
code twice. `fleury run` avoids that extra work; see *How it works* below.

## Hot restart

Some valid edits cannot be migrated into a running program. If the VM rejects
a change to the program's structure after it compiles, use **hot restart**:
drop state and re-run `main()` fresh in the same terminal session.

- Press `Ctrl+G` to open the debug shell, then `F5` (the shell header shows
  `F5 restart` whenever it's available).
- Or invoke the `ext.fleury.restart` service extension from any VM-service
  client — an editor, [`fleury_mcp`](/fleury/guides/driving-with-agents/), or
  a script.

Reload keeps state and is the default loop; restart is for valid changes the
VM cannot migrate, or when you deliberately want fresh state.

`fleury run` preserves the app arguments across restarts. Also pass them to
`runApp` so the plain `dart run` alternative can restart with the same inputs:

```dart
Future<void> main(List<String> args) => runApp(const MyApp(), args: args);
```

Without `args:`, a plain `dart run` cannot recover the original arguments for
its child process. The launcher already has them from its command line.

## In an editor debug session

When you launch under a debugger (VS Code's F5 with the
[Dart extension](https://marketplace.visualstudio.com/items?itemName=Dart-Code.dart-code),
or any editor that speaks the VM service protocol), the editor owns the run
and the supervisor steps aside — Fleury detects the editor's reload instead:
when the editor calls `reloadSources`, Fleury picks up the VM's reload event
and reassembles the widget tree automatically.

`fleury create` projects come pre-wired for this: the generated
`.vscode/launch.json` points the app at the integrated terminal, and
`.vscode/settings.json` sets `dart.hotReloadOnSave: "allIfDirty"` so saving a
dirty file during a debug session reloads without a keypress. For an existing
project, copy those two files' three fields (`console: terminal`,
`dart.cliConsole: terminal`, `dart.hotReloadOnSave`) and point `program` at
your entrypoint. No Fleury-specific editor extension exists or is needed.

## What survives a reload

- Every field on your `State` objects (the object is preserved; only its code
  is swapped).
- Focus — your text input stays focused, with its caret.
- Scroll offsets on `ListView`, `Tree`, `DataTable`.
- Subscriptions registered in `initState` (they were never torn down).
- A value `Animation` settles at its current target so no stale completion is
  left pending; a `FrameTicker` resets its phase and re-anchors its clock.

## What doesn't

- Anything computed in `main()` before `runApp` ran, and top-level globals
  initialized at startup.
- Object identity for instances created in `build()` (same as Flutter).
- Valid changes the VM cannot migrate into existing objects. Hot restart
  applies these with fresh state; compilation errors still need fixing first.

## Refreshing caches on reload

If a `State` caches an expensive computation (parsed config, fetched data)
and you want it recomputed on reload, override `reassemble` — the same hook,
name, and semantics as Flutter:

```dart
class _MyWidgetState extends State<MyWidget> {
  late ParsedConfig _config;

  @override
  void initState() {
    super.initState();
    _config = parseConfig(widget.configSource);
  }

  @override
  void reassemble() {
    super.reassemble();
    _config = parseConfig(widget.configSource); // re-parse with new code
  }
}
```

## When the supervisor steps aside

The supervisor runs only when it can own the session safely: a source app
launched through `fleury run` or a plain JIT `dart run` on a real terminal.
It automatically yields to anything else that
owns the run — an editor debug session (a live VM service), a `fleury serve`
handle, a compiled app, Windows, a non-TTY, or an injected test driver —
and the app runs exactly as before, no supervisor involved.

### Reloading a browser preview

Because the supervisor steps aside for a serve handle, the usual browser
command hot reloads nothing:

```sh
fleury serve --spawn dart run bin/run_app.dart   # no VM service, no reload
```

Enable the service in the spawned command itself and the app reloads on save,
with the browser preview updating live:

```sh
fleury serve --spawn dart --enable-vm-service=0 run bin/run_app.dart
```

`=0` lets the VM pick a free port. Reload only — hot restart is intentionally
unavailable here, because a respawned child would re-dial the handle's
single-accept socket and wedge the session. `serve` never adds the flag on
your behalf: opening a debug port is your call.

Opting out entirely:

```sh
FLEURY_HOT_RELOAD=0 dart run bin/run_app.dart
```

or `runApp(enableHotReload: false)` — the right setting for production
launches, where it also skips the service-extension registration.

## How it works

`fleury run` starts a development supervisor without compiling or running
your app in the launcher. It launches your source app in a child Dart VM with
the VM service enabled, then watches source files and requests reloads. This
also works when the launcher itself is compiled to a native executable.

A plain `dart run` has no VM service, so nothing could trigger a reload —
that's the gap the supervisor closes. When `runApp` starts in a plain JIT dev
run, the first process becomes a thin supervisor: it re-spawns your entrypoint
as a child process with a flag-enabled VM service (`inheritStdio` — the child
owns the terminal, raw mode, and signals exactly as a normal run would),
watches the package sources listed in `package_config.json`, debounces saves,
and calls the VM's `reloadSources` on the child. After the VM swaps the code,
Fleury walks the element tree calling `State.reassemble()` and marking every
element dirty, so the next frame redraws against the new code. Hot restart
asks the child to tear down gracefully (terminal restored), then respawns it
fresh — same session, new process.

When the child exits for real — quit, `Ctrl+C`, a crash — the supervisor
mirrors its exit code, so scripts and CI see exactly what they'd see without
it.

**With plain `dart run`, your `main()` runs twice.** The supervisor *is* your
entrypoint, parked inside `runApp`; the app is a second process running the same entrypoint. So
everything in `main()` before `runApp` executes in both — once in the
supervisor, once in the app. Code that must happen exactly once (binding a
port, taking a lock, subscribing to stdin, writing a pid file) fails or
double-runs in the second process. Use `fleury run` so startup runs only in
the app, or run without the supervisor (`FLEURY_HOT_RELOAD=0`, or
`enableHotReload: false`). The generated scaffold's `main()` is just the
`runApp` call, so this only matters once you add startup work — and the
supervisor prints a hint when the first app process exits non-zero within two
seconds of starting.

## Troubleshooting

**Nothing happens when I save** — In `fleury run` or a plain `dart run`: check
you're on a real terminal (not a pipe) and that `FLEURY_HOT_RELOAD` isn't `0`. Your
entrypoint also has to sit in a package with a resolved
`.dart_tool/package_config.json` (`dart pub get`) — that file is what says
which sources to watch, and with nothing to watch the supervisor steps aside
and the run is an ordinary one. In an
editor debug session: reload-on-save is the editor's job — run **Dart: Hot
Reload** from the command palette, or set `dart.hotReloadOnSave:
"allIfDirty"` (generated projects have it already).

**Reload succeeds but the UI doesn't update** — Check `enableHotReload: true`
(the default) in your `runApp` call.

**The app exits right away under `dart run`, but not with `FLEURY_HOT_RELOAD=0`**
— Startup work before `runApp` ran twice (see *How it works*): the supervisor
already bound the port / took the lock / consumed stdin, and the app process
found it taken. Use `fleury run` so startup runs once.

**"isolate reload failed: missing fields"** — You added a non-nullable field
to a `State` class without a default; the live instance can't be migrated.
Hot restart (`Ctrl+G`, `F5`), or make the field nullable / give it a default.

**Reload succeeded but the tree looks wrong** — Some edits apply but can't
migrate a running tree cleanly (a `StatefulWidget` becoming stateless, a
removed field still referenced). Hot restart.
