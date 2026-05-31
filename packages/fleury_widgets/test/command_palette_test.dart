import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

/// Captures a BuildContext under a Navigator so we can present the
/// palette from it.
class _Capture extends StatelessWidget {
  const _Capture(this.sink);
  final void Function(BuildContext) sink;
  @override
  Widget build(BuildContext context) {
    sink(context);
    return const Text('home');
  }
}

/// Presents the palette and lets the entrance settle (its TextInput
/// autofocuses on build — no focus hack needed under present).
void _open(FleuryTester tester, BuildContext ctx, List<Command> cmds) {
  Navigator.of(ctx).present<void>(CommandPalette(commands: cmds));
  tester.pump(const Duration(milliseconds: 300));
}

/// Pumps out a dismissal transition so the route is fully removed.
Future<void> _settleClose(FleuryTester tester) async {
  tester.pump(const Duration(milliseconds: 300));
  await Future<void>.delayed(Duration.zero);
  tester.pump();
}

void main() {
  late BuildContext ctx;
  List<Command> commands(void Function(String) onRun) => [
    Command(label: 'Open File', onInvoke: () => onRun('open')),
    Command(label: 'Save File', onInvoke: () => onRun('save')),
    Command(label: 'Close Window', onInvoke: () => onRun('close')),
  ];

  testWidgets('filters by fuzzy query and invokes on Enter', (tester) async {
    String? ran;
    tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));
    _open(tester, ctx, commands((v) => ran = v));
    expect(Navigator.of(ctx).depth, 2, reason: 'palette is open');

    tester.type('save'); // matches only "Save File"
    tester.pump();
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    expect(ran, 'save');

    await _settleClose(tester);
    expect(Navigator.of(ctx).depth, 1, reason: 'palette closed on invoke');
  });

  testWidgets('Up/Down move the selection before invoking', (tester) async {
    String? ran;
    tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));
    _open(tester, ctx, commands((v) => ran = v));

    // No query → all three; selection starts at 0 (Open File).
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // → Save File
    tester.sendKey(
      const KeyEvent(keyCode: KeyCode.arrowDown),
    ); // → Close Window
    tester.pump();
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    expect(ran, 'close');
  });

  testWidgets('Esc dismisses without invoking', (tester) async {
    var ran = false;
    tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));
    _open(tester, ctx, [
      Command(label: 'Dangerous', onInvoke: () => ran = true),
    ]);

    tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
    await _settleClose(tester);

    expect(ran, isFalse);
    expect(Navigator.of(ctx).depth, 1, reason: 'palette dismissed');
  });

  group('edges', () {
    testWidgets('shows a no-match message when nothing matches', (
      tester,
    ) async {
      tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));
      _open(tester, ctx, commands((_) {}));
      tester.type('zzzz');
      tester.pump();
      expect(tester.exists(text('No matching commands')), isTrue);
    });

    testWidgets('selection resets to the top when the query changes', (
      tester,
    ) async {
      String? ran;
      tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));
      _open(tester, ctx, commands((v) => ran = v));

      // Move off the top, then type — 's' matches Save + Close, and the
      // selection should snap back to the first match (Save), not stay at 1.
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      tester.type('s');
      tester.pump();
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(ran, 'save', reason: 'selection reset to the first match');
    });

    testWidgets('an empty command list is inert, not a crash', (tester) async {
      tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));
      _open(tester, ctx, const []);
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      tester.pump();
      expect(
        Navigator.of(ctx).depth,
        2,
        reason: 'still open; Enter was a no-op',
      );
    });
  });
}
