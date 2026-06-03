import React from 'react';
import {Box, Text} from 'ink';
import TextInput from 'ink-text-input';
import {TextArea} from 'react-ink-textarea';

export const defaultColumns = 120;
export const defaultRows = 32;
export const selectionNeedle = 'segment-alpha';
export const selectionReplacement = 'selection-replaced';
export const secretValue = 'secret-ink-sb2';
export const completionQuery = 'git che';
export const completionAccepted = 'git checkout';
export const pasteMarker = 'paste-marker-final';

export function mixedText(targetChars) {
  const target = Math.max(256, targetChars);
  const parts = [
    'segment-beta ascii words ',
    'cafe\u0301 combining mark ',
    '界面 表格 入力 ',
    'emoji🙂 cursor ',
    'line-wrap sample text\n'
  ];
  let value = `${selectionNeedle} ascii words `;
  while ([...value].length < target) {
    for (const part of parts) {
      value += part;
      if ([...value].length >= target) {
        break;
      }
    }
  }
  return value;
}

export function largePasteText() {
  return `${'paste🙂界 cafe\u0301 '.repeat(128)}${pasteMarker}`;
}

export class InkSb2Fixture {
  constructor({textChars = 10000, columns = defaultColumns, rows = defaultRows} = {}) {
    this.textChars = textChars;
    this.columns = columns;
    this.rows = rows;
    this.editorValue = mixedText(textChars);
    this.cursorOffset = [...this.editorValue].length;
    this.composerValue = completionQuery;
    this.secretValue = secretValue;
    this.undoStack = [];
    this.redoStack = [];
    this.undoValue = '';
    this.redoValue = '';
    this.history = ['status --short', 'git branch --show-current', completionQuery];
    this.historyPos = -1;
    this.lastHistory = '';
  }

  cursorMove() {
    for (let index = 0; index < 24; index += 1) {
      this.cursorOffset = Math.max(0, this.cursorOffset - 1);
    }
    for (let index = 0; index < 12; index += 1) {
      this.cursorOffset = Math.min([...this.editorValue].length, this.cursorOffset + 1);
    }
    const lines = this.editorValue.split('\n');
    const lineIndex = Math.max(0, lines.length - 2);
    const offsetAtLine = lines.slice(0, lineIndex).join('\n').length + (lineIndex > 0 ? 1 : 0);
    this.cursorOffset = Math.min([...this.editorValue].length, offsetAtLine + Math.min(8, [...lines[lineIndex]].length));
  }

  insertionDeletion() {
    const runes = [...this.editorValue];
    const insertAt = Math.min(this.cursorOffset, runes.length);
    runes.splice(insertAt, 0, 'x');
    runes.splice(insertAt, 1);
    this.editorValue = runes.join('');
    this.cursorOffset = insertAt;
  }

  replaceSelection() {
    this.recordUndo();
    const start = [...this.editorValue.slice(0, this.editorValue.indexOf(selectionNeedle))].length;
    const end = start + [...selectionNeedle].length;
    this.editorValue = replaceRuneRange(this.editorValue, start, end, selectionReplacement);
    this.cursorOffset = start + [...selectionReplacement].length;
  }

  undo() {
    if (this.undoStack.length === 0) {
      return;
    }
    const current = this.editorValue;
    const previous = this.undoStack.pop();
    this.redoStack.push(current);
    this.editorValue = previous;
    this.undoValue = previous;
    this.cursorOffset = [...previous].length;
  }

  redo() {
    if (this.redoStack.length === 0) {
      return;
    }
    const current = this.editorValue;
    const next = this.redoStack.pop();
    this.undoStack.push(current);
    this.editorValue = next;
    this.redoValue = next;
    this.cursorOffset = [...next].length;
  }

  historyPrevious() {
    if (this.historyPos < 0 || this.historyPos > this.history.length) {
      this.historyPos = this.history.length;
    }
    if (this.historyPos > 0) {
      this.historyPos -= 1;
    }
    this.composerValue = this.history[this.historyPos];
    this.lastHistory = this.composerValue;
  }

  acceptCompletion() {
    this.composerValue = completionQuery;
    if (completionAccepted.startsWith(this.composerValue)) {
      this.composerValue = completionAccepted;
    }
  }

  pasteLargeText() {
    const runes = [...this.editorValue];
    const insertAt = Math.min(this.cursorOffset, runes.length);
    runes.splice(insertAt, 0, ...largePasteText());
    this.editorValue = runes.join('');
    this.cursorOffset = insertAt + [...largePasteText()].length;
  }

  stateSnapshot({frame = ''} = {}) {
    const editorValue = this.editorValue;
    const secretVisible = frame.includes(secretValue);
    return {
      editorLength: [...editorValue].length,
      editorLineCount: editorValue.split('\n').length,
      composerValue: this.composerValue,
      secretRawVisible: secretVisible,
      mixedWidthValid: mixedWidthValid(editorValue),
      selectionReplacementValid: editorValue.includes(selectionReplacement) && !editorValue.includes(selectionNeedle),
      undoRedoCorrect: this.undoValue.includes(selectionNeedle) && this.redoValue.includes(selectionReplacement),
      historyNavigationCorrect: this.lastHistory === 'git branch --show-current',
      completionAccepted: this.composerValue === completionAccepted,
      pasteInserted: editorValue.includes(pasteMarker)
    };
  }

  recordUndo() {
    this.undoStack.push(this.editorValue);
    this.redoStack = [];
  }
}

export function InkSb2App({fixture}) {
  return React.createElement(
    Box,
    {flexDirection: 'column', width: fixture.columns},
    React.createElement(Text, null, 'Ink SB.2 Text Editing'),
    React.createElement(TextArea, {
      focus: false,
      value: fixture.editorValue,
      onChange: () => {},
      onSubmit: () => {},
      viewportLines: Math.max(4, Math.min(16, fixture.rows - 8)),
      cursorInterval: 999999,
      maxUndo: 128,
      keybindings: {'Enter': false}
    }),
    React.createElement(
      Box,
      null,
      React.createElement(Text, null, 'composer: '),
      React.createElement(TextInput, {
        value: fixture.composerValue,
        onChange: () => {},
        focus: false,
        showCursor: false
      })
    ),
    React.createElement(
      Box,
      null,
      React.createElement(Text, null, 'secret: '),
      React.createElement(TextInput, {
        value: fixture.secretValue,
        onChange: () => {},
        focus: false,
        showCursor: false,
        mask: '*'
      })
    )
  );
}

function mixedWidthValid(value) {
  return value.includes('cafe\u0301') &&
    value.includes('界面') &&
    value.includes('emoji🙂');
}

function replaceRuneRange(value, start, end, replacement) {
  const runes = [...value];
  const low = Math.max(0, Math.min(start, runes.length));
  const high = Math.max(low, Math.min(end, runes.length));
  runes.splice(low, high - low, ...replacement);
  return runes.join('');
}
