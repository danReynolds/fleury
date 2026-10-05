import { Preview } from '../../preview.mjs';
import { SourceProject } from './source-project.mjs';

// The hosted compiler is small, shared, and has no per-reader limit, so a busy
// or unreachable compiler is a passing state, not a problem with anyone's code.
export const PAD_BUSY = 'The Pad is busy. Try again in a moment.';

// The error for a failed compiler request. `status` is null when no response
// arrived: the network failed, the request timed out, or an overloaded service
// answered without CORS headers. Those, 429 and 503 mean the compiler is
// `unavailable` for now. Other failures keep the compiler's message (plain text
// for DDC's compile errors) and the issues it found.
export function compilerFailure(status, result = {}, { online = true } = {}) {
  if (status === null || status === 429 || status === 503) {
    const message = status === null && !online ? 'You are offline. Your code is saved in this browser.' : PAD_BUSY;
    return Object.assign(new Error(message), { code: 'unavailable' });
  }
  return Object.assign(new Error(result.error || `The compiler returned HTTP ${status}. Try Run again.`), { code: result.code, issues: result.issues });
}

// Shared by the docs workspace and the standalone compiler host.
export function mountPad(root, { monaco, sample, createWorker, compilerUrl = '', frameUrl = '/frame.html', autoRunSample = false, onRun = () => {}, project = null, draftKey = 'fleury-pad-dartpad-source', onView = () => {}, onPreviewStart = () => {}, onReset = () => {}, deferLanguageServices = false, editorOptions = {} }) {
  compilerUrl = compilerUrl.replace(/\/$/, '');
  self.MonacoEnvironment = { getWorker: createWorker };
  const $ = id => root.querySelector(`[data-pad="${id}"]`) ?? root.querySelector(`#${id}`);
  const disposables = [];
  const lifetime = new AbortController();
  let disposed = false;
  let languageServicesActive = !deferLanguageServices;
  // Loading the editor and restoring a draft never depend on a live compiler.
  let buildPromise;
  // Allow Cloud Run's 60-second request window, including a cold start.
  // Accepted compiler work still has a separate 25-second process deadline.
  async function request(path, init = {}) {
    try {
      const response = await fetch(`${compilerUrl}${path}`, { ...init, signal: AbortSignal.any([lifetime.signal, AbortSignal.timeout(65000)]) });
      return { response, body: await response.text() };
    } catch (error) {
      if (lifetime.signal.aborted) throw error;
      throw compilerFailure(null, {}, { online: navigator.onLine !== false });
    }
  }
  function compilerBuild() {
    return buildPromise ??= (async () => {
      if (!compilerUrl) throw new Error('The compiler is not connected. Your code is saved in this browser.');
      const { response, body } = await request('/api/build');
      if (response.status === 429 || response.status === 503) throw compilerFailure(response.status);
      if (!response.ok) throw new Error('Could not connect to the compiler. Try Run again.');
      let build;
      try { build = JSON.parse(body); } catch {}
      if (typeof build?.buildId !== 'string') throw new Error('Invalid compiler response. Try Run again.');
      if (project && !(build.protocolVersion >= 3)) throw new Error('This compiler needs an update to run guide projects. Your edits are saved in this browser.');
      return build;
    })().catch(error => { buildPromise = null; throw error; });
  }
  function readDraft() {
    try { return localStorage.getItem(draftKey); } catch { return null; }
  }
  monaco.editor.defineTheme('fleury-dark', { base: 'vs-dark', inherit: true, rules: [], colors: { 'editor.background': '#10161e', 'editor.lineHighlightBackground': '#19232d', 'editorLineNumber.foreground': '#607080', 'editorGutter.background': '#10161e' } });
  monaco.editor.defineTheme('fleury-light', { base: 'vs', inherit: true, rules: [], colors: { 'editor.background': '#ffffff', 'editor.lineHighlightBackground': '#f0f7f3', 'editorGutter.background': '#ffffff' } });
  const workspace = project ? new SourceProject(project) : null;
  let saved = {};
  if (workspace) { try { saved = JSON.parse(readDraft() ?? '{}'); } catch {} }
  if (!saved || typeof saved !== 'object') saved = {};
  const views = workspace?.views ?? [{ id: 'main', label: 'main.dart', file: 'main.dart', text: sample }];
  const models = new Map(views.map(view => [view.id, monaco.editor.createModel(
    workspace ? (typeof saved[view.id] === 'string' ? saved[view.id] : view.text) : (readDraft() ?? sample), 'dart')]));
  let activeId = views[0].id, generation = 0;
  let model = models.get(activeId);
  const values = () => Object.fromEntries([...models].map(([id, model]) => [id, model.getValue()]));
  function snapshot() {
    if (workspace) return workspace.snapshot(values());
    const source = model.getValue();
    return { source, fingerprint: source, viewText: () => source, toFile: (_id, offset) => offset,
      toView: (_file, offset) => ({ id: 'main', offset }), formatted: (_id, source) => source };
  }
  function payload(snap, id = activeId, offset) {
    const file = views.find(view => view.id === id).file;
    return { source: snap.source, ...(workspace ? { files: snap.files, activeFile: file } : {}),
      ...(offset == null ? {} : { offset: snap.toFile(id, offset) }) };
  }
  const editor = monaco.editor.create($('editor'), {
    model, theme: 'fleury-dark',
    automaticLayout: true, minimap: { enabled: false }, fontSize: 13, lineHeight: 22,
    scrollBeyondLastLine: false, padding: { top: 16 }, tabSize: 2, ariaLabel: 'Dart source',
    // Native EditContext can scroll the clipping wrapper when long lines gain
    // focus after a resize. Use Monaco's established textarea input path.
    editContext: false, accessibilitySupport: 'on', wordBasedSuggestions: 'off', quickSuggestions: true,
    ...editorOptions,
  });
  const syncTheme = () => monaco.editor.setTheme(document.documentElement.dataset.theme === 'light' ? 'fleury-light' : 'fleury-dark');
  syncTheme();
  const themeObserver = new MutationObserver(syncTheme);
  themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
  let checkpoint = null, busy = false, lastSource = null, analysisTimer, sourceHasErrors = false, reverting = false;
  const progress = $('progress');
  let progressTimer;
  function updateProgress(phase, label) {
    if (disposed || !progress) return;
    clearTimeout(progressTimer);
    progress.hidden = phase === 'idle';
    progress.dataset.phase = phase;
    progress.setAttribute('aria-valuetext', label ?? '');
    if (phase === 'complete') progress.setAttribute('aria-valuenow', '100');
    else progress.removeAttribute('aria-valuenow');
    if (phase === 'complete' || phase === 'error') {
      // Let completion register, but never let an earlier update's timer hide
      // a new reload. Status and diagnostics remain after the bar fades.
      progressTimer = setTimeout(() => { progress.hidden = true; }, 1600);
    }
  }
  const diagnostic = message => { if (disposed) return; $('diagnostics').textContent = message; $('diagnostics').hidden = false; };
  const createPreview = () => new Preview($('preview'), { frameUrl, onError(error) {
    checkpoint = null;
    diagnostic(error.message);
    $('status').textContent = 'App error. Restart to run the current source.';
    controls();
  } });
  let preview = createPreview();
  const dispose = () => {
    if (disposed) return;
    disposed = true;
    clearTimeout(progressTimer);
    if (progress) progress.hidden = true;
    clearTimeout(analysisTimer); lifetime.abort(); themeObserver.disconnect(); preview.dispose();
    for (const disposable of disposables) disposable.dispose();
    editor.dispose(); for (const model of models.values()) model.dispose();
  };
  addEventListener('pagehide', event => { if (!event.persisted) dispose(); });
  function controls() {
    if (disposed) return;
    root.dataset.busy = String(busy);
    root.dataset.running = String(preview.hasFrame);
    if (root.dataset.compact === 'true') { $('run').hidden = Boolean(checkpoint); $('reload').hidden = !checkpoint; }
    const hasChanges = snapshot().fingerprint !== lastSource;
    root.dataset.modified = String(lastSource === null ? views.some(view => models.get(view.id).getValue() !== view.text) : hasChanges);
    $('run').disabled = busy; $('reload').disabled = busy || !checkpoint || !hasChanges;
    $('reload').title = hasChanges ? 'Apply your changes and keep app state' : 'Make a change to hot reload';
    $('restart').disabled = busy || !preview.hasFrame; $('format').disabled = busy;
    root.dataset.revertable = String(root.dataset.modified === 'true' || preview.hasFrame || Boolean(readDraft()));
    $('dirty').textContent = sourceHasErrors ? 'Errors in source' : preview.hasFrame && !checkpoint && !busy ? 'Restart required' : snapshot().fingerprint === lastSource ? 'Up to date' : lastSource === null ? (readDraft() ? 'Local draft' : 'Example') : 'Edited';
  }
  async function api(method, payload) {
    const build = await compilerBuild();
    const { response, body } = await request(`/api/v3/${method}`, { method: 'POST', headers: {
      'Content-Type': 'application/json', 'X-Fleury-Build': build.buildId,
    }, body: JSON.stringify(payload) });
    let result;
    try { result = JSON.parse(body); } catch { result = { error: body }; }
    if (!response.ok || result.error) throw compilerFailure(response.status, result);
    return { ...result, elapsed: response.headers.get('x-compile-ms') };
  }
  function rangeAt(offset, length, target = model) {
    const start = target.getPositionAt(offset), end = target.getPositionAt(offset + length);
    return new monaco.Range(start.lineNumber, start.column, end.lineNumber, end.column);
  }
  disposables.push(monaco.languages.registerCompletionItemProvider('dart', {
    triggerCharacters: ['.', "'"],
    async provideCompletionItems(requestModel, position, _context, token) {
      if (requestModel !== model) return { suggestions: [] };
      if (!languageServicesActive && _context.triggerKind !== monaco.languages.CompletionTriggerKind.Invoke) return { suggestions: [] };
      languageServicesActive = true;
      const version = generation, id = activeId, snap = snapshot();
      try {
        const result = await api('complete', payload(snap, id, model.getOffsetAt(position)));
        if (token.isCancellationRequested || disposed || version !== generation || id !== activeId) return { suggestions: [] };
        const file = views.find(v => v.id === id).file;
        const start = snap.toView(file, result.replacementOffset), end = snap.toView(file, result.replacementOffset + result.replacementLength);
        if (start?.id !== id || end?.id !== id) return { suggestions: [] };
        return { suggestions: result.suggestions.map(item => ({
          label: item.completion, insertText: item.completion,
          detail: item.elementParameters || item.returnType || item.kind,
          sortText: String(1000000 - item.relevance).padStart(8, '0'),
          kind: item.elementKind === 'CLASS' || item.elementKind === 'CONSTRUCTOR' ? monaco.languages.CompletionItemKind.Class : monaco.languages.CompletionItemKind.Function,
          range: rangeAt(start.offset, end.offset - start.offset),
        })) };
      } catch { return { suggestions: [] }; }
    },
  }));
  disposables.push(monaco.languages.registerHoverProvider('dart', {
    async provideHover(requestModel, position, token) {
      if (requestModel !== model || !languageServicesActive) return null;
      const version = generation, id = activeId;
      try {
        const result = await api('document', payload(snapshot(), id, model.getOffsetAt(position)));
        if (token.isCancellationRequested || disposed || version !== generation || id !== activeId) return null;
        return { contents: [{ value: result.elementDescription || '' }, { value: result.dartdoc || '' }] };
      } catch { return null; }
    },
  }));
  async function analyze() {
    const version = generation, snap = snapshot();
    try {
      const result = await api('analyze', payload(snap));
      if (disposed || version !== generation) return;
      const markers = new Map([...models.keys()].map(id => [id, []]));
      const hidden = [];
      for (const issue of result.issues) {
        const file = issue.file ?? 'main.dart';
        const start = snap.toView(file, issue.location.charStart);
        const end = snap.toView(file, issue.location.charStart + issue.location.charLength);
        if (start && end && start.id === end.id) {
          markers.get(start.id).push({ ...rangeAt(start.offset, end.offset - start.offset, models.get(start.id)),
            message: issue.message, severity: issue.kind === 'error' ? monaco.MarkerSeverity.Error : monaco.MarkerSeverity.Warning, code: issue.code });
        } else if (issue.kind === 'error') hidden.push(`${file}:${issue.location.line}: ${issue.message}`);
      }
      for (const [id, model] of models) monaco.editor.setModelMarkers(model, 'dartpad', markers.get(id));
      if (hidden.length) diagnostic(hidden.join('\n'));
      sourceHasErrors = result.issues.some(issue => issue.kind === 'error');
      controls();
      if ($('status').textContent === 'Editor ready. Starting Dart tools…') {
        $('status').textContent = workspace ? 'Ready. Run your edits, then hot reload to keep app state.' : 'Ready. Run the example or edit the Dart source.';
      }
    } catch (error) {
      if (disposed) return;
      // Analysis runs again after the next edit, so an unavailable compiler
      // only delays it; report other failures.
      if (error.code !== 'unavailable') diagnostic(error.message);
      if ($('status').textContent === 'Editor ready. Starting Dart tools…') {
        $('status').textContent = error.code === 'unavailable'
          ? 'Editor ready. Dart tools will start after your next edit.'
          : 'Editor ready. Could not connect to Dart tools. Try Run again.';
      }
    }
  }
  for (const sourceModel of models.values()) disposables.push(sourceModel.onDidChangeContent(() => {
    generation++;
    if (reverting) return;
    languageServicesActive = true;
    try { localStorage.setItem(draftKey, workspace ? JSON.stringify(values()) : model.getValue()); }
    catch { diagnostic('This browser could not save your draft. Copy the source before closing.'); }
    sourceHasErrors = false;
    controls();
    clearTimeout(analysisTimer); analysisTimer = setTimeout(analyze, 500);
  }));
  $('format').onclick = async () => {
    languageServicesActive = true;
    try {
      const version = generation, id = activeId, snap = snapshot();
      const result = await api('format', payload(snap, id, model.getOffsetAt(editor.getPosition())));
      if (disposed || version !== generation || id !== activeId) return;
      editor.executeEdits('format', [{ range: model.getFullModelRange(), text: snap.formatted(id, result.source) }]);
      if (!workspace && result.offset != null) editor.setPosition(model.getPositionAt(result.offset));
      editor.focus();
    } catch (error) { diagnostic(error.message); }
  };
  async function compile(mode) {
    if (busy || disposed) return;
    // Keyboard shortcuts follow the same rule as the Hot reload button.
    if (mode === 'reload' && (!checkpoint || snapshot().fingerprint === lastSource)) return;
    languageServicesActive = true;
    busy = true; controls(); $('diagnostics').hidden = true;
    const snap = snapshot();
    let applying = false;
    $('status').textContent = mode === 'reload' ? 'Compiling changes…' : 'Compiling app…';
    updateProgress('compiling', $('status').textContent);
    try {
      const result = await api(mode === 'reload' ? 'compileNewDDCReload' : 'compileNewDDC', {
        ...payload(snap), ...(mode === 'reload' ? { deltaDill: checkpoint } : {}),
      });
      if (disposed) return;
      if (typeof result.result !== 'string' || typeof result.deltaDill !== 'string' || !result.deltaDill) {
        throw new Error('The compiler returned an incomplete update. Try running again.');
      }
      $('metrics').textContent = result.elapsed ? `Compiled in ${result.elapsed} ms` : '';
      $('status').textContent = mode === 'reload' ? 'Applying hot reload…' : 'Starting app…';
      updateProgress('applying', $('status').textContent);
      applying = true;
      if (mode !== 'reload') onPreviewStart();
      await preview.apply({ javascript: result.result,
        libraries: [...result.result.matchAll(/dartDevEmbedder.defineLibrary\("([^"]+)"/g)].map(match => match[1]),
      }, { reload: mode === 'reload' });
      if (disposed) return;
      // Commit only the checkpoint whose code and Fleury reassembly succeeded.
      checkpoint = result.deltaDill;
      onRun();
      lastSource = snap.fingerprint;
      $('status').textContent = mode === 'reload' ? 'Hot reloaded. The app is ready.' : 'Running. Try the app, then edit the Dart source.';
      updateProgress('complete', $('status').textContent);
    } catch (error) {
      if (disposed) return;
      const issues = error.issues?.map(issue => {
        const point = snap.toView(issue.file, issue.location.charStart);
        if (!point) return `${issue.file}:${issue.location.line}: ${issue.message}`;
        const prefix = snap.viewText(point.id).slice(0, point.offset);
        const lines = prefix.split('\n');
        return `${views.find(view => view.id === point.id).label}:${lines.length}:${lines.at(-1).length + 1}: ${issue.message}`;
      });
      diagnostic(issues?.length ? issues.join('\n') : error.message);
      if (applying || error.code === 'checkpoint_rejected') {
        checkpoint = null;
        $('status').textContent = 'App update failed. Restart to run the current source.';
      } else if (checkpoint) {
        $('status').textContent = error.code === 'unavailable' ? 'Not compiled. Your running app is unchanged.' : 'Compilation failed. Your running app is unchanged.';
      } else {
        $('status').textContent = error.code === 'unavailable' ? 'Not compiled. Try Run again in a moment.' : 'Could not compile. Fix the error or try Run again.';
      }
      updateProgress('error', $('status').textContent);
    } finally {
      busy = false; controls();
    }
  }
  $('run').onclick = () => compile('run'); $('reload').onclick = () => compile('reload');
  $('restart').onclick = () => compile('run');
  // Saving applies the edit, as it does under Fleury's terminal hot reload.
  for (const key of [monaco.KeyCode.Enter, monaco.KeyCode.KeyS]) {
    editor.addCommand(monaco.KeyMod.CtrlCmd | key, () => compile(checkpoint ? 'reload' : 'run'));
  }
  // Back to the example as published: its source, and no running edit.
  function revert() {
    if (busy || disposed) return;
    reverting = true;
    try { for (const view of views) models.get(view.id).setValue(workspace ? view.text : sample); }
    finally { reverting = false; }
    try { localStorage.removeItem(draftKey); } catch {}
    clearTimeout(analysisTimer);
    for (const model of models.values()) monaco.editor.setModelMarkers(model, 'dartpad', []);
    const hadApp = preview.hasFrame;
    preview.dispose(); preview = createPreview();
    checkpoint = null; lastSource = null; sourceHasErrors = false;
    updateProgress('idle');
    $('diagnostics').hidden = true; $('metrics').textContent = ''; $('status').textContent = '';
    if (hadApp) onReset();
    controls();
  }
  // Only the known starter runs on arrival. Restored custom drafts still wait
  // for Run, and first compilation takes priority over background analysis.
  const restored = !workspace && model.getValue() !== sample;
  $('status').textContent = deferLanguageServices ? ''
    : restored ? 'Your earlier edit is restored. Press Run to see it.' : 'Editor ready. Starting Dart tools…';
  controls();
  if (autoRunSample && model.getValue() === sample) {
    void compile('run').finally(() => { if (!disposed) void analyze(); });
  } else if (languageServicesActive) {
    void analyze();
  }
  const positions = new Map();
  function select(id, { focus = true } = {}) {
    if (!models.has(id) || id === activeId) return;
    positions.set(activeId, editor.saveViewState());
    activeId = id; model = models.get(id); editor.setModel(model);
    if (positions.has(id)) editor.restoreViewState(positions.get(id));
    onView(id); if (focus) editor.focus();
  }
  return { editor, views, select, snapshot, run: () => compile(checkpoint ? 'reload' : 'run'), revert, dispose };

}
