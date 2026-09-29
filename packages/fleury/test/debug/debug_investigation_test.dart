import 'package:fleury/fleury.dart';
import 'package:fleury/src/debug/debug_shell.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

FrameEvent frame(int number, {int buildMs = 1}) => FrameEvent(
  frameNumber: number,
  reason: 'key:enter',
  build: Duration(milliseconds: buildMs),
  layout: const Duration(microseconds: 200),
  paint: const Duration(microseconds: 300),
  diff: const Duration(microseconds: 100),
  dirtyCells: 8,
  dirtySources: const ['build:SlowPane/_SlowPaneState'],
  bufferSize: const CellSize(80, 24),
);

Future<void> emit(FrameEvent event) async {
  DebugEvents.emitFrame(event);
  await Future<void>.delayed(Duration.zero);
}

class _StateProbe extends StatefulWidget {
  const _StateProbe(this.onMount);
  final void Function() onMount;
  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const Text('app state');
}

void main() {
  test('hosts can disable an unavailable paint-flash overlay', () {
    final controller = DebugController(const DebugConfig())
      ..paintFlashAvailable = false;
    addTearDown(controller.dispose);
    controller.togglePaintFlash();
    expect(controller.paintFlash, isFalse);
  });

  test(
    'scrolling reports settle instead of refreshing themselves at idle',
    () async {
      final driver = FakeTerminalDriver(size: const CellSize(80, 24));
      final app = runApp(
        const Text('idle app'),
        driver: driver,
        debug: const DebugConfig(startMode: DebugMode.fullscreen),
        enableHotReload: false,
      );
      // Allow Live's trailing FPS decay and any scroll-metrics frame to settle.
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      driver.clearOutput();
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      final liveOutput = driver.output;
      driver.enqueue(const KeyEvent(KeyCode.tab));
      driver.enqueue(const KeyEvent(KeyCode.tab));
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      driver.clearOutput();
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      final rebuildOutput = driver.output;
      driver.enqueue(
        const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
      );
      await app;
      await driver.dispose();
      expect(liveOutput, isEmpty);
      expect(rebuildOutput, isEmpty);
    },
  );

  testWidgets('opening, expanding, and hiding preserve the application state', (
    tester,
  ) {
    final controller = DebugController(const DebugConfig());
    addTearDown(controller.dispose);
    var mounts = 0;
    tester.pumpWidget(
      DebugShell(controller: controller, child: _StateProbe(() => mounts++)),
    );
    tester.render(size: const CellSize(80, 24));
    for (final change in [
      controller.toggleOnOff,
      controller.toggleExpand,
      controller.toggleExpand,
      controller.toggleOnOff,
    ]) {
      change();
      tester.pump();
      tester.render(size: const CellSize(80, 24));
      expect(mounts, 1);
    }
  });

  test('native runtime releases the hidden recording on exit', () async {
    final driver = FakeTerminalDriver(size: const CellSize(80, 24));
    final app = runApp(
      const Text('app'),
      driver: driver,
      debug: const DebugConfig(startMode: DebugMode.docked),
      enableHotReload: false,
    );
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    driver.enqueue(
      const KeyEvent(KeyCode.char('g'), modifiers: {KeyModifier.ctrl}),
    );
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(DebugEvents.hasListeners, isTrue);
    driver.enqueue(
      const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
    );
    await app;
    await driver.dispose();
    expect(DebugEvents.hasListeners, isFalse);
  });

  test(
    'recording starts on first open and stays bounded while hidden',
    () async {
      final controller = DebugController(const DebugConfig());
      addTearDown(controller.dispose);
      expect(DebugEvents.hasListeners, isFalse);
      await emit(frame(0));
      expect(controller.frameHistory, isEmpty);

      controller.toggleOnOff();
      await emit(frame(1));
      controller.toggleOnOff();
      for (var i = 2; i <= 65; i++) {
        await emit(frame(i));
      }
      controller.toggleOnOff();
      expect(controller.frameHistory, hasLength(60));
      expect(controller.frameHistory.first.frameNumber, 6);
      expect(controller.frameHistory.last.frameNumber, 65);
      controller.dispose();
      expect(DebugEvents.hasListeners, isFalse);
      expect(controller.frameHistory, isEmpty);
    },
  );

  test('disabled debug tooling never subscribes, even when opened', () {
    final controller = DebugController(
      const DebugConfig(enabled: false, startMode: DebugMode.docked),
    );
    addTearDown(controller.dispose);
    controller.toggleOnOff();
    controller.toggleOnOff();
    expect(DebugEvents.hasListeners, isFalse);
  });

  testWidgets('hidden slow frame survives reopening and expanding', (
    tester,
  ) async {
    final controller = DebugController(
      const DebugConfig(startMode: DebugMode.docked),
    )..selectTab(DebugTab.rebuilds);
    addTearDown(controller.dispose);
    tester.pumpWidget(
      DebugShell(controller: controller, child: const Text('app')),
    );
    tester.render(size: const CellSize(100, 32));

    controller.toggleOnOff();
    tester.pump();
    await emit(frame(41, buildMs: 120));
    await emit(frame(42));
    controller.toggleOnOff();
    controller.toggleExpand();
    tester.pump();
    final output = tester.renderToString(
      size: const CellSize(100, 32),
      emptyMark: ' ',
    );
    expect(output, contains('Last frame  #42'));
    expect(output, contains('Worst frame  #41'));
    expect(output, contains('Worst build  120ms'));
    expect(output, contains('Worst layout  0.2ms'));
    expect(output, contains('Worst sources  build:SlowPane/_SlowPaneState'));
  });

  testWidgets('page keys expose the full trace in a short terminal', (tester) {
    final controller = DebugController(
      const DebugConfig(startMode: DebugMode.fullscreen),
    )..selectTab(DebugTab.errors);
    addTearDown(controller.dispose);
    controller.setErrorHistoryProvider(
      () => [
        RuntimeErrorRecord(
          StateError('failed save'),
          StackTrace.fromString(
            List.generate(25, (i) => '#$i save_step_$i').join('\n'),
          ),
          DateTime(2026, 9, 23, 12),
        ),
      ],
    );
    tester.pumpWidget(
      DebugShell(controller: controller, child: const Text('app')),
    );
    String render() =>
        tester.renderToString(size: const CellSize(60, 16), emptyMark: ' ');
    expect(render(), contains('failed save'));
    expect(render(), isNot(contains('save_step_24')));
    for (var i = 0; i < 6; i++) {
      expect(
        tryConsumeDebugKey(controller, const KeyEvent(KeyCode.pageDown)),
        isTrue,
      );
      tester.pump();
      render();
    }
    expect(render(), contains('save_step_24'));
    controller.selectTab(DebugTab.tree);
    expect(controller.detailScrollController.offset, 0);
    controller.selectTab(DebugTab.errors);
    tester.pump();
    expect(render(), contains('failed save'));

    controller.selectTab(DebugTab.logs);
    expect(
      tryConsumeDebugKey(controller, const KeyEvent(KeyCode.pageDown)),
      isFalse,
    );
    controller.toggleOnOff();
    expect(
      tryConsumeDebugKey(controller, const KeyEvent(KeyCode.pageDown)),
      isFalse,
    );
  });
}
