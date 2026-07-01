// Round-trip and fuzz tests for the structured serve frames (PLAN,
// SEMANTICS, INPUT_EVENT). The PLAN tests cover the cell-patch wire: a
// build from prev/next, encode/decode, and apply-to-mirror reproducing
// the source frame. Property tests seed a fixed RNG; the fuzz block feeds
// malformed payloads and asserts clean rejection.

import 'dart:math';
import 'dart:typed_data';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/remote/remote_codec.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PLAN frame round-trip', () {
    test('hand-built plan with styled runs survives the wire', () {
      final plan = RemotePlan(
        size: const CellSize(80, 24),
        fullRepaint: true,
        styleTable: const [
          CellStyle.empty,
          CellStyle(foreground: RgbColor(200, 100, 50), bold: true),
          CellStyle(foreground: IndexedColor(120)),
        ],
        patches: const [
          RemoteRowPatch(
            row: 0,
            startCol: 0,
            runs: [
              RemotePatchRun(styleIndex: 1, text: 'hello'),
              RemotePatchRun(styleIndex: 2, text: '世'),
              RemotePatchRun(styleIndex: 0, text: '  '),
            ],
          ),
        ],
      );
      final decoded = decodeRemotePlan(encodeRemotePlan(plan));
      expect(decoded.size, plan.size);
      expect(decoded.fullRepaint, isTrue);
      expect(decoded.scrollUpRows, isNull);
      expect(decoded.styleTable, plan.styleTable);
      expect(decoded.patches, hasLength(1));
      final patch = decoded.patches.single;
      expect(patch.row, 0);
      expect(patch.runs.map((r) => r.text).toList(), ['hello', '世', '  ']);
      expect(patch.runs.map((r) => r.styleIndex).toList(), [1, 2, 0]);
    });

    test('scroll-up plan carries the shift', () {
      final plan = RemotePlan(
        size: const CellSize(40, 12),
        fullRepaint: false,
        scrollUpRows: 3,
        styleTable: const [],
        patches: const [],
      );
      final decoded = decodeRemotePlan(encodeRemotePlan(plan));
      expect(decoded.scrollUpRows, 3);
      expect(decoded.patches, isEmpty);
    });

    test(
      'build -> encode -> decode -> apply reproduces the frame (seeded)',
      () {
        final rng = Random(0x5EED);
        const alphabet = 'abcdefgh 0123#@世界';
        for (var iter = 0; iter < 200; iter++) {
          final cols = 4 + rng.nextInt(40);
          final rows = 1 + rng.nextInt(12);
          final prev = CellBuffer(CellSize(cols, rows));
          final next = CellBuffer(CellSize(cols, rows));
          // Seed prev with some content, then mutate into next.
          for (var r = 0; r < rows; r++) {
            final text = _randomText(rng, alphabet, cols);
            prev.writeText(CellOffset(0, r), text, style: _randomStyle(rng));
          }
          _copyBuffer(prev, next);
          // Mutate a few rows.
          for (var m = 0; m < rng.nextInt(rows + 1); m++) {
            final r = rng.nextInt(rows);
            final text = _randomText(rng, alphabet, cols);
            next.writeText(CellOffset(0, r), text, style: _randomStyle(rng));
          }
          final full = rng.nextInt(5) == 0;
          final plan = buildRemotePlan(prev, next, fullRepaint: full);
          final decoded = decodeRemotePlan(encodeRemotePlan(plan));
          // Apply to a mirror seeded with prev.
          final mirror = CellBuffer(CellSize(cols, rows));
          _copyBuffer(prev, mirror);
          applyRemotePlanToBuffer(decoded, mirror);
          // The mirror's rendered content must match next.
          expect(
            _renderAll(mirror),
            _renderAll(next),
            reason: 'iter $iter (full=$full)',
          );
        }
      },
    );
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

  group('framing layer', () {
    test('plan frame round-trips through encode/decode framing', () {
      final prev = CellBuffer(const CellSize(20, 4));
      final next = CellBuffer(const CellSize(20, 4));
      next.writeText(const CellOffset(0, 1), 'changed');
      final plan = buildRemotePlan(prev, next, fullRepaint: false);
      final wire = encodeFrame(PlanFrame(plan));
      final out = (FrameDecoder()..feed(wire)).drain().toList();
      expect(out, hasLength(1));
      final decoded = (out.single as PlanFrame).plan;
      expect(decoded.patches.map((p) => p.row), contains(1));
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
      final prev = CellBuffer(const CellSize(30, 8));
      final next = CellBuffer(const CellSize(30, 8));
      for (var r = 0; r < 8; r++) {
        next.writeText(
          CellOffset(0, r),
          'row $r content here',
          style: const CellStyle(bold: true),
        );
      }
      final full = encodeRemotePlan(
        buildRemotePlan(prev, next, fullRepaint: true),
      );
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
        final bytes = Uint8List.fromList([
          for (var i = 0; i < len; i++) rng.nextInt(256),
        ]);
        expect(() {
          try {
            decodeRemotePlan(bytes);
          } on RemoteCodecException {
            rethrow;
          }
        }, anyOf(returnsNormally, throwsA(isA<RemoteCodecException>())));
        expect(() {
          try {
            decodeInputEvent(bytes);
          } on RemoteCodecException {
            rethrow;
          }
        }, anyOf(returnsNormally, throwsA(isA<RemoteCodecException>())));
      }
    });

    test('a run referencing an out-of-range style index is rejected', () {
      // Build valid bytes, then corrupt a run's style index to a huge value
      // by hand-crafting a tiny plan with styleTable=[] but a run idx=5.
      final w = BytesBuilder()
        ..addByte(0) // flags
        ..addByte(4) // cols (varint)
        ..addByte(1) // rows
        ..addByte(0) // styleCount = 0
        ..addByte(1) // patchCount = 1
        ..addByte(0) // row
        ..addByte(0) // startCol
        ..addByte(1) // runCount
        ..addByte(5) // styleIndex = 5 (out of range)
        ..addByte(1) // text len = 1
        ..addByte(0x78); // 'x'
      expect(
        () => decodeRemotePlan(w.toBytes()),
        throwsA(isA<RemoteCodecException>()),
      );
    });
  });
}

// ---- helpers ---------------------------------------------------------------

void _copyBuffer(CellBuffer from, CellBuffer to) {
  for (var r = 0; r < from.size.rows; r++) {
    for (var c = 0; c < from.size.cols; c++) {
      final cell = from.atColRow(c, r);
      if (cell.role == CellRole.leading && cell.grapheme != null) {
        to.writeText(CellOffset(c, r), cell.grapheme!, style: cell.style);
      }
    }
  }
}

String _renderAll(CellBuffer b) {
  final sb = StringBuffer();
  for (var r = 0; r < b.size.rows; r++) {
    for (var c = 0; c < b.size.cols; c++) {
      sb.write(b.atColRow(c, r).grapheme ?? ' ');
    }
    sb.write('\n');
  }
  return sb.toString();
}

String _randomText(Random rng, String alphabet, int maxLen) {
  final n = rng.nextInt(maxLen);
  return [
    for (var i = 0; i < n; i++) alphabet[rng.nextInt(alphabet.length)],
  ].join();
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
    italic: triState(),
    underline: triState(),
  );
}

TuiEvent _randomEvent(Random rng) {
  Set<KeyModifier> mods() => {
    for (final m in KeyModifier.values)
      if (rng.nextBool()) m,
  };
  switch (rng.nextInt(6)) {
    case 0:
      final hasCode = rng.nextBool();
      return KeyEvent(
        keyCode: hasCode
            ? KeyCode.values[rng.nextInt(KeyCode.values.length)]
            : null,
        char: hasCode && rng.nextBool()
            ? null
            : String.fromCharCode(97 + rng.nextInt(26)),
        modifiers: mods(),
        type: KeyEventType.values[rng.nextInt(KeyEventType.values.length)],
      );
    case 1:
      return TextInputEvent(_randomText(rng, 'abc世 \n\t', 5));
    case 2:
      return switch (rng.nextInt(3)) {
        0 => TextCompositionEvent.update(_randomText(rng, 'ko', 4)),
        1 => TextCompositionEvent.commit(
          rng.nextBool() ? _randomText(rng, 'ko', 4) : null,
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
      return PasteEvent(_randomText(rng, 'abc \n', 6));
    default:
      return ResizeEvent(CellSize(1 + rng.nextInt(300), 1 + rng.nextInt(100)));
  }
}
