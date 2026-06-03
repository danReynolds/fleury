import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('key chord dispatcher internals stay out of public libraries', () {
    final productionLibraries = <String>[
      'lib/fleury.dart',
      'lib/fleury_core.dart',
    ];

    for (final path in productionLibraries) {
      final file = File(path);
      final text = file.readAsStringSync();
      final exportLines = file
          .readAsLinesSync()
          .map((line) => line.trimLeft())
          .where((line) => line.startsWith('export '))
          .join('\n');

      expect(
        exportLines,
        isNot(contains(r'$KeyChordInternal')),
        reason:
            '$path must not export dispatcher-only key chord inspection '
            'helpers as production API.',
      );
      expect(
        text,
        isNot(contains('matchesStepAt')),
        reason:
            '$path must not freeze step-by-step chord inspection as public '
            'API before a stable extension contract exists.',
      );
      expect(
        text,
        isNot(contains('isSequence')),
        reason:
            '$path must not expose dispatcher sequence-state helpers as '
            'public API.',
      );
    }

    final keyBindings = File(
      'lib/src/widgets/key_bindings.dart',
    ).readAsStringSync();
    expect(keyBindings, contains(r'extension $KeyChordInternal'));
    expect(keyBindings, contains('Framework-internal'));
  });
}
