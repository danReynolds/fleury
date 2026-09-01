import 'dart:async';
import 'dart:convert';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_wire.dart';
import 'package:fleury/src/remote/remote_driver.dart';
import 'package:test/test.dart';

final class _SemanticsTransport
    with SynchronousSendTransport
    implements RemoteFrameTransport {
  final StreamController<RemoteFrame> _incoming =
      StreamController<RemoteFrame>.broadcast();
  final List<RemoteFrame> sent = <RemoteFrame>[];
  bool rejectNextSemantics = false;

  @override
  Stream<RemoteFrame> get incoming => _incoming.stream;

  @override
  void send(RemoteFrame frame) {
    if (frame is SemanticsFrame && rejectNextSemantics) {
      rejectNextSemantics = false;
      throw StateError('injected semantics send rejection');
    }
    sent.add(frame);
  }

  void emit(RemoteFrame frame) => _incoming.add(frame);

  @override
  Future<void> close() async {
    if (!_incoming.isClosed) await _incoming.close();
  }
}

SemanticTree _tree(String label) => SemanticTree(
  root: SemanticNode(
    id: const SemanticNodeId('root'),
    role: SemanticRole.app,
    children: <SemanticNode>[
      SemanticNode(
        id: const SemanticNodeId('status'),
        role: SemanticRole.status,
        label: label,
      ),
    ],
  ),
);

SemanticTree _duplicateInternalIdTree() => SemanticTree(
  root: SemanticNode(
    id: const SemanticNodeId('root'),
    role: SemanticRole.app,
    children: <SemanticNode>[
      SemanticNode(
        id: const SemanticNodeId('duplicate'),
        role: SemanticRole.region,
        children: const <SemanticNode>[
          SemanticNode(
            id: SemanticNodeId('first-leaf'),
            role: SemanticRole.text,
          ),
        ],
      ),
      SemanticNode(
        id: const SemanticNodeId('duplicate'),
        role: SemanticRole.region,
        children: const <SemanticNode>[
          SemanticNode(
            id: SemanticNodeId('second-leaf'),
            role: SemanticRole.text,
          ),
        ],
      ),
    ],
  ),
);

Map<String, Object?> _envelope(SemanticsFrame frame) =>
    jsonDecode(utf8.decode(frame.json)) as Map<String, Object?>;

Future<RemoteTerminalDriver> _enteredDriver(
  _SemanticsTransport transport, {
  SemanticsWireEncoder? semanticsEncoder,
}) async {
  final driver = RemoteTerminalDriver(
    transport,
    semanticsEncoder: semanticsEncoder,
  );
  final entered = driver.enter(TerminalMode.interactive);
  transport.emit(
    const InitFrame(
      size: CellSize(80, 24),
      colorMode: ColorMode.truecolor,
      imageProtocol: ImageProtocol.halfBlock,
      tmuxPassthrough: false,
    ),
  );
  await entered;
  return driver;
}

void main() {
  test(
    'oversized semantics are skipped and the next send is a FULL resync',
    () async {
      final transport = _SemanticsTransport();
      final driver = await _enteredDriver(transport);
      addTearDown(driver.restore);

      final oversizedLabel = 'x'.padRight(
        maxRemoteDocumentFramePayloadLength + 1,
        'x',
      );
      driver.presentSemantics(_tree(oversizedLabel));
      expect(transport.sent.whereType<SemanticsFrame>(), isEmpty);

      driver.presentSemantics(_tree('small enough'));
      final frame = transport.sent.whereType<SemanticsFrame>().single;
      expect(_envelope(frame)['mode'], 'full');
    },
  );

  test('a rejected semantics patch resets the next send to FULL', () async {
    final transport = _SemanticsTransport();
    final driver = await _enteredDriver(transport);
    addTearDown(driver.restore);

    driver.presentSemantics(_tree('initial'));
    expect(
      _envelope(transport.sent.whereType<SemanticsFrame>().single)['mode'],
      'full',
    );

    transport.rejectNextSemantics = true;
    expect(
      () => driver.presentSemantics(_tree('rejected patch')),
      throwsStateError,
    );

    driver.presentSemantics(_tree('recovered'));
    final frames = transport.sent.whereType<SemanticsFrame>().toList();
    expect(frames, hasLength(2));
    expect(_envelope(frames.last)['mode'], 'full');
  });

  test('enter() resets a reused encoder so a new peer gets a FULL tree', () async {
    // `reset()`'s own doc says "call when a new peer connects on a reused
    // encoder" — but nothing called it on connect, only the oversize and
    // send-failure paths. Every session being a fresh process is what made
    // that safe, not the code: the moment an encoder outlives one peer, the
    // next browser's first semantics frame is a PATCH against a base it never
    // received, and its accessibility tree is wrong for the whole session.
    final encoder = SemanticsWireEncoder();

    final firstPeer = _SemanticsTransport();
    final firstDriver = await _enteredDriver(
      firstPeer,
      semanticsEncoder: encoder,
    );
    firstDriver.presentSemantics(_tree('first'));
    firstDriver.presentSemantics(_tree('second'));
    final firstFrames = firstPeer.sent.whereType<SemanticsFrame>().toList();
    expect(firstFrames, hasLength(2));
    expect(_envelope(firstFrames.first)['mode'], 'full');
    expect(
      _envelope(firstFrames.last)['mode'],
      'patch',
      reason: 'the encoder must be carrying peer state into the next connect',
    );
    await firstDriver.restore();

    final secondPeer = _SemanticsTransport();
    final secondDriver = await _enteredDriver(
      secondPeer,
      semanticsEncoder: encoder,
    );
    addTearDown(secondDriver.restore);
    // The same tree the OLD peer last held. A stale encoder diffs it to
    // nothing and sends no frame at all; the new peer must get a full tree.
    secondDriver.presentSemantics(_tree('second'));
    final frames = secondPeer.sent.whereType<SemanticsFrame>().toList();
    expect(
      frames,
      hasLength(1),
      reason: 'a new peer holds nothing — its first frame cannot be a no-op',
    );
    expect(
      _envelope(frames.single)['mode'],
      'full',
      reason: 'a new peer holds nothing to patch against',
    );
  });

  test('a structurally unrepresentable tree is skipped before send', () async {
    final transport = _SemanticsTransport();
    final driver = await _enteredDriver(transport);
    addTearDown(driver.restore);

    // The flat wire would turn the two internal duplicate IDs into a branching
    // DAG and leave one child orphaned. The producer must reject it before its
    // mirror advances, not wait for the peer decoder to reject the frame.
    driver.presentSemantics(_duplicateInternalIdTree());
    expect(transport.sent.whereType<SemanticsFrame>(), isEmpty);

    driver.presentSemantics(_tree('recovered'));
    final frame = transport.sent.whereType<SemanticsFrame>().single;
    expect(_envelope(frame)['mode'], 'full');
  });
}
