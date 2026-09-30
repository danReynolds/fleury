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

/// Finds each registry entry's builder expression.
class EntryVisitor extends RecursiveAstVisitor<void> {
  final entries = <String, Expression>{};

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
        final used = d.prefix == null ||
            pendingNames[file]!.contains(d.prefix!.name);
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
  /// docregion marker lines removed. Records where each region's blocks land.
  String renderWhole(String file) {
    final src = source(file);
    var text = src.text;
    final directives = src.unit.directives.whereType<UriBasedDirective>()
        .toList()
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
    final open = <String, int>{};
    final found = <String, List<Block>>{};
    final out = StringBuffer();
    for (final line in const LineSplitter().convert(text)) {
      final match = marker.firstMatch(line);
      if (match == null) {
        out.writeln(line);
        continue;
      }
      final name = match[2]!;
      if (match[1] == null) {
        open[name] = out.length;
      } else {
        final start = open.remove(name) ??
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
    files[logical(root)] =
        '${files[logical(root)]}\n'
        'Widget buildExample() => '
        '${source(root).text.substring(builder.offset, builder.end)};\n';
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

/// The part of [blocks] a reader edits: from the first line of code to the
/// end of the last, skipping blocks that only hold import directives. [block]
/// picks one block instead, for a region whose blocks surround other views.
Block regionView(String content, List<Block> blocks, int? block, String where) {
  bool directivesOnly(Block b) => content
      .substring(b.start, b.end)
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .every((line) => line.startsWith('import ') || line.startsWith('export '));
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
  for (final item in config.entries) {
    final builder =
        visitor.entries[item.key] ??
        (throw StateError('guide_projects.json: no registry example ${item.key}'));
    final project = Project()
      ..include(root, {
        ...names(builder),
        'themedExampleRoot',
        'DocsExampleThemeController',
        'DocsExampleStyle',
      });
    final views = (item.value as List).cast<Map<String, dynamic>>();
    for (final view in views) {
      final file = '$repo/${view['source']}';
      if (!File(file).existsSync()) {
        throw StateError('${item.key}: missing ${view['source']}');
      }
      if (view['declaration'] == null) {
        project.includeWhole(file);
      } else {
        project.include(file, {view['declaration'] as String});
      }
    }
    final files = project.render(root, builder);
    final selections = <Map<String, Object>>[];
    for (var i = 0; i < views.length; i++) {
      final view = views[i];
      final file = logical('$repo/${view['source']}');
      final content = files[file]!;
      final where = '${item.key} view $i (${view['source']})';
      Block range;
      if (view['region'] case final String region) {
        final blocks = project.regions[file]?[region] ??
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
    final bytes = files.values.fold<int>(
      0,
      (n, s) => n + utf8.encode(s).length,
    );
    if (bytes > maxBytes || files.length > maxFiles) {
      throw StateError(
        '${item.key}: $bytes bytes in ${files.length} files exceeds the '
        "compiler's $maxBytes bytes / $maxFiles files",
      );
    }
    for (final a in selections) {
      for (final b in selections) {
        if (!identical(a, b) &&
            a['file'] == b['file'] &&
            (a['start'] as int) < (b['end'] as int) &&
            (b['start'] as int) < (a['end'] as int)) {
          throw StateError('${item.key}: views overlap');
        }
      }
    }
    out[item.key] = {'id': item.key, 'files': files, 'views': selections};
  }
  File(
    '../src/guide_projects.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(out)}\n');
  stdout.writeln('Generated ${out.length} runnable guide projects.');
}
