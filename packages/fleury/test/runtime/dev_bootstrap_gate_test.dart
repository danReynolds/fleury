import 'package:fleury/src/runtime/dev_bootstrap.dart';
import 'package:test/test.dart';

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
}
