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
//     0x16 INLINE_IMAGE payload = [u16 idLen][utf8 id][image bytes] — one
//                   inline image (browser surface), keyed by content-hash id;
//                   sent once before the first PLAN that places it, then
//                   referenced by id so the bytes ride the wire only once
//     0x17 CLIPBOARD_WRITE payload = [u32 seq][utf8 text] — place text on
//                   the PEER's clipboard (the user's machine); answered by
//                   CLIPBOARD_RESULT
//     0x19 CARET    payload = [u8 present][i16 col][i16 row][u16 cols][u16 rows]
//                   — the focused editable's caret rect for IME positioning
//     0x1A SEMANTIC_ACTION_RESULT payload = `<nodeId><action><status>` (see
//                   remote_codec) — the invocation status for a peer's
//                   SEMANTIC_ACTION, so agents/AT get real outcomes instead
//                   of guessing from tree diffs. The app also echoes INIT
//                   (v3+) after receiving the peer's, carrying its protocol
//                   version so the client can detect skew.
//     0x1C DEBUG_RESPONSE payload = [u32 seq][u8 kindLen][kind][json] — the
//                   app's answer to a DEBUG_REQUEST: the recent records for the
//                   requested kind (shape is per-kind)
//
//   Peer (serve / shell) → App, structured input
//     0x14 INPUT_EVENT payload = binary TuiEvent (see remote_codec)
//     0x18 CLIPBOARD_RESULT payload = [u32 seq][u8 status] — how the peer's
//                   clipboard write went (written / denied / unavailable)
//     0x15 SEMANTIC_ACTION payload = `<nodeId><action>` (see remote_codec) —
//                   the peer activating a node in its accessible DOM, so a
//                   served session is operable through the a11y tree, not just
//                   the visual grid
//     0x1B DEBUG_REQUEST payload = JSON `{seq,kind,limit}` — a pull-style debug
//                   query ("send me your recent <kind> records"); answered by
//                   DEBUG_RESPONSE, or silently dropped by apps predating this
//                   frame type (unknown discriminators are skipped)
//
//   Either direction
//     0x11 BYE      payload = empty, signals a clean shutdown
//
// The INIT payload carries `v=<n>` (protocol version). v2 added the
// structured PLAN/SEMANTICS/INPUT_EVENT frames; a peer omitting `v`
// is treated as v1 (ANSI host). The payload size is a 32-bit unsigned
// length so a single frame can hold a fat-screen full repaint.
//
// Versioning rule (the one rule, stated once): NEW FRAME TYPES and
// OPTIONAL TRAILING FIELDS are additive — decoders skip unknown type
// discriminators and tolerate absent trailing fields, so peers one
// version apart interoperate. CELL/ENUM ENCODINGS inside existing
// frames are version-gated: server and client ship from the same
// fleury build (the client bundle is embedded in the binary), so
// changing them requires a version bump and matching peers.
//
// Under that rule: SEMANTIC_ACTION's optional trailing value byte
// (set_value) was additive. v3 added SEMANTIC_ACTION_RESULT (0x1A)
// and the app-side INIT echo — both additive: a v2 peer skips the
// result frame and ignores the echo; a v3 client merely can't show
// action results or detect version skew against a v2 app.
//
// v4 is a version-GATED encoding change (not additive): the PLAN frame's
// cell-style entry gains an OPTIONAL OSC 8 link. The style's spare
// set-mask bit 6 flags "has link" and, when set, a varint-length-prefixed
// UTF-8 URI rides immediately AFTER the two mask bytes and BEFORE the
// colors. A link-free style leaves bit 6 clear and writes no URI, so a
// link-free frame is byte-identical to v3. The app serializes links only
// to a peer that negotiated v>=4 (RemoteTerminalDriver.wantsHyperlinks),
// so a stale v3 client — whose decoder would misalign on the unexpected
// URI — never receives the extra bytes (RFC 0017 §5).
//
// The INIT `hyperlinks=<0|1>` param is the OTHER half and is purely ADDITIVE
// (like `images=`): a peer that can RENDER links sets it so the server-side
// producer gate emits a link in the first place. Absent ⇒ false, so v3/older
// peers (and the version-skew INIT echo) are unaffected and stay byte-flat.
// The two are independent: `hyperlinks=` decides whether a link is PRODUCED;
// v>=4 decides whether the wire SERIALIZES it. Both must hold for a browser to
// receive a clickable cell-grid anchor.
//
// The normative statement of this protocol — the version, the frame table
// above, the additive-vs-version-gated rule, and the launch-relevant caveat
// that the wire is NOT a public/stable integration surface (same-build peers
// only; no third-party compat guarantee) — lives in
// docs/implementation/wire-protocol.md. Keep the two in sync: this comment and
// the FrameType enum below are the source of truth for frame codes; that doc is
// the source of truth for the policy.

import 'dart:convert';
import 'dart:typed_data';

import '../foundation/geometry.dart';
import '../rendering/surface_capabilities.dart';
import '../semantics/semantics.dart';
import '../terminal/capabilities.dart';
import '../input/events.dart';
import 'remote_codec.dart';

/// Current serve/shell protocol version. Bumped when frame semantics
/// change incompatibly; carried in the INIT handshake (and, since v3,
/// echoed app → peer so the client can detect version skew).
///
/// v4 version-gates the optional OSC 8 link in the PLAN cell-style entry
/// (RFC 0017 §5): a link-free frame stays byte-identical to v3, and links
/// are emitted only to a peer that negotiated v>=4.
const int remoteProtocolVersion = 4;

/// Default remote frame payload cap.
///
/// Sixteen MiB leaves ample headroom for a large full repaint or inline image,
/// while avoiding a 64 MiB allocation per frame/session. Known frame types have
/// tighter limits below; this global cap also bounds additive unknown types.
const int defaultMaxRemoteFramePayloadLength = 16 * 1024 * 1024;

/// Small handshake/control frames should never carry document-sized payloads.
const int maxRemoteControlFramePayloadLength = 64 * 1024;

/// Text, paste, clipboard, and semantic-action input accepted in one event.
const int maxRemoteInputFramePayloadLength = 1024 * 1024;

/// Structured plans, semantic snapshots, debug records, and legacy output.
const int maxRemoteDocumentFramePayloadLength = 8 * 1024 * 1024;

/// One encoded inline image. Images remain the only frame allowed up to the
/// global cap.
const int maxRemoteImageFramePayloadLength = defaultMaxRemoteFramePayloadLength;

/// A malformed frame or payload was received from a remote peer.
final class RemoteProtocolException implements Exception {
  const RemoteProtocolException(this.message, {this.recoverable = true});

  final String message;

  /// Whether the decoder can keep parsing the byte stream after this error.
  ///
  /// True (the default) for a single malformed frame whose 4-byte length
  /// header was valid: [FrameDecoder.drain] consumed exactly that frame and
  /// the stream stays framed, so a peer can repair from its mirror and carry
  /// on. False only when stream framing itself was lost — an oversized length
  /// prefix forces the buffer to be cleared with no known next-frame boundary,
  /// so every subsequent feed mis-parses and the session can never
  /// re-synchronize. A peer that sees an unrecoverable error must reconnect
  /// rather than resync (see fleury_web's WireFrameSource).
  final bool recoverable;

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
  inlineImage(0x16),
  clipboardWrite(0x17),
  clipboardResult(0x18),
  caret(0x19),
  semanticActionResult(0x1A),
  debugRequest(0x1B),
  debugResponse(0x1C);

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
    this.images,
    this.hyperlinks = false,
    this.protocolVersion = remoteProtocolVersion,
  });

  final CellSize size;
  final ColorMode colorMode;
  final GlyphTier glyphTier;

  /// The terminal-projection fields: a v1 ANSI peer (`fleury shell`, a
  /// real terminal) genuinely has an escape protocol and a multiplexer.
  final ImageProtocol imageProtocol;
  final bool tmuxPassthrough;

  /// The peer's neutral image capability (v3 `images=` param). Null from
  /// older peers — the app projects [imageProtocol] instead.
  final InlineImageSupport? images;

  /// Whether the peer's surface can render real hyperlinks (OSC 8 on a
  /// terminal, `<a>` anchors in the browser). Optional additive `hyperlinks=`
  /// INIT param: absent from older peers, decoded as false. Threaded into the
  /// app-side [SurfaceCapabilities.hyperlinks] so the server-side producer gate
  /// (e.g. `MarkdownText`) only emits a `linkUri` when the peer can actually
  /// show it. Distinct from [protocolVersion]/[RemoteTerminalDriver.wantsHyperlinks],
  /// which gates whether the wire *serializes* a link at all (v>=4); this gates
  /// whether one is ever *produced*.
  final bool hyperlinks;

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
  const SemanticActionFrame(this.id, this.action, {this.value});
  final SemanticNodeId id;
  final SemanticAction action;

  /// Optional payload, carried only by [SemanticAction.setValue] (a
  /// JSON-friendly scalar). Null for every parameterless action.
  final Object? value;
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

/// The app asks the peer to place [text] on the PEER's clipboard — the
/// machine the user is actually sitting at. Sequenced so the app can match
/// the peer's [ClipboardResultFrame]. App → peer. Without this, copy in a
/// served session lands on the server's clipboard (or nowhere).
final class ClipboardWriteFrame extends RemoteFrame {
  const ClipboardWriteFrame(this.seq, this.text);
  final int seq;
  final String text;
}

/// How the peer's clipboard write went.
enum RemoteClipboardStatus { written, denied, unavailable }

/// The peer's answer to a [ClipboardWriteFrame]. Peer → app.
final class ClipboardResultFrame extends RemoteFrame {
  const ClipboardResultFrame(this.seq, this.status);
  final int seq;
  final RemoteClipboardStatus status;
}

/// The focused editable's caret rectangle in cell space, or absent when
/// nothing editable is focused. The peer positions its hidden IME capture
/// element there so composition candidate windows appear at the caret.
/// App → peer, sent when the rect changes.
final class CaretFrame extends RemoteFrame {
  const CaretFrame(this.caret);
  final CellRect? caret;
}

/// The app's answer to a [SemanticActionFrame]: the node id and action echoed
/// back with the invocation status, so the peer (browser AT mirror, agent
/// bridge) can distinguish "handler ran", "disabled", "not found",
/// "unsupported", and "handler threw" instead of guessing from tree diffs.
/// App → peer.
final class SemanticActionResultFrame extends RemoteFrame {
  const SemanticActionResultFrame(this.id, this.action, this.status);
  final SemanticNodeId id;
  final SemanticAction action;
  final SemanticActionInvocationStatus status;
}

/// A pull-style debug query from the peer (agent bridge, future browser
/// DevTools): "send me your recent [kind] records". Peer → app. [seq]
/// correlates the [DebugResponseFrame]; [limit] bounds how many records the
/// app returns (newest last). Kinds are strings so the set can grow without
/// a protocol change; unknown kinds get an empty response, and apps older
/// than this frame type skip it entirely (unknown-type frames are dropped
/// by design) — peers must treat a missing response as "unsupported".
final class DebugRequestFrame extends RemoteFrame {
  const DebugRequestFrame(this.seq, this.kind, {this.limit = 50});
  final int seq;
  final String kind;
  final int limit;
}

/// The app's answer to a [DebugRequestFrame]: the [seq] and [kind] echoed
/// back with a JSON document of records (shape is per-kind; see
/// `DebugFrameLog.toJson` / runApp's error serialization). App → peer.
final class DebugResponseFrame extends RemoteFrame {
  const DebugResponseFrame(this.seq, this.kind, this.json);
  final int seq;
  final String kind;

  /// UTF-8 JSON document bytes (a list of records).
  final Uint8List json;
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
      encodeSemanticAction(f.id, f.action, value: f.value),
    ),
    SemanticActionResultFrame f => (
      FrameType.semanticActionResult,
      encodeSemanticActionResult(f.id, f.action, f.status),
    ),
    InlineImageFrame f => (FrameType.inlineImage, _encodeInlineImage(f)),
    ClipboardWriteFrame f => (
      FrameType.clipboardWrite,
      _encodeClipboardWrite(f),
    ),
    ClipboardResultFrame f => (
      FrameType.clipboardResult,
      _encodeClipboardResult(f),
    ),
    CaretFrame f => (FrameType.caret, _encodeCaret(f)),
    DebugRequestFrame f => (
      FrameType.debugRequest,
      utf8.encode(jsonEncode({'seq': f.seq, 'kind': f.kind, 'limit': f.limit})),
    ),
    DebugResponseFrame f => (
      FrameType.debugResponse,
      _encodeDebugResponse(f),
    ),
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
    '${f.images == null ? '' : 'images=${f.images!.name},'}'
    // Optional additive param (like `images=`): emitted only when true, so a
    // link-free INIT stays byte-identical to a peer that never learned the
    // field. Absent ⇒ decoded as false.
    '${f.hyperlinks ? 'hyperlinks=1,' : ''}'
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
  if (idLen == 0 || idLen > 256) {
    throw RemoteProtocolException(
      'INLINE_IMAGE frame: id length $idLen is outside 1..256.',
    );
  }
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

/// Wire layout: [u32 seq][utf-8 text...].
Uint8List _encodeClipboardWrite(ClipboardWriteFrame f) {
  final textBytes = utf8.encode(f.text);
  final out = BytesBuilder(copy: false);
  out.add((ByteData(4)..setUint32(0, f.seq)).buffer.asUint8List());
  out.add(textBytes);
  return out.toBytes();
}

ClipboardWriteFrame _decodeClipboardWrite(Uint8List payload) {
  if (payload.length < 4) {
    throw const RemoteProtocolException(
      'CLIPBOARD_WRITE frame: truncated header.',
    );
  }
  final seq = ByteData.sublistView(payload, 0, 4).getUint32(0);
  final text = utf8.decode(payload.sublist(4), allowMalformed: true);
  return ClipboardWriteFrame(seq, text);
}

/// Wire layout: [u32 seq][u8 status]. Status travels by index; the enum is
/// wire-frozen (append-only), matching the codec's version-locked posture.
Uint8List _encodeClipboardResult(ClipboardResultFrame f) {
  final out = ByteData(5)
    ..setUint32(0, f.seq)
    ..setUint8(4, f.status.index);
  return out.buffer.asUint8List();
}

ClipboardResultFrame _decodeClipboardResult(Uint8List payload) {
  if (payload.length != 5) {
    throw const RemoteProtocolException(
      'CLIPBOARD_RESULT frame: payload must be exactly 5 bytes.',
    );
  }
  final data = ByteData.sublistView(payload);
  final statusIndex = data.getUint8(4);
  if (statusIndex >= RemoteClipboardStatus.values.length) {
    throw RemoteProtocolException(
      'CLIPBOARD_RESULT frame: unknown status $statusIndex.',
    );
  }
  return ClipboardResultFrame(
    data.getUint32(0),
    RemoteClipboardStatus.values[statusIndex],
  );
}

/// Wire layout: [u8 present][i16 col][i16 row][u16 cols][u16 rows].
Uint8List _encodeCaret(CaretFrame f) {
  final caret = f.caret;
  final out = ByteData(9)..setUint8(0, caret == null ? 0 : 1);
  if (caret != null) {
    out
      ..setInt16(1, caret.left)
      ..setInt16(3, caret.top)
      ..setUint16(5, caret.size.cols)
      ..setUint16(7, caret.size.rows);
  }
  return out.buffer.asUint8List();
}

CaretFrame _decodeCaret(Uint8List payload) {
  if (payload.length != 9) {
    throw const RemoteProtocolException(
      'CARET frame: payload must be exactly 9 bytes.',
    );
  }
  if (payload[0] > 1) {
    throw RemoteProtocolException(
      'CARET frame: invalid presence flag ${payload[0]}.',
    );
  }
  if (payload[0] == 0) return const CaretFrame(null);
  final data = ByteData.sublistView(payload);
  return CaretFrame(
    CellRect.fromLTWH(
      data.getInt16(1),
      data.getInt16(3),
      data.getUint16(5),
      data.getUint16(7),
    ),
  );
}

/// Streaming frame decoder. Feed bytes as they arrive from the
/// transport; pull out complete frames with [drain]. The decoder
/// holds partial-frame state across calls so a fragmented socket
/// read or websocket message boundary doesn't lose data.
final class FrameDecoder {
  FrameDecoder({this.maxPayloadLength = defaultMaxRemoteFramePayloadLength})
    : assert(maxPayloadLength > 0, 'maxPayloadLength must be positive');

  final int maxPayloadLength;
  Uint8List _buffer = Uint8List(0);
  int _start = 0;
  int _end = 0;
  RemoteProtocolException? _pendingFatalError;

  int get _bufferedLength => _end - _start;

  /// Add raw bytes from the transport.
  void feed(List<int> bytes) {
    if (bytes.isEmpty) return;
    if (_pendingFatalError != null) return;
    // Avoid copying a caller-supplied giant chunk merely to discover from its
    // already-present header that the first frame is invalid. Socket reads are
    // normally small and WebSocket messages are capped at the bridge, but this
    // also keeps the decoder API itself bounded for a single hostile feed.
    if (_bufferedLength == 0 && bytes.length >= 5) {
      final type = FrameType.fromCode(bytes[0]);
      final length =
          bytes[1] * 0x1000000 +
          bytes[2] * 0x10000 +
          bytes[3] * 0x100 +
          bytes[4];
      final limit = _effectivePayloadLimit(type);
      if (length > limit) {
        _pendingFatalError = _oversizedFrame(type, length, limit);
        return;
      }
    }
    _ensureWritable(bytes.length);
    _buffer.setRange(_end, _end + bytes.length, bytes);
    _end += bytes.length;
  }

  /// Pull out every complete frame currently in the buffer. Partial
  /// frames stay buffered until the next [feed].
  Iterable<RemoteFrame> drain() sync* {
    final pendingFatalError = _pendingFatalError;
    if (pendingFatalError != null) {
      _pendingFatalError = null;
      _clearBuffer();
      throw pendingFatalError;
    }
    while (true) {
      if (_bufferedLength < 5) return;
      final frameStart = _start;
      final type = FrameType.fromCode(_buffer[frameStart]);
      final length = ByteData.sublistView(
        _buffer,
        frameStart + 1,
        frameStart + 5,
      ).getUint32(0);
      final effectiveLimit = _effectivePayloadLimit(type);
      if (length > effectiveLimit) {
        // Clearing the buffer discards the current framing position with no
        // known next-frame boundary, so the stream can no longer be
        // resynchronized: mark this unrecoverable so a peer tears down and
        // reconnects instead of resyncing forever against a mirror that will
        // never advance (the "frozen, no banner" hang). A single frame whose
        // length was VALID but whose payload is malformed throws a recoverable
        // exception from _decode below (framing intact), so the two cases are
        // distinguishable at the catch site.
        _clearBuffer();
        throw _oversizedFrame(type, length, effectiveLimit);
      }
      final total = 5 + length;
      if (_bufferedLength < total) return;
      final before = _bufferedLength;
      final payloadStart = frameStart + 5;
      final payloadEnd = frameStart + total;
      _start = payloadEnd;
      if (type == null) {
        // Unknown discriminator — skip silently rather than crash the
        // session. A peer running a newer protocol can extend the
        // type space without breaking older apps.
        _releaseBufferIfEmpty();
        continue;
      }
      // Copy exactly one completed payload. Partial feeds are retained in the
      // amortized byte buffer above instead of repeatedly materializing and
      // restoring the entire prefix (the old fragmented-frame O(n²) path).
      final payload = Uint8List.fromList(
        Uint8List.sublistView(_buffer, payloadStart, payloadEnd),
      );
      _releaseBufferIfEmpty();
      // Framing has advanced past this frame (the buffer now holds only the
      // trailing bytes), so a RECOVERABLE _decode throw below cannot recur on
      // these same bytes when the peer feeds again — the F19 non-loop
      // invariant a recoverable classification rests on.
      assert(
        _bufferedLength < before,
        'drain() must consume a frame from the buffer before decoding its '
        'payload, so a recoverable decode error cannot re-parse the same '
        'bytes forever (F19 non-loop invariant).',
      );
      yield _decode(type, payload);
    }
  }

  void _ensureWritable(int additional) {
    if (_buffer.length - _end >= additional) return;
    final unread = _bufferedLength;
    final needed = unread + additional;
    if (_start > 0 && _buffer.length >= needed) {
      // Reclaim a consumed prefix in place before considering growth. setRange
      // handles overlapping ranges and avoids replacing a large backing store
      // merely because its free space is on the wrong side of unread bytes.
      _buffer.setRange(0, unread, _buffer, _start);
      _start = 0;
      _end = unread;
      return;
    }
    var capacity = _buffer.isEmpty ? 256 : _buffer.length;
    while (capacity < needed) {
      final doubled = capacity * 2;
      capacity = doubled > needed ? doubled : needed;
    }
    final next = Uint8List(capacity);
    if (unread > 0) {
      next.setRange(0, unread, _buffer, _start);
    }
    _buffer = next;
    _start = 0;
    _end = unread;
  }

  void _clearBuffer() {
    _buffer = Uint8List(0);
    _start = 0;
    _end = 0;
  }

  void _releaseBufferIfEmpty() {
    if (_start != _end) return;
    // Keep a small allocation for ordinary frames, but do not pin a multi-MiB
    // backing store for the lifetime of a session after one large frame.
    if (_buffer.length > 1024 * 1024) {
      _buffer = Uint8List(0);
    }
    _start = 0;
    _end = 0;
  }

  int _payloadLimit(FrameType? type) => switch (type) {
    FrameType.init ||
    FrameType.resize ||
    FrameType.clipboardResult ||
    FrameType.caret ||
    FrameType.semanticActionResult ||
    FrameType.debugRequest ||
    FrameType.bye => maxRemoteControlFramePayloadLength,
    FrameType.input ||
    FrameType.inputEvent ||
    FrameType.semanticAction ||
    FrameType.clipboardWrite => maxRemoteInputFramePayloadLength,
    FrameType.output ||
    FrameType.plan ||
    FrameType.semantics ||
    FrameType.debugResponse => maxRemoteDocumentFramePayloadLength,
    FrameType.inlineImage => maxRemoteImageFramePayloadLength,
    null => defaultMaxRemoteFramePayloadLength,
  };

  int _effectivePayloadLimit(FrameType? type) {
    final typeLimit = _payloadLimit(type);
    return typeLimit < maxPayloadLength ? typeLimit : maxPayloadLength;
  }

  RemoteProtocolException _oversizedFrame(
    FrameType? type,
    int length,
    int limit,
  ) => RemoteProtocolException(
    '${type?.name ?? 'unknown'} frame payload length $length exceeds '
    'limit $limit; stream framing lost.',
    recoverable: false,
  );

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
          final (:id, :action, :value) = decodeSemanticAction(payload);
          return SemanticActionFrame(id, action, value: value);
        } on RemoteCodecException catch (e) {
          throw RemoteProtocolException('SEMANTIC_ACTION frame: ${e.message}.');
        }
      case FrameType.semanticActionResult:
        try {
          final (:id, :action, :status) = decodeSemanticActionResult(payload);
          return SemanticActionResultFrame(id, action, status);
        } on RemoteCodecException catch (e) {
          throw RemoteProtocolException(
            'SEMANTIC_ACTION_RESULT frame: ${e.message}.',
          );
        }
      case FrameType.debugRequest:
        try {
          final map = jsonDecode(utf8.decode(payload)) as Map<String, Object?>;
          return DebugRequestFrame(
            map['seq'] as int,
            map['kind'] as String,
            limit: (map['limit'] as int?) ?? 50,
          );
        } on Object catch (e) {
          throw RemoteProtocolException('DEBUG_REQUEST frame: $e.');
        }
      case FrameType.debugResponse:
        try {
          return _decodeDebugResponse(payload);
        } on Object catch (e) {
          throw RemoteProtocolException('DEBUG_RESPONSE frame: $e.');
        }
      case FrameType.inlineImage:
        return _decodeInlineImage(payload);
      case FrameType.clipboardWrite:
        return _decodeClipboardWrite(payload);
      case FrameType.clipboardResult:
        return _decodeClipboardResult(payload);
      case FrameType.caret:
        return _decodeCaret(payload);
      case FrameType.bye:
        if (payload.isNotEmpty) {
          throw const RemoteProtocolException(
            'BYE frame payload must be empty.',
          );
        }
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
    images: switch (params['images']) {
      'none' => InlineImageSupport.none,
      'placements' => InlineImageSupport.placements,
      _ => null,
    },
    hyperlinks: params['hyperlinks'] == '1',
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

// Debug response payload: 4-byte LE seq, 1-byte kind length, kind bytes,
// then the raw JSON document — avoids JSON-escaping the (potentially large)
// document into an envelope.
Uint8List _encodeDebugResponse(DebugResponseFrame f) {
  final kind = utf8.encode(f.kind);
  final out = BytesBuilder(copy: false)
    ..addByte(f.seq & 0xFF)
    ..addByte((f.seq >> 8) & 0xFF)
    ..addByte((f.seq >> 16) & 0xFF)
    ..addByte((f.seq >> 24) & 0xFF)
    ..addByte(kind.length)
    ..add(kind)
    ..add(f.json);
  return out.toBytes();
}

DebugResponseFrame _decodeDebugResponse(Uint8List payload) {
  if (payload.length < 5) {
    throw const RemoteProtocolException('DEBUG_RESPONSE: short payload.');
  }
  final seq = payload[0] |
      (payload[1] << 8) |
      (payload[2] << 16) |
      (payload[3] << 24);
  final kindLen = payload[4];
  if (payload.length < 5 + kindLen) {
    throw const RemoteProtocolException('DEBUG_RESPONSE: truncated kind.');
  }
  final kind = utf8.decode(payload.sublist(5, 5 + kindLen));
  return DebugResponseFrame(
    seq,
    kind,
    Uint8List.sublistView(payload, 5 + kindLen),
  );
}
