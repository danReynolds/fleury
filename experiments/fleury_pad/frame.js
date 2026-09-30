// A docs page names its theme, and the prebuilt example's grid, in the
// fragment. The app gets exactly that many cells in this frame's font, measured
// the way Fleury's web host measures them, and the page is told the frame size.
const page = new URLSearchParams(location.hash.slice(1));
if (page.get('theme') === 'light') document.documentElement.className = 'light';
const cols = Number(page.get('cols')), rows = Number(page.get('rows'));
function sizeToGrid() {
  const app = document.getElementById('app');
  const probe = document.createElement('span');
  probe.textContent = 'MMMMMMMMMM';
  probe.style.cssText = 'position:absolute;visibility:hidden;white-space:pre;left:-10000px;top:-10000px';
  app.append(probe);
  const box = probe.getBoundingClientRect();
  probe.remove();
  const dpr = devicePixelRatio || 1;
  const snap = px => Math.round(px * dpr) / dpr;
  const pad = getComputedStyle(app);
  const width = Math.ceil(cols * snap(box.width / 10) + parseFloat(pad.paddingLeft) + parseFloat(pad.paddingRight)) + 1;
  const height = Math.ceil(rows * snap(box.height) + parseFloat(pad.paddingTop) + parseFloat(pad.paddingBottom)) + 1;
  app.style.width = `${width}px`;
  app.style.height = `${height}px`;
  parent.postMessage({ sender: 'fleury-pad', id: 0, type: 'size', width, height }, '*');
}
if (cols > 0 && rows > 0) {
  // Measure in the docs font once it has loaded, as the prebuilt preview does.
  const font = document.fonts ? document.fonts.load('14px FleuryMono').catch(() => {}) : Promise.resolve();
  font.then(() => {
    if (document.readyState === 'loading') addEventListener('DOMContentLoaded', sizeToGrid);
    else sizeToGrid();
  });
}
let operation = null;
let lastId = 0;
const tell = (type, data = {}) => parent.postMessage({ sender: 'fleury-pad', id: lastId, type, ...data }, '*');
const fail = error => {
  operation = null;
  tell('error', { message: String(error) });
};
window.fleuryPadReady = () => {
  if (operation?.mode !== 'run') return;
  operation = null;
  tell('running');
};
addEventListener('error', event => fail(event.message));
addEventListener('unhandledrejection', event => fail(event.reason));
addEventListener('load', () => tell('ready'));
addEventListener('message', async event => {
  if (event.source !== parent || event.data?.sender !== 'fleury-editor') return;
  const { id, javascript, mode, libraries } = event.data;
  if (operation || !Number.isSafeInteger(id) || id <= lastId) return;
  if (!['run', 'reload'].includes(mode) || typeof javascript !== 'string' || !Array.isArray(libraries) || !libraries.every(name => typeof name === 'string')) return;
  lastId = id;
  operation = { id, mode };
  const url = URL.createObjectURL(new Blob([javascript], { type: 'text/javascript' }));
  try {
    if (mode === 'reload') {
      await dartDevEmbedder.hotReload([url], libraries);
      if (operation?.id !== id) return;
      await window.fleuryPadReassemble();
      // A runtime error may already have invalidated this update while awaited.
      if (operation?.id !== id) return;
      operation = null;
      tell('reloaded');
    } else {
      const script = document.createElement('script');
      script.src = url;
      await new Promise((resolve, reject) => {
        script.onload = resolve;
        script.onerror = () => reject(new Error('Could not load the compiled app.'));
        document.head.append(script);
      });
      dartDevEmbedder.runMain('package:fleury_pad/bootstrap.dart', {});
    }
  } catch (error) { if (lastId === id) fail(error); }
  finally { URL.revokeObjectURL(url); }
});
