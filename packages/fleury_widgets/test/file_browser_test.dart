import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

String _scratchDir() {
  final tmp = Directory.systemTemp.createTempSync('fleuryfb_');
  File('${tmp.path}/alpha.txt').writeAsStringSync('alpha');
  File('${tmp.path}/deploy.log').writeAsStringSync('deploy');
  File('${tmp.path}/.secret').writeAsStringSync('secret');
  Directory('${tmp.path}/src').createSync();
  File('${tmp.path}/src/main.dart').writeAsStringSync('void main() {}');
  addTearDown(() => tmp.deleteSync(recursive: true));
  return tmp.path;
}

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('FileBrowserController lifecycle', () {
    test('dispose is idempotent and keeps final readable state', () {
      final controller = FileBrowserController(selectedIndex: 2);

      controller.dispose();
      controller.dispose();

      expect(controller.selectedIndex, 2);
      expect(controller.visibleRange, isNull);
    });

    test('mutating after dispose throws a lifecycle error', () {
      final controller = FileBrowserController(selectedIndex: 0)..dispose();

      const message = 'FileBrowserController has been disposed.';
      expect(() => controller.selectedIndex = 1, _stateError(message));
      expect(() => controller.jumpToIndex(1), _stateError(message));
    });
  });

  testWidgets('renders entries lazily with file-browser semantics', (tester) {
    final dir = _scratchDir();
    tester.pumpWidget(FileBrowser(initialDirectory: dir));

    final output = tester.renderToString(
      size: const CellSize(80, 8),
      emptyMark: ' ',
    );

    expect(output, contains('src/'));
    expect(output, contains('alpha.txt'));
    expect(output, contains('deploy.log'));
    expect(output, isNot(contains('.secret')));

    final tree = tester.semantics().single(role: SemanticRole.tree);
    expect(tree.label, 'Files');
    expect(tree.state.collectionRowCount, 3);
    expect(tree.state['totalEntryCount'], 3);
    expect(tree.state['selectedIndex'], 0);
    expect(tree.state['selectedEntryType'], 'directory');

    final sourceDir = tester.semantics().single(
      role: SemanticRole.treeItem,
      label: 'src/',
    );
    expect(sourceDir.selected, isTrue);
    expect(sourceDir.actions, contains(SemanticAction.open));
    expect(sourceDir.state['rowIndex'], 0);
    expect(sourceDir.state['viewIndex'], 0);
    expect(sourceDir.state['isDirectory'], isTrue);
  });

  testWidgets('query filter preserves source and filtered view indexes', (
    tester,
  ) {
    final dir = _scratchDir();
    tester.pumpWidget(
      FileBrowser(
        initialDirectory: dir,
        filter: const FileBrowserFilterDescriptor(query: 'deploy'),
      ),
    );

    tester.render(size: const CellSize(80, 6));

    final tree = tester.semantics().single(role: SemanticRole.tree);
    expect(tree.state.collectionRowCount, 1);
    expect(tree.state['totalEntryCount'], 3);
    expect(tree.state.filterText, 'deploy');

    final row = tester.semantics().single(role: SemanticRole.treeItem);
    expect(row.label, 'deploy.log');
    expect(row.state['rowIndex'], 2);
    expect(row.state['viewIndex'], 0);
  });

  testWidgets('Enter opens directories and activates files', (tester) {
    final dir = _scratchDir();
    FileBrowserEntry? activated;
    String? changedDirectory;
    tester.pumpWidget(
      FileBrowser(
        initialDirectory: dir,
        autofocus: true,
        onDirectoryChanged: (path) => changedDirectory = path,
        onActivate: (entry) => activated = entry,
      ),
    );

    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    var output = tester.renderToString(size: const CellSize(80, 6));

    expect(changedDirectory, endsWith('${Platform.pathSeparator}src'));
    expect(output, contains('main.dart'));

    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    expect(activated, isNotNull);
    expect(activated!.name, 'main.dart');

    tester.sendKey(const KeyEvent(keyCode: KeyCode.backspace));
    output = tester.renderToString(size: const CellSize(80, 8));
    expect(output, contains('deploy.log'));
  });

  testWidgets('semantic open navigates directories and activates files', (
    tester,
  ) async {
    final dir = _scratchDir();
    FileBrowserEntry? activated;
    String? changedDirectory;
    tester.pumpWidget(
      FileBrowser(
        initialDirectory: dir,
        onDirectoryChanged: (path) => changedDirectory = path,
        onActivate: (entry) => activated = entry,
      ),
    );

    tester.render(size: const CellSize(80, 6));
    var result = await tester.invokeSemanticAction(
      SemanticAction.open,
      role: SemanticRole.treeItem,
      label: 'src/',
    );
    expect(result.completed, isTrue);
    expect(changedDirectory, endsWith('${Platform.pathSeparator}src'));

    tester.render(size: const CellSize(80, 6));
    result = await tester.invokeSemanticAction(
      SemanticAction.open,
      role: SemanticRole.treeItem,
      label: 'main.dart',
    );
    expect(result.completed, isTrue);
    expect(activated?.name, 'main.dart');
  });

  group('copy/export', () {
    late Clipboard originalClipboard;
    late TestClipboard clipboard;

    setUp(() {
      originalClipboard = Clipboard.instance;
      clipboard = TestClipboard();
      Clipboard.instance = clipboard;
    });

    tearDown(() {
      Clipboard.instance = originalClipboard;
    });

    testWidgets('Ctrl+C copies selected path with source index result', (
      tester,
    ) async {
      final dir = _scratchDir();
      FileBrowserCopyResult? copied;
      tester.pumpWidget(
        FileBrowser(
          initialDirectory: dir,
          autofocus: true,
          filter: const FileBrowserFilterDescriptor(query: 'deploy'),
          copyOptions: const FileBrowserCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(80, 6));
      tester.sendKey(const KeyEvent(char: 'c', modifiers: {KeyModifier.ctrl}));
      await Future<void>.delayed(Duration.zero);

      expect(
        clipboard.lastWritten,
        endsWith('${Platform.pathSeparator}deploy.log'),
      );
      expect(copied, isNotNull);
      expect(copied!.entryIndex, 2);
      expect(copied!.viewIndex, 0);
      expect(copied!.entry.name, 'deploy.log');
      expect(copied!.report.policy.name, 'inProcessOnly');

      final row = tester.semantics().single(
        role: SemanticRole.treeItem,
        action: SemanticAction.copy,
      );
      expect(row.state['rowIndex'], 2);
    });

    testWidgets('semantic copy copies selected path with source index result', (
      tester,
    ) async {
      final dir = _scratchDir();
      FileBrowserCopyResult? copied;
      tester.pumpWidget(
        FileBrowser(
          initialDirectory: dir,
          filter: const FileBrowserFilterDescriptor(query: 'deploy'),
          copyOptions: const FileBrowserCopyOptions(
            clipboardPolicy: ClipboardWritePolicy.inProcessOnly,
          ),
          onCopy: (result) => copied = result,
        ),
      );

      tester.render(size: const CellSize(80, 6));
      final result = await tester.invokeSemanticAction(
        SemanticAction.copy,
        role: SemanticRole.treeItem,
        label: 'deploy.log',
      );

      expect(result.completed, isTrue);
      expect(
        clipboard.lastWritten,
        endsWith('${Platform.pathSeparator}deploy.log'),
      );
      expect(copied?.entryIndex, 2);
      expect(copied?.viewIndex, 0);
      expect(copied?.report.result, ClipboardWriteResult.inProcessOnly);
    });

    test('exportFileBrowserEntry sanitizes path controls', () {
      final text = exportFileBrowserEntry(
        const FileBrowserEntry(
          path: '/tmp/bad\x1b]52;c;secret\x07\nname',
          name: 'bad',
          type: FileBrowserEntryType.file,
        ),
      );

      expect(text, isNot(contains('\x1b]52')));
      expect(text, isNot(contains('secret')));
      expect(text, isNot(contains('\n')));
      expect(text, contains(replacementCharacter));
      expect(text, contains('name'));
    });
  });

  testWidgets('hidden entries can be included explicitly', (tester) {
    final dir = _scratchDir();
    tester.pumpWidget(
      FileBrowser(
        initialDirectory: dir,
        filter: const FileBrowserFilterDescriptor(showHidden: true),
      ),
    );

    final output = tester.renderToString(size: const CellSize(80, 8));
    expect(output, contains('.secret'));
    expect(
      tester.semantics().single(role: SemanticRole.tree).state['showHidden'],
      isTrue,
    );
  });

  testWidgets('sanitizes unsafe filenames for display, search, and semantics', (
    tester,
  ) {
    final tmp = Directory.systemTemp.createTempSync('fleuryfb_unsafe_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(
      '${tmp.path}/bad\x1b]52;c;secret\x07\nname.txt',
    ).writeAsStringSync('unsafe');

    expect(
      buildFileBrowserEntryOrder([
        const FileBrowserEntry(
          path: '/tmp/bad\x1b]52;c;secret\x07\nname.txt',
          name: 'bad\x1b]52;c;secret\x07\nname.txt',
          type: FileBrowserEntryType.file,
        ),
      ], filter: const FileBrowserFilterDescriptor(query: 'secret')),
      isEmpty,
    );

    tester.pumpWidget(FileBrowser(initialDirectory: tmp.path));
    final output = tester.renderToString(
      size: const CellSize(80, 5),
      emptyMark: ' ',
    );

    expect(output, contains('bad'));
    expect(output, contains('name.txt'));
    expect(output, contains(replacementCharacter));
    expect(output, isNot(contains('secret')));
    expect(output, isNot(contains('\x1b]52')));

    final row = tester.semantics().single(role: SemanticRole.treeItem);
    expect(row.label, contains(replacementCharacter));
    expect(row.state.outputSanitized, isTrue);
    expect(row.state['path'], isNot(contains('secret')));
  });
}
