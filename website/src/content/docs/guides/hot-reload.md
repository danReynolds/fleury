---
title: Hot reload
description: Save a file and the running terminal app updates in place — state, focus, and scroll intact. Out of the box, in any editor, plus hot restart from the debug shell.
---

Fleury supports **stateful hot reload**: save a changed source file and the
running terminal app updates in place — widget state, focus, and scroll
positions survive. It works out of the box with a plain `dart run`, in any
editor, with no flags, no plugin, and no wrapper command. This is the Dart VM's
own code-swapping (the mechanism Flutter developers lean on), driven by a dev
supervisor built into `runApp` — not a file watcher that restarts your process
and loses your place.

## Quick start

```sh
dart run bin/main.dart
```

That's the whole setup. A plain JIT run on a real terminal starts Fleury's
**dev supervisor**: it re-runs your entrypoint as a supervised child process
with the VM service enabled, watches your package's sources (`lib/`, `bin/`,
and any local *path* dependencies — a framework checkout included), and hot
reloads on save. Edit in vim, Zed, IntelliJ, VS Code, anything — saving is the
trigger.

Try it: run any app, note some state (a counter, a scroll position, focused
input), change a color or a label in the source, and save. The frame updates
in well under a second; the state stays where you left it.

Reload outcomes surface in the [debug shell](/fleury/guides/debugging/)
(`Ctrl+G`): "Reloaded N libraries in Xms" lands in the **Logs** tab, compile
errors in the **Errors** tab. The app's frames are never disturbed.

## Hot restart

Some edits can't be applied to a running program — changing a constructor
signature, adding a non-`const` top-level initializer, reshaping a `State`
class. The VM rejects these ("isolate reload failed", reported in the Errors
tab), and the fix is a **hot restart**: drop state and re-run `main()` fresh,
in the same terminal session.

- Press `Ctrl+G` to open the debug shell, then `F5` (the shell header shows
  `F5 restart` whenever it's available).
- Or invoke the `ext.fleury.restart` service extension from any VM-service
  client — an editor, [`fleury_mcp`](/fleury/guides/driving-with-agents/), or
  a script.

Reload keeps state and is the default loop; restart is for the changes reload
can't apply.

One caveat: a dev restart re-runs `main()` without the original CLI arguments
(a process cannot recover its own argv for a sibling spawn). An app that must
re-see argv can set `FLEURY_HOT_RELOAD=0` and restart manually.

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
- Edits the VM rejects — changed constructor signatures, generic parameters,
  new non-`const` top-level initializers. Hot restart picks those up.

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

The supervisor runs only when it can own the session safely: a plain JIT
`dart run` on a real terminal. It automatically yields to anything else that
owns the run — an editor debug session (a live VM service), a `fleury serve`
handle, an AOT product build, Windows, a non-TTY, or an injected test driver —
and the app runs exactly as before, no supervisor involved.

Opting out entirely:

```sh
FLEURY_HOT_RELOAD=0 dart run bin/main.dart
```

or `runApp(enableHotReload: false)` — the right setting for production
launches, where it also skips the service-extension registration.

## How it works

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

## Troubleshooting

**Nothing happens when I save** — In a plain `dart run`: check you're on a
real terminal (not a pipe) and that `FLEURY_HOT_RELOAD` isn't `0`. In an
editor debug session: reload-on-save is the editor's job — run **Dart: Hot
Reload** from the command palette, or set `dart.hotReloadOnSave:
"allIfDirty"` (generated projects have it already).

**Reload succeeds but the UI doesn't update** — Check `enableHotReload: true`
(the default) in your `runApp` call.

**"isolate reload failed: missing fields"** — You added a non-nullable field
to a `State` class without a default; the live instance can't be migrated.
Hot restart (`Ctrl+G`, `F5`), or make the field nullable / give it a default.

**Reload succeeded but the tree looks wrong** — Some edits apply but can't
migrate a running tree cleanly (a `StatefulWidget` becoming stateless, a
removed field still referenced). Hot restart.
