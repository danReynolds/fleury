// Debug tooling is on for development runs and off for compiled code.
//
// The default used to be `!dart.vm.product`: on for every JIT run. An app
// installed with `dart pub global activate` runs on the JIT VM from a
// snapshot, so its end users got the Ctrl+G debug shell, F12 logs, and event
// collection. Now a null DebugConfig.enabled means: on when the Dart VM runs
// the app's `.dart` source entrypoint (the rule hot-reload supervision uses)
// or assertions are enabled, off otherwise; an explicit value always wins.

import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/debug/debug_state.dart' show debugToolingEnabled;
import 'package:test/test.dart';

void main() {
  group('debugToolingEnabled — the one rule behind DebugConfig.enabled', () {
    bool resolve(
      bool? enabled, {
      required bool runsFromSource,
      required bool assertions,
    }) => debugToolingEnabled(
      DebugConfig(enabled: enabled),
      runsFromSource: runsFromSource,
      assertionsEnabled: assertions,
    );

    test('a development run gets it: source entrypoint or assertions', () {
      expect(resolve(null, runsFromSource: true, assertions: false), isTrue);
      expect(resolve(null, runsFromSource: false, assertions: true), isTrue);
      expect(resolve(null, runsFromSource: true, assertions: true), isTrue);
    });

    test('compiled code without assertions does not', () {
      expect(resolve(null, runsFromSource: false, assertions: false), isFalse);
    });

    test('an explicit value always wins', () {
      for (final runsFromSource in [true, false]) {
        for (final assertions in [true, false]) {
          expect(
            resolve(
              true,
              runsFromSource: runsFromSource,
              assertions: assertions,
            ),
            isTrue,
          );
          expect(
            resolve(
              false,
              runsFromSource: runsFromSource,
              assertions: assertions,
            ),
            isFalse,
          );
        }
      }
    });
  });

  test('DebugConfig defers to the launch; a controller resolves it once', () {
    // Constructing via package:fleury/fleury.dart is itself the export
    // assertion for DebugConfig.
    expect(const DebugConfig().enabled, isNull);
    // Tests run with assertions enabled, and a browser host has no source
    // entrypoint to report: its default is the assertion half of the rule.
    final byDefault = DebugController(const DebugConfig());
    final optedOut = DebugController(const DebugConfig(enabled: false));
    addTearDown(byDefault.dispose);
    addTearDown(optedOut.dispose);
    expect(byDefault.enabled, isTrue);
    expect(optedOut.enabled, isFalse);
  });

  group(
    'runApp resolves the default from how the process was launched',
    () {
      late Directory temp;
      late String fixture;
      late String snapshot;

      setUpAll(() async {
        temp = Directory.systemTemp.createTempSync('fleury_debug_default_');
        fixture =
            '${Directory.current.path}/test/fixtures/debug_default_fixture.dart';
        // A kernel snapshot run on the JIT VM without assertions is what
        // `dart pub global activate` installs and `dart run <package>:<exe>`
        // runs: not product mode, so the old default left debug tooling on.
        snapshot = '${temp.path}/debug_default_fixture.dill';
        final compiled = await Process.run(Platform.resolvedExecutable, [
          '--snapshot=$snapshot',
          '--snapshot-kind=kernel',
          fixture,
        ]);
        expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
      });

      tearDownAll(() => temp.deleteSync(recursive: true));

      Future<String> debugTooling(List<String> arguments) async {
        final result = await Process.run(
          Platform.resolvedExecutable,
          arguments,
        );
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        final line = '${result.stdout}'
            .split('\n')
            .firstWhere(
              (line) => line.startsWith('DEBUG_TOOLING='),
              orElse: () => fail('no report in:\n${result.stdout}'),
            );
        return line.substring('DEBUG_TOOLING='.length);
      }

      test('a .dart source entrypoint (dart run, fleury run): on', () async {
        expect(await debugTooling([fixture]), 'on');
      });

      test('a snapshot (pub global activate, dart run pkg:exe): off', () async {
        expect(await debugTooling([snapshot]), 'off');
      });

      test('assertions turn it on for compiled code too', () async {
        expect(await debugTooling(['--enable-asserts', snapshot]), 'on');
      });

      test('an explicit DebugConfig.enabled wins over the launch', () async {
        expect(await debugTooling([fixture, 'off']), 'off');
        expect(await debugTooling([snapshot, 'on']), 'on');
      });
      // Each source launch compiles the framework on the JIT VM: seconds when
      // idle, far longer on a loaded machine.
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
