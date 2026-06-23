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
const TYPES = join(here, '..', 'src', 'types.json');
const DOCS = join(here, '..', 'src', 'content', 'docs');
// From src/content/docs/<section>/*.mdx up to src/components/.
const COMPONENT = '../../../components/FleuryExample.astro';
const KNOBS_COMPONENT = '../../../components/FleuryKnobs.astro';
const LAYOUT_COMPONENT = '../../../components/WidgetLayout.astro';

// Widgets that get an interactive props playground instead of a static example.
// The slug must match a key in registry.dart's `knobExamples`.
const KNOB_WIDGETS = new Set(['gauge', 'progressbar', 'histogram', 'heatmap']);

// Curated extra usage examples, shown as a tabbed group under "## Usage" for
// widgets where a few variations are worth showing. Hand-written against the
// real constructor params (see src/api.json); keep them small and accurate.
const TABS_IMPORT = "import { Tabs, TabItem } from '@astrojs/starlight/components';";
const EXTRA_EXAMPLES = {
  gauge: [
    { label: 'Basic', code: `Gauge(value: 0.62, label: 'CPU')` },
    {
      label: 'Thresholds',
      code: `Gauge(
  value: 0.94,
  label: 'CPU',
  // The fill turns amber past 0.7, red past 0.9.
  thresholds: <(double, Color)>[
    (0.7, theme.colorScheme.warning),
    (0.9, theme.colorScheme.error),
  ],
)`,
    },
    {
      label: 'No percentage',
      code: `Gauge(value: 0.5, label: 'Disk', showPercentage: false)`,
    },
  ],
  progressbar: [
    { label: 'Determinate', code: `ProgressBar(value: 0.45)` },
    {
      label: 'Indeterminate',
      code: `// A null value animates an indeterminate bar.
ProgressBar(value: null)`,
    },
  ],
  sparkline: [
    { label: 'Basic', code: `Sparkline(data: const <num>[3, 5, 4, 8, 6, 9, 7])` },
    {
      label: 'With value',
      code: `Sparkline(
  data: const <num>[3, 5, 4, 8, 6, 9, 7],
  showValue: true,
)`,
    },
  ],
};

// The "## Usage" block: a tabbed group when the widget has curated extras,
// otherwise a single titled code frame from the extracted example.
function usageSection(slug, widget, snippet) {
  const extras = EXTRA_EXAMPLES[slug];
  if (extras && extras.length) {
    const items = extras
      .map(
        (ex) =>
          `<TabItem label=${yaml(ex.label)}>\n\n` +
          `\`\`\`dart\n${ex.code}\n\`\`\`\n\n` +
          `</TabItem>`
      )
      .join('\n');
    return `## Usage\n\n<Tabs>\n${items}\n</Tabs>\n\n`;
  }
  if (snippet) {
    return `## Usage\n\n\`\`\`dart title=${yaml(widget + '.dart')}\n${snippet}\n\`\`\`\n\n`;
  }
  return '';
}

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

// name -> repo source path#line, for linking type names back to their source.
const types = JSON.parse(readFileSync(TYPES, 'utf8'));

// Render a Dart type as a monospaced cell, linking any type name we know about
// to its definition on GitHub (the dartdoc "click the type" affordance). Built
// as HTML so the links survive inside a Markdown table cell.
function linkType(typeStr) {
  const esc = String(typeStr)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/\|/g, '&#124;');
  const linked = esc.replace(/[A-Z][A-Za-z0-9_]*/g, (name) =>
    types[name] ? `<a href="${REPO}/${types[name]}">${name}</a>` : name
  );
  return `<code>${linked}</code>`;
}

// A "Properties" table for a widget class, from its extracted constructor params.
function propsTable(widget) {
  const entry = api[widget];
  if (!entry || !entry.params.length) return '';
  const rows = entry.params
    .map((p) => {
      const def = p.required ? '**required**' : p.default ? codeCell(p.default) : '—';
      return `| ${codeCell(p.name)} | ${linkType(p.type)} | ${def} | ${cell(p.doc)} |`;
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
// 'Home' = the landing-hero example, mounted directly on the home page (no
// catalog entry). 'Showcases' = full apps, their own section.
const widgets = all.filter(
  (e) => e.category !== 'Showcases' && e.category !== 'Home'
);
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
    `---\ntitle: ${yaml(e.widget)}\ndescription: ${yaml(e.blurb)}\n` +
      `tableOfContents: false\n---\n\n` +
      `${importLine}\n` +
      `import WidgetLayout from '${LAYOUT_COMPONENT}';\n` +
      (EXTRA_EXAMPLES[slug] ? `${TABS_IMPORT}\n` : '') +
      `\n` +
      `<WidgetLayout>\n\n` +
      // Right column: the live (knob-tweakable) demo only — the code below is a
      // fixed usage example, so it lives in the main column, not next to it.
      `<Fragment slot="aside">\n\n` +
      `${liveBlock}\n\n` +
      `</Fragment>\n\n` +
      // Left column: description → usage example(s) → API breakdown.
      `${intro}\n\n` +
      usageSection(slug, e.widget, snippet) +
      propsTable(e.widget) +
      sourceSection(e.widget) +
      `**Category:** ${e.category} · [All widgets](/widgets/)\n\n` +
      `</WidgetLayout>\n`
  );
}

// ── Doc-only pages ──────────────────────────────────────────────────────────
// Widgets that can't be an in-browser embed — they use dart:io (filesystem,
// processes, image decoding) or are invoked imperatively. They still get a full
// reference page (description, properties, source), just no live demo.
const DOC_ONLY = [
  { slug: 'filebrowser', widget: 'FileBrowser', category: 'Inputs & controls', reason: 'native' },
  { slug: 'filepicker', widget: 'FilePicker', category: 'Inputs & controls', reason: 'native' },
  { slug: 'form', widget: 'FormPanel', category: 'Inputs & controls', reason: 'native' },
  { slug: 'image', widget: 'Image', category: 'Data & lists', reason: 'native',
    code: "Image.file('assets/logo.png', fit: ImageFit.contain)" },
  { slug: 'logregion', widget: 'LogRegion', category: 'Agent surfaces', reason: 'native' },
  { slug: 'processpanel', widget: 'ProcessPanel', category: 'Agent surfaces', reason: 'native' },
  { slug: 'terminaloutputregion', widget: 'TerminalOutputRegion', category: 'Agent surfaces', reason: 'native' },
  { slug: 'workflowsnapshot', widget: 'WorkflowSnapshot', category: 'Agent surfaces', reason: 'native' },
  { slug: 'toaster', widget: 'Toaster', category: 'Navigation & overlays', reason: 'imperative',
    code: "// Wrap your app once:\nToaster(child: app)\n\n// …then from anywhere below it:\nToaster.show(context, 'Saved', severity: ToastSeverity.success);" },
];
const docNote = (reason) => {
  if (reason === 'native')
    return (
      `:::note[Runs locally]\nThis widget uses \`dart:io\` (filesystem, processes, ` +
      `or image decoding), so it runs in a terminal or through ` +
      `[\`fleury serve\`](/architecture/serving-and-embedding/) — not as an ` +
      `in-browser embed. The reference below is generated from the source.\n:::\n`
    );
  if (reason === 'core')
    return (
      `:::note[Core widget]\nA framework primitive from \`package:fleury\` — the ` +
      `same model you know from Flutter. The reference below is generated from ` +
      `the source; the [guides](/guides/layout/) show these in context.\n:::\n`
    );
  return (
    `:::note[Imperative]\nShown by calling \`Toaster.show(context, …)\`, so ` +
    `there's no static preview — wrap your app in a \`Toaster\` once, then ` +
    `raise toasts from anywhere below it.\n:::\n`
  );
};

// Core framework widgets (from package:fleury): the layout, text, async, input,
// and builder primitives a Flutter developer reaches for. Documented from source
// like the rest of the reference; usage in context lives in the guides.
const CORE = [
  { slug: 'text', widget: 'Text', code: "Text('hello', style: CellStyle(bold: true))" },
  { slug: 'richtext', widget: 'RichText',
    code: "RichText(text: TextSpan(children: [\n  TextSpan(text: 'deploy '),\n  TextSpan(text: 'ok', style: CellStyle(bold: true)),\n]))" },
  { slug: 'textspan', widget: 'TextSpan' },
  { slug: 'listview', widget: 'ListView',
    code: "ListView.builder(\n  itemCount: rows.length,\n  itemBuilder: (context, i, selected) => Text(rows[i].label),\n)" },
  { slug: 'scrollview', widget: 'ScrollView',
    code: "ScrollView(child: Column(children: [/* tall content */]))" },
  { slug: 'futurebuilder', widget: 'FutureBuilder',
    code: "FutureBuilder<List<Item>>(\n  future: load(),\n  builder: (context, snapshot) => snapshot.hasData\n      ? ItemList(snapshot.data!)\n      : const Text('Loading…'),\n)" },
  { slug: 'streambuilder', widget: 'StreamBuilder' },
  { slug: 'gesturedetector', widget: 'GestureDetector',
    code: "GestureDetector(\n  onTap: _select,\n  onTapDown: (col, row) => _placeAt(col, row),\n  child: child,\n)" },
  { slug: 'mouseregion', widget: 'MouseRegion' },
  { slug: 'layoutbuilder', widget: 'LayoutBuilder',
    code: "LayoutBuilder(\n  builder: (context, constraints) =>\n      (constraints.maxCols ?? 0) > 60 ? Wide() : Narrow(),\n)" },
  { slug: 'listenablebuilder', widget: 'ListenableBuilder' },
  { slug: 'container', widget: 'Container' },
  { slug: 'sizedbox', widget: 'SizedBox' },
  { slug: 'padding', widget: 'Padding' },
  { slug: 'align', widget: 'Align' },
  { slug: 'positioned', widget: 'Positioned' },
  { slug: 'wrap', widget: 'Wrap' },
  { slug: 'flexible', widget: 'Flexible' },
  { slug: 'spacer', widget: 'Spacer' },
  { slug: 'constrainedbox', widget: 'ConstrainedBox' },
  { slug: 'aspectratio', widget: 'AspectRatio' },
].map((d) => ({ ...d, category: 'Core widgets', reason: 'core' }));

const DOC_PAGES = [...DOC_ONLY, ...CORE];
for (const d of DOC_PAGES) {
  const intro = api[d.widget]?.classDoc ? mdxSafe(api[d.widget].classDoc) : '';
  writeFileSync(
    join(widgetsDir, `${d.slug}.mdx`),
    `---\ntitle: ${yaml(d.widget)}\n` +
      `description: ${yaml(api[d.widget]?.doc ?? d.widget)}\n---\n\n` +
      (intro ? `${intro}\n\n` : '') +
      `${docNote(d.reason)}\n` +
      (d.code ? `## Usage\n\n\`\`\`dart\n${d.code}\n\`\`\`\n\n` : '') +
      propsTable(d.widget) +
      sourceSection(d.widget) +
      `**Category:** ${d.category} · [All widgets](/widgets/)\n`
  );
}

const byCategory = new Map();
for (const e of widgets) {
  if (!byCategory.has(e.category)) byCategory.set(e.category, []);
  byCategory.get(e.category).push(e);
}
// Fold the doc-only widgets into the catalog index, flagged so the lack of a
// live demo is no surprise.
for (const d of DOC_PAGES) {
  const tag = d.reason === 'native'
    ? ' *(runs locally)*'
    : d.reason === 'core'
      ? ' *(core)*'
      : ' *(imperative)*';
  const blurb = (api[d.widget]?.doc ?? '') + tag;
  if (!byCategory.has(d.category)) byCategory.set(d.category, []);
  byCategory.get(d.category).push({ widget: d.widget, id: d.slug, blurb });
}
let widgetIndex =
  `---\ntitle: Overview\ndescription: The Fleury widget library — every page has a live, client-side example.\n---\n\n` +
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

// Showcase slug → its sample source file (for a "view source" link + the
// "widgets used" extraction).
const SAMPLE_FILES = {
  dashboard: 'dashboard.dart',
  files: 'file_manager.dart',
  agent: 'agent_tui.dart',
};
const SHOWCASE_COMPONENT = '../../../components/ShowcaseWidgets.astro';
const SHOWCASE_STAGE_COMPONENT = '../../../components/ShowcaseStage.astro';
const SAMPLES_DIR = join(here, '..', '..', 'packages', 'samples', 'lib', 'src');

// One-paragraph pitch per showcase: what it is + why Fleury made it easy.
const SHOWCASE_GOALS = {
  dashboard:
    'A live operations dashboard — per-core gauges, a streaming history chart, ' +
    "and a sortable process table — the kind of thing you'd normally reach for " +
    'htop or a Grafana panel to build.\n\n' +
    "In Fleury it's one widget tree: the same `Gauge`, `Sparkline`, `LineChart`, " +
    "and `DataTable` you'd use anywhere, composed with `Row`/`Column` and updated " +
    'on a ticker. No canvas math, no manual redraw bookkeeping — call `setState`, ' +
    'and the framework repaints only the cells that changed, so the graphs stream ' +
    'smoothly.',
  files:
    'A two-pane file explorer whose preview adapts to each file type. The left ' +
    "pane is a tree; the right pane swaps in the right viewer for what's selected " +
    '— `CodeView` for source, `MarkdownView` for docs, `JsonView` for data.\n\n' +
    'Each viewer is a drop-in widget with selection, scrolling, and copy already ' +
    'handled, so "the preview matches the file" comes down to a `switch` in ' +
    '`build()`.',
  agent:
    'A Claude-Code-style streaming session — prose, tool cards, a live todo list, ' +
    'a colored diff, a prompt box.\n\n' +
    'None of it uses special "agent" widgets: it is just the Fleury primitives ' +
    'over a cell grid, expressive enough that a rich agent UI comes down to ' +
    'layout and color. And because it is an ordinary Fleury tree, the same UI is ' +
    'inspectable as a semantic graph — so a test, or another agent, can read it. ' +
    'See [Built for agents](/architecture/agents-and-semantics/).',
};

// Catalog widget name → { slug, category }, for the "widgets used" links.
const catalog = new Map();
for (const e of widgets)
  catalog.set(e.widget, { slug: e.id.split('.')[0], category: e.category });
for (const d of DOC_ONLY) catalog.set(d.widget, { slug: d.slug, category: d.category });
const widgetsUsedIn = (file) => {
  const src = readFileSync(join(SAMPLES_DIR, file), 'utf8');
  const used = [];
  for (const [name, info] of catalog) {
    if (new RegExp(`\\b${name}\\(`).test(src))
      used.push({ name, slug: info.slug, category: info.category });
  }
  return used;
};

for (const e of showcases) {
  const slug = e.id.split('.')[1]; // showcase.dashboard -> dashboard
  const file = SAMPLE_FILES[slug];
  const used = file ? widgetsUsedIn(file) : [];
  writeFileSync(
    join(showDir, `${slug}.mdx`),
    `---\ntitle: ${yaml(e.widget)}\ndescription: ${yaml(e.blurb)}\n` +
      `tableOfContents: false\n---\n\n` +
      `import FleuryExample from '${COMPONENT}';\n` +
      `import ShowcaseStage from '${SHOWCASE_STAGE_COMPONENT}';\n` +
      `import ShowcaseWidgets from '${SHOWCASE_COMPONENT}';\n\n` +
      // Richer intro, above the demo: the "what it is + why it was easy" pitch
      // (it leads with the description). The demo then sits in a <ShowcaseStage>
      // with the run command + source link in the right-side rail beside it.
      `${SHOWCASE_GOALS[slug] ?? e.blurb}\n\n` +
      `<ShowcaseStage runCmd="fleury dev samples ${slug}"` +
      (file
        ? ` sourceFile="${file}" sourceUrl="${REPO}/packages/samples/lib/src/${file}"`
        : '') +
      `>\n` +
      `  <FleuryExample id="${e.id}" cols={${e.cols}} rows={${e.rows}}` +
      `${e.interactive ? ' interactive' : ''} />\n` +
      `</ShowcaseStage>\n\n` +
      `## Widgets used\n\n` +
      `<ShowcaseWidgets widgets={${JSON.stringify(used)}} />\n\n` +
      `[All showcases](/showcases/)\n`
  );
}
const showIndex =
  `---\ntitle: Showcases\ndescription: Full Fleury apps, each running live in your browser.\n---\n\n` +
  `Three complete apps, each built entirely from Fleury widgets and **running ` +
  `live in your browser** — open one and use your keyboard and mouse. Each is ` +
  `also a runnable native sample: \`fleury dev samples <app>\`.\n\n` +
  showcases
    .map((e) => `- [${e.widget}](/showcases/${e.id.split('.')[1]}/) — ${e.blurb}`)
    .join('\n') +
  `\n`;
writeFileSync(join(showDir, 'index.mdx'), showIndex);

console.log(
  `generated ${widgets.length} widget pages + ${showcases.length} showcase pages`
);
