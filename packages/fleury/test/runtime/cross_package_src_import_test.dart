// No sibling package's lib/ may import fleury's src/ internals. The
// public barrels (fleury_core / fleury_host / fleury_host_io / fleury /
// fleury_test_support) are the entire supported surface; a src import is a
// semver-invisible dependency that breaks silently on any internal
// refactor — exactly how fleury_web ended up built on an unexported
// wire codec. Test/tool code in publish_to:none packages is exempt.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  const packages = [
    'fleury_widgets',
    'fleury_test',
    'fleury_web',
    'fleury_mcp',
    'fleury_git',
    'samples',
    'storybook',
    'fleury_example_console',
  ];

  for (final package in packages) {
    test('$package lib/ imports fleury only through its barrels', () {
      final libDir = Directory('../$package/lib');
      expect(
        libDir.existsSync(),
        isTrue,
        reason: 'expected sibling package at ${libDir.absolute.path}',
      );
      final offenders = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        final pattern = RegExp(
          '''^\\s*(?:import|export)\\s+['"]package:fleury/src/''',
          multiLine: true,
        );
        if (pattern.hasMatch(source)) offenders.add(entity.path);
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Import package:fleury/fleury_core.dart (widgets/apps) or '
            'fleury_host.dart / fleury_host_io.dart (hosts). If a genuinely '
            'host-facing symbol is missing from a barrel, promote it with a '
            'show combinator instead of reaching into src/.',
      );
    });
  }
}
