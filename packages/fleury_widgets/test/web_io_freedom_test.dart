// Guards the claim in fleury_widgets.dart: everything it reaches compiles
// to a working browser program, free of dart:io and dart:ffi. A successful
// dart2js build does not prove it, because dart2js compiles a dart:io import
// into stubs that only throw once they are called. This walks the imports the
// way a browser build resolves them: a conditional import takes the branch
// whose condition holds on the web, else its default.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Library conditions that hold in a browser build.
const _webLibraries = {
  'dart.library.js_interop',
  'dart.library.js_util',
  'dart.library.html',
};

void main() {
  test(
    'fleury_widgets.dart is transitively free of dart:io and dart:ffi',
    () {
      final packages = _packageLibDirs();
      final offenders = <String>[];
      final visited = <String>{};

      void visit(String path, String from) {
        final normalized = File(path).absolute.uri.normalizePath().toFilePath();
        if (!visited.add(normalized)) return;
        final file = File(normalized);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'missing $normalized ($from)',
        );
        for (final uri in _webResolvedDirectives(file.readAsStringSync())) {
          if (uri == 'dart:io' || uri == 'dart:ffi') {
            offenders.add('$normalized → $uri');
          } else if (uri.startsWith('package:')) {
            final name = uri.substring(8, uri.indexOf('/'));
            // Only first-party sources can hide dart:io; the external
            // dependencies (characters, image, meta) are pure Dart.
            if (name != 'fleury' && name != 'fleury_widgets') continue;
            visit(
              '${packages[name]}/${uri.substring(uri.indexOf('/') + 1)}',
              normalized,
            );
          } else if (!uri.startsWith('dart:')) {
            visit('${File(normalized).parent.path}/$uri', normalized);
          }
        }
      }

      visit('lib/fleury_widgets.dart', 'the web barrel');
      expect(
        offenders,
        isEmpty,
        reason:
            'The web barrel must not reach dart:io or dart:ffi. Take the '
            'platform service as a parameter (as FileBrowser takes a '
            'FileSource) and keep the dart:io implementation behind a '
            'conditional import or the native barrel.',
      );
    },
  );
}

/// The URI each import/export directive resolves to in a browser build.
Iterable<String> _webResolvedDirectives(String source) sync* {
  final directive = RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]((?:\s+if\s*\([^)]*\)\s*['"][^'"]+['"])*)''',
    multiLine: true,
  );
  final configuration = RegExp(
    r'''if\s*\(\s*([\w.]+)(?:\s*==\s*['"]true['"])?\s*\)\s*['"]([^'"]+)['"]''',
  );
  for (final match in directive.allMatches(source)) {
    var uri = match.group(1)!;
    for (final config in configuration.allMatches(match.group(2)!)) {
      if (_webLibraries.contains(config.group(1))) {
        uri = config.group(2)!;
        break;
      }
    }
    yield uri;
  }
}

/// Package name → absolute `lib/` directory, from the package config.
Map<String, String> _packageLibDirs() {
  final config = File('.dart_tool/package_config.json');
  final json = jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
  final base = config.absolute.uri;
  return {
    for (final package
        in (json['packages']! as List).cast<Map<String, Object?>>())
      package['name']! as String: base
          .resolve('${package['rootUri']}/')
          .resolve(package['packageUri']! as String)
          .toFilePath()
          .replaceAll(RegExp(r'/$'), ''),
  };
}
