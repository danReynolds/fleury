// Guards the load-bearing claim in fleury_core.dart / fleury_host.dart:
// everything reachable from the core and host barrels is free of dart:io
// and dart:ffi, so it compiles to the web. The public-api boundary test
// checks WHERE symbols are exported; this checks WHAT those exports drag
// in — the gap that let hot-reload (vm_service) and the process-spawning
// clipboard ship from the "io-free" core.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  for (final barrel in ['lib/fleury_core.dart', 'lib/fleury_host.dart']) {
    test('$barrel is transitively free of dart:io and dart:ffi', () {
      final offenders = <String>[];
      final visited = <String>{};

      void visit(String path) {
        final normalized = File(path).absolute.uri.normalizePath().toFilePath();
        if (!visited.add(normalized)) return;
        final file = File(normalized);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'referenced source file missing: $normalized',
        );
        final source = file.readAsStringSync();
        for (final directive in _directives(source)) {
          if (directive == 'dart:io' || directive == 'dart:ffi') {
            offenders.add('$normalized → $directive');
            continue;
          }
          if (directive.startsWith('dart:')) continue;
          if (directive.startsWith('package:')) {
            // Only fleury's own sources can hide dart:io from us; external
            // packages in the dependency set (characters, meta) are
            // web-safe, and vm_service/ffi only enter via fleury sources,
            // which we do walk.
            if (!directive.startsWith('package:fleury/')) continue;
            visit('lib/${directive.substring('package:fleury/'.length)}');
            continue;
          }
          // Relative import/export.
          final dir = File(normalized).parent.path;
          visit('$dir/$directive');
        }
      }

      visit(barrel);
      expect(
        offenders,
        isEmpty,
        reason:
            'The io-free barrels must not reach dart:io/dart:ffi. Move the '
            'offending code behind the native fleury.dart umbrella.',
      );
    });
  }
}

/// Extracts the URIs of all import/export directives in [source]. A regex is
/// enough here: fleury sources are dart-formatted, and a miss fails toward
/// strictness in review, not silently.
Iterable<String> _directives(String source) sync* {
  final pattern = RegExp(
    '''^\\s*(?:import|export)\\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  for (final m in pattern.allMatches(source)) {
    yield m.group(1)!;
  }
}
