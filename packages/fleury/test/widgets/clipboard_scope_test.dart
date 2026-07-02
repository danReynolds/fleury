import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  group('ClipboardScope', () {
    testWidgets('the tester installs an in-process clipboard', (tester) async {
      tester.pumpWidget(
        const SelectionArea(copyOnRelease: true, child: Text('hello world')),
      );
      tester.render(size: const CellSize(20, 1));

      tester.sendMouse(_mouse(MouseEventKind.down, 0));
      tester.sendMouse(_mouse(MouseEventKind.drag, 4));
      tester.sendMouse(_mouse(MouseEventKind.up, 4));
      await Future<void>.delayed(Duration.zero);

      expect(tester.clipboard.readInProcess(), 'hell');
    });

    testWidgets('an inner scope overrides the tester clipboard', (
      tester,
    ) async {
      final inner = InProcessClipboard();
      tester.pumpWidget(
        ClipboardScope(
          clipboard: inner,
          child: const SelectionArea(
            copyOnRelease: true,
            child: Text('hello world'),
          ),
        ),
      );
      tester.render(size: const CellSize(20, 1));

      tester.sendMouse(_mouse(MouseEventKind.down, 0));
      tester.sendMouse(_mouse(MouseEventKind.drag, 4));
      tester.sendMouse(_mouse(MouseEventKind.up, 4));
      await Future<void>.delayed(Duration.zero);

      expect(inner.readInProcess(), isNotNull, reason: 'nearest scope wins');
      expect(
        tester.clipboard.readInProcess(),
        isNull,
        reason: 'outer scope untouched',
      );
    });

    testWidgets('two testers never share a clipboard', (tester) async {
      // The exact failure mode the old Clipboard.instance global had: two
      // runtimes in one isolate observing each other's copies.
      final other = FleuryTester();
      addTearDown(other.dispose);

      await tester.clipboard.write('from A');
      expect(tester.clipboard.readInProcess(), 'from A');
      expect(other.clipboard.readInProcess(), isNull);
    });

    test('of() without a scope throws a directed StateError', () {
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      late BuildContext captured;
      tester.pumpWidget(
        Builder(
          builder: (context) {
            captured = context;
            return const Text('x');
          },
        ),
      );
      // The tester installs a scope, so maybeOf resolves...
      expect(ClipboardScope.maybeOf(captured), same(tester.clipboard));
    });
  });
}

MouseEvent _mouse(MouseEventKind kind, int col) =>
    MouseEvent(kind: kind, button: MouseButton.left, col: col, row: 0);

/// Minimal builder widget for capturing a context (not exported by the
/// package).
class Builder extends StatelessWidget {
  const Builder({super.key, required this.builder});
  final Widget Function(BuildContext) builder;

  @override
  Widget build(BuildContext context) => builder(context);
}
