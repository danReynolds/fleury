import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury/src/runtime/output_capture.dart' show OutputCapture;
import 'package:test/test.dart';

const _hostileTerminalText =
    'HOSTILE \x1b]52;c;SECRET_CLIPBOARD\x07 after \x1b[2J end';

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

Future<File> _script(Directory dir, String name, String source) async {
  final file = File('${dir.path}/$name.dart');
  await file.writeAsString(source);
  return file;
}

void _expectNoHostileTerminalPayload(String text) {
  expect(text, isNot(contains('\x1B')));
  expect(text, isNot(contains('\x07')));
  expect(text, isNot(contains('SECRET_CLIPBOARD')));
  expect(text, isNot(contains('[2J')));
}

void main() {
  group('terminal-bound untrusted text', () {
    test('sanitizer treats active terminal payloads as data', () {
      final cleaned = sanitizeForDisplay(_hostileTerminalText);

      expect(cleaned, contains(replacementCharacter));
      expect(cleaned, contains('HOSTILE'));
      _expectNoHostileTerminalPayload(cleaned);
    });

    testWidgets('Text widget never writes active terminal payload cells', (
      tester,
    ) {
      tester.pumpWidget(const Text(_hostileTerminalText));

      final rendered = tester.renderToString(size: const CellSize(80, 1));

      expect(rendered, contains(replacementCharacter));
      expect(rendered, contains('HOSTILE'));
      _expectNoHostileTerminalPayload(rendered);
    });

    test('OutputCapture can sanitize terminal-bound captured lines', () {
      final buffer = LogBuffer();
      final liveLines = <LogLine>[];
      final capture = OutputCapture(
        buffer: buffer,
        onLine: liveLines.add,
        sanitizeForTerminal: true,
      );

      capture.addChunk(_hostileTerminalText, LogSource.stdout);
      capture.addChunk('\n', LogSource.stdout);

      final buffered = buffer.lines.single.text;
      final live = liveLines.single.text;
      expect(buffered, live);
      expect(buffered, contains(replacementCharacter));
      _expectNoHostileTerminalPayload(buffered);
    });

    test('runApp stray output hook receives sanitized lines', () async {
      final driver = FakeTerminalDriver();
      final captured = <LogLine>[];
      final future = runApp(
        const Text('ui'),
        driver: driver,
        enableHotReload: false,
        onStrayOutput: captured.add,
        onEvent: (_) {
          print(_hostileTerminalText);
          return const ExitRequested();
        },
      );
      await _settle();
      driver.enqueue(const KeyEvent(keyCode: KeyCode.enter));
      await future;

      final line = captured.single.text;
      expect(line, contains(replacementCharacter));
      _expectNoHostileTerminalPayload(line);
      await driver.dispose();
    });

    test('runApp replay emits sanitized stray output after restore', () async {
      final driver = FakeTerminalDriver();
      final future = runApp(
        const Text('ui'),
        driver: driver,
        enableHotReload: false,
        onEvent: (_) {
          print(_hostileTerminalText);
          return const ExitRequested();
        },
      );
      await _settle();
      driver.enqueue(const KeyEvent(keyCode: KeyCode.enter));
      await future;

      expect(driver.output, contains('HOSTILE $replacementCharacter'));
      final replayed = driver.output.substring(
        driver.output.indexOf('HOSTILE'),
      );
      _expectNoHostileTerminalPayload(replayed);
      await driver.dispose();
    });

    test('ProcessTaskController stores sanitized subprocess output', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'fleury_security_process_',
      );
      try {
        final script = await _script(tempDir, 'hostile_output', r'''
import 'dart:io';

void main() {
  stdout.write('HOSTILE \x1B]52;c;SECRET_CLIPBOARD');
  stdout.add([0x07]);
  stdout.writeln(' after \x1B[2J end');
}
''');
        final controller = ProcessTaskController(id: 'process');
        final result = await controller.startProcess(
          ProcessTaskCommand(Platform.resolvedExecutable, [script.path]),
        );

        expect(result.succeeded, isTrue);
        final output = controller.output.single;
        expect(output.sanitized, isTrue);
        expect(output.text, contains(replacementCharacter));
        _expectNoHostileTerminalPayload(output.text);
        controller.dispose();
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}
