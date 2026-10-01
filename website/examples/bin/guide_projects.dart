// Generates the runnable Pad project behind every editable docs demo.
//
// There is no handwritten copy of an app or a snippet. Each project is built
// from the code its live preview already runs: the registry entry's builder
// and the libraries it reaches. A view selects what the reader edits, either
// a `#docregion` or an AST range (a declaration, one of its methods, or an
// invocation inside it). See GUIDE_PADS.md.
//
// Usage (from website/examples): dart run bin/guide_projects.dart
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

/// The compiler's request limits (see experiments/fleury_pad/dartpad).
const maxBytes = 64000;
const maxFiles = 24;

final repo = p.normalize(p.absolute('../..'));
final examplesLib = '$repo/website/examples/lib';
final samplesLib = '$repo/packages/samples/lib';
final units = <String, Source>{};
Source source(String file) => units.putIfAbsent(file, () => Source(file));

/// The file's path inside a project. Relative imports between example files
/// keep working because the directory layout is preserved.
String logical(String file) {
  if (p.isWithin(examplesLib, file)) {
    return 'examples/${p.relative(file, from: examplesLib)}';
  }
  if (p.isWithin(samplesLib, file)) {
    return 'samples/${p.relative(file, from: samplesLib)}';
  }
  throw StateError('$file is outside the example and sample libraries');
}

/// Resolves [uri] from [file] to a repository file the project must supply,
/// or null for a package the compiler bundles.
String? localImport(String file, String uri) {
  const samples = 'package:fleury_samples/';
  if (uri.startsWith(samples)) {
    return '$samplesLib/${uri.substring(samples.length)}';
  }
  if (!uri.contains(':')) return p.normalize(p.join(p.dirname(file), uri));
  return null;
}

class Names extends RecursiveAstVisitor<void> {
  final values = <String>{};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    values.add(node.name);
  }

  @override
  void visitNamedType(NamedType node) {
    values.add(node.name2.lexeme);
    if (node.importPrefix != null) values.add(node.importPrefix!.name.lexeme);
    super.visitNamedType(node);
  }
}

Set<String> names(AstNode node) {
  final visitor = Names();
  node.accept(visitor);
  return visitor.values;
}

Iterable<String> declared(CompilationUnitMember n) sync* {
  if (n is ClassDeclaration) yield n.name.lexeme;
  if (n is EnumDeclaration) yield n.name.lexeme;
  if (n is MixinDeclaration) yield n.name.lexeme;
  if (n is ExtensionDeclaration && n.name != null) yield n.name!.lexeme;
  if (n is FunctionDeclaration) yield n.name.lexeme;
  if (n is GenericTypeAlias) yield n.name.lexeme;
  if (n is TopLevelVariableDeclaration) {
    yield* n.variables.variables.map((v) => v.name.lexeme);
  }
}

class Source {
  Source(this.path) {
    text = File(path).readAsStringSync();
    unit = parseString(content: text, throwIfDiagnostics: false).unit;
    for (final node in unit.declarations) {
      for (final name in declared(node)) {
        declarations[name] = node;
      }
    }
  }

  final String path;
  late final String text;
  late final CompilationUnit unit;
  final declarations = <String, CompilationUnitMember>{};

  Set<String> exported([Set<String>? seen]) {
    seen ??= {};
    if (!seen.add(path)) return {};
    return {
      ...declarations.keys.where((name) => !name.startsWith('_')),
      for (final d in unit.directives.whereType<ExportDirective>())
        if (localImport(path, d.uri.stringValue!) case final target?)
          ...source(target).exported(seen),
    };
  }
}

/// Finds each registry entry's builder expression and category.
class EntryVisitor extends RecursiveAstVisitor<void> {
  final entries = <String, Expression>{};
  final categories = <String, String>{};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'ExampleInfo') {
      final args = {
        for (final n
            in node.argumentList.arguments.whereType<NamedExpression>())
          n.name.label.name: n.expression,
      };
      final id = (args['id'] as StringLiteral).stringValue!;
      final fn = args['builder'] as FunctionExpression;
      entries[id] = (fn.body as ExpressionFunctionBody).expression;
      categories[id] = (args['category'] as StringLiteral).stringValue!;
    }
    super.visitMethodInvocation(node);
  }
}

/// A docregion block, as offsets into a rendered file.
typedef Block = ({int start, int end});

class Project {
  final selected = <String, Set<CompilationUnitMember>>{};
  final imports = <String, Set<ImportDirective>>{};
  final exports = <String, Set<ExportDirective>>{};
  final pendingNames = <String, Set<String>>{};

  /// Files rendered whole, comments included, rather than trimmed to the
  /// declarations the demo needs.
  final whole = <String>{};

  /// Docregion blocks of the whole files, by file then region name.
  final regions = <String, Map<String, List<Block>>>{};

  void include(String file, Set<String> needed) {
    final nodes = selected.putIfAbsent(file, () => {});
    final fresh = needed.difference(pendingNames.putIfAbsent(file, () => {}));
    if (fresh.isEmpty) return;
    pendingNames[file]!.addAll(fresh);
    final src = source(file);
    for (final name in fresh) {
      final node = src.declarations[name];
      if (node != null && nodes.add(node)) include(file, names(node));
    }
    // Resolve only repository-local imports and exports into editable files.
    for (final d in src.unit.directives) {
      if (d is ImportDirective) {
        final target = localImport(file, d.uri.stringValue!);
        final used =
            d.prefix == null || pendingNames[file]!.contains(d.prefix!.name);
        if (target == null) {
          if (used) imports.putIfAbsent(file, () => {}).add(d);
        } else {
          final wanted = source(target).exported().intersection(fresh);
          if (wanted.isNotEmpty && used) {
            imports.putIfAbsent(file, () => {}).add(d);
            include(target, wanted);
          }
        }
      } else if (d is ExportDirective) {
        final target = localImport(file, d.uri.stringValue!);
        if (target != null) {
          final wanted = source(target).exported().intersection(fresh);
          if (wanted.isNotEmpty) {
            exports.putIfAbsent(file, () => {}).add(d);
            include(target, wanted);
          }
        }
      }
    }
  }

  /// Includes [file] as written, with every library it imports.
  void includeWhole(String file) {
    whole.add(file);
    final src = source(file);
    include(file, src.declarations.keys.toSet());
    for (final d in src.unit.directives.whereType<UriBasedDirective>()) {
      final target = localImport(file, d.uri.stringValue!);
      if (target == null) continue;
      selected.putIfAbsent(target, () => {});
      include(target, source(target).exported().intersection(names(src.unit)));
    }
  }

  String relativeUri(String from, String target) =>
      p.relative(logical(target), from: p.dirname(logical(from)));

  String directive(String file, UriBasedDirective d) {
    final src = source(file);
    final target = localImport(file, d.uri.stringValue!);
    if (target == null) return src.text.substring(d.offset, d.end);
    return src.text.substring(d.offset, d.uri.offset) +
        "'${relativeUri(file, target)}'" +
        src.text.substring(d.uri.end, d.end);
  }

  /// [file] as written, with local package imports made relative and the
  /// docregion marker and `// dart format width=` pragma lines removed: both
  /// are tooling for this repository, not code a reader edits. Records where
  /// each region's blocks land.
  String renderWhole(String file) {
    final src = source(file);
    var text = src.text;
    final directives =
        src.unit.directives.whereType<UriBasedDirective>().toList()
          ..sort((a, b) => b.uri.offset.compareTo(a.uri.offset));
    for (final d in directives) {
      final target = localImport(file, d.uri.stringValue!);
      if (target == null || !d.uri.stringValue!.contains(':')) continue;
      text = text.replaceRange(
        d.uri.offset,
        d.uri.end,
        "'${relativeUri(file, target)}'",
      );
    }
    final marker = RegExp(r'^[ \t]*// #(end)?docregion ([\w-]+)[ \t]*$');
    final formatPragma = RegExp(r'^// dart format width=\d+[ \t]*$');
    final open = <String, int>{};
    final found = <String, List<Block>>{};
    final out = StringBuffer();
    for (final line in const LineSplitter().convert(text)) {
      if (formatPragma.hasMatch(line)) continue;
      final match = marker.firstMatch(line);
      if (match == null) {
        out.writeln(line);
        continue;
      }
      final name = match[2]!;
      if (match[1] == null) {
        open[name] = out.length;
      } else {
        final start =
            open.remove(name) ??
            (throw StateError('$file: unopened #enddocregion $name'));
        found.putIfAbsent(name, () => []).add((start: start, end: out.length));
      }
    }
    if (open.isNotEmpty) {
      throw StateError('$file: unclosed #docregion ${open.keys.join(', ')}');
    }
    regions[logical(file)] = found;
    return out.toString();
  }

  Map<String, String> render(String root, Expression builder) {
    final files = <String, String>{};
    for (final file in selected.keys) {
      if (whole.contains(file)) {
        files[logical(file)] = renderWhole(file);
        continue;
      }
      final nodes = selected[file]!.toList()
        ..sort((a, b) => a.offset.compareTo(b.offset));
      final ds = [...?imports[file], ...?exports[file]]
        ..sort((a, b) => a.offset.compareTo(b.offset));
      final text = source(file).text;
      files[logical(file)] =
          '${ds.map((d) => directive(file, d)).join('\n')}\n\n'
          '${nodes.map((n) => text.substring(n.offset, n.end)).join('\n\n')}\n';
    }
    // The docs-only frame stays out of the code a reader edits: `example()`
    // is the demo, `buildExample()` frames it as the registry does.
    final demo = unframed(builder);
    files[logical(root)] =
        '${files[logical(root)]}\n'
        'Widget buildExample() => '
        '${identical(demo, builder) ? 'example()' : '_framed(example())'};\n\n'
        'Widget example() => ${topLevel(source(root).text, demo)};\n';
    // The same theme and focus traversal as the prebuilt preview. The frame's
    // URL fragment names the docs page's theme (see experiments/fleury_pad).
    files['main.dart'] =
        "import 'package:fleury/fleury_core.dart';\n"
        "import 'package:web/web.dart' as web;\n"
        "import '${logical(root)}';\n\n"
        'final _style = DocsExampleThemeController(\n'
        "  web.window.location.hash.contains('theme=light')\n"
        '      ? DocsExampleStyle.light\n'
        '      : DocsExampleStyle.dark,\n'
        ');\n\n'
        'Widget buildApp() => themedExampleRoot(buildExample, _style);\n';
    return files;
  }
}

/// Finds invocations of [name], constructor or method, inside a node.
class Finder extends RecursiveAstVisitor<void> {
  Finder(this.name);

  final String name;
  final nodes = <AstNode>[];

  @override
  void visitMethodInvocation(MethodInvocation n) {
    if (n.methodName.name == name) nodes.add(n);
    super.visitMethodInvocation(n);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression n) {
    if (n.constructorName.type.name2.lexeme == name) nodes.add(n);
    super.visitInstanceCreationExpression(n);
  }
}

/// The source ranges of the multi-line strings inside a node.
class MultilineStrings extends RecursiveAstVisitor<void> {
  final ranges = <Block>[];

  void add(StringLiteral node) {
    if (node.toSource().contains('\n')) {
      ranges.add((start: node.offset, end: node.end));
    }
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => add(node);

  @override
  void visitStringInterpolation(StringInterpolation node) => add(node);
}

/// [node]'s source in [text] as code that starts a top-level line, such as
/// `Widget example() => …`: its continuation lines lose the indentation of
/// the line [node] starts on, as `dart format` would write them. Lines that
/// begin inside a multi-line string are its content and stay as written.
String topLevel(String text, AstNode node) {
  final lineStart = node.offset == 0
      ? 0
      : text.lastIndexOf('\n', node.offset - 1) + 1;
  var indent = 0;
  while (text.codeUnitAt(lineStart + indent) == 0x20) {
    indent++;
  }
  final strings = MultilineStrings();
  node.accept(strings);
  final lines = text.substring(node.offset, node.end).split('\n');
  var at = node.offset;
  final out = <String>[];
  for (final (i, line) in lines.indexed) {
    final inString = strings.ranges.any((s) => s.start < at && at < s.end);
    var cut = 0;
    if (i > 0 && !inString) {
      while (cut < indent && cut < line.length && line[cut] == ' ') {
        cut++;
      }
    }
    out.add(line.substring(cut));
    at += line.length + 1;
  }
  return out.join('\n');
}

/// [builder] without the registry's docs-only `_framed(...)` wrapper.
Expression unframed(Expression builder) =>
    builder is MethodInvocation &&
        builder.methodName.name == '_framed' &&
        builder.argumentList.arguments.length == 1
    ? builder.argumentList.arguments.single
    : builder;

/// The file a registry import with [prefix] names, if it is a local file.
String? prefixedImport(String file, String prefix) {
  for (final d in source(file).unit.directives.whereType<ImportDirective>()) {
    if (d.prefix?.name == prefix) return localImport(file, d.uri.stringValue!);
  }
  return null;
}

/// The import prefixes [unit] declares, such as `lists` in
/// `import 'lists_guide.dart' as lists;`.
Set<String> importPrefixes(CompilationUnit unit) => {
  for (final d in unit.directives.whereType<ImportDirective>())
    if (d.prefix case final prefix?) prefix.name,
};

/// The State class a stateful widget declaration creates, if it names one.
String? stateClassOf(ClassDeclaration widget) {
  for (final m in widget.members.whereType<MethodDeclaration>()) {
    if (m.name.lexeme != 'createState') continue;
    final body = m.body;
    if (body is! ExpressionFunctionBody) return null;
    return switch (body.expression) {
      InstanceCreationExpression e => e.constructorName.type.name2.lexeme,
      MethodInvocation e => e.methodName.name,
      _ => null,
    };
  }
  return null;
}

/// The view a widget reference page edits: the demo's widget, or its State
/// class when it is stateful, else the demo expression itself.
List<Map<String, dynamic>> widgetPageViews(
  String id,
  String root,
  Expression builder,
) {
  final demo = unframed(builder);
  String? type;
  String? prefix;
  if (demo is InstanceCreationExpression) {
    type = demo.constructorName.type.name2.lexeme;
    prefix = demo.constructorName.type.importPrefix?.name.lexeme;
  } else if (demo is MethodInvocation) {
    type = demo.methodName.name;
    prefix = switch (demo.target) {
      SimpleIdentifier(:final name) => name,
      _ => null,
    };
  }
  // Without resolution, `_Demo.wide()` reads as type `wide` behind an import
  // prefix `_Demo`. A prefix the registry doesn't import names the class.
  if (prefix != null && !importPrefixes(source(root).unit).contains(prefix)) {
    type = prefix;
    prefix = null;
  }
  final label = '${id.split('.').first}_example.dart';
  final file = type == null
      ? null
      : prefix == null
      ? root
      : prefixedImport(root, prefix);
  final declaration = file == null ? null : source(file).declarations[type];
  if (file != null && declaration is ClassDeclaration) {
    final state = stateClassOf(declaration);
    return [
      {
        'label': label,
        'source': p.relative(file, from: repo),
        'declaration':
            state != null && source(file).declarations.containsKey(state)
            ? state
            : type,
      },
    ];
  }
  return [
    {
      'label': label,
      'source': p.relative(root, from: repo),
      'declaration': 'example',
    },
  ];
}

/// The part of [blocks] a reader edits: from the first line of code to the
/// end of the last, skipping blocks that only hold import directives. [block]
/// picks one block instead, for a region whose blocks surround other views.
Block regionView(String content, List<Block> blocks, int? block, String where) {
  bool directivesOnly(Block b) => content
      .substring(b.start, b.end)
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .every(
        (line) => line.startsWith('import ') || line.startsWith('export '),
      );
  var code = blocks.where((b) => !directivesOnly(b)).toList();
  if (code.isEmpty) throw StateError('$where has no code outside directives');
  if (block != null) {
    if (block >= code.length) throw StateError('$where has no block $block');
    code = [code[block]];
  }
  var start = code.first.start;
  while (start < content.length && content[start].trim().isEmpty) {
    start++;
  }
  var end = code.last.end;
  while (end > start && content[end - 1].trim().isEmpty) {
    end--;
  }
  return (start: start, end: end);
}

void main() {
  final root = '$examplesLib/registry.dart';
  final visitor = EntryVisitor();
  source(root).unit.accept(visitor);
  final config =
      jsonDecode(File('guide_projects.json').readAsStringSync())
          as Map<String, dynamic>;
  final out = <String, Object>{};
  // Every widget reference page's demo is editable too. Their views follow
  // from each example's builder; guide_projects.json lists the rest, and the
  // widget demos that span more than one declaration.
  final entries = <String, (List<Map<String, dynamic>>, bool)>{
    for (final item in config.entries)
      item.key: ((item.value as List).cast<Map<String, dynamic>>(), false),
  };
  for (final MapEntry(key: id, value: builder) in visitor.entries.entries) {
    if (entries.containsKey(id) ||
        guideCategories.contains(visitor.categories[id]) ||
        id.contains('.lab.') ||
        knobWidgets.contains(id.split('.').first)) {
      continue;
    }
    entries[id] = (widgetPageViews(id, root, builder), true);
  }
  for (final MapEntry(key: id, value: (views, derived)) in entries.entries) {
    try {
      out[id] = generate(id, root, visitor, views);
    } on StateError catch (error) {
      // A derived project that cannot run leaves its page's plain demo.
      if (!derived) rethrow;
      stderr.writeln('Skipping the editable demo for $id: ${error.message}');
    }
  }
  // A demo's editable code must be the whole demo: a helper, sample data, or
  // builder argument outside every view is code the reader can't see or
  // change. hiddenByDesign lists the few deliberate exceptions, each with its
  // reason; one that no longer matches anything is reported too.
  final problems = [
    for (final MapEntry(key: id, value: project) in out.entries)
      for (final problem in demoProblems(
        project as Map<String, Object>,
        hiddenByDesign[id] ?? const {},
      ))
        '  $id: $problem',
  ];
  for (final id in hiddenByDesign.keys.where((id) => !out.containsKey(id))) {
    problems.add('  $id: hiddenByDesign names a project that does not exist');
  }
  if (problems.isNotEmpty) {
    stderr.writeln(
      'Demos that run code their editable views do not show:\n'
      '${problems.join('\n')}\n'
      'Move the data or helper into the demo widget, or give the demo a view '
      'of it in guide_projects.json (see GUIDE_PADS.md).',
    );
    exit(1);
  }
  File(
    '../src/guide_projects.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(out)}\n');
  stdout.writeln('Generated ${out.length} runnable guide projects.');
}

/// Why an input guide demo's file runs hidden: each section edits only the
/// lines it teaches, and the page shows the whole file beside the demo,
/// read-only, as its "Full source".
const _excerpt =
    'the demo edits an excerpt of this file, and the page shows all of it '
    'as the Full source';

/// What a guide demo deliberately keeps out of its editable views, by example
/// id, with why showing it would be noise rather than lesson. An excuse names
/// a declaration (a class's name also covers its members) or a project file
/// (covering everything declared in it). Everything else a demo runs must
/// appear in one of its views, including what excused code uses.
const hiddenByDesign = <String, Map<String, String>>{
  'commands.overview': {
    'samples/src/scaffold.dart':
        "the samples' shared theme, toast host, and background fill, which "
        'wrap every sample app and have nothing to do with commands',
  },
  'themes.interactive_styles': {
    '_InteractiveStyleTour':
        'draws each state as static text resolved with CellStyle.resolve, '
        'which the guide reserves for authors of reusable widgets',
  },
  'input.actions': {'examples/input/file_actions.dart': _excerpt},
  'input.nesting': {'examples/input/nested_row.dart': _excerpt},
  'input.press': {
    'examples/input/press_tile.dart': _excerpt,
    'examples/input/note_preview.dart':
        'the preview the excerpt opens; the page shows this file in full '
        'beside press_tile.dart, under "Preview rendering"',
  },
  'input.scrolling': {'examples/input/scroll_panes.dart': _excerpt},
  'input.splitter': {'examples/input/split_pane.dart': _excerpt},
};

/// Registry categories that are not widget reference pages.
const guideCategories = {'Guide examples', 'Home', 'Showcases', 'Theming'};

/// Widget pages whose demo is a props playground (see gen-widget-pages.mjs).
const knobWidgets = {
  'gauge',
  'progressbar',
  'histogram',
  'heatmap',
  'anchored',
};

Map<String, Object> generate(
  String id,
  String root,
  EntryVisitor visitor,
  List<Map<String, dynamic>> views,
) {
  final builder =
      visitor.entries[id] ?? (throw StateError('no registry example $id'));
  final project = Project()
    ..include(root, {
      ...names(builder),
      'themedExampleRoot',
      'DocsExampleThemeController',
      'DocsExampleStyle',
    });
  for (final view in views) {
    final file = '$repo/${view['source']}';
    if (!File(file).existsSync()) {
      throw StateError('${id}: missing ${view['source']}');
    }
    if (view['declaration'] == null) {
      project.includeWhole(file);
    } else {
      project.include(file, {
        view['declaration'] as String,
        if (view['through'] case final String through) through,
      });
    }
  }
  final files = project.render(root, builder);
  final selections = <Map<String, Object>>[];
  for (var i = 0; i < views.length; i++) {
    final view = views[i];
    final file = logical('$repo/${view['source']}');
    final content = files[file]!;
    final where = '${id} view $i (${view['source']})';
    Block range;
    if (view['region'] case final String region) {
      final blocks =
          project.regions[file]?[region] ??
          (throw StateError('$where: no #docregion $region'));
      range = regionView(content, blocks, view['block'] as int?, where);
    } else if (view['declaration'] case final String declaration) {
      final unit = parseString(
        content: content,
        throwIfDiagnostics: false,
      ).unit;
      AstNode node = unit.declarations.firstWhere(
        (n) => declared(n).contains(declaration),
        orElse: () => throw StateError('$where: no $declaration'),
      );
      if (view['member'] case final String member) {
        node = (node as ClassDeclaration).members
            .whereType<MethodDeclaration>()
            .firstWhere(
              (n) => n.name.lexeme == member,
              orElse: () => throw StateError('$where: no $member'),
            );
      }
      if (view['expression'] case final String expression) {
        final finder = Finder(expression);
        node.accept(finder);
        final occurrence = view['occurrence'] as int? ?? 0;
        if (finder.nodes.length <= occurrence) {
          throw StateError('$where: no $expression #$occurrence');
        }
        node = finder.nodes[occurrence];
      }
      range = (start: node.offset, end: node.end);
      // A declaration view can run on through later top-level declarations
      // that read with it, such as an app's constants and its root widget.
      if (view['through'] case final String through) {
        final last = unit.declarations.firstWhere(
          (n) => declared(n).contains(through),
          orElse: () => throw StateError('$where: no $through'),
        );
        if (node.parent is! CompilationUnit || last.end <= node.end) {
          throw StateError('$where: `through` needs a later declaration');
        }
        range = (start: node.offset, end: last.end);
      }
    } else {
      range = (start: 0, end: content.length);
    }
    selections.add({
      'id': 'view-$i',
      'label': view['label'] ?? p.basename(file),
      'file': file,
      'start': range.start,
      'end': range.end,
    });
  }
  final bytes = files.values.fold<int>(0, (n, s) => n + utf8.encode(s).length);
  if (bytes > maxBytes || files.length > maxFiles) {
    throw StateError(
      '${id}: $bytes bytes in ${files.length} files exceeds the '
      "compiler's $maxBytes bytes / $maxFiles files",
    );
  }
  for (final a in selections) {
    for (final b in selections) {
      if (!identical(a, b) &&
          a['file'] == b['file'] &&
          (a['start'] as int) < (b['end'] as int) &&
          (b['start'] as int) < (a['end'] as int)) {
        throw StateError('${id}: views overlap');
      }
    }
  }
  return {'id': id, 'files': files, 'views': selections};
}

/// What code inside [ranges] of a unit needs a reader to see: the top-level
/// names it refers to on its own or through one of the unit's import
/// [prefixes], the members of an enclosing class it uses unqualified, and
/// the names it reaches through an object, which an extension may declare
/// (`shout` in `'hi'.shout()`).
///
/// Names a range declares itself (locals, parameters, pattern variables)
/// shadow the rest within that range only; fields are members, not locals.
/// A named argument's label, a dot shorthand such as `.center`, a cascade
/// section such as `..start()`, and a doc comment's `[reference]` refer to
/// nothing a reader has to find.
class References extends RecursiveAstVisitor<void> {
  References(this.ranges, this.prefixes);

  final List<Block> ranges;
  final Set<String> prefixes;

  final _names = <int, Set<String>>{};
  final _locals = <int, Set<String>>{};
  final _members = <int, Set<(ClassMember, String)>>{};
  final _membersOf = <AstNode, Map<String, ClassMember>>{};

  /// Names reached through an object, such as `shout` in `'hi'.shout()`.
  final reached = <String>{};

  int? rangeOf(AstNode node) {
    for (final (i, r) in ranges.indexed) {
      if (r.start <= node.offset && node.end <= r.end) return i;
    }
    return null;
  }

  bool inside(AstNode node) => rangeOf(node) != null;

  /// The top-level names the ranges refer to.
  Set<String> get external => {
    for (final MapEntry(key: i, value: names) in _names.entries)
      ...names.difference(_locals[i] ?? const {}),
  };

  /// The members of enclosing classes the ranges use, with each one's name.
  Set<(ClassMember, String)> get members => {
    for (final MapEntry(key: i, value: uses) in _members.entries)
      for (final use in uses)
        if (!(_locals[i] ?? const {}).contains(use.$2)) use,
  };

  bool _isPrefix(Expression? target) =>
      target is SimpleIdentifier && prefixes.contains(target.name);

  /// The class, mixin, or extension around [node] that declares [name].
  ClassMember? _member(AstNode node, String name) {
    for (AstNode? n = node.parent; n != null; n = n.parent) {
      final members = switch (n) {
        ClassDeclaration(:final members) ||
        MixinDeclaration(:final members) ||
        ExtensionDeclaration(:final members) => members,
        _ => null,
      };
      if (members == null) continue;
      final byName = _membersOf.putIfAbsent(
        n,
        () => {
          for (final member in members)
            for (final name in memberNames(member)) name: member,
        },
      );
      if (byName[name] case final member?) return member;
    }
    return null;
  }

  @override
  void visitComment(Comment node) {}

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final range = rangeOf(node);
    if (range == null) return;
    final throughObject = switch (node.parent) {
      PropertyAccess(:final propertyName, :final target) =>
        identical(propertyName, node) && target is! ThisExpression,
      PrefixedIdentifier(:final identifier, :final prefix) =>
        identical(identifier, node) && !prefixes.contains(prefix.name),
      MethodInvocation(:final methodName, :final target, :final isCascaded) =>
        identical(methodName, node) &&
            (isCascaded ||
                target != null &&
                    target is! ThisExpression &&
                    !_isPrefix(target)),
      ConstructorName(:final name) => identical(name, node),
      _ => false,
    };
    if (throughObject) {
      reached.add(node.name);
      return;
    }
    // A label names a parameter. A dot shorthand (`.center`, `.ctrl`) names a
    // member of the type the context expects: its expression starts with
    // the period before the name.
    final parent = node.parent;
    if (parent is Label ||
        parent?.beginToken.type == TokenType.PERIOD &&
            identical(parent?.beginToken.next, node.token)) {
      return;
    }
    if (_member(node, node.name) case final member?) {
      _members.putIfAbsent(range, () => {}).add((member, node.name));
      return;
    }
    _names.putIfAbsent(range, () => {}).add(node.name);
  }

  @override
  void visitNamedType(NamedType node) {
    final range = rangeOf(node);
    if (range != null) {
      // Without resolution, `_Demo.wide()` reads as type `wide` behind an
      // import prefix `_Demo`: a prefix the unit doesn't import is the type.
      final prefix = node.importPrefix?.name.lexeme;
      _names
          .putIfAbsent(range, () => {})
          .add(
            prefix != null && !prefixes.contains(prefix)
                ? prefix
                : node.name2.lexeme,
          );
    }
    super.visitNamedType(node);
  }

  void _local(Token? name, AstNode node) {
    final range = rangeOf(node);
    if (name != null && range != null) {
      _locals.putIfAbsent(range, () => {}).add(name.lexeme);
    }
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    // Fields and top-level variables are declarations, not locals.
    if (node.parent?.parent
        case VariableDeclarationStatement() || ForPartsWithDeclarations()) {
      _local(node.name, node);
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitSimpleFormalParameter(SimpleFormalParameter node) {
    _local(node.name, node);
    super.visitSimpleFormalParameter(node);
  }

  @override
  void visitFunctionTypedFormalParameter(FunctionTypedFormalParameter node) {
    _local(node.name, node);
    super.visitFunctionTypedFormalParameter(node);
  }

  @override
  void visitDeclaredIdentifier(DeclaredIdentifier node) {
    _local(node.name, node);
    super.visitDeclaredIdentifier(node);
  }

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    _local(node.name, node);
    super.visitDeclaredVariablePattern(node);
  }

  @override
  void visitCatchClauseParameter(CatchClauseParameter node) {
    _local(node.name, node);
    super.visitCatchClauseParameter(node);
  }

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {
    _local(node.functionDeclaration.name, node);
    super.visitFunctionDeclarationStatement(node);
  }
}

/// The names [member] declares: a method's, or each of a field's variables.
Iterable<String> memberNames(ClassMember member) => switch (member) {
  MethodDeclaration(:final name) => [name.lexeme],
  FieldDeclaration(:final fields) => fields.variables.map((v) => v.name.lexeme),
  _ => const [],
};

/// What [project] runs that none of its views shows and [allowed] doesn't
/// excuse, and each [allowed] entry that excuses nothing. [allowed] maps an
/// excuse to its reason: a declaration's name, which also covers a class's
/// members, or a project file such as `examples/input/press_tile.dart`,
/// which covers everything declared in it. What excused code uses needs its
/// own excuse or a view.
List<String> demoProblems(
  Map<String, Object> project,
  Map<String, String> allowed,
) {
  final problems = <String>[];
  final matched = <String>{};
  for (final item in hiddenCode(project, excused: allowed.keys.toSet())) {
    final key = allowed.keys.where((k) => excuses(k, item)).firstOrNull;
    if (key == null) {
      problems.add(item.reason);
    } else {
      matched.add(key);
    }
  }
  for (final key in allowed.keys.toSet().difference(matched)) {
    problems.add('hiddenByDesign lists $key, which is not hidden');
  }
  return problems;
}

/// Whether the excuse [key] covers [item]: its name, its class, or its file.
bool excuses(String key, Hidden item) =>
    item.name == key || item.name.startsWith('$key.') || item.file == key;

/// Something a demo runs that none of its views shows: [name] is the
/// declaration (`Class.member` for a member), or `example` for the builder,
/// and [file] the project file that declares it.
typedef Hidden = ({String name, String file, String reason});

/// The demo code of [project] that none of its views shows:
///
/// - top-level declarations the views use;
/// - members of a class that a view of part of the class uses, such as a
///   helper method a `build` excerpt calls;
/// - extension members the views call, such as `'hi'.shout()`;
/// - the builder's `example()` expression, when it does more than create the
///   demo widget, and that widget, when no view shows it;
/// - what a shown State's widget uses: the State's view stands for the
///   widget's declaration, but not for constants its defaults read;
/// - what [excused] code uses (excuses as [demoProblems] takes them), so
///   nothing runs hidden behind an excused declaration without an excuse of
///   its own.
List<Hidden> hiddenCode(
  Map<String, Object> project, {
  Set<String> excused = const {},
}) {
  final files = project['files'] as Map<String, String>;
  final views = (project['views'] as List).cast<Map<String, Object>>();
  final declarations = <String, CompilationUnitMember>{};
  final fileOf = <AstNode, String>{};
  final prefixesOf = <AstNode, Set<String>>{};
  final extensions = <ExtensionDeclaration, Set<String>>{};
  final shown = <String>{};
  final standIns = <String>{};
  final used = <String>{};
  final reached = <String>{};
  final hidden = <Hidden>[];
  String? created;
  for (final MapEntry(key: file, value: text) in files.entries) {
    if (file == 'main.dart') continue;
    final ranges = <Block>[
      for (final view in views)
        if (view['file'] == file)
          (start: view['start'] as int, end: view['end'] as int),
    ];
    final unit = parseString(content: text, throwIfDiagnostics: false).unit;
    final prefixes = importPrefixes(unit);
    final references = References(ranges, prefixes);
    unit.accept(references);
    used.addAll(references.external);
    reached.addAll(references.reached);
    for (final (member, name) in references.members) {
      if (references.inside(member)) continue;
      final qualified = '${ownerName(member)}.$name';
      hidden.add((
        name: qualified,
        file: file,
        reason: 'its view uses $qualified',
      ));
    }
    for (final node in unit.declarations) {
      for (final name in declared(node)) {
        declarations[name] = node;
      }
      fileOf[node] = file;
      prefixesOf[node] = prefixes;
      if (node is ExtensionDeclaration && !references.inside(node)) {
        extensions[node] = {for (final m in node.members) ...memberNames(m)};
      }
      if (references.inside(node)) {
        shown.addAll(declared(node));
        // A State's view stands for its widget's boilerplate declaration.
        if (node case ClassDeclaration(
          extendsClause: ExtendsClause(:final superclass),
        ) when superclass.name2.lexeme == 'State') {
          for (final type in [...?superclass.typeArguments?.arguments]) {
            if (type is NamedType) standIns.add(type.name2.lexeme);
          }
        }
        continue;
      }
      if (node case FunctionDeclaration(
        :final name,
        functionExpression: FunctionExpression(
          body: ExpressionFunctionBody(:final expression),
        ),
      ) when name.lexeme == 'example') {
        if (!createsWithoutArguments(expression)) {
          hidden.add((
            name: 'example',
            file: file,
            reason: 'its builder runs `${expression.toSource()}`',
          ));
        } else {
          created = createdName(expression, prefixes);
        }
      }
    }
  }
  shown.addAll(standIns);
  String fileFor(String name) =>
      declarations[name] == null ? '' : fileOf[declarations[name]]!;
  // Code that runs although no view shows it: a stand-in widget's
  // declaration, and excused code. What it uses must be shown or excused.
  final sources = {
    for (final name in standIns)
      if (declarations[name] case final node?) name: node,
    for (final MapEntry(key: name, value: node) in declarations.entries)
      if (!shown.contains(name) &&
          (excused.contains(name) || excused.contains(fileOf[node])))
        name: node,
  };
  final through = <String, String>{};
  for (final MapEntry(key: name, value: node) in sources.entries) {
    final references = References([
      (start: node.offset, end: node.end),
    ], prefixesOf[node]!);
    node.accept(references);
    reached.addAll(references.reached);
    for (final use in references.external) {
      if (!declared(node).contains(use) && !shown.contains(use)) {
        through[use] ??= name;
      }
    }
  }
  final found = <String, Hidden>{};
  for (final item in <Hidden>[
    for (final name in used)
      if (declarations.containsKey(name) && !shown.contains(name))
        (name: name, file: fileFor(name), reason: 'its view uses $name'),
    for (final MapEntry(key: name, value: via) in through.entries)
      if (declarations.containsKey(name))
        (
          name: name,
          file: fileFor(name),
          reason: '$via uses $name, which no view shows',
        ),
    for (final MapEntry(key: extension, value: members) in extensions.entries)
      for (final member in members.intersection(reached))
        (
          name: '${extensionName(extension)}.$member',
          file: fileOf[extension]!,
          reason:
              'its code calls $member from ${extensionName(extension)}, '
              'which no view shows',
        ),
    if (created case final created? when !shown.contains(created))
      (
        name: created,
        file: fileFor(created),
        reason: 'its builder creates $created, which no view shows',
      ),
    ...hidden,
  ]) {
    found.putIfAbsent(item.name, () => item);
  }
  return [...found.values];
}

/// The name of the class, mixin, or extension that declares [member].
String ownerName(ClassMember member) => switch (member.thisOrAncestorMatching(
  (n) => n is NamedCompilationUnitMember || n is ExtensionDeclaration,
)) {
  NamedCompilationUnitMember(:final name) => name.lexeme,
  ExtensionDeclaration extension => extensionName(extension),
  _ => '?',
};

/// [extension]'s name, or `extension on T` for an unnamed one.
String extensionName(ExtensionDeclaration extension) =>
    extension.name?.lexeme ??
    'extension on ${extension.onClause?.extendedType.toSource()}';

/// The widget or function [expression] creates or calls: `_Demo` for
/// `const _Demo()` or `const _Demo.wide()`, `Demo` for `lists.Demo()`.
String? createdName(Expression expression, Set<String> prefixes) =>
    switch (expression) {
      InstanceCreationExpression(constructorName: ConstructorName(:final type))
          when type.importPrefix != null &&
              !prefixes.contains(type.importPrefix!.name.lexeme) =>
        type.importPrefix!.name.lexeme,
      InstanceCreationExpression(:final constructorName) =>
        constructorName.type.name2.lexeme,
      MethodInvocation(target: SimpleIdentifier(:final name))
          when !prefixes.contains(name) =>
        name,
      MethodInvocation(:final methodName) => methodName.name,
      _ => null,
    };

/// Whether [expression] only creates a widget, such as `const _Demo()`.
bool createsWithoutArguments(Expression expression) => switch (expression) {
  // Without `const`, `Demo()` and `prefix.Demo()` parse as invocations.
  InstanceCreationExpression(:final argumentList) ||
  MethodInvocation(
    target: null || SimpleIdentifier(),
    :final argumentList,
  ) => argumentList.arguments.isEmpty,
  _ => false,
};
