import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { test } from 'node:test';
import {
  DOCS_ORIGIN, check, compilerFor, libraries, report, runRequest, selectSample, workflowCommand,
} from './pad-compiler-guard.mjs';

const COMPILER = 'https://compiler.test';
const registry = "import 'package:fleury/fleury_core.dart';\nimport 'package:fleury/themes.dart';\n\nWidget example() => const Text('Hello');\n";
const main = "import 'package:fleury/fleury_core.dart';\nimport 'examples/registry.dart';\n\nWidget buildApp() => example();\n";
const project = { id: 'demo', files: { 'main.dart': main, 'examples/registry.dart': registry }, views: [
  { id: 'view-0', label: 'registry.dart', file: 'examples/registry.dart', start: registry.indexOf('Widget example'), end: registry.length - 1 },
] };
const targets = [{ id: 'first', body: runRequest(project) }, { id: 'second', body: runRequest(project) }];

const json = (body, { status = 200, headers = {} } = {}) => new Response(JSON.stringify(body), { status, headers: {
  'content-type': 'application/json', 'access-control-allow-origin': DOCS_ORIGIN, ...headers,
} });
const build = { buildId: 'build-1', protocolVersion: 3, sourceRevision: 'a4799837b03c925267b64f1f5214023e75f18bcc' };
const compiled = () => json({ result: 'dartDevEmbedder.defineLibrary("app")', deltaDill: 'checkpoint' });
const themesMissing = () => json({ error: 'Could not compile the project. Check the source errors.', issues: [{
  file: 'examples/registry.dart', kind: 'error', code: 'uri_does_not_exist',
  message: "Target of URI doesn't exist: 'package:fleury/themes.dart'.",
  location: { charStart: 49, charLength: 28, line: 2, column: 8 },
}] }, { status: 400 });

// A compiler answering each route in turn; a route's last answer repeats.
function compiler(routes) {
  const calls = [];
  async function fetch(url, init = {}) {
    const route = `${init.method ?? 'GET'} ${new URL(url).pathname}`;
    calls.push({ route, headers: init.headers, body: init.body === undefined ? undefined : JSON.parse(init.body) });
    const answers = routes[route] ?? [() => new Response('Not found', { status: 404 })];
    return (answers.length > 1 ? answers.shift() : answers[0])();
  }
  return { fetch, calls };
}
const healthy = (compile = [compiled]) => ({
  'GET /api/build': [() => json(build)],
  'OPTIONS /api/v3/compileNewDDC': [() => new Response(null, { status: 204, headers: { 'access-control-allow-origin': DOCS_ORIGIN } })],
  'POST /api/v3/compileNewDDC': compile,
});
async function run(routes) {
  const { fetch, calls } = compiler(routes);
  const waits = [];
  const outcome = await check({ compiler: COMPILER, targets, fetch, sleep: async ms => { waits.push(ms); } });
  return { outcome, calls, waits, compiles: calls.filter(call => call.route === 'POST /api/v3/compileNewDDC') };
}
const reports = outcome => ({
  deploy: report({ mode: 'deploy', compiler: COMPILER, outcome, total: targets.length, commit: 'c21de584abcdef' }),
  pullRequest: report({ mode: 'pull-request', compiler: COMPILER, outcome, total: targets.length }),
});

test('pass: sends what an unedited docs Run sends, and keeps Run', async () => {
  const { outcome, calls, compiles } = await run(healthy());
  assert.equal(outcome.verdict, 'compatible');
  assert.equal(compilerFor('deploy', outcome.verdict, COMPILER), COMPILER);
  assert.ok(calls.every(call => call.headers.origin === DOCS_ORIGIN));
  const [first] = compiles;
  assert.equal(first.headers['content-type'], 'application/json');
  assert.equal(first.headers['x-fleury-build'], 'build-1');
  // The docs' SourceProject snapshot: the whole project, its first view's
  // file active, the editable region marked.
  assert.deepEqual(Object.keys(first.body).sort(), ['activeFile', 'files', 'source']);
  assert.equal(first.body.activeFile, 'examples/registry.dart');
  assert.equal(first.body.source, first.body.files['main.dart']);
  assert.match(first.body.files['examples/registry.dart'], /\/\* pad:view-0:start \*\/Widget example\(\)/);
  const preflight = calls.find(call => call.route === 'OPTIONS /api/v3/compileNewDDC');
  assert.equal(preflight.headers['access-control-request-headers'], 'content-type,x-fleury-build');
  const { deploy, pullRequest } = reports(outcome);
  assert.equal(deploy.annotation, null);
  assert.equal(pullRequest.annotation, null);
  assert.match(deploy.markdown, /compiled all 2 sampled docs projects, so this build enables Run/);
});

test('source error: read-only deploy naming each project and its first error; PR warning', async () => {
  const { outcome, waits, compiles } = await run(healthy([themesMissing]));
  assert.equal(outcome.verdict, 'incompatible');
  // The compiler's answer is final: no retry, and every project is checked.
  assert.deepEqual(outcome.results.map(entry => [entry.id, entry.kind, entry.attempts]), [['first', 'failed', 1], ['second', 'failed', 1]]);
  assert.equal(compiles.length, 2);
  assert.deepEqual(waits, []);
  assert.equal(outcome.results[0].error, "examples/registry.dart:2:8: Target of URI doesn't exist: 'package:fleury/themes.dart'.");
  assert.equal(compilerFor('deploy', outcome.verdict, COMPILER), '');
  assert.equal(compilerFor('pull-request', outcome.verdict, COMPILER), COMPILER);
  const { deploy, pullRequest } = reports(outcome);
  assert.deepEqual([deploy.annotation.level, deploy.annotation.title], ['error', 'Pads are read-only in this deploy']);
  assert.match(deploy.annotation.message, /^The live Pad compiler \(build build-1, from a4799837\) can't compile 2 of 2 sampled docs projects: first \(examples\/registry\.dart:2:8: Target of URI doesn't exist/);
  assert.match(deploy.annotation.message, /Release the Pad compiler from this commit, then re-run this workflow\.$/);
  assert.match(deploy.markdown, /\*\*Release the Pad compiler from this commit, then re-run this workflow\.\*\* \(Commit `c21de584`/);
  assert.match(deploy.markdown, /\| `second` \| can't compile: examples\/registry\.dart:2:8: Target of URI doesn't exist/);
  assert.deepEqual([pullRequest.annotation.level, pullRequest.annotation.title], ['warning', 'Needs a Pad compiler release after merge']);
  assert.match(pullRequest.annotation.message, /from this pull request: first \(/);
});

test('transient, then pass: a restarting or cold compiler is retried', async () => {
  const { outcome, waits } = await run(healthy([
    () => json({ error: 'Compiler restarting. Try again.' }, { status: 503, headers: { 'retry-after': '2' } }),
    () => { throw new DOMException('The operation was aborted due to timeout', 'TimeoutError'); },
    compiled,
  ]));
  assert.equal(outcome.verdict, 'compatible');
  assert.deepEqual(outcome.results.map(entry => entry.attempts), [3, 1]);
  assert.deepEqual(waits, [3000, 10000]);
});

test('transient, always: a deploy fails closed to read-only, and stops asking', async () => {
  const reset = () => { throw new TypeError('fetch failed', { cause: { code: 'ECONNRESET' } }); };
  const { outcome, waits, compiles } = await run(healthy([reset]));
  assert.equal(outcome.verdict, 'unavailable');
  assert.deepEqual(outcome.results.map(entry => [entry.id, entry.kind, entry.attempts]), [['first', 'transient', 3]]);
  assert.equal(compiles.length, 3);
  assert.deepEqual(waits, [3000, 10000]);
  assert.equal(compilerFor('deploy', outcome.verdict, COMPILER), '');
  assert.equal(compilerFor('pull-request', outcome.verdict, COMPILER), COMPILER);
  const { deploy, pullRequest } = reports(outcome);
  assert.equal(deploy.annotation.level, 'error');
  assert.match(deploy.annotation.message, /: no response \(ECONNRESET\) \(3 attempts\)\. This deploy leaves Pads read-only rather than risk a broken Run\. Re-run this workflow/);
  // A pull request can't learn anything; that is not a warning.
  assert.equal(pullRequest.annotation.level, 'notice');

  // Without the build, no project is sent.
  const down = await run({ 'GET /api/build': [() => json({ error: 'Stopping.' }, { status: 503 })] });
  assert.equal(down.outcome.verdict, 'unavailable');
  assert.equal(down.compiles.length, 0);
  assert.match(down.outcome.problem.error, /HTTP 503: Stopping\. \(3 attempts\)/);
});

test('a hanging compiler is given up on within the time budget', async () => {
  let clock = 0;
  const hang = () => { clock += 70_000; throw new DOMException('The operation was aborted due to timeout', 'TimeoutError'); };
  const { fetch, calls } = compiler(healthy([hang]));
  const outcome = await check({
    compiler: COMPILER, targets, fetch, now: () => clock, sleep: async ms => { clock += ms; },
    limits: { attempts: 3, timeoutMs: 65_000, backoffMs: [3_000, 10_000], budgetMs: 100_000 },
  });
  // The second attempt ends past the budget, so there is no third.
  assert.equal(outcome.verdict, 'unavailable');
  assert.deepEqual(outcome.results.map(entry => [entry.id, entry.attempts]), [['first', 2]]);
  assert.equal(calls.filter(call => call.route === 'POST /api/v3/compileNewDDC').length, 2);
});

test('a compiler released mid-check is asked for its new build', async () => {
  const routes = healthy([() => json({ error: 'Compiler build changed. Reload the page; your source is saved.' }, { status: 409 }), compiled]);
  routes['GET /api/build'] = [() => json(build), () => json({ ...build, buildId: 'build-2' })];
  const { outcome, compiles } = await run(routes);
  assert.equal(outcome.verdict, 'compatible');
  assert.deepEqual(compiles.map(call => call.headers['x-fleury-build']), ['build-1', 'build-2', 'build-2']);
});

test('a compiler that refuses the docs origin, or predates their projects, is not used', async () => {
  // Without the docs origin's CORS grant, a browser can't read the answer.
  const noGrant = await run({ ...healthy(), 'GET /api/build': [() => new Response(JSON.stringify(build))] });
  assert.equal(noGrant.outcome.verdict, 'unavailable');
  assert.match(noGrant.outcome.problem.error, /doesn't grant https:\/\/danreynolds\.github\.io access/);
  const forbidden = await run(healthy([() => json({ error: 'Same-origin JSON requests only.' }, { status: 403 })]));
  assert.equal(forbidden.outcome.verdict, 'unavailable');
  assert.deepEqual(forbidden.outcome.results.map(entry => [entry.kind, entry.attempts]), [['refused', 1]]);
  const old = await run({ ...healthy(), 'GET /api/build': [() => json({ ...build, protocolVersion: 2 })] });
  assert.equal(old.outcome.verdict, 'incompatible');
  assert.match(reports(old.outcome).deploy.annotation.message, /can't run the docs' projects: compiler protocol 2 predates/);
});

test('the sample exercises every library the docs import', () => {
  const source = [
    '// dart format width=60', '/// A library.', 'library;', '',
    "import 'package:a/a.dart';", "import 'b.dart'", "    if (dart.library.js_interop) 'package:c/c.dart';",
    "export 'dart:async' show Timer;", '/* A comment', "   import 'package:commented/out.dart';", '*/',
    "final text = \"import 'package:in/a_string.dart';\";", "import 'package:after/declarations.dart';",
  ].join('\n');
  assert.deepEqual([...libraries(source)], ['package:a/a.dart', 'package:c/c.dart', 'dart:async']);
  const projects = {
    one: { files: { 'main.dart': "import 'package:fleury/fleury_core.dart';\n" } },
    two: { files: { 'main.dart': "import 'package:fleury/fleury_core.dart';\n" } },
    three: { files: { 'main.dart': "import 'package:fleury/fleury_core.dart';\n", 'charts.dart': "import 'package:fleury/charts.dart';\n" } },
  };
  assert.deepEqual(selectSample(projects, ['one', 'gone']), { ids: ['one', 'three'], missing: ['gone'] });
});

const catalogue = new URL('../src/guide_projects.json', import.meta.url);
test('every sampled project is in the generated catalogue', { skip: !existsSync(catalogue) && 'run npm run guides:projects first' }, () => {
  const projects = JSON.parse(readFileSync(catalogue, 'utf8'));
  const { ids, missing } = selectSample(projects);
  assert.deepEqual(missing, []);
  for (const id of ids) runRequest(projects[id]);
  assert.ok(ids.some(id => libraries(projects[id].files['examples/registry.dart'] ?? '').has('package:fleury/themes.dart')));
});

test('annotations survive newlines, percent signs, colons and commas', () => {
  assert.equal(workflowCommand({ level: 'error', title: 'Pads: read-only, again', message: '100%\nnext' }),
    '::error title=Pads%3A read-only%2C again::100%25%0Anext');
});
