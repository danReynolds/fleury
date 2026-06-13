// Round-trip and fuzz tests for the structured serve frames (PLAN,
// SEMANTICS, INPUT_EVENT). Property tests seed a fixed RNG so failures
// reproduce; the fuzz block feeds malformed payloads and asserts the
// decoder rejects them cleanly instead of throwing wild or hanging.

import 'dart:math';
import 'dart:typed_data';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/remote/remote_codec.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PLAN frame round-trip', () {
    test('full plan with styled wide/empty/protocol runs survives the wire', () {
      final plan = RemotePlan(
        size: const CellSize(80, 24),
        fullRepaint: true,
        scrollUpRows: null,
        rows: [
          RowSpanModel(
            row: 0,
            cols: 80,
            runs: [
              const CellSpanRun(
                startCol: 0,
                widthCols: 5,
                text: 'hello',
                style: CellStyle(
                  foreground: RgbColor(200, 100, 50),
                  background: AnsiColor(4),
                  bold: true,
                  underline: false,
                ),
                kind: CellRunKind.text,
                correction: WidthCorrection.none,
              ),
              const CellSpanRun(
                startCol: 5,
                widthCols: 2,
                text: '世',
                style: CellStyle(foreground: IndexedColor(120)),
                kind: CellRunKind.wideText,
                correction: WidthCorrection.pinToCellWidth,
              ),
              const CellSpanRun(
                startCol: 7,
                widthCols: 1,
                text: protocolPlaceholderGlyph,
                style: CellStyle.empty,
                kind: CellRunKind.protocolPlaceholder,
                correction: WidthCorrection.none,
              ),
            ],
          ),
        ],
      );
      final decoded = decodeRemotePlan(encodeRemotePlan(plan));
      expect(decoded.size, plan.size);
      expect(decoded.fullRepaint, isTrue);
      expect(decoded.scrollUpRows, isNull);
      expect(decoded.rows, hasLength(1));
      final row = decoded.rows.single;
      expect(row.row, 0);
      expect(row.runs, hasLength(3));
      // Exact style equality (tri-state attrs preserved).
      expect(row.runs[0].style, plan.rows[0].runs[0].style);
      expect(row.runs[0].text, 'hello');
      expect(row.runs[1].kind, CellRunKind.wideText);
      expect(row.runs[1].correction, WidthCorrection.pinToCellWidth);
      expect(row.runs[1].text, '世');
      expect(row.runs[2].kind, CellRunKind.protocolPlaceholder);
    });

    test('scroll-up plan carries the shift', () {
      final plan = RemotePlan(
        size: const CellSize(40, 12),
        fullRepaint: false,
        scrollUpRows: 3,
        rows: const [],
      );
      final decoded = decodeRemotePlan(encodeRemotePlan(plan));
      expect(decoded.scrollUpRows, 3);
      expect(decoded.fullRepaint, isFalse);
      expect(decoded.rows, isEmpty);
    });

    test('randomized plans round-trip exactly (seeded)', () {
      final rng = Random(0x5EED);
      for (var iter = 0; iter < 200; iter++) {
        final plan = _randomPlan(rng);
        final decoded = decodeRemotePlan(encodeRemotePlan(plan));
        _expectPlanEqual(decoded, plan);
      }
    });

    test('tri-state style attributes round-trip null vs false', () {
      const styles = [
        CellStyle(bold: true),
        CellStyle(bold: false),
        CellStyle(),
        CellStyle(
          italic: true,
          dim: false,
          strikethrough: true,
          inverse: false,
        ),
      ];
      for (final style in styles) {
        final plan = RemotePlan(
          size: const CellSize(4, 1),
          fullRepaint: false,
          rows: [
            RowSpanModel(
              row: 0,
              cols: 4,
              runs: [
                CellSpanRun(
                  startCol: 0,
                  widthCols: 1,
                  text: 'x',
                  style: style,
                  kind: CellRunKind.text,
                  correction: WidthCorrection.none,
                ),
              ],
            ),
          ],
        );
        final decoded = decodeRemotePlan(encodeRemotePlan(plan));
        expect(decoded.rows.single.runs.single.style, style);
      }
    });
  });

  group('INPUT_EVENT round-trip', () {
    test('key event with code, char, modifiers, type', () {
      const event = KeyEvent(
        keyCode: KeyCode.arrowDown,
        char: 'c',
        modifiers: {KeyModifier.ctrl, KeyModifier.shift},
        type: KeyEventType.repeat,
      );
      final decoded = decodeInputEvent(encodeInputEvent(event)) as KeyEvent;
      expect(decoded, event);
    });

    test('all carried event kinds round-trip (seeded)', () {
      final rng = Random(0xC0DEC);
      for (var iter = 0; iter < 200; iter++) {
        final event = _randomEvent(rng);
        final decoded = decodeInputEvent(encodeInputEvent(event));
        expect(decoded, event, reason: 'iter $iter: $event');
      }
    });

    test('paste, resize, and composition kinds', () {
      final events = <TuiEvent>[
        const PasteEvent('multi\nline\tpaste'),
        const ResizeEvent(CellSize(100, 30)),
        const TextCompositionEvent.update('ko'),
        const TextCompositionEvent.commit('korean'),
        const TextCompositionEvent.cancel(),
        const TextInputEvent('日本語'),
        const MouseEvent(
          kind: MouseEventKind.scrollUp,
          button: MouseButton.none,
          col: 12,
          row: 4,
        ),
      ];
      for (final event in events) {
        expect(decodeInputEvent(encodeInputEvent(event)), event);
      }
    });

    test('through the framing layer', () {
      const event = KeyEvent(keyCode: KeyCode.enter);
      final wire = encodeFrame(const InputEventFrame(event));
      final out = (FrameDecoder()..feed(wire)).drain().toList();
      expect(out, hasLength(1));
      expect((out.single as InputEventFrame).event, event);
    });
  });

  group('PLAN/SEMANTICS through the framing layer', () {
    test('plan frame round-trips through encode/decode framing', () {
      final plan = _randomPlan(Random(7));
      final wire = encodeFrame(PlanFrame(plan));
      final out = (FrameDecoder()..feed(wire)).drain().toList();
      expect(out, hasLength(1));
      _expectPlanEqual((out.single as PlanFrame).plan, plan);
    });

    test('semantics frame carries JSON bytes verbatim', () {
      final json = Uint8List.fromList('{"nodeCount":3}'.codeUnits);
      final wire = encodeFrame(SemanticsFrame(json));
      final out = (FrameDecoder()..feed(wire)).drain().toList();
      expect((out.single as SemanticsFrame).json, json);
    });

    test('INIT carries the protocol version', () {
      final wire = encodeFrame(
        const InitFrame(
          size: CellSize(80, 24),
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
        ),
      );
      final out = (FrameDecoder()..feed(wire)).drain().toList();
      expect((out.single as InitFrame).protocolVersion, remoteProtocolVersion);
    });

    test('INIT without v defaults to protocol version 1', () {
      // Hand-frame a v1-style INIT (no `v=`).
      const body = 'cols=80,rows=24,color=truecolor,image=halfBlock,tmux=0';
      final payload = Uint8List.fromList(body.codeUnits);
      final framed = BytesBuilder()
        ..addByte(FrameType.init.code)
        ..add((ByteData(4)..setUint32(0, payload.length)).buffer.asUint8List())
        ..add(payload);
      final out = (FrameDecoder()..feed(framed.toBytes())).drain().toList();
      expect((out.single as InitFrame).protocolVersion, 1);
    });
  });

  group('malformed payload fuzz', () {
    test('truncated plan payloads throw RemoteCodecException, never hang', () {
      final plan = _randomPlan(Random(99));
      final full = encodeRemotePlan(plan);
      for (var cut = 0; cut < full.length; cut++) {
        final truncated = Uint8List.sublistView(full, 0, cut);
        expect(
          () => decodeRemotePlan(truncated),
          throwsA(isA<RemoteCodecException>()),
          reason: 'cut at $cut',
        );
      }
    });

    test('random bytes as plan/event payloads reject cleanly', () {
      final rng = Random(0xFADE);
      for (var iter = 0; iter < 500; iter++) {
        final len = rng.nextInt(64);
        final bytes = Uint8List.fromList(
          [for (var i = 0; i < len; i++) rng.nextInt(256)],
        );
        // Must throw a typed codec error, not a raw RangeError / never hang.
        expect(
          () {
            try {
              decodeRemotePlan(bytes);
            } on RemoteCodecException {
              rethrow;
            }
          },
          anyOf(returnsNormally, throwsA(isA<RemoteCodecException>())),
        );
        expect(
          () {
            try {
              decodeInputEvent(bytes);
            } on RemoteCodecException {
              rethrow;
            }
          },
          anyOf(returnsNormally, throwsA(isA<RemoteCodecException>())),
        );
      }
    });

    test('unknown enum indices in a plan are rejected', () {
      // A run with kind index 250 (out of range).
      final w = BytesBuilder()
        ..addByte(0) // flags
        ..add((ByteData(2)..setUint16(0, 4)).buffer.asUint8List()) // cols
        ..add((ByteData(2)..setUint16(0, 1)).buffer.asUint8List()) // rows
        ..add((ByteData(2)..setUint16(0, 1)).buffer.asUint8List()) // rowCount
        ..add((ByteData(2)..setUint16(0, 0)).buffer.asUint8List()) // rowIndex
        ..add((ByteData(2)..setUint16(0, 4)).buffer.asUint8List()) // rowCols
        ..add((ByteData(2)..setUint16(0, 1)).buffer.asUint8List()) // runCount
        ..add((ByteData(2)..setUint16(0, 0)).buffer.asUint8List()) // startCol
        ..add((ByteData(2)..setUint16(0, 1)).buffer.asUint8List()) // widthCols
        ..addByte(250); // kind index (invalid)
      expect(
        () => decodeRemotePlan(w.toBytes()),
        throwsA(isA<RemoteCodecException>()),
      );
    });
  });
}

// ---- generators ------------------------------------------------------------

RemotePlan _randomPlan(Random rng) {
  final cols = 1 + rng.nextInt(120);
  final rows = 1 + rng.nextInt(50);
  final rowCount = rng.nextInt(6);
  return RemotePlan(
    size: CellSize(cols, rows),
    fullRepaint: rng.nextBool(),
    scrollUpRows: rng.nextBool() ? rng.nextInt(rows) : null,
    rows: [
      for (var i = 0; i < rowCount; i++)
        RowSpanModel(
          row: rng.nextInt(rows),
          cols: cols,
          runs: [
            for (var j = 0; j < rng.nextInt(5); j++) _randomRun(rng, cols),
          ],
        ),
    ],
  );
}

CellSpanRun _randomRun(Random rng, int cols) {
  const texts = ['a', 'hi', '世', '🙂', '', 'tab\tless', protocolPlaceholderGlyph];
  return CellSpanRun(
    startCol: rng.nextInt(cols),
    widthCols: rng.nextInt(3),
    text: texts[rng.nextInt(texts.length)],
    style: _randomStyle(rng),
    kind: CellRunKind.values[rng.nextInt(CellRunKind.values.length)],
    correction: WidthCorrection.values[rng.nextInt(2)],
  );
}

CellStyle _randomStyle(Random rng) {
  bool? triState() => switch (rng.nextInt(3)) {
    0 => null,
    1 => true,
    _ => false,
  };
  Color? color() => switch (rng.nextInt(4)) {
    0 => null,
    1 => AnsiColor(rng.nextInt(16)),
    2 => IndexedColor(rng.nextInt(256)),
    _ => RgbColor(rng.nextInt(256), rng.nextInt(256), rng.nextInt(256)),
  };
  return CellStyle(
    foreground: color(),
    background: color(),
    bold: triState(),
    dim: triState(),
    italic: triState(),
    underline: triState(),
    inverse: triState(),
    strikethrough: triState(),
  );
}

TuiEvent _randomEvent(Random rng) {
  Set<KeyModifier> mods() => {
    for (final m in KeyModifier.values)
      if (rng.nextBool()) m,
  };
  switch (rng.nextInt(6)) {
    case 0:
      // KeyEvent must carry a keyCode or char.
      final hasCode = rng.nextBool();
      return KeyEvent(
        keyCode: hasCode
            ? KeyCode.values[rng.nextInt(KeyCode.values.length)]
            : null,
        char: hasCode && rng.nextBool() ? null : String.fromCharCode(
          97 + rng.nextInt(26),
        ),
        modifiers: mods(),
        type: KeyEventType.values[rng.nextInt(KeyEventType.values.length)],
      );
    case 1:
      return TextInputEvent(_randomText(rng));
    case 2:
      return switch (rng.nextInt(3)) {
        0 => TextCompositionEvent.update(_randomText(rng)),
        1 => TextCompositionEvent.commit(
          rng.nextBool() ? _randomText(rng) : null,
        ),
        _ => const TextCompositionEvent.cancel(),
      };
    case 3:
      return MouseEvent(
        kind: MouseEventKind.values[rng.nextInt(MouseEventKind.values.length)],
        button: MouseButton.values[rng.nextInt(MouseButton.values.length)],
        col: rng.nextInt(500),
        row: rng.nextInt(200),
        modifiers: mods(),
      );
    case 4:
      return PasteEvent(_randomText(rng));
    default:
      return ResizeEvent(CellSize(1 + rng.nextInt(300), 1 + rng.nextInt(100)));
  }
}

String _randomText(Random rng) {
  const chunks = ['a', 'word', '世界', '🙂', '\n', '\t', ' '];
  final n = rng.nextInt(5);
  return [for (var i = 0; i < n; i++) chunks[rng.nextInt(chunks.length)]].join();
}

void _expectPlanEqual(RemotePlan a, RemotePlan b) {
  expect(a.size, b.size);
  expect(a.fullRepaint, b.fullRepaint);
  expect(a.scrollUpRows, b.scrollUpRows);
  expect(a.rows.length, b.rows.length);
  for (var i = 0; i < a.rows.length; i++) {
    final ra = a.rows[i];
    final rb = b.rows[i];
    expect(ra.row, rb.row);
    expect(ra.cols, rb.cols);
    expect(ra.runs.length, rb.runs.length);
    for (var j = 0; j < ra.runs.length; j++) {
      expect(ra.runs[j].startCol, rb.runs[j].startCol);
      expect(ra.runs[j].widthCols, rb.runs[j].widthCols);
      expect(ra.runs[j].text, rb.runs[j].text);
      expect(ra.runs[j].style, rb.runs[j].style);
      expect(ra.runs[j].kind, rb.runs[j].kind);
      expect(ra.runs[j].correction, rb.runs[j].correction);
    }
  }
}
