import 'dart:async';
import 'dart:convert';

import 'package:fleury/fleury.dart';
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
  _SemanticsTransport transport,
) async {
  final driver = RemoteTerminalDriver(transport);
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
