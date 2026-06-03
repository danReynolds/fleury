import test from 'node:test';
import assert from 'node:assert/strict';
import React from 'react';
import {render} from 'ink-testing-library';
import {
  InkSb2App,
  InkSb2Fixture,
  completionAccepted
} from '../lib/text_editing_app.js';

test('Ink SB.2 fixture renders and exercises editor adapters', () => {
  const fixture = new InkSb2Fixture({textChars: 2000});
  const rendered = render(React.createElement(InkSb2App, {fixture}));

  assert.match(rendered.lastFrame(), /Ink SB\.2 Text Editing/);
  assert.equal(rendered.lastFrame().includes('secret-ink-sb2'), false);
  assert.equal(fixture.stateSnapshot({frame: rendered.lastFrame()}).mixedWidthValid, true);

  fixture.cursorMove();
  fixture.insertionDeletion();
  fixture.replaceSelection();
  let snapshot = fixture.stateSnapshot();
  assert.equal(snapshot.selectionReplacementValid, true);

  fixture.undo();
  fixture.redo();
  snapshot = fixture.stateSnapshot();
  assert.equal(snapshot.undoRedoCorrect, true);

  fixture.historyPrevious();
  fixture.historyPrevious();
  snapshot = fixture.stateSnapshot();
  assert.equal(snapshot.historyNavigationCorrect, true);

  fixture.acceptCompletion();
  snapshot = fixture.stateSnapshot();
  assert.equal(snapshot.completionAccepted, true);
  assert.equal(snapshot.composerValue, completionAccepted);

  fixture.pasteLargeText();
  rendered.rerender(React.createElement(InkSb2App, {fixture}));
  snapshot = fixture.stateSnapshot({frame: rendered.lastFrame()});
  assert.equal(snapshot.pasteInserted, true);
  assert.equal(snapshot.mixedWidthValid, true);
  assert.equal(snapshot.secretRawVisible, false);

  rendered.unmount();
});
