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
const DOCS = join(here, '..', 'src', 'content', 'docs');
// From src/content/docs/<section>/*.mdx up to src/components/.
const COMPONENT = '../../../components/FleuryExample.astro';

const yaml = (s) => JSON.stringify(s);
const note = (widget) =>
  `:::note\nThis example runs entirely in your browser — the real \`${widget}\` ` +
  `compiled to JavaScript with dart2js (no server). See ` +
  `[Serving and embedding](/architecture/serving-and-embedding/).\n:::\n`;

const all = JSON.parse(readFileSync(MANIFEST, 'utf8'));
const widgets = all.filter((e) => e.category !== 'Showcases');
const showcases = all.filter((e) => e.category === 'Showcases');

// ── Widget pages ────────────────────────────────────────────────────────────
const widgetsDir = join(DOCS, 'widgets');
rmSync(widgetsDir, { recursive: true, force: true });
mkdirSync(widgetsDir, { recursive: true });

for (const e of widgets) {
  const slug = e.id.split('.')[0];
  writeFileSync(
    join(widgetsDir, `${slug}.mdx`),
    `---\ntitle: ${yaml(e.widget)}\ndescription: ${yaml(e.blurb)}\n---\n\n` +
      `import FleuryExample from '${COMPONENT}';\n\n` +
      `${e.blurb}\n\n` +
      `<FleuryExample id="${e.id}" cols={${e.cols}} rows={${e.rows}} />\n\n` +
      `${note(`${e.widget}\` widget,`)}\n` +
      `**Category:** ${e.category} · [Back to all widgets](/widgets/)\n`
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

for (const e of showcases) {
  const slug = e.id.split('.')[1]; // showcase.dashboard -> dashboard
  writeFileSync(
    join(showDir, `${slug}.mdx`),
    `---\ntitle: ${yaml(e.widget)}\ndescription: ${yaml(e.blurb)}\n---\n\n` +
      `import FleuryExample from '${COMPONENT}';\n\n` +
      `${e.blurb}\n\n` +
      `Launch it from the terminal too:\n\n` +
      '```sh\n' +
      `fleury dev samples ${slug}\n` +
      '```\n\n' +
      `<FleuryExample id="${e.id}" cols={${e.cols}} rows={${e.rows}} />\n\n` +
      `${note('app,')}\n` +
      `[Back to all showcases](/showcases/)\n`
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
