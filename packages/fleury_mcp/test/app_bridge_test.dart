// Protocol-half tests for [FleuryAppBridge] over an in-memory transport that
// encodes frames the same way the real Unix-socket transport does — so an
// over-cap in-band payload throws the same [RemoteProtocolException], and
// injected SEMANTIC_ACTION_RESULT frames exercise the real result-correlation
// path. No subprocess is spawned and no wall-clock waits are used.

import 'dart:async';

import 'package:fleury/fleury_host.dart';
import 'package:fleury_mcp/fleury_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('oversized in-band payload does not kill a healthy app', () {
    test('an over-cap press_key chord is rejected, not read as app death', () {
      final transport = _EncodingTransport();
      final bridge = FleuryAppBridge(transport)..start();
      addTearDown(bridge.close);

      var doneFired = false;
      unawaited(bridge.done.then((_) => doneFired = true));

      // A ~1 MiB literal char held as a chord: encodeInputEvent writes the char
      // uncapped, so the INPUT_EVENT frame overruns the 1 MiB input cap and
      // encodeFrame rejects it ("frame was not encoded") — the socket is intact.
      final huge = 'x' * (maxRemoteInputFramePayloadLength + 1024);
      expect(
        () => bridge.pressKey(char: huge, modifiers: {KeyModifier.ctrl}),
        throwsA(isA<RemoteProtocolException>()),
        reason: 'an over-cap frame is a recoverable encode rejection',
      );

      // The bridge must NOT have declared the healthy app dead.
      expect(bridge.isRunning, isTrue, reason: 'app must stay attached');
      expect(doneFired, isFalse, reason: 'no teardown — bridge.done must not fire');
      // The rejected chord was never handed to the wire.
      expect(transport.sent.whereType<InputEventFrame>(), isEmpty);
    });

    test('an over-cap set_value payload is rejected, not read as app death',
        () async {
      final transport = _EncodingTransport();
      final bridge = FleuryAppBridge(transport)..start();
      addTearDown(bridge.close);

      var doneFired = false;
      unawaited(bridge.done.then((_) => doneFired = true));

      // ~200k control chars: jsonEncode escapes each to "\u0001" (6 bytes) so the
      // encoded value is ~1.2 MB — over the 1 MiB semantic-action cap — even
      // though the char count is under the server's 200k input ceiling.
      final huge = '\u0001' * 200000;

      Object? thrown;
      try {
        // The encode + handling are synchronous inside setValue; the returned
        // future (fixed path never reaches it) is dropped on the failing path so
        // its 2 s timeout can't leak.
        bridge.setValue(const SemanticNodeId('field'), huge).ignore();
      } catch (error) {
        thrown = error;
      }

      expect(
        thrown,
        isA<RemoteProtocolException>(),
        reason: 'an over-cap set_value must throw, not be swallowed as app death',
      );
      expect(bridge.isRunning, isTrue, reason: 'app must stay attached');
      await _pump();
      expect(doneFired, isFalse, reason: 'no teardown — bridge.done must not fire');
      expect(transport.sent.whereType<SemanticActionFrame>(), isEmpty);
    });
  });

  group('SEMANTIC_ACTION_RESULT is correlated to its request', () {
    test('a late result from a superseded action is not attributed to the next',
        () async {
      final transport = _EncodingTransport();
      final bridge = FleuryAppBridge(transport)..start();
      addTearDown(bridge.close);

      const a = SemanticNodeId('nodeA');
      const b = SemanticNodeId('nodeB');

      // Invoke A (its app-side handler is slow), then — before A's result lands —
      // invoke B. In the server this is the post-2 s-timeout next mutation; here
      // the second arm supersedes A's wait the same way, leaving B armed.
      final aResult = bridge.invokeAction(a, SemanticAction.activate);
      final bResult = bridge.invokeAction(b, SemanticAction.activate);

      // A's late result arrives while B is the armed mutation. It must NOT bind
      // to B — a mismatched (id, action) is a stale straggler and is dropped.
      transport.addIncoming(
        SemanticActionResultFrame(
          a,
          SemanticAction.activate,
          SemanticActionInvocationStatus.failed,
        ),
      );
      await _pump();

      // B's real result then arrives and binds to B.
      transport.addIncoming(
        SemanticActionResultFrame(
          b,
          SemanticAction.activate,
          SemanticActionInvocationStatus.completed,
        ),
      );
      await _pump();

      expect(
        await bResult,
        SemanticActionInvocationStatus.completed,
        reason: 'B must reflect its OWN result, not the stale A failure',
      );
      expect(
        await aResult,
        isNull,
        reason: "A's superseded wait degrades to null (its result was stale)",
      );
    });

    test('a matching result completes the pending action (happy path intact)',
        () async {
      final transport = _EncodingTransport();
      final bridge = FleuryAppBridge(transport)..start();
      addTearDown(bridge.close);

      const a = SemanticNodeId('nodeA');
      final result = bridge.invokeAction(a, SemanticAction.activate);
      transport.addIncoming(
        SemanticActionResultFrame(
          a,
          SemanticAction.activate,
          SemanticActionInvocationStatus.completed,
        ),
      );
      expect(await result, SemanticActionInvocationStatus.completed);
    });

    test('a result matching nothing armed is dropped without error', () async {
      final transport = _EncodingTransport();
      final bridge = FleuryAppBridge(transport)..start();
      addTearDown(bridge.close);

      // No mutation is armed; a stray result must be a no-op (not a crash, and it
      // must not poison the next mutation's wait).
      transport.addIncoming(
        SemanticActionResultFrame(
          const SemanticNodeId('ghost'),
          SemanticAction.activate,
          SemanticActionInvocationStatus.completed,
        ),
      );
      await _pump();

      const a = SemanticNodeId('nodeA');
      final result = bridge.invokeAction(a, SemanticAction.activate);
      transport.addIncoming(
        SemanticActionResultFrame(
          a,
          SemanticAction.activate,
          SemanticActionInvocationStatus.disabled,
        ),
      );
      expect(await result, SemanticActionInvocationStatus.disabled);
    });
  });
}

/// Yields a couple of full event-loop turns so injected frames are delivered and
/// microtask completions run — no wall-clock wait.
Future<void> _pump([int turns = 2]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// An in-memory transport that mirrors `UnixSocketFrameTransport.send`: it
/// encodes each outgoing frame synchronously, so an over-cap payload throws
/// [RemoteProtocolException] exactly as the real wire does. Only frames that
/// encode are recorded in [sent].
final class _EncodingTransport
    with SynchronousSendTransport
    implements RemoteFrameTransport {
  final StreamController<RemoteFrame> _incoming =
      StreamController<RemoteFrame>.broadcast();
  final List<RemoteFrame> sent = <RemoteFrame>[];

  @override
  Stream<RemoteFrame> get incoming => _incoming.stream;

  @override
  void send(RemoteFrame frame) {
    encodeFrame(frame); // throws RemoteProtocolException on an over-cap payload
    sent.add(frame);
  }

  @override
  Future<void> close() async {
    if (!_incoming.isClosed) await _incoming.close();
  }

  void addIncoming(RemoteFrame frame) => _incoming.add(frame);
}
