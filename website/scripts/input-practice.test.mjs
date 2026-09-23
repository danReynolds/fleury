import test from 'node:test';
import assert from 'node:assert/strict';
import { completedSteps, practiceSteps, countFieldClicks } from '../src/scripts/input-practice.mjs';

const ready = { focus: 'Title', caret: '1,2', fields: 'Ada', text: '', width: 14, selected: 0, noteOpen: false, hovered: false, pinned: false };
const click = { kind: 'pointer', button: 0, drag: false, target: 'Title', endTarget: 'Title' };
const key = value => ({ kind: 'key', key: value });

test('editing requires a gesture and a changed caret, text, or focus', () => {
  assert.deepEqual(completedSteps('input.editing', ready, ready, click), []);
  const moved = { ...ready, caret: '4,2' };
  assert.deepEqual(completedSteps('input.editing', ready, moved, click), ['caret']);
  assert.deepEqual(completedSteps('input.editing', ready, moved, { ...click, drag: true }), ['drag']);
  assert.deepEqual(completedSteps('input.editing', ready, moved, { ...click, shift: true }), ['caret', 'extend']);
  assert.deepEqual(completedSteps('input.editing', ready, ready, { ...click, clicks: 2 }), ['word']);
  assert.deepEqual(completedSteps('input.editing', ready, ready, key('Tab')), []);
  assert.deepEqual(completedSteps('input.editing', ready, { ...ready, focus: 'Note' }, key('Tab')), ['tab']);
  assert.deepEqual(completedSteps('input.editing', ready, { ...ready, fields: 'Ada!' }, { kind: 'input' }), ['edit']);
  assert.deepEqual(completedSteps('input.editing', ready, ready, { kind: 'input' }), []);
});

test('button prompts require opening by pointer and closing by keyboard', () => {
  const opened = { ...ready, focus: 'Close note', noteOpen: true };
  const action = { ...click, target: 'Open note', endTarget: 'Open note' };
  assert.deepEqual(completedSteps('input.actions', ready, opened, action), ['open']);
  assert.deepEqual(completedSteps('input.actions', ready, ready, action), []);
  assert.deepEqual(completedSteps('input.actions', ready, opened, { ...action, target: '', endTarget: '' }), []);
  assert.deepEqual(completedSteps('input.actions', ready, opened, { ...action, endTarget: '' }), []);
  assert.deepEqual(completedSteps('input.actions', ready, opened, { ...action, drag: true }), []);
  assert.deepEqual(completedSteps('input.actions', ready, opened, { ...action, button: 2 }), []);
  assert.deepEqual(completedSteps('input.actions', opened, ready, key('Enter')), ['keyboard']);
  assert.deepEqual(completedSteps('input.actions', opened, opened, key('Enter')), []);
  assert.deepEqual(completedSteps('input.actions', opened, ready, key(' ')), ['keyboard']);
  assert.deepEqual(completedSteps('input.actions', { ...opened, focus: '' }, ready, key('Enter')), []);
});

test('custom tile needs a reported cancellation or shortcut result', () => {
  const drag = { ...click, target: 'Open notes', drag: true };
  const cancelled = { ...ready, text: 'Cancelled' };
  assert.deepEqual(completedSteps('input.press', ready, ready, drag), []);
  assert.deepEqual(completedSteps('input.press', ready, cancelled, drag), ['cancel']);
  assert.deepEqual(completedSteps('input.press', cancelled, cancelled, { ...drag, target: '' }), []);
  const before = { ...ready, focus: 'Open notes' };
  const details = { ...before, text: 'notes.md · Markdown · 2 KB' };
  assert.deepEqual(completedSteps('input.press', before, details, key('i')), ['shortcut']);
  assert.deepEqual(completedSteps('input.press', details, details, { ...key('i'), ctrl: true }), []);
});

test('splitter needs a changed width; reset needs a nondefault starting width', () => {
  assert.deepEqual(completedSteps('input.splitter', ready, ready, key('ArrowRight')), []);
  const wider = { ...ready, width: 18 };
  assert.deepEqual(completedSteps('input.splitter', ready, wider, key('ArrowRight')), ['arrows']);
  assert.deepEqual(completedSteps('input.splitter', ready, wider, { ...click, drag: true }), ['drag']);
  assert.deepEqual(completedSteps('input.splitter', wider, ready, key('Enter')), ['reset']);
  assert.deepEqual(completedSteps('input.splitter', ready, ready, key('Enter')), []);
});

test('selection needs selected text and excludes select-all in Reply', () => {
  const selected = { ...ready, focus: '', selected: 12 };
  const all = { ...selected, selected: 'Planning notes\nMeet on Tuesday.\nBring the sketches.'.length };
  assert.deepEqual(completedSteps('input.selection', ready, selected, { ...click, drag: true }), ['select']);
  assert.deepEqual(completedSteps('input.selection', selected, all, { ...key('a'), ctrl: true }), ['all']);
  assert.deepEqual(completedSteps('input.selection', { ...selected, focus: 'Reply' }, all, { ...key('a'), ctrl: true }), []);
  assert.deepEqual(completedSteps('input.selection', selected, ready, key('Escape')), ['clear']);
  assert.deepEqual(completedSteps('input.selection', ready, ready, key('Escape')), []);
});

test('nested input prompts require the parent hover and child action together', () => {
  const hovered = { ...ready, hovered: true };
  const hoverPin = { kind: 'hover', target: 'Pin' };
  assert.deepEqual(completedSteps('input.nesting', ready, ready, hoverPin), []);
  assert.deepEqual(completedSteps('input.nesting', ready, hovered, hoverPin), ['hover']);
  assert.deepEqual(completedSteps('input.nesting', ready, hovered, { kind: 'hover', target: '' }), []);
  const pin = { ...click, target: 'Pin', endTarget: 'Pin' };
  const pinned = { ...hovered, pinned: true };
  assert.deepEqual(completedSteps('input.nesting', hovered, pinned, pin), ['pin']);
  assert.deepEqual(completedSteps('input.nesting', hovered, { ...pinned, hovered: false }, pin), []);
  assert.deepEqual(completedSteps('input.nesting', pinned, pinned, pin), []);
  assert.deepEqual(completedSteps('input.nesting', hovered, hovered, pin), []);
});

test('every exercise has distinct steps and ignores unrelated input', () => {
  for (const [id, steps] of Object.entries(practiceSteps)) {
    assert.equal(new Set(steps.map(([key]) => key)).size, steps.length);
    assert.deepEqual(completedSteps(id, ready, ready, key('F8')), []);
  }
});

test('field press counting survives repaints and follows terminal cell boundaries', () => {
  const first = { target: 'Note', col: 14, row: 6, time: 100, clicks: 1 };
  assert.equal(countFieldClicks(first, { ...first, time: 240 }), 2);
  assert.equal(countFieldClicks({ ...first, clicks: 2 }, { ...first, time: 300 }), 3);
  assert.equal(countFieldClicks(first, { ...first, time: 601 }), 1);
  assert.equal(countFieldClicks(first, { ...first, row: 5, time: 240 }), 1);
  assert.equal(countFieldClicks(first, { ...first, col: 15, time: 240 }), 1);
  assert.equal(countFieldClicks(first, { ...first, time: 240, shift: true }), 1);
});

test('Shift arrows extend in either field but plain arrows do not', () => {
  for (const focus of ['Title', 'Note']) {
    const before = { ...ready, focus };
    const after = { ...before, caret: '5,6' };
    for (const arrow of ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown']) {
      assert.deepEqual(completedSteps('input.editing', before, after, { ...key(arrow), shift: true }), ['extend']);
      assert.deepEqual(completedSteps('input.editing', before, after, key(arrow)), []);
    }
    assert.deepEqual(completedSteps('input.editing', before, before, { ...key('ArrowLeft'), shift: true }), []);
  }
});
