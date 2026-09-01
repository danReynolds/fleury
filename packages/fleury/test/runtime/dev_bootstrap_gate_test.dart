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

    test("the user's VM options are replayed, ahead of the supervisor's", () {
      // The child is the process the user interacts with. Every VM flag on
      // their command line used to be dropped on the respawn: `--define=`
      // read back as unset and `--enable-asserts` ran with assertions OFF,
      // silently, with nothing pointing at hot reload.
      final built = devRespawnArguments(
        scriptPath: '/app/bin/main.dart',
        serviceInfo: Uri.parse('file:///tmp/info.json'),
        vmOptions: const ['--enable-asserts', '--define=API_URL=https://x'],
      );
      expect(
        built.take(2),
        ['--enable-asserts', '--define=API_URL=https://x'],
        reason: 'user options first, so a later supervisor flag cannot be '
            'shadowed by them',
      );
      expect(built, contains('--enable-vm-service=0'));
      final firstNonFlag = built.firstWhere((a) => !a.startsWith('-'));
      expect(firstNonFlag, '/app/bin/main.dart');
    });
  });

  group('replayableVmOptions — what a respawn inherits from its parent', () {
    test("dart run's injected bookkeeping is not replayed", () {
      // `dart run` adds these for itself; a direct `dart <script>` spawn has
      // no use for them.
      expect(
        replayableVmOptions(const [
          '--enable-asserts',
          '--resolved_executable_name=/sdk/bin/dart',
          '--executable_name=dart',
        ]),
        ['--enable-asserts'],
      );
    });

    test('anything that collides with the supervisor-owned service is dropped', () {
      // The service comes from the supervisor's own flags; a second server or
      // a pause-on-start on the child would defeat the respawn.
      expect(
        replayableVmOptions(const [
          '--observe=8181',
          '--observe',
          '--enable-vm-service=0',
          '--write-service-info=file:///x',
          '--serve-devtools',
          '--pause-isolates-on-start',
          '--define=A=1',
        ]),
        ['--define=A=1'],
      );
    });

    test("everything else is the user's and passes through verbatim", () {
      const mine = [
        '--enable-asserts',
        '-DFLAG=1',
        '--define=API_URL=https://x',
        '--enable-experiment=records',
        '--packages=.dart_tool/package_config.json',
      ];
      expect(replayableVmOptions(mine), mine);
    });
  });
}
