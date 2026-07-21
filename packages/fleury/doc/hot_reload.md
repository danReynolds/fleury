# Hot reload

fleury supports Dart-VM-class stateful hot reload: save a changed source file
and the running terminal updates in place while widget state, focus, and
scroll positions survive. It works **out of the box, in any editor** — no
flags, no plugin, no wrapper command.

Fleury uses the Dart VM's `reloadSources` RPC and performs a framework-level
reassemble walk after the VM reports a reload.

## What it does, in two sentences

When new code is swapped into the Dart VM — by fleury's own dev supervisor on
save, or by an editor like Dart-Code — fleury notices the swap, walks the
element tree calling `State.reassemble()` on each `State` and marking every
element dirty, and the next frame redraws against the new code.

## Quick start (any editor)

```sh
dart run bin/main.dart
```

That's the whole setup. A plain JIT run on a real terminal starts fleury's
**dev supervisor**: it re-runs your entrypoint as a supervised child process
with the VM service enabled, watches your package's sources (`lib/`, `bin/`,
and any local *path* dependencies — a framework checkout included), and hot
reloads on save. Edit in vim, Zed, IntelliJ, anything — saving is the trigger.

- Reload outcomes surface in the debug shell (`Ctrl+G`): "Reloaded N libraries
  in Xms" in the **Logs** tab, compile errors in the **Errors** tab. The
  frames themselves are never disturbed.
- **Hot restart** — drop state and re-run `main()` fresh, same terminal
  session — is in the debug shell: `Ctrl+G`, then `F5` (shown in the shell
  header whenever it's available). Any VM-service client (an editor,
  `fleury_mcp`, a script) can also invoke `ext.fleury.restart`. Reload keeps
  state; restart is for the changes reload can't apply (see below).
- Opt out with `FLEURY_HOT_RELOAD=0`, or `runApp(enableHotReload: false)`.
- The supervisor steps aside automatically whenever something else owns the
  run: an editor debug session (a live VM service), a `fleury serve` handle,
  an AOT build, Windows, a non-TTY, or an injected test driver. Under a
  `fleury serve --spawn` session, save-to-reload stays available when the
  spawn command itself enables the VM service (e.g. `fleury serve --spawn
  'dart --enable-vm-service=0 run bin/main.dart'`) — the browser preview then
  updates live — but there is never a restart there (the serve socket accepts
  exactly one connection).
- One caveat: a dev restart re-runs `main()` without the original CLI
  arguments (a process cannot recover its own argv for a sibling spawn). An
  app that must re-see argv can set `FLEURY_HOT_RELOAD=0`.

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
- Stop and relaunch when you deliberately want to rebuild from scratch and
  drop state.

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

There is no fleury-specific VS Code extension. The hot reload
mechanism rides on the standard VM service protocol that Dart-Code
already speaks — when it fires `reloadSources`, fleury's
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

Future<void> main() async {
  await runApp(const MyApp());     // enableHotReload defaults to true
}
```

Launch it through Dart-Code as described above. Fleury listens for the VM's
source-reload event; a filesystem watcher that only restarts the
process or sends a signal is not stateful hot reload.

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
- Edits that change a constructor signature, generic parameter, or
  add a non-`const` top-level initializer — the VM rejects these as
  `isolate reload failed` (the message lands in the debug shell's Errors
  tab). **Hot restart** instead: `Ctrl+G`, then `F5` — or invoke
  `ext.fleury.restart` (or stop and relaunch); it drops state but picks up the unsupported change, in the same
  terminal session.

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
run (real TTY, no injected driver, no live VM service, no serve handle), the
first process becomes a thin supervisor instead of running the app:

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
4. `ext.fleury.restart` (registered in the app) asks the supervisor — via a
   `postEvent` on the service's Extension stream — to restart: it requests a
   graceful teardown (`ext.fleury.shutdown` → the normal exit path, terminal
   restored), then respawns the child fresh. A wedged child is SIGKILLed,
   the supervisor restores the terminal from outside (its own stdout *is*
   the tty), and the respawn proceeds.
5. When the child exits for real — quit, Ctrl+C, crash — the supervisor
   mirrors its exit code. Both processes sit in the foreground process
   group; the supervisor swallows its own signal deliveries and lets the
   child's driver own the response.

Why a child *process* rather than a child isolate: `reloadSources` against an
`Isolate.spawnUri` group deadlocks the group when sources actually changed
(reproducible with a plain-Dart child on SDK 3.12 — no fleury involved), so
the supervisor uses the process boundary, which is also what keeps stdin,
signal, and stdio-capture ownership trivially correct across restarts.

## How it works under the hood

1. `runApp(enableHotReload: true)` calls
   `HotReloadController.attach(onReassemble: ...)`. By default, that
   callback runs `BuildOwner.reassembleApplication()` followed by
   `TickerScheduler.reassemble()`.
2. The controller registers a `dart:developer` service extension at
   `ext.fleury.reassemble`. Any tool that can speak the VM service
   protocol can trigger a reassemble explicitly.
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

## Disabling hot reload

```dart
await runApp(const MyApp(), enableHotReload: false);
```

Use this in production launches. It skips the service-extension registration
and VM-service connection. The binary works fine without
`--enable-vm-service`.

## Troubleshooting

**"Nothing happens when I save"** — Reload-on-save is optional and is not
enabled by the generated project. Run **Dart: Hot Reload** from the command
palette, or opt into `dart.hotReloadOnSave: "allIfDirty"` in your user
settings. Dart-Code enables the VM service for a debug launch automatically;
the VM-service flag alone is not hot reload because a client still has to call
`reloadSources`.

**"VS Code reloads my code but the UI doesn't update"** — Same root
cause: the VM service is enabled, but fleury's controller didn't
attach. Check that `enableHotReload: true` (the default) in your
`runApp` call.

**"Hot reload says it succeeded but my widget tree looks wrong"** —
Some edits can't be applied cleanly to a running tree (changing a
`StatefulWidget` to a `StatelessWidget`, removing a field that the
State references). The VM accepts the source change but the next
build crashes. Stop and relaunch the process.

**"`isolate reload failed: missing fields`"** — You added a non-
nullable field to a `State` class without a default value. The
existing State instance can't be migrated. Hot restart, or make the
field nullable / give it a default.

## Implementation references

- `lib/src/runtime/hot_reload.dart` — `HotReloadController`
- `lib/src/widgets/framework.dart` — `BuildOwner.reassembleApplication`,
  `State.reassemble`
- `lib/src/animation/ticker_scheduler.dart` — reassemble registry
- `tool/hot_reload_probe/` — the substrate validation tool used to
  confirm the Dart VM behavior before any framework code shipped
- `example/hot_reload_demo.dart` — the demo
- `.vscode/launch.json` — the VS Code wiring template
- `doc/vscode_f5_acceptance.md` — the manual editor/terminal release gate
