// An in-memory stand-in for a spawned app's side of the wire, shared by the
// tests that drive the real McpServer and FleuryAppBridge without a
// subprocess.

import 'dart:async';

import 'package:fleury/fleury_host.dart';
import 'package:fleury/fleury_wire.dart';

/// The INIT frame an app sends when it connects.
InitFrame appInit(int protocolVersion) => InitFrame(
  size: const CellSize(80, 24),
  colorMode: ColorMode.truecolor,
  glyphTier: GlyphTier.unicode,
  imageProtocol: ImageProtocol.halfBlock,
  tmuxPassthrough: false,
  protocolVersion: protocolVersion,
);

/// A counter app's semantic tree: a Count value and Increment and Reset
/// buttons.
Map<String, Object?> counterRoot(int count) => <String, Object?>{
  'id': 'root',
  'role': 'app',
  'label': 'Counter',
  'children': <Object?>[
    <String, Object?>{
      'id': 'count',
      'role': 'text',
      'label': 'Count',
      'value': count,
    },
    <String, Object?>{
      'id': 'increment',
      'role': 'button',
      'label': 'Increment',
      'actions': <String>['activate'],
    },
    <String, Object?>{
      'id': 'reset',
      'role': 'button',
      'label': 'Reset',
      'actions': <String>['activate'],
    },
  ],
};

/// The app's end of the wire: tests push frames in with [addIncoming] and read
/// what the bridge sent from [sent].
final class FakeAppTransport
    with SynchronousSendTransport
    implements RemoteFrameTransport {
  final StreamController<RemoteFrame> _incoming =
      StreamController<RemoteFrame>.broadcast();
  final List<RemoteFrame> sent = <RemoteFrame>[];
  bool autoCompleteSemanticActions = true;

  @override
  Stream<RemoteFrame> get incoming => _incoming.stream;

  @override
  void send(RemoteFrame frame) {
    // Mirror UnixSocketFrameTransport.send: encode synchronously, so an over-cap
    // outgoing frame throws RemoteProtocolException exactly as the real wire does
    // (and is therefore never recorded as "sent").
    encodeFrame(frame);
    sent.add(frame);
    if (autoCompleteSemanticActions && frame is SemanticActionFrame) {
      scheduleMicrotask(() {
        if (_incoming.isClosed) return;
        _incoming.add(
          SemanticActionResultFrame(
            frame.id,
            frame.action,
            SemanticActionInvocationStatus.completed,
          ),
        );
      });
    }
  }

  @override
  Future<void> close() async {
    if (!_incoming.isClosed) await _incoming.close();
  }

  void addIncoming(RemoteFrame frame) => _incoming.add(frame);

  /// Simulates the app disconnecting — the bridge sees `onDone` and exits.
  Future<void> dropPeer() async {
    if (!_incoming.isClosed) await _incoming.close();
    await Future<void>.delayed(Duration.zero);
  }
}
