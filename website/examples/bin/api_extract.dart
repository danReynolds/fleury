import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

/// Extracts API metadata for public classes in `fleury_widgets` and Fleury's
/// core widget library by parsing their source (no resolution needed).
///
/// Each class records all of its public constructors and their parameters. The
/// top-level `params` member remains as a compatibility view of the unnamed
/// constructor (or the first public named constructor when there is no unnamed
/// constructor).
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
  final sourceFiles = <(File, String)>[
    for (final (dirPath, repoPrefix) in sources)
      ...findApiSourceFiles(Directory(dirPath), repoPrefix),
  ];
  final frameworkWidgetClasses = _frameworkWidgetClasses(
    sourceFiles.map((source) => source.$1.readAsStringSync()),
  );
  final classFields = _classFields(
    sourceFiles.map((source) => source.$1.readAsStringSync()),
  );

  for (final (entity, file) in sourceFiles) {
    final extracted = extractApiFromSource(
      entity.readAsStringSync(),
      file: file,
      frameworkWidgetClasses: frameworkWidgetClasses,
      classFields: classFields,
    );
    for (final entry in extracted.entries) {
      // The first source directory wins on the unlikely event of a clash.
      result.putIfAbsent(entry.key, () => entry.value);
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

/// Finds Dart API sources recursively and pairs each with its repository path.
///
/// Sorting by path makes the generated JSON deterministic across file systems.
List<(File, String)> findApiSourceFiles(
  Directory sourceDirectory,
  String repoPrefix,
) {
  final files =
      sourceDirectory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final sourcePath = sourceDirectory.absolute.uri.path;
  final prefix = repoPrefix.endsWith('/')
      ? repoPrefix.substring(0, repoPrefix.length - 1)
      : repoPrefix;

  return [
    for (final file in files)
      (file, '$prefix/${file.absolute.uri.path.substring(sourcePath.length)}'),
  ];
}

/// Extracts the API entries declared in one Dart source file.
///
/// This is public so the extractor's schema and constructor handling can be
/// regression-tested without invoking a subprocess or touching generated
/// files.
Map<String, Object?> extractApiFromSource(
  String source, {
  required String file,
  Set<String>? frameworkWidgetClasses,
  Map<String, Map<String, (String, String?)>>? classFields,
}) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  final result = <String, Object?>{};
  final widgetClasses =
      frameworkWidgetClasses ?? _frameworkWidgetClasses(<String>[source]);
  final fields = classFields ?? _classFields(<String>[source]);

  for (final declaration in parsed.unit.declarations) {
    if (declaration is! ClassDeclaration) continue;
    final className = declaration.name.lexeme;
    if (className.startsWith('_')) continue;

    final declaredConstructors = declaration.members
        .whereType<ConstructorDeclaration>()
        .toList();
    final publicConstructors = declaredConstructors
        .where(_isPublicConstructor)
        .toList();
    final constructors = <Map<String, Object?>>[];

    if (declaredConstructors.isEmpty) {
      // Dart supplies an implicit public unnamed constructor. Representing it
      // keeps parameterless concrete classes visible to API-coverage checks.
      constructors.add(<String, Object?>{
        'name': className,
        'doc': null,
        'params': <Map<String, Object?>>[],
        'line': parsed.lineInfo.getLocation(declaration.name.offset).lineNumber,
      });
    } else {
      for (final constructor in publicConstructors) {
        constructors.add(<String, Object?>{
          'name': _constructorName(className, constructor),
          'doc': _docText(constructor.documentationComment),
          'params': _params(declaration, constructor, widgetClasses, fields),
          'line': parsed.lineInfo
              .getLocation(constructor.returnType.offset)
              .lineNumber,
        });
      }
    }

    final primary = _primaryPublicConstructor(publicConstructors);
    final legacyParams = primary == null
        ? <Map<String, Object?>>[]
        : _params(declaration, primary, widgetClasses, fields);
    result[className] = <String, Object?>{
      'doc': _docText(declaration.documentationComment),
      'classDoc': _docMarkdown(declaration.documentationComment),
      'params': legacyParams,
      'constructors': constructors,
      'abstract': declaration.abstractKeyword != null,
      'extends': declaration.extendsClause?.superclass.toSource(),
      'file': file,
      'line': parsed.lineInfo.getLocation(declaration.name.offset).lineNumber,
    };
  }

  return result;
}

bool _isPublicConstructor(ConstructorDeclaration constructor) =>
    constructor.name == null || !constructor.name!.lexeme.startsWith('_');

ConstructorDeclaration? _primaryPublicConstructor(
  List<ConstructorDeclaration> constructors,
) {
  for (final constructor in constructors) {
    if (constructor.name == null) return constructor;
  }
  return constructors.firstOrNull;
}

String _constructorName(String className, ConstructorDeclaration constructor) {
  final suffix = constructor.name?.lexeme;
  return suffix == null ? className : '$className.$suffix';
}

List<Map<String, Object?>> _params(
  ClassDeclaration cls,
  ConstructorDeclaration ctor,
  Set<String> frameworkWidgetClasses,
  Map<String, Map<String, (String, String?)>> classFields,
) {
  final out = <Map<String, Object?>>[];
  for (final parameter in ctor.parameters.parameters) {
    final normal = parameter is DefaultFormalParameter
        ? parameter.parameter
        : parameter;
    final name = parameter.name?.lexeme ?? '';
    if (name.isEmpty) continue;

    final field = classFields[cls.name.lexeme]?[name];
    final type = _parameterType(normal, field);
    if (_isFrameworkIdentityKey(
      cls,
      name,
      normal,
      type,
      frameworkWidgetClasses,
    )) {
      continue;
    }
    final ownDoc = normal is NormalFormalParameter
        ? _formalParameterDoc(parameter, normal)
        : null;
    out.add(<String, Object?>{
      'name': name,
      'type': type,
      'required': parameter.isRequired,
      'named': parameter.isNamed,
      'default': parameter is DefaultFormalParameter
          ? parameter.defaultValue?.toSource()
          : null,
      'doc': ownDoc ?? field?.$2,
    });
  }
  return out;
}

bool _isFrameworkIdentityKey(
  ClassDeclaration cls,
  String name,
  FormalParameter parameter,
  String type,
  Set<String> frameworkWidgetClasses,
) =>
    name == 'key' &&
    frameworkWidgetClasses.contains(cls.name.lexeme) &&
    (parameter is SuperFormalParameter || type == 'Key' || type == 'Key?');

Set<String> _frameworkWidgetClasses(Iterable<String> sources) {
  final superclasses = <String, String?>{};
  for (final source in sources) {
    final unit = parseString(content: source, throwIfDiagnostics: false).unit;
    for (final declaration in unit.declarations.whereType<ClassDeclaration>()) {
      superclasses[declaration.name.lexeme] = _baseTypeName(
        declaration.extendsClause?.superclass.toSource(),
      );
    }
  }

  final widgets = <String>{
    'Widget',
    'StatelessWidget',
    'StatefulWidget',
    'RenderObjectWidget',
    'LeafRenderObjectWidget',
    'SingleChildRenderObjectWidget',
    'MultiChildRenderObjectWidget',
    'ProxyWidget',
    'InheritedWidget',
  };
  var changed = true;
  while (changed) {
    changed = false;
    for (final entry in superclasses.entries) {
      if (entry.value != null &&
          widgets.contains(entry.value) &&
          widgets.add(entry.key)) {
        changed = true;
      }
    }
  }
  return widgets;
}

String? _baseTypeName(String? type) {
  if (type == null) return null;
  final unqualified = type.split('.').last;
  final genericStart = unqualified.indexOf('<');
  return genericStart == -1
      ? unqualified
      : unqualified.substring(0, genericStart);
}

Map<String, Map<String, (String, String?)>> _classFields(
  Iterable<String> sources,
) {
  final declarations = <String, ClassDeclaration>{};
  for (final source in sources) {
    final unit = parseString(content: source, throwIfDiagnostics: false).unit;
    for (final declaration in unit.declarations.whereType<ClassDeclaration>()) {
      declarations.putIfAbsent(declaration.name.lexeme, () => declaration);
    }
  }

  final resolved = <String, Map<String, (String, String?)>>{};
  Map<String, (String, String?)> resolve(String className, Set<String> seen) {
    final existing = resolved[className];
    if (existing != null) return existing;
    if (!seen.add(className)) return const <String, (String, String?)>{};

    final declaration = declarations[className];
    if (declaration == null) return const <String, (String, String?)>{};
    final parentName = _baseTypeName(
      declaration.extendsClause?.superclass.toSource(),
    );
    final fields = <String, (String, String?)>{
      if (parentName != null) ...resolve(parentName, seen),
    };
    for (final member in declaration.members.whereType<FieldDeclaration>()) {
      final type = member.fields.type?.toSource() ?? 'dynamic';
      final doc = _docText(member.documentationComment);
      for (final variable in member.fields.variables) {
        fields[variable.name.lexeme] = (type, doc);
      }
    }
    seen.remove(className);
    resolved[className] = fields;
    return fields;
  }

  for (final className in declarations.keys) {
    resolve(className, <String>{});
  }
  return resolved;
}

String? _formalParameterDoc(
  FormalParameter outer,
  NormalFormalParameter normal,
) {
  final attached = _docText(normal.documentationComment);
  if (attached != null) return attached;

  // Analyzer currently leaves comments inside a formal parameter list on the
  // parameter's first token instead of always materializing a [Comment] node.
  // Read that token trivia as the parameter's own docs, but ignore ordinary
  // implementation comments.
  final lines = <String>[];
  Token? comment = outer.beginToken.precedingComments;
  while (comment is CommentToken) {
    final lexeme = comment.lexeme;
    if (lexeme.startsWith('///')) lines.add(lexeme);
    comment = comment.next;
  }
  return _docTextFromLexemes(lines);
}

String _parameterType(FormalParameter parameter, (String, String?)? field) {
  if (parameter is FunctionTypedFormalParameter) {
    final returnType = parameter.returnType?.toSource() ?? 'void';
    final typeParameters = parameter.typeParameters?.toSource() ?? '';
    final nullable = parameter.question == null ? '' : '?';
    return '$returnType Function$typeParameters'
        '${parameter.parameters.toSource()}$nullable';
  }

  TypeAnnotation? explicitType;
  if (parameter is FieldFormalParameter) {
    explicitType = parameter.type;
  } else if (parameter is SimpleFormalParameter) {
    explicitType = parameter.type;
  } else if (parameter is SuperFormalParameter) {
    explicitType = parameter.type;
  }
  return explicitType?.toSource() ?? field?.$1 ?? 'dynamic';
}

/// The full `///` doc comment as Markdown, preserving paragraphs and fenced
/// code. Dartdoc `[Name]` references become inline code (we have no API site to
/// link to yet).
String? _docMarkdown(Comment? comment) {
  if (comment == null) return null;
  final lines = comment.tokens.map((token) {
    var text = token.lexeme;
    if (text.startsWith('///')) text = text.substring(3);
    if (text.startsWith(' ')) text = text.substring(1);
    return text;
  }).toList();
  final text = lines.join('\n').trim();
  if (text.isEmpty) return null;
  return _normalizeDartdocReferences(text);
}

/// First paragraph of a `///` doc comment, collapsed to one line.
String? _docText(Comment? comment) {
  if (comment == null) return null;
  return _docTextFromLexemes(comment.tokens.map((token) => token.lexeme));
}

String? _docTextFromLexemes(Iterable<String> lexemes) {
  final buffer = <String>[];
  for (final lexeme in lexemes) {
    final line = lexeme.replaceFirst(RegExp(r'^///?\s?'), '').trimRight();
    if (line.trim().isEmpty) {
      if (buffer.isNotEmpty) break; // stop at the first blank line
      continue;
    }
    if (_markdownFenceOpening(line, 0, line.length) != null) break;
    buffer.add(line.trim());
  }
  final text = buffer.join(' ').trim();
  return text.isEmpty ? null : _normalizeDartdocReferences(text);
}

String _normalizeDartdocReferences(String text) {
  final out = StringBuffer();
  var plainStart = 0;
  var lineStart = 0;

  while (lineStart < text.length) {
    final newline = text.indexOf('\n', lineStart);
    final lineEnd = newline == -1 ? text.length : newline;
    final contentEnd =
        lineEnd > lineStart && text.codeUnitAt(lineEnd - 1) == 0x0d
        ? lineEnd - 1
        : lineEnd;
    final opening = _markdownFenceOpening(text, lineStart, contentEnd);

    if (opening == null) {
      lineStart = newline == -1 ? text.length : newline + 1;
      continue;
    }

    final fenceEnd = _findMarkdownFenceEnd(
      text,
      newline == -1 ? text.length : newline + 1,
      opening.$1,
      opening.$2,
    );

    out.write(
      _normalizeInlineDartdocReferences(text.substring(plainStart, lineStart)),
    );
    out.write(text.substring(lineStart, fenceEnd));
    plainStart = fenceEnd;
    lineStart = fenceEnd;
  }

  out.write(_normalizeInlineDartdocReferences(text.substring(plainStart)));
  return out.toString();
}

/// Returns the fence marker and run length for a CommonMark fence opener.
///
/// Fence openers may be indented by up to three spaces and use at least three
/// backticks or tildes. Backtick info strings cannot themselves contain a
/// backtick.
(int, int)? _markdownFenceOpening(String text, int start, int end) {
  var cursor = start;
  while (cursor < end && text.codeUnitAt(cursor) == 0x20) {
    cursor++;
    if (cursor - start > 3) return null;
  }
  if (cursor == end) return null;

  final marker = text.codeUnitAt(cursor);
  if (marker != 0x60 && marker != 0x7e) return null;

  final markerStart = cursor;
  while (cursor < end && text.codeUnitAt(cursor) == marker) {
    cursor++;
  }
  final markerLength = cursor - markerStart;
  if (markerLength < 3) return null;

  if (marker == 0x60) {
    while (cursor < end) {
      if (text.codeUnitAt(cursor) == 0x60) return null;
      cursor++;
    }
  }

  return (marker, markerLength);
}

int _findMarkdownFenceEnd(
  String text,
  int start,
  int marker,
  int openingLength,
) {
  var lineStart = start;
  while (lineStart < text.length) {
    final newline = text.indexOf('\n', lineStart);
    final lineEnd = newline == -1 ? text.length : newline;
    final contentEnd =
        lineEnd > lineStart && text.codeUnitAt(lineEnd - 1) == 0x0d
        ? lineEnd - 1
        : lineEnd;

    if (_isMarkdownFenceClosingLine(
      text,
      lineStart,
      contentEnd,
      marker,
      openingLength,
    )) {
      return newline == -1 ? text.length : newline + 1;
    }

    if (newline == -1) return text.length;
    lineStart = newline + 1;
  }
  return text.length;
}

bool _isMarkdownFenceClosingLine(
  String text,
  int start,
  int end,
  int marker,
  int openingLength,
) {
  var cursor = start;
  while (cursor < end && text.codeUnitAt(cursor) == 0x20) {
    cursor++;
    if (cursor - start > 3) return false;
  }

  final markerStart = cursor;
  while (cursor < end && text.codeUnitAt(cursor) == marker) {
    cursor++;
  }
  if (cursor - markerStart < openingLength) return false;

  while (cursor < end) {
    final character = text.codeUnitAt(cursor);
    if (character != 0x20 && character != 0x09) return false;
    cursor++;
  }
  return true;
}

String _normalizeInlineDartdocReferences(String text) {
  final out = StringBuffer();
  var plainStart = 0;
  var cursor = 0;

  while (cursor < text.length) {
    if (text.codeUnitAt(cursor) != 0x60) {
      cursor++;
      continue;
    }

    final openingEnd = _backtickRunEnd(text, cursor);
    final delimiterLength = openingEnd - cursor;
    final closingStart = _findClosingBacktickRun(
      text,
      openingEnd,
      delimiterLength,
    );
    if (closingStart == null) {
      cursor = openingEnd;
      continue;
    }

    out.write(
      _normalizePlainDartdocReferences(text.substring(plainStart, cursor)),
    );
    final closingEnd = closingStart + delimiterLength;
    out.write(text.substring(cursor, closingEnd));
    plainStart = closingEnd;
    cursor = closingEnd;
  }

  out.write(_normalizePlainDartdocReferences(text.substring(plainStart)));
  return out.toString();
}

int _backtickRunEnd(String text, int start) {
  var end = start;
  while (end < text.length && text.codeUnitAt(end) == 0x60) {
    end++;
  }
  return end;
}

int? _findClosingBacktickRun(String text, int start, int delimiterLength) {
  var cursor = start;
  while (cursor < text.length) {
    final runStart = text.indexOf('`', cursor);
    if (runStart == -1) return null;
    final runEnd = _backtickRunEnd(text, runStart);
    if (runEnd - runStart == delimiterLength) return runStart;
    cursor = runEnd;
  }
  return null;
}

String _normalizePlainDartdocReferences(String text) => text.replaceAllMapped(
  RegExp(r'\[([A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*)*)\](?!\()'),
  (match) => '`${match[1]}`',
);
