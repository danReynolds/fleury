import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:fleury/src/runtime/output_capture.dart' show OutputCapture;
import 'package:test/test.dart';

const _hostileTerminalText =
    'HOSTILE \x1b]52;c;SECRET_CLIPBOARD\x07 after \x1b[2J end';

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
  });
}
