import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('key sequence dispatcher internals stay out of public libraries', () {
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
        isNot(contains(r'$KeySequenceInternal')),
        reason:
            '$path must not export dispatcher-only key sequence inspection '
            'helpers as production API.',
      );
      expect(
        text,
        isNot(contains('matchesStepAt')),
        reason:
            '$path must not freeze step-by-step sequence inspection as public '
            'API before a stable extension contract exists.',
      );
    }

    // The internal step-walking extension lives in events.dart (co-located
    // with the sequence types) and is clearly marked framework-internal.
    final events = File('lib/src/input/events.dart').readAsStringSync();
    expect(events, contains(r'extension $KeySequenceInternal'));
    expect(events, contains('Framework-internal'));
  });
}
