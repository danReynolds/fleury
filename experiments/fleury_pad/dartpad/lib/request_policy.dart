import 'dart:convert';
import 'dart:math';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

/// Checkpoints stay client-side, but only this build's compiler can mint them.
/// The envelope is authenticated, not encrypted; never put secrets in it.
class Checkpoints {
  Checkpoints(this.buildId, List<int> key, {int Function()? now})
    : _mac = Hmac(sha256, key),
      _now = now ?? (() => DateTime.now().millisecondsSinceEpoch ~/ 1000) {
    if (key.length < 32) throw ArgumentError('Checkpoint key needs 32 bytes.');
  }

  static List<int> ephemeralKey() {
    final random = Random.secure();
    return List.generate(32, (_) => random.nextInt(256));
  }

  static const maxKernelLength = 2000000;
  static const maxTokenLength = maxKernelLength + 512;
  static const lifetimeSeconds = 86400;
  final String buildId;
  final Hmac _mac;
  final int Function() _now;

  String seal(String kernel) {
    if (kernel.isEmpty || kernel.length > maxKernelLength) {
      throw const FormatException('Reload checkpoint is too large.');
    }
    base64Decode(kernel);
    final content = 'v1.$buildId.${_now() + lifetimeSeconds}.$kernel';
    return '$content.${base64UrlEncode(_mac.convert(utf8.encode(content)).bytes)}';
  }

  String open(Object? token) {
    const invalid = FormatException(
      'Invalid or expired reload checkpoint. Restart the app.',
    );
    if (token is! String || token.length > maxTokenLength) throw invalid;
    final parts = token.split('.');
    if (parts.length != 5 || parts[0] != 'v1' || parts[1] != buildId)
      throw invalid;
    final expiry = int.tryParse(parts[2]);
    if (expiry == null ||
        expiry <= _now() ||
        expiry > _now() + lifetimeSeconds + 60)
      throw invalid;
    final signature = base64Url.decode(parts[4]);
    final expected = _mac.convert(utf8.encode(parts.take(4).join('.'))).bytes;
    if (signature.length != expected.length) throw invalid;
    var difference = 0;
    for (var i = 0; i < expected.length; i++) {
      difference |= signature[i] ^ expected[i];
    }
    if (difference != 0 ||
        parts[3].isEmpty ||
        parts[3].length > maxKernelLength)
      throw invalid;
    // Authenticate before giving any client-supplied binary data to DDC.
    base64Decode(parts[3]);
    return parts[3];
  }
}

/// Validate every URI, including inactive conditional imports and exports.
/// Projects contain only bounded Dart files; no filesystem, remote, or part sources.
void validateSource(
  String source, {
  String file = 'main.dart',
  Set<String> files = const {},
}) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  for (final directive in unit.directives) {
    if (directive is PartDirective || directive is PartOfDirective) {
      throw const FormatException(
        'Use imports between project files; parts are unavailable.',
      );
    }
    if (directive is UriBasedDirective) {
      _validateUri(directive.uri.stringValue, file, files);
      if (directive is NamespaceDirective) {
        for (final config in directive.configurations) {
          _validateUri(config.uri.stringValue, file, files);
        }
      }
    }
  }
}

void _validateUri(String? value, String file, Set<String> files) {
  if (value == null)
    throw const FormatException('Expected a literal import URI.');
  const libraries = {
    'async',
    'collection',
    'convert',
    'core',
    'math',
    'typed_data',
    'js_interop',
    'js_interop_unsafe',
    'html',
    'svg',
    'web_audio',
    'web_gl',
  };
  if (value.startsWith('dart:') && libraries.contains(value.substring(5)))
    return;
  // Decoded Dart string literals only; reject URI escapes, traversal, queries,
  // authorities and backslashes before the compiler resolves any path.
  if (RegExp(
    r'^package:(fleury|fleury_web|http|image|web)/[a-zA-Z0-9_/\.]*$',
  ).hasMatch(value)) {
    final segments = value.substring(8).split('/');
    if (!segments.contains('..') &&
        !segments.contains('.') &&
        !value.contains('//'))
      return;
  }
  if (RegExp(r'^[a-zA-Z0-9_./-]+\.dart$').hasMatch(value) &&
      !value.startsWith('/') &&
      !value.contains('//')) {
    final target = path.posix.normalize(
      path.posix.join(path.posix.dirname(file), value),
    );
    if (files.contains(target)) return;
  }
  throw const FormatException(
    'Use project files, browser Dart libraries or the bundled fleury, fleury_web, and web packages.',
  );
}

Map<String, dynamic> validatePayload(Object? decoded, String method) {
  if (decoded is! Map<String, dynamic> || decoded['source'] is! String) {
    throw const FormatException('Expected Dart source.');
  }
  final source = decoded['source'] as String;
  final rawFiles = decoded['files'];
  final files = <String, String>{};
  if (rawFiles != null) {
    if (rawFiles is! Map<String, dynamic> ||
        rawFiles.isEmpty ||
        rawFiles.length > 24) {
      throw const FormatException('Expected a project of 1 to 24 Dart files.');
    }
    for (final entry in rawFiles.entries) {
      if (!RegExp(
            r'^[a-zA-Z0-9_-]+(?:/[a-zA-Z0-9_-]+)*\.dart$',
          ).hasMatch(entry.key) ||
          entry.key.length > 160 ||
          entry.key == 'bootstrap.dart' ||
          entry.value is! String) {
        throw const FormatException('Invalid project file name or contents.');
      }
      files[entry.key] = entry.value as String;
    }
    if (files['main.dart'] != source) {
      throw const FormatException('Project main.dart must match source.');
    }
  }
  final project = files.isEmpty ? {'main.dart': source} : files;
  if (project.values.fold<int>(
        0,
        (size, text) => size + utf8.encode(text).length,
      ) >
      64000) {
    throw const FormatException('Expected a project of at most 64 KB.');
  }
  final activeFile = decoded['activeFile'] ?? 'main.dart';
  if (activeFile is! String || !project.containsKey(activeFile)) {
    throw const FormatException('Expected an active file in the project.');
  }
  final offset = decoded['offset'];
  if ((offset != null &&
          (offset is! int ||
              offset < 0 ||
              offset > project[activeFile]!.length)) ||
      ((method == 'complete' || method == 'document') && offset == null)) {
    throw const FormatException(
      'Expected a source offset within the active file.',
    );
  }
  for (final entry in project.entries) {
    validateSource(entry.value, file: entry.key, files: files.keys.toSet());
  }
  // Forward only supported fields, never arbitrary compiler arguments.
  return {
    'source': source,
    if (files.isNotEmpty) 'files': files,
    if (files.isNotEmpty) 'activeFile': activeFile,
    if (offset != null) 'offset': offset,
  };
}
