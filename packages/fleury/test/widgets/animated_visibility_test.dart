// AnimatedVisibility: single-child presence with enter/exit + deferred unmount.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

String _line(FleuryTester tester, {int cols = 8}) {
  final buf = tester.render(size: CellSize(cols, 1));
  final sb = StringBuffer();
  for (var c = 0; c < cols; c++) {
    final cell = buf.atColRow(c, 0);
    sb.write(cell.role == CellRole.leading ? cell.grapheme : ' ');
  }
  return sb.toString().trimRight();
}

class _LifecycleProbe extends StatefulWidget {
  const _LifecycleProbe({required this.onInit, required this.onDispose});

  final void Function() onInit;
  final void Function() onDispose;

  @override
  State<_LifecycleProbe> createState() => _LifecycleProbeState();
}

class _LifecycleProbeState extends State<_LifecycleProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('stateful');
}

void main() {
  testWidgets('hidden AnimatedVisibility renders nothing', (tester) {
    tester.pumpWidget(
      const AnimatedVisibility(visible: false, child: Text('hi')),
    );
    expect(_line(tester), '');
  });

  testWidgets('visible AnimatedVisibility with no enter shows immediately', (
    tester,
  ) {
    tester.pumpWidget(
      const AnimatedVisibility(visible: true, child: Text('hi')),
    );
    expect(_line(tester), 'hi');
  });

  testWidgets('toggling visible true plays the enter effect', (tester) {
    tester.pumpWidget(
      AnimatedVisibility(
        visible: false,
        enter: Effects.wipeIn(from: Edge.left),
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
        child: const Text('hello'),
      ),
    );
    expect(_line(tester), '');

    // Become visible → entrance plays (left-to-right wipe).
    tester.pumpWidget(
      AnimatedVisibility(
        visible: true,
        enter: Effects.wipeIn(from: Edge.left),
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
        child: const Text('hello'),
      ),
    );
    tester.pump(const Duration(milliseconds: 60));
    expect(_line(tester), 'hel'); // ~3 of 5 cols
    tester.pump(const Duration(milliseconds: 100));
    expect(_line(tester), 'hello');
  });

  testWidgets('hiding keeps the child mounted until exit finishes, '
      'then drops it', (tester) {
    Widget build(bool visible) => AnimatedVisibility(
      visible: visible,
      exit: Effects.wipeOut(to: Edge.left),
      duration: const Duration(milliseconds: 100),
      curve: Curves.linear,
      child: const Text('bye'),
    );

    tester.pumpWidget(build(true));
    expect(_line(tester), 'bye');

    // Hide → exit animation begins, child still present mid-exit.
    tester.pumpWidget(build(false));
    tester.pump(const Duration(milliseconds: 50));
    expect(_line(tester), isNot(''), reason: 'still mounted while exit plays');

    // After the exit completes, the child is gone.
    tester.pump(const Duration(milliseconds: 100));
    // allow the completion microtask to run
    expect(_line(tester), '');
  });

  testWidgets('exit completion is async-safe — child unmounts', (tester) async {
    Widget build(bool v) => AnimatedVisibility(
      visible: v,
      exit: Effects.fadeOut(),
      duration: const Duration(milliseconds: 80),
      curve: Curves.linear,
      child: const Text(
        'x',
        style: CellStyle(foreground: RgbColor(200, 200, 200)),
      ),
    );
    tester.pumpWidget(build(true));
    tester.pumpWidget(build(false));
    tester.pump(const Duration(milliseconds: 120));
    await Future<void>.delayed(Duration.zero);
    tester.pump();
    expect(tester.scheduler.activeTickerCount, 0);
    expect(_line(tester), '');
  });

  testWidgets('re-showing mid-exit cancels the unmount', (tester) {
    Widget build(bool v) => AnimatedVisibility(
      visible: v,
      enter: Effects.fadeIn(),
      exit: Effects.fadeOut(),
      duration: const Duration(milliseconds: 100),
      curve: Curves.linear,
      child: const Text(
        'keep',
        style: CellStyle(foreground: RgbColor(0, 200, 0)),
      ),
    );
    tester.pumpWidget(build(true));
    tester.pumpWidget(build(false)); // start exiting
    tester.pump(const Duration(milliseconds: 40));
    tester.pumpWidget(build(true)); // re-show mid-exit
    tester.pump(const Duration(milliseconds: 200));
    // Survived: still present at full color.
    expect(_line(tester), 'keep');
  });

  testWidgets('a stale cancelled exit cannot end a newer exit', (tester) async {
    Widget build(bool visible) => AnimatedVisibility(
      visible: visible,
      enter: Effects.fadeIn(),
      exit: Effects.fadeOut(),
      duration: const Duration(milliseconds: 100),
      curve: Curves.linear,
      child: const Text(
        'keep',
        style: CellStyle(foreground: RgbColor(0, 200, 0)),
      ),
    );

    tester.pumpWidget(build(true));
    tester.pumpWidget(build(false));
    tester.pump(const Duration(milliseconds: 30));
    tester.pumpWidget(build(true));
    tester.pumpWidget(build(false));

    // Let completion from the cancelled first exit run. It must not observe
    // the newest `visible: false` and unmount that newer transition.
    await Future<void>.delayed(Duration.zero);
    tester.pump();
    expect(
      _line(tester),
      isNot(''),
      reason: 'the second exit still owns the child lifetime',
    );

    tester.pump(const Duration(milliseconds: 120));
    await Future<void>.delayed(Duration.zero);
    tester.pump();
    expect(_line(tester), '');
  });

  testWidgets(
    'switching between different enter and exit effects preserves child state',
    (tester) {
      var initializations = 0;
      var disposals = 0;

      Widget build(bool visible) => AnimatedVisibility(
        visible: visible,
        enter: Effects.fadeIn(),
        exit: Effects.shrink(),
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
        child: _LifecycleProbe(
          onInit: () => initializations++,
          onDispose: () => disposals++,
        ),
      );

      tester.pumpWidget(build(true));
      tester.pump(const Duration(milliseconds: 120));
      expect(initializations, 1);
      expect(disposals, 0);

      tester.pumpWidget(build(false));
      tester.pump(const Duration(milliseconds: 40));

      expect(
        initializations,
        1,
        reason: 'changing effect wrappers must not remount the visible child',
      );
      expect(disposals, 0, reason: 'the child stays mounted during its exit');
    },
  );

  testWidgets(
    'AnimationPolicy.disabled: enter/exit are instant',
    (tester) {
      tester.pumpWidget(
        const AnimatedVisibility(visible: true, enter: null, child: Text('z')),
      );
      expect(_line(tester), 'z');
    },
    animationPolicy: AnimationPolicy.disabled,
  );
}
