import 'dart:async' show Future;

import 'package:fleury/fleury.dart';
import 'package:fleury_samples/samples.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

const _size = CellSize(82, 28);
const _introSize = CellSize(60, 12);
const _saveCurrentFile = CommandId('editor.save');
const _newFile = CommandId('files.new-file');

void main() {
  testWidgets('the intro shares one save command across every entry point', (
    tester,
  ) async {
    tester.viewportSize = _introSize;
    tester.pumpWidget(const CommandIntroApp());

    var output = tester.renderToString(size: _introSize, emptyMark: ' ');
    expect(output, contains('ONE COMMAND · EVERY ENTRY POINT'));
    expect(output, contains('Save current file · editor.save'));
    expect(output, contains('[ Save ]'));
    expect(output, contains('Ctrl+K [ Commands ]'));
    expect(output, contains('SAVED · 0'));
    expect(tester.button('Save'), isDisabled);

    await _setText(tester, label: 'Intro document', value: 'Edited');
    expect(tester.button('Save'), isEnabled);

    tester.sendKey(
      const KeyEvent(KeyCode.s, modifiers: <KeyModifier>{KeyModifier.ctrl}),
    );
    await Future<void>.delayed(Duration.zero);
    tester.pump();

    output = tester.renderToString(size: _introSize, emptyMark: ' ');
    expect(output, contains('SAVED · 1'));
    expect(
      (await tester.invokeCommand(_saveCurrentFile)).status,
      CommandInvocationStatus.disabled,
    );
  });

  testWidgets('the intro palette discovers and invokes the save command', (
    tester,
  ) async {
    tester.viewportSize = _introSize;
    tester.pumpWidget(const CommandIntroApp());
    await _setText(tester, label: 'Intro document', value: 'Palette edit');

    await tester.button('Commands').press();
    tester.pump(const Duration(milliseconds: 300));

    final saveRow = tester
        .semantics()
        .byRole(SemanticRole.command)
        .singleWhere(
          (node) =>
              node.state['rowIndex'] != null &&
              node.state.commandId == _saveCurrentFile.value,
        );
    expect(saveRow.label, 'Save current file');
    expect(saveRow.enabled, isTrue);

    await tester.target(id: saveRow.id).press();
    await _settlePaletteClose(tester);

    final output = tester.renderToString(size: _introSize, emptyMark: ' ');
    expect(output, contains('SAVED · 1'));
  });

  testWidgets('renders a recognizable editor with shared command controls', (
    tester,
  ) async {
    _pumpWorkbench(tester);

    final output = _render(tester);
    expect(output, contains('COMMAND EDITOR'));
    expect(output, contains('FILES'));
    expect(output, contains('main.dart'));
    expect(output, contains('commands.dart'));
    expect(output, contains('README.md'));
    expect(output, contains('[ New file ]'));
    expect(output, contains('[ Save ]'));
    expect(output, contains('Ctrl+K [ Commands ]'));
    expect(output, contains('Ctrl+S · Save current file'));
    expect(output, contains('SAVED'));
    expect(output, contains('SAVES 0'));

    expect(tester.button('Save'), isDisabled);
    expect(
      tester.target(role: SemanticRole.command, label: 'Save current file'),
      isDisabled,
    );
  });

  testWidgets('save policy stays aligned across the toolbar and registry', (
    tester,
  ) async {
    _pumpWorkbench(tester);

    await _editCurrentFile(tester, 'button revision');
    expect(_render(tester), contains('UNSAVED'));
    expect(_render(tester), contains('Ctrl+S available'));
    expect(tester.button('Save'), isEnabled);
    expect(
      tester.target(role: SemanticRole.command, label: 'Save current file'),
      isEnabled,
    );

    await tester.button('Save').press();
    _expectSaved(tester, count: 1, file: 'main.dart');
  });

  testWidgets('new and save shortcuts operate on the current file', (
    tester,
  ) async {
    _pumpWorkbench(tester);

    tester.sendKey(
      const KeyEvent(KeyCode.n, modifiers: <KeyModifier>{KeyModifier.ctrl}),
    );
    await Future<void>.delayed(Duration.zero);
    tester.pump();

    var output = _render(tester);
    expect(output, contains('untitled_1.dart'));
    expect(output, contains('4 FILES'));
    expect(output, contains('New file · untitled_1.dart'));
    expect(output, contains('UNSAVED'));
    expect(
      (await tester.invokeCommand(_newFile)).status,
      CommandInvocationStatus.completed,
    );

    output = _render(tester);
    expect(output, contains('untitled_2.dart'));
    expect(output, contains('5 FILES'));

    tester.sendKey(
      const KeyEvent(KeyCode.s, modifiers: <KeyModifier>{KeyModifier.ctrl}),
    );
    await Future<void>.delayed(Duration.zero);
    tester.pump();
    _expectSaved(tester, count: 1, file: 'untitled_2.dart');
  });

  testWidgets('the palette discovers new and save with shared availability', (
    tester,
  ) async {
    _pumpWorkbench(tester);
    await _editCurrentFile(tester, 'palette revision');

    await tester.button('Commands').press();
    tester.pump(const Duration(milliseconds: 300));

    final paletteRows = tester
        .semantics()
        .byRole(SemanticRole.command)
        .where((node) => node.state['rowIndex'] != null)
        .toList();
    final paletteIds = paletteRows
        .map((node) => node.state.commandId)
        .whereType<String>()
        .toSet();
    expect(
      paletteIds,
      containsAll(<String>[_newFile.value, _saveCurrentFile.value]),
    );

    final saveRow = paletteRows.singleWhere(
      (node) => node.state.commandId == _saveCurrentFile.value,
    );
    expect(saveRow.enabled, isTrue);
    await tester.target(id: saveRow.id).press();
    await _settlePaletteClose(tester);
    _expectSaved(tester, count: 1, file: 'main.dart');
  });

  testWidgets('the palette-first workbench opens its active command catalog', (
    tester,
  ) async {
    tester.viewportSize = _size;
    tester.pumpWidget(const CommandWorkbenchApp(openPaletteInitially: true));
    tester.pump(const Duration(milliseconds: 300));

    final paletteRows = tester
        .semantics()
        .byRole(SemanticRole.command)
        .where((node) => node.state['rowIndex'] != null)
        .toList();
    expect(
      paletteRows.map((node) => node.state.commandId),
      containsAll(<String>[_newFile.value, _saveCurrentFile.value]),
    );
  });

  testWidgets('switching files keeps each draft and save state', (
    tester,
  ) async {
    _pumpWorkbench(tester);
    await _editCurrentFile(tester, 'unsaved main');

    await tester.button('commands.dart').press();
    expect(_render(tester), contains('Opened commands.dart'));
    expect(
      tester.target(role: SemanticRole.command, label: 'Save current file'),
      isDisabled,
    );

    await tester.button('main.dart').press();
    expect(_render(tester), contains('unsaved main'));
    expect(_render(tester), contains('UNSAVED'));
    expect(
      tester.target(role: SemanticRole.command, label: 'Save current file'),
      isEnabled,
    );
  });
}

void _pumpWorkbench(FleuryTester tester) {
  tester.viewportSize = _size;
  tester.pumpWidget(const CommandWorkbenchApp());
}

String _render(FleuryTester tester) =>
    tester.renderToString(size: _size, emptyMark: ' ');

Future<void> _setText(
  FleuryTester tester, {
  required String label,
  required String value,
}) async {
  await tester.field(label).fill(value);
}

Future<void> _editCurrentFile(FleuryTester tester, String value) async {
  await _setText(tester, label: 'Current file contents', value: value);
  expect(
    tester.target(role: SemanticRole.command, label: 'Save current file'),
    isEnabled,
  );
}

void _expectSaved(
  FleuryTester tester, {
  required int count,
  required String file,
}) {
  final output = _render(tester);
  expect(output, contains('SAVES $count'));
  expect(output, contains('Saved $file'));
  expect(output, contains('Ctrl+S saved'));
  expect(
    tester.target(role: SemanticRole.command, label: 'Save current file'),
    isDisabled,
  );
}

Future<void> _settlePaletteClose(FleuryTester tester) async {
  tester.pump(const Duration(milliseconds: 300));
  await Future<void>.delayed(Duration.zero);
  tester.pump();
}
