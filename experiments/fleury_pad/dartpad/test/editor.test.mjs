import test from 'node:test';
import assert from 'node:assert/strict';
import { mountPad } from '../web/editor.js';

function compilerFailure(t) {
  const source = 'void main() {\n  unknownName();\n}\n';
  const elements = new Map();
  const root = { dataset: {}, querySelector(selector) {
    const id = selector.match(/data-pad="([^"]+)"/)[1];
    if (!elements.has(id)) elements.set(id, { textContent: '', hidden: false });
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
      defineTheme() {}, setTheme() {}, createModel: () => model,
      create: () => ({ addCommand() {}, dispose() {} }),
    },
    languages: { registerCompletionItemProvider: disposable, registerHoverProvider: disposable },
    KeyMod: { CtrlCmd: 1 }, KeyCode: { Enter: 2, KeyS: 4 },
  };
  const drafts = new Map();
  let sendFailure, receivedRequest;
  const response = new Promise(resolve => { sendFailure = resolve; });
  const request = new Promise(resolve => { receivedRequest = resolve; });
  const globals = {
    self: {},
    window: new EventTarget(),
    document: { documentElement: { dataset: {} } },
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
      assert.equal(url, 'https://compiler.test/api/v3/compileNewDDC');
      receivedRequest(JSON.parse(options.body));
      return response;
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
  return { pad, root, model, elements, source, request, fail() {
    sendFailure(Response.json({ error: 'Compilation failed', issues: [{
      file: 'main.dart', message: "Undefined name 'unknownName'.",
      location: { charStart: source.indexOf('unknownName'), charLength: 11, line: 2 },
    }] }, { status: 400 }));
  } };
}

for (const editWhilePending of [false, true]) {
  test(`single-file compiler diagnostics ${editWhilePending ? 'use the submitted source after an edit' : 'remain visible and release the Run button'}`, async t => {
    const { pad, root, model, elements, source, request, fail } = compilerFailure(t);
    const run = pad.run();
    assert.deepEqual(await request, { source });
    assert.equal(root.dataset.busy, 'true');
    if (editWhilePending) model.setValue(`// Added while compiling\n\n${source}`);
    fail();
    await assert.doesNotReject(run);
    assert.equal(elements.get('diagnostics').hidden, false);
    assert.equal(elements.get('diagnostics').textContent, "main.dart:2:3: Undefined name 'unknownName'.");
    assert.equal(elements.get('status').textContent, 'Could not compile. Fix the error or try Run again.');
    assert.equal(root.dataset.busy, 'false');
    assert.equal(elements.get('run').disabled, false);
    if (editWhilePending) assert.equal(root.dataset.modified, 'true');
  });
}
