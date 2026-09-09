import 'package:fleury/fleury.dart';
import 'package:test/test.dart';
import '../support/harness.dart';

void main() {
  testWidgets(
    'native cursor follows controls, overrides, disable and removal',
    (tester) {
      final changes = <MouseCursor>[];
      Widget tree(Widget child) => LayoutBuilder(
        builder: (context, _) {
          PointerRouterScope.maybeOf(context)!.onCursorChanged = changes.add;
          return Align(alignment: Alignment.topLeft, child: child);
        },
      );
      void hover(int col, int row) => tester.sendMouse(
        MouseEvent(
          kind: MouseEventKind.moved,
          button: MouseButton.none,
          col: col,
          row: row,
        ),
      );
      tester.pumpWidget(tree(Button(label: 'Save', onPressed: () {})));
      hover(2, 0);
      expect(changes, [MouseCursor.pointer]);
      hover(3, 0);
      tester.pump();
      expect(
        changes,
        hasLength(1),
        reason: 'unchanged hover must not write OSC repeatedly',
      );
      tester.pumpWidget(tree(const Button(label: 'Save', onPressed: null)));
      expect(changes.last, MouseCursor.basic);
      tester.pumpWidget(tree(const SizedBox(width: 10, child: TextInput())));
      expect(changes.last, MouseCursor.text);
      tester.pumpWidget(tree(const Text('ordinary text')));
      expect(changes.last, MouseCursor.basic);
      tester.pumpWidget(
        tree(
          const MouseRegion(
            cursor: MouseCursor.resizeLeftRight,
            child: SizedBox(width: 10, height: 2),
          ),
        ),
      );
      expect(changes.last, MouseCursor.resizeLeftRight);
      hover(30, 5);
      expect(changes.last, MouseCursor.basic);
    },
  );

  testWidgets('native cursor respects foreground boundaries and cancellation', (
    tester,
  ) {
    final changes = <MouseCursor>[];
    late PointerRouter router;
    tester.pumpWidget(
      LayoutBuilder(
        builder: (context, _) {
          router = PointerRouterScope.maybeOf(context)!
            ..onCursorChanged = changes.add;
          return Stack(
            children: [
              const SizedBox(width: 20, height: 4),
              Positioned(
                left: 0,
                top: 0,
                width: 10,
                height: 1,
                child: Button(label: 'Behind', onPressed: () {}),
              ),
              const Positioned(
                left: 0,
                top: 0,
                width: 5,
                height: 1,
                child: MouseRegion(
                  cursor: MouseCursor.basic,
                  child: SizedBox(width: 5, height: 1),
                ),
              ),
            ],
          );
        },
      ),
    );
    void hover(int col) => tester.sendMouse(
      MouseEvent(
        kind: MouseEventKind.moved,
        button: MouseButton.none,
        col: col,
        row: 0,
      ),
    );
    hover(2);
    expect(changes, isEmpty, reason: 'foreground blocks the background button');
    hover(6);
    expect(changes.last, MouseCursor.pointer);
    router.cancel();
    expect(changes.last, MouseCursor.basic);
    hover(6);
    expect(changes.last, MouseCursor.pointer);
    router.abortFrame();
    expect(changes.last, MouseCursor.basic);
  });

  for (final ending in ['release', 'cancel', 'disable', 'remove', 'abort']) {
    testWidgets('captured cursor survives motion and ends on $ending', (
      tester,
    ) {
      final changes = <MouseCursor>[];
      late PointerRouter router;
      var updates = 0;
      Widget tree({bool enabled = true, bool removed = false}) => LayoutBuilder(
        builder: (context, _) {
          router = PointerRouterScope.maybeOf(context)!
            ..onCursorChanged = changes.add;
          return Align(
            alignment: Alignment.topLeft,
            child: removed
                ? const SizedBox(width: 2, height: 2)
                : MouseRegion(
                    cursor: enabled
                        ? MouseCursor.resizeLeftRight
                        : MouseCursor.basic,
                    child: GestureDetector(
                      onDragUpdate: enabled ? (_) => updates++ : null,
                      child: const SizedBox(width: 2, height: 2),
                    ),
                  ),
          );
        },
      );
      void send(MouseEventKind kind, int col) => tester.sendMouse(
        MouseEvent(kind: kind, button: MouseButton.left, col: col, row: 0),
      );
      tester.pumpWidget(tree());
      send(MouseEventKind.down, 1);
      send(MouseEventKind.drag, 8);
      tester.pump();
      expect(updates, 1);
      expect(changes, [MouseCursor.resizeLeftRight]);
      switch (ending) {
        case 'release':
          send(MouseEventKind.up, 8);
        case 'cancel':
          router.cancel();
        case 'disable':
          tester.pumpWidget(tree(enabled: false));
        case 'remove':
          tester.pumpWidget(tree(removed: true));
        case 'abort':
          router.abortFrame();
      }
      expect(changes.last, MouseCursor.basic);
    });
  }
}
