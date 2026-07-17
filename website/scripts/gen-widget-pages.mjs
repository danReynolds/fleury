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

import { exportedClassNames } from './api-reference-exports.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const MANIFEST = join(here, '..', 'src', 'examples.json');
const API = join(here, '..', 'src', 'api.json');
const CODE = join(here, '..', 'src', 'examples_code.json');
const TYPES = join(here, '..', 'src', 'types.json');
const DOCS = join(here, '..', 'src', 'content', 'docs');
const WIDGET_BARREL = join(
  here,
  '..',
  '..',
  'packages',
  'fleury_widgets',
  'lib',
  'fleury_widgets.dart'
);
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
  // Interactive examples built from a private `_FooExample()` wrapper extract to
  // that wrapper call, which is a meaningless, leaky snippet (the wrapper is a
  // registry implementation detail, not how you use the widget). Suppress the
  // Usage block in that case — the page still has the live example + API reference.
  // Add an explicit `code:` to the registry entry to show real usage instead.
  if (snippet && !/^const\s+_\w+\(\)$/.test(snippet.trim())) {
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

// Reference pages are a public contract, so generation must not quietly turn a
// missing source comment into an em dash. Keep this check beside the generator:
// every local build then validates the exact set of pages it is about to write.
function assertReferenceComplete(widgetNames, section) {
  const failures = [];
  for (const widget of [...new Set(widgetNames)].sort()) {
    const entry = api[widget];
    if (!entry) {
      failures.push(`${widget}: no extracted API entry`);
      continue;
    }
    if (!entry.classDoc?.trim()) failures.push(`${widget}: missing class docs`);
    if (!entry.file || !entry.line) failures.push(`${widget}: missing source link`);
    // `undefined` is the pre-constructor-schema compatibility case. An explicit
    // empty list means the class has no public constructor and must not be
    // rendered as a fabricated unnamed constructor.
    const constructors = entry.constructors ?? [
      { name: widget, params: entry.params ?? [] },
    ];
    if (!constructors.length) {
      failures.push(`${widget}: missing public constructors`);
      continue;
    }
    const undocumentedNamedConstructors = constructors
      .filter((constructor) => constructor.name !== widget && !constructor.doc?.trim())
      .map(
        (constructor) =>
          `${constructor.name} (${entry.file}:${constructor.line ?? entry.line})`
      );
    if (undocumentedNamedConstructors.length) {
      failures.push(
        `${widget}: undocumented named constructors: ` +
        undocumentedNamedConstructors.join(', ')
      );
    }
    const undocumented = constructors
      .flatMap((constructor) => constructor.params ?? [])
      .filter((param) => !param.doc?.trim())
      .map((param) => param.name)
      .filter((name, index, names) => names.indexOf(name) === index);
    if (undocumented.length) {
      failures.push(`${widget}: undocumented parameters: ${undocumented.join(', ')}`);
    }
    const unresolved = constructors
      .flatMap((constructor) =>
        (constructor.params ?? [])
          .filter((param) => param.type === 'dynamic')
          .map((param) => `${constructor.name}.${param.name}`)
      );
    if (unresolved.length) {
      failures.push(`${widget}: unresolved parameter types: ${unresolved.join(', ')}`);
    }
  }
  if (failures.length) {
    throw new Error(
      `Incomplete ${section} API reference:\n- ${failures.join('\n- ')}\n` +
      'Add Dart doc comments to the public constructor fields or parameters, then run npm run generate.'
    );
  }
}

function assertExportedWidgetCoverage(entries) {
  const bySlug = new Map();
  const byWidget = new Map();
  const failures = [];
  for (const entry of entries) {
    const slug = entry.id?.split('.')[0] ?? entry.slug;
    if (bySlug.has(slug)) failures.push(`duplicate slug ${slug}`);
    if (byWidget.has(entry.widget)) failures.push(`duplicate widget ${entry.widget}`);
    bySlug.set(slug, entry.widget);
    byWidget.set(entry.widget, slug);
  }

  const exported = exportedClassNames(readFileSync(WIDGET_BARREL, 'utf8'), {
    barrelRepoDirectory: 'packages/fleury_widgets/lib',
    api,
  });
  const widgetBases = new Set([
    'Widget',
    'StatelessWidget',
    'StatefulWidget',
    'RenderObjectWidget',
    'LeafRenderObjectWidget',
    'SingleChildRenderObjectWidget',
    'MultiChildRenderObjectWidget',
    'ProxyWidget',
    'InheritedWidget',
  ]);
  const isWidget = (name, seen = new Set()) => {
    if (widgetBases.has(name)) return true;
    if (seen.has(name)) return false;
    seen.add(name);
    const parent = api[name]?.extends?.replace(/<.*>$/, '');
    return parent ? isWidget(parent, seen) : false;
  };
  const exportedWidgets = [...exported]
    .filter((name) => api[name] && !api[name].abstract && isWidget(name))
    .sort();
  const missing = exportedWidgets
    .filter((name) => !byWidget.has(name))
  if (missing.length) {
    failures.push(`exported widgets without pages: ${missing.join(', ')}`);
  }
  if (failures.length) {
    throw new Error(`Invalid widget reference coverage:\n- ${failures.join('\n- ')}`);
  }
  return exportedWidgets.length;
}

// A "## Source" section linking the widget class to its file on GitHub, at the
// class declaration line.
function sourceSection(widget) {
  const e = api[widget];
  if (!e || !e.file) return '';
  const url = `${REPO}/${e.file}${e.line ? `#L${e.line}` : ''}`;
  return (
    `## Source\n\n` +
    `\`${widget}\` is defined in [\`${e.file}\`](${url}) — read the ` +
    `implementation, or jump straight to the [widget catalog](/fleury/widgets/).\n\n`
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
  // A prefixed external type such as `img.Image` must not link its `Image`
  // suffix to Fleury's own class of the same name.
  const linked = esc.replace(/(?<!\.)\b[A-Z][A-Za-z0-9_]*/g, (name) =>
    types[name] ? `<a href="${REPO}/${types[name]}">${name}</a>` : name
  );
  return `<code>${linked}</code>`;
}

// Constructor-specific parameter tables from the source. Keeping overloads
// separate matters for APIs such as ListView.builder and Image.file: a single
// merged "properties" table can contradict the usage example above it.
function constructorsSection(widget) {
  const entry = api[widget];
  if (!entry) return '';
  const constructors = entry.constructors ?? [
    { name: widget, doc: null, params: entry.params ?? [] },
  ];
  if (!constructors.length) {
    throw new Error(`${widget} has no public constructors to document`);
  }
  let out = `## Constructors\n\n`;
  for (const constructor of constructors) {
    const params = constructor.params ?? [];
    out += `### ${codeCell(`${constructor.name}()`)}\n\n`;
    if (constructor.doc) out += `${mdxSafe(constructor.doc)}\n\n`;
    if (!params.length) {
      out += `This constructor has no public parameters.\n\n`;
      continue;
    }
    const rows = params
      .map((p) => {
        const def = p.required ? '**required**' : p.default ? codeCell(p.default) : '—';
        const name = p.named ? `${p.name}:` : p.name;
        return `| ${codeCell(name)} | ${linkType(p.type)} | ${def} | ${cell(p.doc)} |`;
      })
      .join('\n');
    out +=
      `| Parameter | Type | Default | Description |\n` +
      `| --- | --- | --- | --- |\n` +
      `${rows}\n\n`;
  }
  return out;
}

const all = JSON.parse(readFileSync(MANIFEST, 'utf8'));
// 'Home' = the landing-hero example, mounted directly on the home page (no
// catalog entry). 'Showcases' = full apps, their own section.
const widgets = all.filter(
  (e) => e.category !== 'Showcases' && e.category !== 'Home'
);
const showcases = all.filter((e) => e.category === 'Showcases');

// ── Widget pages ────────────────────────────────────────────────────────────
assertReferenceComplete(widgets.map((entry) => entry.widget), 'widget');
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
      constructorsSection(e.widget) +
      sourceSection(e.widget) +
      `**Category:** ${e.category} · [All widgets](/fleury/widgets/)\n\n` +
      `</WidgetLayout>\n`
  );
}

// ── Source-backed pages ─────────────────────────────────────────────────────
// Public APIs without an embedded registry example still get a full reference
// page. Some require dart:io, some are invoked imperatively or are supporting
// models, and some simply do not need a second live showcase.
const DOC_ONLY = [
  { slug: 'filebrowser', widget: 'FileBrowser', category: 'Inputs & controls', reason: 'native',
    code: "FileBrowser(\n  initialDirectory: Directory.current.path,\n  onActivate: (entry) => openFile(entry.path),\n)" },
  { slug: 'filepicker', widget: 'FilePicker', category: 'Inputs & controls', reason: 'native',
    code: "FilePicker(\n  initialDirectory: Directory.current.path,\n  filter: (entity) => entity is Directory || entity.path.endsWith('.dart'),\n  onSelect: (file) => openFile(file.path),\n)" },
  { slug: 'image', widget: 'Image', category: 'Data & lists', reason: 'native',
    code: "Image.file('assets/logo.png', fit: ImageFit.contain)" },
  { slug: 'logregion', widget: 'LogRegion', category: 'Agent surfaces', reason: 'native',
    code: "LogRegion(\n  entries: const [\n    LogEntry(message: 'Starting build', source: 'build'),\n    LogEntry(message: 'Tests failed', severity: LogSeverity.error),\n  ],\n  filter: const LogRegionFilterDescriptor(query: 'build'),\n)" },
  { slug: 'processpanel', widget: 'ProcessPanel', category: 'Agent surfaces', reason: 'native',
    code: "final controller = ProcessTaskController(id: 'doctor', label: 'Doctor');\n\nProcessPanel(\n  controller: controller,\n  command: const ProcessTaskCommand('dart', ['--version']),\n)" },
  { slug: 'terminaloutputregion', widget: 'TerminalOutputRegion', category: 'Agent surfaces', reason: 'native',
    code: "TerminalOutputRegion(\n  buffer: LogBuffer(),\n  label: 'Build output',\n  filter: const LogRegionFilterDescriptor(severities: {LogSeverity.error}),\n)" },
  { slug: 'workflowsnapshot', widget: 'WorkflowSnapshot', category: 'Supporting models', reason: 'native-model',
    code: "final snapshot = WorkflowSnapshot(\n  title: 'Release check',\n  tasks: const [\n    TaskGraphNode(id: 'tests', label: 'Tests', status: TaskGraphStatus.running),\n  ],\n);\n\nfinal health = snapshot.summary.health;" },
  { slug: 'toaster', widget: 'Toaster', category: 'Navigation & overlays', reason: 'imperative',
    code: "// Wrap your app once:\nToaster(child: app)\n\n// …then from anywhere below it:\nToaster.show(context, 'Saved', severity: ToastSeverity.success);" },
];
const docNote = (reason) => {
  if (reason === 'native')
    return (
      `:::note[Runs locally]\nThis widget uses \`dart:io\` (filesystem, processes, ` +
      `or image decoding), so it runs in a terminal or through ` +
      `[\`fleury serve\`](/fleury/architecture/serving-and-embedding/) — not as an ` +
      `in-browser embed. The reference below is generated from the source.\n:::\n`
    );
  if (reason === 'native-model')
    return (
      `:::note[Supporting model]\nThis is a protocol-neutral data snapshot, not ` +
      `a widget or an I/O service. Its current \`LogEntry\` dependency lives ` +
      `in the native-only log library, so use it in a terminal or through ` +
      `[\`fleury serve\`](/fleury/architecture/serving-and-embedding/), not in a ` +
      `client-side embed.\n:::\n`
    );
  if (reason === 'core')
    return (
      `:::note[Core widget]\nA framework primitive from \`package:fleury\` — the ` +
      `same model you know from Flutter. The reference below is generated from ` +
      `the source; the [guides](/fleury/guides/layout/) show these in context.\n:::\n`
    );
  if (reason === 'reference')
    return (
      `:::note[Source-backed reference]\nThis public widget does not have an ` +
      `embedded showcase on this page. Its constructor reference is generated ` +
      `directly from the current Dart source.\n:::\n`
    );
  return (
    `:::note[Imperative]\nShown by calling \`Toaster.show(context, …)\`, so ` +
    `there's no static preview — wrap your app in a \`Toaster\` once, then ` +
    `raise toasts from anywhere below it.\n:::\n`
  );
};

// Every exported higher-level widget gets a page, even when it is not useful to
// duplicate its behavior as a standalone embedded example.
const REFERENCE_ONLY = [
  { slug: 'canvas', widget: 'Canvas', category: 'Charts & meters', reason: 'reference',
    code: "Canvas(\n  painter: painter,\n  bounds: const CanvasBounds(minX: 0, maxX: 10, minY: 0, maxY: 10),\n)" },
  { slug: 'checkbox', widget: 'Checkbox', category: 'Inputs & controls', reason: 'reference',
    code: "Checkbox(value: accepted, label: 'Accept', onChanged: setAccepted)" },
  { slug: 'formwizard', widget: 'FormWizard', category: 'Inputs & controls', reason: 'reference',
    code: "FormWizard(\n  definition: form,\n  steps: steps,\n  onSubmit: handleSubmit,\n)" },
  { slug: 'keyhintbar', widget: 'KeyHintBar', category: 'Navigation & overlays', reason: 'reference',
    code: "const KeyHintBar()" },
  { slug: 'markdowntext', widget: 'MarkdownText', category: 'Documents', reason: 'reference',
    code: "MarkdownText('## Status\\n\\n**Ready** to deploy.')" },
  { slug: 'multiselect', widget: 'MultiSelect', category: 'Inputs & controls', reason: 'reference',
    code: "MultiSelect<String>(\n  options: options,\n  values: selected,\n  onChanged: setSelected,\n)" },
  { slug: 'radio', widget: 'Radio', category: 'Inputs & controls', reason: 'reference',
    code: "Radio<String>(\n  value: 'fast',\n  groupValue: mode,\n  label: 'Fast',\n  onChanged: setMode,\n)" },
  { slug: 'radiogroup', widget: 'RadioGroup', category: 'Inputs & controls', reason: 'reference',
    code: "RadioGroup<String>(\n  value: mode,\n  options: const [\n    RadioOption(value: 'fast', label: 'Fast'),\n    RadioOption(value: 'safe', label: 'Safe'),\n  ],\n  onChanged: setMode,\n)" },
  { slug: 'switch', widget: 'Switch', category: 'Inputs & controls', reason: 'reference',
    code: "Switch(value: enabled, label: 'Feature', onChanged: setEnabled)" },
  { slug: 'toggle', widget: 'Toggle', category: 'Inputs & controls', reason: 'reference',
    code: "Toggle(value: enabled, label: 'Feature', onChanged: setEnabled)" },
  { slug: 'tokenmeter', widget: 'TokenMeter', category: 'Agent surfaces', reason: 'reference',
    code: "TokenMeter(usage: usage, label: 'Context')" },
];

// Core framework widgets (from package:fleury): the layout, text, async, input,
// and builder primitives a Flutter developer reaches for. Documented from source
// like the rest of the reference; usage in context lives in the guides.
const CORE = [
  { slug: 'text', widget: 'Text', code: "Text('hello', style: CellStyle(bold: true))" },
  { slug: 'richtext', widget: 'RichText',
    code: "RichText(text: TextSpan(children: [\n  TextSpan(text: 'deploy '),\n  TextSpan(text: 'ok', style: CellStyle(bold: true)),\n]))" },
  { slug: 'textspan', widget: 'TextSpan',
    code: "TextSpan(\n  text: 'deploy ',\n  children: [TextSpan(text: 'ok', style: CellStyle(bold: true))],\n)" },
  { slug: 'listview', widget: 'ListView',
    code: "ListView.builder(\n  itemCount: rows.length,\n  itemBuilder: (context, i, selected) => Text(rows[i].label),\n)" },
  { slug: 'scrollview', widget: 'ScrollView',
    code: "ScrollView(child: Column(children: [/* tall content */]))" },
  { slug: 'futurebuilder', widget: 'FutureBuilder',
    code: "FutureBuilder<List<Item>>(\n  future: load(),\n  builder: (context, snapshot) => snapshot.hasData\n      ? ItemList(snapshot.data!)\n      : const Text('Loading…'),\n)" },
  { slug: 'streambuilder', widget: 'StreamBuilder',
    code: "StreamBuilder<int>(\n  stream: ticks,\n  initialData: 0,\n  builder: (context, snapshot) => Text('tick ${snapshot.data ?? 0}'),\n)" },
  { slug: 'gesturedetector', widget: 'GestureDetector',
    code: "GestureDetector(\n  onTap: _select,\n  onTapDown: (col, row) => _placeAt(col, row),\n  child: child,\n)" },
  { slug: 'mouseregion', widget: 'MouseRegion',
    code: "MouseRegion(\n  onEnter: () => setHover(true),\n  onExit: () => setHover(false),\n  child: Text('hover me'),\n)" },
  { slug: 'layoutbuilder', widget: 'LayoutBuilder',
    code: "LayoutBuilder(\n  builder: (context, constraints) =>\n      (constraints.maxCols ?? 0) > 60 ? Wide() : Narrow(),\n)" },
  { slug: 'listenablebuilder', widget: 'ListenableBuilder',
    code: "ListenableBuilder(\n  listenable: model,\n  builder: (context, child) => Text(model.statusLabel),\n)" },
  { slug: 'container', widget: 'Container',
    code: "Container(\n  width: 32,\n  padding: const EdgeInsets.symmetric(horizontal: 1),\n  border: BoxBorder(style: BorderStyle.rounded),\n  child: Text('Settings'),\n)" },
  { slug: 'sizedbox', widget: 'SizedBox',
    code: "SizedBox(\n  width: 20,\n  height: 3,\n  child: Text('fixed area'),\n)" },
  { slug: 'padding', widget: 'Padding',
    code: "Padding(\n  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),\n  child: Text('inset'),\n)" },
  { slug: 'align', widget: 'Align',
    code: "Align(\n  alignment: Alignment.centerRight,\n  child: Text('status'),\n)" },
  { slug: 'positioned', widget: 'Positioned',
    code: "Stack(children: [\n  Text('base'),\n  Positioned(left: 4, top: 1, child: Text('overlay')),\n])" },
  { slug: 'wrap', widget: 'Wrap',
    code: "Wrap(\n  spacing: 1,\n  runSpacing: 1,\n  children: tags.map((tag) => Text('#$tag')).toList(),\n)" },
  { slug: 'flexible', widget: 'Flexible',
    code: "Row(children: [\n  Flexible(child: Text(longLabel)),\n  Text('ready'),\n])" },
  { slug: 'spacer', widget: 'Spacer',
    code: "Row(children: [\n  Text('left'),\n  const Spacer(),\n  Text('right'),\n])" },
  { slug: 'constrainedbox', widget: 'ConstrainedBox',
    code: "ConstrainedBox(\n  minWidth: 24,\n  maxWidth: 48,\n  child: Text('bounded content'),\n)" },
  { slug: 'aspectratio', widget: 'AspectRatio',
    code: "AspectRatio(\n  aspectRatio: 2.0,\n  child: Heatmap(values: values),\n)" },
].map((d) => ({ ...d, category: 'Core widgets', reason: 'core' }));

const DOC_PAGES = [...DOC_ONLY, ...REFERENCE_ONLY, ...CORE];
const exportedWidgetCount = assertExportedWidgetCoverage([
  ...widgets,
  ...DOC_PAGES,
]);
assertReferenceComplete(DOC_PAGES.map((entry) => entry.widget), 'source-only widget');
for (const d of DOC_PAGES) {
  const intro = api[d.widget]?.classDoc ? mdxSafe(api[d.widget].classDoc) : '';
  writeFileSync(
    join(widgetsDir, `${d.slug}.mdx`),
    `---\ntitle: ${yaml(d.widget)}\n` +
      `description: ${yaml(api[d.widget]?.doc ?? d.widget)}\n---\n\n` +
      (intro ? `${intro}\n\n` : '') +
      `${docNote(d.reason)}\n` +
      (d.code ? `## Usage\n\n\`\`\`dart\n${d.code}\n\`\`\`\n\n` : '') +
      constructorsSection(d.widget) +
      sourceSection(d.widget) +
      `**Category:** ${d.category} · [All widgets](/fleury/widgets/)\n`
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
      : d.reason === 'native-model'
        ? ' *(supporting model; runs locally)*'
        : d.reason === 'reference'
          ? ' *(source-backed)*'
      : ' *(imperative)*';
  const blurb = (api[d.widget]?.doc ?? '') + tag;
  if (!byCategory.has(d.category)) byCategory.set(d.category, []);
  byCategory.get(d.category).push({ widget: d.widget, id: d.slug, blurb });
}
let widgetIndex =
  `---\ntitle: Overview\ndescription: Every exported Fleury higher-level widget, plus the most-used core primitives — live where useful and source-backed throughout.\n---\n\n` +
  `This reference covers every widget exported by \`fleury_widgets\`, plus ` +
  `the core layout, text, async, and input primitives most apps reach for. ` +
  `Live client-side examples are compiled with dart2js; every page has ` +
  `constructor-specific API details generated from the ` +
  `current Dart source.\n\n`;
for (const [category, items] of byCategory) {
  widgetIndex += `## ${category}\n\n`;
  for (const e of items)
    widgetIndex += `- [${e.widget}](/fleury/widgets/${e.id.split('.')[0]}/) — ${e.blurb}\n`;
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
    'See [Built for agents](/fleury/architecture/agents-and-semantics/).',
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
      `[All showcases](/fleury/showcases/)\n`
  );
}
const showIndex =
  `---\ntitle: Showcases\ndescription: Full Fleury apps, each running live in your browser.\n---\n\n` +
  `Three complete apps, each built entirely from Fleury widgets and **running ` +
  `live in your browser** — open one and use your keyboard and mouse. Each is ` +
  `also a runnable native sample: \`fleury dev samples <app>\`.\n\n` +
  showcases
    .map((e) => `- [${e.widget}](/fleury/showcases/${e.id.split('.')[1]}/) — ${e.blurb}`)
    .join('\n') +
  `\n`;
writeFileSync(join(showDir, 'index.mdx'), showIndex);

console.log(
  `generated ${widgets.length + DOC_PAGES.length} widget/API pages + ` +
  `${showcases.length} showcase pages; covered ${exportedWidgetCount} ` +
  `exported concrete widgets`
);
