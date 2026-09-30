// Generates the widget-reference and showcase pages from the example manifest
// (src/examples.json, produced by `dart run examples/bin/manifest.dart`).
//
//  - widgets/   one page per widget (+ a catalog index grouped by category)
//  - showcases/ one page per full-app showcase (+ an overview index)
//
// Each page embeds a live, client-side example. Showcases get their own page
// each (rather than all on one page) so only one live app + ticker runs at a
// time. Run via `npm run gen:widgets` (wired into pre{dev,build}).
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, posix } from 'node:path';
import { fileURLToPath } from 'node:url';

import { exportedClassNames } from './api-reference-exports.mjs';
import { GUIDE_GROUPS } from '../src/guides.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const ROOT = join(here, '..', '..');
const MANIFEST = join(here, '..', 'src', 'examples.json');
const API = join(here, '..', 'src', 'api.json');
const CODE = join(here, '..', 'src', 'examples_code.json');
const TYPES = join(here, '..', 'src', 'types.json');
// Read by astro.config.mjs to build the grouped Widgets sidebar.
const WIDGET_SIDEBAR = join(here, '..', 'src', 'widget-sidebar.json');
const DOCS = join(here, '..', 'src', 'content', 'docs');
const WIDGET_BARREL = join(ROOT, 'packages', 'fleury_widgets', 'lib', 'fleury_widgets.dart');
// From src/content/docs/<section>/*.mdx up to src/components/.
const COMPONENT = '../../../components/FleuryExample.astro';
const KNOBS_COMPONENT = '../../../components/FleuryKnobs.astro';
const LAYOUT_COMPONENT = '../../../components/WidgetLayout.astro';

// Widgets that get an interactive props playground instead of a static example.
// The slug must match a key in registry.dart's `knobExamples`.
const KNOB_WIDGETS = new Set([
  'gauge',
  'progressbar',
  'histogram',
  'heatmap',
  'anchored',
]);

// Curated extra usage examples, shown as a tabbed group under "## Usage" for
// widgets where a few variations are worth showing. Hand-written against the
// real constructor params (see src/api.json); keep them small and accurate.
const TABS_IMPORT = "import { Tabs, TabItem } from '@astrojs/starlight/components';";
const EXTRA_EXAMPLES = {
  barchart: [
    {
      label: 'Basic',
      code: `BarChart(
  bars: <Bar>[Bar('q1', 12), Bar('q2', 19), Bar('q3', 9), Bar('q4', 22)],
  showYAxis: true,
)`,
    },
    {
      label: 'Stacked',
      code: `// Segments paint bottom to top; segmentLabels feeds the legend.
BarChart(
  bars: const <Bar>[
    Bar.stacked('host-a', [40, 30, 10]),
    Bar.stacked('host-b', [55, 25, 5]),
  ],
  segmentLabels: const ['cpu', 'mem', 'disk'],
)`,
    },
  ],
  formfield: [
    {
      label: 'Wrap a control',
      code: `FormField(
  validator: () => slug.text.isEmpty ? 'Enter a slug.' : null,
  child: TextInput(controller: slug, semanticLabel: 'Slug'),
)`,
    },
    {
      label: 'Custom value',
      code: `// One validated value built from two controls.
FormField.builder(
  validator: () => end > start ? null : 'End must be greater than start.',
  builder: (context, field) => Column(
    children: [
      Stepper(
        label: 'Start',
        value: start,
        focusNode: field.focusNode, // where an error moves focus
        onChanged: (value) {
          setState(() => start = value);
          field.valueChanged();
        },
      ),
      Stepper(
        label: 'End',
        value: end,
        onChanged: (value) {
          setState(() => end = value);
          field.valueChanged();
        },
      ),
    ],
  ),
)`,
    },
  ],
  container: [
    {
      label: 'Box',
      code: `Container(
  width: 30,
  padding: const EdgeInsets.symmetric(horizontal: 1),
  border: const BoxBorder(),
  alignment: Alignment.center,
  child: const Text('Build passed'),
)`,
    },
    {
      label: 'Filled layer',
      code: `// An opaque theme surface: content underneath doesn't show through.
Container.filled(
  padding: const EdgeInsets.all(1),
  child: const Text('Saved'),
)`,
    },
    {
      label: 'Floating chrome',
      code: `// Fill plus the theme's border, for menus, tooltips, and popovers.
Container.framed(
  padding: const EdgeInsets.symmetric(horizontal: 1),
  child: const Text('Container.framed'),
)`,
    },
  ],
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
function usageSection(slug, snippet) {
  if (slug === 'datatable') return '<DataTableExamples />\n\n';
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
    return `## Usage\n\n\`\`\`dart\n${snippet}\n\`\`\`\n\n`;
  }
  return '';
}

const yaml = (s) => JSON.stringify(s);

// Markdown reduced to the plain text a meta description or social card shows:
// code spans, emphasis, and links keep only their text.
function plainText(md) {
  return String(md)
    .split(/(`[^`]*`)/g)
    .map((part, i) =>
      i % 2 === 1
        ? part.slice(1, -1)
        : part
            .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
            .replace(/(\*\*|__)(.+?)\1/g, '$2')
            .replace(/(^|[^\w*])\*(?!\s)(.+?)\*(?!\w)/g, '$1$2')
    )
    .join('')
    .replace(/\s+/g, ' ')
    .trim();
}

// "View source" links, pinned to the commit these pages were generated from so
// a `#L…` anchor keeps pointing at the declaration it named after main moves
// on. CI provides GITHUB_SHA; a local build asks git; without either, main.
function sourceRef() {
  if (process.env.GITHUB_SHA) return process.env.GITHUB_SHA;
  try {
    const sha = execFileSync('git', ['rev-parse', 'HEAD'], {
      cwd: here,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    return /^[0-9a-f]{40}$/.test(sha) ? sha : 'main';
  } catch {
    return 'main';
  }
}
const REPO = `https://github.com/danReynolds/fleury/blob/${sourceRef()}`;

// API reference + example source, extracted from the Dart source at build time.
const api = JSON.parse(readFileSync(API, 'utf8'));
const exampleCode = JSON.parse(readFileSync(CODE, 'utf8'));
// Runnable Pad projects (npm run guides:projects), keyed by example id: a
// demo with one is editable in place; the rest stay prebuilt-only.
const padProjects = JSON.parse(readFileSync(join(here, '..', 'src', 'guide_projects.json'), 'utf8'));
const PAD_COMPONENT = '../../../components/GuidePad.astro';
const demoBlock = (e) => {
  const example = `<FleuryExample${padProjects[e.id] ? ' slot="demo"' : ''} id="${e.id}" cols={${e.cols}} rows={${e.rows}}` +
    `${e.interactive ? ' interactive' : ''} />`;
  return padProjects[e.id]
    ? `<GuidePad id="${e.id}" compact codeLabel="Example" codeMaxHeight="18rem">\n${example}\n</GuidePad>`
    : example;
};
const padImport = (e) => (padProjects[e.id] ? `import GuidePad from '${PAD_COMPONENT}';\n` : '');

// What a reference page still lacks from its source docs; empty when complete.
function referenceGaps(widget) {
  const gaps = [];
  const entry = api[widget];
  if (!entry) return [`${widget}: no extracted API entry`];
  if (!entry.classDoc?.trim()) gaps.push(`${widget}: missing class docs`);
  if (!entry.file || !entry.line) gaps.push(`${widget}: missing source link`);
  // `undefined` is the pre-constructor-schema compatibility case. An explicit
  // empty list means the class has no public constructor and must not be
  // rendered as a fabricated unnamed constructor.
  const constructors = entry.constructors ?? [
    { name: widget, params: entry.params ?? [] },
  ];
  if (!constructors.length) return [...gaps, `${widget}: missing public constructors`];
  const undocumentedNamedConstructors = constructors
    .filter((constructor) => constructor.name !== widget && !constructor.doc?.trim())
    .map(
      (constructor) =>
        `${constructor.name} (${entry.file}:${constructor.line ?? entry.line})`
    );
  if (undocumentedNamedConstructors.length) {
    gaps.push(
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
    gaps.push(`${widget}: undocumented parameters: ${undocumented.join(', ')}`);
  }
  const unresolved = constructors.flatMap((constructor) =>
    (constructor.params ?? [])
      .filter((param) => param.type === 'dynamic')
      .map((param) => `${constructor.name}.${param.name}`)
  );
  if (unresolved.length) {
    gaps.push(`${widget}: unresolved parameter types: ${unresolved.join(', ')}`);
  }
  return gaps;
}

// Reference pages are a public contract, so generation must not quietly turn a
// missing source comment into an em dash. Keep this check beside the generator:
// every local build then validates the exact set of pages it is about to write.
function assertReferenceComplete(widgetNames, section) {
  const failures = [...new Set(widgetNames)].sort().flatMap(referenceGaps);
  if (failures.length) {
    throw new Error(
      `Incomplete ${section} API reference:\n- ${failures.join('\n- ')}\n` +
      'Add Dart doc comments to the public constructor fields or parameters, then run npm run generate.'
    );
  }
}

// Pages whose source docs are still incomplete. Each is written as soon as
// every public parameter it documents has a doc comment; until then generation
// lists what is missing instead of publishing an em dash. Every other page must
// be complete, and generation fails when one is not.
const AWAITING_SOURCE_DOCS = new Set();
const deferred = new Map();
const awaitingEntries = new Set();
const publishable = (widget) => {
  if (!AWAITING_SOURCE_DOCS.has(widget)) return true;
  awaitingEntries.add(widget);
  const gaps = referenceGaps(widget);
  if (gaps.length) deferred.set(widget, gaps);
  return gaps.length === 0;
};

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
  // Widgets intentionally shipped without a generated reference page —
  // behavioral wrappers with no standalone demo. Keep this list tiny and
  // justified; a widget users pick and configure should get a page instead.
  const undocumentedWidgets = new Set([
    // The bounds primitive underneath Anchored. BoundsObserver renders
    // nothing of its own (it publishes its child's painted bounds), and
    // BoundsAnchor only positions once a live observer feeds it. Deep-dive
    // APIs for cross-tree cases; the catalogue documents Anchored.
    'BoundsObserver',
    'BoundsAnchor',
  ]);
  const exportedWidgets = [...exported]
    .filter((name) => api[name] && !api[name].abstract && isWidget(name))
    .filter((name) => !undocumentedWidgets.has(name))
    .sort();
  const missing = exportedWidgets.filter((name) => !byWidget.has(name));
  if (missing.length) {
    failures.push(`exported widgets without pages: ${missing.join(', ')}`);
  }
  // An exemption that has since gained a page is stale; drop it from the list.
  const stale = [...undocumentedWidgets].filter((name) => byWidget.has(name));
  if (stale.length) {
    failures.push(`undocumentedWidgets entries that now have pages: ${stale.join(', ')}`);
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
    `\`${widget}\` is defined in [\`${e.file}\`](${url}).\n\n`
  );
}

// ── Import line ─────────────────────────────────────────────────────────────
// Which library a reader imports for each page's widget, read from the package
// barrels rather than from a list: the app library, plus the web-safe one a
// browser build imports instead (see architecture/core-and-targets).
const LIBRARIES = {
  fleury: { app: 'fleury.dart', browser: 'fleury_core.dart' },
  fleury_widgets: { app: 'fleury_widgets.dart', browser: 'fleury_widgets_web.dart' },
};
const libraryExportCache = new Map();
// Class names a library exports, following `export 'other_barrel.dart';` hops
// (fleury.dart re-exports fleury_host.dart, which re-exports fleury_core.dart).
function libraryExports(repoPath, seen = new Set()) {
  if (libraryExportCache.has(repoPath)) return libraryExportCache.get(repoPath);
  if (seen.has(repoPath)) return new Set();
  seen.add(repoPath);
  const text = readFileSync(join(ROOT, repoPath), 'utf8');
  const directory = posix.dirname(repoPath);
  const names = exportedClassNames(text, { barrelRepoDirectory: directory, api });
  for (const [, uri] of text.matchAll(/^export\s+'([^':]+)'/gm)) {
    if (uri.startsWith('src/')) continue;
    for (const name of libraryExports(posix.join(directory, uri), seen)) names.add(name);
  }
  libraryExportCache.set(repoPath, names);
  return names;
}
function importLine(widget) {
  const file = api[widget]?.file ?? '';
  const pkg = file.match(/^packages\/([^/]+)\/lib\//)?.[1];
  const libraries = LIBRARIES[pkg];
  if (!libraries) throw new Error(`${widget}: no import known for ${file}`);
  const uri = (library) => `\`package:${pkg}/${library}\``;
  const inApp = libraryExports(`packages/${pkg}/lib/${libraries.app}`).has(widget);
  const inBrowser = libraryExports(`packages/${pkg}/lib/${libraries.browser}`).has(widget);
  const targets = '/fleury/architecture/core-and-targets/';
  if (inApp && inBrowser) {
    return `**Import:** ${uri(libraries.app)}, or ${uri(libraries.browser)} in [browser code](${targets}).\n\n`;
  }
  if (inApp) {
    return `**Import:** ${uri(libraries.app)}. It needs \`dart:io\`, so it is [not available in browser code](${targets}).\n\n`;
  }
  throw new Error(`${widget} has a page but ${uri(libraries.app)} does not export it`);
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

// Splits a doc into its opening paragraph and the rest. The split is at the
// first blank line outside a code fence.
function splitClassDoc(doc) {
  const lines = doc.split('\n');
  let inFence = false;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].trim().startsWith('```')) inFence = !inFence;
    if (!inFence && lines[i].trim() === '') {
      return {
        summary: lines.slice(0, i).join('\n').trim(),
        details: lines.slice(i + 1).join('\n').trim(),
      };
    }
  }
  return { summary: doc.trim(), details: '' };
}

// Splits prose into sentences, each keeping its closing punctuation. Code
// spans, links, and parentheses never split, nor do the abbreviations prose
// uses mid-sentence.
function sentences(text) {
  const units = [];
  let start = 0;
  let depth = 0;
  let inCode = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '`') inCode = !inCode;
    if (inCode) continue;
    if (c === '(' || c === '[') depth++;
    if ((c === ')' || c === ']') && depth > 0) depth--;
    if (depth > 0 || !'.!?:'.includes(c) || !/\s/.test(text[i + 1] ?? ' ')) continue;
    const unit = text.slice(start, i + 1);
    if (/\b(e\.g|i\.e|etc|vs|cf)\.$/.test(unit)) continue;
    units.push(unit.trim());
    start = i + 1;
  }
  const rest = text.slice(start).trim();
  if (rest) units.push(rest);
  return units;
}

// A sentence that only points at the sample after it ("For example:", "Use it
// like this:") says nothing once the sample is gone.
const POINTS_AT_SAMPLE =
  /^(for example|for instance|e\.g\.|example|usage)\b|\b(like this|like so|as follows|as shown(?: below)?|the following|below)\s*:$/i;

// Ends the paragraph that introduced a code sample the page no longer shows
// ("…a fixed-list UI over callback commands:") as a sentence, or drops the
// sentence when it only pointed at the sample. [out] holds the lines before
// the sample. Returns the paragraph when that sentence was all it said.
function closeLeadIn(out) {
  let end = out.length - 1;
  while (end >= 0 && out[end].trim() === '') end--;
  if (end < 0 || !/:\s*$/.test(out[end])) return null;
  let start = end;
  while (start > 0 && out[start - 1].trim() !== '') start--;
  const paragraph = out.slice(start, end + 1);
  // A lead-in inside a list or quote belongs to that structure.
  if (/^\s*([-*+>]|\d+[.)])\s/.test(paragraph[0])) {
    out[end] = out[end].replace(/:\s*$/, '.');
    return null;
  }
  const units = sentences(paragraph.map((line) => line.trim()).join(' '));
  const leadIn = units.pop();
  const onlyLeadIn = units.length === 0;
  if (!POINTS_AT_SAMPLE.test(leadIn)) units.push(leadIn.replace(/:\s*$/, '.'));
  const text = units.join(' ');
  out.splice(start, out.length - start, ...(text ? [text] : []));
  return onlyLeadIn && text ? text : null;
}

// A class doc's own code samples are written for IDE readers. On a page that
// already shows a usage example they repeat it, so the details drop them and
// close the sentences that introduced them. Details left holding nothing but
// those introductions ("Fire one imperatively from anywhere below it.") only
// repeat the usage example, so they go too.
function withoutCodeSamples(md) {
  const lines = md.split('\n');
  const out = [];
  const introductions = new Set();
  for (let i = 0; i < lines.length; i++) {
    if (!lines[i].trim().startsWith('```')) {
      out.push(lines[i]);
      continue;
    }
    while (i + 1 < lines.length && !lines[i + 1].trim().startsWith('```')) i++;
    i++; // the closing fence
    const introduction = closeLeadIn(out);
    if (introduction) introductions.add(introduction);
  }
  const text = out.join('\n').replace(/\n{3,}/g, '\n\n').trim();
  const paragraphs = text.split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean);
  return paragraphs.every((p) => introductions.has(p)) ? '' : text;
}
const detailsSection = (details, hasUsage) => {
  const body = hasUsage ? withoutCodeSamples(details) : details;
  return body ? `## Details\n\n${body}\n\n` : '';
};

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

// Render a Dart type as a monospaced cell, linking each type name to its
// reference page when it has one and otherwise to its definition on GitHub
// (the dartdoc "click the type" affordance). Built as HTML so the links survive
// inside a Markdown table cell.
function linkType(typeStr) {
  const esc = String(typeStr)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/\|/g, '&#124;');
  // A prefixed external type such as `img.Image` must not link its `Image`
  // suffix to Fleury's own class of the same name.
  const linked = esc.replace(/(?<!\.)\b[A-Z][A-Za-z0-9_]*/g, (name) =>
    PAGE_SLUGS.has(name)
      ? `<a href="/fleury/widgets/${PAGE_SLUGS.get(name)}/">${name}</a>`
      : types[name]
        ? `<a href="${REPO}/${types[name]}">${name}</a>`
        : name
  );
  return `<code>${linked}</code>`;
}

// A parameter's doc for its table row: the opening paragraph, which has to fit
// on one line of a Markdown table. Paragraphs after it become a note under the
// table (see constructorsSection).
function parameterDoc(doc) {
  const { summary, details } = splitClassDoc(doc ?? '');
  return { summary: summary.replace(/\s*\n\s*/g, ' '), more: details };
}

// Constructor-specific parameter tables from the source. Keeping overloads
// separate matters for APIs such as ListView.builder and Image.file: a single
// merged "properties" table can contradict the usage example above it.
//
// A table row holds a parameter's first paragraph. When its doc goes on (how to
// use it, what it costs), the rest follows the table as a note the row links
// to, written once per page even when several constructors share it.
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
  // Named constructors often repeat a parameter list verbatim (Container,
  // Container.filled, Container.framed); print each distinct table once.
  const tables = new Map();
  // Notes already on the page: `${name}\n${more}` -> anchor id.
  const notes = new Map();
  const anchors = new Set();
  for (const constructor of constructors) {
    const params = constructor.params ?? [];
    out += `### ${codeCell(`${constructor.name}()`)}\n\n`;
    if (constructor.doc) out += `${mdxSafe(constructor.doc)}\n\n`;
    if (!params.length) {
      out += `This constructor has no public parameters.\n\n`;
      continue;
    }
    const signature = JSON.stringify(params);
    if (tables.has(signature)) {
      out += `Takes the same parameters as ${codeCell(`${tables.get(signature)}()`)}.\n\n`;
      continue;
    }
    tables.set(signature, constructor.name);
    const fresh = [];
    const rows = params
      .map((p) => {
        // A default that names a private helper (`_defaultStringFor`) means
        // nothing to a reader, so the parameter's doc has to say what the
        // default does instead.
        const privateDefault = p.default && /(^|[^\w.$])_[A-Za-z]/.test(p.default);
        if (privateDefault && !/\bDefaults? to\b/i.test(p.doc ?? '')) {
          throw new Error(
            `${constructor.name}.${p.name} defaults to private ${p.default}; ` +
              `say what the default does in its doc ("Defaults to …")`
          );
        }
        const def = p.required
          ? '**required**'
          : p.default && !privateDefault
            ? codeCell(p.default)
            : '—';
        const name = p.named ? `${p.name}:` : p.name;
        const { summary, more } = parameterDoc(p.doc);
        let description = cell(summary || null);
        if (more) {
          const key = `${p.name}\n${more}`;
          if (!notes.has(key)) {
            let id = `param-${p.name.toLowerCase()}`;
            for (let n = 2; anchors.has(id); n++) id = `param-${p.name.toLowerCase()}-${n}`;
            anchors.add(id);
            notes.set(key, id);
            fresh.push({ name: p.name, more, id });
          }
          description += ` [More](#${notes.get(key)})`;
        }
        return `| ${codeCell(name)} | ${linkType(p.type)} | ${def} | ${description} |`;
      })
      .join('\n');
    out +=
      `| Parameter | Type | Default | Description |\n` +
      `| --- | --- | --- | --- |\n` +
      `${rows}\n\n`;
    for (const { name, more, id } of fresh) {
      // A list item's continuation lines are indented under its marker.
      const body = mdxSafe(more).replace(/\n/g, '\n  ').replace(/\n  (?=\n)/g, '\n');
      out += `- <span id="${id}"></span>**${codeCell(name)}:** ${body}\n`;
    }
    if (fresh.length) out += `\n`;
  }
  return out;
}

const all = JSON.parse(readFileSync(MANIFEST, 'utf8'));
// 'Home' = the landing-hero example, mounted directly on the home page (no
// catalog entry). 'Showcases' = full apps, their own section. 'Theming' =
// embeds on the theming guide — they demonstrate a *theme*, which is data
// rather than a widget, so there is no class to build an API reference from.
// 'Guide examples' are outcome-oriented compositions that may reuse a widget
// which already has a canonical reference example.
const GUIDE_EMBED_CATEGORIES = new Set([
  'Showcases',
  'Home',
  'Theming',
  'Guide examples',
]);
const widgets = all.filter(
  (e) =>
    !GUIDE_EMBED_CATEGORIES.has(e.category) &&
    // '.lab.*' ids are extra comparison examples embedded on hand-written pages
    // (e.g. the LineChart rendering lab); they ship in the bundle to be mounted
    // there, but aren't canonical per-widget reference pages.
    !String(e.id ?? '').includes('.lab.') &&
    publishable(e.widget)
);
const showcases = all.filter((e) => e.category === 'Showcases');

// ── Widget pages ────────────────────────────────────────────────────────────
assertReferenceComplete(widgets.map((entry) => entry.widget), 'widget');
const widgetsDir = join(DOCS, 'widgets');
rmSync(widgetsDir, { recursive: true, force: true });
mkdirSync(widgetsDir, { recursive: true });

// "See also" pointers between easily-confused widgets, rendered right under the
// intro so a reader on the wrong page finds the right one immediately. Keyed by
// slug; each entry is `[label, slug, when-to-prefer-it]`.
const SEE_ALSO = {
  table: [
    ['DataTable', 'datatable', 'for large or virtualized data sets'],
    ['TreeTable', 'treetable', 'for hierarchies'],
  ],
  datatable: [
    ['Table', 'table', 'for small grids of widget cells'],
    ['TreeTable', 'treetable', 'for hierarchies'],
  ],
  treetable: [
    ['DataTable', 'datatable', 'for flat data'],
    ['Tree', 'tree', 'when you don’t need columns'],
  ],
  tree: [['TreeTable', 'treetable', 'for rows with columns']],
  markdown: [['MarkdownText', 'markdowntext', 'for short inline strings']],
  markdowntext: [['MarkdownView', 'markdown', 'for full documents']],
  textinput: [
    ['TextArea', 'textarea', 'for multiline text'],
    ['CompletionTextInput', 'completiontextinput', 'for inline suggestions'],
  ],
  textarea: [['TextInput', 'textinput', 'for a single line']],
  autocomplete: [
    ['Select', 'select', 'for a short fixed choice list'],
    ['CompletionTextInput', 'completiontextinput', 'for suggestions inside free text'],
  ],
  completiontextinput: [
    ['Autocomplete', 'autocomplete', 'when the result is one picked option'],
  ],
  select: [
    ['Autocomplete', 'autocomplete', 'to type-and-filter many options'],
    ['MultiSelect', 'multiselect', 'for multiple choices'],
  ],
  multiselect: [['Select', 'select', 'for a single choice']],
  checkbox: [
    ['Toggle', 'toggle', 'for a compact on/off switch'],
    ['Switch', 'switch', 'for a setting that should stand out'],
  ],
  toggle: [
    ['Checkbox', 'checkbox', 'for a checklist item'],
    ['Switch', 'switch', 'for a setting that should stand out'],
  ],
  switch: [
    ['Toggle', 'toggle', 'for a compact on/off switch'],
    ['Checkbox', 'checkbox', 'for a checklist item'],
  ],
  radio: [['RadioGroup', 'radiogroup', 'to make a group one Tab stop with arrow-key selection']],
  radiogroup: [['Radio', 'radio', 'to lay out each choice yourself']],
  stepper: [['NumberInput', 'numberinput', 'for typed numeric entry']],
  numberinput: [['Stepper', 'stepper', 'for arrow-key increments']],
  filepicker: [['FileBrowser', 'filebrowser', 'to browse with filtering and copy']],
  filebrowser: [['FilePicker', 'filepicker', 'to pick a single file']],
  progressbar: [
    ['Gauge', 'gauge', 'for a labelled meter with thresholds'],
    ['Spinner', 'spinner', 'for activity without a known end'],
  ],
  spinner: [['ProgressBar', 'progressbar', 'when progress can be measured']],
  gauge: [['ProgressBar', 'progressbar', 'for a plain progress bar']],
  scrollview: [['ListView', 'listview', 'for virtualized, selectable lists']],
  listview: [
    ['ScrollView', 'scrollview', 'for one tall non-list child'],
    ['DataTable', 'datatable', 'for rows with named columns'],
  ],
  linechart: [
    ['AreaChart', 'areachart', 'for a filled look'],
    ['Sparkline', 'sparkline', 'for a compact inline trend'],
  ],
  areachart: [['LineChart', 'linechart', 'for lines or scatter points']],
  sparkline: [['LineChart', 'linechart', 'for axes, legends, and several series']],
  barchart: [['Histogram', 'histogram', 'to bin raw samples into a distribution']],
  histogram: [['BarChart', 'barchart', 'for values you already have per category']],
  heatmap: [['CalendarHeatmap', 'calendarheatmap', 'for values keyed by date']],
  calendarheatmap: [['Heatmap', 'heatmap', 'for any 2-D grid of values']],
  diffview: [['PatchReview', 'patchreview', 'to review a multi-file patch file by file']],
  patchreview: [['DiffView', 'diffview', 'for one diff without the file list']],
  messagelist: [['LogRegion', 'logregion', 'for log output with severities']],
  logregion: [['MessageList', 'messagelist', 'for a conversation transcript']],
  dialog: [['ApprovalPrompt', 'approvalprompt', 'for a ready-made yes/no decision']],
  approvalprompt: [['Dialog', 'dialog', 'to build your own modal']],
  menu: [['Select', 'select', 'to choose a value rather than run an action']],
  tooltip: [['Anchored', 'anchored', 'to float any content next to a trigger']],
  keybindings: [['KeyDetector', 'keydetector', 'for low-level key handling inside a custom control']],
  keydetector: [['KeyBindings', 'keybindings', 'for declared, labelled shortcuts']],
  text: [['RichText', 'richtext', 'to style parts of a line differently']],
  richtext: [['Text', 'text', 'when one style covers the whole string']],
  textspan: [['RichText', 'richtext', 'to render a span tree']],
  row: [['Column', 'column', 'for a vertical line'], ['Wrap', 'wrap', 'to flow onto more lines']],
  column: [['Row', 'row', 'for a horizontal line'], ['ListView', 'listview', 'when the content should scroll']],
  expanded: [
    ['Flexible', 'flexible', 'to let the child take less than its share'],
    ['Spacer', 'spacer', 'for an empty gap'],
  ],
  flexible: [
    ['Expanded', 'expanded', 'to make the child fill its share'],
    ['Spacer', 'spacer', 'for an empty gap'],
  ],
  spacer: [
    ['Expanded', 'expanded', 'to give the space to a child'],
    ['Flexible', 'flexible', 'for a child that may take less'],
  ],
  stack: [['IndexedStack', 'indexedstack', 'to show one child at a time']],
  indexedstack: [['Tabs', 'tabs', 'for a tab strip that switches pages']],
};
// The guide that teaches each widget in context, keyed by page slug. A widget
// page links here so the reference is never a dead end for a reader who needs
// the bigger picture; widgets without a guide simply get no line.
const WIDGET_GUIDES = {
  button: ['input-and-gestures'],
  textinput: ['forms'],
  textarea: ['forms'],
  checkbox: ['forms'],
  toggle: ['forms'],
  switch: ['forms'],
  radio: ['forms'],
  radiogroup: ['forms'],
  select: ['forms'],
  multiselect: ['forms'],
  rangeslider: ['forms'],
  stepper: ['forms'],
  numberinput: ['forms'],
  passwordinput: ['forms'],
  autocomplete: ['forms'],
  completiontextinput: ['forms'],
  colorpicker: ['forms'],
  datepicker: ['forms'],
  form: ['forms'],
  formfield: ['forms'],
  formcontroller: ['forms'],
  commandbutton: ['commands'],
  commandpalette: ['commands'],
  datatable: ['lists-and-scrolling'],
  treetable: ['lists-and-scrolling'],
  listview: ['lists-and-scrolling'],
  scrollview: ['lists-and-scrolling'],
  scrollbar: ['lists-and-scrolling'],
  dialog: ['navigation'],
  navigation: ['navigation'],
  popscope: ['navigation'],
  theme: ['theming'],
  text: ['theming'],
  spinner: ['animation'],
  futurebuilder: ['loading-data'],
  streambuilder: ['loading-data'],
  image: ['loading-data'],
  scope: ['state-management'],
  scopebuilder: ['state-management'],
  notifierbuilder: ['state-management'],
  gesturedetector: ['input-and-gestures'],
  mouseregion: ['input-and-gestures'],
  selectionarea: ['input-and-gestures'],
  keybindings: ['focus-and-keyboard'],
  keydetector: ['focus-and-keyboard'],
  keyhintbar: ['focus-and-keyboard'],
  whichkey: ['focus-and-keyboard'],
  focus: ['focus'],
  focusnode: ['focus'],
  focusscope: ['focus'],
  focusdetector: ['focus'],
  ...Object.fromEntries(
    [
      'container', 'row', 'column', 'expanded', 'flexible', 'spacer', 'center',
      'align', 'padding', 'sizedbox', 'constrainedbox', 'aspectratio', 'stack',
      'positioned', 'indexedstack', 'wrap', 'layoutbuilder',
    ].map((slug) => [slug, ['layout']])
  ),
};
const GUIDE_TITLES = new Map(
  GUIDE_GROUPS.flatMap((group) =>
    group.items.map((item) => [item.slug.replace(/^guides\//, ''), item.label])
  )
);
const guideLink = (guide) => {
  const title = GUIDE_TITLES.get(guide);
  if (!title) throw new Error(`Unknown guide "${guide}" linked from a widget page`);
  return `[${title}](/fleury/guides/${guide}/)`;
};
const guideLine = (slug) => {
  const guides = WIDGET_GUIDES[slug];
  return guides?.length ? `**Learn more:** ${guides.map(guideLink).join(' · ')}\n\n` : '';
};

// The catalog's section for a category. Starlight slugs headings with
// github-slugger: lowercase, punctuation dropped, spaces to hyphens, so
// "Inputs & controls" becomes "inputs--controls".
const categoryLink = (category) => {
  const anchor = category
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s-]/gu, '')
    .replace(/\s/g, '-');
  return `[${category}](/fleury/widgets/#${anchor})`;
};

// ── Source-backed pages ─────────────────────────────────────────────────────
// Public APIs documented from source rather than a registry entry, borrowing a
// guide's live example. Every widget should run live: when one depends on a
// platform service (the disk, captured output), give it a parameter the
// browser can satisfy, as FileBrowser takes a FileSource, and add a registry
// example instead of a page here.
const DOC_ONLY = [
  { slug: 'image', widget: 'Image', category: 'Text & content', reason: 'image-file', example: 'loading.image',
    code: "Image.bytes(logoBytes, fit: ImageFit.contain)\n// Image.file(...) needs dart:io — use bytes/decoded in embeds" },
];
const DOC_ONLY_REASONS = new Set(['image-file']);
for (const entry of DOC_ONLY) {
  if (!DOC_ONLY_REASONS.has(entry.reason)) {
    throw new Error(
      `${entry.widget} uses unsupported doc-only reason "${entry.reason}"; ` +
      `add a live browser example for web-safe widgets`
    );
  }
  if (!entry.example) {
    throw new Error(`${entry.widget} needs an example: every reference page runs live`);
  }
}
const docNote = (d) =>
  d.reason === 'image-file'
    ? `:::note[Embed-safe with bytes]\n\`Image\` itself is web-safe — use ` +
      `\`Image.bytes\` or \`Image.decoded\` in client-side embeds. Only ` +
      `\`Image.file\` needs \`dart:io\` (terminal or ` +
      `[\`fleury serve\`](/fleury/architecture/serving-and-embedding/)).\n:::\n\n`
    : '';

// Core framework widgets (from package:fleury): the layout, text, async, input,
// and builder primitives a Flutter developer reaches for. Documented from source
// like the rest of the reference; usage in context lives in the guides. An
// `example` borrows a guide's live demo for the page's aside.
const CORE = [
  { slug: 'text', category: 'Text & content', widget: 'Text', code: "Text('hello', style: CellStyle(bold: true))" },
  { slug: 'richtext', category: 'Text & content', widget: 'RichText',
    code: "RichText(text: TextSpan(children: [\n  TextSpan(text: 'deploy '),\n  TextSpan(text: 'ok', style: CellStyle(bold: true)),\n]))" },
  { slug: 'textspan', category: 'Text & content', widget: 'TextSpan',
    code: "TextSpan(\n  text: 'deploy ',\n  children: [TextSpan(text: 'ok', style: CellStyle(bold: true))],\n)" },
  { slug: 'listview', category: 'Lists & data', widget: 'ListView', example: 'lists.files',
    code: "ListView.builder(\n  itemCount: rows.length,\n  itemBuilder: (context, i, highlighted) => Text(rows[i].label),\n)" },
  { slug: 'scrollview', category: 'Lists & data', widget: 'ScrollView', example: 'lists.document',
    code: "ScrollView(child: Column(children: [/* tall content */]))" },
  { slug: 'scrollbar', category: 'Lists & data', widget: 'Scrollbar', example: 'lists.document',
    code: "// The flag on ListView and ScrollView adds one and shares their controller:\nListView.builder(\n  itemCount: rows.length,\n  itemBuilder: (context, i, highlighted) => Text(rows[i].label),\n  scrollbar: true,\n)\n\n// Or wrap a view you control, passing the controller it scrolls with:\nScrollbar(\n  controller: scroll,\n  child: ScrollView(controller: scroll, child: child),\n)" },
  { slug: 'spinner', category: 'Charts & meters', widget: 'Spinner',
    code: "Spinner(label: 'Connecting')" },
  { slug: 'futurebuilder', category: 'State & async', widget: 'FutureBuilder', example: 'loading.snapshot',
    code: "// In your State: create the future once. Calling load() in build would\n// start a new request on every rebuild.\nlate final Future<List<Item>> _items = load();\n\n// In build:\nFutureBuilder<List<Item>>(\n  future: _items,\n  builder: (context, snapshot) {\n    if (snapshot.hasError) return Text('Failed: ${snapshot.error}');\n    if (!snapshot.hasData) return const Text('Loading…');\n    return ItemList(snapshot.data!);\n  },\n)" },
  { slug: 'streambuilder', category: 'State & async', widget: 'StreamBuilder', example: 'loading.stream',
    code: "StreamBuilder<int>(\n  stream: ticks,\n  initialData: 0,\n  builder: (context, snapshot) => Text('tick ${snapshot.data ?? 0}'),\n)" },
  { slug: 'gesturedetector', category: 'Input handling & focus', widget: 'GestureDetector', example: 'input.press',
    code: "GestureDetector(\n  onTap: _select,\n  onTapDown: (details) => _placeAt(details.localPosition),\n  child: child,\n)" },
  { slug: 'mouseregion', category: 'Input handling & focus', widget: 'MouseRegion', example: 'input.nesting',
    code: "MouseRegion(\n  onEnter: () => setHover(true),\n  onExit: () => setHover(false),\n  child: Text('hover me'),\n)" },
  { slug: 'selectionarea', category: 'Input handling & focus', widget: 'SelectionArea', example: 'input.selection',
    code: "SelectionArea(\n  onSelectionChanged: (content) =>\n      setState(() => selected = content?.plainText ?? ''),\n  child: const Column(\n    children: [\n      Text('Planning notes'),\n      Text('Meet on Tuesday.'),\n    ],\n  ),\n)" },
  { slug: 'popscope', category: 'Navigation & overlays', widget: 'PopScope', example: 'navigation.guard',
    code: "PopScope(\n  canPop: !hasUnsavedChanges,\n  onBlocked: () => setState(() => status = 'Save or discard first'),\n  child: editor,\n)" },
  { slug: 'theme', category: 'App & theming', widget: 'Theme', example: 'themes.custom',
    code: "// Override the theme for one subtree, starting from the one above it:\nTheme(\n  data: Theme.of(context).copyWith(borderStyle: BorderStyle.double),\n  child: child,\n)\n\n// Any descendant reads the nearest theme:\nfinal primary = Theme.of(context).colorScheme.primary;" },
  { slug: 'row', category: 'Layout', widget: 'Row',
    code: "Row(\n  children: [\n    const Text('Name'),\n    const SizedBox(width: 2),\n    Expanded(child: TextInput(controller: name)),\n  ],\n)" },
  { slug: 'column', category: 'Layout', widget: 'Column',
    code: "Column(\n  crossAxisAlignment: CrossAxisAlignment.start,\n  children: [\n    const Text('Deploying'),\n    ProgressBar(value: progress),\n  ],\n)" },
  { slug: 'expanded', category: 'Layout', widget: 'Expanded',
    code: "Row(\n  children: [\n    const SizedBox(width: 18, child: Sidebar()),\n    const Expanded(child: Editor()),\n  ],\n)" },
  { slug: 'center', category: 'Layout', widget: 'Center',
    code: "Center(child: Text('No results'))" },
  { slug: 'stack', category: 'Layout', widget: 'Stack',
    code: "Stack(\n  children: [\n    const Editor(),\n    Positioned(left: 2, top: 0, child: Text('● saved')),\n  ],\n)" },
  { slug: 'indexedstack', category: 'Layout', widget: 'IndexedStack',
    code: "IndexedStack(\n  index: selectedTab,\n  children: const [InboxView(), SettingsView()],\n)" },
  { slug: 'layoutbuilder', category: 'Layout', widget: 'LayoutBuilder', example: 'layout.responsive',
    code: "LayoutBuilder(\n  builder: (context, constraints) =>\n      (constraints.maxCols ?? 0) > 60 ? Wide() : Narrow(),\n)" },
  { slug: 'scope', category: 'State & async', widget: 'Scope', example: 'state.project-scope',
    code: "// Share a value owned elsewhere:\nScope(project, child: const ProjectPath())\n\n// Create and own a model for this subtree:\nScope.create(Cart.new, child: const ShopScreen())\n\n// Read the nearest one in a descendant's build (it rebuilds on change):\nfinal cart = context.scope<Cart>();" },
  { slug: 'scopebuilder', category: 'State & async', widget: 'ScopeBuilder',
    code: "ScopeBuilder<Project>(\n  builder: (context, project) => Text('Project: ${project.name}'),\n)" },
  { slug: 'notifierbuilder', category: 'State & async', widget: 'NotifierBuilder', example: 'state.cart-notifier',
    code: "NotifierBuilder(\n  notifier: cart,\n  builder: (context, cart) => Text('Items: ${cart.itemCount}'),\n)" },
  { slug: 'sizedbox', category: 'Layout', widget: 'SizedBox',
    code: "SizedBox(\n  width: 20,\n  height: 3,\n  child: Text('fixed area'),\n)" },
  { slug: 'padding', category: 'Layout', widget: 'Padding',
    code: "Padding(\n  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),\n  child: Text('inset'),\n)" },
  { slug: 'align', category: 'Layout', widget: 'Align',
    code: "Align(\n  alignment: Alignment.centerRight,\n  child: Text('status'),\n)" },
  { slug: 'positioned', category: 'Layout', widget: 'Positioned',
    code: "Stack(children: [\n  Text('base'),\n  Positioned(left: 4, top: 1, child: Text('overlay')),\n])" },
  { slug: 'wrap', category: 'Layout', widget: 'Wrap',
    code: "Wrap(\n  spacing: 1,\n  runSpacing: 1,\n  children: tags.map((tag) => Text('#$tag')).toList(),\n)" },
  { slug: 'flexible', category: 'Layout', widget: 'Flexible',
    code: "Row(children: [\n  Flexible(child: Text(longLabel)),\n  Text('ready'),\n])" },
  { slug: 'spacer', category: 'Layout', widget: 'Spacer',
    code: "Row(children: [\n  Text('left'),\n  const Spacer(),\n  Text('right'),\n])" },
  { slug: 'constrainedbox', category: 'Layout', widget: 'ConstrainedBox',
    code: "ConstrainedBox(\n  minWidth: 24,\n  maxWidth: 48,\n  child: Text('bounded content'),\n)" },
  { slug: 'aspectratio', category: 'Layout', widget: 'AspectRatio',
    code: "AspectRatio(\n  aspectRatio: 2.0,\n  child: Heatmap(values: values),\n)" },
].filter((d) => publishable(d.widget));

// Every reference page by widget name, so API tables can link a parameter's
// type to its page here rather than to its source.
const PAGE_SLUGS = new Map([
  ...widgets.map((e) => [e.widget, e.id.split('.')[0]]),
  ...[...DOC_ONLY, ...CORE].map((d) => [d.widget, d.slug]),
]);

// The lines between a page's summary and its usage: pointers for a reader on
// the wrong page, the guide for the bigger picture, and the import to write.
const pageLead = (slug, widget) => seeAlsoLine(slug) + guideLine(slug) + importLine(widget);
function seeAlsoLine(slug) {
  const entries = SEE_ALSO[slug];
  if (!entries) return '';
  const parts = entries
    .filter(([label]) => PAGE_SLUGS.has(label))
    .map(([label, target, when]) => `[${label}](/fleury/widgets/${target}/) ${when}`);
  return parts.length ? `**See also:** ${parts.join(' · ')}.\n\n` : '';
}
for (const [slug, entries] of Object.entries(SEE_ALSO)) {
  for (const [label, target] of entries) {
    if (PAGE_SLUGS.has(label) && PAGE_SLUGS.get(label) !== target) {
      throw new Error(`SEE_ALSO.${slug} links ${label} to ${target}, but its page is ${PAGE_SLUGS.get(label)}`);
    }
  }
}

// ── Registry widget pages ───────────────────────────────────────────────────
for (const e of widgets) {
  const slug = e.id.split('.')[0];
  // Prefer the widget's own source doc comment (richer); fall back to the blurb.
  // Its opening paragraph leads the page; the rest follows the usage example.
  const { summary: intro, details } = api[e.widget]?.classDoc
    ? splitClassDoc(mdxSafe(api[e.widget].classDoc))
    : { summary: e.blurb, details: '' };
  // An explicit `code` override (used by animated examples to keep the snippet
  // static) wins; otherwise show the code extracted from the builder.
  const snippet = e.code ?? exampleCode[e.id];
  // Knob-enabled widgets get an interactive props playground; others a static
  // (but live) example.
  const usage = usageSection(slug, snippet);
  const isKnob = KNOB_WIDGETS.has(slug);
  const componentImport = isKnob
    ? `import FleuryKnobs from '${KNOBS_COMPONENT}';`
    : `import FleuryExample from '${COMPONENT}';`;
  const liveBlock = isKnob
    ? `<FleuryKnobs id="${slug}" cols={${e.cols}} rows={${e.rows}} />`
    : demoBlock(e);
  writeFileSync(
    join(widgetsDir, `${slug}.mdx`),
    `---\ntitle: ${yaml(e.widget)}\ndescription: ${yaml(plainText(e.blurb))}\n` +
      // Generated from gitignored output: there is no source file to edit.
      `tableOfContents: false\neditUrl: false\n---\n\n` +
      `${componentImport}\n` +
      (isKnob ? '' : padImport(e)) +
      `import WidgetLayout from '${LAYOUT_COMPONENT}';\n` +
      (slug === 'datatable' ? `import DataTableExamples from '../../../components/DataTableExamples.astro';\n` : '') +
      (EXTRA_EXAMPLES[slug] ? `${TABS_IMPORT}\n` : '') +
      `\n` +
      (slug === 'datatable' ? '' : `<WidgetLayout>\n\n`) +
      // Right column: the live (knob-tweakable) demo only — the code below is a
      // fixed usage example, so it lives in the main column, not next to it.
      (slug === 'datatable' ? '' : `<Fragment slot="aside">\n\n${liveBlock}\n\n</Fragment>\n\n`) +
      // Left column: summary → see-also → guides → import → usage example(s)
      // → the rest of the class doc → API breakdown.
      `${intro}\n\n` +
      pageLead(slug, e.widget) +
      usage +
      detailsSection(details, usage !== '') +
      constructorsSection(e.widget) +
      sourceSection(e.widget) +
      `**Category:** ${categoryLink(e.category)} · [All widgets](/fleury/widgets/)\n\n` +
      (slug === 'datatable' ? '' : `</WidgetLayout>\n`)
  );
}

const DOC_PAGES = [...DOC_ONLY, ...CORE];
const exportedWidgetCount = assertExportedWidgetCoverage([
  ...widgets,
  ...DOC_PAGES,
]);
assertReferenceComplete(DOC_PAGES.map((entry) => entry.widget), 'doc-only widget');
// First sentence of a doc comment — for one-line settings (frontmatter
// description, catalog bullets) where the whole first paragraph is too much.
const firstSentence = (s) => s.split(/(?<=\.)\s+(?=[A-Z`(])/)[0];
for (const d of DOC_PAGES) {
  const { summary: intro, details } = api[d.widget]?.classDoc
    ? splitClassDoc(mdxSafe(api[d.widget].classDoc))
    : { summary: '', details: '' };
  // An entry can borrow a guide's live example that shows the widget at work;
  // it goes in the same aside as a registry page's demo.
  const example = d.example ? all.find((x) => x.id === d.example) : null;
  if (d.example && !example) {
    throw new Error(`${d.widget} names example "${d.example}", which the registry lacks`);
  }
  const body =
    (intro ? `${intro}\n\n` : '') +
    pageLead(d.slug, d.widget) +
    docNote(d) +
    (d.code ? `## Usage\n\n\`\`\`dart\n${d.code}\n\`\`\`\n\n` : '') +
    detailsSection(details, Boolean(d.code)) +
    constructorsSection(d.widget) +
    sourceSection(d.widget) +
    `**Category:** ${categoryLink(d.category)} · [All widgets](/fleury/widgets/)\n`;
  writeFileSync(
    join(widgetsDir, `${d.slug}.mdx`),
    `---\ntitle: ${yaml(d.widget)}\n` +
      `description: ${yaml(plainText(firstSentence(api[d.widget]?.doc ?? d.widget)))}\n` +
      (example ? `tableOfContents: false\n` : '') +
      `editUrl: false\n---\n\n` +
      (example
        ? `import FleuryExample from '${COMPONENT}';\n` +
          padImport(example) +
          `import WidgetLayout from '${LAYOUT_COMPONENT}';\n\n` +
          `<WidgetLayout>\n\n<Fragment slot="aside">\n\n` +
          `${demoBlock(example)}\n\n</Fragment>\n\n` +
          `${body}\n</WidgetLayout>\n`
        : body)
  );
}

// ── Catalog ─────────────────────────────────────────────────────────────────
// Within a category the framework primitives from package:fleury lead (Text
// before MarkdownView, ListView before DataTable), in the reading order below;
// fleury_widgets pages follow in registry order, then its doc-only pages.
// Primitive-ness comes from the widget's source, not from which list names it.
const PRIMITIVE_ORDER = [
  // Text & content
  'Text', 'RichText', 'TextSpan',
  // Lists & data
  'ListView', 'ScrollView', 'Scrollbar',
  // Inputs & controls
  'TextInput', 'TextArea', 'Button',
  // Navigation & overlays
  'Navigator', 'PopScope', 'Anchored',
  // App & theming
  'FleuryApp', 'Theme',
  // Layout
  'Row', 'Column', 'Expanded', 'Flexible', 'Spacer', 'Container', 'Padding',
  'SizedBox', 'ConstrainedBox', 'AspectRatio', 'Center', 'Align', 'Stack',
  'Positioned', 'IndexedStack', 'Wrap', 'LayoutBuilder',
  // Input handling & focus
  'Focus', 'FocusNode', 'FocusScope', 'FocusDetector', 'KeyBindings',
  'KeyDetector', 'GestureDetector', 'MouseRegion', 'SelectionArea',
  // State & async
  'FutureBuilder', 'StreamBuilder', 'Scope', 'ScopeBuilder', 'NotifierBuilder',
];
const isPrimitive = (widget) => api[widget]?.file?.startsWith('packages/fleury/');
const byCategory = new Map();
const catalogEntry = (d) => {
  // One sentence only — several core doc comments open with a full paragraph,
  // which read as walls of text next to the curated one-line blurbs.
  const blurb = firstSentence(api[d.widget]?.doc ?? '');
  return { widget: d.widget, id: d.slug, blurb, category: d.category };
};
const catalogEntries = [
  ...CORE.map(catalogEntry),
  ...widgets,
  ...DOC_ONLY.map(catalogEntry),
].map((entry, index) => ({ entry, index }));
const catalogRank = ({ entry, index }) => {
  if (!isPrimitive(entry.widget)) return [1, index];
  const order = PRIMITIVE_ORDER.indexOf(entry.widget);
  return [0, order === -1 ? PRIMITIVE_ORDER.length + index : order];
};
catalogEntries.sort((a, b) => {
  const [groupA, rankA] = catalogRank(a);
  const [groupB, rankB] = catalogRank(b);
  return groupA - groupB || rankA - rankB;
});
for (const { entry } of catalogEntries) {
  if (!byCategory.has(entry.category)) byCategory.set(entry.category, []);
  byCategory.get(entry.category).push(entry);
}
let widgetIndex =
  `---\ntitle: Widget reference\ndescription: Every exported Fleury higher-level widget, plus the most-used core primitives — live where useful and source-backed throughout.\neditUrl: false\n---\n\n` +
  `This reference covers every widget exported by \`fleury_widgets\`, plus ` +
  `the core layout, text, async, and input primitives most apps reach for. ` +
  `Most pages embed the real widget running live in your browser; every ` +
  `page's API tables are generated from the current Dart source.\n\n`;
// Deliberate reading order: the control families a first visit scans for come
// first; the framework primitives close the page. Categories group widgets by
// what they are for, not by package, so core and fleury_widgets pages mix.
// Unlisted categories (if a new one appears in the registry) fall in last.
const CATEGORY_ORDER = [
  'Inputs & controls',
  'Forms',
  'Lists & data',
  'Charts & meters',
  'Text & content',
  'Agent surfaces',
  'Navigation & overlays',
  'App & theming',
  'Layout',
  'Input handling & focus',
  'State & async',
];
const categoryRank = (c) => {
  const i = CATEGORY_ORDER.indexOf(c);
  return i === -1 ? CATEGORY_ORDER.length : i;
};
const orderedCategories = [...byCategory.entries()].sort(
  (a, b) => categoryRank(a[0]) - categoryRank(b[0])
);
for (const [category, items] of orderedCategories) {
  widgetIndex += `## ${category}\n\n`;
  for (const e of items)
    widgetIndex += `- [${e.widget}](/fleury/widgets/${e.id.split('.')[0]}/) — ${e.blurb}\n`;
  widgetIndex += `\n`;
}
writeFileSync(join(widgetsDir, 'index.mdx'), widgetIndex);

// The Widgets sidebar mirrors this catalog: one collapsible group per category,
// in the same order, so the sidebar and the index agree and a reader browsing
// for "an input" scans one group instead of an alphabetical list of ~100.
writeFileSync(
  WIDGET_SIDEBAR,
  JSON.stringify(
    orderedCategories.map(([category, items]) => ({
      label: category,
      items: items.map((e) => ({
        label: e.widget,
        slug: `widgets/${e.id.split('.')[0]}`,
      })),
    })),
    null,
    2
  ) + '\n'
);

// ── Showcase pages (one app per page) ───────────────────────────────────────
const showDir = join(DOCS, 'showcases');
rmSync(showDir, { recursive: true, force: true });
mkdirSync(showDir, { recursive: true });

// Showcase slug → its sample source file (for a "view source" link + the
// "widgets used" extraction).
const SAMPLE_FILES = {
  dashboard: 'dashboard.dart',
  files: 'file_manager.dart',
  commands: 'commands_showcase.dart',
  agent: 'agent_tui.dart',
  editor: 'editor.dart',
  finance: 'finance.dart',
  forms: 'forms_showcase.dart',
  state: 'state_management_showcase.dart',
  themes: 'theming_showcase.dart',
  asteroids: 'neon_asteroids.dart',
  sprite: 'ansi_sprite_studio.dart',
};
const SHOWCASE_COMPONENT = '../../../components/ShowcaseWidgets.astro';
const SHOWCASE_STAGE_COMPONENT = '../../../components/ShowcaseStage.astro';
const SAMPLES_DIR = join(ROOT, 'packages', 'samples', 'lib', 'src');

// One-paragraph pitch per showcase: what it is + why Fleury made it easy.
const SHOWCASE_GOALS = {
  dashboard:
    'A live operations dashboard — per-core gauges, a streaming history chart, ' +
    "and a live process table sorted by CPU — the kind of thing you'd normally " +
    'reach for htop or a Grafana panel to build.\n\n' +
    "In Fleury it's one widget tree: the same `Gauge`, `Sparkline`, `LineChart`, " +
    "and `DataTable` you'd use anywhere, composed with `Row`/`Column` and updated " +
    'on a ticker. No canvas math, no manual redraw bookkeeping — call `setState`, ' +
    'and the framework repaints only the cells that changed, so the graphs stream ' +
    'smoothly.',
  files:
    'A two-pane file explorer whose preview adapts to each file type. The left ' +
    'pane is a tree; the right pane swaps in the right viewer for the file you ' +
    'open — `CodeView` for source, `MarkdownView` for docs, `JsonView` for data.\n\n' +
    'Each viewer is a drop-in widget with selection, scrolling, and copy already ' +
    'handled, so "the preview matches the file" comes down to a `switch` in ' +
    '`build()`.',
  commands:
    'A small editor built to make command architecture visible. **New file** ' +
    'and **Save current file** are each defined once as an `AppCommand`, which ' +
    'supplies its shortcut, palette row, semantic action, and stable ID ' +
    'together.\n\n' +
    'Edit a file and Save becomes available on every surface at once; save it ' +
    'and they all disable together. The palette opener is itself a command ' +
    'bound to Ctrl+K, so the palette lists exactly what the editor\'s ' +
    '`CommandScope` offers. The demo is deterministic and local.',
  agent:
    'A coding-agent streaming session — prose, tool cards, a live todo list, ' +
    'a colored diff, a prompt box.\n\n' +
    'It is built from core primitives alone — `Text`, `Row`, `Column`, a ' +
    '`ListView`, and a `TextInput` over a cell grid — so a rich agent UI comes ' +
    'down to layout and color. The [Agent surfaces](/fleury/widgets/#agent-surfaces) ' +
    'widgets package pieces like these (transcripts, tool-call cards, diffs) ' +
    'when you would rather not build them. And because it is an ordinary ' +
    'Fleury tree, the same UI is inspectable as a semantic tree — so a test, or ' +
    'another agent, can read it. See ' +
    '[Built for agents](/fleury/architecture/agents-and-semantics/).',
  editor:
    'One buffer, two editors. The same text, the same widget tree — but ' +
    'Ctrl+B swaps the entire keymap between a nano-style modeless one and a ' +
    'modal vim one, live.\n\n' +
    'It exists to show the two opposite ways a terminal app teaches its own ' +
    'keys, both of which Fleury gives you for free. nano shows everything ' +
    'always: the shortcut bar along the bottom is a `KeyHintBar`, which reads ' +
    'the live bindings through `KeyBindings.activeOf` — no list to maintain. ' +
    'vim reveals on demand: press `d`, `g` or the `Space` leader and pause, ' +
    'and the which-key popup (`WhichKey`, fed by `KeyBindings.pendingOf`) ' +
    'lists what can come next.\n\n' +
    'The modal behaviour underneath is ordinary app state. In vim NORMAL the ' +
    'editor declines typed text, so printables route to `KeyBindings` as ' +
    'commands; in INSERT it claims them. See ' +
    '[Key handling](/fleury/guides/focus-and-keyboard/).',
  finance:
    'A personal-finance workspace that feels immediately familiar: balances, ' +
    'cash flow, category spending, filters, and a transaction ledger filled ' +
    'with deterministic sample data.\n\n' +
    'It combines Fleury charts with a virtualized, stable-ID `DataTable`; turn ' +
    'on stress mode to filter and sort 2,500 additional rows without changing ' +
    'the workflow. The wide and compact layouts are the same widget tree, so ' +
    'the demo also shows how a data-heavy TUI can remain useful when resized.',
  forms:
    'A believable service-deployment flow spread across three screens: service ' +
    'details, runtime choices, and a final review before an asynchronous deploy.\n\n' +
    'The application owns its values and layout while `Form` coordinates the ' +
    'behavior that should be consistent: validation, first-invalid focus, server ' +
    'errors, and duplicate-safe submission. Each screen is an ordinary route, so ' +
    'going back preserves the draft without a form schema or wizard abstraction.',
  themes:
    'A live studio for comparing every bundled community theme against the same ' +
    'application surface. Switch to Custom to edit primary, focus, and status ' +
    'colors, brightness, and borders.\n\n' +
    'The preview keeps ordinary text, form controls, status colors, progress, ' +
    'selected data, and actions visible together so each change is easy to see.',
  state:
    'Three small examples show where state lives in Fleury: a local counter, ' +
    'a project shared through a subtree, and a cart shared with application code.\n\n' +
    'Change the project or add an item and watch builder widgets and context ' +
    'readers update together. The [state-management guide](/fleury/guides/state-management/) ' +
    'walks through each API; the sample source puts them in one app.',
  asteroids:
    'A complete arcade game rendered into terminal cells: fixed-step physics, ' +
    'toroidal wrapping, swept collisions, asteroid splitting, particles, ' +
    'waves, lives, and score.\n\n' +
    'The playfield is a braille `Canvas`, while Fleury focus, pointer input, ' +
    'tickers, semantics, and presence effects provide the application shell. ' +
    'It is deliberately deterministic, making visual and timing regressions ' +
    'testable instead of turning the showcase into a lucky animation.',
  sprite:
    'A small but complete asset tool: paint full-color terminal cells, edit ' +
    'keyed animation frames, tune their timing, onion-skin adjacent frames, ' +
    'and preview the result live.\n\n' +
    'Every edit is undoable and the exact animation round-trips through a ' +
    'portable JSON format. It exercises pointer-to-cell geometry, custom ' +
    'rendering, focus, keyboard commands, host clipboard writes, and dense ' +
    'stateful workflows without requiring a filesystem or network service.',
};

// One concrete interaction invitation per showcase, shown right above the live
// demo — the demos are interactive, but without this visitors watch passively.
// Each is grounded in the sample source (autofocus + handlers verified).
const SHOWCASE_TRY = {
  dashboard:
    '*Try it: the process table has focus — ↑/↓ move the row selection ' +
    'while the charts stream.*',
  files:
    '*Try it: use the arrows to move to a file, then press Enter or click it ' +
    'to open its preview.*',
  commands:
    '*Try it: edit the file, then save it with Ctrl+S or press Ctrl+K and ' +
    'choose **Save current file**. Choose **New file** from the palette to ' +
    'open an untitled file; the last-command line reports each invocation.*',
  agent:
    '*Try it: type a message in the prompt (or just press Enter) and the ' +
    'next turn streams in.*',
  editor:
    '*Try it: press Ctrl+B to switch between nano and vim — the whole ' +
    'shortcut bar changes with it. Then, in vim, press `d` and pause to see ' +
    'which-key list `dd`, `dw` and `d$`.*',
  finance:
    '*Try it: search for `Netflix`, sort or filter the ledger, then enable ' +
    'Stress +2,500 to exercise the same workflow over a large fixture.*',
  forms:
    '*Try it: continue with an empty name to see first-invalid focus, then use ' +
    'the reserved name `fleury` to trigger a server error. Complete the flow and ' +
    'go back once to see the app-owned draft survive navigation.*',
  themes:
    '*Try it: arrow through the Theme picker, then choose Custom, select a ' +
    'palette role, and change its color—the full widget gallery updates immediately.*',
  state:
    '*Try it: **Increment** changes local state. **Switch project** updates both ' +
    'scope readers. **Add item** updates both readers of the shared cart.*',
  asteroids:
    '*Try it: press Space to launch, then steer with A/D/W and fire with ' +
    'Space—or click and drag directly in the playfield.*',
  sprite:
    '*Try it in this browser: drag across the cell canvas, press R to play your edit, then ' +
    'Ctrl+Z to undo the entire stroke. Copy JSON exports exactly what plays.*\n\n' +
    'In a native POSIX terminal, the app sees Ctrl+Z first, and Fleury ' +
    'suspends it only when nothing handles the key. The undo binding is off ' +
    'while there is nothing to undo, so an extra Ctrl+Z suspends the studio; ' +
    '`fg` resumes it. See ' +
    '[keys handled by the host](/fleury/guides/focus-and-keyboard/#keys-handled-by-the-host).',
};

// Layout and text primitives nearly every app is built from. Listing them
// under "Widgets used" would bury what makes each showcase distinct, so they
// stay out on purpose, and every other widget with a page is listed.
const SHOWCASE_PRIMITIVES = new Set([
  'Text', 'RichText', 'TextSpan', 'Row', 'Column', 'Expanded', 'Flexible',
  'Spacer', 'Container', 'Padding', 'SizedBox', 'ConstrainedBox', 'Center',
  'Align', 'Stack', 'Positioned', 'Wrap',
]);
// Widget name → { slug, category }, for the "widgets used" links.
const catalog = new Map(
  catalogEntries
    .filter(({ entry }) => !SHOWCASE_PRIMITIVES.has(entry.widget))
    .map(({ entry }) => [
      entry.widget,
      { slug: entry.id.split('.')[0], category: entry.category },
    ])
);
// Dart source without its comments, so a widget named in a comment or doc
// comment doesn't count as used. (String contents stay; none of the samples
// spell a constructor call inside a string.)
const withoutDartComments = (src) =>
  src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '').replace(/\s\/\/\s.*$/gm, '');
const widgetsUsedIn = (file) => {
  const src = withoutDartComments(readFileSync(join(SAMPLES_DIR, file), 'utf8'));
  const used = [];
  for (const [name, info] of catalog) {
    // A constructor call, named constructor, or static helper that builds the
    // widget (`ListView.builder(`, `CommandPalette.open(`). Lookups such as
    // `Theme.of(context)` read an ancestor the app did not build here.
    for (const [, member] of src.matchAll(
      new RegExp(`\\b${name}(?:<(?:[^<>]|<[^<>]*>)*>)?(?:\\.(\\w+))?\\s*\\(`, 'g')
    )) {
      if (member && /^(maybeOf|of|\w+Of)$/.test(member)) continue;
      used.push({ name, slug: info.slug, category: info.category });
      break;
    }
  }
  return used;
};

// Starlight orders an autogenerated sidebar group by `sidebar.order`, then by
// file name; give the showcases the index's order instead of alphabetical.
const showcaseOrder = (e) => showcases.indexOf(e) + 1;
const withFrontmatter = (mdx, lines) => mdx.replace(/^---\n/, `---\n${lines}`);
for (const e of showcases) {
  const slug = e.id.split('.')[1]; // showcase.dashboard -> dashboard
  // This command-shaped showcase has an illustrated shell and native recording,
  // so it owns its presentation instead of using the fullscreen-app template.
  if (slug === 'inline') {
    const source = readFileSync(join(here, '..', 'showcases', 'inline.mdx'), 'utf8');
    writeFileSync(
      join(showDir, 'inline.mdx'),
      withFrontmatter(source, `sidebar:\n  order: ${showcaseOrder(e)}\n`)
    );
    continue;
  }
  const file = SAMPLE_FILES[slug];
  const used = file ? widgetsUsedIn(file) : [];
  writeFileSync(
    join(showDir, `${slug}.mdx`),
    `---\ntitle: ${yaml(e.widget)}\ndescription: ${yaml(plainText(e.blurb))}\n` +
      `tableOfContents: false\neditUrl: false\nsidebar:\n  order: ${showcaseOrder(e)}\n---\n\n` +
      `import FleuryExample from '${COMPONENT}';\n` +
      `import ShowcaseStage from '${SHOWCASE_STAGE_COMPONENT}';\n` +
      `import ShowcaseWidgets from '${SHOWCASE_COMPONENT}';\n\n` +
      // Richer intro, above the demo: the "what it is + why it was easy" pitch
      // (it leads with the description). The demo then sits in a <ShowcaseStage>
      // with the run command + source link in the right-side rail beside it.
      `${SHOWCASE_GOALS[slug] ?? e.blurb}\n\n` +
      (SHOWCASE_TRY[slug] ? `${SHOWCASE_TRY[slug]}\n\n` : '') +
      `<ShowcaseStage runCmd="dart run packages/samples/bin/samples.dart ${slug}"` +
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
  `---\ntitle: Showcases\ndescription: Full-screen apps and interactive CLI commands, running live in your browser.\n` +
  `editUrl: false\nsidebar:\n  order: 0\n---\n\n` +
  `${showcases.length} complete apps, each built entirely from Fleury widgets and **running ` +
  `live in your browser** — open one and use your keyboard and mouse. Each is ` +
  `also runnable from a Fleury framework checkout with ` +
  `\`dart run packages/samples/bin/samples.dart <app>\`.\n\n` +
  showcases
    .map((e) => `- [${e.widget}](/fleury/showcases/${e.id.split('.')[1]}/) — ${e.blurb}`)
    .join('\n') +
  `\n`;
writeFileSync(join(showDir, 'index.mdx'), showIndex);

for (const widget of AWAITING_SOURCE_DOCS) {
  if (!awaitingEntries.has(widget)) {
    throw new Error(`AWAITING_SOURCE_DOCS names ${widget}, which has no page entry`);
  }
  console.log(
    deferred.has(widget)
      ? `deferred the ${widget} page until its source docs are complete:\n  - ${deferred.get(widget).join('\n  - ')}`
      : `${widget} is fully documented and published; remove it from AWAITING_SOURCE_DOCS.`
  );
}
console.log(
  `generated ${widgets.length + DOC_PAGES.length} widget/API pages + ` +
  `${showcases.length} showcase pages; covered ${exportedWidgetCount} ` +
  `exported concrete widgets`
);
