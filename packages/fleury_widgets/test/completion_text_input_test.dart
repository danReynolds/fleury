import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _commands = [
  TextCompletionOption(label: 'checkout', detail: 'Switch branches'),
  TextCompletionOption(label: 'cherry-pick', detail: 'Apply commits'),
  TextCompletionOption(label: 'status'),
];

Iterable<TextCompletionOption> _commandProvider(TextCompletionRequest request) {
  final query = request.query.toLowerCase();
  return _commands.where((option) => option.label.startsWith(query));
}

String _screen(FleuryTester tester, {int cols = 32, int rows = 8}) =>
    tester.renderToString(size: CellSize(cols, rows), emptyMark: ' ');

/// Column span of the popup's rounded frame on the row it opens, in real
/// terminal cells (`right - left + 1` is its display width).
({int top, int left, int right}) _frame(CellBuffer buf) {
  for (var r = 0; r < buf.size.rows; r++) {
    for (var c = 0; c < buf.size.cols; c++) {
      if (buf.atColRow(c, r).grapheme != '\u256d') continue;
      for (var c2 = c + 1; c2 < buf.size.cols; c2++) {
        if (buf.atColRow(c2, r).grapheme == '\u256e') {
          return (top: r, left: c, right: c2);
        }
      }
    }
  }
  fail('no popup frame in the rendered buffer');
}

/// The text painted inside the frame on [row], as written (continuation cells
/// of a wide grapheme contribute nothing — their leading cell already did).
String _inside(
  CellBuffer buf,
  ({int top, int left, int right}) frame,
  int row,
) {
  final sb = StringBuffer();
  for (var c = frame.left + 1; c < frame.right; c++) {
    final cell = buf.atColRow(c, frame.top + row);
    if (cell.role == CellRole.leading) sb.write(cell.grapheme);
    if (cell.role == CellRole.empty) sb.write(' ');
  }
  return sb.toString().trim();
}

void main() {
  testWidgets('typing opens a provider-backed completion menu', (tester) {
    TextCompletionRequest? lastRequest;
    tester.pumpWidget(
      CompletionTextInput(
        provider: (request) {
          lastRequest = request;
          return _commandProvider(request);
        },
        autofocus: true,
      ),
    );

    tester.type('ch');

    final out = _screen(tester);
    expect(lastRequest?.query, 'ch');
    expect(lastRequest?.range, const TextRange(start: 0, end: 2));
    expect(out.contains('checkout'), isTrue);
    expect(out.contains('cherry-pick'), isTrue);
    expect(out.contains('status'), isFalse);
    expect(tester.overlay.entries.length, 2);
  });

  testWidgets('Down and Tab accept the selected completion', (tester) {
    final controller = TextEditingController();
    TextCompletionOption? accepted;
    tester.pumpWidget(
      CompletionTextInput(
        provider: _commandProvider,
        controller: controller,
        autofocus: true,
        onCompletionAccepted: (option) => accepted = option,
      ),
    );

    tester.type('ch');
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    tester.sendKey(const KeyEvent(KeyCode.tab));

    expect(controller.text, 'cherry-pick');
    expect(controller.selection, const TextSelection.collapsed(offset: 11));
    expect(accepted?.label, 'cherry-pick');
    expect(tester.overlay.entries.length, 1);

    tester.sendKey(
      const KeyEvent(KeyCode.char('z'), modifiers: {KeyModifier.ctrl}),
    );
    expect(controller.text, 'ch');
  });

  testWidgets('completion range targets the current word', (tester) {
    final controller = TextEditingController();
    tester.pumpWidget(
      CompletionTextInput(
        provider: _commandProvider,
        controller: controller,
        autofocus: true,
      ),
    );

    tester.type('git ch');
    tester.sendKey(const KeyEvent(KeyCode.tab));

    expect(controller.text, 'git checkout');
    expect(controller.selection, const TextSelection.collapsed(offset: 12));
  });

  testWidgets('Escape closes completion before calling onEscape', (tester) {
    var escapes = 0;
    tester.pumpWidget(
      CompletionTextInput(
        provider: _commandProvider,
        autofocus: true,
        onEscape: () => escapes += 1,
      ),
    );

    tester.type('ch');
    expect(tester.overlay.entries.length, 2);

    tester.sendKey(const KeyEvent(KeyCode.escape));
    expect(tester.overlay.entries.length, 1);
    expect(escapes, 0);

    tester.sendKey(const KeyEvent(KeyCode.escape));
    expect(escapes, 1);
  });

  testWidgets('Tab bubbles when the completion menu is closed', (tester) {
    final a = FocusNode(debugLabel: 'a');
    final b = FocusNode(debugLabel: 'b');
    tester.pumpWidget(
      FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CompletionTextInput(
              provider: _commandProvider,
              focusNode: a,
              autofocus: true,
            ),
            TextInput(focusNode: b),
          ],
        ),
      ),
    );
    tester.render(size: const CellSize(32, 4));

    tester.sendKey(const KeyEvent(KeyCode.tab));

    expect(b.hasFocus, isTrue);
  });

  testWidgets('forwards onChanged and text-field semantics', (tester) {
    final controller = TextEditingController();
    final changes = <String>[];
    tester.pumpWidget(
      CompletionTextInput(
        provider: _commandProvider,
        controller: controller,
        autofocus: true,
        onChanged: changes.add,
        semanticLabel: 'Command field',
        semanticState: const SemanticState({'fieldKind': 'command'}),
      ),
    );

    controller.value = TextEditingValue(
      text: 'ch',
      selection: const TextSelection.collapsed(offset: 2),
    );
    tester.pump();
    controller.caretOffset = 1;
    tester.pump();
    controller.caretOffset = 2;
    tester.pump();
    tester.sendKey(const KeyEvent(KeyCode.tab));

    expect(changes, ['ch', 'checkout']);
    final field = tester.semantics().single(
      role: SemanticRole.textField,
      label: 'Command field',
    );
    expect(field.value, 'checkout');
    expect(field.state['fieldKind'], 'command');
  });

  testWidgets('completion menu contributes semantic rows', (tester) {
    tester.pumpWidget(
      CompletionTextInput(provider: _commandProvider, autofocus: true),
    );

    tester.type('ch');
    _screen(tester);

    final menu = tester.semantics().single(
      role: SemanticRole.menu,
      label: 'Completions',
    );
    expect(menu.focused, isTrue);
    expect(menu.expanded, isTrue);
    expect(menu.actions, contains(SemanticAction.close));
    expect(menu.state.filterText, 'ch');
    expect(menu.state.collectionRowCount, 2);

    final selected = tester.semantics().single(
      role: SemanticRole.menuItem,
      label: 'checkout',
      selected: true,
    );
    expect(selected.hint, 'Switch branches');
    expect(selected.value, 'checkout');
    expect(selected.focused, isTrue);
    expect(selected.actions, contains(SemanticAction.activate));
    expect(selected.state.completionQuery, 'ch');
    expect(selected.state.menuItemPosition, 1);
    expect(selected.state.menuItemCount, 2);
  });

  testWidgets('semantic activation accepts a completion option', (
    tester,
  ) async {
    final controller = TextEditingController();
    TextCompletionOption? accepted;
    tester.pumpWidget(
      CompletionTextInput(
        provider: _commandProvider,
        controller: controller,
        autofocus: true,
        placeholder: 'Command',
        onCompletionAccepted: (option) => accepted = option,
      ),
    );

    tester.type('ch');
    _screen(tester);

    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.menuItem,
      label: 'cherry-pick',
    );

    expect(result.completed, isTrue);
    expect(controller.text, 'cherry-pick');
    expect(controller.selection, const TextSelection.collapsed(offset: 11));
    expect(accepted?.label, 'cherry-pick');
    expect(tester.semantics().where(role: SemanticRole.menu), isEmpty);
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.textField, label: 'Command')
          .value,
      'cherry-pick',
    );
  });

  testWidgets('semantic close hides completions without clearing text', (
    tester,
  ) async {
    final controller = TextEditingController();
    tester.pumpWidget(
      CompletionTextInput(
        provider: _commandProvider,
        controller: controller,
        autofocus: true,
        placeholder: 'Command',
      ),
    );

    tester.type('ch');
    _screen(tester);

    final result = await tester.invokeSemanticAction(
      SemanticAction.close,
      role: SemanticRole.menu,
      label: 'Completions',
    );

    expect(result.completed, isTrue);
    expect(controller.text, 'ch');
    expect(tester.semantics().where(role: SemanticRole.menu), isEmpty);
  });

  testWidgets('sanitizes unsafe completion labels and details', (tester) {
    tester.pumpWidget(
      CompletionTextInput(
        provider: (_) => const [
          TextCompletionOption(
            label: 'run\x1b]52;c;secret\x07cmd',
            detail: 'det\nail\x1b[2J',
          ),
        ],
        autofocus: true,
      ),
    );
    tester.type('r');
    final out = _screen(tester);
    expect(out, isNot(contains('secret')));
    expect(out, isNot(contains('\x1b[2J')));
    expect(out, contains(replacementCharacter));
    final row = tester.semantics().single(role: SemanticRole.menuItem);
    expect(row.label, contains(replacementCharacter));
    expect(row.label, isNot(contains('secret')));
  });

  // Popup geometry is display width, not code units: a BMP wide character
  // (CJK, Kana, Hangul, fullwidth) is one code unit but two cells. Sizing the
  // box by `String.length` under-measured it, so the first option wrapped into
  // the second option's row and the second was never rendered at all.
  group('option labels are measured by display width', () {
    const wide = [
      // 9 code units / 18 cells, and 6 units / 12 cells.
      TextCompletionOption(label: '日本語のファイル名'),
      TextCompletionOption(label: '設定ファイル'),
    ];

    testWidgets('the box fits the widest label and each option owns a row', (
      tester,
    ) {
      tester.pumpWidget(
        CompletionTextInput(provider: (_) => wide, autofocus: true),
      );
      tester.type('a');

      final buf = tester.render(size: const CellSize(40, 8));
      final frame = _frame(buf);
      expect(
        frame.right - frame.left + 1,
        22,
        reason: '18 cells for the widest label + 2 for the marker + 2 border',
      );
      expect(_inside(buf, frame, 1), '› 日本語のファイル名');
      expect(_inside(buf, frame, 2), '設定ファイル');
    });

    testWidgets('a label wider than the surface elides instead of wrapping', (
      tester,
    ) {
      tester.pumpWidget(
        CompletionTextInput(provider: (_) => wide, autofocus: true),
      );
      tester.type('a');

      // Far too narrow for an 18-cell label: the box clamps to the surface and
      // the label is cut with an ellipsis — it must not reflow into the row
      // that belongs to the next option.
      final buf = tester.render(size: const CellSize(14, 8));
      final frame = _frame(buf);
      expect(frame.right, lessThan(14));
      expect(_inside(buf, frame, 1), startsWith('› 日本'));
      expect(_inside(buf, frame, 1), endsWith('…'));
      expect(
        _inside(buf, frame, 2),
        startsWith('設定'),
        reason: 'the second option still gets its own row',
      );
    });
  });
}
