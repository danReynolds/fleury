import test from 'node:test';
import assert from 'node:assert/strict';
import { mountPad } from '../web/editor.js';

function createPad(t) {
  const source = 'void main() {\n  unknownName();\n}\n';
  const elements = new Map();
  const root = { dataset: {}, querySelector(selector) {
    const id = selector.match(/data-pad="([^"]+)"/)[1];
    if (!elements.has(id)) {
      const attributes = new Map();
      elements.set(id, { textContent: '', hidden: id === 'progress', dataset: {},
        setAttribute: (name, value) => attributes.set(name, value),
        getAttribute: name => attributes.get(name) ?? null,
        removeAttribute: name => attributes.delete(name),
        replaceChildren(...children) { this.children = children; },
      });
    }
    return elements.get(id);
  } };
  let value = source;
  const listeners = new Set();
  const model = {
    getValue: () => value,
    setValue(next) { value = next; for (const listener of listeners) listener(); },
    onDidChangeContent(listener) {
      listeners.add(listener);
      return { dispose: () => listeners.delete(listener) };
    },
    dispose() {},
  };
  const disposable = () => ({ dispose() {} });
  const monaco = {
    editor: {
      defineTheme() {}, setTheme() {}, setModelMarkers() {}, createModel: () => model,
      create: () => ({ addCommand() {}, dispose() {} }),
    },
    languages: { registerCompletionItemProvider: disposable, registerHoverProvider: disposable },
    KeyMod: { CtrlCmd: 1 }, KeyCode: { Enter: 2, KeyS: 4 },
  };
  const drafts = new Map();
  const queue = [];
  function exchange() {
    let receive, respond;
    const request = new Promise(resolve => { receive = resolve; });
    const response = new Promise(resolve => { respond = resolve; });
    queue.push({ receive, response });
    return { request, respond: (body, status = 200) => respond(Response.json(body, { status })) };
  }
  const first = exchange();
  const sent = [];
  const globals = {
    self: {},
    window: new EventTarget(),
    document: { documentElement: { dataset: {} }, createElement(tag) {
      assert.equal(tag, 'iframe');
      return { style: {}, setAttribute() {}, remove() {},
        contentWindow: { postMessage: message => sent.push(message) } };
    } },
    MutationObserver: class { observe() {} disconnect() {} },
    addEventListener() {},
    localStorage: {
      getItem: key => drafts.get(key) ?? null,
      setItem: (key, value) => drafts.set(key, value),
      removeItem: key => drafts.delete(key),
    },
    async fetch(url, options) {
      if (url === 'https://compiler.test/api/build') {
        return Response.json({ buildId: 'test-build' });
      }
      if (url.endsWith('/analyze')) return Response.json({ issues: [] });
      assert.match(url, /\/api\/v3\/compileNewDDC(Reload)?$/);
      const next = queue.shift();
      assert.ok(next, 'the test must prepare a compiler response');
      next.receive(JSON.parse(options.body));
      return next.response;
    },
  };
  const originals = new Map(Object.keys(globals).map(key => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
  let pad;
  t.after(() => {
    pad?.dispose();
    for (const [key, original] of originals) {
      if (original) Object.defineProperty(globalThis, key, original);
      else delete globalThis[key];
    }
  });
  for (const [key, value] of Object.entries(globals)) {
    Object.defineProperty(globalThis, key, { value, configurable: true, writable: true });
  }
  pad = mountPad(root, { monaco, sample: source, compilerUrl: 'https://compiler.test', deferLanguageServices: true });
  function message(type, id = sent.at(-1)?.id, extra = {}) {
    const event = new Event('message');
    Object.assign(event, { source: elements.get('preview').children[0].contentWindow,
      data: { sender: 'fleury-pad', type, id, ...extra } });
    window.dispatchEvent(event);
  }
  return { pad, root, model, elements, source, exchange, message, sent,
    request: first.request, respond: first.respond, fail() {
    first.respond({ error: 'Compilation failed', issues: [{
      file: 'main.dart', message: "Undefined name 'unknownName'.",
      location: { charStart: source.indexOf('unknownName'), charLength: 11, line: 2 },
    }] }, 400);
  } };
}

for (const editWhilePending of [false, true]) {
  test(`single-file compiler diagnostics ${editWhilePending ? 'use the submitted source after an edit' : 'remain visible and release the Run button'}`, async t => {
    const { pad, root, model, elements, source, request, fail } = createPad(t);
    const run = pad.run();
    assert.deepEqual(await request, { source });
    assert.equal(root.dataset.busy, 'true');
    assert.equal(elements.get('progress').hidden, false);
    assert.equal(elements.get('progress').dataset.phase, 'compiling');
    if (editWhilePending) model.setValue(`// Added while compiling\n\n${source}`);
    fail();
    await assert.doesNotReject(run);
    assert.equal(elements.get('diagnostics').hidden, false);
    assert.equal(elements.get('diagnostics').textContent, "main.dart:2:3: Undefined name 'unknownName'.");
    assert.equal(elements.get('status').textContent, 'Could not compile. Fix the error or try Run again.');
    assert.equal(root.dataset.busy, 'false');
    assert.equal(elements.get('run').disabled, false);
    assert.equal(elements.get('progress').dataset.phase, 'error');
    assert.equal(elements.get('progress').getAttribute('aria-valuenow'), null);
    if (editWhilePending) assert.equal(root.dataset.modified, 'true');
  });
}

const compiled = { result: 'compiled program', deltaDill: 'checkpoint' };
const flush = () => new Promise(resolve => setImmediate(resolve));

test('reload progress waits for app acknowledgement and survives an earlier completion timer', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const { pad, model, source, elements, request, respond, exchange, message, sent } = createPad(t);
  const progress = elements.get('progress');
  const initial = pad.run();
  await request;
  respond(compiled);
  await flush();
  assert.equal(progress.dataset.phase, 'applying');
  assert.equal(progress.getAttribute('aria-valuenow'), null);
  message('ready');
  message('running');
  await initial;
  assert.equal(progress.dataset.phase, 'complete');
  assert.equal(progress.getAttribute('aria-valuenow'), '100');

  const next = exchange();
  model.setValue(source + '// edited');
  const reload = pad.run();
  assert.equal((await next.request).deltaDill, 'checkpoint');
  assert.equal(progress.dataset.phase, 'compiling');
  assert.equal(progress.getAttribute('aria-valuenow'), null);
  t.mock.timers.tick(1600);
  await flush();
  assert.equal(progress.hidden, false, 'the previous completion cannot hide a new reload');
  next.respond(compiled);
  await flush();
  assert.equal(sent.at(-1).mode, 'reload');
  assert.equal(progress.dataset.phase, 'applying');
  assert.equal(progress.getAttribute('aria-valuenow'), null, 'compiler success is not app readiness');
  message('reloaded', sent.at(-1).id - 1);
  assert.equal(progress.dataset.phase, 'applying', 'ignore an old app acknowledgement');
  message('reloaded');
  await reload;
  assert.equal(progress.dataset.phase, 'complete');
  assert.equal(progress.getAttribute('aria-valuenow'), '100');
  t.mock.timers.tick(1600);
  assert.equal(progress.hidden, true);
  assert.equal(elements.get('status').textContent, 'Hot reloaded. The app is ready.');
});

test('an app update failure stops the animation without reporting completion', async t => {
  const { pad, root, elements, request, respond, message } = createPad(t);
  const run = pad.run();
  await request;
  respond(compiled);
  await flush();
  message('ready');
  message('error', undefined, { message: 'Reassembly failed' });
  await run;
  assert.equal(root.dataset.busy, 'false');
  assert.equal(elements.get('progress').dataset.phase, 'error');
  assert.equal(elements.get('progress').getAttribute('aria-valuenow'), null);
  assert.equal(elements.get('diagnostics').textContent, 'Reassembly failed');
});

test('disposing during compilation hides progress and ignores the late response', async t => {
  const { pad, elements, request, respond } = createPad(t);
  const run = pad.run();
  await request;
  pad.dispose();
  assert.equal(elements.get('progress').hidden, true);
  respond(compiled);
  await run;
  assert.equal(elements.get('progress').hidden, true);
  assert.equal(elements.get('preview').children, undefined);
});
