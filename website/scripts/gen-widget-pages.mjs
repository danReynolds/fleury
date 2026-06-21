// Generates the widget-reference and showcase pages from the example manifest
// (src/examples.json, produced by `dart run examples/bin/manifest.dart`).
//
//  - widgets/   one page per widget (+ a catalog index grouped by category)
//  - showcases/ one page per full-app showcase (+ an overview index)
//
// Each page embeds a live, client-side example. Showcases get their own page
// each (rather than all on one page) so only one live app + ticker runs at a
// time. Run via `npm run gen:widgets` (wired into pre{dev,build}).
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const MANIFEST = join(here, '..', 'src', 'examples.json');
const API = join(here, '..', 'src', 'api.json');
const CODE = join(here, '..', 'src', 'examples_code.json');
const DOCS = join(here, '..', 'src', 'content', 'docs');
// From src/content/docs/<section>/*.mdx up to src/components/.
const COMPONENT = '../../../components/FleuryExample.astro';
const KNOBS_COMPONENT = '../../../components/FleuryKnobs.astro';

// Widgets that get an interactive props playground instead of a static example.
// The slug must match a key in registry.dart's `knobExamples`.
const KNOB_WIDGETS = new Set(['gauge', 'progressbar', 'histogram', 'heatmap']);

const yaml = (s) => JSON.stringify(s);

// "View source" base — links each widget page back to its Dart implementation,
// the way the Flutter/dartdoc API reference does.
const REPO = 'https://github.com/danReynolds/fleury/blob/main';

// API reference + example source, extracted from the Dart source at build time.
const api = JSON.parse(readFileSync(API, 'utf8'));
const exampleCode = JSON.parse(readFileSync(CODE, 'utf8'));

// A "## Source" section linking the widget class to its file on GitHub, at the
// class declaration line.
function sourceSection(widget) {
  const e = api[widget];
  if (!e || !e.file) return '';
  const url = `${REPO}/${e.file}${e.line ? `#L${e.line}` : ''}`;
  return (
    `## Source\n\n` +
    `\`${widget}\` is defined in [\`${e.file}\`](${url}) — read the ` +
    `implementation, or jump straight to the [widget catalog](/widgets/).\n\n`
  );
}

// Escape MDX-significant chars (`<` opens a tag, `{` an expression) in prose,
// leaving fenced and inline code verbatim. For rendering source doc comments.
const mdxSafe = (md) =>
  md
    .split(/(```[\s\S]*?```)/g)
    .map((seg, i) =>
      i % 2 === 1
        ? seg
        : seg
            .split(/(`[^`]*`)/g)
            .map((s, j) =>
              j % 2 === 1
                ? s
                : s.replace(/</g, '&lt;').replace(/\{/g, '&#123;')
            )
            .join('')
    )
    .join('');

// Markdown-table-safe (and MDX-safe) cell text.
const cell = (s) =>
  String(s ?? '—')
    .replace(/\|/g, '\\|')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/\{/g, '&#123;')
    .replace(/\}/g, '&#125;');
const codeCell = (s) => '`' + String(s).replace(/\|/g, '\\|') + '`';

// A "Properties" table for a widget class, from its extracted constructor params.
function propsTable(widget) {
  const entry = api[widget];
  if (!entry || !entry.params.length) return '';
  const rows = entry.params
    .map((p) => {
      const def = p.required ? '**required**' : p.default ? codeCell(p.default) : '—';
      return `| ${codeCell(p.name)} | ${codeCell(p.type)} | ${def} | ${cell(p.doc)} |`;
    })
    .join('\n');
  return (
    `## Properties\n\n` +
    `| Property | Type | Default | Description |\n` +
    `| --- | --- | --- | --- |\n` +
    `${rows}\n\n`
  );
}

const all = JSON.parse(readFileSync(MANIFEST, 'utf8'));
const widgets = all.filter((e) => e.category !== 'Showcases');
const showcases = all.filter((e) => e.category === 'Showcases');

// ── Widget pages ────────────────────────────────────────────────────────────
const widgetsDir = join(DOCS, 'widgets');
rmSync(widgetsDir, { recursive: true, force: true });
mkdirSync(widgetsDir, { recursive: true });

for (const e of widgets) {
  const slug = e.id.split('.')[0];
  // Prefer the widget's own source doc comment (richer); fall back to the blurb.
  const intro = api[e.widget]?.classDoc ? mdxSafe(api[e.widget].classDoc) : e.blurb;
  // An explicit `code` override (used by animated examples to keep the snippet
  // static) wins; otherwise show the code extracted from the builder.
  const snippet = e.code ?? exampleCode[e.id];
  // Knob-enabled widgets get an interactive props playground; others a static
  // (but live) example.
  const isKnob = KNOB_WIDGETS.has(slug);
  const importLine = isKnob
    ? `import FleuryKnobs from '${KNOBS_COMPONENT}';`
    : `import FleuryExample from '${COMPONENT}';`;
  const liveBlock = isKnob
    ? `<FleuryKnobs id="${slug}" cols={${e.cols}} rows={${e.rows}} />`
    : `<FleuryExample id="${e.id}" cols={${e.cols}} rows={${e.rows}}` +
      `${e.interactive ? ' interactive' : ''} />`;
  writeFileSync(
    join(widgetsDir, `${slug}.mdx`),
    `---\ntitle: ${yaml(e.widget)}\ndescription: ${yaml(e.blurb)}\n---\n\n` +
      `${importLine}\n\n` +
      `${intro}\n\n` +
      `## Example\n\n` +
      `${liveBlock}\n\n` +
      (snippet ? `\`\`\`dart\n${snippet}\n\`\`\`\n\n` : '') +
      propsTable(e.widget) +
      sourceSection(e.widget) +
      `**Category:** ${e.category} · [All widgets](/widgets/)\n`
  );
}

const byCategory = new Map();
for (const e of widgets) {
  if (!byCategory.has(e.category)) byCategory.set(e.category, []);
  byCategory.get(e.category).push(e);
}
let widgetIndex =
  `---\ntitle: Widgets\ndescription: The Fleury widget library — every page has a live, client-side example.\n---\n\n` +
  `Fleury ships a broad widget library: charts and meters, data and lists, ` +
  `document viewers, and agent surfaces. Each widget below has its own page ` +
  `with a **live example that runs in your browser** (compiled with dart2js).\n\n`;
for (const [category, items] of byCategory) {
  widgetIndex += `## ${category}\n\n`;
  for (const e of items)
    widgetIndex += `- [${e.widget}](/widgets/${e.id.split('.')[0]}/) — ${e.blurb}\n`;
  widgetIndex += `\n`;
}
writeFileSync(join(widgetsDir, 'index.mdx'), widgetIndex);

// ── Showcase pages (one app per page) ───────────────────────────────────────
const showDir = join(DOCS, 'showcases');
rmSync(showDir, { recursive: true, force: true });
mkdirSync(showDir, { recursive: true });

// Showcase slug → its sample source file (for a "view source" link).
const SAMPLE_FILES = {
  dashboard: 'dashboard.dart',
  files: 'file_manager.dart',
  agent: 'agent_tui.dart',
};
for (const e of showcases) {
  const slug = e.id.split('.')[1]; // showcase.dashboard -> dashboard
  const file = SAMPLE_FILES[slug];
  const source = file
    ? `## Source\n\n` +
      `Built entirely from Fleury widgets — see ` +
      `[\`packages/samples/lib/src/${file}\`](${REPO}/packages/samples/lib/src/${file}).\n\n`
    : '';
  writeFileSync(
    join(showDir, `${slug}.mdx`),
    `---\ntitle: ${yaml(e.widget)}\ndescription: ${yaml(e.blurb)}\n---\n\n` +
      `import FleuryExample from '${COMPONENT}';\n\n` +
      `${e.blurb}\n\n` +
      `## Example\n\n` +
      `<FleuryExample id="${e.id}" cols={${e.cols}} rows={${e.rows}}` +
      `${e.interactive ? ' interactive' : ''} />\n\n` +
      `## Run it from the terminal\n\n` +
      '```sh\n' +
      `fleury dev samples ${slug}\n` +
      '```\n\n' +
      source +
      `[All showcases](/showcases/)\n`
  );
}
const showIndex =
  `---\ntitle: Showcases\ndescription: Full Fleury apps, each running live in your browser.\n---\n\n` +
  `Three complete apps, each built entirely from Fleury widgets and **running ` +
  `live in your browser** — the real Dart, compiled to JavaScript with dart2js, ` +
  `no server. They double as runnable examples: \`fleury dev samples <app>\`.\n\n` +
  showcases
    .map((e) => `- [${e.widget}](/showcases/${e.id.split('.')[1]}/) — ${e.blurb}`)
    .join('\n') +
  `\n`;
writeFileSync(join(showDir, 'index.mdx'), showIndex);

console.log(
  `generated ${widgets.length} widget pages + ${showcases.length} showcase pages`
);
