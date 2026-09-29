import test from 'node:test';
import assert from 'node:assert/strict';
import { completedSteps, practiceSteps } from '../src/scripts/input-practice.mjs';

const closed = { focus: 'Open notes', noteOpen: false, cancelled: false };
const opened = { ...closed, noteOpen: true };
const click = { kind: 'pointer', button: 0, target: 'Open notes', endTarget: 'Open notes', drag: false };
const key = value => ({ kind: 'key', key: value });

test('opening requires the tile action and a visible note, with either input method', () => {
  assert.deepEqual(completedSteps('input.press', closed, opened, click), ['open']);
  assert.deepEqual(completedSteps('input.press', closed, closed, click), []);
  for (const action of [{ ...click, button: 2 }, { ...click, endTarget: '' }, { ...click, drag: true }]) {
    assert.deepEqual(completedSteps('input.press', closed, opened, action), []);
  }
  for (const value of ['Enter', ' ']) {
    assert.deepEqual(completedSteps('input.press', closed, opened, key(value)), ['open']);
    assert.deepEqual(completedSteps('input.press', closed, opened, { ...key(value), ctrl: true }), []);
    assert.deepEqual(completedSteps('input.press', { ...closed, focus: 'Details' }, opened, key(value)), []);
  }
});

test('cancellation requires an already open note to remain visible', () => {
  const drag = { ...click, drag: true, endTarget: '' };
  const cancelled = { ...opened, cancelled: true };
  assert.deepEqual(completedSteps('input.press', opened, cancelled, drag), ['cancel']);
  assert.deepEqual(completedSteps('input.press', closed, { ...closed, cancelled: true }, drag), []);
  assert.deepEqual(completedSteps('input.press', opened, { ...closed, cancelled: true }, drag), []);
  assert.deepEqual(completedSteps('input.press', opened, opened, drag), []);
  assert.deepEqual(completedSteps('input.press', opened, cancelled, { ...drag, target: '' }), []);
  assert.deepEqual(completedSteps('input.press', opened, cancelled, { ...drag, button: 2 }), []);
});

test('practice is opt-in for this sequence and ignores unrelated input', () => {
  assert.deepEqual(Object.keys(practiceSteps), ['input.press']);
  assert.deepEqual(completedSteps('input.actions', closed, opened, click), []);
  assert.deepEqual(completedSteps('input.press', closed, opened, key('F8')), []);
});
