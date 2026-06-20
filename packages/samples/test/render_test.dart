import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
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
    testWidgets('renders the tree and a markdown preview by default', (
      tester,
    ) {
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
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight)); // expand lib/
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // → main.dart
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // open
      final out = tester.renderToString(size: _size);
      expect(out, contains('main.dart'));
      expect(out, contains('runTui'));
    });

    testWidgets('opening config.json shows the JSON preview', (tester) {
      tester.pumpWidget(const FileManagerApp());
      tester.render(size: _size);
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // → test/
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // → assets/
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowRight)); // expand
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // → config.json
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // open
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
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter)); // submit → next
      tester.pump(const Duration(seconds: 6));
      expect(
        tester.renderToString(size: tall),
        contains('All tests passed!'),
      );
    });
  });
}
