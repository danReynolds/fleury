// Deterministic guard on the `get_ui` payload size — the token cost an agent
// pays per snapshot. Unlike latency, JSON byte size is deterministic, so it
// gates cleanly and catches regressions (e.g. a verbose id format, a fat new
// per-node field). Tighten the bounds when the payload genuinely shrinks.
import 'dart:convert';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

// A representative keyed list: a keyed scope, R keyed rows, C unkeyed cells —
// the shape a real data screen produces (rows carry keys, cells don't).
Widget _screen(int rows, int cols) => Semantics(
  key: const ValueKey('list'),
  role: SemanticRole.list,
  child: Column(
    children: <Widget>[
      for (var i = 0; i < rows; i++)
        Semantics(
          key: ValueKey('row-$i'),
          role: SemanticRole.listItem,
          label: 'Row $i',
          child: Row(
            children: <Widget>[
              for (var c = 0; c < cols; c++)
                Semantics(
                  role: SemanticRole.text,
                  label: 'Cell $i.$c',
                  child: Text('C$i.$c'),
                ),
            ],
          ),
        ),
    ],
  ),
);

void main() {
  testWidgets('get_ui payload stays within its per-node token budget', (
    tester,
  ) {
    tester.pumpWidget(_screen(50, 4));
    tester.render(size: const CellSize(60, 20));
    final snapshot = tester.semantics().toInspectionSnapshot();
    final json = jsonEncode(snapshot.toJsonCapped(maxNodes: 800));

    final nodes = snapshot.nodeCount;
    final bytes = json.length;
    final perNode = bytes / nodes;
    // ignore: avoid_print
    print('PAYLOAD nodes=$nodes bytes=$bytes per-node=${perNode.toStringAsFixed(1)} '
        '(~${(bytes / 4).round()} tokens)');

    // Bounds with headroom over the measured size (~160 B/node after the
    // compact-id work). A regression that re-bloats per-node cost — a verbose
    // id, an un-trimmed field — trips this.
    expect(
      perNode,
      lessThan(190),
      reason: 'per-node payload regressed — check id format / node fields',
    );
    expect(
      nodes,
      greaterThan(250),
      reason: 'sanity: the fixture should produce a few hundred nodes',
    );
  });
}
