// Wire-format round-trip tests for the remote-rendering protocol.

import 'dart:typed_data';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/remote/remote_protocol.dart';
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

    test('oversized frame payloads fail with a protocol error', () {
      final wire = encodeFrame(InputFrame(Uint8List.fromList([1, 2, 3, 4, 5])));
      final decoder = FrameDecoder(maxPayloadLength: 4)..feed(wire);

      expect(
        () => decoder.drain().toList(),
        throwsA(isA<RemoteProtocolException>()),
      );
    });

    test('malformed RESIZE payloads fail with a protocol error', () {
      final wire = _rawFrame(FrameType.resize, 'rows=24'.codeUnits);
      final decoder = FrameDecoder()..feed(wire);

      expect(
        () => decoder.drain().toList(),
        throwsA(isA<RemoteProtocolException>()),
      );
    });

    test('invalid UTF-8 control payloads fail with a protocol error', () {
      final wire = _rawFrame(FrameType.init, const [0xFF]);
      final decoder = FrameDecoder()..feed(wire);

      expect(
        () => decoder.drain().toList(),
        throwsA(isA<RemoteProtocolException>()),
      );
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
