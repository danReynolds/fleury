/** The UI only paces the run; Dart owns the widget, actions, and assertions. */
interface TestStep {
  done: boolean;
  label: string;
  code: string;
  assertion: boolean;
  html: string;
}
interface TestRun {
  next(): Promise<TestStep>;
  dispose(): void;
}
const api = window as Window & {
  fleuryCreatePreferencesTest?: () => TestRun;
};
let bundle: Promise<void> | undefined;

function loadRunner(): Promise<void> {
  if (api.fleuryCreatePreferencesTest) return Promise.resolve();
  return bundle ??= new Promise<void>((resolve, reject) => {
    const script = document.createElement('script');
    script.src = '/fleury/fleury-preferences-test.js';
    script.onload = () => {
      if (api.fleuryCreatePreferencesTest) resolve();
      else reject(new Error('The test runner did not start. Please try again.'));
    };
    script.onerror = () => reject(new Error('Could not load the test. Please try again.'));
    document.head.append(script);
  }).catch((error) => {
    bundle = undefined;
    throw error;
  });
}

export function attachPreferencesTest(
  host: HTMLElement,
  codeScope: ParentNode,
): () => void {
  const surface = host.parentElement!;
  const controls = document.createElement('div');
  controls.className = 'fleury-test-controls';
  const toolbar = document.createElement('div');
  toolbar.className = 'fleury-test-toolbar';
  const run = document.createElement('button');
  run.type = 'button';
  run.className = 'fleury-test-run';
  run.textContent = '▶ Run test';
  const tryIt = document.createElement('button');
  tryIt.type = 'button';
  tryIt.textContent = 'Try it yourself';
  tryIt.hidden = true;
  const status = document.createElement('div');
  status.className = 'fleury-test-status';
  status.setAttribute('role', 'status');
  status.textContent = 'Watch the test step through this example.';
  const checks = document.createElement('ul');
  checks.className = 'fleury-test-checks';
  checks.setAttribute('aria-label', 'Passed assertions');
  checks.hidden = true;
  const snapshot = document.createElement('div');
  snapshot.className = 'fleury-test-snapshot';
  snapshot.hidden = true;
  snapshot.setAttribute('role', 'img');
  // The real test's 32 × 11 viewport is displayed with the embed's typography.
  snapshot.style.cssText = 'width:32ch;height:13.75em;max-width:100%;';
  toolbar.append(run, tryIt);
  controls.append(toolbar, status);
  surface.before(controls);
  surface.append(snapshot);
  surface.after(checks);
  const badge = host.closest('.fleury-frame')?.querySelector<HTMLElement>('.fleury-badge');
  const originalBadge = badge?.innerHTML;

  let active: TestRun | undefined;
  let generation = 0;
  let running = false;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let wake: (() => void) | undefined;
  const pause = () => new Promise<void>((resolve) => {
    wake = resolve;
    timer = setTimeout(resolve, 850);
  });
  const clearHighlight = () => codeScope.querySelectorAll('.fleury-test-line')
    .forEach((line) => line.classList.remove('fleury-test-line'));
  const highlight = (code: string) => {
    clearHighlight();
    const normalize = (text: string) => text.replace(/\s+/g, '');
    const pane = codeScope.querySelector<HTMLElement>('[data-cds-code-file="1"]');
    const line = Array.from(pane?.querySelectorAll<HTMLElement>('.ec-line') ?? [])
      .find((line) => normalize(line.textContent ?? '').includes(normalize(code)));
    if (!line) return;
    line.classList.add('fleury-test-line');
    // Scroll only the code pane, never the reader's page.
    let scroller = line.parentElement;
    while (scroller && scroller !== codeScope) {
      if (scroller.scrollHeight > scroller.clientHeight &&
          ['auto', 'scroll'].includes(getComputedStyle(scroller).overflowY)) {
        const delta = line.getBoundingClientRect().top - scroller.getBoundingClientRect().top;
        if (delta < 0 || delta + line.offsetHeight > scroller.clientHeight) {
          scroller.scrollTop += delta - scroller.clientHeight / 2;
        }
        break;
      }
      scroller = scroller.parentElement;
    }
  };
  const stop = () => {
    generation++;
    running = false;
    clearTimeout(timer);
    wake?.();
    wake = undefined;
    active?.dispose();
    active = undefined;
  };
  const restoreLive = () => {
    stop();
    host.hidden = false;
    snapshot.hidden = true;
    if (badge && originalBadge) badge.innerHTML = originalBadge;
    controls.dataset.state = 'idle';
    checks.hidden = true;
    tryIt.hidden = true;
    run.textContent = '▶ Run test';
    status.textContent = 'Watch the test step through this example.';
    clearHighlight();
  };
  tryIt.addEventListener('click', restoreLive);
  run.addEventListener('click', async () => {
    if (running) {
      stop();
      status.textContent = 'Stopped. Run again to start with fresh forms.';
      run.textContent = '↻ Run again';
      controls.dataset.state = 'stopped';
      return;
    }
    stop();
    const token = generation;
    running = true;
    run.textContent = '■ Stop';
    tryIt.hidden = false;
    checks.replaceChildren();
    checks.hidden = true;
    status.textContent = 'Starting a fresh test…';
    controls.dataset.state = 'running';
    codeScope.querySelector<HTMLButtonElement>('[data-cds-file-tab="1"]')?.click();
    let count = 0;
    try {
      await loadRunner();
      if (token !== generation) return;
      const test = active = api.fleuryCreatePreferencesTest!();
      while (token === generation) {
        const step = await test.next();
        if (token !== generation) return;
        if (step.done) break;
        // Markup comes from Fleury's escaped CellBuffer renderer, never page input.
        snapshot.innerHTML = step.html;
        snapshot.setAttribute('aria-label', `Test view: ${step.label}`);
        snapshot.hidden = false;
        host.hidden = true;
        if (badge) badge.textContent = 'Test view';
        highlight(step.code);
        status.textContent = step.label;
        if (step.assertion) {
          const check = document.createElement('li');
          check.textContent = `✓ ${step.label}`;
          checks.append(check);
          checks.hidden = false;
          count++;
        }
        await pause();
      }
      if (token !== generation) return;
      status.textContent = `Passed · ${count} assertions`;
      controls.dataset.state = 'passed';
    } catch (error) {
      if (token !== generation) return;
      status.textContent = `Failed: ${error instanceof Error ? error.message : String(error)}`;
      controls.dataset.state = 'failed';
    } finally {
      if (token === generation) {
        active?.dispose();
        active = undefined;
        running = false;
        run.textContent = '↻ Run again';
      }
    }
  });
  const dispose = () => {
    stop();
    clearHighlight();
    controls.remove();
    checks.remove();
    snapshot.remove();
    if (badge && originalBadge) badge.innerHTML = originalBadge;
    host.hidden = false;
    document.removeEventListener('astro:before-swap', dispose);
  };
  document.addEventListener('astro:before-swap', dispose, { once: true });
  return dispose;
}
