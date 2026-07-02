// RemoteClipboard: the served app's clipboard. Copy in a served session
// must land on the machine the user is sitting at — the peer's — not the
// server's. Writes go out as CLIPBOARD_WRITE frames; the peer answers
// with CLIPBOARD_RESULT, and the report says `hostSurface` when the
// user's clipboard actually took the text. The in-process register is
// always populated first, so paste-within-app works even against a peer
// that denies clipboard access.

import 'dart:async';
import 'dart:convert';

import '../runtime/clipboard.dart';
import '../runtime/remote_surface_sink.dart';
import '../terminal/capability_requirements.dart';
import 'remote_protocol.dart';

/// Clipboard for structured remote sessions: writes travel to the peer.
final class RemoteClipboard extends Clipboard {
  RemoteClipboard(
    this._sink, {
    Duration resultTimeout = const Duration(seconds: 2),
  }) : _resultTimeout = resultTimeout {
    _sink.onClipboardResult = _onResult;
  }

  final RemoteSurfaceSink _sink;
  final Duration _resultTimeout;
  String? _register;
  var _nextSeq = 0;
  final Map<int, Completer<RemoteClipboardStatus?>> _pending = {};

  @override
  String? readInProcess() => _register;

  void _onResult(int seq, RemoteClipboardStatus status) {
    _pending.remove(seq)?.complete(status);
  }

  /// Detaches from the sink and resolves in-flight writes as unanswered.
  void dispose() {
    _sink.onClipboardResult = null;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.complete(null);
    }
    _pending.clear();
  }

  @override
  Future<ClipboardWriteReport> writeWithReport(
    String text, {
    ClipboardWritePolicy policy = ClipboardWritePolicy.standard,
  }) async {
    _register = text;
    final payloadBytes = utf8.encode(text).length;
    final seq = _nextSeq++;
    final completer = Completer<RemoteClipboardStatus?>();
    _pending[seq] = completer;
    _sink.sendClipboardWrite(seq, text);
    final status = await completer.future
        .timeout(_resultTimeout, onTimeout: () => null)
        .whenComplete(() => _pending.remove(seq));

    final delivered = status == RemoteClipboardStatus.written;
    return ClipboardWriteReport(
      result: delivered
          ? ClipboardWriteResult.hostSurface
          : ClipboardWriteResult.inProcessOnly,
      resolution: CapabilityResolution(
        feature: TerminalFeature.clipboardWrite,
        level: CapabilityLevel.preferred,
        state: delivered
            ? CapabilityResolutionState.available
            : CapabilityResolutionState.degraded,
        fallbackLabel: delivered ? null : 'in-process register',
      ),
      policy: policy,
      payloadBytes: payloadBytes,
      osc52EncodedLength: 0,
      overSsh: false,
      inProcessUpdated: true,
      platformToolAttempted: false,
      osc52Attempted: false,
      osc52Emitted: false,
    );
  }
}
