import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

const _sampleDiff = '''
diff --git a/lib/app.dart b/lib/app.dart
index 111..222 100644
--- a/lib/app.dart
+++ b/lib/app.dart
@@ -1,4 +1,5 @@
 void main() {
-  print("old");
+  print("new");
+  run();
 }
\\ No newline at end of file
''';

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('DiffViewController lifecycle', () {
    test('dispose is idempotent and keeps final readable state', () {
      final controller = DiffViewController(selectedIndex: 7);

      controller.dispose();
      controller.dispose();

      expect(controller.selectedIndex, 7);
      expect(controller.visibleRange, isNull);
    });

    test('mutating after dispose throws a lifecycle error', () {
      final controller = DiffViewController()..dispose();

      const message = 'DiffViewController has been disposed.';
      expect(() => controller.selectedIndex = 1, _stateError(message));
      expect(() => controller.jumpToIndex(1), _stateError(message));
    });
  });

  test('parseUnifiedDiff tracks files, hunks, line numbers, and stats', () {
    final document = parseUnifiedDiff(_sampleDiff);

    expect(document.fileCount, 1);
    expect(document.hunkCount, 1);
    expect(document.additionCount, 2);
    expect(document.deletionCount, 1);
    expect(document.rows, hasLength(11));

    final added = document.rows.singleWhere(
      (row) => row.text == '+  print("new");',
    );
    expect(added.kind, DiffLineKind.addition);
    expect(added.newLine, 2);
    expect(added.oldLine, isNull);
    expect(added.hunkIndex, 0);
    expect(added.oldPath, 'lib/app.dart');
    expect(added.newPath, 'lib/app.dart');

    final deleted = document.rows.singleWhere(
      (row) => row.text == '-  print("old");',
    );
    expect(deleted.kind, DiffLineKind.deletion);
    expect(deleted.oldLine, 2);
    expect(deleted.newLine, isNull);
  });

  testWidgets('renders an old/new line-number gutter by default', (tester) {
    tester.pumpWidget(
      DiffView(diff: '@@ -1,2 +1,2 @@\n context\n-old\n+new\n', label: 'Patch'),
    );
    final output = tester.renderToString(
      size: const CellSize(40, 8),
      emptyMark: ' ',
    );
    // Context line carries both numbers; the gutter separator is present.
    expect(output, contains('1 1 │  context'));
    expect(output, contains('│ '));
    // The deletion has an old number but no new; the addition the reverse.
    expect(output, contains('2   │ -old'));
    expect(output, contains('  2 │ +new'));
  });

  testWidgets('renders diff rows with aggregate and row semantics', (tester) {
    tester.pumpWidget(DiffView(diff: _sampleDiff, label: 'Patch'));

    final output = tester.renderToString(
      size: const CellSize(80, 12),
      emptyMark: ' ',
    );
    expect(output, contains('diff --git a/lib/app.dart b/lib/app.dart'));
    expect(output, contains('-  print("old");'));
    expect(output, contains('+  print("new");'));

    final diff = tester.semantics().single(
      role: SemanticRole.diff,
      label: 'Patch',
      action: SemanticAction.copy,
    );
    expect(diff.state.collectionRowCount, 11);
    expect(diff.state['fileCount'], 1);
    expect(diff.state['hunkCount'], 1);
    expect(diff.state['additionCount'], 2);
    expect(diff.state['deletionCount'], 1);
    expect(diff.state.selectedKey, 0);
    expect(diff.state['selectedDiffKind'], 'fileHeader');

    final added = tester.semantics().single(
      role: SemanticRole.diffLine,
      label: '+  print("new");',
    );
    expect(added.value, '+  print("new");');
    expect(added.state['diffKind'], 'addition');
    expect(added.state['newLine'], 2);
    expect(added.state['filePath'], 'lib/app.dart');
    expect(added.state.outputSanitized, isFalse);
  });

  group('copy/export', () {
    testWidgets('Ctrl+C copies the selected hunk when configured', (
      tester,
    ) async {
      final controller = DiffViewController(selectedIndex: 7);
      DiffViewCopyResult? copied;
      tester.pumpWidget(
        DiffView(
          diff: _sampleDiff,
          autofocus: true,
          controller: controller,
          copyOptions: const DiffViewCopyOptions(
            mode: DiffViewCopyMode.hunk,
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
        '@@ -1,4 +1,5 @@\n'
        ' void main() {\n'
        '-  print("old");\n'
        '+  print("new");\n'
        '+  run();\n'
        ' }\n'
        r'\ No newline at end of file',
      );
      expect(copied, isNotNull);
      expect(copied!.row.text, '+  print("new");');
      expect(copied!.report.policy.name, 'inProcessOnly');

      final selected = tester.semantics().single(
        role: SemanticRole.diffLine,
        label: '+  print("new");',
        selected: true,
        action: SemanticAction.copy,
      );
      expect(selected.state['newLine'], 2);
    });

    testWidgets('semantic copy copies the selected diff hunk', (tester) async {
      final controller = DiffViewController(selectedIndex: 7);
      DiffViewCopyResult? copied;
      tester.pumpWidget(
        DiffView(
          diff: _sampleDiff,
          controller: controller,
          copyOptions: const DiffViewCopyOptions(
            mode: DiffViewCopyMode.hunk,
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(80, 12));
      final result = await tester.invokeSemanticAction(
        SemanticAction.copy,
        role: SemanticRole.diffLine,
        label: '+  print("new");',
      );

      expect(result.completed, isTrue);
      expect(tester.clipboard.readInProcess(), contains('@@ -1,4 +1,5 @@'));
      expect(tester.clipboard.readInProcess(), contains('+  print("new");'));
      expect(copied?.row.text, '+  print("new");');
      expect(copied?.report.result, ClipboardWriteResult.inProcessOnly);
    });

    testWidgets('semantic activate selects a diff row', (tester) async {
      final controller = DiffViewController(selectedIndex: 0);
      tester.pumpWidget(
        DiffView(
          diff: _sampleDiff,
          label: 'Patch',
          controller: controller,
          copyOptions: const DiffViewCopyOptions(
            mode: DiffViewCopyMode.hunk,
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
        ),
      );

      tester.render(size: const CellSize(80, 12));
      var row = tester.semantics().single(
        role: SemanticRole.diffLine,
        label: '+  run();',
        action: SemanticAction.activate,
      );
      expect(row.selected, isFalse);

      final result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.diffLine,
        label: '+  run();',
      );

      expect(result.completed, isTrue);
      expect(controller.selectedIndex, 8);

      tester.render(size: const CellSize(80, 12));
      row = tester.semantics().single(
        role: SemanticRole.diffLine,
        label: '+  run();',
        selected: true,
        action: SemanticAction.copy,
      );
      expect(row.state['newLine'], 3);

      final diff = tester.semantics().single(
        role: SemanticRole.diff,
        label: 'Patch',
      );
      expect(diff.focused, isTrue);
      expect(diff.state.selectedKey, 8);
      expect(diff.state['selectedIndex'], 8);
      expect(diff.state['selectedDiffKind'], 'addition');
      expect(diff.state['selectedNewLine'], 3);
    });

    testWidgets('unsafe terminal payloads are collapsed before display/copy', (
      tester,
    ) async {
      final controller = DiffViewController(selectedIndex: 4);
      tester.pumpWidget(
        DiffView(
          autofocus: true,
          controller: controller,
          diff:
              '--- a/a.txt\n'
              '+++ b/a.txt\n'
              '@@ -1 +1 @@\n'
              '-safe\n'
              '+bad\x1b]52;c;secret\x07 payload\n',
          copyOptions: const DiffViewCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
        ),
      );

      final output = tester.renderToString(
        size: const CellSize(80, 6),
        emptyMark: ' ',
      );
      expect(output, contains('+bad'));
      expect(output, isNot(contains('secret')));
      expect(output, isNot(contains('\x1b]52')));

      final unsafe = tester.semantics().single(
        role: SemanticRole.diffLine,
        selected: true,
      );
      expect(unsafe.label, contains('+bad'));
      expect(unsafe.label, isNot(contains('secret')));
      expect(unsafe.state.outputSanitized, isTrue);

      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await Future<void>.delayed(Duration.zero);

      expect(tester.clipboard.readInProcess(), contains('+bad'));
      expect(tester.clipboard.readInProcess(), isNot(contains('secret')));
      expect(tester.clipboard.readInProcess(), isNot(contains('\x1b]52')));
    });
  });
}
