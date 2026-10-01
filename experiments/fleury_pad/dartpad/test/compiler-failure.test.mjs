import test from 'node:test';
import assert from 'node:assert/strict';
import { PAD_BUSY, compilerFailure } from '../web/editor.js';

test('a busy, restarting or unreachable compiler reads as busy, not as a code error', () => {
  for (const [status, result] of [
    [429, { error: 'Compiler busy. Try again.' }],
    [503, { error: 'Compiler timed out and is restarting. Try again.' }],
    [null, {}],
  ]) {
    const error = compilerFailure(status, result);
    assert.equal(error.message, PAD_BUSY);
    assert.equal(error.code, 'unavailable');
  }
});

test('an unreachable compiler says so when the browser is offline', () => {
  const error = compilerFailure(null, {}, { online: false });
  assert.equal(error.message, 'You are offline. Your code is saved in this browser.');
  assert.equal(error.code, 'unavailable');
  // A response proves the network works, whatever navigator.onLine says.
  assert.equal(compilerFailure(429, {}, { online: false }).message, PAD_BUSY);
});

test("other failures keep the compiler's explanation, code and issues", () => {
  const ddc = "main.dart:36:16: Error: The getter 'missingLabel' isn't defined for the type '_CounterState'.";
  assert.equal(compilerFailure(400, { error: ddc }).message, ddc);
  const issues = [{ kind: 'error', message: 'Undefined name.' }];
  const project = compilerFailure(400, { error: 'Could not compile the project. Check the source errors.', issues });
  assert.equal(project.issues, issues);
  const stale = compilerFailure(400, { error: 'Invalid or expired reload checkpoint. Restart the app.', code: 'checkpoint_rejected' });
  assert.equal(stale.code, 'checkpoint_rejected');
  assert.equal(compilerFailure(409, { error: 'Compiler build changed. Reload the page; your source is saved.' }).message,
    'Compiler build changed. Reload the page; your source is saved.');
  assert.equal(compilerFailure(500, {}).message, 'The compiler returned HTTP 500. Try Run again.');
});
