// Wires every GuidePad on the page: the editor mounts as the demo nears the
// viewport, so the code is editable without an activation step. Compilation
// waits for the reader's first Run; the prebuilt preview runs until then.
type Pad = {
  editor: any;
  select(id: string, options?: { focus?: boolean }): void;
  revert(): void;
};
type ExampleApi = Window & {
  fleuryUnmountExample?: (host: Element) => void;
  fleuryMountExamples?: () => void;
};

for (const root of document.querySelectorAll<HTMLDialogElement>('.guide-pad')) {
  if (root.dataset.wired) continue;
  root.dataset.wired = 'true';
  const $ = <T extends HTMLElement>(selector: string) => root.querySelector<T>(selector)!;
  const project = JSON.parse($<HTMLScriptElement>('[data-project]').textContent!);
  const marks: number[] = JSON.parse(root.dataset.marks ?? '[]');
  const tabs = [...root.querySelectorAll<HTMLButtonElement>('[data-guide-view]')];
  const previewPane = $<HTMLElement>('[data-pad="preview"]');
  let current = project.views[0].id;
  let pad: Pad | undefined;
  let loading: Promise<void> | undefined;
  let expanded = false, previousOverflow = '';
  // The prebuilt example, kept aside while the reader's own run replaces it.
  let prebuilt: Node[] | undefined;
  function sizeEditor() {
    if (!pad) return;
    root.style.setProperty('--guide-content-height', `${Math.ceil(pad.editor.getContentHeight())}px`);
  }
  function select(id: string, focus = false) {
    current = id;
    for (const tab of tabs) {
      const selected = tab.dataset.guideView === id;
      tab.setAttribute('aria-selected', String(selected)); tab.tabIndex = selected ? 0 : -1;
      if (selected && focus) tab.focus();
    }
    for (const source of root.querySelectorAll<HTMLElement>('[data-guide-source]')) source.hidden = source.dataset.guideSource !== id;
    pad?.select(id, { focus: false });
    sizeEditor();
  }
  for (const [index, tab] of tabs.entries()) {
    tab.onclick = () => select(tab.dataset.guideView!);
    tab.onkeydown = event => {
      const next = event.key === 'ArrowRight' ? (index + 1) % tabs.length : event.key === 'ArrowLeft' ? (index - 1 + tabs.length) % tabs.length : event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1 : -1;
      if (next < 0) return;
      event.preventDefault(); select(tabs[next].dataset.guideView!, true);
    };
  }
  function keepPrebuilt() {
    if (prebuilt) return;
    prebuilt = [...previewPane.childNodes];
    const host = previewPane.querySelector('[data-fleury-example]');
    if (host) (window as ExampleApi).fleuryUnmountExample?.(host);
  }
  function restorePrebuilt() {
    if (!prebuilt) return;
    previewPane.replaceChildren(...prebuilt);
    prebuilt = undefined;
    for (const host of previewPane.querySelectorAll('[data-fleury-example]')) {
      host.replaceChildren();
      host.removeAttribute('data-fleury-state');
    }
    (window as ExampleApi).fleuryMountExamples?.();
  }
  async function mountEditor() {
    return loading ??= (async () => {
      try {
        const [{ monaco, EditorWorker }, { mountPad }] = await Promise.all([import('./monaco'), import('../../../../experiments/fleury_pad/dartpad/web/editor.js')]);
        // A revision-bound draft cannot leak into another example or a changed
        // backing program.
        let revision = 2166136261;
        for (const char of JSON.stringify(project)) revision = Math.imul(revision ^ char.charCodeAt(0), 16777619);
        // The reader's run gets the prebuilt example's grid and theme: the
        // frame sizes its app to the same cols × rows in its own font.
        const original = previewPane.querySelector<HTMLElement>('.fleury-frame, [data-fleury-example]');
        if (original) {
          const { width, height } = original.getBoundingClientRect();
          root.style.setProperty('--guide-preview-width', `${Math.max(240, width + 16)}px`);
          root.style.setProperty('--guide-preview-height', `${Math.max(128, height)}px`);
        }
        const grid = previewPane.querySelector<HTMLElement>('[data-cols][data-rows]');
        const frame = new URLSearchParams({ theme: document.documentElement.dataset.theme === 'light' ? 'light' : 'dark' });
        if (grid) { frame.set('cols', grid.dataset.cols!); frame.set('rows', grid.dataset.rows!); }
        $<HTMLElement>('.guide-pad-static').hidden = true;
        $<HTMLElement>('[data-pad="editor"]').hidden = false;
        pad = mountPad(root, { monaco, project, sample: '', createWorker: () => new EditorWorker(),
          compilerUrl: root.dataset.compiler, frameUrl: `${root.dataset.compiler}/frame.html#${frame}`,
          draftKey: `fleury-guide-pad:${project.id}:${revision >>> 0}`,
          deferLanguageServices: true,
          editorOptions: { lineNumbers: 'off', glyphMargin: false, folding: false, lineDecorationsWidth: 0,
            overviewRulerLanes: 0, hideCursorInOverviewRuler: true, renderLineHighlight: 'none',
            lineHeight: 20, padding: { top: 8, bottom: 8 }, scrollBeyondLastLine: false,
            scrollbar: { alwaysConsumeMouseWheel: false }, },
          onView: (id: string) => select(id),
          onPreviewStart: keepPrebuilt,
          onReset: restorePrebuilt,
        }) as Pad;
        root.dataset.ready = 'true';
        $<HTMLButtonElement>('[data-guide="retry"]').hidden = true;
        if (marks.length) {
          // Decorations follow edits; the highlighted lines move with the code.
          pad.select(project.views[0].id, { focus: false });
          pad.editor.createDecorationsCollection(marks.map(line => ({
            range: new monaco.Range(line, 1, line, 1),
            options: { isWholeLine: true, className: 'guide-pad-marked' },
          })));
        }
        pad.select(current, { focus: false });
        pad.editor.onDidContentSizeChange(sizeEditor);
        sizeEditor();
      } catch (error) {
        loading = undefined;
        $<HTMLElement>('.guide-pad-static').hidden = false;
        $<HTMLElement>('[data-pad="editor"]').hidden = true;
        const diagnostics = $<HTMLElement>('[data-pad="diagnostics"]');
        diagnostics.hidden = false;
        diagnostics.textContent = `Could not load the editor. ${error instanceof Error ? error.message : ''}`;
        $<HTMLButtonElement>('[data-guide="retry"]').hidden = false;
      }
    })();
  }
  $<HTMLButtonElement>('[data-guide="retry"]').onclick = () => void mountEditor();
  $<HTMLButtonElement>('[data-guide="revert"]').onclick = () => pad?.revert();
  // Prepare code as it approaches the viewport. This loads only local editor
  // assets: language tools start after an edit or an explicit editor action.
  const observer = new IntersectionObserver(entries => {
    if (entries.some(entry => entry.isIntersecting)) { observer.disconnect(); void mountEditor(); }
  }, { rootMargin: '400px' });
  observer.observe(root);
  root.addEventListener('focusin', () => { void mountEditor(); });
  const expand = $<HTMLButtonElement>('[data-guide="expand"]');
  function fullscreen(value: boolean) {
    if (value === expanded) return;
    expanded = value;
    root.close();
    if (value) {
      previousOverflow = document.documentElement.style.overflow;
      document.documentElement.style.overflow = 'hidden'; root.setAttribute('role', 'dialog'); root.showModal();
      void mountEditor();
    } else { root.open = true; root.setAttribute('role', 'group'); document.documentElement.style.overflow = previousOverflow; }
    expand.setAttribute('aria-expanded', String(value));
    expand.setAttribute('aria-label', value ? 'Exit fullscreen' : `Expand ${project.id} playground`);
    $<HTMLElement>('[data-expand-label]').textContent = value ? 'Close' : 'Expand';
    sizeEditor(); pad?.editor.layout(); expand.focus({ preventScroll: true });
  }
  expand.onclick = () => fullscreen(!expanded);
  root.addEventListener('cancel', event => { event.preventDefault(); fullscreen(false); });
}
