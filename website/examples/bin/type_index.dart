import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// Builds a name -> GitHub-source index of every public type declared in the
/// framework packages, so the docs site can turn the `Type` column of each
/// widget's Properties table into links back to the implementation (the way
/// the Flutter/dartdoc API reference does). Emits JSON keyed by type name.
///
/// Usage: dart run bin/type_index.dart [out.json]   (defaults to stdout)
void main(List<String> args) {
  // (scan root, repo-relative prefix)
  const roots = <(String, String)>[
    ('../../packages/fleury/lib', 'packages/fleury/lib'),
    ('../../packages/fleury_widgets/lib', 'packages/fleury_widgets/lib'),
  ];
  final index = <String, String>{};

  for (final (root, prefix) in roots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = '$prefix${entity.path.substring(root.length)}';
      final parsed = parseString(
        content: entity.readAsStringSync(),
        throwIfDiagnostics: false,
      );
      for (final decl in parsed.unit.declarations) {
        final name = _typeName(decl);
        if (name == null || name.startsWith('_') || index.containsKey(name)) {
          continue;
        }
        final line = parsed.lineInfo.getLocation(decl.offset).lineNumber;
        index[name] = '$rel#L$line';
      }
    }
  }

  final sorted = <String, String>{
    for (final k in index.keys.toList()..sort()) k: index[k]!,
  };
  final json = const JsonEncoder.withIndent('  ').convert(sorted);
  if (args.isNotEmpty) {
    File(args.first).writeAsStringSync('$json\n');
    stdout.writeln('indexed ${sorted.length} types -> ${args.first}');
  } else {
    stdout.write(json);
  }
}

/// The declared name of a public type declaration, or null for non-types.
String? _typeName(CompilationUnitMember decl) => switch (decl) {
      ClassDeclaration d => d.name.lexeme,
      EnumDeclaration d => d.name.lexeme,
      MixinDeclaration d => d.name.lexeme,
      // ignore: experimental_member_use
      ExtensionTypeDeclaration d => d.name.lexeme,
      ClassTypeAlias d => d.name.lexeme,
      TypeAlias d => d.name.lexeme,
      _ => null,
    };
