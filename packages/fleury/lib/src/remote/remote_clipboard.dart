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

    // A remote host-surface write is the served equivalent of a platform
    // clipboard write. Respect an in-process-only policy before allocating a
    // sequence or pending result, so policy-protected text never reaches the
    // peer.
    if (!policy.allowPlatformTool) {
      return _report(
        policy: policy,
        payloadBytes: payloadBytes,
        policyBlocked: true,
        warning: 'Remote clipboard write is disabled by policy.',
      );
    }

    // CLIPBOARD_WRITE carries [seq:u32] before its UTF-8 text. Oversized
    // writes stay useful inside the app, but must not create a request that
    // encodeFrame will reject or leave a completer waiting for a result that
    // can never arrive.
    final textLimit =
        remoteFramePayloadLimit(FrameType.clipboardWrite) -
        _clipboardSequenceBytes;
    if (payloadBytes > textLimit) {
      return _report(
        policy: policy,
        payloadBytes: payloadBytes,
        warning:
            'Remote clipboard payload exceeds the $textLimit-byte wire limit.',
      );
    }

    final seq = _nextSeq++;
    final completer = Completer<RemoteClipboardStatus?>();
    _pending[seq] = completer;
    try {
      _sink.sendClipboardWrite(seq, text);
    } on Object catch (error) {
      _pending.remove(seq);
      return _report(
        policy: policy,
        payloadBytes: payloadBytes,
        warning: 'Remote clipboard write could not be sent: $error',
      );
    }
    final status = await completer.future
        .timeout(_resultTimeout, onTimeout: () => null)
        .whenComplete(() => _pending.remove(seq));

    final delivered = status == RemoteClipboardStatus.written;
    return _report(
      delivered: delivered,
      policy: policy,
      payloadBytes: payloadBytes,
      warning: delivered
          ? null
          : 'Peer clipboard write was denied or unanswered.',
    );
  }

  ClipboardWriteReport _report({
    required ClipboardWritePolicy policy,
    required int payloadBytes,
    bool delivered = false,
    bool policyBlocked = false,
    String? warning,
  }) {
    final truth = CapabilityTruth(
      feature: TerminalFeature.clipboardWrite,
      support: delivered
          ? CapabilitySupport.supported
          : policyBlocked
          ? CapabilitySupport.unknown
          : CapabilitySupport.supported,
      enablement: policyBlocked
          ? CapabilityEnablement.disabled
          : CapabilityEnablement.notApplicable,
      delivery: delivered
          ? CapabilityDelivery.delivered
          : policyBlocked
          ? CapabilityDelivery.notApplicable
          : CapabilityDelivery.failed,
      policyBlocked: policyBlocked,
      evidence: <CapabilityEvidence>[
        CapabilityEvidence(
          source: policyBlocked
              ? CapabilityEvidenceSource.policy
              : CapabilityEvidenceSource.operationResult,
          detail:
              warning ?? 'The peer acknowledged writing the host clipboard.',
        ),
      ],
    );
    return ClipboardWriteReport(
      result: delivered
          ? ClipboardWriteResult.hostSurface
          : ClipboardWriteResult.inProcessOnly,
      resolution: resolveCapabilityRequirement(
        const CapabilityRequirement(
          feature: TerminalFeature.clipboardWrite,
          level: CapabilityLevel.preferred,
          fallback: CapabilityFallback(label: 'in-process register'),
        ),
        truth,
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

const int _clipboardSequenceBytes = 4;
