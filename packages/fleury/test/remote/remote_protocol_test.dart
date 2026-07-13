// Wire-format round-trip tests for the remote-rendering protocol.

import 'dart:typed_data';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('encode/decode round-trip', () {
    test(
      'INIT carries size, color mode, glyph tier, image protocol, tmux flag',
      () {
        final frame = const InitFrame(
          size: CellSize(132, 43),
          colorMode: ColorMode.truecolor,
          glyphTier: GlyphTier.ascii,
          imageProtocol: ImageProtocol.kitty,
          tmuxPassthrough: true,
        );
        final wire = encodeFrame(frame);
        final decoder = FrameDecoder()..feed(wire);
        final out = decoder.drain().toList();
        expect(out, hasLength(1));
        final decoded = out.single as InitFrame;
        expect(decoded.size, const CellSize(132, 43));
        expect(decoded.colorMode, ColorMode.truecolor);
        expect(decoded.glyphTier, GlyphTier.ascii);
        expect(decoded.imageProtocol, ImageProtocol.kitty);
        expect(decoded.tmuxPassthrough, isTrue);
      },
    );

    test('INIT round-trips the optional hyperlinks capability', () {
      final withLinks = const InitFrame(
        size: CellSize(80, 24),
        colorMode: ColorMode.truecolor,
        imageProtocol: ImageProtocol.halfBlock,
        tmuxPassthrough: false,
        images: InlineImageSupport.placements,
        hyperlinks: true,
      );
      final decodedOn =
          (FrameDecoder()..feed(encodeFrame(withLinks))).drain().single
              as InitFrame;
      expect(decodedOn.hyperlinks, isTrue);
    });

    test(
      'a hyperlinks-false INIT is byte-identical to a peer that never sent the '
      'field, and both decode to false (additive/backward-compatible)',
      () {
        const base = InitFrame(
          size: CellSize(80, 24),
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
        );
        const explicitFalse = InitFrame(
          size: CellSize(80, 24),
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
          hyperlinks: false,
        );
        // No `hyperlinks=` param is emitted when false, so an older peer's wire
        // and a new peer's link-free wire are the same bytes.
        expect(encodeFrame(explicitFalse), encodeFrame(base));
        final decoded =
            (FrameDecoder()..feed(encodeFrame(base))).drain().single
                as InitFrame;
        expect(
          decoded.hyperlinks,
          isFalse,
          reason: 'an absent hyperlinks param decodes to false',
        );
      },
    );

    test('INPUT preserves arbitrary binary including 0x1B and 0x00', () {
      final bytes = Uint8List.fromList([
        0x1B, 0x5B, 0x41, // ESC [ A — arrow up
        0x00, 0xFF, 0x7F, // edge bytes
      ]);
      final wire = encodeFrame(InputFrame(bytes));
      final decoded = (FrameDecoder()..feed(wire)).drain().toList();
      expect(decoded, hasLength(1));
      expect((decoded.single as InputFrame).bytes, bytes);
    });

    test('OUTPUT preserves arbitrary ANSI', () {
      final ansi = Uint8List.fromList(
        '\x1B[?2026h\x1B[1;1Hhello\x1B[?2026l'.codeUnits,
      );
      final wire = encodeFrame(OutputFrame(ansi));
      final decoded = (FrameDecoder()..feed(wire)).drain().toList();
      expect((decoded.single as OutputFrame).bytes, ansi);
    });

    test('RESIZE preserves the new size', () {
      final wire = encodeFrame(const ResizeFrame(CellSize(200, 60)));
      final decoded = (FrameDecoder()..feed(wire)).drain().toList();
      expect((decoded.single as ResizeFrame).size, const CellSize(200, 60));
    });

    test('BYE has no payload', () {
      final wire = encodeFrame(const ByeFrame());
      expect(wire.length, 5, reason: '1 type byte + 4 length bytes');
      final decoded = (FrameDecoder()..feed(wire)).drain().toList();
      expect(decoded.single, isA<ByeFrame>());
    });

    test('CLIPBOARD_WRITE round-trips seq and text', () {
      final wire = encodeFrame(const ClipboardWriteFrame(42, 'copy me — ✂'));
      final decoded =
          (FrameDecoder()..feed(wire)).drain().single as ClipboardWriteFrame;
      expect(decoded.seq, 42);
      expect(decoded.text, 'copy me — ✂');
    });

    test('CLIPBOARD_RESULT round-trips seq and status', () {
      final wire = encodeFrame(
        const ClipboardResultFrame(7, RemoteClipboardStatus.denied),
      );
      final decoded =
          (FrameDecoder()..feed(wire)).drain().single as ClipboardResultFrame;
      expect(decoded.seq, 7);
      expect(decoded.status, RemoteClipboardStatus.denied);
    });

    test('CLIPBOARD_RESULT rejects an unknown status index', () {
      final raw = _rawFrame(FrameType.clipboardResult, const [
        0,
        0,
        0,
        1,
        0xEE,
      ]);
      final decoder = FrameDecoder()..feed(raw);
      expect(
        () => decoder.drain().toList(),
        throwsA(isA<RemoteProtocolException>()),
      );
    });

    test('CARET round-trips a rect and its absence', () {
      final withCaret = encodeFrame(CaretFrame(CellRect.fromLTWH(12, 3, 1, 1)));
      final decoded =
          (FrameDecoder()..feed(withCaret)).drain().single as CaretFrame;
      expect(decoded.caret, CellRect.fromLTWH(12, 3, 1, 1));

      final without = encodeFrame(const CaretFrame(null));
      final decodedNull =
          (FrameDecoder()..feed(without)).drain().single as CaretFrame;
      expect(decodedNull.caret, isNull);
    });

    test('SEMANTIC_ACTION_RESULT carries id, action, and status', () {
      final frame = SemanticActionResultFrame(
        const SemanticNodeId('save'),
        SemanticAction.activate,
        SemanticActionInvocationStatus.disabled,
      );
      final wire = encodeFrame(frame);
      final decoder = FrameDecoder()..feed(wire);
      final out = decoder.drain().toList();
      expect(out, hasLength(1));
      final decoded = out.single as SemanticActionResultFrame;
      expect(decoded.id, const SemanticNodeId('save'));
      expect(decoded.action, SemanticAction.activate);
      expect(decoded.status, SemanticActionInvocationStatus.disabled);
    });

    test('SEMANTIC_ACTION_RESULT rejects an unknown status name', () {
      final wire = encodeFrame(
        SemanticActionResultFrame(
          const SemanticNodeId('save'),
          SemanticAction.activate,
          SemanticActionInvocationStatus.completed,
        ),
      );
      // Corrupt the status by rewriting the payload with a bogus name via
      // the raw framing helper: id 's', action 'activate', status 'nope'.
      Uint8List vstr(String v) {
        final b = BytesBuilder()
          ..addByte(v.length)
          ..add(v.codeUnits);
        return b.toBytes();
      }

      final payload = BytesBuilder()
        ..add(vstr('s'))
        ..add(vstr('activate'))
        ..add(vstr('nope'));
      final raw = _rawFrame(FrameType.semanticActionResult, payload.toBytes());
      final decoder = FrameDecoder()..feed(raw);
      expect(
        () => decoder.drain().toList(),
        throwsA(isA<RemoteProtocolException>()),
      );
      expect(wire, isNotEmpty);
    });
  });

  group('decoder framing', () {
    test('three frames in one chunk decode in order', () {
      final builder = BytesBuilder()
        ..add(
          encodeFrame(
            const InitFrame(
              size: CellSize(80, 24),
              colorMode: ColorMode.ansi16,
              imageProtocol: ImageProtocol.halfBlock,
              tmuxPassthrough: false,
            ),
          ),
        )
        ..add(encodeFrame(InputFrame(Uint8List.fromList([0x71]))))
        ..add(encodeFrame(const ByeFrame()));
      final decoded = (FrameDecoder()..feed(builder.toBytes()))
          .drain()
          .toList();
      expect(decoded.map((f) => f.runtimeType).toList(), [
        InitFrame,
        InputFrame,
        ByeFrame,
      ]);
    });

    test('one frame split across two feeds buffers and emits cleanly', () {
      final wire = encodeFrame(InputFrame(Uint8List.fromList([1, 2, 3, 4, 5])));
      final decoder = FrameDecoder();
      // Split mid-payload (after type+length and 2 payload bytes).
      decoder.feed(wire.sublist(0, 7));
      expect(
        decoder.drain().toList(),
        isEmpty,
        reason: 'partial frame must not emit yet',
      );
      decoder.feed(wire.sublist(7));
      final out = decoder.drain().toList();
      expect(out, hasLength(1));
      expect((out.single as InputFrame).bytes, [1, 2, 3, 4, 5]);
    });

    test('split inside the 5-byte header still resumes correctly', () {
      final wire = encodeFrame(InputFrame(Uint8List.fromList([42])));
      final decoder = FrameDecoder();
      decoder.feed(wire.sublist(0, 2)); // type + 1 length byte
      expect(decoder.drain().toList(), isEmpty);
      decoder.feed(wire.sublist(2));
      final out = decoder.drain().toList();
      expect((out.single as InputFrame).bytes.single, 42);
    });

    test(
      'unknown frame type is skipped, valid frames after it still decode',
      () {
        // Hand-craft a frame with an unrecognised type byte (0xAB).
        final unknown = BytesBuilder()
          ..addByte(0xAB)
          ..add(Uint8List(4)..[3] = 3) // length 3
          ..add([1, 2, 3]);
        final good = encodeFrame(const ByeFrame());
        final decoder = FrameDecoder()
          ..feed(unknown.toBytes())
          ..feed(good);
        final out = decoder.drain().toList();
        expect(out, hasLength(1));
        expect(out.single, isA<ByeFrame>());
      },
    );

    test('oversized frame payloads fail UNRECOVERABLY (framing lost)', () {
      final wire = encodeFrame(InputFrame(Uint8List.fromList([1, 2, 3, 4, 5])));
      final decoder = FrameDecoder(maxPayloadLength: 4)..feed(wire);

      // The buffer is cleared with no known next-frame boundary, so the stream
      // can never resync — flagged recoverable:false so a peer tears down (and
      // shows a reload banner) rather than resyncing forever. See F19.
      expect(
        () => decoder.drain().toList(),
        throwsA(
          isA<RemoteProtocolException>().having(
            (e) => e.recoverable,
            'recoverable',
            isFalse,
          ),
        ),
      );
    });

    test('malformed RESIZE payloads fail RECOVERABLY (framing intact)', () {
      final wire = _rawFrame(FrameType.resize, 'rows=24'.codeUnits);
      final decoder = FrameDecoder()..feed(wire);

      // A valid length header was consumed, so exactly this frame is skipped
      // and the stream stays framed — recoverable:true (a peer resyncs and
      // carries on rather than tearing down). See F19.
      expect(
        () => decoder.drain().toList(),
        throwsA(
          isA<RemoteProtocolException>().having(
            (e) => e.recoverable,
            'recoverable',
            isTrue,
          ),
        ),
      );
    });

    test('invalid UTF-8 control payloads fail RECOVERABLY (framing intact)', () {
      final wire = _rawFrame(FrameType.init, const [0xFF]);
      final decoder = FrameDecoder()..feed(wire);

      expect(
        () => decoder.drain().toList(),
        throwsA(
          isA<RemoteProtocolException>().having(
            (e) => e.recoverable,
            'recoverable',
            isTrue,
          ),
        ),
      );
    });
  });

  group('debug frame pair (DT1)', () {
    test('DEBUG_REQUEST round-trips seq, kind, limit', () {
      final wire = encodeFrame(const DebugRequestFrame(7, 'frames', limit: 20));
      final out = (FrameDecoder()..feed(wire)).drain().toList();
      final f = out.single as DebugRequestFrame;
      expect(f.seq, 7);
      expect(f.kind, 'frames');
      expect(f.limit, 20);
    });

    test('DEBUG_RESPONSE round-trips seq, kind, and the raw JSON payload', () {
      final json = Uint8List.fromList(
        '[{"frame":1,"buildUs":42}]'.codeUnits,
      );
      final wire = encodeFrame(DebugResponseFrame(9, 'frames', json));
      final out = (FrameDecoder()..feed(wire)).drain().toList();
      final f = out.single as DebugResponseFrame;
      expect(f.seq, 9);
      expect(f.kind, 'frames');
      expect(f.json, json);
    });

    test('DEBUG_RESPONSE handles a high seq (>16-bit) and empty payload', () {
      final wire = encodeFrame(
        DebugResponseFrame(0x00ABCDEF, 'errors', Uint8List(0)),
      );
      final f = (FrameDecoder()..feed(wire)).drain().single
          as DebugResponseFrame;
      expect(f.seq, 0x00ABCDEF);
      expect(f.json, isEmpty);
    });
  });
}

Uint8List _rawFrame(FrameType type, List<int> payload) {
  final length = Uint8List(4);
  length.buffer.asByteData().setUint32(0, payload.length);
  final builder = BytesBuilder()
    ..addByte(type.code)
    ..add(length)
    ..add(payload);
  return builder.toBytes();
}
