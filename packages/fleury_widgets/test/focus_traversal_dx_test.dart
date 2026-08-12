import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  testWidgets(
    'FleuryApp gives built-in controls sequential and spatial traversal',
    (tester) {
      final newFile = FocusNode(debugLabel: 'new file');
      final openFile = FocusNode(debugLabel: 'open file');
      final settings = FocusNode(debugLabel: 'settings');
      final refresh = FocusNode(debugLabel: 'refresh');
      final inspect = FocusNode(debugLabel: 'inspect');
      final publish = FocusNode(debugLabel: 'publish');

      Widget button(String label, FocusNode node, {bool autofocus = false}) =>
          SizedBox(
            width: 14,
            child: Button(
              label: label,
              focusNode: node,
              autofocus: autofocus,
              onPressed: () {},
            ),
          );

      tester.pumpWidget(
        FleuryApp(
          title: 'Focus DX',
          home: Padding(
            padding: const EdgeInsets.all(1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      button('New file', newFile, autofocus: true),
                      button('Open file', openFile),
                      button('Settings', settings),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      button('Refresh', refresh),
                      button('Inspect', inspect),
                      button('Publish', publish),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      tester.render(size: const CellSize(48, 8));

      expect(newFile.hasFocus, isTrue);
      expect(
        [newFile, openFile, settings].map((node) => node.rect!.size.cols),
        everyElement(14),
        reason: 'layout wrappers may normalize button widths',
      );
      expect(
        [newFile, openFile, settings].map((node) => node.rect!.top),
        orderedEquals([1, 2, 3]),
        reason: 'fixed-width composition must preserve each focus row',
      );
      // Arrow keys follow the two-dimensional layout without any explicit
      // FocusTraversalGroup in the screen.
      tester.sendKey(const KeyEvent(KeyCode.arrowRight));
      expect(refresh.hasFocus, isTrue);
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      expect(inspect.hasFocus, isTrue);
      tester.sendKey(const KeyEvent(KeyCode.arrowLeft));
      expect(openFile.hasFocus, isTrue);

      // Tab follows the painted row-major reading order across both panes.
      newFile.requestFocus();
      tester.sendKey(const KeyEvent(KeyCode.tab));
      expect(refresh.hasFocus, isTrue);
      tester.sendKey(const KeyEvent(KeyCode.tab));
      expect(openFile.hasFocus, isTrue);
      tester.sendKey(const KeyEvent(KeyCode.tab));
      expect(inspect.hasFocus, isTrue);
      tester.sendKey(const KeyEvent(KeyCode.tab));
      expect(settings.hasFocus, isTrue);
      tester.sendKey(const KeyEvent(KeyCode.tab));
      expect(publish.hasFocus, isTrue);
      tester.sendKey(const KeyEvent(KeyCode.tab));
      expect(newFile.hasFocus, isTrue, reason: 'Tab wraps within the route');

      tester.sendKey(
        const KeyEvent(KeyCode.tab, modifiers: {KeyModifier.shift}),
      );
      expect(publish.hasFocus, isTrue, reason: 'Shift+Tab wraps backward');
    },
  );
}
