// "What has focus" must name the node that holds focus.
//
// A node's `focused` flag is set by the control that holds focus and also by
// regions that report focus anywhere inside them — FocusDetector nests like
// CSS :focus-within, and a pane that accents while one of its controls has
// the keys reports the same thing semantically. Such a region encloses the
// control and comes first in tree order, so "the first focused node" is the
// region, not the control. Agents (inspection `focusedNodeId`), the
// accessibility snapshot, the browser host, and the debug panel all read
// this answer.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

/// A region that reports focus while focus is anywhere inside it: the shape
/// of the bundled Panel, isolating the primitive focus contract.
class _Pane extends StatefulWidget {
  const _Pane({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  State<_Pane> createState() => _PaneState();
}

class _PaneState extends State<_Pane> {
  bool _focusWithin = false;

  @override
  Widget build(BuildContext context) => Semantics(
    role: SemanticRole.region,
    label: widget.label,
    focused: _focusWithin,
    child: FocusDetector(
      onFocusChange: (within) => setState(() => _focusWithin = within),
      child: widget.child,
    ),
  );
}

SemanticNode _node(
  String id,
  SemanticRole role, {
  bool focused = false,
  List<SemanticNode> children = const [],
}) => SemanticNode(
  id: SemanticNodeId(id),
  role: role,
  label: id,
  focused: focused,
  children: children,
);

SemanticTree _tree(List<SemanticNode> children) => SemanticTree(
  root: SemanticNode(
    id: const SemanticNodeId('root'),
    role: SemanticRole.app,
    children: children,
  ),
);

void main() {
  testWidgets('a control focused inside a focus-reporting region', (tester) {
    tester.pumpWidget(
      _Pane(
        label: 'Release',
        child: Column(
          children: [
            const Text('Ready to ship'),
            Button(text: 'Deploy', autofocus: true, onPressed: () {}),
          ],
        ),
      ),
    );
    tester.render(size: const CellSize(24, 4));

    final tree = tester.semantics();
    final region = tree.single(role: SemanticRole.region, label: 'Release');
    expect(region.focused, isTrue, reason: 'the region reports focus within');
    expect(tree.focusedNode?.role, SemanticRole.button);
    expect(tree.focusedNode?.label, 'Deploy');

    final accessibility = tester.accessibilitySnapshot();
    expect(accessibility.focusedNode?.role, SemanticRole.button);
    expect(accessibility.focusedNode?.label, 'Deploy');
    expect(
      accessibility.summary.focusedNodeId,
      accessibility.focusedNode?.sourceId,
    );
    expect(accessibility.summary.focusedLabel, 'Deploy');

    final inspection = tester.semanticInspectionSnapshot();
    final focused = inspection.nodeById(inspection.focusedNodeId!);
    expect(focused?.role, SemanticRole.button.name);
    expect(focused?.label, 'Deploy');
  });

  group('every focus reader takes the deepest node on the focus path', () {
    // Each case runs through the live tree, the inspection snapshot (from the
    // tree, and parsed from JSON without a producer's answer), and the
    // accessibility snapshot, so they can't disagree.
    void expectFocused(SemanticTree tree, String? id) {
      expect(tree.focusedNode?.id.value, id, reason: 'tree');
      final inspection = tree.toInspectionSnapshot();
      expect(inspection.focusedNodeId, id, reason: 'inspection');
      final json = inspection.toJson()..remove('focusedNodeId');
      expect(
        SemanticInspectionSnapshot.fromJson(json).focusedNodeId,
        id,
        reason: 'inspection parsed from JSON',
      );
      final accessibility = tree.toAccessibilitySnapshot();
      expect(accessibility.focusedNode?.sourceId.value, id);
      expect(accessibility.summary.focusedNodeId?.value, id);
    }

    test('a control inside a focused region', () {
      expectFocused(
        _tree([
          _node(
            'pane',
            SemanticRole.region,
            focused: true,
            children: [
              _node('status', SemanticRole.text),
              _node('deploy', SemanticRole.button, focused: true),
            ],
          ),
        ]),
        'deploy',
      );
    });

    test('through nested regions and a node that reports nothing', () {
      expectFocused(
        _tree([
          _node(
            'outer',
            SemanticRole.region,
            focused: true,
            children: [
              _node(
                'inner',
                SemanticRole.region,
                focused: true,
                children: [
                  _node(
                    'form',
                    SemanticRole.form,
                    children: [
                      _node('name', SemanticRole.textField, focused: true),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ]),
        'name',
      );
    });

    test('the current row of a focused table', () {
      expectFocused(
        _tree([
          _node(
            'runs',
            SemanticRole.table,
            focused: true,
            children: [
              _node('run-1', SemanticRole.tableRow),
              _node('run-2', SemanticRole.tableRow, focused: true),
            ],
          ),
        ]),
        'run-2',
      );
    });

    test('the first focus path in tree order, when there are two', () {
      // A text field holds focus while its popup, mounted later in an
      // overlay, marks the highlighted suggestion.
      expectFocused(
        _tree([
          _node('query', SemanticRole.textField, focused: true),
          _node(
            'suggestions',
            SemanticRole.list,
            children: [
              _node('suggestion', SemanticRole.listItem, focused: true),
            ],
          ),
        ]),
        'query',
      );
    });

    test('none when nothing reports focus', () {
      expectFocused(_tree([_node('deploy', SemanticRole.button)]), null);
    });
  });
}
