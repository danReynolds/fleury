---
title: Deployment & distribution
description: Ship a Fleury app as a terminal binary or in-browser bundle, and preview native apps with the local serve bridge.
---

The same app can ship as a native terminal program or a self-contained browser
bundle. During development, `fleury serve` can also mirror a native process into
a browser. This guide covers each path; for *how* the browser paths work under
the hood, see [Serving and embedding](/fleury/architecture/serving-and-embedding/).

## Ship a terminal app

In development, run the entry point directly:

```sh
dart run bin/my_app.dart
```

To distribute, compile to a **single native executable** — no Dart SDK needed on
the target machine. A Fleury app AOT-compiles like any Dart program; there's no
special build step:

```sh
dart compile exe bin/my_app.dart -o my_app
./my_app
```

That binary is the whole app. Ship it like any CLI tool.

## Run it in a browser (embed)

The *same* widget tree compiles to JavaScript and runs client-side — no server.
Write a tiny web entry point that mounts your app with
[`mountApp`](/fleury/concepts/app-entry/):

```dart
// web/main.dart
import 'package:fleury/fleury_core.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';
import 'package:web/web.dart' as web;

void main() {
  final host = web.document.getElementById('app')!;
  mountApp(() => const MyApp(), into: host);
}
```

Compile it with `dart2js`:

```sh
dart compile js web/main.dart -o web/app.js -O2
```

Then load the bundle and give it a host element with an **explicit size and a
monospace font** — without those, the grid measures zero cells and paints
nothing:

```html
<div id="app" style="width:80ch;height:24em;font-family:monospace"></div>
<script src="app.js"></script>
```

The output is a static `.js` file — host it on any CDN or static site, ship it
offline, and scale it like a normal web asset. The one constraint: a client-side
bundle can only use **web-safe widgets**. The handful that need the platform
(file pickers, the log and process panels, anything touching `dart:io`) won't
compile to JS — import `package:fleury_widgets/fleury_widgets_web.dart` rather
than the full barrel, and the compiler will hold you to it. To preview those
widgets in a browser during development, use `serve` instead.

## Preview a native app with `serve`

`fleury serve` carries a **native** app's rendered frames to a browser over a
WebSocket, painting into a DOM cell grid. In spawn mode it starts and owns the
app process; in bridge mode it attaches to an app that you start. It is
primarily a local preview and debugging bridge. The app keeps full `dart:io`
access, so every widget works, including the native-only ones:

```sh
# Spawn a fresh app process for each browser session:
fleury serve --spawn dart run my_app.dart
```

Flags (put them *before* `--spawn`, which greedily consumes everything after it
as the command to run):

| Flag | Default | Meaning |
|---|---|---|
| `--port=<n>` | `5777` | Port to listen on |
| `--host=<addr>` | `127.0.0.1` | Bind address (`0.0.0.0` to expose) |
| `--allow-origin=<origin>` | same-origin | Allow an embedding origin, or `*` |
| `--token=<secret>` | none | Require `?token=<secret>` on the WebSocket |
| `--debug` | off | Expose frame, log, and full error diagnostics in spawn mode |
| `--max-sessions=<n>` | `8` | Cap concurrent browser sessions in spawn mode |
| `--spawn <cmd …>` | bridge mode | Spawn an isolated process per connection |

There are two models. **Bridge mode** (no `--spawn`) serves a single shared
session — good for a local demo or IDE-driven debugging. **Spawn mode**
(`--spawn dart run my_app.dart`) gives every browser connection its own isolated
subprocess, with a warm standby so reconnects start quickly.

The default bind address is loopback. If you deliberately expose it on a trusted
network, set `--token`, choose explicit origins, and prefer a trusted tunnel or
authenticating reverse proxy. `serve` is not a hardened public hosting layer:
any client that passes its gates can drive the app and read its redacted
semantic tree.

## Embed or serve?

| | Embed (`mountApp`) | Serve (`fleury serve`) |
|---|---|---|
| Where it runs | In the browser | A native process |
| Backend needed | None — static asset | Yes — the running app |
| Widgets | Web-safe only | All, incl. file/process/log |
| Scaling | Static/CDN asset | One shared app (bridge) or one process per connection (spawn) |
| Use when | It fits the browser sandbox | Local preview needs the real machine |

Rule of thumb: ship an embed when it can run in the sandbox; use `serve` during
development when the preview needs the host — the filesystem, a process, or real
`dart:io`.

## Installing the `fleury` CLI

`fleury serve` (and `shell`, `diagnose`) come from the `fleury` CLI. While Fleury
is pre-release it isn't on pub.dev yet, so install it from a local checkout:

```sh
dart pub global activate --source path packages/fleury
```

That puts `fleury` on your `PATH`. Without installing, you can always run it
directly: `dart run packages/fleury/bin/fleury.dart serve …`.

> **Release status.** Fleury is pre-1.0 and not yet published to pub.dev; apps
> depend on it via git or path dependencies (as in [Getting
> started](/fleury/getting-started/)). Published packages, a Homebrew tap, and a
> `create-fleury-app` scaffold are planned for after the API stabilizes.
