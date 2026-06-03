import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('test fake public API boundary', () {
    test('production barrels do not export deterministic test fakes', () {
      final productionBarrels = <String>[
        'lib/fleury.dart',
        'lib/fleury_core.dart',
      ];

      for (final path in productionBarrels) {
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('FakeClock')), reason: path);
        expect(source, isNot(contains('FakeTickerScheduler')), reason: path);
        expect(source, isNot(contains('TestClipboard')), reason: path);
      }
    });

    test('fleury_test exposes deterministic test fakes', () {
      final source = File('lib/fleury_test.dart').readAsStringSync();

      expect(source, contains('FakeClock'));
      expect(source, contains('FakeTickerScheduler'));
      expect(source, contains('TestClipboard'));
    });
  });
}
