// The served browser client must PATCH the accessibility DOM in place on a
// semantic wire patch, not tear it down and rebuild the whole tree every frame.
// This drives the real client pipeline — SemanticsWireEncoder.encodeTree (server)
// → SemanticsWireDecoder (client) → SemanticsOwner.update → SemanticDomPresenter
// — exactly what wire_frame_source now wires, and asserts a one-node patch
// reuses just the one element instead of re-processing the whole tree.
@TestOn('browser')
library;

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/semantics/semantic_dom_presenter.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

SemanticTree _tree(int tick) => SemanticTree(
  root: SemanticNode(
    id: const SemanticNodeId('root'),
    role: SemanticRole.app,
    children: [
      const SemanticNode(
        id: SemanticNodeId('a'),
        role: SemanticRole.text,
        label: 'A',
        value: 'A',
      ),
      const SemanticNode(
        id: SemanticNodeId('b'),
        role: SemanticRole.text,
        label: 'B',
        value: 'B',
      ),
      SemanticNode(
        id: const SemanticNodeId('c'),
        role: SemanticRole.text,
        label: 'C $tick',
        value: 'C $tick',
      ),
    ],
  ),
);

void main() {
  test('a decoded patch updates the DOM in place, not a full rebuild', () {
    // Server: a full frame, then a patch touching only node `c`.
    final encoder = SemanticsWireEncoder();
    final serverOwner = SemanticsOwner();
    final t0 = _tree(0);
    final full = encoder.encodeTree(t0, update: serverOwner.update(t0))!;
    final t1 = _tree(1);
    final patch = encoder.encodeTree(t1, update: serverOwner.update(t1))!;

    // Client: decode → owner.update → present (the wire_frame_source pipeline).
    final root = web.document.createElement('div');
    final presenter = SemanticDomPresenter(root: root);
    final decoder = SemanticsWireDecoder();
    final clientOwner = SemanticsOwner();

    final d0 = decoder.apply(full)!;
    presenter.present(d0, update: clientOwner.update(d0)); // full build
    final cElement = root.querySelector('[data-fleury-semantic-id="c"]')!;

    final d1 = decoder.apply(patch)!;
    final stats = presenter.present(d1, update: clientOwner.update(d1));

    // Incremental: the presenter reuses ONLY the one changed element (a full
    // rebuild would re-process all four nodes, root + a + b + c).
    expect(
      stats.reusedElementCount,
      1,
      reason: 'a one-node patch must touch one element; a full rebuild would '
          're-process the whole tree',
    );
    expect(stats.createdElementCount, 0);
    expect(
      root.querySelector('[data-fleury-semantic-id="c"]'),
      same(cElement),
      reason: 'the changed node is patched in place, not recreated',
    );
    expect(cElement.textContent, contains('C 1'));

    // The unchanged siblings are left entirely alone.
    expect(root.querySelector('[data-fleury-semantic-id="a"]'), isNotNull);
    expect(root.querySelector('[data-fleury-semantic-id="b"]'), isNotNull);
  });
}
