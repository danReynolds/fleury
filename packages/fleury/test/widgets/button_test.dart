// Basic actions require only fleury_core, including on a browser surface.
import 'package:fleury/fleury_core.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  test('requires exactly one of text and child', () {
    expect(() => Button(onPressed: null), throwsA(isA<AssertionError>()));
    expect(
      () => Button(text: 'Copy', child: const Text('Copy'), onPressed: null),
      throwsA(isA<AssertionError>()),
    );
    // An empty string is still an explicitly supplied value.
    expect(const Button(text: '', onPressed: null).text, '');
    expect(
      const Button(child: Text('Copy'), onPressed: null).child,
      isA<Text>(),
    );
  });

  testWidgets(
    'core button has styled spaces, semantics and keyboard activation',
    (tester) {
      var presses = 0;
      tester.pumpWidget(
        Button(text: 'New key', autofocus: true, onPressed: () => presses++),
      );
      final buffer = tester.render(size: const CellSize(14, 1));
      for (var col = 0; col < 11; col++) {
        expect(buffer.atColRow(col, 0).style.inverse, isTrue);
      }
      tester.press(.enter);
      tester.press(.space);
      expect(presses, 2);
      expect(
        tester.semantics().single(role: SemanticRole.button).label,
        'New key',
      );
    },
  );

  for (final composed in [false, true]) {
    testWidgets(
      'plain content is left aligned and styles full bounds ($composed)',
      (tester) {
        var presses = 0;
        tester.pumpWidget(
          SizedBox(
            width: 12,
            height: 1,
            child: Button(
              appearance: ButtonAppearance.plain,
              text: composed ? null : 'Copy',
              child: composed ? const Text('Copy') : null,
              semanticLabel: 'Copy',
              autofocus: true,
              onPressed: () => presses++,
            ),
          ),
        );
        final buffer = tester.render(size: const CellSize(12, 1));
        expect(tester.renderToString(emptyMark: ' ').trimRight(), 'Copy');
        for (var col = 0; col < 12; col++) {
          expect(buffer.atColRow(col, 0).style.inverse, isTrue);
        }
        tester.press(.enter);
        tester.press(.space);
        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.left,
            col: 11,
            row: 0,
          ),
        );
        tester.sendMouse(
          const MouseEvent(
            kind: MouseEventKind.up,
            button: MouseButton.left,
            col: 11,
            row: 0,
          ),
        );
        expect(presses, 3);
        expect(
          tester.semantics().single(role: SemanticRole.button).label,
          'Copy',
        );
      },
    );
  }

  testWidgets('Tab traverses core field and button in both directions', (
    tester,
  ) {
    final field = FocusNode();
    final button = FocusNode();
    addTearDown(field.dispose);
    addTearDown(button.dispose);
    tester.pumpWidget(
      FocusTraversalGroup(
        child: Column(
          children: [
            TextInput(focusNode: field, autofocus: true),
            Button(text: 'Save', focusNode: button, onPressed: () {}),
          ],
        ),
      ),
    );
    expect(field.hasFocus, isTrue);
    tester.press(.tab);
    expect(button.hasFocus, isTrue);
    tester.press(.shift.tab);
    expect(field.hasFocus, isTrue);
  });

  testWidgets('composed content retains styling and all activation paths', (
    tester,
  ) async {
    var presses = 0;
    tester.pumpWidget(
      Button(
        semanticLabel: 'Copy',
        autofocus: true,
        onPressed: () => presses++,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('[c] ', style: CellStyle(bold: true)),
            Text('Copy'),
          ],
        ),
      ),
    );
    final buffer = tester.render(size: const CellSize(20, 1));
    expect(tester.renderToString(emptyMark: ' ').trimRight(), '[ [c] Copy ]');
    expect(buffer.atColRow(2, 0).style.bold, isTrue);
    expect(buffer.atColRow(6, 0).style.bold, isNot(true));
    for (var col = 0; col < 12; col++) {
      expect(buffer.atColRow(col, 0).style.inverse, isTrue);
    }
    final node = tester.semantics().single(role: SemanticRole.button);
    expect(node.label, 'Copy');
    expect(
      node.descendants.where((child) => child.label != null),
      isEmpty,
      reason: 'the shortcut is only decoration',
    );
    tester.press(.enter);
    tester.press(.space);
    tester.sendMouse(
      const MouseEvent(
        kind: MouseEventKind.down,
        button: MouseButton.left,
        col: 3,
        row: 0,
      ),
    );
    tester.sendMouse(
      const MouseEvent(
        kind: MouseEventKind.up,
        button: MouseButton.left,
        col: 3,
        row: 0,
      ),
    );
    await tester.invokeSemanticAction(SemanticAction.activate, node: node);
    expect(presses, 4);
  });

  testWidgetsOnBothTextPolicies(
    'child text matches string framing at loose and tight widths',
    (tester, policy) {
      for (final label in ['Go', '界', 'Ω']) {
        for (final width in [null, 10, 11]) {
          Widget button({required bool composed}) {
            final button = Button(
              text: composed ? null : label,
              child: composed ? Text(label) : null,
              autofocus: true,
              onPressed: () {},
            );
            return width == null
                ? button
                : SizedBox(width: width, child: button);
          }

          tester.pumpWidget(button(composed: false));
          final expected = tester.renderToString(
            size: const CellSize(20, 1),
            emptyMark: ' ',
          );
          tester.pumpWidget(button(composed: true));
          expect(
            tester.renderToString(size: const CellSize(20, 1), emptyMark: ' '),
            expected,
          );
          final buffer = tester.render(size: const CellSize(20, 1));
          final naturalWidth =
              const DefaultWidthResolver().widthOfText(label, policy.widths) +
              4;
          for (var col = 0; col < (width ?? naturalWidth); col++) {
            expect(buffer.atColRow(col, 0).style.inverse, isTrue);
          }
        }
      }
    },
  );

  testWidgets('disabled child is muted, skipped by Tab and not actionable', (
    tester,
  ) async {
    final disabled = FocusNode();
    final enabled = FocusNode();
    addTearDown(disabled.dispose);
    addTearDown(enabled.dispose);
    tester.pumpWidget(
      FocusTraversalGroup(
        child: Column(
          children: [
            Button(
              child: const Text('Unavailable'),
              semanticLabel: 'Unavailable',
              autofocus: true,
              focusNode: disabled,
              onPressed: null,
            ),
            Button(text: 'Continue', focusNode: enabled, onPressed: () {}),
          ],
        ),
      ),
    );
    final buffer = tester.render(size: const CellSize(20, 2));
    expect(buffer.atColRow(2, 0).style.dim, isTrue);
    expect(disabled.hasFocus, isFalse);
    tester.press(.tab);
    expect(enabled.hasFocus, isTrue);
    final node = tester.semantics().single(
      role: SemanticRole.button,
      label: 'Unavailable',
    );
    expect(node.enabled, isFalse);
    expect(node.actions, isEmpty);
    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      node: node,
    );
    expect(result.status, SemanticActionInvocationStatus.disabled);
  });

  testWidgets('unnamed child retains its content semantics without brackets', (
    tester,
  ) {
    tester.pumpWidget(Button(child: const Text('Copy'), onPressed: () {}));
    final node = tester.semantics().single(role: SemanticRole.button);
    expect(node.children.single.label, 'Copy');
  });

  testWidgets('composed child state survives resizing and focus styling', (
    tester,
  ) {
    var mounts = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    tester.pumpWidget(
      Button(
        child: _MountedContent(() => mounts++),
        semanticLabel: 'Copy',
        focusNode: focus,
        onPressed: () {},
      ),
    );
    tester.render(size: const CellSize(20, 1));
    focus.requestFocus();
    tester.render(size: const CellSize(8, 1));
    tester.render(size: const CellSize(30, 1));
    expect(mounts, 1);
    expect(focus.hasFocus, isTrue);
  });
}

class _MountedContent extends StatefulWidget {
  const _MountedContent(this.onMount);
  final void Function() onMount;

  @override
  State<_MountedContent> createState() => _MountedContentState();
}

class _MountedContentState extends State<_MountedContent> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const Text('Copy');
}
