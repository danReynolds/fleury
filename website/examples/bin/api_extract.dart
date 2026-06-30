import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// Extracts a Properties table for each public widget in `fleury_widgets` by
/// parsing the source (no resolution needed — the AST is version-stable). For
/// each class it records its doc comment and its primary constructor's
/// parameters: name, type, required/default, and the doc comment (pulled from
/// the backing field for `this.x` field-formals). Emits JSON keyed by class
/// name so the docs site can render a table per widget.
///
/// Usage: dart run bin/api_extract.dart [out.json]   (defaults to stdout)
void main(List<String> args) {
  // Scan the high-level widget library AND the framework's core widgets, so the
  // reference can document both. Repo-relative prefix per dir builds the GitHub
  // "view source" link. fleury_widgets is scanned first; on the (unlikely) name
  // clash it wins, preserving existing pages.
  const sources = <(String, String)>[
    (
      '../../packages/fleury_widgets/lib/src',
      'packages/fleury_widgets/lib/src',
    ),
    (
      '../../packages/fleury/lib/src/widgets',
      'packages/fleury/lib/src/widgets',
    ),
  ];
  final result = <String, Object?>{};

  for (final (dirPath, repoPrefix) in sources) {
    for (final entity in Directory(dirPath).listSync()) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final parsed = parseString(
        content: entity.readAsStringSync(),
        throwIfDiagnostics: false,
      );
      final unit = parsed.unit;
      final file = '$repoPrefix/${entity.uri.pathSegments.last}';
      for (final decl in unit.declarations) {
        if (decl is! ClassDeclaration) continue;
        final name = decl.name.lexeme;
        if (name.startsWith('_')) continue;
        if (result.containsKey(name)) continue; // first dir wins on clash
        final ctor = _primaryConstructor(decl);
        if (ctor == null) continue;
        final params = _params(decl, ctor);
        if (params.isEmpty) continue;
        result[name] = <String, Object?>{
          'doc': _docText(decl.documentationComment),
          'classDoc': _docMarkdown(decl.documentationComment),
          'params': params,
          'file': file,
          'line': parsed.lineInfo.getLocation(decl.name.offset).lineNumber,
        };
      }
    }
  }

  final json = const JsonEncoder.withIndent('  ').convert(result);
  if (args.isNotEmpty) {
    File(args.first).writeAsStringSync('$json\n');
    stdout.writeln('extracted ${result.length} classes → ${args.first}');
  } else {
    stdout.write(json);
  }
}

ConstructorDeclaration? _primaryConstructor(ClassDeclaration decl) {
  final ctors = decl.members.whereType<ConstructorDeclaration>().toList();
  for (final c in ctors) {
    if (c.name == null) return c; // the unnamed constructor
  }
  return ctors.isEmpty ? null : ctors.first;
}

List<Map<String, Object?>> _params(
  ClassDeclaration cls,
  ConstructorDeclaration ctor,
) {
  final out = <Map<String, Object?>>[];
  for (final p in ctor.parameters.parameters) {
    final normal = p is DefaultFormalParameter ? p.parameter : p;
    final name = p.name?.lexeme ?? '';
    if (name.isEmpty || name == 'key') continue;
    if (normal is SuperFormalParameter) continue; // super.key etc.

    var type = 'dynamic';
    String? doc;
    final field = _field(cls, name);
    if (normal is FieldFormalParameter) {
      type = field?.$1 ?? 'dynamic';
      doc = field?.$2;
    } else if (normal is SimpleFormalParameter) {
      type = field?.$1 ?? normal.type?.toSource() ?? 'dynamic';
      doc = field?.$2;
    } else if (normal is FunctionTypedFormalParameter) {
      type = '${normal.returnType?.toSource() ?? 'void'} Function(…)';
      doc = field?.$2;
    }

    out.add(<String, Object?>{
      'name': name,
      'type': type,
      'required': p.isRequired,
      'default': p is DefaultFormalParameter
          ? p.defaultValue?.toSource()
          : null,
      'doc': doc,
    });
  }
  return out;
}

/// Returns (type, doc) for the field named [name] on [cls].
(String, String?)? _field(ClassDeclaration cls, String name) {
  for (final m in cls.members) {
    if (m is! FieldDeclaration) continue;
    for (final v in m.fields.variables) {
      if (v.name.lexeme == name) {
        return (
          m.fields.type?.toSource() ?? 'dynamic',
          _docText(m.documentationComment),
        );
      }
    }
  }
  return null;
}

/// The full `///` doc comment as Markdown, preserving paragraphs and fenced
/// code. Dartdoc `[Name]` references become inline code (we have no API site to
/// link to yet).
String? _docMarkdown(Comment? comment) {
  if (comment == null) return null;
  final lines = comment.tokens.map((t) {
    var s = t.lexeme;
    if (s.startsWith('///')) s = s.substring(3);
    if (s.startsWith(' ')) s = s.substring(1);
    return s;
  }).toList();
  var text = lines.join('\n').trim();
  if (text.isEmpty) return null;
  text = text.replaceAllMapped(
    RegExp(r'\[([A-Za-z_][\w]*)\](?!\()'),
    (m) => '`${m[1]}`',
  );
  return text;
}

/// First paragraph of a `///` doc comment, collapsed to one line.
String? _docText(Comment? comment) {
  if (comment == null) return null;
  final buf = <String>[];
  for (final token in comment.tokens) {
    final line = token.lexeme.replaceFirst(RegExp(r'^///?\s?'), '').trimRight();
    if (line.trim().isEmpty) {
      if (buf.isNotEmpty) break; // stop at the first blank line
      continue;
    }
    if (line.trimLeft().startsWith('```')) break;
    buf.add(line.trim());
  }
  final text = buf.join(' ').trim();
  return text.isEmpty ? null : text;
}
