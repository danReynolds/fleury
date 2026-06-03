import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('terminal extension points are intentionally public', () {
    final core = File('lib/fleury_core.dart').readAsStringSync();
    final native = File('lib/fleury.dart').readAsStringSync();

    for (final symbol in <String>[
      'TerminalDriver',
      'TerminalHandoffDriver',
      'TerminalMode',
      'TerminalProbeTransport',
      'runTerminalProbeSuite',
      'InputParser',
      'TuiEventSink',
      'FakeTerminalDriver',
    ]) {
      expect(
        core,
        contains(symbol),
        reason: '$symbol is part of the launch extension/testing surface.',
      );
    }

    for (final symbol in <String>[
      'createNativeTerminalDriver',
      'PosixTerminalDriver',
      'WindowsTerminalDriver',
      'runTui',
    ]) {
      expect(
        native,
        contains(symbol),
        reason: '$symbol is part of the native terminal launch surface.',
      );
    }
  });

  test(
    'terminal implementation internals stay out of production libraries',
    () {
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
          text,
          isNot(contains('createNativeTerminalDriverForPlatform')),
          reason:
              '$path must not expose the platform-selector test hook as public '
              'native API.',
        );
        expect(
          text,
          isNot(contains('WindowsConsoleModeController')),
          reason:
              '$path must not expose Windows console-mode controller injection '
              'as public API.',
        );
        expect(
          text,
          isNot(contains('WindowsConsoleModePlan')),
          reason: '$path must keep Windows bit planning test-owned.',
        );
        expect(
          text,
          isNot(contains('planWindowsConsoleModes')),
          reason: '$path must not freeze Windows FFI planner internals.',
        );
        expect(
          text,
          isNot(contains('NativeWindowsConsoleModeController')),
          reason: '$path must keep the native FFI adapter private.',
        );
        expect(
          exportLines,
          isNot(contains('terminal_sequences.dart')),
          reason:
              '$path must not expose raw terminal enter/exit sequence builders '
              'as production API.',
        );
      }
    },
  );

  test('Windows driver constructor does not expose controller injection', () {
    final source = File(
      'lib/src/terminal/windows_driver.dart',
    ).readAsStringSync();
    final constructorStart = source.indexOf('WindowsTerminalDriver({');
    final constructorEnd = source.indexOf('}) :', constructorStart);

    expect(constructorStart, isNonNegative);
    expect(constructorEnd, isNonNegative);

    final constructor = source.substring(constructorStart, constructorEnd);
    expect(constructor, isNot(contains('consoleModeController')));

    expect(source, contains('WindowsConsoleModeController'));
    expect(source, contains('planWindowsConsoleModes'));
  });
}
