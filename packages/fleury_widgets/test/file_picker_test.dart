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
      tester.sendKey(const KeyEvent(keyCode: KeyCode.end));
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
      File? picked;
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
      File? picked;
      tester.pumpWidget(
        FilePicker(
          initialDirectory: dir,
          autofocus: true,
          onSelect: (f) => picked = f,
        ),
      );
      // Directory 'sub' sorts first; arrow down twice lands on a.txt
      // (the first file after the sub dir).
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(picked, isNotNull);
      expect(picked!.path.endsWith('a.txt'), isTrue);
    });

    testWidgets('Enter on a directory navigates into it', (tester) {
      final dir = _scratchDir();
      tester.pumpWidget(
        FilePicker(initialDirectory: dir, autofocus: true, onSelect: (_) {}),
      );
      // Cursor starts at row 0 = the sub/ directory; Enter opens it.
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
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

      tester.sendKey(const KeyEvent(keyCode: KeyCode.backspace));
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
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowUp));
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      // The expected state is "back at row 0"; just verify no throw.
      tester.render(size: const CellSize(60, 6));
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
      expect(tree.state['selectedIndex'], 0);
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

      final result = await tester.invokeSemanticAction(
        SemanticAction.open,
        role: SemanticRole.treeItem,
        label: 'sub/',
      );

      expect(result.completed, isTrue);
      expect(
        tester.semantics().single(role: SemanticRole.tree).value,
        '$dir${Platform.pathSeparator}sub',
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
      File? picked;
      tester.pumpWidget(
        FilePicker(
          initialDirectory: dir,
          autofocus: true,
          onSelect: (file) => picked = file,
        ),
      );
      tester.render(size: const CellSize(40, 10));

      final result = await tester.invokeSemanticAction(
        SemanticAction.open,
        role: SemanticRole.treeItem,
        label: 'a.txt',
      );

      expect(result.completed, isTrue);
      expect(picked, isNotNull);
      expect(picked!.path, '$dir${Platform.pathSeparator}a.txt');
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.tree)
            .state['selectedIndex'],
        1,
      );
    });

    testWidgets('semantic focus updates the focused tree node', (tester) async {
      final dir = _scratchDir();
      tester.pumpWidget(FilePicker(initialDirectory: dir, onSelect: (_) {}));

      final result = await tester.invokeSemanticAction(
        SemanticAction.focus,
        role: SemanticRole.tree,
        label: 'Files',
      );

      expect(result.completed, isTrue);
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.tree, label: 'Files')
            .focused,
        isTrue,
      );
    });
  });
}
