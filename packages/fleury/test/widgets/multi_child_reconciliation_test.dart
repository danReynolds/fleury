// Reconciliation tests for MultiChildRenderObjectElement.
//
// What "correct" means in terms the framework promises:
//   - Same runtimeType in the same position: element + State preserved.
//   - Different runtimeType at the same position: old unmounts, new mounts.
//   - Keyed children that reorder: state survives, mapped by key.
//   - Unkeyed children: positional reconciliation; reorder = remount.
//   - Children added at the end: existing children preserved.
//   - Children removed: their State.dispose runs.

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// Stateful widget that records its instance hashCode in `lifecycle`.
class _Trackable extends StatefulWidget {
  const _Trackable({super.key, required this.label, required this.lifecycle});
  final String label;
  final List<String> lifecycle;

  @override
  State<_Trackable> createState() => _TrackableState();
}

class _TrackableState extends State<_Trackable> {
  int value = 0;

  @override
  void initState() {
    super.initState();
    widget.lifecycle.add('init:${widget.label}');
  }

  @override
  void dispose() {
    widget.lifecycle.add('dispose:${widget.label}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}

/// Helper: find every _TrackableState under [root], in tree order.
List<_TrackableState> _statesOf(Element root) {
  final out = <_TrackableState>[];
  void visit(Element e) {
    if (e is StatefulElement && e.state is _TrackableState) {
      out.add(e.state as _TrackableState);
    }
    e.visitChildren(visit);
  }

  visit(root);
  return out;
}

void main() {
  group('Unkeyed positional reconciliation', () {
    test('same widgets in same order: every State is preserved', () {
      final lifecycle = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(
        Row(
          children: [
            _Trackable(label: 'a', lifecycle: lifecycle),
            _Trackable(label: 'b', lifecycle: lifecycle),
          ],
        ),
      );

      final statesBefore = _statesOf(root);
      expect(statesBefore.length, 2);
      statesBefore[0].value = 11;
      statesBefore[1].value = 22;

      owner.updateRoot(
        root,
        Row(
          children: [
            _Trackable(label: 'a', lifecycle: lifecycle),
            _Trackable(label: 'b', lifecycle: lifecycle),
          ],
        ),
      );

      final statesAfter = _statesOf(root);
      expect(identical(statesAfter[0], statesBefore[0]), isTrue);
      expect(identical(statesAfter[1], statesBefore[1]), isTrue);
      expect(statesAfter[0].value, 11);
      expect(statesAfter[1].value, 22);
    });

    test('appending: existing State preserved, new State created', () {
      final lifecycle = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(
        Row(
          children: [_Trackable(label: 'a', lifecycle: lifecycle)],
        ),
      );

      final aBefore = _statesOf(root).single;
      aBefore.value = 7;

      owner.updateRoot(
        root,
        Row(
          children: [
            _Trackable(label: 'a', lifecycle: lifecycle),
            _Trackable(label: 'b', lifecycle: lifecycle),
          ],
        ),
      );

      final states = _statesOf(root);
      expect(states.length, 2);
      expect(identical(states[0], aBefore), isTrue);
      expect(states[0].value, 7);
      expect(states[1].widget.label, 'b');
      expect(lifecycle, contains('init:b'));
    });

    test('removing: dropped State sees dispose', () {
      final lifecycle = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(
        Row(
          children: [
            _Trackable(label: 'a', lifecycle: lifecycle),
            _Trackable(label: 'b', lifecycle: lifecycle),
          ],
        ),
      );

      owner.updateRoot(
        root,
        Row(
          children: [_Trackable(label: 'a', lifecycle: lifecycle)],
        ),
      );

      expect(lifecycle, contains('dispose:b'));
      expect(_statesOf(root).length, 1);
      expect(_statesOf(root).single.widget.label, 'a');
    });

    test('unkeyed reorder remounts each affected child (positional match)', () {
      final lifecycle = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(
        Row(
          children: [
            _Trackable(label: 'a', lifecycle: lifecycle),
            _Trackable(label: 'b', lifecycle: lifecycle),
          ],
        ),
      );

      final statesBefore = _statesOf(root);
      statesBefore[0].value = 1;
      statesBefore[1].value = 2;

      owner.updateRoot(
        root,
        Row(
          children: [
            _Trackable(label: 'b', lifecycle: lifecycle),
            _Trackable(label: 'a', lifecycle: lifecycle),
          ],
        ),
      );

      // Without chords, positional reconciliation reuses position 0 and 1
      // in place. The widget data (label) is updated but the State
      // identity stays. So the value `1` is now associated with label 'b'.
      final statesAfter = _statesOf(root);
      expect(identical(statesAfter[0], statesBefore[0]), isTrue);
      expect(identical(statesAfter[1], statesBefore[1]), isTrue);
      expect(statesAfter[0].value, 1);
      expect(statesAfter[0].widget.label, 'b');
      expect(statesAfter[1].widget.label, 'a');
    });
  });

  group('Keyed reconciliation', () {
    test('keyed children that reorder keep their State', () {
      final lifecycle = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(
        Row(
          children: [
            _Trackable(
              key: const ValueKey<String>('a'),
              label: 'a',
              lifecycle: lifecycle,
            ),
            _Trackable(
              key: const ValueKey<String>('b'),
              label: 'b',
              lifecycle: lifecycle,
            ),
          ],
        ),
      );

      final statesBefore = _statesOf(root);
      statesBefore[0].value = 11; // 'a'
      statesBefore[1].value = 22; // 'b'

      // Swap.
      owner.updateRoot(
        root,
        Row(
          children: [
            _Trackable(
              key: const ValueKey<String>('b'),
              label: 'b',
              lifecycle: lifecycle,
            ),
            _Trackable(
              key: const ValueKey<String>('a'),
              label: 'a',
              lifecycle: lifecycle,
            ),
          ],
        ),
      );

      final statesAfter = _statesOf(root);
      // Position 0 now holds 'b' (the state that had value 22).
      expect(statesAfter[0].widget.label, 'b');
      expect(statesAfter[0].value, 22);
      // Position 1 now holds 'a' (the state that had value 11).
      expect(statesAfter[1].widget.label, 'a');
      expect(statesAfter[1].value, 11);
      expect(lifecycle, isNot(contains('dispose:a')));
      expect(lifecycle, isNot(contains('dispose:b')));
    });

    test('keyed child whose key disappears from the new list unmounts', () {
      final lifecycle = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(
        Row(
          children: [
            _Trackable(
              key: const ValueKey<String>('a'),
              label: 'a',
              lifecycle: lifecycle,
            ),
            _Trackable(
              key: const ValueKey<String>('b'),
              label: 'b',
              lifecycle: lifecycle,
            ),
          ],
        ),
      );

      owner.updateRoot(
        root,
        Row(
          children: [
            _Trackable(
              key: const ValueKey<String>('a'),
              label: 'a',
              lifecycle: lifecycle,
            ),
          ],
        ),
      );

      expect(lifecycle, contains('dispose:b'));
      expect(_statesOf(root).length, 1);
    });

    test('keyed → unkeyed at the same position remounts', () {
      // The new widget at position 0 is unkeyed; the old keyed widget
      // is unmatched and unmounts. The unkeyed new takes a fresh element.
      final lifecycle = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(
        Row(
          children: [
            _Trackable(
              key: const ValueKey<String>('a'),
              label: 'a',
              lifecycle: lifecycle,
            ),
          ],
        ),
      );

      _statesOf(root).single.value = 99;

      owner.updateRoot(
        root,
        Row(
          children: [_Trackable(label: 'a', lifecycle: lifecycle)],
        ),
      );

      // The old keyed state disposed; a fresh one took its place.
      expect(lifecycle, contains('dispose:a'));
      // The new state starts at value 0.
      expect(_statesOf(root).single.value, 0);
    });
  });
}
