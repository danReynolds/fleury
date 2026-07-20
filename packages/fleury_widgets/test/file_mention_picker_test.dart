import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

List<FileMentionEntry> _entries() => const [
  FileMentionEntry(
    path: 'lib/main.dart',
    label: 'Main entrypoint',
    detail: 'App bootstrap',
    language: 'dart',
    line: 12,
    mentionText: '@lib/main.dart:12',
  ),
  FileMentionEntry(
    path: 'docs/launch.md',
    label: 'Launch plan',
    detail: 'Release notes',
    language: 'markdown',
  ),
  FileMentionEntry(
    path: 'packages/fleury_widgets/lib/src/search_panel.dart',
    label: 'SearchPanel',
    detail: 'Search result surface',
    language: 'dart',
  ),
];

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('FileMentionPicker', () {
    group('controller lifecycle', () {
      test('dispose is idempotent and keeps final readable state', () {
        final controller = FileMentionPickerController(selectedIndex: 2);

        controller.dispose();
        controller.dispose();

        expect(controller.selectedIndex, 2);
        expect(controller.visibleRange, isNull);
      });

      test('mutating after dispose throws a lifecycle error', () {
        final controller = FileMentionPickerController()..dispose();

        const message = 'FileMentionPickerController has been disposed.';
        expect(() => controller.selectedIndex = 1, _stateError(message));
        expect(() => controller.jumpToIndex(1), _stateError(message));
      });
    });

    test('buildFileMentionOrder ranks by exact, prefix, contains, fuzzy', () {
      final order = buildFileMentionOrder(_entries(), query: 'docs/launch');
      expect(order, [1]);

      expect(buildFileMentionOrder(_entries(), query: 'src panel'), [2]);
    });

    test('exportFileMention sanitizes controls and respects copy options', () {
      final text = exportFileMention(
        const FileMentionEntry(
          path: 'lib/unsafe.dart',
          label: 'bad\x1b]52;c;secret\x07',
          detail: 'two\nlines',
          mentionText: '@lib/unsafe.dart',
        ),
        options: const FileMentionCopyOptions(includeDetail: true),
      );

      expect(text, '@lib/unsafe.dart | two lines');
      expect(text, isNot(contains('secret')));
      expect(text, isNot(contains('\x1b]52')));

      expect(
        exportFileMention(
          _entries().first,
          options: const FileMentionCopyOptions(copyMentionText: false),
        ),
        'lib/main.dart',
      );
    });

    testWidgets('filters, picks, and exposes file mention semantics', (
      tester,
    ) async {
      FileMentionPickResult? picked;
      tester.pumpWidget(
        FileMentionPicker(
          semanticLabel: 'Composer mentions',
          entries: _entries(),
          autofocus: true,
          onPick: (result) => picked = result,
        ),
      );

      tester.type('docs/launch');
      tester.pump();
      tester.render(size: const CellSize(90, 6));
      tester.sendKey(const KeyEvent(KeyCode.enter));

      expect(picked?.entry.path, 'docs/launch.md');
      expect(picked?.entryIndex, 1);
      expect(picked?.viewIndex, 0);

      final picker = tester.semantics().single(
        role: SemanticRole.fileMentionPicker,
        label: 'Composer mentions',
      );
      expect(picker.state.filterText, 'docs/launch');
      expect(picker.state['totalMentionCount'], 3);
      expect(picker.state['filteredMentionCount'], 1);
      expect(picker.state.selectedFilePath, 'docs/launch.md');

      final row = tester.semantics().single(
        role: SemanticRole.fileMention,
        label: 'Launch plan',
        value: '@docs/launch.md',
      );
      expect(row.selected, isTrue);
      expect(row.actions, contains(SemanticAction.activate));
      expect(row.state.filePath, 'docs/launch.md');
      expect(row.state.fileKind, 'file');
      expect(row.state.fileLanguage, 'markdown');
      expect(row.state.mentionText, '@docs/launch.md');

      final fallback = tester.accessibilitySnapshot().single(
        role: SemanticRole.fileMention,
        label: 'Launch plan',
      );
      expect(
        fallback.states,
        contains(
          'file mention path docs/launch.md, kind file, language markdown, '
          'mention @docs/launch.md',
        ),
      );
    });

    testWidgets('semantic navigate and row activation focus mentions', (
      tester,
    ) async {
      final controller = FileMentionPickerController();
      FileMentionPickResult? picked;
      tester.pumpWidget(
        FileMentionPicker(
          semanticLabel: 'Composer mentions',
          entries: _entries(),
          controller: controller,
          onPick: (result) => picked = result,
        ),
      );

      tester.render(size: const CellSize(90, 7));
      var picker = tester.semantics().single(
        role: SemanticRole.fileMentionPicker,
        label: 'Composer mentions',
        action: SemanticAction.focus,
      );
      expect(picker.focused, isFalse);
      expect(picker.actions, contains(SemanticAction.navigate));

      var result = await tester.invokeSemanticAction(
        SemanticAction.navigate,
        role: SemanticRole.fileMentionPicker,
        label: 'Composer mentions',
      );
      expect(result.completed, isTrue);

      tester.render(size: const CellSize(90, 7));
      picker = tester.semantics().single(
        role: SemanticRole.fileMentionPicker,
        label: 'Composer mentions',
        focused: true,
      );
      expect(picker.state.selectedFilePath, 'lib/main.dart');

      result = await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.fileMention,
        label: 'Launch plan',
      );
      expect(result.completed, isTrue);
      expect(controller.selectedIndex, 1);
      expect(picked?.entry.path, 'docs/launch.md');

      tester.render(size: const CellSize(90, 7));
      final row = tester.semantics().single(
        role: SemanticRole.fileMention,
        label: 'Launch plan',
        selected: true,
        action: SemanticAction.copy,
      );
      expect(row.state.filePath, 'docs/launch.md');

      picker = tester.semantics().single(
        role: SemanticRole.fileMentionPicker,
        label: 'Composer mentions',
        focused: true,
      );
      expect(picker.state.selectedFilePath, 'docs/launch.md');
      expect(picker.state['selectedIndex'], 1);
    });

    testWidgets('preserves selected mention identity across refresh', (tester) {
      final controller = FileMentionPickerController(selectedIndex: 2);
      tester.pumpWidget(
        FileMentionPicker(
          semanticLabel: 'Composer mentions',
          entries: _entries(),
          controller: controller,
        ),
      );
      tester.render(size: const CellSize(90, 7));

      tester.pumpWidget(
        FileMentionPicker(
          semanticLabel: 'Composer mentions',
          entries: [
            _entries()[0],
            const FileMentionEntry(
              path: 'lib/inserted.dart',
              label: 'Inserted file',
              detail: 'Newly discovered source file',
              language: 'dart',
            ),
            _entries()[1],
            const FileMentionEntry(
              path: 'packages/fleury_widgets/lib/src/search_panel.dart',
              label: 'SearchPanel',
              detail: 'Updated search result surface',
              language: 'dart',
              line: 48,
              column: 7,
              mentionText: '@search-panel',
            ),
          ],
          controller: controller,
        ),
      );
      tester.render(size: const CellSize(90, 8));
      tester.pump();
      tester.render(size: const CellSize(90, 8));

      expect(controller.selectedIndex, 3);
      final picker = tester.semantics().single(
        role: SemanticRole.fileMentionPicker,
        label: 'Composer mentions',
      );
      expect(
        picker.state.selectedFilePath,
        'packages/fleury_widgets/lib/src/search_panel.dart',
      );
      expect(picker.state['selectedMentionText'], '@search-panel');

      final row = tester.semantics().single(
        role: SemanticRole.fileMention,
        label: 'SearchPanel',
        selected: true,
      );
      expect(row.state.fileLanguage, 'dart');
      expect(row.state.mentionText, '@search-panel');
      expect(row.state['line'], 48);
      expect(row.state['column'], 7);
    });

    testWidgets('semantic copy copies selected mention text', (tester) async {
      FileMentionCopyResult? copied;
      try {
        tester.pumpWidget(
          FileMentionPicker(
            entries: _entries(),
            queryController: TextEditingController(text: 'main'),
            copyOptions: const FileMentionCopyOptions(
              clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
            ),
            onCopy: (result) => copied = result,
          ),
        );

        tester.render(size: const CellSize(90, 6));
        final result = await tester.invokeSemanticAction(
          SemanticAction.copy,
          role: SemanticRole.fileMention,
          label: 'Main entrypoint',
        );

        expect(result.completed, isTrue);
        expect(tester.clipboard.readInProcess(), '@lib/main.dart:12');
        expect(copied?.entryIndex, 0);
        expect(copied?.viewIndex, 0);
        expect(copied?.report.policy.name, 'inProcessOnly');
      } finally {
        // clipboard is tester-scoped; nothing to restore
      }
    });
  });
}
