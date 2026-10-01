# Hot reload

Fleury supports stateful hot reload: save a changed source file and the
running terminal updates in place while widget state, focus, and scroll
positions survive. It uses the Dart VM's `reloadSources` RPC followed by a
framework reassemble. On macOS and Linux, Fleury's dev supervisor makes it
work in any editor. The supervisor doesn't run on Windows, where `fleury run`
and `dart run` start the app without reload or restart; use an editor debug
session there (see [Quick start (VS Code)](#quick-start-vs-code)).

## Quick start (any editor)

On macOS or Linux, from your app's project directory:

```sh
fleury run
```

Without a globally installed CLI, use `dart run fleury run`. The launcher
starts your source app once with the VM service enabled, watches `lib/`,
`bin/`, and local path dependencies, and reloads on save. A compiled Fleury
CLI supports the same development workflow; the app itself runs in the Dart
SDK's JIT VM. A compiled app has no hot reload. If the app fails to compile
at startup, the launcher doesn't run it again: the compiler's errors print
once and the launcher exits with the app's exit code.

With no script named, the launcher picks the only Dart file in `bin/`, then
prefers `main.dart`, `run_app.dart`, or the package-named file. Name a script
when you want another entrypoint. Put VM options before the script and app
arguments after it:

```sh
fleury run --enable-asserts bin/run_app.dart --profile=local
```

The launcher preserves those arguments across restarts. Also pass argv to
`runApp` so the plain `dart run` alternative can restart with the same inputs:

```dart
Future<void> main(List<String> args) => runApp(const MyApp(), args: args);
```

Under plain `dart run`, the child cannot recover the original arguments by
itself. Without `args:`, it sees an empty list from its first frame, not only
after restart. The launcher already has the arguments from its command line.

Try it: increment a counter or focus an input, change a label in `build`,
and save. The label changes while the counter and focus stay where they were.

## Fix a failed save or restart

Open the debug shell with `Ctrl+G`. Successful reloads appear in **Logs**;
failed saves appear in **Errors** with their compiler diagnostics and as an
error banner over the app. A successful save clears the failed-edit banner.

- **Syntax or type error:** fix the source and save again. The running app
  keeps its previous code and state until the next successful reload.
- **Valid code the VM cannot migrate:** use **hot restart** (`Ctrl+G`, then
  `F5`) to run `main()` in a fresh child. Restart drops state. It does not fix
  compilation errors.

The debug header shows `F5 restart` only when a development supervisor is
attached. Under an editor's debugger the editor owns the run, so use its
**Restart** instead. If `F5` never reaches the app (a Mac keyboard may need
`Fn`, and VS Code's integrated terminal takes `F5` to start debugging), see
[When F5 doesn't restart](https://danreynolds.github.io/fleury/guides/hot-reload/#when-f5-doesnt-restart)
in the site guide.

## Plain `dart run` and other launch modes

`dart run bin/run_app.dart` also reloads on save in a real terminal. Its
supervisor starts from inside `runApp`, so it compiles the app twice and runs
code before `runApp` in both processes. Prefer `fleury run` when startup work
must happen once. Both paths keep the same terminal session and return the
app's exit code.

Opt out with `FLEURY_HOT_RELOAD=0`, or `runApp(enableHotReload: false)`. The
supervisor also steps aside for an editor-owned VM service, a `fleury serve`,
`fleury shell`, or `fleury_mcp` handle, an actual compiled app, Windows, a
non-TTY, or an app that passes its own `driver:` to `runApp` (under
`fleury run`, such an app still reloads on save but has no restart). For a
browser preview, enable the service in the spawned command:

```sh
fleury serve --spawn dart --enable-vm-service=0 run bin/run_app.dart
```

That preview reloads on save but has no hot restart: the serve socket accepts
one connection.

## Quick start (VS Code)

**Prerequisite**: the official [Dart VS Code extension][dart-ext]
(`Dart-Code.dart-code`). Fleury itself does **not** require its own extension.

fleury ships `.vscode/launch.json` and `.vscode/settings.json` in this
package. The launch config points every example at the integrated terminal;
the setting makes Dart-Code use that terminal for inline Run and Debug actions
too. Open `packages/fleury/` in VS Code, press F5, and the example launches.
Then:

- Run **Dart: Hot Reload** from the command palette after editing source.
- Or just save: `fleury create` projects set `dart.hotReloadOnSave:
  "allIfDirty"` in their workspace settings, so saving a dirty file during a
  debug session reloads automatically. (This repo's own workspace leaves it
  unset — delete the line from a generated project to opt out.)
- Use the editor's **Restart** (or stop and relaunch) when you deliberately
  want to rebuild from scratch and drop state. The debug shell offers no
  restart in a debug session.

Try this: launch `fleury · hot reload demo`, press `→` a few times
to bump the counter, then edit `_titleColor = AnsiColor(4)` to
`AnsiColor(1)` in `example/hot_reload_demo.dart` and save. The title
recolors after you run **Dart: Hot Reload**; the counter stays where you left
it. Enabling reload-on-save makes the save trigger that command automatically.

[dart-ext]: https://marketplace.visualstudio.com/items?itemName=Dart-Code.dart-code

## Adding the same to your own app

`fleury create my_app` writes the minimal project configuration automatically:
`console: terminal` in `.vscode/launch.json`, plus `dart.cliConsole: terminal`
and `dart.hotReloadOnSave: "allIfDirty"` in `.vscode/settings.json`. The Dart
VS Code extension does the debugging and hot reload; Fleury reassembles
automatically when the VM reports a reload.

For an existing project, copy those three fields and point `program` at your
entrypoint. No Fleury-specific VS Code extension is required.

The hot reload mechanism rides on the standard VM service protocol that
Dart-Code already speaks — when it fires `reloadSources`, fleury's
`HotReloadController` picks up the `IsolateReload` event via
the VM-service client and calls `BuildOwner.reassembleApplication()`.

## Fallback for a debugger without a terminal

Prefer an IDE-integrated terminal. On macOS or Linux, if an IDE can debug Dart
but only offers a non-TTY output pane, run `fleury shell` from the project root
and then launch the app from that project in the debugger. The app discovers
`.fleury/handle`; rendering and input stay in the real terminal while the
debugger remains attached. `FLEURY_HANDLE=<absolute socket>` is the explicit
override when the app cannot discover the project handle.

## Adding hot reload to your own app

Three lines:

```dart
import 'package:fleury/fleury.dart';

Future<void> main(List<String> args) async {
  await runApp(const MyApp(), args: args); // enableHotReload defaults to true
}
```

Run it with `fleury run` as in the quick start, or launch it through Dart-Code
as described above. Fleury listens for the VM's source-reload event; a
filesystem watcher that only restarts the process or sends a signal is not
stateful hot reload.

## What survives a reload

- Every `State.someField` you assigned (the State object itself is
  preserved across reload — only its code is swapped).
- Focused widget (your text input stays focused).
- Scroll offsets on `ListView` / `Tree`.
- A value `Animation` settles at its current target so no stale completion is
  left pending. A `FrameTicker` resets its phase and re-anchors its clock.
- Subscriptions registered in `initState` (they were never torn
  down).

## What doesn't survive

- Anything you computed once in `main()` before `runApp` ran.
- Top-level globals initialized at startup.
- Object identity for new instances created in `build()` (Flutter same).
- Valid changes that the VM cannot migrate into existing objects. Use hot
  restart (`Ctrl+G`, then `F5`) to apply these changes with fresh state. Fix
  compilation errors before restarting.

## Cache invalidation in your widgets

If your `State` caches an expensive computation (parsed config, fetched
data, derived layout) and you want the cache to refresh on reload,
override `reassemble`:

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
    _config = parseConfig(widget.configSource);  // re-parse with new code
  }
  // ...
}
```

This is exactly the Flutter contract — same hook name, same semantics.

## How the dev supervisor works

A plain `dart run` has no VM service, so nothing could trigger a reload —
that's the gap the supervisor closes. When `runApp` starts in a plain JIT dev
run on macOS or Linux (real TTY, no injected driver, no live VM service, no
serve handle), the first process becomes a thin supervisor instead of running
the app:

1. It re-spawns the same entrypoint script as a **child process** with
   `--enable-vm-service=0 --no-serve-devtools --write-service-info=<file>`
   and `inheritStdio` — the child owns the PTY, raw mode, signals, and stdio
   capture exactly as a normal run would. (The one visible trace is the VM
   service's single startup line, which the alt screen immediately hides.
   The service must come from VM flags — the whole reason a child *process*
   exists: under a runtime-enabled service (`Service.controlWebServer`, the
   only kind an already-running process can have) reloading changed sources
   crashes the VM's kernel service and hangs the RPC. See
   `docs/implementation/vm-reload-bug-report-draft.md`; same crash signature
   as dart-lang/sdk#54905.)
2. The child re-enters `runApp`, sees the `FLEURY_DEV_SUPERVISED` marker,
   confirms its service URI through a handshake file, and runs the classic
   single-isolate app — the same battle-tested shape an editor debugs.
3. The supervisor watches the package sources (via `package_config.json`:
   the root package plus local path deps; the pub cache is immutable and
   skipped), debounces saves, and calls `reloadSources` on the child's main
   isolate — then reports the outcome through `ext.fleury.reloadReport` so
   it lands in the debug shell.
4. Hot restart (the debug shell's `F5`) posts a `fleury.restartRequested`
   event on the child's VM-service Extension stream, which the supervisor
   listens to. The supervisor requests a graceful teardown
   (`ext.fleury.shutdown` → the normal exit path, terminal restored), then
   respawns the child fresh. A wedged child is SIGKILLed, the supervisor
   restores the terminal from outside (its own stdout *is* the tty), and the
   respawn proceeds. The app's `ext.fleury.restart` extension posts the same
   event, but it is the supervisor's hook, not an entry point for other
   tools: the child's service address goes to a temp file that the
   supervisor deletes once it has read it, and in an editor debug session no
   supervisor is listening, so the extension does nothing.
5. When the child exits for real — quit, Ctrl+C, crash — the supervisor
   mirrors its exit code. Both processes sit in the foreground process
   group; the supervisor swallows its own signal deliveries and lets the
   child's driver own the response.

Why a child *process* rather than a child isolate: `reloadSources` against an
`Isolate.spawnUri` group deadlocks the group when sources actually changed
(reproducible with a plain-Dart child on SDK 3.12 — no fleury involved), so
the supervisor uses the process boundary, which is also what keeps stdin,
signal, and stdio-capture ownership trivially correct across restarts.

`fleury run` runs this same supervisor from the CLI process instead of from a
first copy of the app, which is what saves the second compile. The child
cannot tell the difference: it sees a flag-enabled VM service and the
supervised-child environment either way.

## How it works under the hood

1. `runApp(enableHotReload: true)` calls
   `HotReloadController.attach(onReassemble: ...)`. That callback runs
   `TuiRuntime.reassembleApplication()`, which calls
   `BuildOwner.reassembleApplication()` followed by
   `TickerScheduler.reassemble()`, then schedules a frame.
2. The controller registers a `dart:developer` service extension at
   `ext.fleury.reassemble`. A VM-service client connected to the app (an
   editor's debug session, for example) can trigger a reassemble explicitly.
3. The controller probes `Service.getInfo()`. If a VM service URI is
   available, it opens a `VmService` connection and subscribes to
   `IsolateReload` events. When one fires, it calls onReassemble. This
   is the path that powers VS Code's reload-on-save.

`BuildOwner.reassembleApplication()`:
- Walks the element tree depth-first.
- For each `StatefulElement`, calls `state.reassemble()` (your hook to
  refresh caches).
- Marks every element dirty.
- Calls `flushBuild()` so the next frame rebuilds against the new code.

`TickerScheduler.reassemble()`:
- Fires every registered reassemble callback (a separate signal from
  per-frame tick callbacks).
- `Animation` settles at its current target so no old completion remains
  pending. `FrameTicker` resets its phase and re-anchors its clock.

## Browser development hosts

Terminal and browser reloads share `TuiRuntime.reassembleApplication()`:
rebuild the element tree, then reset surviving animations and frame tickers.
A browser tool such as [Fleury Pad](https://danreynolds.github.io/fleury/pad/)
applies the compiler's code update itself, then calls
`await MountedApp.reassemble()` from `package:fleury_web`. That future
completes after the rebuilt frame and its accessibility update are presented,
and rejects if the mount is disposed or presentation fails. Compilation and
code transport stay outside the framework; there is no separate tree walk for
the browser.

## Disabling hot reload

```dart
await runApp(const MyApp(), enableHotReload: false);
```

Use this in production launches. It skips the service-extension registration
and VM-service connection. The binary works fine without
`--enable-vm-service`.

## Troubleshooting

**"Nothing happens when I save"** — In `fleury run` or a plain `dart run`,
check that you are on macOS or Linux in a real terminal, `FLEURY_HOT_RELOAD`
is not `0`, and `dart pub get` has produced `.dart_tool/package_config.json`.
Setting `FLEURY_DEV_BOOTSTRAP_LOG` to a file path logs what the supervisor
watches and reloads. In an editor session, the editor triggers reload: use
**Dart: Hot Reload**, or enable `dart.hotReloadOnSave: "allIfDirty"`.
Generated projects already include that setting.

**"The compiler rejected my save"** — Fix the reported source error and save
again; your running app keeps its state. Restart only after the source
compiles, when the VM cannot migrate the changed program or you want to reset
state.

**"VS Code reloads my code but the UI doesn't update"** — The VM service is
enabled, but Fleury's controller didn't attach. Check that
`enableHotReload: true` (the default) in your `runApp` call.

**"Hot reload says it succeeded but my widget tree looks wrong"** —
Some edits can't be applied cleanly to a running tree (changing a
`StatefulWidget` to a `StatelessWidget`, removing a field that the
State references). The VM accepts the source change but the next
build crashes. Hot restart (`Ctrl+G`, then `F5`), or stop and relaunch the
process where restart isn't available.

**A new field throws `type 'Null' is not a subtype of type …` after a
reload** — Existing objects never ran the constructor that sets the new
field. Give it an initializer where it's declared, or hot restart. A
non-nullable field with neither is a compile error, and the reload reports
it.

## Implementation references

- `lib/src/runtime/hot_reload.dart` — `HotReloadController`
- `lib/src/runtime/tui_runtime.dart` — `TuiRuntime.reassembleApplication`,
  shared by the terminal and browser hosts
- `lib/src/widgets/framework.dart` — `BuildOwner.reassembleApplication`,
  `State.reassemble`
- `lib/src/animation/ticker_scheduler.dart` — reassemble registry
- `tool/hot_reload_probe/` — the substrate validation tool used to
  confirm the Dart VM behavior before any framework code shipped
- `example/hot_reload_demo.dart` — the demo
- `.vscode/launch.json` — the VS Code wiring template
- `doc/vscode_f5_acceptance.md` — the manual editor/terminal release gate
