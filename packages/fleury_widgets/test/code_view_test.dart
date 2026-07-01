import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _sampleCode =
    "import 'package:fleury/fleury.dart';\n"
    '\n'
    'final class DemoScreen extends StatelessWidget {\n'
    '\tconst DemoScreen();\n'
    '  // Builds source diagnostics.\n'
    '  @override\n'
    '  Widget build(BuildContext context) {\n'
    "    return const Text('ready');\n"
    '  }\n'
    '}\n';

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('CodeViewController lifecycle', () {
    test('dispose is idempotent and keeps final readable state', () {
      final controller = CodeViewController(selectedIndex: 2);

      controller.dispose();
      controller.dispose();

      expect(controller.selectedIndex, 2);
      expect(controller.visibleRange, isNull);
    });

    test('mutating after dispose throws a lifecycle error', () {
      final controller = CodeViewController()..dispose();

      const message = 'CodeViewController has been disposed.';
      expect(() => controller.selectedIndex = 1, _stateError(message));
      expect(() => controller.jumpToIndex(1), _stateError(message));
    });
  });

  test('parseCodeDocument tracks source shape and sanitized rows', () {
    final document = parseCodeDocument(
      _sampleCode,
      language: 'dart',
      filePath: 'lib/demo.dart',
      tabSize: 4,
    );

    expect(document.language, 'dart');
    expect(document.filePath, 'lib/demo.dart');
    expect(document.lineCount, 10);
    expect(document.nonEmptyLineCount, 9);
    expect(document.commentCount, 1);
    expect(document.blankCount, 1);
    expect(document.showLineNumbers, isTrue);
    expect(document.tabSize, 4);

    final import = document.lines[0];
    expect(import.kind, CodeLineKind.import);
    expect(import.lineNumber, 1);
    expect(import.displayText, startsWith(' 1 │ import'));

    final declaration = document.lines[2];
    expect(declaration.kind, CodeLineKind.declaration);
    expect(
      declaration.text,
      'final class DemoScreen extends StatelessWidget {',
    );

    final tabbed = document.lines[3];
    expect(tabbed.text, '    const DemoScreen();');
    expect(tabbed.indentation, 4);
    expect(tabbed.kind, CodeLineKind.keyword);
    expect(tabbed.outputSanitized, isTrue);

    final comment = document.lines[4];
    expect(comment.kind, CodeLineKind.comment);
    expect(comment.indentation, 2);
  });

  test('parseCodeDocument can omit rendered line numbers', () {
    final document = parseCodeDocument(
      'final answer = 42;',
      showLineNumbers: false,
    );

    expect(document.showLineNumbers, isFalse);
    expect(document.lines.single.displayText, 'final answer = 42;');
  });

  testWidgets('renders code rows with aggregate and row semantics', (tester) {
    tester.pumpWidget(
      CodeView(
        source: _sampleCode,
        label: 'Source fixture',
        language: 'dart',
        filePath: 'lib/demo.dart',
      ),
    );

    final output = tester.renderToString(
      size: const CellSize(80, 12),
      emptyMark: ' ',
    );
    expect(output, contains(' 1 │ import'));
    expect(output, contains(' 3 │ final class DemoScreen'));
    expect(output, contains(' 5 │   // Builds source diagnostics.'));

    final code = tester.semantics().single(
      role: SemanticRole.code,
      label: 'Source fixture',
      action: SemanticAction.copy,
    );
    expect(code.state.collectionRowCount, 10);
    expect(code.state['lineCount'], 10);
    expect(code.state['nonEmptyLineCount'], 9);
    expect(code.state['commentCount'], 1);
    expect(code.state['blankCount'], 1);
    expect(code.state['language'], 'dart');
    expect(code.state['filePath'], 'lib/demo.dart');
    expect(code.state['showLineNumbers'], isTrue);
    expect(code.state['tabSize'], 2);
    expect(code.state.selectedKey, 1);
    expect(code.state['selectedCodeLineKind'], 'import');

    final declaration = tester.semantics().single(
      role: SemanticRole.codeLine,
      label: 'final class DemoScreen extends StatelessWidget {',
    );
    expect(
      declaration.value,
      'final class DemoScreen extends StatelessWidget {',
    );
    expect(declaration.state['codeLineKind'], 'declaration');
    expect(declaration.state['lineNumber'], 3);
    expect(declaration.state['indentation'], 0);
    expect(declaration.state.outputSanitized, isFalse);

    final tabbed = tester.semantics().single(
      role: SemanticRole.codeLine,
      label: '  const DemoScreen();',
    );
    expect(tabbed.state.outputSanitized, isTrue);
  });

  group('copy/export', () {
    testWidgets('Ctrl+C copies the selected source line', (tester) async {
      final controller = CodeViewController(selectedIndex: 2);
      CodeViewCopyResult? copied;
      tester.pumpWidget(
        CodeView(
          source: _sampleCode,
          autofocus: true,
          controller: controller,
          copyOptions: const CodeViewCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(80, 12));
      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await Future<void>.delayed(Duration.zero);

      expect(
        tester.clipboard.readInProcess(),
        'final class DemoScreen extends StatelessWidget {',
      );
      expect(copied, isNotNull);
      expect(copied!.lineIndex, 2);
      expect(copied!.line.lineNumber, 3);
      expect(copied!.report.policy.name, 'inProcessOnly');

      final selected = tester.semantics().single(
        role: SemanticRole.codeLine,
        label: 'final class DemoScreen extends StatelessWidget {',
        selected: true,
        action: SemanticAction.copy,
      );
      expect(selected.state['lineNumber'], 3);
    });

    testWidgets('semantic focus and copy drive CodeView', (tester) async {
      final controller = CodeViewController(selectedIndex: 2);
      CodeViewCopyResult? copied;
      tester.pumpWidget(
        CodeView(
          source: _sampleCode,
          label: 'Source fixture',
          controller: controller,
          copyOptions: const CodeViewCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(80, 12));
      var result = await tester.invokeSemanticAction(
        SemanticAction.focus,
        role: SemanticRole.code,
        label: 'Source fixture',
      );
      expect(result.completed, isTrue);
      expect(
        tester.semantics().single(role: SemanticRole.code).focused,
        isTrue,
      );

      result = await tester.invokeSemanticAction(
        SemanticAction.copy,
        role: SemanticRole.codeLine,
        label: 'final class DemoScreen extends StatelessWidget {',
      );

      expect(result.completed, isTrue);
      expect(
        tester.clipboard.readInProcess(),
        'final class DemoScreen extends StatelessWidget {',
      );
      expect(copied?.line.lineNumber, 3);
      expect(copied?.report.result, ClipboardWriteResult.inProcessOnly);
    });

    testWidgets('semantic activate selects a source line', (tester) async {
      final controller = CodeViewController(selectedIndex: 0);
      tester.pumpWidget(
        CodeView(
          source: _sampleCode,
          label: 'Source fixture',
          controller: controller,
          copyOptions: const CodeViewCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
        ),
      );

      tester.render(size: const CellSize(80, 12));
      var line = tester.semantics().single(
        role: SemanticRole.codeLine,
        label: '  // Builds source diagnostics.',
        action: SemanticAction.activate,
      );
      expect(line.selected, isFalse);

      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.codeLine,
        label: '  // Builds source diagnostics.',
      );

      expect(result.completed, isTrue);
      expect(controller.selectedIndex, 4);

      tester.render(size: const CellSize(80, 12));
      line = tester.semantics().single(
        role: SemanticRole.codeLine,
        label: '  // Builds source diagnostics.',
        selected: true,
        action: SemanticAction.copy,
      );
      expect(line.state['lineNumber'], 5);

      final code = tester.semantics().single(
        role: SemanticRole.code,
        label: 'Source fixture',
      );
      expect(code.focused, isTrue);
      expect(code.state.selectedKey, 5);
      expect(code.state['selectedIndex'], 4);
      expect(code.state['selectedCodeLineKind'], 'comment');
    });

    test('exportCodeSelection supports whole-document copy mode', () {
      final document = parseCodeDocument(_sampleCode);

      expect(
        exportCodeSelection(
          document,
          lineIndex: 0,
          options: const CodeViewCopyOptions(mode: CodeViewCopyMode.document),
        ),
        _sampleCode.substring(0, _sampleCode.length - 1).replaceAll('\t', '  '),
      );
    });

    testWidgets('unsafe terminal payloads are collapsed before display/copy', (
      tester,
    ) async {
      final controller = CodeViewController(selectedIndex: 0);
      tester.pumpWidget(
        CodeView(
          autofocus: true,
          controller: controller,
          source: "final note = 'safe\x1b]52;c;secret\x07 payload';\n",
          copyOptions: const CodeViewCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
        ),
      );

      final output = tester.renderToString(
        size: const CellSize(80, 3),
        emptyMark: ' ',
      );
      expect(output, contains("final note = 'safe"));
      expect(output, isNot(contains('secret')));
      expect(output, isNot(contains('\x1b]52')));

      final unsafe = tester.semantics().single(
        role: SemanticRole.codeLine,
        selected: true,
      );
      expect(unsafe.label, contains("final note = 'safe"));
      expect(unsafe.label, isNot(contains('secret')));
      expect(unsafe.state.outputSanitized, isTrue);

      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await Future<void>.delayed(Duration.zero);

      expect(tester.clipboard.readInProcess(), contains("final note = 'safe"));
      expect(tester.clipboard.readInProcess(), isNot(contains('secret')));
      expect(tester.clipboard.readInProcess(), isNot(contains('\x1b]52')));
    });
  });
}
