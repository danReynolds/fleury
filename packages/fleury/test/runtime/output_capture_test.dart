import 'package:fleury/src/runtime/output_capture.dart';
import 'package:test/test.dart';

void main() {
  group('OutputCapture', () {
    test('lines are buffered and routed to onLine, tagged by source', () {
      final buffer = LogBuffer();
      final hooked = <LogLine>[];
      final capture = OutputCapture(buffer: buffer, onLine: hooked.add);

      capture.addLine('OUT-LINE', LogSource.stdout);
      capture.addLine('ERR-LINE', LogSource.stderr);

      expect(buffer.lines.map((l) => l.text), ['OUT-LINE', 'ERR-LINE']);
      expect(hooked.map((l) => l.text), ['OUT-LINE', 'ERR-LINE']);
      expect(
        hooked.map((l) => l.source),
        [LogSource.stdout, LogSource.stderr],
      );
    });

    test('partial writes are assembled into whole lines', () {
      final buffer = LogBuffer();
      final capture = OutputCapture(buffer: buffer);

      capture.addChunk('par', LogSource.stdout);
      expect(buffer.lines, isEmpty, reason: 'no newline yet');
      capture.addChunk('tial\nnext-', LogSource.stdout);
      expect(buffer.lines.map((l) => l.text), ['partial']);

      capture.flushPartials();
      expect(
        buffer.lines.map((l) => l.text),
        ['partial', 'next-'],
        reason: 'flushPartials emits the unterminated tail',
      );
    });

    test('streams keep independent partial-line state', () {
      final buffer = LogBuffer();
      final capture = OutputCapture(buffer: buffer);

      capture.addChunk('out-', LogSource.stdout);
      capture.addChunk('err-line\n', LogSource.stderr);
      expect(buffer.lines.single.text, 'err-line');
      expect(buffer.lines.single.source, LogSource.stderr);

      capture.addChunk('done\n', LogSource.stdout);
      expect(buffer.lines.last.text, 'out-done');
      expect(buffer.lines.last.source, LogSource.stdout);
    });

    test('unterminated lines are emitted in bounded segments', () {
      final buffer = LogBuffer();
      final capture = OutputCapture(buffer: buffer, maxPendingLineLength: 4);

      capture.addChunk('abcdefghij', LogSource.stdout);
      expect(buffer.lines.map((line) => line.text), ['abcd', 'efgh']);

      capture.flushPartials();
      expect(buffer.lines.map((line) => line.text), ['abcd', 'efgh', 'ij']);
    });

    test('newline after a full bounded segment adds no phantom empty line', () {
      final buffer = LogBuffer();
      final capture = OutputCapture(buffer: buffer, maxPendingLineLength: 4);

      capture.addChunk('abcd\n\n', LogSource.stdout);

      expect(buffer.lines.map((line) => line.text), ['abcd', '']);
    });
  });
}
