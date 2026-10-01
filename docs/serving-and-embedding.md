# Serving and embedding Fleury in the browser

Fleury runs in a browser two different ways. They paint to the **same** DOM
cell-grid surface, and both support inline images as true-pixel `<img>`
overlays. Embeds supply images through `Image.bytes` or `Image.decoded`;
`Image.file` stays native-only. They differ in **where your widget tree
actually executes**:

- **Embed** — compile your app to JavaScript with **dart2js** and run the whole
  widget tree **in the browser**. No server.
- **Serve** — run your app as a **native Dart process** and stream the rendered
  frames to a thin browser client. `fleury serve` is primarily a local preview
  and debugging bridge.

Both are targets behind the same host SPI; see
[Core and targets](core-and-targets.md) for the layering.

```
 EMBED  (mountApp)                    SERVE  (fleury serve)
 ─────────────────────                ─────────────────────
 dart2js bundle:                      local native process:
   widget tree                          widget tree  ← runs here
   Fleury core                          Fleury core
   fleury_web DOM host                  remote driver → cell-diff frames
        │                                        │  WebSocket
        ▼ runs in the browser                    ▼
   paints DOM cell grid               thin dart2js client paints DOM cell grid
        ▲                                        ▲
   browser events ┘                    browser events ┘ (sent back over the socket)
```

---

## Embed — `mountApp` (client-side)

dart2js compiles your widget tree **plus** the Fleury core **plus** the
`fleury_web` DOM host into one JS bundle. The whole program runs in the browser;
the DOM host paints the `CellBuffer` into retained DOM rows and feeds browser
keyboard/mouse/input back into the framework.

```dart
// web/main.dart — compiled with: dart compile js web/main.dart -o app.js
import 'package:fleury_web/fleury_web.dart';
import 'package:web/web.dart' as web;

void main() {
  final host = web.document.querySelector('#app')! as web.Element;
  mountApp(() => const MyApp(), into: host);
}
```

```html
<!-- the host element must have a real size + monospace metrics, or the
     grid computes 0×0 and paints nothing -->
<div id="app" style="width:80ch;height:24em;font-family:monospace"></div>
<script src="app.js"></script>
```

<!-- fleury-example: linechart.basic 60x16 | Embedded right here in these docs: the real LineChart widget, compiled with dart2js, running client-side in your browser. -->

**Properties**

- **No backend.** The bundle is a static asset — ship it on any CDN, scale it
  like a normal web asset, and support offline use.
- **Self-contained.** Drop a widget into an existing web page (the docs site
  embeds live examples this exact way).

**Constraints**

- **Web-safe code only.** Code that reaches `dart:io` fails in the browser:
  dart2js compiles it, but the call throws when it runs. Every widget in
  `fleury_core.dart` includes the web-safe catalog; `FileBrowser` and `FilePicker` read a
  `FileSource` you pass (such as a `MemoryFileSource`), since there is no local
  disk to list. Import `package:fleury/fleury_core.dart`, not `fleury.dart`
  (see [Core and targets](core-and-targets.md#the-web-safety-boundary)).
- **No host machine.** No filesystem, processes, or environment — the browser
  sandbox is all you get.
- The host element needs an explicit CSS size.

**Use it for:** docs examples, marketing demos, self-contained web tools,
offline apps, or anything that should deploy as a static asset.

---

## Serve — `fleury serve` (local bridge)

`fleury serve` requires macOS or Linux: its connection to the native app uses
Unix-domain sockets. The Windows terminal driver does not support this path.

`fleury serve` carries a **native** Dart app's rendering to the browser. The
native process holds the real widget tree. Its remote driver emits visual
cell-diff frames over a WebSocket; semantic updates are diffed and sent
separately when the exposed tree or its painted coverage changes. A small
dart2js client in the browser paints the visual frames into the same DOM cell
grid and sends input events back.

There are two lifecycle models:

- **Bridge mode** (no `--spawn`) attaches one app process that you start and
  accepts one browser at a time. Close that browser before connecting another;
  a second simultaneous browser is rejected. It is useful for IDE-driven
  debugging and local demos.
- **Spawn mode** (`--spawn <command …>`) owns an isolated app subprocess per
  browser connection and keeps a warm standby so reconnects start quickly.

```sh
# Run any fleury app and open it in a browser at http://127.0.0.1:5777
fleury serve --spawn dart run bin/run_app.dart

# Advanced: exposed on a trusted network. A network bind always requires a
# token: pass --token, or serve generates one and prints it in the URL.
fleury serve --port=8080 --host=0.0.0.0 \
             --allow-origin=https://example.com \
             --spawn dart run bin/run_app.dart
# → open the printed http://<host>:8080/?token=<secret>
```

`--spawn` selects the isolated, managed-process model. Without it, `serve`
waits for the single bridge-mode app session instead.

### Hot reload in the browser

`serve` does not add a VM service to the command it spawns, and the dev
supervisor deliberately yields to a serve handle — so the plain `--spawn dart
run bin/run_app.dart` above gives you **no** hot reload. Enable the service in
the spawn command itself and saving a source file reloads the app behind the
browser preview:

```sh
fleury serve --spawn dart --enable-vm-service=0 run bin/run_app.dart
```

`=0` lets the VM pick a free port. Reload only; hot **restart** stays
unavailable under a serve handle, because a respawned child would re-dial the
handle's single-accept socket and wedge the session. `serve` will not inject
the flag for you: a VM service is a debug port, and opening one is the
operator's decision, not a side effect of asking for a browser preview.

Two more controls must appear before `--spawn`:

- `--max-sessions=<n>` (spawn mode only) caps concurrent browser sessions
  (default `8`). A
  browser that arrives at the cap is turned away after the WebSocket upgrade
  with close code `4001` and a reason the page shows in its banner, so the cap
  is visible to the user rather than a blank grid.
- `--debug` exposes frame timings, captured logs, and full error details over
  the debug wire. It is off unless explicitly requested, in both spawn and
  bridge mode.

### Trust model

**Anyone who can open the WebSocket owns the app.** The wire carries full
control — key and text injection, semantic actions, and the app's (redacted)
semantic tree. There is no user-account layer; `fleury serve` gives you three
gates and nothing else:

- **Bind address.** The default `--host=127.0.0.1` keeps the port
  loopback-only. Binding anything else prints a warning and exposes the app to
  every peer that can reach the port.
- **Origin check.** WebSocket upgrades are same-origin by default;
  `--allow-origin` adds origins. This stops *cross-site browser pages* from
  attaching — it does not stop non-browser clients, which simply omit the
  Origin header.
- **Token.** `--token=<secret>` requires `?token=` on the WebSocket URL (the
  served page forwards its own `?token=` query automatically, and the startup
  banner prints the full URL). This is the gate that covers non-browser
  clients and other local users. A bind that is not loopback never runs
  without one: when `--token` is absent, `serve` generates a random 128-bit
  token for the run. Prefer HTTPS/WSS termination in front (a reverse proxy)
  so the token and session aren't readable on the wire.

`fleury serve` is not a hardened public hosting layer. For anything beyond a
trusted network, keep it on loopback and put it behind access control you
already trust — an SSH tunnel (`ssh -L 5777:localhost:5777 …`), a VPN, or an
authenticating reverse proxy.

**Properties**

- **Full fidelity.** The app is the real native program, with a filesystem,
  processes, and environment: `FileBrowser` and `FilePicker` read the real
  disk, `TerminalOutputRegion` shows captured output, and `Image.file` works.
- **Browser-visible.** A running terminal app becomes a local URL for preview,
  debugging, and trusted pairing.
- The wire is tuned: cell-range patches with a style table and varints,
  DEFLATE-compressed, semantics diffed separately, with backpressure and
  resize/input DoS clamps.

**Constraints**

- **Needs a running native process** — one app with one connected browser in
  bridge mode, or one managed subprocess per connection in spawn mode. The
  spawn pool's warm standby reduces reconnect latency but still carries process
  startup and memory costs.
- **Network latency** sits between input and paint.
- **Not public hosting.** Origin and token checks are useful local/trusted-network
  safeguards, not a user-account or internet-service security boundary.

**Use it for:** local browser previews of a full app (including file or process
access), debugging, and deliberately trusted remote pairing.

---

## Which do I want?

| | **Embed** (`mountApp`) | **Serve** (`fleury serve`) |
|---|---|---|
| Widget tree runs… | in the browser (dart2js) | in a local native Dart process |
| Backend required | **none** — static asset | one native app process (manually started in bridge mode; managed per connection in spawn mode) |
| Scaling | static/CDN asset | one browser at a time (bridge) or one process per connection (spawn) |
| File and log widgets | Browser-safe data sources | Host files, processes, and logs |
| Host machine access | ❌ sandbox only | ✅ full |
| Latency | local | network round-trip |
| Offline | ✅ | ❌ |
| Best for | docs, demos, self-contained web apps | local preview and trusted full-fidelity sessions |

Rule of thumb: **if it can run in the browser sandbox, embed it** — it deploys
and scales like a static web asset. **Reach for serve during development when a
browser preview needs the real machine** (files, processes, the host environment)
or for a deliberately trusted remote pairing session.

Because both paths drive the same DOM cell-grid presenter, the reusable widget
tree and application logic can move between them unchanged. The host entrypoint
and imports still differ: an embed calls `mountApp` from web-safe code, while a
served app keeps its native `runApp` entrypoint.
