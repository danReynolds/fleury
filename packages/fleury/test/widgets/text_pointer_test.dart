import 'package:fleury/fleury.dart';
import 'package:test/test.dart';
import '../support/harness.dart';
import 'pointer_contract_test.dart' show at, click;

void main() {
  for (final app in [false, true]) {
    testWidgets(
      'click places the caret before focusing (${app ? 'app' : 'bare'})',
      (tester) {
        final a = FocusNode();
        final b = FocusNode();
        final controller = TextEditingController(text: 'abcdef');
        addTearDown(a.dispose);
        addTearDown(b.dispose);
        addTearDown(controller.dispose);
        final fields = Column(
          children: [
            TextInput(focusNode: a, autofocus: true),
            TextInput(focusNode: b, controller: controller),
          ],
        );
        tester.pumpWidget(
          app ? FleuryApp(title: 'Fields', home: fields) : fields,
        );
        click(tester, b.rect!.left + 2, b.rect!.top);
        expect(b.hasFocus, isTrue);
        expect(controller.caretOffset, 2);
        tester.type('X');
        expect(controller.text, 'abXcdef');
      },
    );
  }

  testWidgets(
    'single-line drag, Shift-click, and cancellation preserve an editing selection',
    (tester) {
      final controller = TextEditingController(text: 'abcdef');
      addTearDown(controller.dispose);
      tester.pumpWidget(TextInput(controller: controller));
      tester.sendMouse(at(MouseEventKind.down, 1, 0));
      tester.sendMouse(at(MouseEventKind.drag, 4, 0));
      tester.sendMouse(at(MouseEventKind.up, 4, 0));
      expect(controller.selectedText, 'bcd');
      click(tester, 5, 0, shift: true);
      expect(controller.selectedText, 'bcde');
      tester.sendMouse(at(MouseEventKind.down, 2, 0));
      tester.sendMouse(at(MouseEventKind.drag, 4, 0));
      tester.sendMouse(at(MouseEventKind.cancel, 0, 0));
      tester.sendMouse(at(MouseEventKind.drag, 6, 0));
      expect(controller.selectedText, 'cd');
    },
  );

  testWidgets('double click selects a word and triple click selects its line', (
    tester,
  ) {
    final controller = TextEditingController(text: 'hello world\nnext');
    addTearDown(controller.dispose);
    tester.pumpWidget(
      SizedBox(width: 20, height: 3, child: TextArea(controller: controller)),
    );
    click(tester, 2, 0);
    click(tester, 2, 0);
    expect(controller.selectedText, 'hello');
    click(tester, 2, 0);
    expect(controller.selectedText, 'hello world\n');
  });

  testWidgets('multi-line drag uses the actual line and scroll offset', (
    tester,
  ) {
    final controller = TextEditingController(
      text: 'first\nsecond\nthird\nfourth',
    );
    addTearDown(controller.dispose);
    tester.pumpWidget(
      SizedBox(width: 12, height: 2, child: TextArea(controller: controller)),
    );
    // The last two lines are visible while the initial caret is at the end.
    tester.sendMouse(at(MouseEventKind.down, 1, 0));
    tester.pump();
    expect(controller.caretOffset, 14);
    tester.sendMouse(at(MouseEventKind.drag, 3, 1));
    tester.sendMouse(at(MouseEventKind.up, 3, 1));
    expect(controller.selectedText, 'hird\nfou');
  });

  testWidgets('wide and combining graphemes map to whole boundaries', (tester) {
    final controller = TextEditingController(text: 'a界e\u0301z');
    addTearDown(controller.dispose);
    tester.pumpWidget(TextInput(controller: controller));
    click(tester, 2, 0);
    expect(
      controller.caretOffset,
      2,
      reason: 'second cell of 界 selects its end',
    );
    click(tester, 4, 0);
    expect(
      controller.caretOffset,
      4,
      reason: 'the combining mark stays with e',
    );
  });

  testWidgets(
    'horizontal scroll and obscured glyphs determine click positions',
    (tester) {
      final controller = TextEditingController(text: 'a界bcd');
      addTearDown(controller.dispose);
      tester.pumpWidget(
        SizedBox(
          width: 4,
          child: TextInput(controller: controller, obscureText: true),
        ),
      );
      click(tester, 0, 0);
      expect(
        controller.caretOffset,
        2,
        reason:
            'five one-cell masking glyphs plus the trailing caret scroll by two',
      );
    },
  );

  for (final readOnly in [false, true]) {
    testWidgets('${readOnly ? 'read-only' : 'disabled'} field pointer policy', (
      tester,
    ) {
      final controller = TextEditingController(text: 'abcdef');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      tester.pumpWidget(
        TextInput(
          controller: controller,
          focusNode: focus,
          enabled: readOnly,
          readOnly: readOnly,
        ),
      );
      click(tester, 2, 0);
      expect(controller.caretOffset, readOnly ? 2 : 6);
      expect(focus.hasFocus, readOnly);
      tester.type('X');
      expect(controller.text, 'abcdef');
    });
  }

  testWidgets(
    'TextInput fills finite width and retains intrinsic width in a Row',
    (tester) {
      final bounded = FocusNode();
      final intrinsic = FocusNode();
      addTearDown(bounded.dispose);
      addTearDown(intrinsic.dispose);
      tester.pumpWidget(
        SizedBox(
          width: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextInput(focusNode: bounded),
              Row(
                children: [
                  const Text('Name: '),
                  TextInput(focusNode: intrinsic),
                ],
              ),
            ],
          ),
        ),
      );
      expect(bounded.rect!.size.cols, 20);
      expect(intrinsic.rect!.size.cols, 1);
      click(tester, 12, 0);
      expect(bounded.hasFocus, isTrue);
    },
  );
}
