# Hot reload

fleury supports Dart-VM-class stateful hot reload: save a source file
and the running terminal updates in place — counter values, focus,
scroll positions, animation tickers all survive.

This is uncommon in TUI frameworks. Bubble Tea / Ratatui / Ink can only
restart the process and lose state; Textual reloads CSS but not Python
code. fleury inherits Flutter's reload mechanism by riding the Dart
VM's `reloadSources` RPC.

## What it does, in two sentences

When you save a file, your editor (or a CLI watcher) tells the Dart VM
to swap in the new code. fleury notices the swap, walks the element
tree calling `State.reassemble()` on each `State` and marking every
element dirty, and the next frame redraws against the new code.

## Quick start (VS Code)

**Prerequisite**: the official [Dart VS Code extension][dart-ext]
(`Dart-Code.dart-code`). Anyone writing Dart in VS Code already has
it; fleury itself does **not** require its own extension.

fleury ships `.vscode/launch.json` and `.vscode/settings.json` in
this package — the launch config wires `--enable-vm-service` and
points at the integrated terminal; the settings turn on
`dart.flutterHotReloadOnSave` (which despite the name applies to any
VM-service-enabled Dart program). Open `packages/fleury/` in VS
Code, press F5, the example launches. Then:

- **Save a file** — Dart VS Code extension auto-reloads. Changes
  appear instantly. (If reload-on-save isn't firing, check that
  `dart.flutterHotReloadOnSave` is `"always"` in your user or
  workspace settings.)
- **Cmd+Shift+F5** (Mac) / **Ctrl+Shift+F5** (Win/Linux) — manual hot
  reload via the command palette ("Dart: Hot Reload"). Always works
  regardless of the on-save setting.
- **Cmd+F5** — hot restart (rebuild the tree from scratch, drops state).

Try this: launch `fleury · hot reload demo`, press `→` a few times
to bump the counter, then edit `_titleColor = AnsiColor(4)` to
`AnsiColor(1)` in `example/hot_reload_demo.dart` and save. The title
recolors live; the counter stays where you left it.

[dart-ext]: https://marketplace.visualstudio.com/items?itemName=Dart-Code.dart-code

## Adding the same to your own app

Copy fleury's `.vscode/launch.json` and `.vscode/settings.json`
templates into your own project's `.vscode/`, swap the `program:` path
to point at your `bin/your_app.dart`, and you're done. The Dart VS
Code extension does all the work; fleury's framework reassemble
runs automatically when the VM reports a reload.

There is no fleury-specific VS Code extension. The hot reload
mechanism rides on the standard VM service protocol that Dart-Code
already speaks — when it fires `reloadSources`, fleury's
`HotReloadController` picks up the `IsolateReload` event via
`dart:developer` and calls `BuildOwner.reassembleApplication()`.

## Quick start (CLI)

```sh
dart pub global activate hotreloader   # one time
dart --enable-vm-service example/hot_reload_demo.dart
```

The community `hotreloader` package watches the filesystem and asks
the VM to reload on change. fleury picks the reload event up
automatically.

## Other editors

- **IntelliJ / Android Studio**: install the Dart plugin and use the
  same launch.json fields under a Dart run configuration. Cmd+\ /
  Ctrl+\ triggers Hot Reload via the same VM service path.
- **Neovim with `dartls`** or **Emacs with `lsp-dart`**: trigger
  reload through your LSP client's command interface (`Reload Sources`
  RPC), or fall back to the SIGUSR1 path below.
- **Anything else**: the SIGUSR1 path below works without an LSP.

## Editor-agnostic (any file watcher)

fleury also reassembles on SIGUSR1. Wire any watcher you like:

```sh
dart --enable-vm-service example/hot_reload_demo.dart &
PID=$!
find lib example -name '*.dart' | entr -p kill -SIGUSR1 $PID
```

(Windows: SIGUSR1 doesn't exist, so use the VS Code or `hotreloader`
paths there.)

## Adding hot reload to your own app

Three lines:

```dart
import 'package:fleury/fleury.dart';

Future<void> main() async {
  await runTui(const MyApp());     // enableHotReload defaults to true
}
```

Then pick a launch path: VS Code (template above), CLI with
`hotreloader`, or editor-agnostic SIGUSR1. All three use the same
underlying mechanism — your `runTui` call is identical.

## What survives a reload

- Every `State.someField` you assigned (the State object itself is
  preserved across reload — only its code is swapped).
- Focused widget (your text input stays focused).
- Scroll offsets on `ListView` / `Tree`.
- Animation tickers mid-flight (they re-anchor cleanly via the
  scheduler's reassemble lane, so a value tween doesn't jump).
- Subscriptions registered in `initState` (they were never torn
  down).

## What doesn't survive

- Anything you computed once in `main()` before `runTui` ran.
- Top-level globals initialized at startup.
- Object identity for new instances created in `build()` (Flutter same).
- Edits that change a constructor signature, generic parameter, or
  add a non-`const` top-level initializer — the VM rejects these as
  `isolate reload failed` and you get a stderr message. Hot restart
  (Cmd+F5) instead — it's still fast, just drops state.

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

1. `runTui(enableHotReload: true)` calls
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
4. On POSIX, the controller installs a `SIGUSR1` handler that also
   calls onReassemble. This is the path that powers any file-watcher
   wrapper (entr, fswatch, inotifywait, custom Makefiles).

`BuildOwner.reassembleApplication()`:
- Walks the element tree depth-first.
- For each `StatefulElement`, calls `state.reassemble()` (your hook to
  refresh caches).
- Marks every element dirty.
- Calls `flushBuild()` so the next frame rebuilds against the new code.

`TickerScheduler.reassemble()`:
- Fires every registered reassemble callback (a separate signal from
  per-frame tick callbacks).
- Animation primitives use this to re-anchor in-flight tweens so they
  continue smoothly rather than restarting.

## Disabling hot reload

```dart
await runTui(const MyApp(), enableHotReload: false);
```

Use this in production launches. It skips the service-extension
registration, the VM-service connection, and the SIGUSR1 handler. The
binary works fine without `--enable-vm-service`.

## Troubleshooting

**"Nothing happens when I save"** — Check that `--enable-vm-service`
was passed (VS Code's launch.json template includes it). Look for a
startup line like `The Dart VM service is listening on http://...` in
stderr; if you don't see it, the flag isn't being applied.

**"VS Code reloads my code but the UI doesn't update"** — Same root
cause: the VM service is enabled, but fleury's controller didn't
attach. Check that `enableHotReload: true` (the default) in your
`runTui` call.

**"Hot reload says it succeeded but my widget tree looks wrong"** —
Some edits can't be applied cleanly to a running tree (changing a
`StatefulWidget` to a `StatelessWidget`, removing a field that the
State references). The VM accepts the source change but the next
build crashes. Hot restart instead (Cmd+F5 in VS Code, kill and
relaunch in CLI).

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

## Comparison to peers

| Framework | Stateful hot reload | Notes |
| --- | --- | --- |
| Flutter (Dart) | Yes | `WidgetsBinding.performReassemble` |
| **fleury** | **Yes** | Same VM mechanism, framework-level reassemble walk |
| Textual (Python) | CSS only | Python code reload requested in #4218; unimplemented |
| Bubble Tea (Go) | No | `air` rebuilds + restarts |
| Ratatui (Rust) | No | `cargo watch` rebuilds + restarts |
| Ink (Node) | No | `nodemon` restarts |
