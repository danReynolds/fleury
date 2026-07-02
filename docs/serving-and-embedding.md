# Serving and embedding Fleury in the browser

Fleury runs in a browser two different ways. They paint to the **same** DOM
cell-grid surface, so cell output renders identically — inline images are the
one exception (served sessions get true-pixel `<img>` overlays; embedded apps
don't ship the `Image` widget at all). They differ in **where your widget tree
actually executes**:

- **Embed** — compile your app to JavaScript with **dart2js** and run the whole
  widget tree **in the browser**. No server.
- **Serve** — run your app **on a server** (a normal native Dart process) and
  stream the rendered frames to a thin browser client. `fleury serve`.

Both are targets behind the same host SPI; see
[Core and targets](core-and-targets.md) for the layering.

```
 EMBED  (mountApp)                    SERVE  (fleury serve)
 ─────────────────────                ─────────────────────
 dart2js bundle:                      server (native Dart):
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

- **Web-safe widgets only.** Anything that reaches `dart:io` won't compile to JS
  — that's the 8 native-only `fleury_widgets` (file I/O, log capture, process, and the widgets built on them).
  Import `package:fleury/fleury_core.dart`, not `fleury.dart` (see
  [Core and targets](core-and-targets.md#the-web-safety-boundary-practical-rule)).
- **No host machine.** No filesystem, processes, or environment — the browser
  sandbox is all you get.
- The host element needs an explicit CSS size.

**Use it for:** docs examples, marketing demos, self-contained web tools,
offline apps, or anything that should deploy as a static asset.

---

## Serve — `fleury serve` (remote)

`fleury serve` runs your app as a normal **native** Dart process and proxies its
rendering to the browser. The server holds the real widget tree; on each frame
its remote driver emits **cell-diff + semantics frames** over a WebSocket, and a
small dart2js client in the browser paints them into the same DOM cell grid and
sends input events back.

```sh
# Run any fleury app and open it in a browser at http://127.0.0.1:5777
fleury serve --spawn dart run my_app.dart

# Exposed beyond localhost — set a token and share the URL with it
fleury serve --port=8080 --host=0.0.0.0 \
             --allow-origin=https://example.com \
             --token=$(openssl rand -hex 16) \
             --spawn dart run my_app.dart
# → share http://<host>:8080/?token=<secret>
```

`--spawn` runs your app as a subprocess, isolated per browser connection.

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
- **`--token=<secret>`.** Requires `?token=` on the WebSocket URL (the served
  page forwards its own `?token=` query automatically). This is the gate that
  covers non-browser clients and other local users; always set it when the
  host is not loopback. Prefer HTTPS/WSS termination in front (a reverse
  proxy) so the token and session aren't readable on the wire.

For anything beyond a trusted network, put the port behind the access control
you already trust — an SSH tunnel (`ssh -L 5777:localhost:5777 …`), a VPN, or
an authenticating reverse proxy.

**Properties**

- **Full fidelity.** The app is the real native program, so *every* widget works
  — including the `dart:io`-backed ones (`FileBrowser`, `Image`, `ProcessPanel`,
  log/terminal regions). It has a filesystem, processes, and environment.
- **Shareable.** A running terminal app becomes a URL — remote sessions, live
  demos of the actual program, pairing.
- The wire is tuned: cell-range patches with a style table and varints,
  DEFLATE-compressed, semantics diffed separately, with backpressure and
  resize/input DoS clamps.

**Constraints**

- **Needs a running server** — one native process per session. That means
  hosting, capacity planning, and startup cost (mitigated by warm-standby
  pre-spawning), not a free static asset.
- **Network latency** sits between input and paint.

**Use it for:** remote access to a real tool, demos of a full app (with file or
process access), sharing a session, anything that genuinely needs the host
machine.

---

## Which do I want?

| | **Embed** (`mountApp`) | **Serve** (`fleury serve`) |
|---|---|---|
| Widget tree runs… | in the browser (dart2js) | on a server (native Dart) |
| Backend required | **none** — static asset | a running process per session |
| Scaling | static/CDN asset | one process per user |
| `dart:io` widgets (files/process/log) | ❌ no | ✅ yes |
| Host machine access | ❌ sandbox only | ✅ full |
| Latency | local | network round-trip |
| Offline | ✅ | ❌ |
| Best for | docs, demos, self-contained web apps | remote sessions, full-fidelity apps |

Rule of thumb: **if it can run in the browser sandbox, embed it** — it deploys
and scales like a static web asset. **Reach for serve when the app needs the real
machine** (files, processes, the host environment) or when you want to expose an
existing native session over a URL.

Because both paths drive the same DOM cell-grid presenter, you can start by
embedding and move to serve later (or offer both) without changing your app.
