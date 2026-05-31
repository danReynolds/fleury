import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

class _Capture extends StatelessWidget {
  const _Capture(this.sink);
  final void Function(BuildContext) sink;
  @override
  Widget build(BuildContext context) {
    sink(context);
    return const Text('app');
  }
}

String _screen(FleuryTester tester, {int cols = 20, int rows = 8}) =>
    tester.renderToString(size: CellSize(cols, rows), emptyMark: ' ');

void main() {
  testWidgets('shows a toast and auto-dismisses after the duration', (
    tester,
  ) async {
    late BuildContext ctx;
    tester.pumpWidget(
      Toaster(
        duration: const Duration(seconds: 2),
        child: _Capture((c) => ctx = c),
      ),
    );

    Toaster.show(ctx, 'Saved');
    tester.pump();
    expect(_screen(tester).contains('Saved'), isTrue);

    // After the duration the auto-dismiss timer fires and removes it.
    tester.pump(const Duration(seconds: 2));
    await Future<void>.delayed(Duration.zero);
    tester.pump();
    expect(_screen(tester).contains('Saved'), isFalse);
  });

  testWidgets('stacks multiple toasts', (tester) {
    late BuildContext ctx;
    tester.pumpWidget(Toaster(child: _Capture((c) => ctx = c)));

    Toaster.show(ctx, 'first');
    Toaster.show(ctx, 'second');
    tester.pump();
    final out = _screen(tester);
    expect(out.contains('first'), isTrue);
    expect(out.contains('second'), isTrue);
  });

  testWidgets('toasts float over a presented modal', (tester) async {
    // The Toaster's overlay entry sits above the navigator, so a toast
    // shows on top of a dialog presented on the navigator.
    late BuildContext ctx;
    tester.pumpWidget(
      Toaster(child: Navigator(home: _Capture((c) => ctx = c))),
    );
    Navigator.of(ctx).present<void>(const Text('dialog'));
    tester.pump(const Duration(milliseconds: 300));

    Toaster.show(ctx, 'notice');
    tester.pump();
    expect(_screen(tester).contains('notice'), isTrue);
  });

  testWidgets('throws without a Toaster ancestor', (tester) {
    late BuildContext ctx;
    tester.pumpWidget(_Capture((c) => ctx = c));
    expect(() => Toaster.show(ctx, 'x'), throwsStateError);
  });

  testWidgets('severity tints the toast text', (tester) {
    late BuildContext ctx;
    tester.pumpWidget(Toaster(child: _Capture((c) => ctx = c)));
    Toaster.show(ctx, 'oops', severity: ToastSeverity.error);
    tester.pump();
    final buf = tester.render(size: const CellSize(20, 8));
    // Find the 'o' of 'oops' and check it carries the error (red) color.
    var found = false;
    for (var r = 0; r < 8 && !found; r++) {
      for (var c = 0; c < 20; c++) {
        if (buf.atColRow(c, r).grapheme == 'o') {
          expect(buf.atColRow(c, r).style.foreground, const AnsiColor(1));
          found = true;
          break;
        }
      }
    }
    expect(found, isTrue, reason: 'rendered the toast text');
  });

  group('action', () {
    testWidgets('renders the action label and key hint', (tester) {
      late BuildContext ctx;
      tester.pumpWidget(
        Toaster(child: Focus(autofocus: true, child: _Capture((c) => ctx = c))),
      );
      tester.render(size: const CellSize(40, 8));
      Toaster.show(
        ctx,
        'Deleted',
        action: ToastAction(
          label: 'Undo',
          key: KeyChord.alt.u,
          onPressed: () {},
        ),
      );
      tester.pump();
      final out = _screen(tester, cols: 40);
      expect(out.contains('Deleted'), isTrue);
      expect(out.contains('Alt+U'), isTrue, reason: 'key hint shown');
      expect(out.contains('Undo'), isTrue);
    });

    testWidgets('the hotkey fires onPressed and dismisses the toast', (tester) {
      late BuildContext ctx;
      var undone = 0;
      tester.pumpWidget(
        Toaster(child: Focus(autofocus: true, child: _Capture((c) => ctx = c))),
      );
      tester.render(size: const CellSize(40, 8));
      Toaster.show(
        ctx,
        'Deleted',
        action: ToastAction(
          label: 'Undo',
          key: KeyChord.alt.u,
          onPressed: () => undone++,
        ),
      );
      tester.pump();
      expect(_screen(tester, cols: 40).contains('Undo'), isTrue);

      tester.sendKey(const KeyEvent(char: 'u', modifiers: {KeyModifier.alt}));
      expect(undone, 1);
      tester.pump();
      expect(
        _screen(tester, cols: 40).contains('Undo'),
        isFalse,
        reason: 'toast dismissed after the action ran',
      );
    });
  });

  testWidgets('info severity stays neutral (uncolored)', (tester) {
    late BuildContext ctx;
    tester.pumpWidget(Toaster(child: _Capture((c) => ctx = c)));
    Toaster.show(ctx, 'plain');
    tester.pump();
    final buf = tester.render(size: const CellSize(20, 8));
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 20; c++) {
        if (buf.atColRow(c, r).grapheme == 'p' &&
            buf.atColRow(c + 1, r).grapheme == 'l') {
          expect(buf.atColRow(c, r).style.foreground, isNull);
          return;
        }
      }
    }
    fail('did not find the toast text');
  });
}
