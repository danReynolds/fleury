// Serve-side guarantees of the shared semantics pipeline, asserted through
// the wire (what an agent/AT mirror actually receives):
//
//   1. Coverage fallback: a painted region with NO semantic node yields
//      synthetic text nodes in the decoded SemanticsFrame — the "no silent
//      AT gaps" guarantee, previously embed-only.
//   2. Retained-leaf economy: a value-only change ships a `patch` envelope
//      (the changed node), not a second `full` frame.
//   3. The diff chain decodes cleanly across flushes.

import 'dart:async';
import 'dart:convert';

import 'package:fleury/fleury.dart';
import 'package:fleury/src/remote/remote_driver.dart';
import 'package:test/test.dart';

import 'remote_test_support.dart';

const _init = InitFrame(
  size: CellSize(40, 4),
  colorMode: ColorMode.truecolor,
  imageProtocol: ImageProtocol.halfBlock,
  tmuxPassthrough: false,
);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

/// Paints raw text cells with NO semantic contributor — the shape a chart
/// or custom render object has. Only the coverage fallback can make this
/// text reachable to AT.
class _OrphanText extends LeafRenderObjectWidget {
  const _OrphanText(this.text);
  final String text;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderOrphanText(text);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderOrphanText).text = text;
  }
}

class _RenderOrphanText extends RenderObject {
  _RenderOrphanText(this._text);

  String _text;
  set text(String value) {
    if (value == _text) return;
    _text = value;
    markNeedsPaint();
  }

  @override
  CellSize performLayout(CellConstraints constraints) =>
      constraints.constrain(CellSize(_text.length, 1));

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellRect? clipRect,
    CellOffset? screenOffset,
  }) {
    buffer.writeText(offset, _text);
  }
}

class _App extends StatefulWidget {
  const _App();

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyCode.char('t'),
          onTrigger: () => setState(() => _count++),
        ),
      ],
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            Semantics(
              id: const SemanticNodeId('count'),
              role: SemanticRole.text,
              label: 'count',
              value: '$_count',
              child: Text('count: $_count'),
            ),
            const _OrphanText('orphan painted text'),
          ],
        ),
      ),
    );
  }
}

Map<String, Object?> _decodeEnvelope(SemanticsFrame frame) =>
    jsonDecode(utf8.decode(frame.json)) as Map<String, Object?>;

void main() {
  test('serve ships coverage fallback and retained-leaf patches', () async {
    final transport = FakeFrameTransport();
    final driver = RemoteTerminalDriver(transport);
    scheduleMicrotask(() => transport.emit(_init));

    final done = runApp(
      const _App(),
      driver: driver,
      enableHotReload: false,
      requireInteractiveTerminal: false,
    );
    await _settle();

    List<SemanticsFrame> semantics() =>
        transport.sent.whereType<SemanticsFrame>().toList();

    // --- 1. Coverage fallback over the wire.
    expect(semantics(), hasLength(1));
    final full = _decodeEnvelope(semantics().first);
    expect(full['mode'], 'full');
    final decoder = SemanticsWireDecoder();
    final tree = decoder.apply(semantics().first.json);
    expect(tree, isNotNull, reason: 'full frame decodes');
    final labels = [
      for (final node in tree!.nodesById.values)
        if (node.label != null) node.label!,
    ];
    // The fallback segments painted text into word-run nodes.
    final joined = labels.join('\n');
    for (final word in ['orphan', 'painted', 'text']) {
      expect(
        joined,
        contains(word),
        reason:
            'painted-but-unannotated text reaches the peer as synthetic '
            'fallback nodes — no silent AT gap over serve',
      );
    }

    // --- 2. A value-only change ships a patch, not a second full frame.
    transport.emit(const InputEventFrame(KeyEvent(KeyCode.char('t'))));
    await _settle();
    expect(semantics(), hasLength(2));
    final patch = _decodeEnvelope(semantics()[1]);
    expect(patch['mode'], 'patch', reason: 'leaf change → patch envelope');
    final setNodes = (patch['set'] as List?) ?? const [];
    expect(
      setNodes.map((n) => (n as Map)['value']).join(','),
      contains('1'),
      reason: 'the count node updated in place',
    );

    // --- 3. The chain keeps decoding.
    final tree2 = decoder.apply(semantics()[1].json);
    expect(tree2, isNotNull);
    expect(
      [
        for (final node in tree2!.nodesById.values)
          if (node.value != null) node.value!,
      ].join(','),
      contains('1'),
    );

    transport.emit(const ByeFrame());
    await done;
    await transport.close();
  });
}
