import 'dart:async';
import 'dart:isolate';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

class _Mounted extends StatelessWidget {
  const _Mounted(this.onMount);
  final void Function() onMount;

  @override
  Widget build(BuildContext context) {
    onMount();
    return const Text('session');
  }
}

// Completers locate the ownership boundaries without wall-clock sleeps.
class _ControlledDriver implements TerminalDriver {
  _ControlledDriver({
    this.enterGate,
    this.restoreGate,
    this.asyncStartupError = false,
    this.failRestore = false,
  });

  final Future<void>? enterGate;
  final Future<void>? restoreGate;
  final bool asyncStartupError;
  final bool failRestore;
  final entered = Completer<void>();
  final restoring = Completer<void>();
  final restored = Completer<void>();
  final fake = FakeTerminalDriver();

  @override
  bool get isActive => fake.isActive;
  @override
  bool get isInteractive => fake.isInteractive;
  @override
  CellSize get size => fake.size;
  @override
  TerminalCapabilities get capabilities => fake.capabilities;
  @override
  Stream<TuiEvent> get events => fake.events;
  @override
  void write(String data) => fake.write(data);

  @override
  Future<TerminalSessionProfile> enter(TerminalMode mode) async {
    entered.complete();
    if (asyncStartupError) {
      scheduleMicrotask(() => throw StateError('async startup failure'));
    }
    await enterGate;
    if (restoring.isCompleted) throw StateError('startup cancelled by restore');
    return fake.enter(mode);
  }

  @override
  Future<void> restore() async {
    restoring.complete();
    await restoreGate;
    await fake.restore();
    restored.complete();
    if (failRestore) throw StateError('late restore failure');
  }
}

void main() {
  test('exitApp starts shutdown; runApp awaits terminal restoration', () async {
    final gate = Completer<void>();
    final driver = _ControlledDriver(restoreGate: gate.future);
    addTearDown(driver.fake.dispose);
    var completed = false;
    final running =
        runApp(
          const Text('session'),
          driver: driver,
          enableHotReload: false,
        ).then((result) {
          completed = true;
          return result;
        });
    await driver.entered.future;
    expect(exitApp(), isTrue);
    expect(exitApp(), isFalse);
    await driver.restoring.future;
    expect(completed, isFalse);
    gate.complete();
    expect((await running).signal, isNull);
    expect(driver.restored.isCompleted, isTrue);
    expect(exitApp(), isFalse);
  });

  test(
    'a restoration that fails after its deadline stays quarantined',
    () async {
      final result = await Isolate.run(() async {
        final gate = Completer<void>();
        final driver = _ControlledDriver(
          restoreGate: gate.future,
          failRestore: true,
        );
        var firstFailed = false;
        final first =
            runApp(
              const Text('first'),
              driver: driver,
              enableHotReload: false,
            ).then(
              (_) {},
              onError: (Object error) {
                firstFailed = error is FleuryError;
              },
            );
        exitApp();
        await first;
        gate.complete();
        await driver.restored.future;
        await Future<void>.delayed(Duration.zero);
        final nextDriver = FakeTerminalDriver();
        var blocked = false;
        try {
          await runApp(
            const Text('blocked'),
            driver: nextDriver,
            enableHotReload: false,
          );
        } on StateError catch (error) {
          blocked = error.message.contains('terminal restore');
        }
        final secondEntered = nextDriver.enterCallCount;
        await driver.fake.dispose();
        await nextDriver.dispose();
        return (firstFailed, blocked, secondEntered);
      });
      expect(result, (true, true, 0));
    },
  );

  test('fatal cleanup holds admission until late startup is fenced', () async {
    final gate = Completer<void>();
    final driver = _ControlledDriver(
      enterGate: gate.future,
      asyncStartupError: true,
    );
    final nextDriver = FakeTerminalDriver();
    addTearDown(driver.fake.dispose);
    addTearDown(nextDriver.dispose);
    var oldBuilds = 0;
    final first = runApp(
      _Mounted(() => oldBuilds++),
      driver: driver,
      enableHotReload: false,
    );
    await expectLater(
      first,
      throwsA(
        isA<FleuryError>().having(
          (e) => e.details,
          'details',
          contains('terminal startup'),
        ),
      ),
    );
    await expectLater(
      runApp(const Text('too early'), driver: nextDriver),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('terminal startup'),
        ),
      ),
    );
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(oldBuilds, 0);
    expect(driver.fake.enterCallCount, 0);
    final next = runApp(
      const Text('next'),
      driver: nextDriver,
      enableHotReload: false,
    );
    expect(exitApp(), isTrue);
    await next;
    expect(nextDriver.restoreCallCount, 1);
  });

  test('expired async app callbacks cannot exit the next invocation', () async {
    final firstDriver = FakeTerminalDriver();
    final secondDriver = FakeTerminalDriver();
    addTearDown(firstDriver.dispose);
    addTearDown(secondDriver.dispose);
    final mounted = Completer<void>();
    final trigger = Completer<void>();
    final staleResult = Completer<bool>();
    final first = runApp(
      _Mounted(() {
        if (mounted.isCompleted) return;
        trigger.future.then((_) => staleResult.complete(exitApp()));
        mounted.complete();
      }),
      driver: firstDriver,
      enableHotReload: false,
    );
    await mounted.future;
    expect(exitApp(), isTrue);
    await first;

    final secondMounted = Completer<void>();
    final second = runApp(
      _Mounted(() {
        if (!secondMounted.isCompleted) secondMounted.complete();
      }),
      driver: secondDriver,
      enableHotReload: false,
    );
    await secondMounted.future;
    trigger.complete();
    expect(await staleResult.future, isFalse);
    expect(secondDriver.restoreCallCount, 0);
    // Deliberately unscoped host calls still address the current app.
    expect(exitApp(), isTrue);
    await second;
    expect(exitApp(), isFalse);
  });

  test('admission precedes an asynchronous driver startup', () async {
    final gate = Completer<void>();
    final driver = _ControlledDriver(enterGate: gate.future);
    final overlapping = FakeTerminalDriver();
    addTearDown(driver.fake.dispose);
    addTearDown(overlapping.dispose);
    final first = runApp(
      const Text('first'),
      driver: driver,
      enableHotReload: false,
    );
    await driver.entered.future;
    await expectLater(
      runApp(const Text('overlap'), driver: overlapping),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Await its completion'),
        ),
      ),
    );
    expect(overlapping.enterCallCount, 0);
    expect(exitApp(), isTrue);
    gate.complete();
    await first;
    expect(driver.fake.restoreCallCount, 1);
  });

  test('nested calls fail instead of awaiting their own parent', () async {
    final driver = FakeTerminalDriver();
    final nestedDriver = FakeTerminalDriver();
    addTearDown(driver.dispose);
    addTearDown(nestedDriver.dispose);
    final result = Completer<Object>();
    var started = false;
    final app = runApp(
      _Mounted(() {
        if (started) return;
        started = true;
        runApp(const Text('nested'), driver: nestedDriver).then(
          (_) => result.complete('unexpected success'),
          onError: (Object error) => result.complete(error),
        );
      }),
      driver: driver,
      enableHotReload: false,
    );
    expect(await result.future, isA<StateError>());
    expect(nestedDriver.enterCallCount, 0);
    expect(exitApp(), isTrue);
    await app;
  });

  test('admission remains held throughout driver restoration', () async {
    final gate = Completer<void>();
    final driver = _ControlledDriver(restoreGate: gate.future);
    final nextDriver = FakeTerminalDriver();
    addTearDown(driver.fake.dispose);
    addTearDown(nextDriver.dispose);
    final mounted = Completer<void>();
    final first = runApp(
      _Mounted(() {
        if (!mounted.isCompleted) mounted.complete();
      }),
      driver: driver,
      enableHotReload: false,
    );
    await mounted.future;
    expect(exitApp(), isTrue);
    await driver.restoring.future;
    expect(exitApp(), isFalse);
    await expectLater(
      runApp(const Text('too early'), driver: nextDriver),
      throwsStateError,
    );
    expect(nextDriver.enterCallCount, 0);
    gate.complete();
    await first;

    final next = runApp(
      const Text('after cleanup'),
      driver: nextDriver,
      enableHotReload: false,
    );
    expect(exitApp(), isTrue);
    await next;
    expect(nextDriver.restoreCallCount, 1);
  });

  test('pre-entry failure releases admission for a fresh driver', () async {
    final invalid = FakeTerminalDriver(isInteractive: false);
    final valid = FakeTerminalDriver();
    addTearDown(invalid.dispose);
    addTearDown(valid.dispose);
    await expectLater(
      runApp(const Text('invalid'), driver: invalid),
      throwsA(isA<FleuryError>()),
    );
    expect(invalid.enterCallCount, 0);
    final app = runApp(
      const Text('valid'),
      driver: valid,
      enableHotReload: false,
    );
    expect(exitApp(), isTrue);
    await app;
    expect(valid.restoreCallCount, 1);
  });

  test(
    'a cleanup deadline does not release pending terminal ownership',
    () async {
      final gate = Completer<void>();
      final driver = _ControlledDriver(restoreGate: gate.future);
      final nextDriver = FakeTerminalDriver();
      addTearDown(driver.fake.dispose);
      addTearDown(nextDriver.dispose);
      final first = runApp(
        const Text('first'),
        driver: driver,
        enableHotReload: false,
      );
      final failed = expectLater(
        first,
        throwsA(
          isA<FleuryError>().having(
            (e) => e.details,
            'details',
            contains('terminal restore'),
          ),
        ),
      );
      expect(exitApp(), isTrue);
      await failed;
      await expectLater(
        runApp(const Text('too early'), driver: nextDriver),
        throwsStateError,
      );
      expect(nextDriver.enterCallCount, 0);
      gate.complete();
      await driver.restored.future;
      // Let the underlying restore future and its ownership continuation settle.
      await Future<void>.delayed(Duration.zero);
      final next = runApp(
        const Text('after late restoration'),
        driver: nextDriver,
        enableHotReload: false,
      );
      expect(exitApp(), isTrue);
      await next;
      expect(nextDriver.restoreCallCount, 1);
    },
  );
}
