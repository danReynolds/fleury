// The HTML+JS xterm.js client served by `fleury serve` at `GET /`.
//
// xterm.js is loaded from a CDN for v1 — vendoring it into the
// binary (so `fleury serve` works offline / in air-gapped envs) is a
// polish step for the next slice. The JS implements the same binary
// frame protocol Dart speaks in `remote_protocol.dart` — `fleury
// serve` is therefore a pure byte pump between the WebSocket and the
// app's Unix socket, no protocol translation.

const String serveIndexHtml = r'''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>fleury serve</title>
  <link rel="stylesheet"
        href="https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.min.css">
  <script src="https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10.0/lib/addon-fit.min.js"></script>
  <style>
    html, body { margin: 0; padding: 0; height: 100%; background: #1a1b26; }
    #term { width: 100vw; height: 100vh; padding: 6px; box-sizing: border-box; }
    #status { position: fixed; bottom: 4px; right: 8px; color: #7f7f8a;
              font: 11px/1 ui-monospace, Menlo, monospace; }
  </style>
</head>
<body>
  <div id="term"></div>
  <div id="status">connecting...</div>
  <script>
    // Wire format (mirror of lib/src/remote/remote_protocol.dart):
    //   [ 1 byte type ][ 4 bytes BE length ][ payload ]
    const FRAME = { INIT: 0x01, INPUT: 0x02, RESIZE: 0x03, OUTPUT: 0x10, BYE: 0x11 };

    function encodeFrame(type, payload) {
      const buf = new Uint8Array(5 + payload.length);
      buf[0] = type;
      buf[1] = (payload.length >>> 24) & 0xFF;
      buf[2] = (payload.length >>> 16) & 0xFF;
      buf[3] = (payload.length >>> 8) & 0xFF;
      buf[4] = payload.length & 0xFF;
      buf.set(payload, 5);
      return buf;
    }

    let inbuf = new Uint8Array(0);
    function* drainFrames(chunk) {
      const merged = new Uint8Array(inbuf.length + chunk.length);
      merged.set(inbuf, 0);
      merged.set(chunk, inbuf.length);
      inbuf = merged;
      while (inbuf.length >= 5) {
        const len = (inbuf[1] << 24) | (inbuf[2] << 16) | (inbuf[3] << 8) | inbuf[4];
        if (inbuf.length < 5 + len) break;
        const type = inbuf[0];
        const payload = inbuf.slice(5, 5 + len);
        inbuf = inbuf.slice(5 + len);
        yield { type, payload };
      }
    }

    const term = new Terminal({
      cursorBlink: true,
      fontFamily: 'ui-monospace, Menlo, "Cascadia Code", Consolas, monospace',
      fontSize: 13,
      theme: {
        background: '#1a1b26', foreground: '#c0caf5', cursor: '#c0caf5',
      },
      allowProposedApi: true,
    });
    const fit = new FitAddon.FitAddon();
    term.loadAddon(fit);
    term.open(document.getElementById('term'));
    fit.fit();
    const status = document.getElementById('status');

    const enc = new TextEncoder();
    const dec = new TextDecoder();
    const ws = new WebSocket((location.protocol === 'https:' ? 'wss://' : 'ws://')
                             + location.host + '/ws');
    ws.binaryType = 'arraybuffer';

    ws.onopen = () => {
      status.textContent = 'connected — waiting for app...';
      // INIT: tell the app the canvas size + capabilities. We always
      // advertise truecolor + halfBlock (xterm.js handles SGR; the
      // browser is not a real terminal, so the richer image protocols
      // would render as garbage).
      const init = `cols=${term.cols},rows=${term.rows},color=truecolor,`
                 + `image=halfBlock,tmux=0`;
      ws.send(encodeFrame(FRAME.INIT, enc.encode(init)));
    };

    ws.onmessage = (event) => {
      for (const f of drainFrames(new Uint8Array(event.data))) {
        if (f.type === FRAME.OUTPUT) {
          term.write(dec.decode(f.payload));
          status.textContent = 'connected';
        } else if (f.type === FRAME.BYE) {
          status.textContent = 'app exited';
        }
      }
    };

    ws.onclose = () => { status.textContent = 'disconnected'; };
    ws.onerror = () => { status.textContent = 'connection error'; };

    // Browser → app input.
    term.onData(data => {
      ws.send(encodeFrame(FRAME.INPUT, enc.encode(data)));
    });

    // Window resize → fit xterm.js → notify app.
    let resizeT;
    const onResize = () => {
      clearTimeout(resizeT);
      resizeT = setTimeout(() => {
        fit.fit();
        const r = `cols=${term.cols},rows=${term.rows}`;
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(encodeFrame(FRAME.RESIZE, enc.encode(r)));
        }
      }, 80);
    };
    window.addEventListener('resize', onResize);
  </script>
</body>
</html>
''';
