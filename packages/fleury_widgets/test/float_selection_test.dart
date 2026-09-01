// Chrome text in a float is not copyable content.
//
// `runApp` wraps the app root — and only the app root — in
// `DefaultRootSelection`, so every rendered Text is drag-selectable and
// Ctrl+C-copyable by default. A float's own text is chrome, not content: a
// drag over a tooltip, a menu row, or a which-key hint must not put
// "f  Find file" on the user's clipboard.
//
// Six of these floats mount through an `OverlayEntry`, which sits OUTSIDE the
// root selection scope — so they were safe by accident of where they mount,
// not by anything they say. `WhichKey` was the counter-example: it renders its
// popup INLINE, inside the app subtree, and its chrome really was copyable.
// Each float now states the property itself with `SelectionArea.disabled`,
// which is what this file pins — for the mounted-outside ones too, so the
// property survives a float that later moves in-tree.

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _size = CellSize(44, 16);

MouseEvent _mouse(MouseEventKind kind, int col, int row) => MouseEvent(
  kind: kind,
  button: MouseButton.left,
  col: col,
  row: row,
);

/// Drags across the whole rendered screen (top-left to bottom-right) and
/// copies. A selection that swallows the float's chrome shows up in the
/// clipboard; one that skips it does not.
String? _dragAllAndCopy(FleuryTester tester) {
  tester.render(size: _size);
  tester.sendMouse(_mouse(MouseEventKind.down, 0, 0));
  tester.sendMouse(_mouse(MouseEventKind.drag, _size.cols - 1, _size.rows - 1));
  tester.sendMouse(_mouse(MouseEventKind.up, _size.cols - 1, _size.rows - 1));
  tester.press(KeySequence.ctrl.c);
  return tester.clipboard.readInProcess();
}

void _expectChromeNotCopied(
  FleuryTester tester, {
  required String chrome,
  required String showing,
}) {
  final screen = tester.renderToString(size: _size, emptyMark: ' ');
  expect(screen, contains(showing), reason: 'the float is actually open');
  final copied = _dragAllAndCopy(tester);
  expect(
    copied ?? '',
    isNot(contains(chrome)),
    reason:
        'chrome text must never reach the clipboard.\n'
        'Copied:\n$copied\nScreen:\n$screen',
  );
}

void _noop() {}

/// Hands a test a BuildContext below the widget under test.
class _Capture extends StatelessWidget {
  const _Capture(this.sink);
  final void Function(BuildContext) sink;
  @override
  Widget build(BuildContext context) {
    sink(context);
    return const Text('body');
  }
}

void main() {
  testWidgets('a WhichKey popup is not copyable chrome', (tester) {
    // The only float here that renders INLINE (a Stack in the app subtree),
    // so it inherits the root selection scope unless it opts out. This is the
    // case that was really leaking "f  Find file" into the clipboard.
    tester.pumpWidget(
      WhichKey(
        showDelay: Duration.zero,
        child: KeyBindings(
          bindings: [
            KeyBinding(
              KeySequence.space.f,
              label: 'Find file',
              onTrigger: (_) {},
            ),
          ],
          child: const Focus(autofocus: true, child: Text('body')),
        ),
      ),
    );
    tester.render(size: _size);
    tester.press(KeySequence.space); // leave the sequence pending
    _expectChromeNotCopied(tester, chrome: 'Find file', showing: 'Find file');
  });

  testWidgets('a Tooltip is not copyable chrome', (tester) {
    tester.pumpWidget(
      const Tooltip(
        message: 'Save to disk',
        child: Focus(autofocus: true, child: Text('Save')),
      ),
    );
    _expectChromeNotCopied(tester, chrome: 'Save to disk', showing: 'Save to');
  });

  testWidgets('a Toaster toast is not copyable chrome', (tester) {
    late BuildContext ctx;
    tester.pumpWidget(Toaster(child: _Capture((c) => ctx = c)));
    tester.render(size: _size);
    Toaster.show(ctx, 'Build finished');
    tester.pump();
    _expectChromeNotCopied(
      tester,
      chrome: 'Build finished',
      showing: 'Build finished',
    );
  });

  testWidgets('an open Select list is not copyable chrome', (tester) {
    tester.pumpWidget(
      Select<String>(
        options: const [
          SelectOption(value: 'a', label: 'Alpha'),
          SelectOption(value: 'b', label: 'Beta'),
        ],
        value: 'a',
        onChanged: (_) {},
        autofocus: true,
      ),
    );
    tester.render(size: _size);
    tester.press(KeySequence.enter); // open the dropdown
    _expectChromeNotCopied(tester, chrome: 'Beta', showing: 'Beta');
  });

  testWidgets('an open Menu is not copyable chrome', (tester) {
    tester.pumpWidget(
      Menu(
        trigger: const Text('Edit'),
        autofocus: true,
        items: [MenuItem(label: 'Duplicate', onSelect: _noop)],
      ),
    );
    tester.render(size: _size);
    tester.press(KeySequence.enter); // open the menu
    _expectChromeNotCopied(tester, chrome: 'Duplicate', showing: 'Duplicate');
  });

  testWidgets('a CommandPalette is not copyable chrome', (tester) {
    tester.pumpWidget(
      const CommandPalette(
        commands: [Command(label: 'Open File', onInvoke: _noop)],
        width: 24,
        maxVisible: 3,
      ),
    );
    _expectChromeNotCopied(tester, chrome: 'Open File', showing: 'Open File');
  });

  testWidgets('a completion popup is not copyable chrome', (tester) {
    tester.pumpWidget(
      CompletionTextInput(
        provider: (request) => const [
          TextCompletionOption(label: 'checkout', detail: 'Switch'),
        ],
        autofocus: true,
      ),
    );
    tester.render(size: _size);
    tester.type('c');
    _expectChromeNotCopied(tester, chrome: 'checkout', showing: 'checkout');
  });
}
