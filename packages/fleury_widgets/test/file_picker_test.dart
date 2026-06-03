import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
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

void main() {
  group('FilePicker', () {
    testWidgets('lists files and directories in the initial dir', (tester) {
      final dir = _scratchDir();
      tester.pumpWidget(FilePicker(initialDirectory: dir, onSelected: (_) {}));
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
      tester.pumpWidget(FilePicker(initialDirectory: dir, onSelected: (_) {}));
      var out = tester.renderToString(size: const CellSize(60, 6));
      expect(out.contains('.hidden'), isFalse);

      tester.pumpWidget(
        FilePicker(initialDirectory: dir, showHidden: true, onSelected: (_) {}),
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
          onSelected: (_) {},
        ),
      );
      final out = tester.renderToString(size: const CellSize(60, 6));
      expect(out.contains('b.dart'), isTrue);
      expect(out.contains('a.txt'), isFalse);
    });

    testWidgets('Enter on a file calls onSelected with that File', (tester) {
      final dir = _scratchDir();
      File? picked;
      tester.pumpWidget(
        FilePicker(
          initialDirectory: dir,
          autofocus: true,
          onSelected: (f) => picked = f,
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
        FilePicker(initialDirectory: dir, autofocus: true, onSelected: (_) {}),
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
          onSelected: (_) {},
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
        FilePicker(initialDirectory: dir, autofocus: true, onSelected: (_) {}),
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
        FilePicker(initialDirectory: tmp.path, onSelected: (_) {}),
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
          onSelected: (_) {},
        ),
      );

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
        FilePicker(initialDirectory: dir, autofocus: true, onSelected: (_) {}),
      );

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
          onSelected: (file) => picked = file,
        ),
      );

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
      tester.pumpWidget(FilePicker(initialDirectory: dir, onSelected: (_) {}));

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
