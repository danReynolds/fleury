import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { Preview } from './preview.mjs';

function harness(t, options = {}) {
  const listeners = new Set();
  const frames = [];
  globalThis.window = { addEventListener: (_, cb) => listeners.add(cb), removeEventListener: (_, cb) => listeners.delete(cb) };
  globalThis.document = { createElement() {
    const sent = [];
    const attributes = {};
    const frame = { sent, attributes, contentWindow: { postMessage: data => sent.push(data) }, setAttribute(name, value) { attributes[name] = value; }, remove() {} };
    frames.push(frame);
    return frame;
  } };
  const errors = [];
  const preview = new Preview({ replaceChildren() {} }, { onError: error => errors.push(error.message), ...options });
  t.after(() => preview.dispose());
  function message(type, id, frame = frames.at(-1), extra = {}) {
    for (const cb of listeners) cb({ source: frame.contentWindow, data: { sender: 'fleury-pad', type, id, ...extra } });
  }
  async function start() {
    const done = preview.apply({ javascript: 'initial', libraries: ['main'] });
    message('ready');
    message('running', frames.at(-1).sent[0].id);
    await done;
  }
  return { preview, frames, errors, message, start, listeners };
}

test('only sends executable data once and waits for the matching acknowledgement', async t => {
  const { preview, frames, message } = harness(t);
  let finished = false;
  const done = preview.apply({ javascript: 'code', libraries: ['main'], checkpoint: 'private', source: 'private' }).then(() => finished = true);
  const frame = frames[0];
  message('ready'); message('ready');
  assert.equal(frame.sent.length, 1);
  assert.deepEqual(Object.keys(frame.sent[0]).sort(), ['id', 'javascript', 'libraries', 'mode', 'sender']);
  message('running', 99);
  message('reloaded', 1);
  await Promise.resolve();
  assert.equal(finished, false);
  message('running', 1);
  await done;
  assert.equal(preview.canReload, true);
});

test('reload ignores old acknowledgements and rejects overlapping requests', async t => {
  const { preview, message, start } = harness(t);
  await start();
  let finished = false;
  const reload = preview.apply({ javascript: 'delta', libraries: ['main'] }, { reload: true }).then(() => finished = true);
  await assert.rejects(preview.apply({ javascript: 'overlap', libraries: [] }), /already pending/);
  message('reloaded', 1);
  await Promise.resolve();
  assert.equal(finished, false);
  message('reloaded', 2); await reload;
  assert.equal(preview.canReload, true);
});

test('failed application requires restart and old frame messages cannot finish it', async t => {
  const { preview, frames, message, start } = harness(t);
  await start();
  const failure = assert.rejects(preview.apply({ javascript: 'bad', libraries: [] }, { reload: true }), /reassembly failed/);
  message('error', 2, frames[0], { message: 'reassembly failed' });
  await failure;
  assert.equal(preview.canReload, false);
  await assert.rejects(preview.apply({ javascript: 'delta', libraries: [] }, { reload: true }), /Restart/);
  let finished = false;
  const restarted = preview.apply({ javascript: 'fresh', libraries: [] }).then(() => finished = true);
  message('ready', 0, frames[0]); message('running', 3, frames[0]);
  await Promise.resolve();
  assert.equal(finished, false);
  assert.equal(frames[1].sent.length, 0);
  message('ready'); message('running', 3); await restarted;
});

test('a missing acknowledgement times out and leaves restart available', async t => {
  const { preview, message } = harness(t, { timeoutMs: 10 });
  await assert.rejects(preview.apply({ javascript: 'unresponsive', libraries: [] }), /did not finish/);
  assert.equal(preview.pending, null);
  assert.equal(preview.hasFrame, true);
  assert.equal(preview.canReload, false);
  const restarted = preview.apply({ javascript: 'fresh', libraries: [] });
  message('ready'); message('running', 2); await restarted;
});

test('a runtime error invalidates reload once without deleting the preview', async t => {
  const { preview, errors, frames, message, start } = harness(t);
  await start();
  message('error', 1, frames[0], { message: 'app threw' });
  message('error', 1, frames[0], { message: 'duplicate' });
  assert.deepEqual(errors, ['app threw']);
  assert.equal(preview.hasFrame, true);
  assert.equal(preview.canReload, false);
});

test('disposal rejects an outstanding operation and releases the listener', async t => {
  const { preview, listeners } = harness(t);
  const rejection = assert.rejects(preview.apply({ javascript: 'code', libraries: [] }), /closed/);
  preview.dispose(); await rejection;
  assert.equal(listeners.size, 0);
  await assert.rejects(preview.apply({ javascript: 'code', libraries: [] }), /disposed/);
});

function frameHarness(hash = '') {
  const handlers = new Map(), replies = [];
  const parent = { postMessage: data => replies.push(data) };
  const app = { style: {}, append() {} };
  const context = { parent, window: {}, Blob, URL, URLSearchParams, Number, Math, Promise, console,
    location: { hash }, devicePixelRatio: 2,
    getComputedStyle: () => ({ paddingLeft: '16px', paddingRight: '16px', paddingTop: '12px', paddingBottom: '12px' }),
    addEventListener: (name, handler) => handlers.set(name, handler),
    document: { readyState: 'complete', documentElement: {}, getElementById: () => app,
      createElement: () => ({ style: {}, remove() {}, getBoundingClientRect: () => ({ width: 84.2, height: 17.9 }) }),
      head: { append: script => script.onload() } },
    dartDevEmbedder: { hotReload: async () => {}, runMain: () => context.window.fleuryPadReady() },
    app,
  };
  vm.runInNewContext(readFileSync(new URL('./frame.js', import.meta.url), 'utf8'), context);
  const send = (id, mode = 'reload') => handlers.get('message')({ source: parent, data: { sender: 'fleury-editor', id, mode, javascript: 'code', libraries: ['main'] } });
  return { context, handlers, replies, send };
}

test('the frame acknowledges reload only after the Fleury host future completes', async () => {
  const { context, replies, send } = frameHarness();
  let finish, entered;
  const started = new Promise(resolve => entered = resolve);
  context.window.fleuryPadReassemble = () => {
    entered();
    return new Promise(resolve => finish = resolve);
  };
  const reload = send(1);
  await started;
  assert.deepEqual(replies, []);
  finish(); await reload;
  assert.equal(replies[0].type, 'reloaded');
  assert.equal(replies[0].id, 1);
  await send(1); // duplicate delivery must not apply code twice
  assert.equal(replies.length, 1);
});

test('the frame reports reassembly failure without sending success', async () => {
  const { context, replies, send } = frameHarness();
  context.window.fleuryPadReassemble = async () => { throw new Error('host disposed'); };
  await send(1);
  assert.equal(replies.length, 1);
  assert.equal(replies[0].type, 'error');
  assert.match(replies[0].message, /host disposed/);
});

test('a runtime error during reassembly suppresses a later success', async () => {
  const { context, handlers, replies, send } = frameHarness();
  let finish, entered;
  const started = new Promise(resolve => entered = resolve);
  context.window.fleuryPadReassemble = () => {
    entered();
    return new Promise(resolve => finish = resolve);
  };
  const reload = send(1); await started;
  handlers.get('error')({ message: 'runtime failure' });
  finish(); await reload;
  assert.equal(replies.length, 1);
  assert.equal(replies[0].type, 'error');
});

test('runtime asset failures before readiness are reported without waiting for timeout', async t => {
  const { preview, message } = harness(t);
  const failed = assert.rejects(preview.apply({ javascript: 'code', libraries: [] }), /SDK asset failed/);
  message('error', 0, undefined, { message: 'SDK asset failed' });
  await failed;
  assert.equal(preview.pending, null);
});

test('a failure while applying Dart code prevents framework reassembly', async () => {
  const { context, handlers, replies, send } = frameHarness();
  let finish, reassemblies = 0;
  context.dartDevEmbedder.hotReload = () => new Promise(resolve => finish = resolve);
  context.window.fleuryPadReassemble = async () => reassemblies++;
  const reload = send(1);
  handlers.get('error')({ message: 'code update failed' });
  finish(); await reload;
  assert.equal(reassemblies, 0);
  assert.equal(replies.length, 1);
  assert.equal(replies[0].type, 'error');
});


test('docs use the configured compiler frame with an opaque script-only sandbox', async t => {
  const { frames, start } = harness(t, { frameUrl: 'https://compiler.example.com/frame.html' });
  await start();
  assert.equal(frames[0].src, 'https://compiler.example.com/frame.html');
  assert.equal(frames[0].attributes.sandbox, 'allow-scripts');
});

test('a docs frame sizes its app to the requested grid and reports the size', async () => {
  const { context, replies } = frameHarness('#theme=light&cols=10&rows=4');
  await new Promise(resolve => setTimeout(resolve));
  assert.equal(context.document.documentElement.className, 'light');
  // 10 cells of 8.5px (84.2/10 snapped to half pixels) and rows of 18px, plus
  // padding and a pixel of slack against rounding.
  assert.equal(context.app.style.width, '118px');
  assert.equal(context.app.style.height, '97px');
  // Replies are built in the frame's own realm; compare their data.
  assert.deepEqual(JSON.parse(JSON.stringify(replies)), [{ sender: 'fleury-pad', id: 0, type: 'size', width: 118, height: 97 }]);
});

test('a frame without a grid keeps its full size and reports nothing', async () => {
  const { context, replies } = frameHarness('#theme=dark');
  await new Promise(resolve => setTimeout(resolve));
  assert.equal(context.document.documentElement.className, undefined);
  assert.deepEqual(context.app.style, {});
  assert.deepEqual(replies, []);
});

test('the preview resizes its frame to fit a reported grid', async t => {
  const { frames, message, start } = harness(t);
  await start();
  frames[0].style = {};
  message('size', 0, frames[0], { width: 118, height: 97 });
  assert.deepEqual(frames[0].style, { width: '120px', height: '99px' });
});
