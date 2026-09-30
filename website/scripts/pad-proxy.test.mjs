import assert from 'node:assert/strict';
import { test } from 'node:test';
import { padProxy } from './pad-proxy.mjs';

function middleware() {
  let handler;
  padProxy('http://127.0.0.1:8080').plugins[0].configureServer({ middlewares: { use(fn) { handler = fn; } } });
  return async (method, path, origin) => {
    const result = {};
    await handler({ method, url: path, headers: { host: '127.0.0.1:4334', ...(origin ? { origin } : {}) } }, {
      writeHead(status, headers) { Object.assign(result, { status, headers }); },
      end(body) { result.body = String(body); },
    }, () => { result.next = true; });
    return result;
  };
}

test('the authenticated proxy rejects foreign origins and arbitrary routes before forwarding', async t => {
  t.mock.method(globalThis, 'fetch', () => { throw new Error('Must not forward'); });
  const request = middleware();
  for (const origin of [undefined, 'null', 'https://evil.test']) {
    assert.equal((await request('POST', '/__pad/api/v3/compileNewDDC', origin)).status, 403);
  }
  assert.equal((await request('GET', '/__pad/private')).status, 403);
  assert.equal((await request('POST', '/__pad/api/v3/unknown', 'http://127.0.0.1:4334')).status, 403);
  assert.equal(globalThis.fetch.mock.callCount(), 0);
});

test('the docs API forwards only to the configured local compiler proxy', async t => {
  const fetch = t.mock.method(globalThis, 'fetch', async () => new Response('{"ok":true}', { headers: {'content-type': 'application/json', 'x-compile-ms': '321'} }));
  const response = await middleware()('POST', '/fleury/__pad/api/v3/compileNewDDC', 'http://127.0.0.1:4334');
  assert.equal(response.status, 200);
  assert.equal(String(fetch.mock.calls[0].arguments[0]), 'http://127.0.0.1:8080/api/v3/compileNewDDC');
  assert.equal(fetch.mock.calls[0].arguments[1].headers.origin, 'http://127.0.0.1:8080');
  assert.equal(response.headers['x-compile-ms'], '321');
});

test('the dev frame loads the matching runtime while retaining network isolation', async t => {
  t.mock.method(globalThis, 'fetch', async () => new Response('<style>@font-face{src:url(fleury-mono.woff2?v=1)}</style><script src="/sdk.js?v=1"></script>', { headers: {
    'content-type': 'text/html', 'x-frame-options': 'SAMEORIGIN',
    'content-security-policy': "default-src 'none'; script-src 'self' blob: 'unsafe-eval'; font-src 'self'; connect-src 'none'",
  } }));
  const response = await middleware()('GET', '/__pad/frame.html');
  assert.equal(response.status, 200);
  assert.match(response.body, /src="http:\/\/127\.0\.0\.1:8080\/sdk.js\?v=1"/);
  assert.match(response.body, /url\(http:\/\/127\.0\.0\.1:8080\/fleury-mono.woff2\?v=1\)/);
  assert.match(response.headers['content-security-policy'], /font-src http:\/\/127\.0\.0\.1:8080;/);
  assert.match(response.headers['content-security-policy'], /connect-src 'none'/);
  assert.match(response.headers['content-security-policy'], /frame-ancestors 'self'/);
  assert.equal(response.headers['x-frame-options'], undefined);
});

test('the dev proxy never accepts a remote target', () => {
  for (const url of ['https://example.com', 'http://example.com', 'http://127.0.0.1:8080/path', 'http://user:secret@127.0.0.1:8080']) {
    assert.throws(() => padProxy(url));
  }
  assert.deepEqual(padProxy(), {});
});
