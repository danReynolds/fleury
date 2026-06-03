// Wire framing for the remote-rendering transports (`fleury shell`,
// `fleury serve`). One protocol covers every transport — a Unix socket,
// a WebSocket, anything that ships ordered byte streams in both
// directions.
//
// Wire format (all multi-byte values big-endian):
//
//     ┌──────────┬───────────┬────────────────────┐
//     │ 1 byte   │ 4 bytes   │ N bytes            │
//     │ type     │ length N  │ payload            │
//     └──────────┴───────────┴────────────────────┘
//
// Five bytes of overhead per frame. We accept that to cleanly carry
// resize events out-of-band from the input byte stream — without
// framing, a SIGWINCH on the remote display would have to be smuggled
// inside a fake ANSI sequence, which is brittle and layers terminal
// concerns into the transport.
//
// Message types — direction is informational; nothing in the encoder
// rejects an off-direction frame, so test harnesses can inject either
// side:
//
//   Peer (shell / serve) → App
//     0x01 INIT     payload = `cols=<n>,rows=<n>,color=<mode>,`
//                            `image=<protocol>,tmux=<0|1>`
//                   sent exactly once, before any INPUT frame
//     0x02 INPUT    payload = raw bytes destined for stdin
//                   (escape sequences, key chords, paste contents)
//     0x03 RESIZE   payload = `cols=<n>,rows=<n>`
//
//   App → Peer
//     0x10 OUTPUT   payload = raw ANSI bytes to render
//
//   Either direction
//     0x11 BYE      payload = empty, signals a clean shutdown
//
// The payload size is a 32-bit unsigned length so a single frame can
// hold a fat-screen full repaint (a 200×60 buffer with worst-case SGR
// is well under the 4 GiB ceiling).

import 'dart:convert';
import 'dart:typed_data';

import '../foundation/geometry.dart';
import '../terminal/capabilities.dart';

/// Default remote frame payload cap.
///
/// This is intentionally much larger than normal terminal diff frames, while
/// still preventing a malformed peer from advertising a multi-gigabyte frame
/// and keeping the decoder pinned forever waiting for it.
const int defaultMaxRemoteFramePayloadLength = 64 * 1024 * 1024;

/// A malformed frame or payload was received from a remote peer.
final class RemoteProtocolException implements Exception {
  const RemoteProtocolException(this.message);

  final String message;

  @override
  String toString() => 'RemoteProtocolException: $message';
}

/// Frame type discriminator.
enum FrameType {
  init(0x01),
  input(0x02),
  resize(0x03),
  output(0x10),
  bye(0x11);

  const FrameType(this.code);
  final int code;

  static FrameType? fromCode(int code) {
    for (final t in FrameType.values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

/// One decoded frame off the wire. Sealed so callers exhaustively
/// switch in dispatch.
sealed class RemoteFrame {
  const RemoteFrame();
}

/// Initial handshake sent by the peer before any [InputFrame]. Carries
/// the remote display's size and the capabilities the app should plan
/// against (color mode, image protocol, multiplexer wrapping).
final class InitFrame extends RemoteFrame {
  const InitFrame({
    required this.size,
    required this.colorMode,
    required this.imageProtocol,
    required this.tmuxPassthrough,
  });

  final CellSize size;
  final ColorMode colorMode;
  final ImageProtocol imageProtocol;
  final bool tmuxPassthrough;
}

/// Raw input bytes from the remote display — keystrokes, escape
/// sequences, paste contents. Routed through the same [InputParser]
/// pipeline as a local POSIX driver.
final class InputFrame extends RemoteFrame {
  const InputFrame(this.bytes);
  final Uint8List bytes;
}

/// The remote display resized. Surfaced as a `ResizeEvent` on the
/// driver's event stream.
final class ResizeFrame extends RemoteFrame {
  const ResizeFrame(this.size);
  final CellSize size;
}

/// Outbound ANSI bytes — the app's diff render. Only ever flows
/// app → peer.
final class OutputFrame extends RemoteFrame {
  OutputFrame(this.bytes);
  final Uint8List bytes;
}

/// Either side signals a clean shutdown. Empty payload.
final class ByeFrame extends RemoteFrame {
  const ByeFrame();
}

/// Encodes a frame into wire bytes ready for the transport.
Uint8List encodeFrame(RemoteFrame frame) {
  final (type, payload) = switch (frame) {
    InitFrame f => (FrameType.init, utf8.encode(_encodeInit(f))),
    InputFrame f => (FrameType.input, f.bytes),
    ResizeFrame f => (
      FrameType.resize,
      utf8.encode('cols=${f.size.cols},rows=${f.size.rows}'),
    ),
    OutputFrame f => (FrameType.output, f.bytes),
    ByeFrame() => (FrameType.bye, const <int>[]),
  };
  final out = BytesBuilder(copy: false);
  out.addByte(type.code);
  final header = ByteData(4)..setUint32(0, payload.length);
  out.add(header.buffer.asUint8List());
  out.add(payload);
  return out.toBytes();
}

String _encodeInit(InitFrame f) =>
    'cols=${f.size.cols},'
    'rows=${f.size.rows},'
    'color=${f.colorMode.name},'
    'image=${f.imageProtocol.name},'
    'tmux=${f.tmuxPassthrough ? 1 : 0}';

/// Streaming frame decoder. Feed bytes as they arrive from the
/// transport; pull out complete frames with [drain]. The decoder
/// holds partial-frame state across calls so a fragmented socket
/// read or websocket message boundary doesn't lose data.
final class FrameDecoder {
  FrameDecoder({this.maxPayloadLength = defaultMaxRemoteFramePayloadLength})
    : assert(maxPayloadLength > 0, 'maxPayloadLength must be positive');

  final int maxPayloadLength;
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  /// Add raw bytes from the transport.
  void feed(List<int> bytes) {
    _buffer.add(bytes);
  }

  /// Pull out every complete frame currently in the buffer. Partial
  /// frames stay buffered until the next [feed].
  Iterable<RemoteFrame> drain() sync* {
    while (true) {
      final bytes = _buffer.toBytes();
      if (bytes.length < 5) {
        // Need at least the type byte + 4-byte length header. Restore
        // what we read so [feed] can append on top.
        _buffer.clear();
        _buffer.add(bytes);
        return;
      }
      final length = ByteData.sublistView(bytes, 1, 5).getUint32(0);
      if (length > maxPayloadLength) {
        _buffer.clear();
        throw RemoteProtocolException(
          'Frame payload length $length exceeds limit $maxPayloadLength.',
        );
      }
      final total = 5 + length;
      if (bytes.length < total) {
        _buffer.clear();
        _buffer.add(bytes);
        return;
      }
      final type = FrameType.fromCode(bytes[0]);
      final payload = bytes.sublist(5, total);
      // Anything past the frame is the next frame's bytes; re-buffer.
      _buffer.clear();
      if (bytes.length > total) {
        _buffer.add(bytes.sublist(total));
      }
      if (type == null) {
        // Unknown discriminator — skip silently rather than crash the
        // session. A peer running a newer protocol can extend the
        // type space without breaking older apps.
        continue;
      }
      yield _decode(type, payload);
    }
  }

  RemoteFrame _decode(FrameType type, Uint8List payload) {
    switch (type) {
      case FrameType.init:
        return _decodeInit(_decodeUtf8Payload(payload, 'INIT'));
      case FrameType.input:
        return InputFrame(payload);
      case FrameType.resize:
        final params = _parseParams(_decodeUtf8Payload(payload, 'RESIZE'));
        return ResizeFrame(_decodeSize(params, 'RESIZE'));
      case FrameType.output:
        return OutputFrame(payload);
      case FrameType.bye:
        return const ByeFrame();
    }
  }
}

String _decodeUtf8Payload(Uint8List payload, String frameType) {
  try {
    return utf8.decode(payload);
  } on FormatException catch (error) {
    throw RemoteProtocolException(
      '$frameType frame payload is not valid UTF-8: ${error.message}.',
    );
  }
}

InitFrame _decodeInit(String body) {
  final params = _parseParams(body);
  return InitFrame(
    size: _decodeSize(params, 'INIT'),
    colorMode: ColorMode.values.firstWhere(
      (m) => m.name == params['color'],
      orElse: () => ColorMode.truecolor,
    ),
    imageProtocol: ImageProtocol.values.firstWhere(
      (p) => p.name == params['image'],
      orElse: () => ImageProtocol.halfBlock,
    ),
    tmuxPassthrough: params['tmux'] == '1',
  );
}

CellSize _decodeSize(Map<String, String> params, String frameType) {
  final cols = _decodePositiveInt(params, 'cols', frameType);
  final rows = _decodePositiveInt(params, 'rows', frameType);
  return CellSize(cols, rows);
}

int _decodePositiveInt(
  Map<String, String> params,
  String key,
  String frameType,
) {
  final raw = params[key];
  if (raw == null || raw.isEmpty) {
    throw RemoteProtocolException('$frameType frame is missing `$key`.');
  }
  final value = int.tryParse(raw);
  if (value == null || value <= 0) {
    throw RemoteProtocolException(
      '$frameType frame has invalid `$key`: `$raw`.',
    );
  }
  return value;
}

Map<String, String> _parseParams(String body) {
  final out = <String, String>{};
  for (final pair in body.split(',')) {
    final eq = pair.indexOf('=');
    if (eq < 0) continue;
    out[pair.substring(0, eq)] = pair.substring(eq + 1);
  }
  return out;
}
