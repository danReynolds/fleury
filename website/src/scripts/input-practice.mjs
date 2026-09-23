// Guide-only interaction prompts. The demos remain ordinary Fleury widgets.
export const practiceSteps = {
  'input.editing': [
    ['caret', 'Click to move the caret'],
    ['edit', 'Type something'],
    ['drag', 'Drag over some text'],
    ['extend', 'Extend with Shift-click or Shift+←/→'],
    ['word', 'Double-click a word'],
    ['tab', 'Tab to the other field'],
  ],
  'input.actions': [
    ['open', 'Click Open notes.md'],
    ['secondary', 'Right-click for details'],
    ['keyboard', 'Activate a button with Enter or Space'],
  ],
  'input.press': [
    ['open', 'Press and release the tile'],
    ['cancel', 'Press, then drag to cancel'],
    ['shortcut', 'Press I for details'],
  ],
  'input.splitter': [
    ['drag', 'Drag the divider'],
    ['arrows', 'Resize with ← or →'],
    ['reset', 'Reset the width'],
  ],
  'input.selection': [
    ['select', 'Drag across the note'],
    ['all', 'Select all with Ctrl+A / ⌘A'],
    ['clear', 'Clear with Esc'],
  ],
  'input.scrolling': [
    ['hover', 'Hover over the file row'],
    ['pin', 'Click Pin'],
    ['wheel', 'Scroll inside Recent'],
    ['contain', 'Turn on scroll containment'],
  ],
};

// Event + resulting demo state, not mere presence of a control on the page.
// The text-field gesture prompts record gestures; they do not certify the
// selected text or clipboard. Value/focus/action prompts require an outcome.
export function completedSteps(id, before, after, action) {
  const done = [];
  const pointer = action.kind === 'pointer';
  const primary = pointer && action.button === 0 && !action.drag && action.target === action.endTarget;
  const key = action.kind === 'key' ? action.key : '';
  const unmodified = !action.ctrl && !action.alt && !action.shift;
  const activate = unmodified && (key === 'Enter' || key === ' ');
  const field = after.focus === 'Title' || after.focus === 'Note';
  const movedCaret = field && before.caret !== after.caret;
  switch (id) {
    case 'input.editing':
      if (primary && /^(Title|Note)$/.test(action.target) && movedCaret) done.push('caret');
      if (action.kind === 'input' && before.fields !== after.fields) done.push('edit');
      if (pointer && action.button === 0 && /^(Title|Note)$/.test(action.target) && action.drag && movedCaret) done.push('drag');
      if (action.shift && movedCaret && (primary || /^Arrow(Left|Right|Up|Down)$/.test(key))) done.push('extend');
      if (primary && action.clicks === 2 && /^(Title|Note)$/.test(action.target) && field) done.push('word');
      if (key === 'Tab' && field && before.focus !== after.focus) done.push('tab');
      break;
    case 'input.actions':
      if (primary && action.target === 'Open notes.md' && after.text.includes('Opened notes.md')) done.push('open');
      if (pointer && action.button === 2 && action.target === 'Open notes.md' && action.endTarget === action.target && !action.drag && after.text.includes('Markdown · 2 KB')) done.push('secondary');
      if (activate && /^(Open notes.md|Details)$/.test(before.focus) && /Opened notes.md|Markdown · 2 KB/.test(after.text)) done.push('keyboard');
      break;
    case 'input.press':
      if (primary && action.target === 'Open notes' && after.text.includes('Opened notes.md')) done.push('open');
      if (pointer && action.button === 0 && action.target === 'Open notes' && action.drag && after.text.includes('Cancelled')) done.push('cancel');
      if (unmodified && key.toLowerCase() === 'i' && before.focus === 'Open notes' && after.text.includes('Markdown · 2 KB')) done.push('shortcut');
      break;
    case 'input.splitter':
      if (pointer && action.drag && before.width !== after.width) done.push('drag');
      if ((key === 'ArrowLeft' || key === 'ArrowRight') && before.width !== after.width) done.push('arrows');
      if ((primary || activate) && before.width !== 14 && after.width === 14) done.push('reset');
      break;
    case 'input.selection':
      if (pointer && action.drag && after.selected > 0) done.push('select');
      if (key.toLowerCase() === 'a' && action.ctrl && before.focus !== 'Reply' && after.selected === 'Planning notes\nMeet on Tuesday.\nBring the sketches.'.length) done.push('all');
      if (key === 'Escape' && before.selected > 0 && after.selected === 0) done.push('clear');
      break;
    case 'input.scrolling':
      if (action.kind === 'hover' && after.text.includes('Over the row')) done.push('hover');
      if (primary && after.pins > before.pins) done.push('pin');
      if (action.kind === 'wheel' && action.inRecent && action.delta !== 0) done.push('wheel');
      if (!before.contain && after.contain) done.push('contain');
      break;
  }
  return done;
}

function snapshot(host) {
  const mirror = host.querySelector('[data-fleury-semantic-root]');
  const caret = host.querySelector('[data-fleury-caret-state]');
  const text = mirror?.textContent ?? '';
  return {
    text,
    focus: mirror?.querySelector('[data-fleury-focused="true"][aria-label]')?.getAttribute('aria-label') ?? '',
    caret: `${caret?.getAttribute('data-fleury-caret-col')},${caret?.getAttribute('data-fleury-caret-row')}`,
    fields: Array.from(mirror?.querySelectorAll('input, textarea') ?? [], el => el.value).join('\n'),
    width: Number(mirror?.querySelector('[role="slider"]')?.getAttribute('aria-valuenow')),
    selected: Number(text.match(/(\d+) characters selected/)?.[1] ?? 0),
    pins: Number(text.match(/pins: (\d+)/)?.[1] ?? 0),
    contain: mirror?.querySelector('[role="checkbox"]')?.getAttribute('aria-checked') === 'true',
  };
}

// Hit the semantic bounds using the same monospace pitch as the visible grid.
// Reading these regions keeps the checklist accurate when a demo is expanded.
function hitPoint(host, event) {
  const screen = host.querySelector('.fleury-screen');
  if (!screen) return { target: '', col: -1, row: -1 };
  const style = getComputedStyle(screen);
  const context = document.createElement('canvas').getContext('2d');
  context.font = style.font;
  const pitch = context.measureText('M').width + (parseFloat(style.letterSpacing) || 0);
  const height = parseFloat(style.lineHeight);
  const rect = screen.getBoundingClientRect();
  const col = Math.floor((event.clientX - rect.left) / pitch);
  const row = Math.floor((event.clientY - rect.top) / height);
  let label = '';
  let area = Infinity;
  for (const node of host.querySelectorAll('[data-fleury-bounds-left][aria-label]')) {
    const left = Number(node.getAttribute('data-fleury-bounds-left'));
    const top = Number(node.getAttribute('data-fleury-bounds-top'));
    const width = Number(node.getAttribute('data-fleury-bounds-width'));
    const rows = Number(node.getAttribute('data-fleury-bounds-height'));
    if (col >= left && col < left + width && row >= top && row < top + rows && width * rows < area) {
      label = node.getAttribute('aria-label');
      area = width * rows;
    }
  }
  return { target: label, col, row };
}

// TextPointerSelection counts presses in the same cell within 500 ms. Native
// dblclick is unreliable here: repainting can replace its original DOM target.
export function countFieldClicks(previous, point) {
  return previous && point.target === previous.target && point.col === previous.col &&
    point.row === previous.row && point.time - previous.time < 500 &&
    !point.shift ? (previous.clicks % 3) + 1 : 1;
}

export function attachInputPractice(root) {
  const id = root.dataset.example;
  const steps = practiceSteps[id];
  const host = root.querySelector('.fleury-host');
  if (!steps || !host) return () => {};
  const panel = document.createElement('div');
  panel.className = 'input-practice-panel';
  const header = document.createElement('div');
  header.className = 'input-practice-header';
  const count = document.createElement('span');
  count.setAttribute('role', 'status');
  count.setAttribute('aria-live', 'polite');
  const reset = document.createElement('button');
  reset.type = 'button';
  reset.textContent = 'Reset checklist';
  header.append(count, reset);
  const list = document.createElement('ul');
  list.className = 'input-practice-steps';
  const items = new Map(steps.map(([key, label]) => {
    const item = document.createElement('li');
    item.dataset.step = key;
    const icon = document.createElement('span');
    icon.className = 'input-practice-check';
    icon.setAttribute('aria-hidden', 'true');
    icon.textContent = '○';
    const text = document.createElement('span');
    text.textContent = label;
    item.append(icon, text);
    list.append(item);
    return [key, item];
  }));
  panel.append(header, list);
  root.append(panel);
  const done = new Set();
  let pending;
  let press;
  let selectionEscape;
  let lastFieldPress;
  let frame = 0;
  let disposed = false;
  const abort = new AbortController();
  const options = { capture: true, signal: abort.signal };
  const render = () => {
    count.textContent = done.size === steps.length
      ? `All ${steps.length} explored ✓` : `${done.size} / ${steps.length} explored`;
    for (const [key, item] of items) {
      item.dataset.done = String(done.has(key));
      item.firstChild.textContent = done.has(key) ? '✓' : '○';
      item.setAttribute('aria-label', `${done.has(key) ? 'Completed' : 'Try'}: ${steps.find(step => step[0] === key)[1]}`);
    }
  };
  const evaluate = () => {
    if (disposed || !pending) return;
    const marks = completedSteps(id, pending.before, snapshot(host), pending.action);
    let changed = false;
    for (const mark of marks) if (!done.has(mark)) { done.add(mark); changed = true; }
    if (changed) render();
  };
  const queue = (action, before = snapshot(host)) => {
    evaluate();
    pending = { action, before };
    cancelAnimationFrame(frame);
    // Semantic presentation follows visual presentation. A mutation observer
    // catches its eventual commit; the frame also covers unchanged values.
    frame = requestAnimationFrame(() => { frame = requestAnimationFrame(evaluate); });
  };
  const observer = new MutationObserver(evaluate);
  observer.observe(host, { subtree: true, childList: true, attributes: true, characterData: true });
  const on = (event, callback) => host.addEventListener(event, callback, options);
  on('pointerdown', event => {
    evaluate();
    pending = undefined;
    const point = { ...hitPoint(host, event), time: event.timeStamp, shift: event.shiftKey };
    const clicks = countFieldClicks(lastFieldPress, point);
    if (event.button === 0 && /^(Title|Note)$/.test(point.target)) lastFieldPress = { ...point, clicks };
    else lastFieldPress = undefined;
    press = { before: snapshot(host), ...point, clicks, button: event.button, id: event.pointerId, drag: false };
  });
  on('pointermove', event => {
    if (press && press.id === event.pointerId && event.buttons) {
      const point = hitPoint(host, event);
      press.drag ||= point.col !== press.col || point.row !== press.row;
    } else if (!event.buttons && id === 'input.scrolling') queue({ kind: 'hover' });
  });
  on('pointerup', event => {
    const held = press;
    press = undefined;
    if (!held || held.id !== event.pointerId || held.button !== event.button) return;
    queue({ kind: 'pointer', button: event.button, drag: held.drag, shift: event.shiftKey, clicks: held.clicks, target: held.target, endTarget: hitPoint(host, event).target }, held.before);
  });
  on('dblclick', event => queue({ kind: 'pointer', button: 0, drag: false, clicks: 2, shift: event.shiftKey, target: hitPoint(host, event).target, endTarget: hitPoint(host, event).target }));
  on('pointercancel', () => { press = pending = undefined; });
  on('keydown', event => {
    const before = snapshot(host);
    selectionEscape = id === 'input.selection' && event.key === 'Escape' && before.selected > 0 ? event : undefined;
    queue({ kind: 'key', key: event.key, ctrl: event.ctrlKey || event.metaKey, alt: event.altKey, shift: event.shiftKey }, before);
  });
  // Let the widget clear its selection before the playground sees Escape.
  // This must run during bubbling, after the widget's own input listener.
  host.addEventListener('keydown', event => {
    if (event !== selectionEscape) return;
    event.preventDefault();
    event.stopPropagation();
    selectionEscape = undefined;
  }, { signal: abort.signal });
  // Printable shortcuts also produce beforeinput in some browsers. Only the
  // editing lesson observes text insertion, so it cannot replace an I action.
  if (id === 'input.editing') on('beforeinput', () => queue({ kind: 'input' }));
  on('wheel', event => {
    queue({ kind: 'wheel', delta: event.deltaY, inRecent: hitPoint(host, event).target === 'Recent' });
  });
  reset.addEventListener('click', () => {
    pending = press = lastFieldPress = undefined;
    cancelAnimationFrame(frame);
    done.clear();
    render();
  }, { signal: abort.signal });
  render();
  return () => {
    disposed = true;
    observer.disconnect();
    abort.abort();
    cancelAnimationFrame(frame);
    panel.remove();
  };
}
