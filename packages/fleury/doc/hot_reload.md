# Hot reload

fleury supports Dart-VM-class stateful hot reload: reload changed source and
the running terminal updates in place while widget state, focus, and scroll
positions survive.

Fleury uses the Dart VM's `reloadSources` RPC and performs a framework-level
reassemble walk after the VM reports a reload.

## What it does, in two sentences

When Dart-Code tells the Dart VM to swap in new code, fleury notices the swap,
walks the element
tree calling `State.reassemble()` on each `State` and marking every
element dirty, and the next frame redraws against the new code.

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
  `isolate reload failed` and you get a stderr message. Stop and relaunch the
  app instead; it drops state but picks up the unsupported change.

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
