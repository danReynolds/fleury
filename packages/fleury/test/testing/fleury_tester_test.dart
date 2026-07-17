// Meta-tests: exercise FleuryTester / finders / goldens themselves.

import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

/// Captures the BuildContext its build runs under (for present() tests).
class _CtxCapture extends StatelessWidget {
  const _CtxCapture({required this.sink, required this.label});
  final void Function(BuildContext) sink;
  final String label;
  @override
  Widget build(BuildContext context) {
    sink(context);
    return Text(label);
  }
}

void main() {
  group('FleuryTester lifecycle', () {
    test('constructs with isolated framework pieces', () {
      final t = FleuryTester();
      try {
        expect(t.binding, isNotNull);
        expect(t.scheduler, isA<FakeTickerScheduler>());
        expect(t.focusManager, isNotNull);
        expect(t.dispatcher, isNotNull);
        expect(t.owner, isNotNull);
        expect(t.root, isNull);
      } finally {
        t.dispose();
      }
    });

    testWidgets('throws when find is called before pumpWidget', (tester) {
      expect(() => tester.find(byType(Text)), throwsStateError);
    });

    testWidgets('throws after dispose', (tester) {
      tester.dispose();
      expect(() => tester.pump(), throwsStateError);
    });
  });

  group('settle / pumpFleuryHome', () {
    testWidgets('settle() surfaces async stream values pump() cannot', (
      tester,
    ) async {
      final controller = StreamController<String>();
      tester.pumpWidget(
        StreamBuilder<String>(
          stream: controller.stream,
          builder: (_, snap) => Text(snap.data ?? 'loading'),
        ),
      );
      expect(
        tester.renderToString(size: const CellSize(8, 1)),
        contains('loading'),
      );

      // Emit on a timer (truly async): a synchronous pump() can't observe it,
      // but settle() yields to the event loop until the value lands.
      Timer(const Duration(milliseconds: 10), () => controller.add('ready'));
      await tester.settle();
      expect(
        tester.renderToString(size: const CellSize(8, 1)),
        contains('ready'),
      );
      await controller.close();
    });

    testWidgets('pumpWidget leaves app-shell policy to the supplied root', (
      tester,
    ) {
      BuildContext? ctx;
      tester.pumpWidget(_CtxCapture(sink: (c) => ctx = c, label: 'bare'));

      expect(ctx, isNotNull);
      expect(Navigator.maybeOf(ctx!), isNull);
      expect(tester.binding.rootNavigator, isNull);
      expect(
        tester.renderToString(size: const CellSize(8, 1)),
        contains('bare'),
      );
    });

    testWidgets('pumpFleuryHome installs the canonical FleuryApp shell', (
      tester,
    ) async {
      BuildContext? ctx;
      tester.pumpFleuryHome(_CtxCapture(sink: (c) => ctx = c, label: 'home'));
      expect(
        tester.renderToString(size: const CellSize(8, 1)),
        contains('home'),
      );

      final app = FleuryApp.of(ctx!);
      final navigator = Navigator.of(ctx!);
      expect(app.title, 'Fleury test app');
      expect(tester.binding.rootNavigator, same(navigator));

      ctx!.present<void>(const Text('modal'), transition: RouteTransition.none);
      await tester.settle();
      expect(
        tester.renderToString(size: const CellSize(8, 1)),
        contains('modal'),
      );
    });
  });

  group('pumpFleuryHome re-pump / paint-only settle (review regressions)', () {
    testWidgets(
      'pumpFleuryHome replaces the app on re-pump; pumpWidget unwraps',
      (tester) {
        tester.pumpFleuryHome(const Text('one'));
        expect(
          tester.renderToString(size: const CellSize(8, 1)),
          contains('one'),
        );

        tester.pumpFleuryHome(const Text('two'));
        final second = tester.renderToString(size: const CellSize(8, 1));
        expect(
          second,
          contains('two'),
          reason: 'a later pumpFleuryHome must not be silently ignored',
        );
        expect(second, isNot(contains('one')));

        tester.pumpWidget(const Text('three'));
        expect(
          tester.renderToString(size: const CellSize(8, 1)),
          contains('three'),
          reason:
              'pumpWidget after pumpFleuryHome mounts bare (no latched mode)',
        );
      },
    );

    testWidgets('a LayoutBuilder subtree still mounts + subscribes under the '
        'render-skip settle', (tester) async {
      // settle() only renders on the first step and build-work steps; the
      // first render must still mount layout-time subtrees so their streams
      // subscribe (else hollow quiescence).
      final controller = StreamController<String>();
      tester.pumpWidget(
        LayoutBuilder(
          builder: (context, constraints) => StreamBuilder<String>(
            stream: controller.stream,
            builder: (_, snap) => Text(snap.data ?? 'loading'),
          ),
        ),
      );
      Timer(const Duration(milliseconds: 10), () => controller.add('ready'));
      await tester.settle();
      expect(
        tester.renderToString(size: const CellSize(8, 1)),
        contains('ready'),
        reason: 'the LayoutBuilder-hosted StreamBuilder must resolve',
      );
      await controller.close();
    });

    testWidgets('pumpAndSettle after settle() still renders its first step '
        '(no shared render flag)', (tester) async {
      // A prior settle() must not leave a latched flag that makes a later
      // pumpAndSettle skip its guaranteed first render (hollow quiescence).
      tester.pumpWidget(const Text('warm'));
      await tester.settle(); // sets any shared render state
      final probe = GlobalKey<_PaintOnlyAnimState>();
      tester.pumpWidget(_PaintOnlyAnim(key: probe));
      tester.pump();
      tester.pumpAndSettle();
      expect(
        probe.currentState!.completed,
        isTrue,
        reason:
            'pumpAndSettle must render from its own first step '
            'regardless of a prior settle()',
      );
    });

    testWidgets('settle rejects a zero step (would spin forever)', (tester) {
      tester.pumpWidget(const Text('x'));
      expect(
        () => tester.settle(step: Duration.zero),
        throwsA(anything),
        reason: 'a zero step never advances elapsed → timeout unreachable',
      );
    });

    testWidgets('pumpAndSettle runs a paint-only ticker animation to '
        'completion', (tester) {
      final probe = GlobalKey<_PaintOnlyAnimState>();
      tester.pumpWidget(_PaintOnlyAnim(key: probe));
      tester.pump(); // start the ticker
      tester.pumpAndSettle();
      expect(
        probe.currentState!.completed,
        isTrue,
        reason:
            'a bounded animation that only marks paint (no rebuilds) '
            'must still run to completion — paint damage counts as '
            'activity in the settle predicate',
      );
    });
  });

  group('pumpWidget / pump', () {
    testWidgets('mounts the user widget under the binding scope', (tester) {
      tester.pumpWidget(const Text('hello'));
      expect(tester.find(byType(Text)), hasLength(1));
    });

    testWidgets('subsequent pumpWidget replaces the tree', (tester) {
      tester.pumpWidget(const Text('one'));
      expect(tester.find(text('one')), hasLength(1));
      expect(tester.find(text('two')), isEmpty);

      tester.pumpWidget(const Text('two'));
      expect(tester.find(text('two')), hasLength(1));
      expect(tester.find(text('one')), isEmpty);
    });

    testWidgets('pump(duration) advances the scheduler', (tester) {
      tester.pumpWidget(const Text('x'));
      final t0 = tester.clock.now;
      tester.pump(const Duration(milliseconds: 100));
      expect(tester.clock.now - t0, const Duration(milliseconds: 100));
    });

    testWidgets('pumpAndSettle returns once tickers idle', (tester) {
      // No active tickers in this tree: should return immediately.
      tester.pumpWidget(const Text('x'));
      tester.pumpAndSettle();
      expect(tester.scheduler.activeTickerCount, 0);
    });
  });

  group('Finders', () {
    testWidgets('byType matches every widget of that type', (tester) {
      tester.pumpWidget(
        const Column(children: [Text('a'), Text('b'), Text('c')]),
      );
      expect(tester.find(byType(Text)), hasLength(3));
      expect(tester.find(byType(Column)), hasLength(1));
    });

    testWidgets('byKey matches the keyed widget', (tester) {
      const key = ValueKey('target');
      tester.pumpWidget(
        const Column(
          children: [
            Text('skip'),
            Text('hit', key: key),
            Text('skip-also'),
          ],
        ),
      );
      final hit = tester.findOne(byKey(key));
      expect(hit.widget, isA<Text>());
      expect((hit.widget as Text).data, 'hit');
    });

    testWidgets('text matches Text.data exactly', (tester) {
      tester.pumpWidget(const Column(children: [Text('save'), Text('cancel')]));
      expect(tester.find(text('save')), hasLength(1));
      expect(
        tester.find(text('Save')),
        isEmpty,
        reason: 'matcher is case-sensitive',
      );
    });

    testWidgets('byPredicate uses the closure', (tester) {
      tester.pumpWidget(
        const Column(children: [Text('alpha'), Text('beta'), Text('gamma')]),
      );
      final found = tester.find(
        byPredicate(
          (w) => w is Text && w.data.startsWith('b'),
          description: 'Text starting with b',
        ),
      );
      expect(found, hasLength(1));
      expect((found.single.widget as Text).data, 'beta');
    });

    testWidgets('descendantOf scopes the inner finder', (tester) {
      const inner = ValueKey('inner');
      const outer = ValueKey('outer');
      tester.pumpWidget(
        const Column(
          children: [
            Column(key: inner, children: [Text('inside')]),
            Column(key: outer, children: [Text('outside')]),
          ],
        ),
      );
      final hits = tester.find(
        descendantOf(of: byKey(inner), matching: byType(Text)),
      );
      expect(hits, hasLength(1));
      expect((hits.single.widget as Text).data, 'inside');
    });

    testWidgets('findOne fails with a tree dump on zero matches', (tester) {
      tester.pumpWidget(const Text('only-one'));
      try {
        tester.findOne(text('nope'));
        fail('findOne should have thrown');
      } on TestFailure catch (e) {
        expect(e.message, contains("text('nope')"));
        expect(e.message, contains('Current tree:'));
      }
    });

    testWidgets('findOne fails on multiple matches', (tester) {
      tester.pumpWidget(const Column(children: [Text('x'), Text('x')]));
      expect(() => tester.findOne(text('x')), throwsA(isA<TestFailure>()));
    });
  });

  group('Rendering', () {
    testWidgets('render produces a sized cell buffer', (tester) {
      tester.pumpWidget(const Text('hi'));
      final buf = tester.render(size: const CellSize(5, 1));
      expect(buf.size.cols, 5);
      expect(buf.size.rows, 1);
      expect(buf.atColRow(0, 0).grapheme, 'h');
      expect(buf.atColRow(1, 0).grapheme, 'i');
    });

    testWidgets('renderToString uses · for empty cells and rstrips '
        'trailing emptys', (tester) {
      tester.pumpWidget(const Text('hi'));
      final s = tester.renderToString(size: const CellSize(5, 1));
      expect(s, 'hi\n');
    });
  });

  group('Input', () {
    testWidgets('type dispatches a TextInputEvent and flushes builds', (
      tester,
    ) {
      final controller = TextEditingController();
      tester.pumpWidget(TextInput(controller: controller, autofocus: true));
      tester.type('ab');
      expect(controller.text, 'ab');
    });

    testWidgets('sendKey dispatches a KeyEvent', (tester) {
      final controller = TextEditingController(text: 'ab');
      tester.pumpWidget(TextInput(controller: controller, autofocus: true));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.backspace));
      expect(controller.text, 'a');
    });
  });

  group('Goldens', () {
    test(
      'writes the file on first run (and matches itself thereafter)',
      () async {
        final tempDir = Directory.systemTemp.createTempSync('fleury_goldens_');
        addTearDown(() => tempDir.deleteSync(recursive: true));

        // First run: file does not exist. Matcher should write + pass.
        const value = 'hello world\n';
        expect(value, matchesGolden('a.txt', directory: tempDir.path));
        final file = File('${tempDir.path}/a.txt');
        expect(file.existsSync(), isTrue);
        expect(file.readAsStringSync(), value);

        // Second run with identical content: should still pass.
        expect(value, matchesGolden('a.txt', directory: tempDir.path));
      },
    );

    test('fails with a diff when content drifts', () {
      final tempDir = Directory.systemTemp.createTempSync('fleury_goldens_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      File('${tempDir.path}/b.txt').writeAsStringSync('expected\n');

      expect(
        () =>
            expect('actual\n', matchesGolden('b.txt', directory: tempDir.path)),
        throwsA(
          isA<TestFailure>().having(
            (e) => e.message,
            'message',
            allOf(contains('expected'), contains('actual')),
          ),
        ),
      );
    });
  });
}

/// A bounded 200ms animation driven entirely through markNeedsPaintOnly —
/// zero rebuilds per tick (the render-layer animation pattern).
class _PaintOnlyAnim extends StatefulWidget {
  const _PaintOnlyAnim({super.key});
  @override
  State<_PaintOnlyAnim> createState() => _PaintOnlyAnimState();
}

class _PaintOnlyAnimState extends State<_PaintOnlyAnim>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _holder = _ProgressHolder();
  bool completed = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _holder.set((elapsed.inMilliseconds / 200).clamp(0.0, 1.0));
      if (elapsed >= const Duration(milliseconds: 200)) {
        completed = true;
        _ticker.stop();
      }
    });
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _PaintPulse(holder: _holder);
}

class _ProgressHolder extends ChangeNotifier {
  double value = 0;
  void set(double v) {
    value = v;
    notifyListeners();
  }
}

class _PaintPulse extends LeafRenderObjectWidget {
  const _PaintPulse({required this.holder});
  final _ProgressHolder holder;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintPulse(holder);
  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {}
}

class _RenderPaintPulse extends RenderObject {
  _RenderPaintPulse(this._holder) {
    _holder.addListener(markNeedsPaintOnly);
  }
  final _ProgressHolder _holder;

  @override
  CellSize performLayout(CellConstraints constraints) =>
      constraints.constrain(const CellSize(4, 1));

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    buffer.writeGrapheme(
      offset,
      _holder.value >= 1.0 ? 'D' : 'p',
      style: CellStyle.empty,
    );
  }
}
