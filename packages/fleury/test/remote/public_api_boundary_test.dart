import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('remote session internals stay out of public libraries', () {
    final publicLibraries = <String>[
      'lib/fleury.dart',
      'lib/fleury_core.dart',
      'lib/fleury_test.dart',
    ];

    for (final path in publicLibraries) {
      final file = File(path);
      final text = file.readAsStringSync();
      final exportLines = file
          .readAsLinesSync()
          .map((line) => line.trimLeft())
          .where((line) => line.startsWith('export '))
          .join('\n');

      expect(
        exportLines,
        isNot(contains('src/remote/')),
        reason:
            '$path must not export remote protocol, transport, or driver '
            'internals before the remote API is intentionally stabilized.',
      );
      expect(
        text,
        isNot(contains('RemoteTerminalDriver')),
        reason:
            '$path should keep remote rendering available through runApp '
            'auto-discovery and the fleury CLI, not through direct driver '
            'construction.',
      );
      expect(
        text,
        isNot(contains('RemoteFrameTransport')),
        reason:
            '$path should not freeze the remote transport interface as public '
            'API during the launch cycle.',
      );
    }

    final nativeUmbrella = File('lib/fleury.dart').readAsStringSync();
    final retiredNativeEntry = 'run${'Tui'}';
    expect(nativeUmbrella, contains('runApp'));
    expect(nativeUmbrella, isNot(contains(retiredNativeEntry)));

    final core = File('lib/fleury_core.dart').readAsStringSync();
    expect(core, contains('TerminalDriver'));
  });
}
