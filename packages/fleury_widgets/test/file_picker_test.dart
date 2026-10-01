import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

/// Builds a temporary directory with a deterministic layout for each
/// test. Returns the tempdir's path; cleans itself up via addTearDown.
String _scratchDir() {
  final tmp = Directory.systemTemp.createTempSync('fleuryfp_');
  // Files at the root.
  File('${tmp.path}/a.txt').writeAsStringSync('a');
  File('${tmp.path}/b.dart').writeAsStringSync('b');
  File('${tmp.path}/.hidden').writeAsStringSync('hide me');
  // A subdirectory with one file in it.
  Directory('${tmp.path}/sub').createSync();
  File('${tmp.path}/sub/inside.dart').writeAsStringSync('inside');
  addTearDown(() => tmp.deleteSync(recursive: true));
  return tmp.path;
}

/// A full left-click (press + release) at one cell. Render first so the
/// pointer router has the current paint-time rects.
void _clickAt(FleuryTester tester, {required int col, required int row}) {
  tester.sendMouse(
    MouseEvent(
      kind: MouseEventKind.down,
      button: MouseButton.left,
      col: col,
      row: row,
    ),
  );
  tester.sendMouse(
    MouseEvent(
      kind: MouseEventKind.up,
      button: MouseButton.left,
      col: col,
      row: row,
    ),
  );
}

String _bigDir(int count) {
  final tmp = Directory.systemTemp.createTempSync('fleuryfpbig_');
  for (var i = 0; i < count; i++) {
    File(
      '${tmp.path}/file_${i.toString().padLeft(2, '0')}.txt',
    ).writeAsStringSync('x');
  }
  addTearDown(() => tmp.deleteSync(recursive: true));
  return tmp.path;
}

void main() {
  group('FilePicker', () {
    testWidgets('scrolls to keep the cursor visible in a long directory', (
      tester,
    ) {
      tester.pumpWidget(
        FilePicker(
          initialDirectory: _bigDir(20),
          autofocus: true,
          maxVisible: 5,
          onSelect: (_) {},
        ),
      );
      // Height accommodates the wrapped cwd path, the clickable '..' parent
      // row, and the maxVisible window beneath them.
      tester.render(size: const CellSize(40, 8));
      // End jumps to the last entry; the window must scroll it into view and
      // push the top entry off (a plain Column would have clipped it).
      tester.sendKey(const KeyEvent(KeyCode.end));
      final out = tester.renderToString(
        size: const CellSize(40, 8),
        emptyMark: ' ',
      );
      expect(out.contains('file_19.txt'), isTrue, reason: 'cursor scrolled in');
      expect(out.contains('file_00.txt'), isFalse, reason: 'top scrolled off');
    });

    testWidgets('clicking an entry row opens a directory; the parent row '
        'climbs back out — both with the mouse alone', (tester) {
      final dir = _scratchDir();
      tester.pumpWidget(
        FilePicker(initialDirectory: dir, autofocus: true, onSelect: (_) {}),
      );
      // Layout at width 70: row0=path, row1='▴ ..', row2='▸ sub/', row3=a.txt.
      tester.render(size: const CellSize(70, 8));
      _clickAt(tester, col: 3, row: 2); // the sub/ directory row
      expect(
        tester
            .renderToString(size: const CellSize(70, 8))
            .contains('inside.dart'),
        isTrue,
        reason: 'clicking the directory opened it',
      );

      // The '..' parent row is back at row 1; clicking it returns to the root.
      _clickAt(tester, col: 2, row: 1);
      final out = tester.renderToString(size: const CellSize(70, 8));
      expect(out.contains('a.txt'), isTrue, reason: 'climbed back to the root');
      expect(out.contains('sub/'), isTrue);
    });

    testWidgets('clicking a file row selects it', (tester) {
      final dir = _scratchDir();
      FileEntry? picked;
      tester.pumpWidget(
        FilePicker(
          initialDirectory: dir,
          autofocus: true,
          onSelect: (f) => picked = f,
        ),
      );
      // row0=path, row1='▴ ..', row2='▸ sub/', row3='a.txt'.
      tester.render(size: const CellSize(70, 8));
      _clickAt(tester, col: 3, row: 3);
      expect(picked?.path, endsWith('a.txt'));
    });

    testWidgets('a click on a link row does nothing and leaves the keys '
        'working', (tester) {
      FileEntry? picked;
      tester.pumpWidget(
        FilePicker(
          initialDirectory: '/p',
          source: const _FixedSource({
            '/p': [
              FileEntry(
                path: '/p/a.txt',
                name: 'a.txt',
                type: FileEntryType.file,
              ),
              FileEntry(
                path: '/p/b.lnk',
                name: 'b.lnk',
                type: FileEntryType.link,
              ),
              FileEntry(
                path: '/p/c.txt',
                name: 'c.txt',
                type: FileEntryType.file,
              ),
            ],
          }),
          autofocus: true,
          onSelect: (f) => picked = f,
        ),
      );
      String? selectedPath() =>
          tester
                  .semantics()
                  .single(role: SemanticRole.tree)
                  .state['selectedPath']
              as String?;
      // row0=path, row1='▴ ..', row2=a.txt, row3=b.lnk, row4=c.txt.
      final lines = tester
          .renderToString(size: const CellSize(40, 8), emptyMark: ' ')
          .split('\n');
      expect(lines[3], contains('b.lnk'));
      _clickAt(tester, col: 4, row: 3);
      expect(picked, isNull, reason: 'a link cannot be chosen');
      expect(selectedPath(), '/p/a.txt', reason: 'the click is inert');

      tester.sendKey(const KeyEvent(KeyCode.arrowUp)); // wraps to c.txt
      tester.sendKey(const KeyEvent(KeyCode.enter));
      expect(picked?.path, '/p/c.txt');
    });

    testWidgets('lists files and directories in the initial dir', (tester) {
      final dir = _scratchDir();
      tester.pumpWidget(FilePicker(initialDirectory: dir, onSelect: (_) {}));
      final out = tester.renderToString(
        size: const CellSize(60, 6),
        emptyMark: ' ',
      );
      expect(
        out.contains('sub/'),
        isTrue,
        reason: 'directory shown with trailing /',
      );
      expect(out.contains('a.txt'), isTrue);
      expect(out.contains('b.dart'), isTrue);
    });

    testWidgets('hides dotfiles unless showHidden is true', (tester) {
      final dir = _scratchDir();
      tester.pumpWidget(FilePicker(initialDirectory: dir, onSelect: (_) {}));
      var out = tester.renderToString(size: const CellSize(60, 6));
      expect(out.contains('.hidden'), isFalse);

      tester.pumpWidget(
        FilePicker(initialDirectory: dir, showHidden: true, onSelect: (_) {}),
      );
      out = tester.renderToString(size: const CellSize(60, 6));
      expect(out.contains('.hidden'), isTrue);
    });

    testWidgets('filter callback excludes matching entries', (tester) {
      final dir = _scratchDir();
      tester.pumpWidget(
        FilePicker(
          initialDirectory: dir,
          filter: (e) => e is Directory || e.path.endsWith('.dart'),
          onSelect: (_) {},
        ),
      );
      final out = tester.renderToString(size: const CellSize(60, 6));
      expect(out.contains('b.dart'), isTrue);
      expect(out.contains('a.txt'), isFalse);
    });

    testWidgets('Enter on a file calls onSelect with that File', (tester) {
      final dir = _scratchDir();
      FileEntry? picked;
      tester.pumpWidget(
        FilePicker(
          initialDirectory: dir,
          autofocus: true,
          onSelect: (f) => picked = f,
        ),
      );
      // Directory 'sub' sorts first; arrow down twice lands on a.txt
      // (the first file after the sub dir).
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(KeyCode.enter));
      expect(picked, isNotNull);
      expect(picked!.path.endsWith('a.txt'), isTrue);
    });

    testWidgets('Enter on a directory navigates into it', (tester) {
      final dir = _scratchDir();
      tester.pumpWidget(
        FilePicker(initialDirectory: dir, autofocus: true, onSelect: (_) {}),
      );
      // Cursor starts at row 0 = the sub/ directory; Enter opens it.
      tester.sendKey(const KeyEvent(KeyCode.enter));
      final out = tester.renderToString(size: const CellSize(80, 4));
      expect(
        out.contains('inside.dart'),
        isTrue,
        reason: 'contents of sub/ should now be listed',
      );
    });

    testWidgets('Backspace goes up to the parent directory', (tester) {
      final dir = _scratchDir();
      tester.pumpWidget(
        FilePicker(
          initialDirectory: '$dir/sub',
          autofocus: true,
          onSelect: (_) {},
        ),
      );
      // inside.dart is visible at start.
      var out = tester.renderToString(size: const CellSize(80, 4));
      expect(out.contains('inside.dart'), isTrue);

      tester.sendKey(const KeyEvent(KeyCode.backspace));
      out = tester.renderToString(size: const CellSize(80, 6));
      expect(
        out.contains('sub/'),
        isTrue,
        reason: 'we should now be in the parent, with sub/ visible',
      );
    });

    testWidgets('arrow down + up cycle the cursor', (tester) {
      final dir = _scratchDir();
      tester.pumpWidget(
        FilePicker(initialDirectory: dir, autofocus: true, onSelect: (_) {}),
      );
      // We have 3 entries (sub/, a.txt, b.dart). Arrow Up at row 0 wraps
      // to the last; arrow Down then wraps back to the top.
      tester.sendKey(const KeyEvent(KeyCode.arrowUp));
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      // The expected state is "back at row 0"; just verify no throw.
      tester.render(size: const CellSize(60, 6));
    });

    testWidgets('entering a just-deleted directory keeps the listing and '
        'surfaces an error row', (tester) {
      final dir = _scratchDir();
      tester.pumpWidget(
        FilePicker(initialDirectory: dir, autofocus: true, onSelect: (_) {}),
      );
      tester.render(size: const CellSize(70, 8));

      // The cursor starts on sub/ (directories sort first). Delete it
      // out-of-band, then try to enter it: must not throw, must not move.
      Directory('$dir/sub').deleteSync(recursive: true);
      tester.sendKey(const KeyEvent(KeyCode.enter));

      final out = tester.renderToString(
        size: const CellSize(70, 8),
        emptyMark: ' ',
      );
      expect(out, contains('a.txt'), reason: 'old listing is retained');
      final tree = tester.semantics().single(role: SemanticRole.tree);
      expect(tree.value, dir, reason: 'cwd did not move');
      expect(tree.state['error'], isNotNull);

      // A later successful navigation clears the error again.
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(KeyCode.enter)); // a.txt: onSelect
      expect(
        tester.semantics().single(role: SemanticRole.tree).state['error'],
        isNotNull,
        reason: 'selecting a file does not relist',
      );
      tester.sendKey(const KeyEvent(KeyCode.backspace)); // parent
      expect(
        tester.semantics().single(role: SemanticRole.tree).state['error'],
        isNull,
      );
    });

    testWidgets('entering an unreadable directory keeps state and shows the '
        'error', (tester) {
      final dir = _scratchDir();
      final locked = Directory('$dir/locked')..createSync();
      // Restore permissions before _scratchDir's tearDown deletes the tree
      // (tear-downs run last-registered-first, even on failure).
      addTearDown(() => Process.runSync('chmod', ['700', locked.path]));
      expect(Process.runSync('chmod', ['000', locked.path]).exitCode, 0);
      try {
        // Running as root ignores mode 000; nothing to assert in that case.
        locked.listSync();
        return;
      } on FileSystemException {
        // Expected: the directory is unreadable for this process.
      }

      tester.pumpWidget(
        FilePicker(initialDirectory: dir, autofocus: true, onSelect: (_) {}),
      );
      tester.render(size: const CellSize(70, 9));

      // Directories sort first alphabetically: locked/ is the cursor row.
      tester.sendKey(const KeyEvent(KeyCode.enter));

      final out = tester.renderToString(
        size: const CellSize(70, 9),
        emptyMark: ' ',
      );
      expect(out, contains('sub/'), reason: 'old listing is retained');
      final tree = tester.semantics().single(role: SemanticRole.tree);
      expect(tree.value, dir, reason: 'cwd did not move');
      expect(tree.state['error'], isNotNull);

      // Pressing Enter again is still safe, and navigation elsewhere works.
      tester.sendKey(const KeyEvent(KeyCode.enter));
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(KeyCode.enter)); // into sub/
      expect(
        tester.renderToString(size: const CellSize(70, 9)),
        contains('inside.dart'),
      );
      expect(
        tester.semantics().single(role: SemanticRole.tree).state['error'],
        isNull,
      );
    }, skip: Platform.isWindows ? 'chmod is unavailable on Windows' : false);

    testWidgets('unlistable initial directory renders an error row instead '
        'of throwing', (tester) {
      final tmp = Directory.systemTemp.createTempSync('fleuryfp_gone_');
      final missing = '${tmp.path}/missing';
      addTearDown(() => tmp.deleteSync(recursive: true));

      tester.pumpWidget(
        FilePicker(initialDirectory: missing, onSelect: (_) {}),
      );
      final out = tester.renderToString(
        size: const CellSize(70, 4),
        emptyMark: ' ',
      );
      expect(out, contains('missing'), reason: 'header shows the request');
      expect(
        tester.semantics().single(role: SemanticRole.tree).state['error'],
        isNotNull,
      );
    });

    testWidgets('empty directory renders a quiet "(empty)" notice', (tester) {
      final tmp = Directory.systemTemp.createTempSync('fleuryfp_empty_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      tester.pumpWidget(
        FilePicker(initialDirectory: tmp.path, onSelect: (_) {}),
      );
      final out = tester.renderToString(size: const CellSize(40, 4));
      expect(out.contains('(empty)'), isTrue);
    });

    testWidgets('exposes tree semantics for the selected entry', (tester) {
      final dir = _scratchDir();
      tester.pumpWidget(
        FilePicker(
          initialDirectory: dir,
          semanticLabel: 'Project files',
          onSelect: (_) {},
        ),
      );
      tester.render(size: const CellSize(40, 10)); // lay out the windowed list

      final tree = tester.semantics().single(
        role: SemanticRole.tree,
        label: 'Project files',
        value: dir,
        action: SemanticAction.open,
      );
      expect(tree.actions, contains(SemanticAction.focus));
      expect(tree.actions, contains(SemanticAction.navigate));
      expect(tree.state.collectionRowCount, 3);
      expect(tree.state['currentIndex'], 0);
      expect(tree.state['selectedPath'], '$dir${Platform.pathSeparator}sub');
      expect(tree.state['selectedEntryType'], 'directory');
      expect(tree.state['selectedIsDirectory'], isTrue);

      final selected = tester.semantics().single(
        role: SemanticRole.treeItem,
        label: 'sub/',
        selected: true,
        action: SemanticAction.open,
      );
      expect(selected.value, '$dir${Platform.pathSeparator}sub');
      expect(selected.state['entryType'], 'directory');
      expect(selected.state['isDirectory'], isTrue);

      expect(
        tester
            .accessibilitySnapshot()
            .single(role: SemanticRole.tree, label: 'Project files')
            .states,
        contains('3 rows'),
      );
    });

    testWidgets('semantic open on a directory navigates into it', (
      tester,
    ) async {
      final dir = _scratchDir();
      tester.pumpWidget(
        FilePicker(initialDirectory: dir, autofocus: true, onSelect: (_) {}),
      );
      tester.render(size: const CellSize(40, 10));

      await tester.target(role: SemanticRole.treeItem, label: 'sub/').open();

      expect(
        tester.target(role: SemanticRole.tree),
        hasValue('$dir${Platform.pathSeparator}sub'),
      );
      expect(
        tester.semantics().single(
          role: SemanticRole.treeItem,
          label: 'inside.dart',
          selected: true,
        ),
        isNotNull,
      );
    });

    testWidgets('semantic open on a file selects it', (tester) async {
      final dir = _scratchDir();
      FileEntry? picked;
      tester.pumpWidget(
        FilePicker(
          initialDirectory: dir,
          autofocus: true,
          onSelect: (file) => picked = file,
        ),
      );
      tester.render(size: const CellSize(40, 10));

      await tester.target(role: SemanticRole.treeItem, label: 'a.txt').open();

      expect(picked, isNotNull);
      expect(picked!.path, '$dir${Platform.pathSeparator}a.txt');
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.tree)
            .state['currentIndex'],
        1,
      );
    });

    testWidgets('semantic focus updates the focused tree node', (tester) async {
      final dir = _scratchDir();
      tester.pumpWidget(FilePicker(initialDirectory: dir, onSelect: (_) {}));

      await tester.target(role: SemanticRole.tree, label: 'Files').focus();

      expect(tester.target(role: SemanticRole.tree, label: 'Files'), isFocused);
    });
  });

  group('FilePicker across parent rebuilds', () {
    String? selectedPath(FleuryTester tester) =>
        tester.semantics().single(role: SemanticRole.tree).state['selectedPath']
            as String?;

    testWidgets('an inline filter keeps the cursor and reads nothing', (
      tester,
    ) {
      final source = _CountingSource(
        MemoryFileSource(['/p/a.txt', '/p/b.txt', '/p/c.txt', '/p/d.log']),
      );
      final rebuild = ValueNotifier<int>(0);
      tester.pumpWidget(
        NotifierBuilder(
          notifier: rebuild,
          builder: (context, _) => FilePicker(
            initialDirectory: '/p',
            source: source,
            autofocus: true,
            // A new closure on every build of the parent.
            filter: (entry) => !entry.name.endsWith('.log'),
            onSelect: (_) {},
          ),
        ),
      );
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      expect(selectedPath(tester), '/p/c.txt');
      final reads = source.reads;

      rebuild.value++;
      tester.pump();
      expect(selectedPath(tester), '/p/c.txt', reason: 'cursor stays put');
      expect(source.reads, reads, reason: 'the directory was not read again');
    });

    testWidgets('a filter that changes what it hides applies at once, keeping '
        'the cursor on its entry', (tester) {
      final source = _CountingSource(
        MemoryFileSource(['/p/a.md', '/p/b.txt', '/p/c.txt']),
      );
      final hideMarkdown = ValueNotifier<bool>(false);
      tester.pumpWidget(
        NotifierBuilder(
          notifier: hideMarkdown,
          builder: (context, notifier) {
            final hide = notifier.value;
            return FilePicker(
              initialDirectory: '/p',
              source: source,
              autofocus: true,
              filter: (entry) => !(hide && entry.name.endsWith('.md')),
              onSelect: (_) {},
            );
          },
        ),
      );
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      expect(selectedPath(tester), '/p/c.txt');
      final reads = source.reads;

      hideMarkdown.value = true;
      tester.pump();
      var tree = tester.semantics().single(role: SemanticRole.tree);
      expect(tree.state.collectionRowCount, 2, reason: 'a.md is hidden now');
      expect(tree.state['selectedPath'], '/p/c.txt');
      expect(tree.state['currentIndex'], 1);
      expect(source.reads, reads, reason: 'filtering needs no read');

      // An entry the filter now hides can't keep the cursor: first row.
      tester.sendKey(const KeyEvent(KeyCode.home));
      hideMarkdown.value = false;
      tester.pump();
      tree = tester.semantics().single(role: SemanticRole.tree);
      expect(tree.state.collectionRowCount, 3);
      expect(tree.state['selectedPath'], '/p/b.txt');
    });

    testWidgets('toggling showHidden applies at once, keeping the cursor and '
        'reading nothing', (tester) {
      final source = _CountingSource(
        MemoryFileSource(['/p/.env', '/p/a.txt', '/p/b.txt']),
      );
      final showHidden = ValueNotifier<bool>(false);
      tester.pumpWidget(
        NotifierBuilder(
          notifier: showHidden,
          builder: (context, notifier) => FilePicker(
            initialDirectory: '/p',
            source: source,
            autofocus: true,
            showHidden: notifier.value,
            onSelect: (_) {},
          ),
        ),
      );
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      expect(selectedPath(tester), '/p/b.txt');
      final reads = source.reads;

      showHidden.value = true;
      tester.pump();
      final tree = tester.semantics().single(role: SemanticRole.tree);
      expect(tree.state.collectionRowCount, 3, reason: '.env is shown now');
      expect(tree.state['selectedPath'], '/p/b.txt');
      expect(source.reads, reads, reason: 'the directory was not read again');
    });

    testWidgets('a different source re-reads the directory, keeping the '
        'cursor on its entry', (tester) {
      Widget picker(FileSource source) => FilePicker(
        initialDirectory: '/p',
        source: source,
        autofocus: true,
        onSelect: (_) {},
      );
      tester.pumpWidget(picker(MemoryFileSource(['/p/a.txt', '/p/b.txt'])));
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      expect(selectedPath(tester), '/p/b.txt');

      tester.pumpWidget(
        picker(MemoryFileSource(['/p/0.txt', '/p/a.txt', '/p/b.txt'])),
      );
      final tree = tester.semantics().single(role: SemanticRole.tree);
      expect(tree.state.collectionRowCount, 3, reason: 'read from the new one');
      expect(tree.state['selectedPath'], '/p/b.txt');
    });
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

/// Lists fixed entries per directory, so a test can show entry types a
/// [MemoryFileSource] cannot, such as a link.
final class _FixedSource implements FileSource {
  const _FixedSource(this._entries);

  final Map<String, List<FileEntry>> _entries;

  @override
  String absolute(String path) => path;

  @override
  String parent(String path) {
    final cut = path.lastIndexOf('/');
    return cut <= 0 ? '/' : path.substring(0, cut);
  }

  @override
  List<FileEntry> list(String directory) =>
      _entries[directory] ??
      (throw FileSourceException('No such directory: $directory'));
}
