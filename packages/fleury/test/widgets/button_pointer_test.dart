import 'package:fleury/fleury_core.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void pointer(
  FleuryTester tester,
  MouseEventKind kind,
  int col, {
  MouseButton button = MouseButton.left,
}) {
  tester.sendMouse(MouseEvent(kind: kind, button: button, col: col, row: 0));
  tester.pump();
}

const feedback = CellStyle.interactive(
  focused: CellStyle(underline: true),
  pressed: CellStyle(inverse: true),
);

void main() {
  testWidgets('moving a keyed button drops its captured press', (tester) {
    final key = GlobalKey();
    var activations = 0;
    final button = Button(
      key: key,
      text: 'Move',
      style: feedback,
      onPressed: () => activations++,
    );
    Widget tree(bool moved) => Column(
      children: [
        Row(
          children: [if (!moved) button, const SizedBox(width: 1, height: 1)],
        ),
        Row(children: [if (moved) button, const SizedBox(width: 1, height: 1)]),
      ],
    );
    tester.pumpWidget(tree(false));
    pointer(tester, MouseEventKind.down, 2);
    expect(tester.render().atColRow(2, 0).style.inverse, isTrue);
    tester.pumpWidget(tree(true));
    expect(tester.render().atColRow(2, 1).style.inverse, isFalse);
    tester.sendMouse(
      const MouseEvent(
        kind: MouseEventKind.up,
        button: MouseButton.left,
        col: 2,
        row: 1,
      ),
    );
    tester.pump();
    expect(activations, 0);
  });

  for (final appearance in ButtonAppearance.values) {
    for (final composed in [false, true]) {
      testWidgets(
        'press paints the full $appearance surface (child=$composed)',
        (tester) {
          var activations = 0;
          tester.pumpWidget(
            SizedBox(
              width: 14,
              child: Button(
                text: composed ? null : 'Open',
                child: composed ? const Text('Open') : null,
                appearance: appearance,
                style: feedback,
                onPressed: () => activations++,
              ),
            ),
          );
          pointer(tester, MouseEventKind.down, 2);
          final pressed = tester.render();
          for (var col = 0; col < 14; col++) {
            expect(pressed.atColRow(col, 0).style.inverse, isTrue);
            expect(pressed.atColRow(col, 0).style.underline, isTrue);
          }
          expect(activations, 0);
          pointer(tester, MouseEventKind.up, 2);
          expect(activations, 1);
          expect(tester.render().atColRow(2, 0).style.inverse, isFalse);
          expect(
            tester.semantics().single(role: SemanticRole.button).focused,
            isTrue,
          );
        },
      );
    }
  }

  for (final ending in [
    'outside',
    'movement',
    'cancel',
    'mismatched release',
  ]) {
    testWidgets('$ending clears pressed feedback without activation', (tester) {
      var activations = 0;
      tester.pumpWidget(
        Button(text: 'Open', style: feedback, onPressed: () => activations++),
      );
      pointer(tester, MouseEventKind.down, 2);
      expect(tester.render().atColRow(2, 0).style.inverse, isTrue);
      switch (ending) {
        case 'outside':
          pointer(tester, MouseEventKind.up, 30);
        case 'movement':
          pointer(tester, MouseEventKind.drag, 3);
        case 'cancel':
          pointer(tester, MouseEventKind.cancel, 0);
        case 'mismatched release':
          pointer(tester, MouseEventKind.up, 2, button: MouseButton.right);
      }
      expect(tester.render().atColRow(2, 0).style.inverse, isFalse);
      pointer(tester, MouseEventKind.up, 2);
      expect(activations, 0);
    });
  }

  testWidgets('disable and re-enable cannot revive a held press', (tester) {
    var primary = 0;
    var secondary = 0;
    Widget tree(bool enabled) => Button(
      text: 'Open',
      style: feedback,
      onPressed: enabled ? () => primary++ : null,
      onSecondaryPressed: () => secondary++,
    );
    tester.pumpWidget(tree(true));
    pointer(tester, MouseEventKind.down, 2);
    tester.pumpWidget(tree(false));
    final disabled = tester.render().atColRow(2, 0).style;
    expect(disabled.inverse, isFalse);
    expect(disabled.dim, isTrue);
    pointer(tester, MouseEventKind.down, 2, button: MouseButton.right);
    pointer(tester, MouseEventKind.up, 2, button: MouseButton.right);
    expect(
      tester.semantics().single(role: SemanticRole.button).focused,
      isFalse,
    );
    tester.pumpWidget(tree(true));
    expect(tester.render().atColRow(2, 0).style.inverse, isFalse);
    pointer(tester, MouseEventKind.up, 2);
    expect([primary, secondary], [0, 0]);
    pointer(tester, MouseEventKind.down, 2);
    pointer(tester, MouseEventKind.up, 2);
    expect(primary, 1);
  });

  testWidgets(
    'secondary click focuses without primary feedback or activation',
    (tester) async {
      var primary = 0;
      var secondary = 0;
      tester.pumpWidget(
        Button(
          text: 'Open',
          style: feedback,
          onPressed: () => primary++,
          onSecondaryPressed: () => secondary++,
        ),
      );
      pointer(tester, MouseEventKind.down, 2, button: MouseButton.right);
      expect(tester.render().atColRow(2, 0).style.inverse, isFalse);
      expect(secondary, 0);
      pointer(tester, MouseEventKind.up, 2, button: MouseButton.right);
      expect([primary, secondary], [0, 1]);
      final node = tester.semantics().single(role: SemanticRole.button);
      expect(node.focused, isTrue);
      tester.press(KeySequence.enter);
      tester.press(KeySequence.space);
      await tester.invokeSemanticAction(SemanticAction.activate, node: node);
      expect([primary, secondary], [3, 1]);
      expect(
        tester.render().atColRow(2, 0).style.inverse,
        isFalse,
        reason: 'keyboard and semantic actions do not latch a pointer press',
      );
      pointer(tester, MouseEventKind.down, 2, button: MouseButton.right);
      pointer(tester, MouseEventKind.up, 30, button: MouseButton.right);
      expect(secondary, 1);
      pointer(tester, MouseEventKind.down, 2, button: MouseButton.right);
      pointer(tester, MouseEventKind.cancel, 0);
      pointer(tester, MouseEventKind.up, 2, button: MouseButton.right);
      expect(secondary, 1);
    },
  );

  testWidgets('clipping a pressed control clears feedback when it returns', (
    tester,
  ) {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var activations = 0;
    tester.pumpWidget(
      SizedBox(
        width: 15,
        height: 1,
        child: ScrollView(
          controller: scroll,
          child: Column(
            children: [
              Button(
                text: 'Open',
                style: feedback,
                onPressed: () => activations++,
              ),
              const SizedBox(height: 3),
            ],
          ),
        ),
      ),
    );
    pointer(tester, MouseEventKind.down, 2);
    scroll.jumpTo(1);
    tester.pump();
    scroll.jumpTo(0);
    tester.pump();
    expect(tester.render().atColRow(2, 0).style.inverse, isFalse);
    pointer(tester, MouseEventKind.up, 2);
    expect(activations, 0);
  });
}
