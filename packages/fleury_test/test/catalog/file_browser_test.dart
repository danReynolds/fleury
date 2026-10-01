import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
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
  for (final missing in [false, true]) {
    testWidgets(
      'parent action leaves an ${missing ? "unreadable" : "empty"} directory',
      (tester) async {
        final parent = _scratchDir();
        final leaf = Directory('$parent/empty');
        if (!missing) leaf.createSync();
        final controller = FileBrowserController();
        addTearDown(controller.dispose);
        final changed = <String>[];
        tester.pumpWidget(
          FileBrowser(
            initialDirectory: leaf.path,
            controller: controller,
            onDirectoryChanged: changed.add,
          ),
        );
        tester.render(size: const CellSize(80, 5));
        final up = tester.semantics().single(
          role: SemanticRole.button,
          label: 'Parent directory',
        );
        expect(up.bounds?.top, 1, reason: 'reuse the existing separator row');
        expect(
          (await tester.invokeSemanticAction(
            SemanticAction.activate,
            id: up.id,
          )).completed,
          isTrue,
        );
        expect(controller.currentDirectory, parent);
        expect(changed, [parent]);
        // The navigation row is outside the collection: source/view indices stay intact.
        expect(controller.currentIndex, 0);
      },
    );
  }

  testWidgets('mouse can use the parent action without a file row', (tester) {
    final parent = _scratchDir();
    final leaf = Directory('$parent/empty')..createSync();
    final controller = FileBrowserController();
    addTearDown(controller.dispose);
    tester.pumpWidget(
      FileBrowser(initialDirectory: leaf.path, controller: controller),
    );
    tester.render(size: const CellSize(80, 5));
    for (final kind in [MouseEventKind.down, MouseEventKind.up]) {
      tester.sendMouse(
        MouseEvent(kind: kind, button: MouseButton.left, col: 2, row: 1),
      );
    }
    expect(controller.currentDirectory, parent);
  });

  group('FileBrowserController lifecycle', () {
    test('dispose is idempotent and keeps final readable state', () {
      final controller = FileBrowserController(initialIndex: 2);

      controller.dispose();
      controller.dispose();

      expect(controller.currentIndex, 2);
      expect(controller.visibleRange, isNull);
    });

    test('mutating after dispose throws a lifecycle error', () {
      final controller = FileBrowserController(initialIndex: 0)..dispose();

      const message = 'FileBrowserController has been disposed.';
      expect(() => controller.currentIndex = 1, _stateError(message));
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
    expect(tree.state['currentIndex'], 0);
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

  test('query filtering does not match the shared parent directory', () {
    final parent = ['', 'tmp', 'deploy-project'].join(Platform.pathSeparator);
    final entries = [
      FileEntry(
        path: '$parent${Platform.pathSeparator}alpha.txt',
        name: 'alpha.txt',
        type: FileEntryType.file,
      ),
      FileEntry(
        path: '$parent${Platform.pathSeparator}deploy.log',
        name: 'deploy.log',
        type: FileEntryType.file,
      ),
    ];

    expect(
      buildFileBrowserEntryOrder(
        entries,
        filter: const FileBrowserFilterDescriptor(query: 'deploy'),
      ),
      [1],
    );
  });

  testWidgets('Enter opens directories and activates files', (tester) {
    final dir = _scratchDir();
    FileEntry? activated;
    String? changedDirectory;
    tester.pumpWidget(
      FileBrowser(
        initialDirectory: dir,
        autofocus: true,
        onDirectoryChanged: (path) => changedDirectory = path,
        onActivate: (entry) => activated = entry,
      ),
    );

    tester.sendKey(const KeyEvent(KeyCode.enter));
    var output = tester.renderToString(size: const CellSize(80, 6));

    expect(changedDirectory, endsWith('${Platform.pathSeparator}src'));
    expect(output, contains('main.dart'));

    tester.sendKey(const KeyEvent(KeyCode.enter));
    expect(activated, isNotNull);
    expect(activated!.name, 'main.dart');

    tester.sendKey(const KeyEvent(KeyCode.backspace));
    output = tester.renderToString(size: const CellSize(80, 8));
    expect(output, contains('deploy.log'));
  });

  for (final unreadable in [false, true]) {
    testWidgets('the keyboard climbs out of an '
        '${unreadable ? 'unreadable' : 'empty'} directory', (tester) {
      // A directory with nothing to list leaves no rows to hold focus;
      // the browser holds it, so Backspace and Left still go up.
      final tmp = Directory.systemTemp.createTempSync('fleuryfb_leaf_');
      addTearDown(() {
        if (unreadable) Process.runSync('chmod', ['755', '${tmp.path}/a']);
        tmp.deleteSync(recursive: true);
      });
      Directory('${tmp.path}/a').createSync();
      File('${tmp.path}/z.txt').writeAsStringSync('z');
      final controller = FileBrowserController();
      addTearDown(controller.dispose);
      tester.pumpWidget(
        FileBrowser(
          initialDirectory: tmp.path,
          controller: controller,
          autofocus: true,
        ),
      );
      final start = controller.currentDirectory;

      for (final key in [KeyCode.backspace, KeyCode.arrowLeft]) {
        if (unreadable) {
          Process.runSync('chmod', ['000', '${tmp.path}/a']);
        }
        tester.sendKey(const KeyEvent(KeyCode.enter));
        expect(controller.currentDirectory, endsWith('a'));
        tester.render(size: const CellSize(40, 4));

        tester.sendKey(KeyEvent(key));

        expect(controller.currentDirectory, start, reason: '$key goes up');
        if (unreadable) {
          Process.runSync('chmod', ['755', '${tmp.path}/a']);
        }
      }
    }, skip: unreadable && Platform.isWindows ? 'no chmod' : false);
  }

  testWidgets('a rebuilt inline entityFilter neither re-reads nor moves', (
    tester,
  ) {
    // An inline closure is a new predicate on every parent build; the
    // directory is read when it opens or on reload(), not on each rebuild.
    final dir = _scratchDir();
    final controller = FileBrowserController();
    addTearDown(controller.dispose);
    Widget browser() => FileBrowser(
      initialDirectory: dir,
      controller: controller,
      autofocus: true,
      entryFilter: (entry) => !entry.path.endsWith('.tmp'),
    );
    tester.pumpWidget(browser());
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    expect(controller.currentIndex, 2);
    File('$dir/new.txt').writeAsStringSync('new');

    tester.pumpWidget(browser());

    expect(controller.currentIndex, 2, reason: 'the cursor stays put');
    expect(
      tester.renderToString(size: const CellSize(40, 8)),
      isNot(contains('new.txt')),
      reason: 'the disk was not read again',
    );

    controller.reload();
    expect(
      tester.renderToString(size: const CellSize(40, 8)),
      contains('new.txt'),
    );
  });

  testWidgets('a filter that changes what it hides applies at once, keeping '
      'the selected entry', (tester) {
    // As in FilePicker: a new predicate narrows the entries already read,
    // without reading the directory again.
    final source = _CountingSource(
      MemoryFileSource(['/p/a.md', '/p/b.txt', '/p/c.txt']),
    );
    final hiddenSuffix = ValueNotifier<String?>(null);
    tester.pumpWidget(
      NotifierBuilder(
        notifier: hiddenSuffix,
        builder: (context, notifier) {
          final suffix = notifier.value;
          return FileBrowser(
            initialDirectory: '/p',
            source: source,
            autofocus: true,
            entryFilter: (entry) =>
                suffix == null || !entry.name.endsWith(suffix),
          );
        },
      ),
    );
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    SemanticNode browserNode() =>
        tester.semantics().single(role: SemanticRole.tree);
    expect(browserNode().state['selectedPath'], '/p/c.txt');
    final reads = source.reads;

    hiddenSuffix.value = '.md';
    tester.pump();
    var browser = browserNode();
    expect(browser.state.collectionRowCount, 2, reason: 'a.md is hidden now');
    expect(browser.state['selectedPath'], '/p/c.txt');
    expect(browser.state['currentIndex'], 1);
    expect(source.reads, reads, reason: 'filtering needs no read');

    // Hiding the selected entry selects the first row. a.md comes back from
    // the entries already read.
    hiddenSuffix.value = '.txt';
    tester.pump();
    browser = browserNode();
    expect(browser.state.collectionRowCount, 1);
    expect(browser.state['selectedPath'], '/p/a.md');
    expect(source.reads, reads);
  });

  testWidgets('a query change keeps the selected entry selected', (tester) {
    final dir = _scratchDir();
    final controller = FileBrowserController();
    addTearDown(controller.dispose);
    Widget browser(String query) => FileBrowser(
      initialDirectory: dir,
      controller: controller,
      autofocus: true,
      filter: FileBrowserFilterDescriptor(query: query),
    );
    // src/, alpha.txt, deploy.log: select deploy.log.
    tester.pumpWidget(browser(''));
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));

    // 'l' lists alpha.txt then deploy.log: deploy.log moves to row 1.
    tester.pumpWidget(browser('l'));

    final selected = tester.semantics().single(role: SemanticRole.tree);
    expect(selected.state['selectedPath'], endsWith('deploy.log'));
  });

  group('the selected entry stays selected', () {
    String dirWith(List<String> names) {
      final tmp = Directory.systemTemp.createTempSync('fleuryfb_keep_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      for (final name in names) {
        File('${tmp.path}/$name').writeAsStringSync(name);
      }
      return tmp.path;
    }

    String? selectedPath(FleuryTester tester) =>
        tester.semantics().single(role: SemanticRole.tree).state['selectedPath']
            as String?;

    Widget browser(
      String dir,
      FileBrowserController controller, {
      String query = '',
      bool showHidden = false,
    }) => FileBrowser(
      initialDirectory: dir,
      controller: controller,
      autofocus: true,
      filter: FileBrowserFilterDescriptor(query: query, showHidden: showHidden),
    );

    void down(FleuryTester tester, int times) {
      for (var i = 0; i < times; i++) {
        tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      }
      tester.pump();
    }

    testWidgets('through a query that moves it up', (tester) {
      final dir = dirWith(['a1.txt', 'b2.txt', 'c3.log', 'd4.txt', 'e5.txt']);
      final controller = FileBrowserController();
      addTearDown(controller.dispose);
      tester.pumpWidget(browser(dir, controller));
      down(tester, 3);
      expect(selectedPath(tester), endsWith('d4.txt'));

      tester.pumpWidget(browser(dir, controller, query: 'txt'));

      expect(selectedPath(tester), endsWith('d4.txt'));
    });

    testWidgets('when hidden entries above it are hidden', (tester) {
      final dir = dirWith(['.h1', '.h2', 'a.txt', 'b.txt', 'c.txt']);
      final controller = FileBrowserController();
      addTearDown(controller.dispose);
      tester.pumpWidget(browser(dir, controller, showHidden: true));
      down(tester, 2);
      expect(selectedPath(tester), endsWith('a.txt'));

      tester.pumpWidget(browser(dir, controller));

      expect(selectedPath(tester), endsWith('a.txt'));
    });

    testWidgets('when hidden entries above it are shown', (tester) {
      // Row 2 of 3 moves to row 4 of 5, past the row count the list showed.
      final dir = dirWith(['.h1', '.h2', 'a.txt', 'b.txt', 'c.txt']);
      final controller = FileBrowserController();
      addTearDown(controller.dispose);
      tester.pumpWidget(browser(dir, controller));
      down(tester, 2);
      expect(selectedPath(tester), endsWith('c.txt'));

      tester.pumpWidget(browser(dir, controller, showHidden: true));

      expect(selectedPath(tester), endsWith('c.txt'));
    });

    testWidgets('through a reload with new entries ahead of it', (tester) {
      final dir = dirWith(['b.txt', 'c.txt']);
      final controller = FileBrowserController();
      addTearDown(controller.dispose);
      tester.pumpWidget(browser(dir, controller));
      down(tester, 1);
      expect(selectedPath(tester), endsWith('c.txt'));

      File('$dir/a0.txt').writeAsStringSync('a0');
      File('$dir/a1.txt').writeAsStringSync('a1');
      controller.reload();
      tester.pump();

      expect(selectedPath(tester), endsWith('c.txt'));
    });
  });

  testWidgets('semantic open navigates directories and activates files', (
    tester,
  ) async {
    final dir = _scratchDir();
    FileEntry? activated;
    String? changedDirectory;
    tester.pumpWidget(
      FileBrowser(
        initialDirectory: dir,
        onDirectoryChanged: (path) => changedDirectory = path,
        onActivate: (entry) => activated = entry,
      ),
    );

    tester.render(size: const CellSize(80, 6));
    await tester.target(role: SemanticRole.treeItem, label: 'src/').open();
    expect(changedDirectory, endsWith('${Platform.pathSeparator}src'));

    tester.render(size: const CellSize(80, 6));
    await tester.target(role: SemanticRole.treeItem, label: 'main.dart').open();
    expect(activated?.name, 'main.dart');
  });

  group('copy/export', () {
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
      tester.sendKey(
        const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        tester.clipboard.readInProcess(),
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
      await tester
          .target(role: SemanticRole.treeItem, label: 'deploy.log')
          .copy();

      expect(
        tester.clipboard.readInProcess(),
        endsWith('${Platform.pathSeparator}deploy.log'),
      );
      expect(copied?.entryIndex, 2);
      expect(copied?.viewIndex, 0);
      expect(copied?.report.result, ClipboardWriteResult.inProcessOnly);
    });

    test('exportFileBrowserEntry sanitizes path controls', () {
      final text = exportFileBrowserEntry(
        const FileEntry(
          path: '/tmp/bad\x1b]52;c;secret\x07\nname',
          name: 'bad',
          type: FileEntryType.file,
        ),
      );

      expect(text, isNot(contains('\x1b]52')));
      expect(text, isNot(contains('secret')));
      expect(text, isNot(contains('\n')));
      expect(text, contains(replacementCharacter));
      expect(text, contains('name'));
    });
  });

  group('the display order follows its inputs', () {
    String screen(FleuryTester tester) =>
        tester.renderToString(size: const CellSize(60, 8));

    testWidgets('a new query re-filters, and clearing it restores all', (
      tester,
    ) {
      final dir = _scratchDir();
      Widget browser(String query) => FileBrowser(
        initialDirectory: dir,
        filter: FileBrowserFilterDescriptor(query: query),
      );
      tester.pumpWidget(browser(''));
      expect(screen(tester), contains('alpha.txt'));

      tester.pumpWidget(browser('deploy'));
      expect(screen(tester), isNot(contains('alpha.txt')));
      expect(screen(tester), contains('deploy.log'));

      tester.pumpWidget(browser(''));
      expect(screen(tester), contains('alpha.txt'));
    });

    testWidgets('a reload lists a file created since', (tester) {
      final dir = _scratchDir();
      final controller = FileBrowserController();
      addTearDown(controller.dispose);
      tester.pumpWidget(
        FileBrowser(initialDirectory: dir, controller: controller),
      );
      expect(screen(tester), isNot(contains('zeta.md')));

      File('$dir/zeta.md').writeAsStringSync('zeta');
      controller.reload();
      tester.pump();

      expect(screen(tester), contains('zeta.md'));
    });

    testWidgets('showing hidden entries lists them', (tester) {
      final dir = _scratchDir();
      Widget browser(bool showHidden) => FileBrowser(
        initialDirectory: dir,
        filter: FileBrowserFilterDescriptor(showHidden: showHidden),
      );
      tester.pumpWidget(browser(false));
      expect(screen(tester), isNot(contains('.secret')));

      tester.pumpWidget(browser(true));

      expect(screen(tester), contains('.secret'));
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
        const FileEntry(
          path: '/tmp/bad\x1b]52;c;secret\x07\nname.txt',
          name: 'bad\x1b]52;c;secret\x07\nname.txt',
          type: FileEntryType.file,
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

/// Counts directory reads, so a test can tell a re-read from a re-filter.
final class _CountingSource implements FileSource {
  _CountingSource(this._inner);

  final FileSource _inner;
  int reads = 0;

  @override
  String absolute(String path) => _inner.absolute(path);

  @override
  String parent(String path) => _inner.parent(path);

  @override
  List<FileEntry> list(String directory) {
    reads++;
    return _inner.list(directory);
  }
}
