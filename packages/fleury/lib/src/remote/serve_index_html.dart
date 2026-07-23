// The page served by `fleury serve` at `GET /`.
//
// It hosts the fleury web renderer — the compiled dart2js client
// (web/remote_client.dart, embedded as remote_client_asset.dart and served
// at `/remote_client.js`). The client speaks the v2 structured protocol:
// it receives presentation plans and renders them through the retained DOM
// surface, and sends structured input back. No terminal emulator, no CDN —
// the whole client ships inside the binary.

/// Path the serve HTTP handler serves the compiled client bundle at.
const String serveClientJsPath = '/remote_client.js';

/// Path the serve HTTP handler serves the embedded subset-JuliaMono woff2 at.
/// The browser surface renders cells as text, so a braille/octant-dense mono
/// (rather than the system Menlo/Consolas, which stipples braille) makes
/// charts and canvas render crisp.
const String serveMonoFontPath = '/fleury-mono.woff2';

const String serveIndexHtml = r'''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>fleury serve</title>
  <style>
    /* Braille/octant-dense mono shipped inside the binary (see
       serve_mono_font_asset.dart) so charts and canvas render crisp instead
       of stippled; falls back to the system mono if it fails to load. */
    @font-face {
      font-family: "FleuryMono";
      font-display: swap;
      src: url("/fleury-mono.woff2") format("woff2");
    }
    html, body { margin: 0; padding: 0; height: 100%; background: #0e0f13; }
    #fleury-remote {
      width: 100vw; height: 100vh; box-sizing: border-box; padding: 6px;
      font: 13px/1.2 "FleuryMono", Menlo, Consolas, "DejaVu Sans Mono", monospace;
      color: #c8d3e0; white-space: pre; overflow: hidden;
      font-kerning: none; font-variant-ligatures: none;
      font-feature-settings: "liga" 0, "clig" 0;
    }
    #status { position: fixed; bottom: 4px; right: 8px; color: #7f7f8a;
              font: 11px/1 ui-monospace, Menlo, monospace; }
  </style>
</head>
<body>
  <div id="fleury-remote" tabindex="0"></div>
  <div id="status">connecting…</div>
  <script>
    const status = document.getElementById('status');
    const obs = new MutationObserver(() => {
      const s = document.body.getAttribute('data-fleury-remote-client');
      if (s) status.textContent = s;
    });
    obs.observe(document.body, { attributes: true,
      attributeFilter: ['data-fleury-remote-client'] });
  </script>
  <script src="/remote_client.js"></script>
</body>
</html>
''';
