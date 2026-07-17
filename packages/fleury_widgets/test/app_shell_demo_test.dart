import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

import '../example/app_shell_demo.dart';

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
    KeyEvent(char: character, modifiers: const <KeyModifier>{KeyModifier.ctrl}),
  );
}

void _openPalette(FleuryTester tester) {
  _sendCtrl(tester, 'k');
  tester.pump(_transitionDuration);
  tester.render(size: _size);
}

void _dismissPalette(FleuryTester tester) {
  tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
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
      expect(output, contains('Environment: production healthy'));

      final semantics = tester.semantics();
      expect(
        semantics
            .single(role: SemanticRole.app, label: 'Fleury Launchpad')
            .label,
        'Fleury Launchpad',
      );
      expect(
        semantics
            .single(role: SemanticRole.command, label: 'Open Command Palette')
            .state
            .commandId,
        'app.open-palette',
      );
      expect(
        semantics
            .single(
              role: SemanticRole.command,
              label: 'Open Production Deployment',
            )
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

      tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
      tester.pump(_transitionDuration);
      output = tester.renderToString(size: _size);
      expect(output, contains('Fleury Launchpad'));
      expect(output, contains('Open production'));
    });

    testWidgets('semantic navigation command uses the same route action', (
      tester,
    ) async {
      tester.pumpWidget(const AppShellDemo());
      tester.render(size: _size);

      final result = await tester.invokeSemanticAction(
        SemanticAction.navigate,
        role: SemanticRole.command,
        label: 'Open Production Deployment',
      );
      tester.pump(_transitionDuration);

      expect(result.completed, isTrue);
      expect(tester.renderToString(size: _size), contains('refreshes: 0'));
    });

    testWidgets('palette follows the focused active route command scope', (
      tester,
    ) {
      tester.pumpWidget(const AppShellDemo());
      tester.render(size: _size);

      _openPalette(tester);
      var labels = _paletteRows(tester).map((node) => node.label).toSet();
      expect(labels, isNot(contains('Open Command Palette')));
      expect(labels, contains('Open Production Deployment'));
      expect(labels, isNot(contains('Refresh Production Deployment')));
      _dismissPalette(tester);

      _sendCtrl(tester, 'o');
      tester.pump(_transitionDuration);
      tester.render(size: _size);

      _openPalette(tester);
      labels = _paletteRows(tester).map((node) => node.label).toSet();
      expect(labels, isNot(contains('Open Command Palette')));
      expect(labels, contains('Refresh Production Deployment'));
      expect(labels, isNot(contains('Open Production Deployment')));
      _dismissPalette(tester);
    });
  });
}
