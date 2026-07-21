import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_samples/samples.dart';
import 'package:test/test.dart';

const _size = CellSize(120, 40);

void main() {
  group('dashboard', () {
    testWidgets('renders its meters, history chart, and process table', (
      tester,
    ) {
      tester.pumpWidget(const DashboardApp());
      final out = tester.renderToString(size: _size);
      expect(out, contains('Fleury System Monitor'));
      expect(out, contains('CPU'));
      expect(out, contains('Memory & I/O'));
      expect(out, contains('history'));
      expect(out, contains('Processes'));
      expect(out, contains('COMMAND'));
      expect(out, contains('fleury serve'));
    });
  });

  group('file manager', () {
    testWidgets('renders the tree and a markdown preview by default', (tester) {
      tester.pumpWidget(const FileManagerApp());
      final out = tester.renderToString(size: _size);
      expect(out, contains('Explorer'));
      expect(out, contains('lib/'));
      expect(out, contains('README.md'));
      // README.md is pre-selected, so its rendered markdown is visible.
      expect(out, contains('tiny counter'));
    });

    testWidgets('opening a .dart file shows the code preview', (tester) {
      tester.pumpWidget(const FileManagerApp());
      tester.render(size: _size); // mount + focus the tree
      // lib/ is the first row: expand it, step to main.dart, open it.
      tester.sendKey(const KeyEvent(KeyCode.arrowRight)); // expand lib/
      tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // → main.dart
      tester.sendKey(const KeyEvent(KeyCode.enter)); // open
      final out = tester.renderToString(size: _size);
      expect(out, contains('main.dart'));
      expect(out, contains('runApp'));
    });

    testWidgets('opening config.json shows the JSON preview', (tester) {
      tester.pumpWidget(const FileManagerApp());
      tester.render(size: _size);
      tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // → test/
      tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // → assets/
      tester.sendKey(const KeyEvent(KeyCode.arrowRight)); // expand
      tester.sendKey(const KeyEvent(KeyCode.arrowDown)); // → config.json
      tester.sendKey(const KeyEvent(KeyCode.enter)); // open
      final out = tester.renderToString(size: _size);
      expect(out, contains('config.json'));
      expect(out, contains('telemetry'));
    });
  });

  group('agent', () {
    // A tall viewport so the whole streamed turn is present in the snapshot
    // (the conversation is bottom-pinned, so a short viewport scrolls the head
    // off — fine in use, awkward to assert against).
    const tall = CellSize(120, 60);

    testWidgets('streams a Claude-Code-style turn: todos, tools, diff', (
      tester,
    ) {
      tester.pumpWidget(const AgentApp());
      tester.pump(const Duration(seconds: 6)); // drain the streamed reply
      final out = tester.renderToString(size: tall);
      expect(out, contains('Fleury Code'));
      expect(out, contains('Update Todos'));
      expect(out, contains('Read(lib/main.dart)'));
      expect(out, contains('Update(lib/main.dart)'));
      expect(out, contains('packageVersion')); // a line from the diff body
      expect(out, contains('ready')); // streaming finished
    });

    testWidgets('Enter advances to the next scripted turn', (tester) {
      tester.pumpWidget(const AgentApp());
      tester.pump(const Duration(seconds: 6));
      tester.sendKey(const KeyEvent(KeyCode.enter)); // submit → next
      tester.pump(const Duration(seconds: 6));
      expect(tester.renderToString(size: tall), contains('All tests passed!'));
    });
  });

  group('debug playground', () {
    testWidgets('renders the scenario menu and readout', (tester) {
      tester.pumpWidget(const DebugPlaygroundApp());
      final out = tester.renderToString(size: _size);
      expect(out, contains('Fleury Debug Playground'));
      expect(out, contains('Scenarios'));
      expect(out, contains('Spike a slow frame'));
      expect(out, contains('Throw in a handler'));
      expect(out, contains('Emit a log burst'));
      expect(out, contains('What just happened'));
      expect(out, contains('press Ctrl+G')); // Ctrl+G is the reliable toggle
    });

    testWidgets('arrow keys traverse the scenario buttons via the app route', (
      tester,
    ) {
      // The sample runner mounts every showcase as FleuryApp(home: ...), whose
      // Navigator gives the home route its traversal group.
      tester.pumpFleuryHome(const DebugPlaygroundApp());
      tester.render(size: _size); // autofocus lands on the first button
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.button, focused: true)
            .label,
        'Spike a slow frame',
      );
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.render(size: _size);
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.button, focused: true)
            .label,
        'Throw in a handler',
        reason: '↓ moves focus to the next button inside the traversal group',
      );
    });

    testWidgets('activating a scenario via its semantic action updates the '
        'readout — the same path an agent drives over fleury mcp', (
      tester,
    ) async {
      tester.pumpWidget(const DebugPlaygroundApp());
      tester.render(size: _size); // mount + focus
      await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.button,
        label: 'Emit a log burst',
      );
      final out = tester.renderToString(size: _size);
      expect(out, contains('emitted 40 log lines'));
      expect(out, contains('log bursts')); // the tally row is present
    });
  });
}
