import { Preview } from './preview.mjs';
const $ = id => document.getElementById(id);
const source = $('source'), status = $('status'), diagnostics = $('diagnostics');
const build = await (await fetch('/api/build')).json();
let checkpoint = null, lastSource = null, busy = false;
const preview = new Preview($('preview'), { onError(exception) {
  checkpoint = null; error(exception.message);
  status.textContent = 'App error. Restart to run the current source.'; controls();
} });
addEventListener('pagehide', () => preview.dispose());
const controls = () => {
  $('run').disabled = busy;
  $('reload').disabled = busy || !checkpoint;
  $('restart').disabled = busy || !preview.hasFrame;
  $('dirty').textContent = source.value === lastSource ? 'Saved' : 'Edited';
};
const error = message => { diagnostics.textContent = message; diagnostics.hidden = false; };
source.addEventListener('input', controls);
source.addEventListener('keydown', event => {
  if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') {
    event.preventDefault(); if (!busy) compile(checkpoint ? 'reload' : 'run');
  }
});
async function compile(mode) {
  if (busy) return;
  let applying = false;
  busy = true; controls(); diagnostics.hidden = true;
  const submitted = source.value;
  status.textContent = mode === 'reload' ? 'Compiling changes…' : 'Compiling app…';
  try {
    const response = await fetch('/api/compile', {method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({source: submitted, buildId: build.buildId, checkpoint: mode === 'reload' ? checkpoint : null})});
    const result = await response.json();
    if (!response.ok || !result.ok) {
      error(result.diagnostics || result.error); status.textContent = checkpoint ? 'Compilation failed. Your running app is unchanged.' : 'Fix the compiler error and run again.';
      busy = false; controls(); return;
    }
    $('metrics').textContent = `Compile ${result.compileMs} ms`;
    status.textContent = mode === 'reload' ? 'Applying hot reload…' : 'Starting app…';
    applying = true;
    await preview.apply(result, { reload: mode === 'reload' });
    checkpoint = result.checkpoint;
    lastSource = submitted;
    status.textContent = mode === 'reload' ? 'Hot reloaded. The app is ready.' : 'Running. Try the app, then edit the Dart source.';
  } catch (exception) {
    if (applying) checkpoint = null;
    error(String(exception));
    status.textContent = applying ? 'App update failed. Restart to run the current source.' : 'Compilation service unavailable.';
  } finally { busy = false; controls(); }
}
$('run').onclick = () => compile('run');
$('reload').onclick = () => compile('reload');
$('restart').onclick = () => compile('run');
source.value = await (await fetch('/sample.dart')).text();
status.textContent = 'Ready. Run the example or edit the Dart source.';
controls();
