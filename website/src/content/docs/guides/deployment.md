---
title: Deployment & distribution
description: Ship a Fleury app as a terminal binary or in-browser bundle, and preview native apps with the local serve bridge.
---

The same app can ship as a native terminal program or a self-contained browser
bundle. During development, `fleury serve` can also mirror a native process into
a browser.

| You want to… | Use |
|---|---|
| Ship a command-line tool | A native executable built with `dart compile exe` |
| Put the app on a web page | A browser bundle: `mountApp` compiled with `dart compile js` |
| Preview a native app in a browser during development | `fleury serve` |

For *how* the browser paths work under the hood, see
[Serving and embedding](/fleury/architecture/serving-and-embedding/).

## Ship a terminal app

In development, run the entry point directly:

```sh
dart run bin/run_app.dart
```

To distribute, compile to a **single native executable** — no Dart SDK needed on
the target machine. A Fleury app AOT-compiles like any Dart program; there's no
special build step:

```sh
dart compile exe bin/run_app.dart -o my_app
./my_app
```

That binary is the whole app. Build it on each operating system you ship for,
run it once in a real terminal before release, and distribute it like any CLI
tool. The supported baseline is a modern UTF-8, xterm-compatible terminal on
macOS or Linux; the Windows driver is a preview.

### Pipes, CI, and cron

`runApp` needs a terminal. When standard output is piped or redirected
(`my_app | less`, a CI job, cron), it throws before drawing anything, with
"runApp needs an interactive terminal", rather than write screen-control codes
into the output. If people will script your command, give it a plain-output
path that doesn't call `runApp`, chosen by a flag such as `--plain` or by
checking `stdout.hasTerminal` from `dart:io`.

A `stdout.hasTerminal` check is also false when `fleury serve` or `fleury_mcp`
runs the app, or an IDE runs it for `fleury shell`: the app draws over a socket
there, and its standard output isn't a terminal. Prefer a flag if you use
those tools. `runApp(requireInteractiveTerminal: false)` turns the check off,
but the frames Fleury draws then go into the pipe as escape codes; it's meant
for capturing that stream.

### Debug tooling in shipped apps

The debug shell (`Ctrl+G`), its `F12` logs, and the agent debug tools
(`read_frames`, `read_logs`, `read_errors`) are on when the app runs from a
`.dart` source file or with assertions enabled. They're off in the builds you
ship: AOT executables and snapshots (`dart pub global activate` installs an
app from pub.dev or Git as a snapshot). With the tooling off, your app's own
`Ctrl+G` and `F12` bindings work. To choose for yourself, pass a `DebugConfig`
to `runApp`:

```dart
await runApp(const MyApp(), debug: const DebugConfig(enabled: false));
```

`enabled: false` keeps the tooling off during development too; `enabled: true`
turns it on in a compiled build, such as one an agent drives. See
[Debugging](/fleury/guides/debugging/#configuring-it).

## Ship a browser bundle

The *same* widget tree compiles to JavaScript and runs client-side, with no
server. [Getting started](/fleury/getting-started/#6-optional-ship-a-browser-bundle)
walks through the three pieces: a web-safe library for the app, which imports
`package:fleury/fleury_core.dart` (including the full catalog) and never
`dart:io`; a
`web/main.dart` that mounts it with [`mountApp`](/fleury/concepts/app-entry/);
and a `web/index.html` whose host element has an explicit width and height and
a monospace font. Without a size, the grid measures zero cells and paints
nothing; without a monospace font, the cells misalign. Then compile:

```sh
dart compile js web/main.dart -o web/app.js -O2
```

### Host it

The site is `web/index.html` and `web/app.js`. The compiler also writes
`app.js.map`, a source map that browser developer tools use to show your Dart
source, and `app.js.deps`, a list of the compiler's inputs. Publish the map if
you want to debug the deployed page; the site doesn't need the `.deps` file.
If your code uses deferred imports, publish the `app.js_*.part.js` files too.

Any static host works — GitHub Pages, Netlify, an object store behind a CDN,
or an ordinary web server — with no server-side code or WebSocket to run.
Keep `app.js` next to `index.html` (or change the script's `src`). If the host
caches files for a long time, give the bundle a new name with each release so
browsers load the new one. To mount the app inside an existing page or
single-page app, give it any sized element; keep the handle `mountApp` returns
and call `dispose()` on it when that view goes away.

A client-side bundle runs in the browser sandbox, with no local disk,
processes, or environment. Every widget in
`package:fleury/fleury_core.dart` runs there; `FileBrowser` and
`FilePicker` read a `FileSource` you pass (such as a `MemoryFileSource`)
instead of the disk. Code that reaches `dart:io` still compiles with dart2js,
but throws when it runs. To try an app that needs the local machine in a
browser, use `serve` instead.

## Preview a native app with `serve`

The socket-based tools — `fleury serve`, `fleury shell`, and `fleury_mcp` —
require macOS or Linux. They reach the app over a Unix-domain socket, which
the Dart SDK supports only on Linux, macOS, and Android.

`fleury serve` carries a **native** app's rendered frames to a browser over a
WebSocket, painting into a DOM cell grid. (The `fleury` command comes from the
CLI — [install it](#installing-the-fleury-cli) first if you haven't.) It is
primarily a local preview and debugging bridge. The app keeps full `dart:io`
access, so file widgets read the real disk and captured output shows up.

In **spawn mode**, `serve` starts a fresh app process for every browser tab,
with a warm standby so reconnects start quickly:

```sh
# The VM-service flag is what makes save-to-reload work in the browser:
fleury serve --spawn dart --enable-vm-service=0 run bin/run_app.dart
```

In **bridge mode** (no `--spawn`), `serve` waits for an app you start
yourself. Run `fleury serve` in the app's package directory and open the URL it
prints. Then start the app from that directory (`dart run bin/run_app.dart`)
or an IDE debugger, or from anywhere with the `FLEURY_HANDLE=…` value `serve`
prints: the app finds the running `serve` and draws in the browser instead of
the terminal. Bridge mode serves one browser at a time. While a session is
live, another browser is turned away with a message to close the first one or
use `--spawn`.

Flags (put them *before* `--spawn`, which greedily consumes everything after it
as the command to run):

| Flag | Default | Meaning |
|---|---|---|
| `--port=<n>` | `5777` | Port to listen on; `0` chooses a free port |
| `--host=<addr>` | `127.0.0.1` | Bind address (`0.0.0.0` to expose) |
| `--allow-origin=<origin>` | same-origin | Allow an embedding origin, or `*` |
| `--token=<secret>` | none on loopback; generated otherwise | Require `?token=<secret>` on the WebSocket |
| `--debug` | off | Expose frame, log, and full error diagnostics |
| `--max-sessions=<n>` | `8` | Cap concurrent browser sessions in spawn mode |
| `--spawn <cmd …>` | bridge mode | Spawn an isolated process per connection |

The default bind address is loopback. A bind that is not loopback always
requires a token: pass `--token`, or `serve` generates one for the run and
prints the URL that carries it. If you deliberately expose it on a trusted
network, also choose explicit origins, and prefer a trusted tunnel or
authenticating reverse proxy. `serve` is not a hardened public hosting layer:
any client that passes its gates can drive the app and read its redacted
semantic tree.

## Embed or serve?

| | Embed (`mountApp`) | Serve (`fleury serve`) |
|---|---|---|
| Where it runs | In the browser | A native process on the host |
| Backend needed | None — static files | Yes — the running app |
| Host resources | None — the browser sandbox | The host's disk, processes, and captured output |
| Sessions | Every page load runs its own copy | One browser at a time (bridge) or one process per tab (spawn) |
| Use when | It fits the browser sandbox | Local preview needs the real machine |

Rule of thumb: ship an embed when it can run in the sandbox; use `serve` during
development when the preview needs the host — the filesystem, a process, or real
`dart:io`.

## Installing the `fleury` CLI

`fleury create`, `run`, `serve`, `shell`, and `diagnose` come from the `fleury`
CLI; `serve` and `shell` run on macOS and Linux.
While Fleury is pre-release it isn't on pub.dev yet. Install it directly from
Git:

```sh
dart pub global activate --source git \
  https://github.com/danReynolds/fleury.git \
  --git-path packages/fleury
```

That puts `fleury` on your `PATH`. From the root of a local Fleury checkout, you
can instead use `dart pub global activate --source path packages/fleury`, or run
the source executable from `packages/fleury`: `dart run bin/fleury.dart serve …`.

Until the packages are published, create an app with Git dependencies:

```sh
fleury create my_app --dependency-source=git
```

> **Release status.** Fleury is pre-1.0 and not yet published to pub.dev; apps
> depend on it via git or path dependencies (as in [Getting
> started](/fleury/getting-started/)). `fleury create` already defaults to
> hosted dependencies, which resolve only once the packages are published, so
> pass `--dependency-source=git` until then. The normal
> `dart pub global activate fleury` path also arrives with publication.
