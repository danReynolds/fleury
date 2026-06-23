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
//                            `glyph=<tier>,image=<protocol>,tmux=<0|1>`
//                   sent exactly once, before any INPUT frame
//     0x02 INPUT    payload = raw bytes destined for stdin
//                   (escape sequences, key chords, paste contents)
//     0x03 RESIZE   payload = `cols=<n>,rows=<n>`
//
//   App → Peer
//     0x10 OUTPUT   payload = raw ANSI bytes to render (legacy ANSI host;
//                            retired-but-reserved — the structured serve
//                            host emits PLAN/SEMANTICS instead)
//     0x12 PLAN     payload = binary presentation plan (see remote_codec)
//     0x13 SEMANTICS payload = UTF-8 JSON semantic snapshot
//
//   Peer (serve / shell) → App, structured input
//     0x14 INPUT_EVENT payload = binary TuiEvent (see remote_codec)
//     0x15 SEMANTIC_ACTION payload = `<nodeId><action>` (see remote_codec) —
//                   the peer activating a node in its accessible DOM, so a
//                   served session is operable through the a11y tree, not just
//                   the visual grid
//
//   Either direction
//     0x11 BYE      payload = empty, signals a clean shutdown
//
// The INIT payload carries `v=<n>` (protocol version). v2 added the
// structured PLAN/SEMANTICS/INPUT_EVENT frames; a peer omitting `v`
// is treated as v1 (ANSI host). The payload size is a 32-bit unsigned
// length so a single frame can hold a fat-screen full repaint.

import 'dart:convert';
import 'dart:typed_data';

import '../foundation/geometry.dart';
import '../semantics/semantics.dart';
import '../terminal/capabilities.dart';
import '../terminal/events.dart';
import 'remote_codec.dart';

/// Current serve/shell protocol version. Bumped when frame semantics
/// change incompatibly; carried in the INIT handshake.
const int remoteProtocolVersion = 2;

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
  bye(0x11),
  plan(0x12),
  semantics(0x13),
  inputEvent(0x14),
  semanticAction(0x15),
  inlineImage(0x16);

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
    this.glyphTier = GlyphTier.unicode,
    required this.imageProtocol,
    required this.tmuxPassthrough,
    this.protocolVersion = remoteProtocolVersion,
  });

  final CellSize size;
  final ColorMode colorMode;
  final GlyphTier glyphTier;
  final ImageProtocol imageProtocol;
  final bool tmuxPassthrough;

  /// Negotiated protocol version. A peer omitting `v` in INIT is read as
  /// v1 (the legacy ANSI host).
  final int protocolVersion;
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
/// app → peer. Legacy host; the structured serve host emits [PlanFrame].
final class OutputFrame extends RemoteFrame {
  OutputFrame(this.bytes);
  final Uint8List bytes;
}

/// A presentation plan — the structured serve host's per-frame output,
/// driving a visual surface on the peer instead of ANSI. App → peer.
final class PlanFrame extends RemoteFrame {
  const PlanFrame(this.plan);
  final RemotePlan plan;
}

/// A semantic snapshot (UTF-8 JSON, the [SemanticInspectionSnapshot] shape)
/// for the just-rendered frame. App → peer; lets a served session stay
/// agent-drivable and accessible.
final class SemanticsFrame extends RemoteFrame {
  const SemanticsFrame(this.json);

  /// Raw UTF-8 JSON bytes of the semantic snapshot.
  final Uint8List json;
}

/// A structured input event from the peer — keystroke, mouse, paste,
/// resize, composition — dispatched server-side as a [TuiEvent]. Replaces
/// the raw [InputFrame] byte stream on the structured path. Peer → app.
final class InputEventFrame extends RemoteFrame {
  const InputEventFrame(this.event);
  final TuiEvent event;
}

/// The peer activated a node in its accessible DOM (a screen reader or agent
/// driving the semantics, not the visual grid). The host invokes [action] on
/// the live node [id]. Peer → app; the structured counterpart to the
/// app → peer [SemanticsFrame].
final class SemanticActionFrame extends RemoteFrame {
  const SemanticActionFrame(this.id, this.action);
  final SemanticNodeId id;
  final SemanticAction action;
}

/// The bytes of one inline image (browser surface), keyed by content-hash
/// [id]. App → peer, sent once before the first [PlanFrame] that places it; the
/// client caches it by id and renders an `<img>` overlay wherever a plan's
/// `placements` reference it. Decoupling bytes from placement keeps the image
/// off the cell-grid wire and ships it a single time.
final class InlineImageFrame extends RemoteFrame {
  const InlineImageFrame(this.id, this.bytes);
  final String id;
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
    PlanFrame f => (FrameType.plan, encodeRemotePlan(f.plan)),
    SemanticsFrame f => (FrameType.semantics, f.json),
    InputEventFrame f => (FrameType.inputEvent, encodeInputEvent(f.event)),
    SemanticActionFrame f => (
      FrameType.semanticAction,
      encodeSemanticAction(f.id, f.action),
    ),
    InlineImageFrame f => (FrameType.inlineImage, _encodeInlineImage(f)),
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
    'glyph=${f.glyphTier.name},'
    'image=${f.imageProtocol.name},'
    'tmux=${f.tmuxPassthrough ? 1 : 0},'
    'v=${f.protocolVersion}';

/// Wire layout: [u16 id length][id utf-8][image bytes...].
Uint8List _encodeInlineImage(InlineImageFrame f) {
  final idBytes = utf8.encode(f.id);
  final out = BytesBuilder(copy: false);
  out.add((ByteData(2)..setUint16(0, idBytes.length)).buffer.asUint8List());
  out.add(idBytes);
  out.add(f.bytes);
  return out.toBytes();
}

InlineImageFrame _decodeInlineImage(Uint8List payload) {
  if (payload.length < 2) {
    throw RemoteProtocolException('INLINE_IMAGE frame: truncated header.');
  }
  final idLen = ByteData.sublistView(payload, 0, 2).getUint16(0);
  if (2 + idLen > payload.length) {
    throw RemoteProtocolException('INLINE_IMAGE frame: id overruns payload.');
  }
  // Tolerate malformed UTF-8 in the id (matching the rest of the codec): a
  // bit-flipped id should degrade to a harmless mismatched key, not throw a
  // raw FormatException that drops every other frame in the batch.
  final id = utf8.decode(payload.sublist(2, 2 + idLen), allowMalformed: true);
  final bytes = Uint8List.fromList(payload.sublist(2 + idLen));
  return InlineImageFrame(id, bytes);
}

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
      case FrameType.plan:
        try {
          return PlanFrame(decodeRemotePlan(payload));
        } on RemoteCodecException catch (e) {
          throw RemoteProtocolException('PLAN frame: ${e.message}.');
        }
      case FrameType.semantics:
        // Validated when consumed (JSON parse on the peer); carry verbatim.
        return SemanticsFrame(payload);
      case FrameType.inputEvent:
        try {
          return InputEventFrame(decodeInputEvent(payload));
        } on RemoteCodecException catch (e) {
          throw RemoteProtocolException('INPUT_EVENT frame: ${e.message}.');
        }
      case FrameType.semanticAction:
        try {
          final (:id, :action) = decodeSemanticAction(payload);
          return SemanticActionFrame(id, action);
        } on RemoteCodecException catch (e) {
          throw RemoteProtocolException('SEMANTIC_ACTION frame: ${e.message}.');
        }
      case FrameType.inlineImage:
        return _decodeInlineImage(payload);
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
    glyphTier: GlyphTier.values.firstWhere(
      (t) => t.name == params['glyph'],
      orElse: () => GlyphTier.unicode,
    ),
    imageProtocol: ImageProtocol.values.firstWhere(
      (p) => p.name == params['image'],
      orElse: () => ImageProtocol.halfBlock,
    ),
    tmuxPassthrough: params['tmux'] == '1',
    protocolVersion: int.tryParse(params['v'] ?? '') ?? 1,
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
