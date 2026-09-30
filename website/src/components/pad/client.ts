import { monaco, EditorWorker } from './monaco';
import { mountPad } from '../../../../experiments/fleury_pad/dartpad/web/editor.js';
import sample from '../../../../experiments/fleury_pad/lib/main.dart?raw';

const root = document.querySelector<HTMLDialogElement>('.fleury-pad');
if (root) {
  const expand = root.querySelector<HTMLButtonElement>('[data-pad="expand"]')!;
  let expanded = false;
  let previousOverflow = '';
  function setExpanded(value: boolean) {
    if (expanded === value) return;
    expanded = value;
    // Promote the same workspace to the top layer without moving its iframe.
    // This keeps both the editor and the running app alive across layout changes.
    root!.close();
    if (expanded) {
      previousOverflow = document.documentElement.style.overflow;
      document.documentElement.style.overflow = 'hidden';
      root!.setAttribute('role', 'dialog');
      root!.showModal();
    } else {
      root!.open = true;
      root!.setAttribute('role', 'group');
      document.documentElement.style.overflow = previousOverflow;
    }
    expand.setAttribute('aria-expanded', String(expanded));
    expand.title = expanded ? 'Exit fullscreen' : 'Expand workspace';
    expand.setAttribute('aria-label', expanded ? 'Exit fullscreen' : 'Expand workspace');
    expand.focus({ preventScroll: true });
  }
  expand.onclick = () => setExpanded(!expanded);
  root.addEventListener('cancel', event => {
    event.preventDefault();
    setExpanded(false);
  });
  const tabs = [...root.querySelectorAll<HTMLButtonElement>('[data-view]')];
  const show = (view: string) => {
    root.dataset.mode = view;
    for (const tab of tabs) {
      tab.setAttribute('aria-selected', String(tab.dataset.view === view));
      tab.tabIndex = tab.dataset.view === view ? 0 : -1;
    }
  };
  for (const tab of tabs) {
    tab.onclick = () => show(tab.dataset.view!);
    tab.onkeydown = event => {
      if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
      event.preventDefault();
      const next = tabs.find(item => item !== tab)!;
      show(next.dataset.view!); next.focus();
    };
  }
  const preview = root.querySelector<HTMLElement>('[data-pad="preview"]')!;
  const initialPreview = [...preview.childNodes];
  const pad = mountPad(root, {
    monaco, sample, compilerUrl: root.dataset.compiler, frameUrl: root.dataset.frame,
    createWorker: () => new EditorWorker(), autoRunSample: true,
    onRun: () => show('app'),
    onReset: () => preview.replaceChildren(...initialPreview),
  });
  const reset = root.querySelector<HTMLButtonElement>('[data-pad="reset"]')!;
  const start = root.querySelector<HTMLButtonElement>('[data-pad="start"]')!;
  const syncControls = () => {
    const busy = root.dataset.busy === 'true';
    reset.disabled = busy || root.dataset.revertable !== 'true';
    start.disabled = busy;
  };
  const controlsObserver = new MutationObserver(syncControls);
  controlsObserver.observe(root, { attributes: true, attributeFilter: ['data-busy', 'data-revertable'] });
  addEventListener('pagehide', event => { if (!event.persisted) controlsObserver.disconnect(); });
  syncControls();
  reset.onclick = () => {
    pad.revert();
    show('editor');
    root.querySelector<HTMLElement>('[data-pad="status"]')!.textContent = 'Example restored. Run to start fresh.';
    pad.editor.focus();
  };
  start.onclick = () => pad.run();
  root.querySelector<HTMLButtonElement>('[data-pad="download"]')!.onclick = () => {
    const url = URL.createObjectURL(new Blob([pad.editor.getValue()], { type: 'text/plain' }));
    const link = document.createElement('a');
    link.href = url; link.download = 'main.dart'; link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };
  const help = root.querySelector<HTMLDetailsElement>('.pad-help')!;
  root.addEventListener('keydown', event => { if (event.key === 'Escape') help.open = false; });
  root.addEventListener('pointerdown', event => { if (!help.contains(event.target as Node)) help.open = false; });
}
