// Optional practice for the press lifecycle: an action, then a cancelled attempt.
// Ordinary demos use FleuryExample without tasks (see website/README.md).
export const practiceSteps = {
  'input.press': [
    ['open', 'Open the note'],
    ['cancel', 'Cancel another press; keep the note open'],
  ],
};

export function completedSteps(id, before, after, action) {
  if (id !== 'input.press') return [];
  const pointer = action.kind === 'pointer' && action.button === 0 && action.target === 'Open notes';
  const click = pointer && !action.drag && action.endTarget === action.target;
  const activate = action.kind === 'key' && !action.ctrl && !action.alt && !action.shift &&
    (action.key === 'Enter' || action.key === ' ') && before.focus === 'Open notes';
  const done = [];
  if ((click || activate) && after.noteOpen) done.push('open');
  if (pointer && action.drag && before.noteOpen && after.noteOpen && after.cancelled) done.push('cancel');
  return done;
}

function snapshot(host) {
  const mirror = host.querySelector('[data-fleury-semantic-root]');
  const text = mirror?.textContent ?? '';
  return {
    focus: mirror?.querySelector('[data-fleury-focused="true"][aria-label]')?.getAttribute('aria-label') ?? '',
    noteOpen: text.includes('Bring the sketches.'),
    cancelled: text.includes('Cancelled'),
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
    press = { before: snapshot(host), ...hitPoint(host, event), button: event.button, id: event.pointerId, drag: false };
  });
  on('pointermove', event => {
    if (press && press.id === event.pointerId && event.buttons) {
      const point = hitPoint(host, event);
      press.drag ||= point.col !== press.col || point.row !== press.row;
    }
  });
  on('pointerup', event => {
    const held = press;
    press = undefined;
    if (!held || held.id !== event.pointerId || held.button !== event.button) return;
    queue({ kind: 'pointer', button: event.button, drag: held.drag, target: held.target, endTarget: hitPoint(host, event).target }, held.before);
  });
  on('pointercancel', () => { press = pending = undefined; });
  on('keydown', event => queue({ kind: 'key', key: event.key, ctrl: event.ctrlKey || event.metaKey, alt: event.altKey, shift: event.shiftKey }));
  reset.addEventListener('click', () => {
    pending = press = undefined;
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
