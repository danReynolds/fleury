import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

/// Extracts API metadata for public classes in `fleury_widgets` and Fleury's
/// core widget and app libraries by parsing their source (no resolution
/// needed).
///
/// Each class records all of its public constructors and their parameters. The
/// top-level `params` member remains as a compatibility view of the unnamed
/// constructor (or the first public named constructor when there is no unnamed
/// constructor).
///
/// Constructor and parameter `doc`s are the complete doc comment as Markdown,
/// paragraphs and all; a class's `doc` is only its first paragraph, on one
/// line, and `classDoc` is the complete comment.
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
    // FleuryApp, and the command and status shell it installs.
    ('../../packages/fleury/lib/src/app', 'packages/fleury/lib/src/app'),
  ];
  final result = <String, Object?>{};
  final sourceFiles = <(File, String)>[
    for (final (dirPath, repoPrefix) in sources)
      ...findApiSourceFiles(Directory(dirPath), repoPrefix),
  ];
  final texts = <String>[
    for (final (file, _) in sourceFiles) file.readAsStringSync(),
  ];
  final index = ApiSourceIndex(texts);

  for (var i = 0; i < sourceFiles.length; i++) {
    final extracted = extractApiFromSource(
      texts[i],
      file: sourceFiles[i].$2,
      index: index,
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

/// Every class declaration across the scanned sources, so a parameter can be
/// resolved through its superclass chain even when the superclass lives in
/// another file.
final class ApiSourceIndex {
  ApiSourceIndex(Iterable<String> sources) {
    for (final source in sources) {
      final unit = parseString(content: source, throwIfDiagnostics: false).unit;
      for (final declaration
          in unit.declarations.whereType<ClassDeclaration>()) {
        _declarations.putIfAbsent(declaration.name.lexeme, () => declaration);
      }
    }
    _widgetClasses = _frameworkWidgetClasses(_declarations.values);
  }

  final _declarations = <String, ClassDeclaration>{};
  late final Set<String> _widgetClasses;
  final _fields = <String, Map<String, _Field>>{};
  final _resolving = <String>{};

  ClassDeclaration? declaration(String className) => _declarations[className];

  /// Whether [className] is a widget, so its `key` parameter is framework
  /// identity rather than API.
  bool isWidget(String className) => _widgetClasses.contains(className);

  /// The fields [className] declares or inherits, by name.
  Map<String, _Field> fields(String className) {
    final existing = _fields[className];
    if (existing != null) return existing;
    if (!_resolving.add(className)) return const <String, _Field>{};
    final declaration = _declarations[className];
    final parent = _baseTypeName(
      declaration?.extendsClause?.superclass.toSource(),
    );
    final fields = <String, _Field>{if (parent != null) ...this.fields(parent)};
    for (final member
        in declaration?.members.whereType<FieldDeclaration>() ??
            const <FieldDeclaration>[]) {
      final type = member.fields.type?.toSource() ?? 'dynamic';
      final doc = _docLines(member.documentationComment);
      for (final variable in member.fields.variables) {
        fields[variable.name.lexeme] = _Field(type, doc);
      }
    }
    _resolving.remove(className);
    return _fields[className] = fields;
  }
}

/// A field's declared type and its raw doc lines (Dartdoc references intact).
final class _Field {
  const _Field(this.type, this.doc);

  final String type;
  final List<String>? doc;
}

/// One constructor parameter as a reader of that constructor sees it.
final class _Parameter {
  const _Parameter({
    required this.type,
    required this.defaultValue,
    required this.doc,
  });

  final String type;
  final String? defaultValue;

  /// Raw doc lines, Dartdoc references intact.
  final List<String>? doc;
}

/// Extracts the API entries declared in one Dart source file.
///
/// This is public so the extractor's schema and constructor handling can be
/// regression-tested without invoking a subprocess or touching generated
/// files. [index] resolves superclasses declared in other files; it defaults
/// to this file alone.
Map<String, Object?> extractApiFromSource(
  String source, {
  required String file,
  ApiSourceIndex? index,
}) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  final result = <String, Object?>{};
  final classes = index ?? ApiSourceIndex(<String>[source]);

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
          'doc': _markdown(_docLines(constructor.documentationComment)),
          'params': _params(declaration, constructor, classes),
          'line': parsed.lineInfo
              .getLocation(constructor.returnType.offset)
              .lineNumber,
        });
      }
    }

    final primary = _primaryPublicConstructor(publicConstructors);
    final legacyParams = primary == null
        ? <Map<String, Object?>>[]
        : _params(declaration, primary, classes);
    result[className] = <String, Object?>{
      'doc': _firstParagraph(_docLines(declaration.documentationComment)),
      'classDoc': _markdown(_docLines(declaration.documentationComment)),
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
  ApiSourceIndex index,
) {
  final out = <Map<String, Object?>>[];
  for (final parameter in ctor.parameters.parameters) {
    final name = parameter.name?.lexeme ?? '';
    if (name.isEmpty) continue;
    final normal = parameter is DefaultFormalParameter
        ? parameter.parameter
        : parameter;
    final resolved = _resolveParameter(cls, ctor, parameter, index, <String>{});
    if (_isFrameworkIdentityKey(cls, name, normal, resolved.type, index)) {
      continue;
    }
    out.add(<String, Object?>{
      'name': name,
      'type': resolved.type,
      'required': parameter.isRequired,
      'named': parameter.isNamed,
      'default': resolved.defaultValue,
      'doc': _markdown(resolved.doc),
    });
  }
  return out;
}

/// Resolves what a reader of [ctor] needs to know about [parameter]: its type,
/// its default, and its doc.
///
/// A parameter's own declaration wins. A `super.x` parameter then takes
/// whatever it leaves out from the superclass constructor parameter it
/// forwards to (following further `super.x` hops), so `Expanded({required
/// super.child})` reads Flexible's `required Widget super.child` rather than
/// the nullable field it is stored in. Last comes the field that stores the
/// value, whose doc covers every constructor: sentences about another
/// constructor are dropped from it (see [_forConstructor]).
_Parameter _resolveParameter(
  ClassDeclaration cls,
  ConstructorDeclaration ctor,
  FormalParameter parameter,
  ApiSourceIndex index,
  Set<String> seen,
) {
  final name = parameter.name?.lexeme ?? '';
  final normal = parameter is DefaultFormalParameter
      ? parameter.parameter
      : parameter;
  var type = _explicitType(normal);
  var defaultValue = parameter is DefaultFormalParameter
      ? parameter.defaultValue?.toSource()
      : null;
  var doc = normal is NormalFormalParameter
      ? _formalParameterDocLines(parameter, normal)
      : null;

  if (normal is SuperFormalParameter &&
      (type == null || defaultValue == null || doc == null)) {
    final forwarded = _superParameter(cls, ctor, parameter, index);
    if (forwarded != null) {
      final (superClass, superCtor, superParameter) = forwarded;
      final key = '${superClass.name.lexeme}.${superCtor.name?.lexeme}.$name';
      if (seen.add(key)) {
        final inherited = _resolveParameter(
          superClass,
          superCtor,
          superParameter,
          index,
          seen,
        );
        // An explicitly required super parameter may still inherit a
        // default declared for the optional parameter it forwards to; that
        // default never applies, so don't report it.
        type ??= inherited.type;
        defaultValue ??= parameter.isRequired ? null : inherited.defaultValue;
        doc ??= inherited.doc;
      }
    }
  }

  final field = index.fields(cls.name.lexeme)[name];
  return _Parameter(
    type: type ?? field?.type ?? 'dynamic',
    defaultValue: defaultValue,
    doc: doc ?? _forConstructor(field?.doc, cls, ctor),
  );
}

/// The superclass constructor parameter a `super.x` [parameter] of [ctor]
/// forwards to: the same-named parameter for a named one, the one at the same
/// position among the positionals otherwise.
(ClassDeclaration, ConstructorDeclaration, FormalParameter)? _superParameter(
  ClassDeclaration cls,
  ConstructorDeclaration ctor,
  FormalParameter parameter,
  ApiSourceIndex index,
) {
  final superName = _baseTypeName(cls.extendsClause?.superclass.toSource());
  final superClass = superName == null ? null : index.declaration(superName);
  if (superClass == null) return null;
  final invocation = ctor.initializers
      .whereType<SuperConstructorInvocation>()
      .firstOrNull;
  final constructorName = invocation?.constructorName?.name;
  final superCtor = superClass.members
      .whereType<ConstructorDeclaration>()
      .where((candidate) => candidate.name?.lexeme == constructorName)
      .firstOrNull;
  if (superCtor == null) return null;
  final superParameters = superCtor.parameters.parameters;
  if (parameter.isNamed) {
    final match = superParameters
        .where(
          (candidate) =>
              candidate.isNamed &&
              candidate.name?.lexeme == parameter.name?.lexeme,
        )
        .firstOrNull;
    return match == null ? null : (superClass, superCtor, match);
  }
  final position = ctor.parameters.parameters
      .where((candidate) => candidate.isPositional)
      .toList()
      .indexOf(parameter);
  final positionals = superParameters
      .where((candidate) => candidate.isPositional)
      .toList();
  return position < 0 || position >= positionals.length
      ? null
      : (superClass, superCtor, positionals[position]);
}

bool _isFrameworkIdentityKey(
  ClassDeclaration cls,
  String name,
  FormalParameter parameter,
  String type,
  ApiSourceIndex index,
) =>
    name == 'key' &&
    index.isWidget(cls.name.lexeme) &&
    (parameter is SuperFormalParameter || type == 'Key' || type == 'Key?');

Set<String> _frameworkWidgetClasses(Iterable<ClassDeclaration> declarations) {
  final superclasses = <String, String?>{
    for (final declaration in declarations)
      declaration.name.lexeme: _baseTypeName(
        declaration.extendsClause?.superclass.toSource(),
      ),
  };

  final widgets = <String>{
    'Widget',
    'StatelessWidget',
    'StatefulWidget',
    'RenderObjectWidget',
    'LeafRenderObjectWidget',
    'SingleChildRenderObjectWidget',
    'MultiChildRenderObjectWidget',
    'ProxyWidget',
    'Scope',
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

String? _explicitType(FormalParameter parameter) {
  if (parameter is FunctionTypedFormalParameter) {
    final returnType = parameter.returnType?.toSource() ?? 'void';
    final typeParameters = parameter.typeParameters?.toSource() ?? '';
    final nullable = parameter.question == null ? '' : '?';
    return '$returnType Function$typeParameters'
        '${parameter.parameters.toSource()}$nullable';
  }
  return switch (parameter) {
    FieldFormalParameter(:final type) => type?.toSource(),
    SimpleFormalParameter(:final type) => type?.toSource(),
    SuperFormalParameter(:final type) => type?.toSource(),
    _ => null,
  };
}

// ── Doc comments ────────────────────────────────────────────────────────────

/// A `///` doc comment's lines without their comment markers, Dartdoc
/// references intact; null when there is no comment or it is blank.
List<String>? _docLines(Comment? comment) => comment == null
    ? null
    : _linesFromLexemes(comment.tokens.map((t) => t.lexeme));

List<String>? _linesFromLexemes(Iterable<String> lexemes) {
  final lines = <String>[
    for (final lexeme in lexemes)
      if (lexeme.startsWith('///'))
        (lexeme.length > 3 && lexeme[3] == ' '
                ? lexeme.substring(4)
                : lexeme.substring(3))
            .trimRight(),
  ];
  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  return lines.isEmpty ? null : lines;
}

List<String>? _formalParameterDocLines(
  FormalParameter outer,
  NormalFormalParameter normal,
) {
  final attached = _docLines(normal.documentationComment);
  if (attached != null) return attached;

  // Analyzer currently leaves comments inside a formal parameter list on the
  // parameter's first token instead of always materializing a [Comment] node.
  // Read that token trivia as the parameter's own docs, but ignore ordinary
  // implementation comments.
  final lexemes = <String>[];
  Token? comment = outer.beginToken.precedingComments;
  while (comment is CommentToken) {
    lexemes.add(comment.lexeme);
    comment = comment.next;
  }
  return _linesFromLexemes(lexemes);
}

/// The complete doc comment as Markdown, preserving paragraphs and fenced
/// code. Dartdoc `[Name]` references become inline code (we have no API site
/// to link to yet).
String? _markdown(List<String>? lines) =>
    lines == null ? null : _normalizeDartdocReferences(lines.join('\n').trim());

/// First paragraph of a doc comment, collapsed to one line.
String? _firstParagraph(List<String>? lines) {
  if (lines == null) return null;
  final buffer = <String>[];
  for (final line in lines) {
    if (line.trim().isEmpty) break;
    if (_markdownFenceOpening(line, 0, line.length) != null) break;
    buffer.add(line.trim());
  }
  final text = buffer.join(' ').trim();
  return text.isEmpty ? null : _normalizeDartdocReferences(text);
}

/// A field's doc, as the doc of the [ctor] parameter that initializes it.
///
/// A field's doc describes the field under every constructor, so it can say
/// "mutually exclusive with [children]" or "null for [MarkdownView.document]".
/// In a table of one constructor's parameters that is noise at best, and it
/// contradicts the table at worst. This keeps the field's doc but drops each
/// sentence (or `;` clause) of a prose paragraph that names another public
/// constructor of [cls], or a parameter only another constructor takes,
/// without naming [ctor] itself: "[Container.filled] and [Container.framed]
/// fill with the theme's surface instead" stays in both of their tables and
/// leaves `Container`'s. A doc left with nothing is returned unchanged.
List<String>? _forConstructor(
  List<String>? lines,
  ClassDeclaration cls,
  ConstructorDeclaration ctor,
) {
  if (lines == null) return null;
  final className = cls.name.lexeme;
  final constructors = cls.members
      .whereType<ConstructorDeclaration>()
      .where(_isPublicConstructor)
      .toList();
  String reference(ConstructorDeclaration c) =>
      '$className.${c.name?.lexeme ?? 'new'}';
  final ownParameters = {
    for (final p in ctor.parameters.parameters) ?p.name?.lexeme,
  };
  final foreign = <String>{
    for (final other in constructors)
      if (!identical(other, ctor)) ...[
        reference(other),
        for (final p in other.parameters.parameters)
          if (p.name?.lexeme case final name?
              when !ownParameters.contains(name))
            name,
      ],
  };
  if (foreign.isEmpty) return lines;
  final own = reference(ctor);
  bool namesForeign(String unit) {
    final names = _references(unit).toSet();
    return names.any(foreign.contains) && !names.contains(own);
  }

  final out = <String>[];
  var changed = false;
  for (final paragraph in _paragraphs(lines)) {
    if (!_isProse(paragraph) || !paragraph.any(namesForeign)) {
      if (out.isNotEmpty) out.add('');
      out.addAll(paragraph);
      continue;
    }
    final units = _sentences(paragraph.map((line) => line.trim()).join(' '));
    final kept = units.where((unit) => !namesForeign(unit)).toList();
    changed = true;
    if (kept.isEmpty) continue;
    var text = kept.join(' ').trim();
    // A kept clause that ended in `;` now ends the paragraph.
    if (text.endsWith(';')) text = '${text.substring(0, text.length - 1)}.';
    text = text[0].toUpperCase() + text.substring(1);
    if (out.isNotEmpty) out.add('');
    out.add(text);
  }
  return !changed || out.isEmpty ? lines : out;
}

Iterable<List<String>> _paragraphs(List<String> lines) sync* {
  var current = <String>[];
  String? fence;
  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (fence == null &&
        (trimmed.startsWith('```') || trimmed.startsWith('~~~'))) {
      fence = trimmed.substring(0, 3);
    } else if (fence != null && trimmed.startsWith(fence)) {
      fence = null;
    }
    if (fence == null && line.trim().isEmpty) {
      if (current.isNotEmpty) yield current;
      current = <String>[];
    } else {
      current.add(line);
    }
  }
  if (current.isNotEmpty) yield current;
}

/// Whether [paragraph] is plain prose, rather than a list, quote, table,
/// heading, or code block, which are left exactly as written.
bool _isProse(List<String> paragraph) => paragraph.every((line) {
  final trimmed = line.trimLeft();
  return !(line.startsWith('    ') ||
      trimmed.startsWith('```') ||
      trimmed.startsWith('~~~') ||
      trimmed.startsWith('>') ||
      trimmed.startsWith('|') ||
      trimmed.startsWith('#') ||
      RegExp(r'^([-*+]|\d+[.)])\s').hasMatch(trimmed));
});

/// Splits prose into sentences and `;` clauses, each keeping its closing
/// punctuation. Code spans, references, and parentheses never split, nor do
/// the abbreviations prose uses mid-sentence.
List<String> _sentences(String text) {
  const abbreviations = ['e.g.', 'i.e.', 'etc.', 'vs.', 'cf.'];
  final units = <String>[];
  var start = 0;
  var depth = 0;
  var inCode = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '`') {
      inCode = !inCode;
      continue;
    }
    if (inCode) continue;
    if (c == '(' || c == '[') depth++;
    if ((c == ')' || c == ']') && depth > 0) depth--;
    if (depth > 0 || !'.!?;'.contains(c)) continue;
    if (i + 1 < text.length && text[i + 1] != ' ') continue;
    final unit = text.substring(start, i + 1);
    if (c == '.' && abbreviations.any(unit.endsWith)) continue;
    units.add(unit.trim());
    start = i + 1;
  }
  final rest = text.substring(start).trim();
  if (rest.isNotEmpty) units.add(rest);
  return units;
}

/// The Dartdoc references (`[name]`) and whole code spans (`` `name` ``) in
/// [text]: the ways a doc names a parameter or constructor.
Iterable<String> _references(String text) sync* {
  for (final match in RegExp(
    r'\[([A-Za-z_][\w.]*)\](?!\()|`([A-Za-z_][\w.]*)`',
  ).allMatches(text)) {
    yield (match[1] ?? match[2])!;
  }
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
