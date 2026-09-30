// Compile-checks every ```dart block on the generated widget reference pages.
//
// Most of those snippets are hand-written strings (registry `code:` overrides,
// EXTRA_EXAMPLES, CORE, DOC_ONLY) that nothing else compiles, so a renamed
// parameter or a wrong handler type would otherwise reach readers unnoticed.
// Run after `npm run gen:widgets`; wired into `prebuild`.
//
// Snippets are fragments: they use names the reader's app would define (`rows`,
// `save()`, `_quantity`). Pass 1 wraps each snippet as an expression and as a
// statement block, keeps whichever parses, and collects the names it leaves
// undefined. Pass 2 rebuilds each snippet inside a `State` with a typed
// stand-in for every such name (STUBS below) and analyzes it against the real
// packages. Anything still reported is a real error in the snippet, or a new
// placeholder name that needs a stand-in here.
import { execFileSync } from 'node:child_process';
import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const PAGES = join(here, '..', 'src', 'content', 'docs', 'widgets');
const EXAMPLES = join(here, '..', 'examples');
// Inside the examples package (so its dependencies resolve) and gitignored.
const OUT_REL = join('build', 'widget_snippets');
const OUT = join(EXAMPLES, OUT_REL);

const HEADER = `// ignore_for_file: type=lint, unused_local_variable, unused_element, unused_field, dead_code, unused_import, unnecessary_import
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:fleury/fleury.dart';
import 'package:fleury_themes/fleury_themes.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:image/image.dart' as img;
`;

// Typed stand-ins for the app-side names snippets use. Keep them realistic:
// the type is what makes the check meaningful (a `void save()` stand-in is how
// `onTrigger: save` gets caught as the wrong handler type).
const widgetStub = (name) =>
  `class ${name} extends StatelessWidget { const ${name}({super.key}); ` +
  `@override Widget build(BuildContext context) => const Text(''); }`;
const TOP_STUBS = {
  RowData: `class RowData { String label = ''; }`,
  Item: `class Item {}`,
  ItemList:
    `class ItemList extends StatelessWidget { const ItemList(this.items, {super.key}); ` +
    `final List<Item> items; @override Widget build(BuildContext context) => const Text(''); }`,
  Project: `class Project { String get name => ''; }`,
  Cart: `class Cart with Notifier { int get itemCount => 0; }`,
  Preferences: `class Preferences {}`,
  ...Object.fromEntries(
    [
      'SettingsPanel', 'ProjectPath', 'ShopScreen', 'Wide', 'Narrow', 'Editor',
      'Sidebar', 'InboxView', 'SettingsView', 'ConfirmDialog', 'DeleteDialog',
      'DetailsScreen', 'SetupStep', 'TrackRow',
    ].map((name) => [name, widgetStub(name)])
  ),
};
const STUBS = {
  // Values a control shows.
  _size: `String? _size;`, _accepted: `bool _accepted = false;`,
  _compact: `bool _compact = false;`, _streaming: `bool _streaming = false;`,
  _mode: `String? _mode;`, mode: `String? mode;`, _selected: `Set<String> _selected = {};`,
  _range: `(num, num) _range = (0, 1);`, range: `(num, num) range = (0, 1);`,
  _quantity: `num _quantity = 0;`, count: `num? count;`, cursor: `int cursor = 0;`,
  start: `num start = 0;`, end: `num end = 0;`, progress: `double progress = 0;`,
  selectedTab: `int selectedTab = 0;`, editorActive: `bool editorActive = false;`,
  _showDetails: `bool _showDetails = false;`, selected: `String selected = '';`,
  hasUnsavedChanges: `bool hasUnsavedChanges = false;`, status: `String status = '';`,
  _color: `late Color _color;`, accent: `late Color accent;`,
  _date: `late DateTime _date;`, today: `late DateTime today;`,
  options: `List<SelectOption<String>> options = [];`,
  // Controllers and models.
  controller: `late TextEditingController controller;`,
  name: `late TextEditingController name;`, slug: `late TextEditingController slug;`,
  form: `late FormController form;`, theme: `late ThemeData theme;`, cs: `late ColorScheme cs;`,
  preferences: `late Preferences preferences;`, project: `late Project project;`,
  cart: `late Cart cart;`, ticks: `late Stream<int> ticks;`,
  scroll: `late ScrollController scroll;`,
  load: `Future<List<Item>> load() async => [];`,
  // Data.
  points: `List<(num, num)> points = [];`, cpuSamples: `List<(num, num)> cpuSamples = [];`,
  memSamples: `List<(num, num)> memSamples = [];`, rows: `List<RowData> rows = [];`,
  weeklyActivity: `List<List<num>> weeklyActivity = [];`, values: `List<List<num>> values = [];`,
  latenciesMs: `List<num> latenciesMs = [];`, samples: `List<num> samples = [];`,
  cpuHistory: `List<num> cpuHistory = [];`, tags: `List<String> tags = [];`,
  downloaded: `int downloaded = 0;`, total: `int total = 1;`,
  _codeSample: `String _codeSample = '';`, _markdownSample: `String _markdownSample = '';`,
  _diffSample: `String _diffSample = '';`, utcTime: `String utcTime = '';`,
  estTime: `String estTime = '';`, longLabel: `String longLabel = '';`,
  releaseNotes: `String releaseNotes = '';`,
  logoBytes: `late Uint8List logoBytes;`, bytes: `late Uint8List bytes;`,
  buf: `late Uint8List buf;`, decoded: `late img.Image decoded;`,
  // Widgets passed in.
  app: `late Widget app;`, editor: `late Widget editor;`, child: `late Widget child;`,
  view: `late Widget view;`, pane: `late Widget pane;`, list: `late Widget list;`,
  // App callbacks.
  save: `void save() {}`, quit: `void quit() {}`, cancel: `void cancel() {}`,
  play: `void play() {}`, runTests: `void runTests() {}`, findFile: `void findFile() {}`,
  buffers: `void buffers() {}`, git: `void git() {}`, toggleTheme: `void toggleTheme() {}`,
  toggleBookmark: `void toggleBookmark() {}`, clearBookmarks: `void clearBookmarks() {}`,
  jumpToTop: `void jumpToTop() {}`, move: `void move(int delta) {}`,
  choose: `void choose(String value) {}`, search: `void search(String query) {}`,
  openFile: `void openFile(String path) {}`, openInEditor: `void openInEditor(String path) {}`,
  updateDraft: `void updateDraft(String text) {}`, runCommand: `void runCommand(String text) {}`,
  updateReleaseNotes: `void updateReleaseNotes(String text) {}`,
  saveReleaseNotes: `void saveReleaseNotes(String text) {}`,
  saveProject: `Future<void> saveProject() async {}`, setHover: `void setHover(bool value) {}`,
  _toggle: `void _toggle() {}`, _save: `void _save() {}`, _cancel: `void _cancel() {}`,
  _select: `void _select() {}`, _placeAt: `void _placeAt(CellOffset offset) {}`,
  _canScroll: `bool _canScroll(int delta) => true;`, _scrollBy: `void _scrollBy(int delta) {}`,
};
// A name whose stand-in type differs on one page.
const PAGE_STUBS = {
  commandpalette: { openFile: `void openFile() {}` },
};
// Names snippets declare as classes that the host's widget stubs complete.
const COMPANIONS = [
  [
    /class _WorkspaceState extends State<Workspace>/,
    `class Workspace extends StatefulWidget { const Workspace({super.key}); ` +
      `@override State<Workspace> createState() => _WorkspaceState(); }`,
  ],
];

const UNDEFINED = new Set([
  'UNDEFINED_IDENTIFIER', 'UNDEFINED_FUNCTION', 'CREATION_WITH_NON_TYPE',
  'NON_TYPE_AS_TYPE_ARGUMENT', 'UNDEFINED_CLASS',
]);
const DECLARATION =
  /^(class|final class|abstract class|base class|sealed class|enum|typedef|mixin|extension)\b/;

function extractSnippets() {
  const snippets = [];
  for (const file of readdirSync(PAGES).sort()) {
    if (!file.endsWith('.mdx') || file === 'index.mdx') continue;
    const slug = file.replace(/\.mdx$/, '');
    const lines = readFileSync(join(PAGES, file), 'utf8').split('\n');
    let section = 'intro';
    for (let i = 0; i < lines.length; i++) {
      const heading = lines[i].match(/^## (\w+)/);
      if (heading) section = heading[1].toLowerCase();
      if (!lines[i].trim().startsWith('```dart')) continue;
      const body = [];
      const startLine = i + 2;
      for (i++; i < lines.length && lines[i].trim() !== '```'; i++) body.push(lines[i]);
      snippets.push({
        id: `s${String(snippets.length).padStart(3, '0')}`,
        slug,
        section,
        startLine,
        code: body.join('\n'),
      });
    }
  }
  return snippets;
}

const withoutComments = (code) =>
  code.split('\n').filter((line) => !/^\s*\/\//.test(line)).join('\n').trim();

// Ends a statement chunk with `;` unless it already closes a block or a list.
function terminate(chunk) {
  const lines = chunk.split('\n');
  let i = lines.length - 1;
  while (i >= 0 && (/^\s*\/\//.test(lines[i]) || /^\s*$/.test(lines[i]))) i--;
  if (i < 0) return chunk;
  const line = lines[i].replace(/\s+$/, '');
  if (!/[;{},]$/.test(line)) lines[i] = `${line};`;
  return lines.join('\n');
}

// Splits a snippet into top-level declarations and statement chunks at blank
// lines, keeping a declaration whose body contains blank lines together.
function split(code) {
  const chunks = code.split(/\n\s*\n/);
  const depth = (text) => (text.match(/\{/g) ?? []).length - (text.match(/\}/g) ?? []).length;
  const declarations = [];
  const statements = [];
  for (let k = 0; k < chunks.length; k++) {
    let chunk = chunks[k];
    if (DECLARATION.test(withoutComments(chunk))) {
      while (depth(chunk) > 0 && k + 1 < chunks.length) chunk += `\n\n${chunks[++k]}`;
      declarations.push(chunk);
    } else {
      statements.push(chunk);
    }
  }
  return { declarations, statements };
}

function analyze() {
  let output = '';
  try {
    output = execFileSync('dart', ['analyze', '--format=machine', OUT_REL], {
      cwd: EXAMPLES,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (error) {
    // Exits non-zero whenever it reports errors; the report is still on stderr.
    output = `${error.stdout ?? ''}${error.stderr ?? ''}`;
  }
  const byFile = new Map();
  for (const line of output.split('\n')) {
    const [severity, type, code, file, row, , , ...message] = line.split('|');
    if (!file || !code) continue;
    const name = file.split(/[\\/]/).pop().replace(/\.dart$/, '');
    if (!byFile.has(name)) byFile.set(name, []);
    byFile.get(name).push({ severity, type, code, row: Number(row), message: message.join('|') });
  }
  return byFile;
}

function resetOut() {
  rmSync(OUT, { recursive: true, force: true });
  mkdirSync(OUT, { recursive: true });
}

// Pass 1: find the wrapping that parses, and the names left undefined.
function firstPass(snippets) {
  resetOut();
  for (const s of snippets) {
    const { declarations, statements } = split(s.code);
    if (declarations.length) {
      s.shape = 'mixed';
      writeFileSync(join(OUT, `m_${s.id}.dart`), `${HEADER}\n${declarations.join('\n\n')}\n` +
        (statements.length
          ? `Future<Object?> snippet(BuildContext context) async {\n${statements.map(terminate).join('\n\n')}\n  return null;\n}\n`
          : ''));
      continue;
    }
    writeFileSync(join(OUT, `e_${s.id}.dart`), `${HEADER}\nObject? snippet(BuildContext context) => (\n${s.code}\n);\n`);
    writeFileSync(join(OUT, `b_${s.id}.dart`), `${HEADER}\nFuture<Object?> snippet(BuildContext context) async {\n${statements.map(terminate).join('\n\n')}\n  return null;\n}\n`);
  }
  const report = analyze();
  for (const s of snippets) {
    let diagnostics;
    if (s.shape === 'mixed') {
      diagnostics = report.get(`m_${s.id}`) ?? [];
    } else {
      const asExpression = report.get(`e_${s.id}`) ?? [];
      const asBlock = report.get(`b_${s.id}`) ?? [];
      const syntax = (list) => list.filter((d) => d.type === 'SYNTACTIC_ERROR').length;
      const expression =
        syntax(asExpression) < syntax(asBlock) ||
        (syntax(asExpression) === syntax(asBlock) && asExpression.length <= asBlock.length);
      s.shape = expression ? 'expression' : 'block';
      diagnostics = expression ? asExpression : asBlock;
    }
    s.undefined = [
      ...new Set(
        diagnostics
          .filter((d) => UNDEFINED.has(d.code))
          .map((d) => d.message.match(/'([^']+)'/)?.[1])
          .filter(Boolean)
      ),
    ];
  }
}

// Pass 2: the snippet inside a State, with typed stand-ins for its names.
function secondPass(snippets) {
  resetOut();
  const missing = [];
  for (const s of snippets) {
    const { declarations, statements } = split(s.code);
    const companions = COMPANIONS.filter(([pattern]) => pattern.test(s.code)).map(([, source]) => source);
    const declared = [...declarations, ...companions].join('\n');
    const names = s.undefined.filter(
      (name) => !TOP_STUBS[name] && name !== 'setState' && !declared.includes(`class ${name} `)
    );
    const stubs = names.map((name) => {
      const stub = PAGE_STUBS[s.slug]?.[name] ?? STUBS[name];
      if (!stub) missing.push({ s, name });
      return stub ?? '';
    });
    let body = '';
    if (s.shape === 'expression') {
      body = `  Object? snippet(BuildContext context) => (\n${s.code}\n  );`;
    } else if (statements.length) {
      body = `  Future<Object?> snippet(BuildContext context) async {\n${statements.map(terminate).join('\n\n')}\n    return null;\n  }`;
    }
    // A snippet that declares its own classes sees the app names at top level.
    const topLevel = declarations.length ? `${stubs.join('\n')}\n${declarations.join('\n')}\n` : '';
    const members = declarations.length ? '' : stubs.join('\n  ');
    s.prefix =
      `${HEADER}\n${Object.values(TOP_STUBS).join('\n')}\n${companions.join('\n')}\n${topLevel}` +
      `class _Host extends StatefulWidget { const _Host(); ` +
      `@override State<_Host> createState() => _HostState(); }\n` +
      `class _HostState extends State<_Host> {\n  ${members}\n` +
      `  @override Widget build(BuildContext context) => const Text('');\n`;
    writeFileSync(join(OUT, `x_${s.id}.dart`), `${s.prefix}${body}\n}\n`);
  }
  const report = analyze();
  const failures = [];
  for (const s of snippets) {
    for (const d of report.get(`x_${s.id}`) ?? []) {
      if (d.severity === 'INFO') continue;
      failures.push({ s, d });
    }
  }
  return { missing, failures };
}

const snippets = extractSnippets();
if (snippets.length === 0) {
  console.error('check-widget-snippets: no widget pages found; run `npm run gen:widgets` first.');
  process.exit(1);
}
firstPass(snippets);
const { missing, failures } = secondPass(snippets);
rmSync(OUT, { recursive: true, force: true });

if (missing.length || failures.length) {
  console.error('Widget reference snippets that do not compile:\n');
  for (const { s, name } of missing) {
    console.error(
      `  widgets/${s.slug}.mdx (${s.section}, line ${s.startLine}): no stand-in for '${name}'. ` +
        `Add a typed one to STUBS in scripts/check-widget-snippets.mjs.`
    );
  }
  for (const { s, d } of failures) {
    console.error(`  widgets/${s.slug}.mdx (${s.section}, line ${s.startLine}): ${d.code}: ${d.message}`);
  }
  console.error(
    '\nFix the snippet at its source: a `code:` override in examples/lib/registry.dart, ' +
      'EXTRA_EXAMPLES / CORE / DOC_ONLY in scripts/gen-widget-pages.mjs, or the class doc comment.'
  );
  process.exit(1);
}
console.log(`check-widget-snippets: ${snippets.length} snippets compile against the real API.`);
