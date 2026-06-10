@TestOn('browser')
library;

import 'dart:async';

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:test/test.dart';

class _FakeFlush {
  Duration? delay;
  void Function()? _pending;
  var scheduleCount = 0;

  bool get pending => _pending != null;

  void schedule(Duration delay, void Function() flush) {
    scheduleCount += 1;
    this.delay = delay;
    _pending = flush;
  }

  void fire() {
    final flush = _pending;
    if (flush == null) throw StateError('No pending frame flush.');
    _pending = null;
    delay = null;
    flush();
  }
}

Future<void> _drainEvents() => Future<void>.delayed(Duration.zero);

void main() {
  test('initial render is scheduled through injected frame flush', () async {
    final driver = FakeTerminalDriver(size: const CellSize(10, 1));
    final flush = _FakeFlush();

    await runTuiWeb(
      () => const Text('hi'),
      driver: driver,
      flushScheduler: flush.schedule,
    );

    expect(flush.scheduleCount, 1);
    expect(flush.delay, Duration.zero);
    expect(flush.pending, isTrue);

    driver.clearOutput();
    flush.fire();

    expect(driver.output, contains('hi'));
    await driver.dispose();
  });

  test('resize is queued and applied during the next frame', () async {
    final driver = FakeTerminalDriver(size: const CellSize(8, 1));
    final flush = _FakeFlush();

    await runTuiWeb(
      () => const Text('resized'),
      driver: driver,
      flushScheduler: flush.schedule,
    );
    flush.fire();
    driver.clearOutput();

    driver.resize(const CellSize(12, 1));
    await _drainEvents();

    expect(flush.pending, isTrue);
    expect(driver.output, isEmpty);

    flush.fire();

    expect(driver.output, contains('\x1B[2J\x1B[H'));
    expect(driver.output, contains('resized'));
    await driver.dispose();
  });

  test('post-frame state changes schedule another frame', () async {
    final driver = FakeTerminalDriver(size: const CellSize(10, 1));
    final flush = _FakeFlush();

    await runTuiWeb(
      () => const _PostFrameCounter(),
      driver: driver,
      flushScheduler: flush.schedule,
    );

    driver.clearOutput();
    flush.fire();
    expect(driver.output, contains('count:0'));
    expect(flush.pending, isTrue);

    driver.clearOutput();
    flush.fire();
    expect(driver.output, contains('1'));
    await driver.dispose();
  });

  test('closing the driver makes pending frame flushes no-ops', () async {
    final driver = FakeTerminalDriver(size: const CellSize(10, 1));
    final flush = _FakeFlush();

    await runTuiWeb(
      () => const Text('late'),
      driver: driver,
      flushScheduler: flush.schedule,
    );

    expect(flush.pending, isTrue);
    driver.clearOutput();
    await driver.dispose();

    flush.fire();
    expect(driver.output, isEmpty);
  });

  test('setup failures restore the entered driver', () async {
    final error = StateError('write failed');
    final driver = _ThrowingWriteDriver(error);
    final flush = _FakeFlush();

    await expectLater(
      runTuiWeb(
        () => const Text('unused'),
        driver: driver,
        flushScheduler: flush.schedule,
      ),
      throwsA(same(error)),
    );

    expect(driver.enterCallCount, 1);
    expect(driver.restoreCallCount, 1);
    expect(driver.isActive, isFalse);
    expect(flush.pending, isFalse);
    await driver.dispose();
  });
}

final class _ThrowingWriteDriver implements TerminalDriver {
  _ThrowingWriteDriver(this.error);

  final Object error;
  final _events = StreamController<TuiEvent>.broadcast();
  var enterCallCount = 0;
  var restoreCallCount = 0;
  var _active = false;

  @override
  CellSize get size => const CellSize(10, 1);

  @override
  TerminalCapabilities get capabilities =>
      TerminalCapabilities.defaultCapabilities;

  @override
  Stream<TuiEvent> get events => _events.stream;

  @override
  bool get isActive => _active;

  @override
  bool get isInteractive => true;

  @override
  Future<void> enter(TerminalMode mode) async {
    enterCallCount += 1;
    _active = true;
  }

  @override
  Future<void> restore() async {
    if (!_active) return;
    restoreCallCount += 1;
    _active = false;
  }

  @override
  void write(String data) {
    throw error;
  }

  Future<void> dispose() => _events.close();
}

final class _PostFrameCounter extends StatefulWidget {
  const _PostFrameCounter();

  @override
  State<_PostFrameCounter> createState() => _PostFrameCounterState();
}

final class _PostFrameCounterState extends State<_PostFrameCounter> {
  var count = 0;

  @override
  void initState() {
    super.initState();
    TuiBinding.of(context).addPostFrameCallback((_) {
      setState(() => count += 1);
    });
  }

  @override
  Widget build(BuildContext context) => Text('count:$count');
}
