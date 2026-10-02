// Checks that the live Pad compiler can run the docs about to be built.
//
// Pages deploys the docs on every push to main, but the compiler behind their
// Run buttons is released by hand (experiments/fleury_pad/DEPLOYMENT.md). When
// the docs start using a library or API the serving compiler predates, every
// editable demo's Run fails to compile, as it did for over an hour after #291
// ("Target of URI doesn't exist: 'package:fleury/themes.dart'"). This compiles
// a sample of the docs' own Pad projects on the live compiler, sending what a
// reader's unedited Run sends from the docs' origin, and reaches a verdict:
//
// - compatible: every sampled project compiled.
// - incompatible: the compiler answered, and can't compile one of them. A
//   compiler release from this commit fixes that.
// - unavailable: the compiler didn't answer, even after retries, or refused
//   the docs' origin.
//
// A deploy builds with the compiler only when compatible; otherwise Pads are
// read-only (their prebuilt demos, no Run). A pull request's build is never
// changed: the check only annotates it.
//
//   node website/scripts/pad-compiler-guard.mjs --compiler https://… \
//     [--mode deploy|pull-request] [--projects src/guide_projects.json]
//
// Generate the projects first (npm run guides:projects). In GitHub Actions it
// also writes the step outputs `verdict` and `compiler-url` (the compiler the
// build should use, empty for read-only Pads), a job summary and an
// annotation. It exits 0 whenever it reaches a verdict.
import { appendFileSync, readFileSync, realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { SourceProject } from '../../experiments/fleury_pad/dartpad/web/source-project.mjs';

/** The published docs' origin; the compiler serves only this one. */
export const DOCS_ORIGIN = 'https://danreynolds.github.io';

/**
 * The docs projects every check compiles: the home page demo, guide demos
 * (`commands.overview` and `input.press` span five files; `loading.snapshot`
 * also imports package:http and package:image), the theming guide's
 * package:fleury/themes.dart, and widget reference pages. [selectSample]
 * adds a project for any library none of these import.
 */
export const SAMPLE = [
  'home.pad', 'guide.hot-reload', 'commands.overview', 'input.press', 'loading.snapshot',
  'themes.custom', 'state.shop', 'sparkline.basic', 'datatable.basic', 'textinput.basic',
];

/**
 * A request waits up to the browser's 65 seconds: Cloud Run's request window,
 * including a cold start. What may pass on its own is retried after a pause.
 */
export const LIMITS = {
  deploy: { attempts: 3, timeoutMs: 65_000, backoffMs: [3_000, 10_000], budgetMs: 300_000 },
  'pull-request': { attempts: 2, timeoutMs: 65_000, backoffMs: [3_000], budgetMs: 120_000 },
};

/** The `dart:` and `package:` libraries a Dart file imports or exports. */
export function libraries(source) {
  const found = new Set();
  let directive = '', comment = false;
  // Directives precede every declaration: read up to the first other line.
  for (let line of source.split('\n')) {
    line = line.trim();
    if (comment) {
      if (!line.includes('*/')) continue;
      comment = false;
      line = line.slice(line.indexOf('*/') + 2).trim();
    }
    while (line.startsWith('/*')) {
      const end = line.indexOf('*/', 2);
      if (end < 0) { comment = true; line = ''; break; }
      line = line.slice(end + 2).trim();
    }
    if (directive || /^(import|export)\b/.test(line)) {
      directive += ` ${line}`;
      if (!line.includes(';')) continue;
      for (const match of directive.matchAll(/(['"])((?:dart|package):[^'"]+)\1/g)) found.add(match[2]);
      directive = '';
    } else if (line && !line.startsWith('//') && !line.startsWith('@') && !/^(library|part)\b/.test(line)) {
      break;
    }
  }
  return found;
}

/**
 * The projects to compile: [named]'s, then the first project to import each
 * library those don't, so a newly imported library is always exercised.
 * `missing` lists names the catalogue no longer has.
 */
export function selectSample(projects, named = SAMPLE) {
  const imports = id => Object.values(projects[id].files).flatMap(source => [...libraries(source)]);
  const ids = named.filter(id => projects[id]);
  const covered = new Set(ids.flatMap(imports));
  for (const id of Object.keys(projects)) {
    if (ids.includes(id) || imports(id).every(uri => covered.has(uri))) continue;
    ids.push(id);
    for (const uri of imports(id)) covered.add(uri);
  }
  return { ids, missing: named.filter(id => !projects[id]) };
}

/** What a reader's unedited Run sends for a docs project (dartpad/web/editor.js). */
export function runRequest(project) {
  const workspace = new SourceProject(project);
  const { source, files } = workspace.snapshot({});
  return { source, files, activeFile: workspace.views[0].file };
}

/** A failed compile's first error, as the docs would show it. */
export function firstError({ status, body }) {
  const issue = body?.issues?.find(issue => issue.kind === 'error') ?? body?.issues?.[0];
  if (issue) {
    const at = issue.location ? `:${issue.location.line}:${issue.location.column}` : '';
    return `${issue.file ?? 'main.dart'}${at}: ${issue.message}`;
  }
  const message = String(body?.error ?? '').split('\n').find(line => line.trim());
  return message?.trim() || `HTTP ${status}`;
}

// No response (network error, timeout), a body that timed out, a busy
// compiler, or a 5xx (cold start, restart, outage): these may pass on retry.
const transient = status => status === null || status === 408 || status === 429 || status >= 500;
// The compiler is there but won't serve the docs' requests.
const refusing = new Set([401, 403, 404, 405]);

/**
 * Compiles [targets] (`{id, body}`) on [compiler] as the docs would, and
 * returns `{verdict, build, problem, results}`. `problem` is a failure that
 * stopped the check before any project; `results` has one entry per project
 * checked: `{id, kind, error, attempts, ms}`, where `kind` is `ok`, `failed`
 * (the compiler couldn't compile it), `refused` or `transient`.
 */
export async function check({
  compiler, targets, origin = DOCS_ORIGIN, limits = LIMITS.deploy,
  fetch = globalThis.fetch, sleep = ms => new Promise(resolve => setTimeout(resolve, ms)),
  now = Date.now, log = () => {},
}) {
  const deadline = now() + limits.budgetMs;
  const describe = response => response.status === null ? response.reason
    : `HTTP ${response.status}${response.body?.error ? `: ${String(response.body.error).split('\n')[0]}` : ''}`;
  const cors = `the compiler doesn't grant ${origin} access (CORS)`;

  async function send(path, init = {}) {
    const remaining = deadline - now();
    if (remaining <= 0) return { status: null, reason: 'the check ran out of time' };
    const timeout = Math.min(limits.timeoutMs, remaining);
    try {
      const response = await fetch(compiler + path, {
        ...init, signal: AbortSignal.timeout(timeout),
        headers: { origin, 'user-agent': 'fleury-docs-pad-check', ...init.headers },
      });
      const text = await response.text();
      let body = null;
      try { body = JSON.parse(text); } catch {}
      return {
        status: response.status, body,
        granted: response.headers.get('access-control-allow-origin') === origin,
        retryAfterMs: (Number(response.headers.get('retry-after')) || 0) * 1000,
      };
    } catch (error) {
      return { status: null, reason: error?.name === 'TimeoutError'
        ? `no response within ${Math.round(timeout / 1000)} s`
        : `no response (${error?.cause?.code ?? error?.cause?.message ?? error?.message ?? error})` };
    }
  }

  // Repeats [attempt] while its outcome is transient, within the budget.
  async function persist(attempt) {
    for (let n = 1; ; n++) {
      const outcome = { ...(await attempt()), attempts: n };
      if (outcome.kind !== 'transient') return outcome;
      const wait = Math.min(30_000, Math.max(outcome.retryAfterMs ?? 0, limits.backoffMs[n - 1] ?? limits.backoffMs.at(-1)));
      if (n >= limits.attempts || now() + wait >= deadline) {
        return { ...outcome, error: n > 1 ? `${outcome.error} (${n} attempts)` : outcome.error };
      }
      log(`  ${outcome.error}; retrying in ${wait / 1000} s`);
      await sleep(wait);
    }
  }

  async function readBuild() {
    const response = await send('/api/build');
    if (transient(response.status)) return { kind: 'transient', error: describe(response), retryAfterMs: response.retryAfterMs };
    if (response.status !== 200 || typeof response.body?.buildId !== 'string') {
      return { kind: 'refused', error: response.status === 200 ? 'not a Pad compiler (no build ID)' : describe(response) };
    }
    if (!response.granted) return { kind: 'refused', error: cors };
    // The docs refuse an older compiler for their projects.
    if (!(response.body.protocolVersion >= 3)) {
      return { kind: 'failed', error: `compiler protocol ${response.body.protocolVersion ?? 'unknown'} predates the docs' projects, which need 3` };
    }
    return { kind: 'ok', build: response.body };
  }

  // Browsers preflight the docs' compile requests.
  async function preflight() {
    const response = await send('/api/v3/compileNewDDC', { method: 'OPTIONS', headers: {
      'access-control-request-method': 'POST', 'access-control-request-headers': 'content-type,x-fleury-build',
    } });
    if (transient(response.status)) return { kind: 'transient', error: describe(response), retryAfterMs: response.retryAfterMs };
    if (response.status < 200 || response.status > 299 || !response.granted) {
      return { kind: 'refused', error: `the compiler refused ${origin}'s preflight (${describe(response)})` };
    }
    return { kind: 'ok' };
  }

  const result = { verdict: 'compatible', build: null, problem: null, results: [] };
  const finish = () => {
    const kinds = [result.problem?.kind, ...result.results.map(entry => entry.kind)].filter(Boolean);
    result.verdict = kinds.includes('failed') ? 'incompatible'
      : kinds.some(kind => kind !== 'ok') || result.results.length < targets.length ? 'unavailable' : 'compatible';
    return result;
  };

  const build = await persist(readBuild);
  if (build.kind !== 'ok') { result.problem = build; return finish(); }
  let current = result.build = build.build;
  log(`Compiler build ${current.buildId} (protocol ${current.protocolVersion}, from ${current.sourceRevision ?? 'unknown source'})`);
  const allowed = await persist(preflight);
  if (allowed.kind !== 'ok') { result.problem = allowed; return finish(); }

  for (const target of targets) {
    const started = now();
    const outcome = await persist(async () => {
      if (!current) {
        const refreshed = await readBuild();
        if (refreshed.kind !== 'ok') return refreshed;
        current = result.build = refreshed.build;
      }
      const response = await send('/api/v3/compileNewDDC', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-fleury-build': current.buildId },
        body: JSON.stringify(target.body),
      });
      if (transient(response.status)) return { kind: 'transient', error: describe(response), retryAfterMs: response.retryAfterMs };
      // A new compiler build is serving: ask for it, then try again.
      if (response.status === 409) { current = null; return { kind: 'transient', error: describe(response) }; }
      if (refusing.has(response.status)) return { kind: 'refused', error: describe(response) };
      if (response.status !== 200) return { kind: 'failed', error: firstError(response) };
      if (typeof response.body?.result !== 'string' || typeof response.body?.deltaDill !== 'string' || !response.body.deltaDill) {
        return { kind: 'failed', error: 'the compiler returned no runnable app' };
      }
      return response.granted ? { kind: 'ok' } : { kind: 'refused', error: cors };
    });
    const entry = { id: target.id, kind: outcome.kind, error: outcome.error, attempts: outcome.attempts, ms: now() - started };
    result.results.push(entry);
    log(`${target.id}: ${entry.kind === 'ok' ? `compiled in ${entry.ms} ms` : entry.error}`);
    // The compiler can't be asked; the rest would only wait the same way.
    if (outcome.kind === 'transient' || outcome.kind === 'refused') break;
  }
  return finish();
}

/**
 * The compiler URL a build should use. A deploy enables Run only on evidence
 * that it works; a pull request's build is never changed by the check.
 */
export function compilerFor(mode, verdict, compiler) {
  return mode === 'pull-request' || verdict === 'compatible' ? compiler : '';
}

/**
 * The annotation (`{level, title, message}`, or null) and the markdown job
 * summary for an outcome. [commit] is the commit being checked.
 */
export function report({ mode, compiler, outcome, total, commit = '' }) {
  const { verdict, build, problem, results = [] } = outcome;
  const deploy = mode === 'deploy';
  const short = sha => sha ? String(sha).slice(0, 8) : 'an unknown commit';
  const compilerName = build
    ? `The live Pad compiler (build ${build.buildId}, from ${short(build.sourceRevision)})`
    : `The live Pad compiler at ${compiler}`;
  const release = 'Release the Pad compiler from this commit, then re-run this workflow.';
  const afterMerge = 'Once this merges, the docs deploy with read-only Pads until the compiler is released from main and the docs workflow re-runs.';
  let annotation = null, heading, lines;
  if (verdict === 'skipped') {
    annotation = deploy
      ? { level: 'notice', title: 'Pads are read-only', message: 'FLEURY_PAD_COMPILER_URL is empty, so this build has read-only Pads.' }
      : { level: 'notice', title: 'Pad compiler not checked', message: 'No compiler URL is available to this run (FLEURY_PAD_COMPILER_URL is unset, or this pull request comes from a fork).' };
    heading = annotation.title;
    lines = [annotation.message];
  } else if (verdict === 'compatible') {
    heading = deploy ? 'Pad compiler: Run enabled' : 'Pad compiler: compatible';
    lines = [`${compilerName} compiled all ${total} sampled docs projects${deploy ? ', so this build enables Run.' : ' from this pull request.'}`];
  } else if (verdict === 'incompatible') {
    const failed = results.filter(entry => entry.kind === 'failed');
    const finding = problem?.kind === 'failed'
      ? `${compilerName} can't run the docs' projects: ${problem.error}`
      : `${compilerName} can't compile ${failed.length} of ${total} sampled docs projects${deploy ? '' : ' from this pull request'}`;
    const named = failed.map(entry => `${entry.id} (${entry.error.slice(0, 200)})`).join('; ');
    const found = named ? `${finding}: ${named}` : finding;
    annotation = deploy
      ? { level: 'error', title: 'Pads are read-only in this deploy', message: `${found}. This deploy leaves Pads read-only. ${release}` }
      : { level: 'warning', title: 'Needs a Pad compiler release after merge', message: `${found}. ${afterMerge}` };
    heading = annotation.title;
    lines = deploy
      ? [`${finding}, so this deploy leaves the compiler URL empty: Pads show their prebuilt demos, read-only.`,
        `**${release}** (Commit \`${short(commit)}\`; see experiments/fleury_pad/DEPLOYMENT.md.)`]
      : [`${finding}.`, afterMerge];
  } else {
    const reason = problem?.error ?? results.find(entry => entry.kind === 'transient' || entry.kind === 'refused')?.error;
    annotation = deploy
      ? { level: 'error', title: 'Pads are read-only in this deploy',
        message: `Couldn't check the live Pad compiler at ${compiler}: ${reason}. This deploy leaves Pads read-only rather than risk a broken Run. Re-run this workflow once the compiler serves the docs again; to withdraw it on purpose, unset FLEURY_PAD_COMPILER_URL.` }
      : { level: 'notice', title: 'Pad compiler not checked', message: `Couldn't check this pull request's docs projects on the live Pad compiler at ${compiler}: ${reason}.` };
    heading = annotation.title;
    lines = [annotation.message];
  }
  const outcomes = { failed: "can't compile", refused: 'refused', transient: 'no answer' };
  const cell = text => text.replace(/\s*\n\s*/g, ' ').replaceAll('|', '\\|');
  const rows = results.map(entry => `| \`${entry.id}\` | ${entry.kind === 'ok' ? `compiled in ${entry.ms} ms`
    : `${outcomes[entry.kind]}: ${cell(entry.error)}`} |`);
  const markdown = [`### ${heading}`, '', ...lines.flatMap(line => [line, '']),
    ...(rows.length ? ['| Project | Result |', '| --- | --- |', ...rows, ''] : [])].join('\n');
  return { annotation, markdown };
}

/** A GitHub Actions workflow command for [annotation]. */
export function workflowCommand({ level, title, message }) {
  const data = value => value.replaceAll('%', '%25').replaceAll('\r', '%0D').replaceAll('\n', '%0A');
  const property = value => data(value).replaceAll(':', '%3A').replaceAll(',', '%2C');
  return `::${level} title=${property(title)}::${data(message)}`;
}

async function main() {
  const repo = new URL('../../', import.meta.url);
  const { values } = parseArgs({ options: {
    compiler: { type: 'string', default: '' },
    mode: { type: 'string', default: 'deploy' },
    projects: { type: 'string', default: fileURLToPath(new URL('website/src/guide_projects.json', repo)) },
    // The Pad page runs its starter on arrival: one file, no project.
    'pad-sample': { type: 'string', default: fileURLToPath(new URL('experiments/fleury_pad/lib/main.dart', repo)) },
    origin: { type: 'string', default: DOCS_ORIGIN },
  } });
  const mode = values.mode;
  if (!LIMITS[mode]) throw new Error('--mode must be deploy or pull-request.');
  const compiler = values.compiler.trim().replace(/\/$/, '');
  const projects = JSON.parse(readFileSync(values.projects, 'utf8'));
  const { ids, missing } = selectSample(projects);
  const targets = ids.map(id => ({ id, body: runRequest(projects[id]) }));
  if (values['pad-sample']) targets.push({ id: 'pad', body: { source: readFileSync(values['pad-sample'], 'utf8') } });
  // Nothing checked is no evidence; failing here leaves a deploy read-only.
  if (!targets.length) throw new Error(`No docs projects to check in ${values.projects}.`);
  const actions = process.env.GITHUB_ACTIONS === 'true';
  if (missing.length) {
    const message = `SAMPLE in website/scripts/pad-compiler-guard.mjs names projects the docs no longer have: ${missing.join(', ')}.`;
    console.log(actions ? workflowCommand({ level: 'warning', title: 'Pad compiler check', message }) : message);
  }
  console.log(`Checking ${targets.length} docs projects on ${compiler || '(no compiler)'} from ${values.origin} (${mode}).`);
  const outcome = compiler
    ? await check({ compiler, targets, origin: values.origin, limits: LIMITS[mode], log: line => console.log(line) })
    : { verdict: 'skipped', results: [] };
  const url = compilerFor(mode, outcome.verdict, compiler);
  const { annotation, markdown } = report({ mode, compiler, outcome, total: targets.length, commit: process.env.GITHUB_SHA });
  if (annotation) console.log(actions ? workflowCommand(annotation) : `${annotation.level}: ${annotation.message}`);
  console.log(`Verdict: ${outcome.verdict}. ${mode === 'pull-request' ? 'This pull request builds as configured.'
    : url ? `This build enables Run with ${url}.` : 'This build has read-only Pads (no compiler URL).'}`);
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${markdown}\n`);
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `verdict=${outcome.verdict}\ncompiler-url=${url}\n`);
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => {
    console.error(error);
    process.exitCode = 2;
  });
}
