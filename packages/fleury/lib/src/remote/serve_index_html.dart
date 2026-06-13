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
  <script src="https://cdn.jsdelivr.net/npm/xterm-addon-canvas@0.5.0/lib/xterm-addon-canvas.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10.0/lib/addon-fit.min.js"></script>
  <style>
    html, body { margin: 0; padding: 0; height: 100%; background: #1a1b26; }
    #term { width: 100vw; height: 100vh; padding: 6px; box-sizing: border-box; }
    #term .xterm-rows {
      font-kerning: none;
      font-variant-ligatures: none;
      font-feature-settings: "liga" 0, "clig" 0;
    }
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
    const MAX_FRAME_PAYLOAD = 64 * 1024 * 1024;

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
        const len = new DataView(inbuf.buffer, inbuf.byteOffset, inbuf.byteLength)
          .getUint32(1, false);
        if (len > MAX_FRAME_PAYLOAD) {
          inbuf = new Uint8Array(0);
          throw new Error('frame too large');
        }
        if (inbuf.length < 5 + len) break;
        const type = inbuf[0];
        const payload = inbuf.slice(5, 5 + len);
        inbuf = inbuf.slice(5 + len);
        yield { type, payload };
      }
    }

    const term = new Terminal({
      cursorBlink: true,
      fontFamily: 'Menlo, Consolas, "DejaVu Sans Mono", monospace',
      fontSize: 13,
      letterSpacing: 0,
      customGlyphs: true,
      theme: {
        background: '#1a1b26', foreground: '#c0caf5', cursor: '#c0caf5',
      },
      allowProposedApi: true,
    });
    const fit = new FitAddon.FitAddon();
    if (globalThis.CanvasAddon?.CanvasAddon) {
      term.loadAddon(new CanvasAddon.CanvasAddon());
    }
    term.loadAddon(fit);
    const termElement = document.getElementById('term');
    term.open(termElement);
    // Native runTui hides the terminal cursor by default. The web peer must
    // mirror that mode locally; otherwise xterm's own cursor blinks on top of
    // Fleury-rendered focus/selection state.
    term.write('\x1B[?25l');
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
      try {
        for (const f of drainFrames(new Uint8Array(event.data))) {
          if (f.type === FRAME.OUTPUT) {
            term.write(dec.decode(f.payload));
            status.textContent = 'connected';
          } else if (f.type === FRAME.BYE) {
            status.textContent = 'app exited';
          }
        }
      } catch (e) {
        status.textContent = 'protocol error';
        ws.close(1009, 'frame too large');
      }
    };

    ws.onclose = () => { status.textContent = 'disconnected'; };
    ws.onerror = () => { status.textContent = 'connection error'; };

    function sendInput(data) {
      if (ws.readyState !== WebSocket.OPEN) return;
      ws.send(encodeFrame(FRAME.INPUT, enc.encode(data)));
    }

    // Browser → app input.
    term.onData(data => {
      sendInput(data);
    });

    function mouseCell(event) {
      const screen = termElement.querySelector('.xterm-screen');
      if (!screen || term.cols <= 0 || term.rows <= 0) return null;
      const rect = screen.getBoundingClientRect();
      if (
        event.clientX < rect.left || event.clientX >= rect.right ||
        event.clientY < rect.top || event.clientY >= rect.bottom
      ) {
        return null;
      }
      const cellWidth = rect.width / term.cols;
      const cellHeight = rect.height / term.rows;
      const col = Math.floor((event.clientX - rect.left) / cellWidth) + 1;
      const row = Math.floor((event.clientY - rect.top) / cellHeight) + 1;
      return {
        col: Math.min(term.cols, Math.max(1, col)),
        row: Math.min(term.rows, Math.max(1, row)),
      };
    }

    function buttonCode(button) {
      switch (button) {
        case 0: return 0; // left
        case 1: return 1; // middle
        case 2: return 2; // right
        default: return null;
      }
    }

    function mouseModifiers(event) {
      let mods = 0;
      if (event.shiftKey) mods += 4;
      if (event.altKey) mods += 8;
      if (event.ctrlKey) mods += 16;
      return mods;
    }

    function sendSgrMouse(button, cell, finalByte, event) {
      sendInput(`\x1B[<${button + mouseModifiers(event)};${cell.col};${cell.row}${finalByte}`);
    }

    let pointerButton = null;
    let lastPointerEventAt = 0;

    function rememberPointerEvent(event) {
      if (event.pointerId !== undefined) lastPointerEventAt = Date.now();
    }

    function duplicateMouseEvent(event) {
      return event.type.startsWith('mouse') &&
        Date.now() - lastPointerEventAt < 80;
    }

    // xterm.js only forwards keyboard/paste bytes through `onData` unless a
    // terminal app negotiates browser-side mouse reporting. The remote driver
    // already parses SGR 1006 mouse reports, so synthesize those from browser
    // events and keep pointer behavior consistent with a native terminal.
    function handleMouseDown(event) {
      if (duplicateMouseEvent(event)) return;
      const button = buttonCode(event.button);
      const cell = mouseCell(event);
      if (button === null || cell === null) return;
      event.preventDefault();
      term.focus();
      pointerButton = button;
      rememberPointerEvent(event);
      if (event.pointerId !== undefined) {
        termElement.setPointerCapture?.(event.pointerId);
      }
      sendSgrMouse(button, cell, 'M', event);
    }

    function handleMouseMove(event) {
      if (duplicateMouseEvent(event)) return;
      if (pointerButton === null || event.buttons === 0) return;
      const cell = mouseCell(event);
      if (cell === null) return;
      event.preventDefault();
      rememberPointerEvent(event);
      sendSgrMouse(pointerButton + 32, cell, 'M', event);
    }

    function handleMouseUp(event) {
      if (duplicateMouseEvent(event)) return;
      const button = pointerButton ?? buttonCode(event.button);
      const cell = mouseCell(event);
      if (event.pointerId !== undefined) {
        termElement.releasePointerCapture?.(event.pointerId);
      }
      if (button === null || cell === null) {
        pointerButton = null;
        return;
      }
      event.preventDefault();
      rememberPointerEvent(event);
      sendSgrMouse(button, cell, 'm', event);
      pointerButton = null;
    }

    function handleMouseCancel(event) {
      pointerButton = null;
      if (event.pointerId !== undefined) {
        termElement.releasePointerCapture?.(event.pointerId);
      }
    }

    const mouseCapture = { capture: true };
    termElement.addEventListener('pointerdown', handleMouseDown, mouseCapture);
    termElement.addEventListener('pointermove', handleMouseMove, mouseCapture);
    termElement.addEventListener('pointerup', handleMouseUp, mouseCapture);
    termElement.addEventListener('pointercancel', handleMouseCancel, mouseCapture);
    termElement.addEventListener('mousedown', handleMouseDown, mouseCapture);
    termElement.addEventListener('mousemove', handleMouseMove, mouseCapture);
    termElement.addEventListener('mouseup', handleMouseUp, mouseCapture);
    termElement.addEventListener('mouseleave', handleMouseCancel, mouseCapture);

    termElement.addEventListener('wheel', event => {
      const cell = mouseCell(event);
      if (cell === null) return;
      event.preventDefault();
      term.focus();
      sendSgrMouse(event.deltaY < 0 ? 64 : 65, cell, 'M', event);
    }, { capture: true, passive: false });

    termElement.addEventListener('contextmenu', event => {
      event.preventDefault();
    }, mouseCapture);

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
