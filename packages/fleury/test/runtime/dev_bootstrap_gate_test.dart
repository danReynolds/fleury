import 'package:fleury/src/runtime/dev_bootstrap.dart';
import 'package:test/test.dart';

/// `endsWith` for lists — the matcher package's is String-only.
Matcher endsWith2(List<String> tail) => predicate<List<String>>(
  (actual) =>
      actual.length >= tail.length &&
      actual.sublist(actual.length - tail.length).join('\u0000') ==
          tail.join('\u0000'),
  'ends with $tail',
);

void main() {
  group('DevBootstrap.shouldConsider', () {
    test('an injected driver can never be supervised', () {
      expect(
        DevBootstrap.shouldConsider(
          driverInjected: true,
          enableHotReload: true,
        ),
        isFalse,
      );
    });

    test('enableHotReload: false opts out entirely', () {
      expect(
        DevBootstrap.shouldConsider(
          driverInjected: false,
          enableHotReload: false,
        ),
        isFalse,
      );
    });

    test('the test environment itself can never be supervised', () {
      // Under `dart test` stdout/stdin are pipes, so even the permissive
      // argument combination stays out of supervision — every existing
      // runApp test keeps the classic synchronous startup path.
      expect(
        DevBootstrap.shouldConsider(
          driverInjected: false,
          enableHotReload: true,
        ),
        isFalse,
      );
    });
  });

  group('InAppDevReload.shouldConsider', () {
    test('requires a serve/remote handle', () {
      // No FLEURY_HANDLE in the test environment → never active here.
      expect(InAppDevReload.shouldConsider(enableHotReload: true), isFalse);
      expect(InAppDevReload.shouldConsider(enableHotReload: false), isFalse);
    });
  });

  group('devRespawnArguments — what a hot restart re-runs', () {
    List<String> build([List<String> args = const []]) => devRespawnArguments(
      scriptPath: '/app/bin/samples.dart',
      serviceInfo: Uri.parse('file:///tmp/info.json'),
      args: args,
    );

    test("the app's own argv is replayed", () {
      // A process cannot portably read back its own script arguments, so a
      // respawn used to re-run the entrypoint with an EMPTY argv. An app that
      // picks what to show from argv then quietly showed something else:
      // `samples asteroids` restarted onto its usage banner and exited, which
      // reads as a broken CLI rather than a dropped argument.
      expect(build(const ['asteroids']), endsWith2(['asteroids']));
      expect(
        build(const ['run', '--story=button']),
        endsWith2(['run', '--story=button']),
      );
    });

    test('the script path stays the first non-flag argument', () {
      // argv is appended, never prepended — otherwise the VM would try to run
      // the app's own first argument as the script.
      final built = build(const ['asteroids']);
      final firstNonFlag = built.firstWhere((a) => !a.startsWith('-'));
      expect(firstNonFlag, '/app/bin/samples.dart');
    });

    test('an app that hands over nothing is unchanged', () {
      expect(build(), build(const []));
      expect(build().last, '/app/bin/samples.dart');
    });

    test('the VM service comes from FLAGS, never a runtime enable', () {
      // Under a runtime-enabled service any reload of changed sources crashes
      // the VM's kernel service and hangs the RPC.
      expect(build(), contains('--enable-vm-service=0'));
      expect(build(), contains('--write-service-info=file:///tmp/info.json'));
    });
  });
}
