import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

import '../../../fleury/example/catalog/app_shell_demo.dart';

const _size = CellSize(72, 16);
const _transitionDuration = Duration(milliseconds: 300);

List<SemanticNode> _paletteRows(FleuryTester tester) {
  return tester
      .semantics()
      .byRole(SemanticRole.command)
      .where((node) => node.state['rowIndex'] != null)
      .toList();
}

void _sendCtrl(FleuryTester tester, String character) {
  tester.sendKey(
    KeyEvent(
      KeyCode.char(character),
      modifiers: const <KeyModifier>{KeyModifier.ctrl},
    ),
  );
}

void _openPalette(FleuryTester tester) {
  _sendCtrl(tester, 'k');
  tester.pump(_transitionDuration);
  tester.render(size: _size);
}

void _dismissPalette(FleuryTester tester) {
  tester.sendKey(const KeyEvent(KeyCode.escape));
  tester.pump(_transitionDuration);
}

void main() {
  group('AppShellDemo', () {
    testWidgets('renders the standard app shell and command semantics', (
      tester,
    ) {
      tester.pumpWidget(const AppShellDemo());

      final output = tester.renderToString(size: _size);
      expect(output, contains('Fleury Launchpad'));
      expect(output, contains('Production deployment'));
      expect(output, contains('Production: healthy'));

      final semantics = tester.semantics();
      expect(
        semantics
            .single(role: SemanticRole.app, label: 'Fleury Launchpad')
            .label,
        'Fleury Launchpad',
      );
      expect(
        semantics
            .single(role: SemanticRole.command, label: 'Commands')
            .state
            .commandId,
        'app.open-palette',
      );
      expect(
        semantics
            .single(role: SemanticRole.command, label: 'Open production')
            .state
            .commandId,
        'deployment.open-production',
      );
    });

    testWidgets('route shortcuts navigate, mutate local state, and go back', (
      tester,
    ) {
      tester.pumpWidget(const AppShellDemo());
      tester.render(size: _size);

      _sendCtrl(tester, 'o');
      tester.pump(_transitionDuration);

      var output = tester.renderToString(size: _size);
      expect(output, contains('Production deployment'));
      expect(output, contains('refreshes: 0'));

      _sendCtrl(tester, 'r');
      tester.pump();
      output = tester.renderToString(size: _size);
      expect(output, contains('refreshes: 1'));

      tester.sendKey(const KeyEvent(KeyCode.escape));
      tester.pump(_transitionDuration);
      output = tester.renderToString(size: _size);
      expect(output, contains('Fleury Launchpad'));
      expect(output, contains('Open production'));
    });

    testWidgets('keeps status and shortcuts visible in a short terminal', (
      tester,
    ) {
      const narrow = CellSize(32, 12);
      tester.pumpWidget(const AppShellDemo());
      var output = tester.renderToString(size: narrow);
      expect(output, contains('Production: healthy'));
      expect(output, contains('[Ctrl+O] Open production'));
      expect(output, contains('+1'));

      _sendCtrl(tester, 'o');
      tester.pump(_transitionDuration);
      output = tester.renderToString(size: narrow);
      expect(output, contains('Production: healthy'));
      expect(output, contains('[Ctrl+R] Refresh status'));

      _sendCtrl(tester, 'r');
      tester.pump();
      expect(tester.renderToString(size: narrow), contains('refreshes: 1'));

      // With less height, Tab scrolls the second body button into view.
      tester.render(size: const CellSize(32, 10));
      tester.sendKey(const KeyEvent(KeyCode.tab));
      tester.pump();
      expect(
        tester.renderToString(size: const CellSize(32, 10)),
        contains('Back'),
      );
      tester.sendKey(const KeyEvent(KeyCode.enter));
      tester.pump(_transitionDuration);
      expect(tester.renderToString(size: narrow), contains('[Ctrl+O]'));

      output = tester.renderToString(size: _size);
      expect(output, contains('Fleury Launchpad'));
      expect(output, contains('[Ctrl+K] Commands'));
    });

    testWidgets('semantic navigation command uses the same route action', (
      tester,
    ) async {
      tester.pumpWidget(const AppShellDemo());
      tester.render(size: _size);

      await tester
          .target(role: SemanticRole.command, label: 'Open production')
          .perform(SemanticAction.navigate);
      tester.pump(_transitionDuration);

      expect(tester.renderToString(size: _size), contains('refreshes: 0'));
    });

    testWidgets('palette follows the focused active route command scope', (
      tester,
    ) {
      tester.pumpWidget(const AppShellDemo());
      tester.render(size: _size);

      _openPalette(tester);
      var labels = _paletteRows(tester).map((node) => node.label).toSet();
      expect(labels, isNot(contains('Commands')));
      expect(labels, contains('Open production'));
      expect(labels, isNot(contains('Refresh status')));
      _dismissPalette(tester);

      _sendCtrl(tester, 'o');
      tester.pump(_transitionDuration);
      tester.render(size: _size);

      _openPalette(tester);
      labels = _paletteRows(tester).map((node) => node.label).toSet();
      expect(labels, isNot(contains('Commands')));
      expect(labels, contains('Refresh status'));
      expect(labels, isNot(contains('Open production')));
      _dismissPalette(tester);
    });
  });
}
