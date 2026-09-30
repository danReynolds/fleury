// Development only: keep credentials in the authenticated Cloud Run proxy.
// Forward only the compiler API and sandbox runtime, never arbitrary URLs.
export function padProxy(target) {
  if (!target) return {};
  const url = new URL(target);
  if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' || url.pathname !== '/' || url.search || url.hash || url.username || url.password) {
    throw new Error('FLEURY_PAD_PROXY_TARGET must be an HTTP 127.0.0.1 origin.');
  }
  const methods = new Set(['compileNewDDC', 'compileNewDDCReload', 'analyze', 'complete', 'format', 'document']);
  const assets = new Set(['/api/build', '/frame.html']);
  return { plugins: [{
    name: 'fleury-pad-local-proxy',
    configureServer(server) {
      server.middlewares.use(async (req, res, next) => {
        // Astro removes its base before Vite's development middleware.
        const route = req.url?.match(/^\/(?:fleury\/)?__pad(\/[^?]*)$/);
        if (!route) return next();
        const path = route[1];
        const origin = req.headers.origin;
        const sameOrigin = origin === `http://${req.headers.host}`;
        const localHost = /^127\.0\.0\.1:\d+$/.test(req.headers.host ?? '');
        const routeAllowed = (req.method === 'GET' && assets.has(path)) ||
          (req.method === 'POST' && path.startsWith('/api/v3/') && methods.has(path.slice(8)) && sameOrigin);
        if (!localHost || (origin && !sameOrigin) || !routeAllowed) {
          res.writeHead(403, { 'content-type': 'application/json' });
          res.end(JSON.stringify({ error: 'Use the local Fleury docs page to access this compiler.' }));
          return;
        }
        try {
          const headers = { origin: url.origin };
          for (const name of ['content-type', 'x-fleury-build']) if (req.headers[name]) headers[name] = req.headers[name];
          const response = await fetch(new URL(path, url), {
            method: req.method, headers,
            ...(req.method === 'POST' ? { body: req, duplex: 'half' } : {}),
            signal: AbortSignal.timeout(65000),
          });
          const outgoing = { 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' };
          for (const name of ['content-type', 'content-security-policy', 'x-compile-ms', 'x-fleury-precompiled', 'retry-after']) {
            if (response.headers.has(name)) outgoing[name] = response.headers.get(name);
          }
          let body = Buffer.from(await response.arrayBuffer());
          if (path === '/frame.html') {
            // Runtime scripts and the font come from the compiler, not the
            // Astro dev server. Opaque sandbox subresources are correctly
            // rejected by Astro.
            body = Buffer.from(body.toString().replaceAll('src="/', `src="${url.origin}/`)
              .replaceAll('url(fleury-mono.woff2', `url(${url.origin}/fleury-mono.woff2`));
            outgoing['content-security-policy'] = outgoing['content-security-policy']
              .replace("script-src 'self'", `script-src ${url.origin}`)
              .replace("font-src 'self'", `font-src ${url.origin}`) + "; frame-ancestors 'self'";
          }
          res.writeHead(response.status, outgoing); res.end(body);
        } catch {
          res.writeHead(503, { 'content-type': 'application/json' });
          res.end(JSON.stringify({ error: 'Could not reach the compiler. Check the local Cloud Run proxy and try again.' }));
        }
      });
    },
  }] };
}
