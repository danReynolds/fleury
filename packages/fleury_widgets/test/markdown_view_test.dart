import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _sampleMarkdown =
    '# Fleury Guide\n'
    '\n'
    'Use **reactive** widgets with [docs](https://fleury.dev).\n'
    '- Semantic graph drives tests\n'
    '1. Copy safely\n'
    '> unsafe safe\x1b]52;c;secret\x07 payload stays inert\n'
    '---\n'
    '```dart\n'
    'final view = MarkdownView(markdown: guide);\n'
    '[hidden](https://fleury.dev/hidden)\n'
    '```\n';

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('MarkdownViewController lifecycle', () {
    test('dispose is idempotent and keeps final readable state', () {
      final controller = MarkdownViewController(selectedIndex: 5);

      controller.dispose();
      controller.dispose();

      expect(controller.selectedIndex, 5);
      expect(controller.visibleRange, isNull);
    });

    test('mutating after dispose throws a lifecycle error', () {
      final controller = MarkdownViewController()..dispose();

      const message = 'MarkdownViewController has been disposed.';
      expect(() => controller.selectedIndex = 1, _stateError(message));
      expect(() => controller.jumpToIndex(1), _stateError(message));
    });
  });

  test('parseMarkdownDocument tracks document shape and safe links', () {
    final document = parseMarkdownDocument(_sampleMarkdown);

    expect(document.blockCount, 9);
    expect(document.headingCount, 1);
    expect(document.listItemCount, 2);
    expect(document.linkCount, 1);
    expect(document.codeBlockCount, 1);
    expect(document.codeLineCount, 2);
    expect(document.source, isNot(contains('secret')));
    expect(document.source, isNot(contains('\x1b]52')));

    final heading = document.blocks[0];
    expect(heading.kind, MarkdownBlockKind.heading);
    expect(heading.headingLevel, 1);
    expect(heading.plainText, 'Fleury Guide');
    expect(heading.sourceText, '# Fleury Guide');

    final paragraph = document.blocks[2];
    expect(paragraph.kind, MarkdownBlockKind.paragraph);
    expect(paragraph.linkCount, 1);
    expect(paragraph.plainText, contains('docs (https://fleury.dev)'));

    final link = document.links.single;
    expect(link.index, 0);
    expect(link.blockIndex, 2);
    expect(link.text, 'docs');
    expect(link.url, 'https://fleury.dev');
    expect(link.safeScheme, isTrue);

    final unsafe = document.blocks[5];
    expect(unsafe.kind, MarkdownBlockKind.blockquote);
    expect(unsafe.sourceText, contains('> unsafe safe'));
    expect(unsafe.sourceText, isNot(contains('secret')));
    expect(unsafe.outputSanitized, isTrue);

    final hiddenLink = document.links
        .where((link) => link.url.contains('/hidden'))
        .toList();
    expect(hiddenLink, isEmpty, reason: 'links inside code fences stay inert');
  });

  test('plainText unwraps inline emphasis to its text, never literal \$1', () {
    // Regression: _plainInlineText stripped code/bold/strike/italic with
    // String.replaceAll(regExp, r'$1'). Dart (unlike JS) uses the replacement
    // string literally — no capture-group substitution — so every span became
    // the two characters "$1". plainText is the Semantics label of every block
    // and a public field, so agents and screen readers received "$1" in place
    // of the emphasized/code text.
    final document = parseMarkdownDocument(
      'Deploy **failed** on `prod` after a ~~clean~~ *rushed* _final_ push\n',
    );
    final paragraph = document.blocks.singleWhere(
      (block) => block.kind == MarkdownBlockKind.paragraph,
    );
    expect(
      paragraph.plainText,
      'Deploy failed on prod after a clean rushed final push',
    );
    expect(paragraph.plainText, isNot(contains(r'$1')));
  });

  testWidgets(
    'renders markdown rows with aggregate, block, and link semantics',
    (tester) {
      tester.pumpWidget(
        MarkdownView(markdown: _sampleMarkdown, semanticLabel: 'Launch notes'),
      );

      final output = tester.renderToString(
        size: const CellSize(90, 12),
        emptyMark: ' ',
      );
      expect(output, contains('Fleury Guide'));
      expect(output, contains('docs (https://fleury.dev)'));
      expect(output, contains('• Semantic graph drives tests'));
      expect(output, contains('│ unsafe safe'));
      expect(output, isNot(contains('secret')));
      expect(output, isNot(contains('\x1b]52')));

      final markdown = tester.semantics().single(
        role: SemanticRole.markdown,
        label: 'Launch notes',
        action: SemanticAction.copy,
      );
      expect(markdown.state.collectionRowCount, 9);
      expect(markdown.state['blockCount'], 9);
      expect(markdown.state['headingCount'], 1);
      expect(markdown.state['listItemCount'], 2);
      expect(markdown.state['linkCount'], 1);
      expect(markdown.state['codeBlockCount'], 1);
      expect(markdown.state['codeLineCount'], 2);
      expect(markdown.state.selectedKey, 0);
      expect(markdown.state['selectedMarkdownBlockKind'], 'heading');

      final block = tester.semantics().single(
        role: SemanticRole.markdownBlock,
        label: 'Semantic graph drives tests',
      );
      expect(block.value, '- Semantic graph drives tests');
      expect(block.state['markdownBlockKind'], 'bullet');
      expect(block.state['listDepth'], 0);
      expect(block.state.outputSanitized, isFalse);

      final link = tester.semantics().single(
        role: SemanticRole.link,
        label: 'docs',
      );
      expect(link.value, 'https://fleury.dev');
      expect(link.state['markdownBlockIndex'], 2);
      expect(link.state.capabilityResolution, 'disabledByPolicy');
      expect(link.state.activeFallback, 'visible URL');
      expect(link.state['safeLinkScheme'], isTrue);
    },
  );

  group('copy/export', () {
    testWidgets('Ctrl+C copies the selected sanitized markdown block', (
      tester,
    ) async {
      final controller = MarkdownViewController(selectedIndex: 5);
      MarkdownViewCopyResult? copied;
      tester.pumpWidget(
        MarkdownView(
          markdown: _sampleMarkdown,
          autofocus: true,
          controller: controller,
          copyOptions: const MarkdownViewCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(90, 12));
      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await Future<void>.delayed(Duration.zero);

      expect(tester.clipboard.readInProcess(), contains('> unsafe safe'));
      expect(tester.clipboard.readInProcess(), isNot(contains('secret')));
      expect(tester.clipboard.readInProcess(), isNot(contains('\x1b]52')));
      expect(copied, isNotNull);
      expect(copied!.blockIndex, 5);
      expect(copied!.block.kind, MarkdownBlockKind.blockquote);
      expect(copied!.report.policy.name, 'inProcessOnly');

      final selected = tester.semantics().single(
        role: SemanticRole.markdownBlock,
        selected: true,
        action: SemanticAction.copy,
      );
      expect(selected.state['markdownBlockKind'], 'blockquote');
      expect(selected.state.outputSanitized, isTrue);
    });

    testWidgets('semantic copy copies selected markdown block', (tester) async {
      final controller = MarkdownViewController(selectedIndex: 5);
      MarkdownViewCopyResult? copied;
      tester.pumpWidget(
        MarkdownView(
          markdown: _sampleMarkdown,
          controller: controller,
          copyOptions: const MarkdownViewCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(90, 12));
      final result = await tester.invokeSemanticAction(
        SemanticAction.copy,
        role: SemanticRole.markdownBlock,
        selected: true,
      );

      expect(result.completed, isTrue);
      expect(tester.clipboard.readInProcess(), contains('> unsafe safe'));
      expect(tester.clipboard.readInProcess(), isNot(contains('secret')));
      expect(copied?.block.kind, MarkdownBlockKind.blockquote);
      expect(copied?.report.result, ClipboardWriteResult.inProcessOnly);
    });

    testWidgets('semantic activate selects a markdown block', (tester) async {
      final controller = MarkdownViewController(selectedIndex: 0);
      tester.pumpWidget(
        MarkdownView(
          markdown: _sampleMarkdown,
          semanticLabel: 'Launch notes',
          controller: controller,
          copyOptions: const MarkdownViewCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
        ),
      );

      tester.render(size: const CellSize(90, 12));
      var block = tester.semantics().single(
        role: SemanticRole.markdownBlock,
        label: 'Semantic graph drives tests',
        action: SemanticAction.activate,
      );
      expect(block.selected, isFalse);

      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.markdownBlock,
        label: 'Semantic graph drives tests',
      );

      expect(result.completed, isTrue);
      expect(controller.selectedIndex, 3);

      tester.render(size: const CellSize(90, 12));
      block = tester.semantics().single(
        role: SemanticRole.markdownBlock,
        label: 'Semantic graph drives tests',
        selected: true,
        action: SemanticAction.copy,
      );
      expect(block.state['markdownBlockKind'], 'bullet');

      final markdown = tester.semantics().single(
        role: SemanticRole.markdown,
        label: 'Launch notes',
      );
      expect(markdown.focused, isTrue);
      expect(markdown.state.selectedKey, 3);
      expect(markdown.state['selectedIndex'], 3);
      expect(markdown.state['selectedMarkdownBlockKind'], 'bullet');
    });

    test('exportMarkdownSelection supports whole-document copy mode', () {
      final document = parseMarkdownDocument(_sampleMarkdown);

      final exported = exportMarkdownSelection(
        document,
        blockIndex: 0,
        options: const MarkdownViewCopyOptions(
          mode: MarkdownViewCopyMode.document,
        ),
      );

      expect(exported, startsWith('# Fleury Guide'));
      expect(exported, contains('```dart'));
      expect(exported, isNot(contains('secret')));
      expect(exported, isNot(contains('\x1b]52')));
    });
  });
}
