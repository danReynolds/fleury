// Protocol-half tests for [FleuryAppBridge] over an in-memory transport that
// encodes frames the same way the real Unix-socket transport does — so an
// over-cap in-band payload throws the same [RemoteProtocolException], and
// injected SEMANTIC_ACTION_RESULT frames exercise the real result-correlation
// path. No subprocess is spawned; only the watchdog regression uses a bounded
// wall-clock wait.

import 'dart:async';
import 'dart:convert';

import 'package:fleury/fleury_host.dart';
import 'package:fleury/fleury_wire.dart';
import 'package:fleury_mcp/fleury_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('echoed INIT negotiation', () {
    test('matching app protocol keeps the bridge attached', () async {
      final transport = _EncodingTransport();
      final bridge = FleuryAppBridge(transport)..start();
      addTearDown(bridge.close);

      transport.addIncoming(_appInit(remoteProtocolVersion));
      await _pump();

      expect(bridge.protocolError, isNull);
      expect(bridge.isRunning, isTrue);
      expect(transport.isClosed, isFalse);
    });

    test(
      'mismatched app protocol is rejected before frames are used',
      () async {
        final transport = _EncodingTransport();
        final bridge = FleuryAppBridge(transport)..start();
        addTearDown(bridge.close);

        final appVersion = remoteProtocolVersion - 1;
        transport.addIncoming(_appInit(appVersion));
        await bridge.ready;
        await _pump(4);

        expect(bridge.isRunning, isFalse);
        expect(bridge.snapshot, isNull);
        expect(
          bridge.protocolError,
          allOf(
            contains('protocol mismatch'),
            contains('bridge v$remoteProtocolVersion'),
            contains('app v$appVersion'),
          ),
        );
        expect(transport.sent.whereType<ByeFrame>(), hasLength(1));
        expect(transport.isClosed, isTrue);
      },
    );

    test(
      'positional target tokens require v6 and are forwarded intact',
      () async {
        final transport = _EncodingTransport();
        final bridge = FleuryAppBridge(transport)..start();
        addTearDown(bridge.close);

        expect(
          () => bridge.invokeAction(
            const SemanticNodeId('element-7'),
            SemanticAction.activate,
            targetToken: 'element-build-7',
          ),
          throwsA(isA<FleuryAppBridgeException>()),
        );
        expect(transport.sent.whereType<SemanticActionFrame>(), isEmpty);

        transport.addIncoming(_appInit(remoteProtocolVersion));
        await _pump();
        final result = bridge.invokeAction(
          const SemanticNodeId('element-7'),
          SemanticAction.activate,
          targetToken: 'element-build-7',
        );
        final frame = transport.sent.whereType<SemanticActionFrame>().single;
        expect(frame.targetToken, 'element-build-7');
        transport.addIncoming(
          const SemanticActionResultFrame(
            SemanticNodeId('element-7'),
            SemanticAction.activate,
            SemanticActionInvocationStatus.completed,
          ),
        );
        expect(await result, SemanticActionInvocationStatus.completed);
      },
    );

    test('a semantics frame before the echoed INIT is rejected', () async {
      final transport = _EncodingTransport();
      final bridge = FleuryAppBridge(transport)..start();
      addTearDown(bridge.close);

      final bytes = SemanticsWireEncoder().encode(
        SemanticInspectionSnapshot.fromJson(<String, Object?>{
          'schemaVersion': 1,
          'root': <String, Object?>{'id': 'root', 'role': 'app'},
        }),
      );
      transport.addIncoming(SemanticsFrame(bytes!));
      await bridge.ready;
      await _pump(4);

      expect(bridge.isRunning, isFalse);
      expect(bridge.snapshot, isNull);
      expect(
        bridge.protocolError,
        allOf(contains('negotiation failed'), contains('before echoing')),
      );
      expect(transport.sent.whereType<ByeFrame>(), hasLength(1));
    });

    test('outbound operations require the exact echoed INIT', () async {
      final transport = _EncodingTransport();
      final bridge = FleuryAppBridge(transport)..start();
      addTearDown(bridge.close);

      expect(
        () => bridge.invokeAction(
          const SemanticNodeId('button'),
          SemanticAction.activate,
        ),
        throwsA(isA<FleuryAppBridgeException>()),
      );
      expect(
        () => bridge.setValue(const SemanticNodeId('field'), 'hello'),
        throwsA(isA<FleuryAppBridgeException>()),
      );
      expect(
        () => bridge.typeText('hello'),
        throwsA(isA<FleuryAppBridgeException>()),
      );
      expect(
        () => bridge.pressKey(KeyCode.enter),
        throwsA(isA<FleuryAppBridgeException>()),
      );
      expect(
        () => bridge.resize(const CellSize(100, 40)),
        throwsA(isA<FleuryAppBridgeException>()),
      );
      expect(
        () => bridge.queryDebug('frames'),
        throwsA(isA<FleuryAppBridgeException>()),
      );
      expect(
        transport.sent,
        everyElement(isA<InitFrame>()),
        reason: 'only the bridge INIT may cross the wire before negotiation',
      );
      expect(transport.sent, hasLength(1));

      transport.addIncoming(_appInit(remoteProtocolVersion));
      await _pump();
      bridge.typeText('hello');
      bridge.pressKey(KeyCode.enter);
      bridge.resize(const CellSize(100, 40));

      expect(transport.sent.whereType<InputEventFrame>(), hasLength(2));
      expect(
        transport.sent.whereType<ResizeFrame>().single.size,
        const CellSize(100, 40),
      );
    });

    test('the first-frame watchdog reports a missing echoed INIT', () async {
      final transport = _EncodingTransport();
      final bridge = FleuryAppBridge(
        transport,
        firstFrameTimeout: const Duration(milliseconds: 10),
      )..start();
      addTearDown(bridge.close);

      await bridge.ready;
      await _pump(4);

      expect(bridge.isRunning, isFalse);
      expect(bridge.renderTimedOut, isFalse);
      expect(
        bridge.protocolError,
        allOf(contains('negotiation failed'), contains('did not echo')),
      );
    });

    test('input and resize throw after the app exits', () async {
      final transport = _EncodingTransport();
      final bridge = FleuryAppBridge(transport)..start();
      addTearDown(bridge.close);
      transport.addIncoming(_appInit(remoteProtocolVersion));
      await _pump();
      transport.addIncoming(const ByeFrame());
      await _pump();

      expect(bridge.isRunning, isFalse);
      for (final operation in <void Function()>[
        () => bridge.typeText('hello'),
        () => bridge.pressKey(KeyCode.enter),
        () => bridge.resize(const CellSize(100, 40)),
      ]) {
        expect(operation, throwsA(isA<FleuryAppBridgeException>()));
      }
      expect(
        () => bridge.typeText(''),
        returnsNormally,
        reason: 'empty text remains an intentional no-op after exit',
      );
    });

    test(
      'semantics queued after BYE cannot mutate the last snapshot',
      () async {
        final transport = _EncodingTransport();
        final bridge = FleuryAppBridge(transport)..start();
        addTearDown(bridge.close);
        final encoder = SemanticsWireEncoder();

        transport.addIncoming(_appInit(remoteProtocolVersion));
        transport.addIncoming(
          SemanticsFrame(
            encoder.encode(
              SemanticInspectionSnapshot.fromJson(<String, Object?>{
                'schemaVersion': 1,
                'root': <String, Object?>{
                  'id': 'root',
                  'role': 'app',
                  'label': 'before exit',
                },
              }),
            )!,
          ),
        );
        await bridge.ready;
        final beforeSnapshot = bridge.snapshot;
        final beforeRevision = bridge.revision;

        transport.addIncoming(const ByeFrame());
        transport.addIncoming(
          SemanticsFrame(
            encoder.encode(
              SemanticInspectionSnapshot.fromJson(<String, Object?>{
                'schemaVersion': 1,
                'root': <String, Object?>{
                  'id': 'root',
                  'role': 'app',
                  'label': 'after exit',
                },
              }),
            )!,
          ),
        );
        await _pump();

        expect(bridge.isRunning, isFalse);
        expect(bridge.revision, beforeRevision);
        expect(bridge.snapshot, same(beforeSnapshot));
        expect(bridge.snapshot!.root.label, 'before exit');
      },
    );

    test(
      'close settles lifecycle and attempts every cleanup when cleanup throws',
      () async {
        final transport = _EncodingTransport(
          closeError: StateError('transport close failed'),
        );
        var onCloseCalls = 0;
        final bridge = FleuryAppBridge(
          transport,
          onClose: () async {
            onCloseCalls++;
            throw StateError('process close failed');
          },
        )..start();

        await expectLater(bridge.close(), completes);

        expect(transport.closeCalls, 1);
        expect(onCloseCalls, 1);
        expect(bridge.isRunning, isFalse);
        await expectLater(bridge.done, completes);
        await expectLater(
          bridge.close(),
          completes,
          reason: 'failed cleanup still leaves close idempotent',
        );
      },
    );
  });

  group('local encode failures do not kill a healthy app', () {
    test(
      'an over-cap press_key chord is rejected, not read as app death',
      () async {
        final transport = _EncodingTransport();
        final bridge = FleuryAppBridge(transport)..start();
        addTearDown(bridge.close);
        transport.addIncoming(_appInit(remoteProtocolVersion));
        await _pump();

        var doneFired = false;
        unawaited(bridge.done.then((_) => doneFired = true));

        // A ~1 MiB literal char held as a chord: encodeInputEvent writes the char
        // uncapped, so the INPUT_EVENT frame overruns the 1 MiB input cap and
        // encodeFrame rejects it ("frame was not encoded") — the socket is intact.
        final huge = 'x' * (maxRemoteInputFramePayloadLength + 1024);
        expect(
          () => bridge.pressKey(
            KeyCode.char(huge),
            modifiers: {KeyModifier.ctrl},
          ),
          throwsA(isA<RemoteProtocolException>()),
          reason: 'an over-cap frame is a recoverable encode rejection',
        );

        // The bridge must NOT have declared the healthy app dead.
        expect(bridge.isRunning, isTrue, reason: 'app must stay attached');
        expect(
          doneFired,
          isFalse,
          reason: 'no teardown — bridge.done must not fire',
        );
        // The rejected chord was never handed to the wire.
        expect(transport.sent.whereType<InputEventFrame>(), isEmpty);
      },
    );

    test(
      'an over-cap set_value payload is rejected, not read as app death',
      () async {
        final transport = _EncodingTransport();
        final bridge = FleuryAppBridge(transport)..start();
        addTearDown(bridge.close);
        transport.addIncoming(_appInit(remoteProtocolVersion));
        await _pump();

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
          reason:
              'an over-cap set_value must throw, not be swallowed as app death',
        );
        expect(bridge.isRunning, isTrue, reason: 'app must stay attached');
        await _pump();
        expect(
          doneFired,
          isFalse,
          reason: 'no teardown — bridge.done must not fire',
        );
        expect(transport.sent.whereType<SemanticActionFrame>(), isEmpty);
      },
    );

    test(
      'a structured codec rejection aborts the action waiter and rethrows',
      () async {
        final transport = _EncodingTransport();
        final bridge = FleuryAppBridge(transport)..start();
        addTearDown(bridge.close);
        transport.addIncoming(_appInit(remoteProtocolVersion));
        await _pump();

        expect(
          () => bridge.invokeAction(
            const SemanticNodeId('element-7'),
            SemanticAction.activate,
            targetToken: 'x' * 65,
          ),
          throwsA(isA<RemoteCodecException>()),
        );
        expect(bridge.isRunning, isTrue);
        expect(bridge.protocolError, isNull);
        expect(transport.sent.whereType<SemanticActionFrame>(), isEmpty);

        const validId = SemanticNodeId('save');
        final valid = bridge.invokeAction(validId, SemanticAction.activate);
        transport.addIncoming(
          const SemanticActionResultFrame(
            validId,
            SemanticAction.activate,
            SemanticActionInvocationStatus.completed,
          ),
        );
        expect(await valid, SemanticActionInvocationStatus.completed);
      },
    );

    test(
      'a local JSON encode failure aborts the action waiter and rethrows',
      () async {
        final transport = _EncodingTransport();
        final bridge = FleuryAppBridge(transport)..start();
        addTearDown(bridge.close);
        transport.addIncoming(_appInit(remoteProtocolVersion));
        await _pump();

        expect(
          () => bridge.setValue(const SemanticNodeId('field'), Object()),
          throwsA(isA<JsonUnsupportedObjectError>()),
        );
        expect(bridge.isRunning, isTrue);
        expect(bridge.protocolError, isNull);
        expect(transport.sent.whereType<SemanticActionFrame>(), isEmpty);

        const validId = SemanticNodeId('save');
        final valid = bridge.invokeAction(validId, SemanticAction.activate);
        transport.addIncoming(
          const SemanticActionResultFrame(
            validId,
            SemanticAction.activate,
            SemanticActionInvocationStatus.completed,
          ),
        );
        expect(await valid, SemanticActionInvocationStatus.completed);
      },
    );

    test(
      'an overlong debug kind fails locally without killing later queries',
      () async {
        final transport = _EncodingTransport();
        final bridge = FleuryAppBridge(transport)..start();
        addTearDown(bridge.close);
        transport.addIncoming(_appInit(remoteProtocolVersion));
        await _pump();

        expect(
          () => bridge.queryDebug('x' * 256),
          throwsA(isA<ArgumentError>()),
        );
        expect(bridge.isRunning, isTrue);
        expect(bridge.protocolError, isNull);
        expect(transport.sent.whereType<DebugRequestFrame>(), isEmpty);

        final valid = bridge.queryDebug('logs');
        final request = transport.sent.whereType<DebugRequestFrame>().single;
        transport.addIncoming(
          DebugResponseFrame(request.seq, 'logs', utf8.encode('[]')),
        );
        expect(await valid, isEmpty);
      },
    );
  });

  group('SEMANTIC_ACTION_RESULT is correlated to its request', () {
    test(
      'a second action cannot supersede one whose result is pending',
      () async {
        final transport = _EncodingTransport();
        final bridge = FleuryAppBridge(transport)..start();
        addTearDown(bridge.close);
        transport.addIncoming(_appInit(remoteProtocolVersion));
        await _pump();

        const a = SemanticNodeId('nodeA');
        const b = SemanticNodeId('nodeB');

        // The MCP server serializes mutations, but the bridge is public. Reject
        // direct concurrent use rather than replacing the only correlation slot.
        final aResult = bridge.invokeAction(a, SemanticAction.activate);
        expect(
          () => bridge.invokeAction(b, SemanticAction.activate),
          throwsA(
            predicate<Object>(
              (error) => error.toString().contains('still awaiting its result'),
            ),
          ),
        );

        transport.addIncoming(
          SemanticActionResultFrame(
            a,
            SemanticAction.activate,
            SemanticActionInvocationStatus.completed,
          ),
        );
        expect(await aResult, SemanticActionInvocationStatus.completed);
      },
    );

    test(
      'a timed-out action blocks same-target retry until its late result',
      () async {
        final transport = _EncodingTransport();
        final bridge = FleuryAppBridge(transport)..start();
        addTearDown(bridge.close);
        transport.addIncoming(_appInit(remoteProtocolVersion));
        await _pump();

        const id = SemanticNodeId('same-node');
        final first = bridge.invokeAction(id, SemanticAction.activate);
        await expectLater(
          first,
          throwsA(
            predicate<Object>(
              (error) =>
                  error.toString().contains('did not acknowledge "activate"') &&
                  error.toString().contains('late result'),
            ),
          ),
        );

        expect(bridge.isRunning, isTrue);
        expect(
          () => bridge.invokeAction(id, SemanticAction.activate),
          throwsA(
            predicate<Object>(
              (error) =>
                  error.toString().contains('timed-out "activate"') &&
                  error.toString().contains('late result'),
            ),
          ),
          reason: 'the late first result must have no retry slot to satisfy',
        );
        expect(transport.sent.whereType<SemanticActionFrame>(), hasLength(1));

        // The exact late result clears the tombstone but cannot complete the
        // already-timed-out caller. A fresh retry gets its own result slot.
        transport.addIncoming(
          const SemanticActionResultFrame(
            id,
            SemanticAction.activate,
            SemanticActionInvocationStatus.completed,
          ),
        );
        await _pump();
        final retry = bridge.invokeAction(id, SemanticAction.activate);
        expect(transport.sent.whereType<SemanticActionFrame>(), hasLength(2));
        transport.addIncoming(
          const SemanticActionResultFrame(
            id,
            SemanticAction.activate,
            SemanticActionInvocationStatus.disabled,
          ),
        );
        expect(await retry, SemanticActionInvocationStatus.disabled);
      },
    );

    test(
      'a matching result completes the pending action (happy path intact)',
      () async {
        final transport = _EncodingTransport();
        final bridge = FleuryAppBridge(transport)..start();
        addTearDown(bridge.close);
        transport.addIncoming(_appInit(remoteProtocolVersion));
        await _pump();

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
      },
    );

    test('a result matching nothing armed is dropped without error', () async {
      final transport = _EncodingTransport();
      final bridge = FleuryAppBridge(transport)..start();
      addTearDown(bridge.close);
      transport.addIncoming(_appInit(remoteProtocolVersion));
      await _pump();

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

InitFrame _appInit(int protocolVersion) => InitFrame(
  size: const CellSize(80, 24),
  colorMode: ColorMode.truecolor,
  glyphTier: GlyphTier.unicode,
  imageProtocol: ImageProtocol.halfBlock,
  tmuxPassthrough: false,
  protocolVersion: protocolVersion,
);

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
  _EncodingTransport({this.closeError});

  final Object? closeError;
  final StreamController<RemoteFrame> _incoming =
      StreamController<RemoteFrame>.broadcast();
  final List<RemoteFrame> sent = <RemoteFrame>[];
  bool isClosed = false;
  int closeCalls = 0;

  @override
  Stream<RemoteFrame> get incoming => _incoming.stream;

  @override
  void send(RemoteFrame frame) {
    encodeFrame(frame); // throws RemoteProtocolException on an over-cap payload
    sent.add(frame);
  }

  @override
  Future<void> close() async {
    closeCalls++;
    isClosed = true;
    if (!_incoming.isClosed) await _incoming.close();
    if (closeError case final error?) throw error;
  }

  void addIncoming(RemoteFrame frame) => _incoming.add(frame);
}
