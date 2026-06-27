---
title: Deployment & distribution
description: Ship a Fleury app — as a terminal binary, an in-browser bundle, or a served web app.
---

The same app can ship three ways: as a native terminal program, as a
self-contained browser bundle, or served to browsers from a running process.
This guide covers the commands for each; for *how* the browser paths work under
the hood, see [Serving and embedding](/architecture/serving-and-embedding/).

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
[`mountApp`](/concepts/app-entry/):

```dart
// web/main.dart
import 'package:fleury_web/fleury_web.dart';
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
offline, scale it for free. The one constraint: a client-side bundle can only use
**web-safe widgets**. The handful that need the platform (file pickers, the log
and process panels, anything touching `dart:io`) won't compile to JS — import
`package:fleury_widgets/fleury_widgets_web.dart` rather than the full barrel, and
the compiler will hold you to it. For those, use serve instead.

## Serve it

`fleury serve` runs your **native** app and streams its rendered frames to a
browser over a WebSocket, painting into a DOM cell grid. The app keeps full
`dart:io` access — every widget works, including the native-only ones — and the
URL is shareable:

```sh
# Run the app yourself and bridge one browser session to it:
fleury serve --spawn dart run my_app.dart
```

Flags (put them *before* `--spawn`, which greedily consumes everything after it
as the command to run):

| Flag | Default | Meaning |
|---|---|---|
| `--port=<n>` | `5777` | Port to listen on |
| `--host=<addr>` | `127.0.0.1` | Bind address (`0.0.0.0` to expose) |
| `--allow-origin=<origin>` | same-origin | Allow an embedding origin, or `*` |
| `--spawn <cmd …>` | bridge mode | Spawn an isolated process per connection |

There are two models. **Bridge mode** (no `--spawn`) serves a single shared
session — good for a local demo or IDE-driven debugging. **Spawn mode**
(`--spawn dart run my_app.dart`) gives every browser connection its own isolated
subprocess — "your TUI as a multi-user web app" — with a warm-standby pool so new
sessions start fast. For production spawn mode, point it at an AOT binary
(`--spawn ./my_app`) rather than `dart run` to cut per-session startup.

```sh
fleury serve --port=8080 --host=0.0.0.0 --allow-origin=https://example.com --spawn ./my_app
```

## Embed or serve?

| | Embed (`mountApp`) | Serve (`fleury serve`) |
|---|---|---|
| Where it runs | In the browser | A native process |
| Backend needed | None — static asset | Yes — the running app |
| Widgets | Web-safe only | All, incl. file/process/log |
| Scaling | Free (CDN) | One process per session |
| Use when | It fits the browser sandbox | It needs the real machine |

Rule of thumb: if it can run in the sandbox, embed it; reach for serve when the
app needs the host — the filesystem, a process, real `dart:io`.

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
> started](/getting-started/)). Published packages, a Homebrew tap, and a
> `create-fleury-app` scaffold are planned for after the API stabilizes.
