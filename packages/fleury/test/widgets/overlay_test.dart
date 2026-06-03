// Overlay + OverlayEntry tests. Exercise the lifecycle (insert,
// remove, mark needs build), stacking order, and opaque-entry
// hiding.

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

Matcher _stateError(String message) => throwsA(
  isA<StateError>().having((error) => error.message, 'message', message),
);

class _Probe extends StatefulWidget {
  const _Probe({required this.label, required this.log});
  final String label;
  final List<String> log;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.log.add('mount:${widget.label}');
  }

  @override
  void dispose() {
    widget.log.add('unmount:${widget.label}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}

/// Locates the first [OverlayState] in the subtree rooted at [root].
/// Used by tests that need to drive [OverlayState.insert] without
/// resorting to a GlobalKey.
OverlayState _findOverlayState(Element root) {
  OverlayState? found;
  void visit(Element e) {
    if (found != null) return;
    if (e is StatefulElement && e.state is OverlayState) {
      found = e.state as OverlayState;
      return;
    }
    e.visitChildren(visit);
  }

  visit(root);
  if (found == null) {
    throw StateError('No OverlayState below this element.');
  }
  return found!;
}

void main() {
  group('Overlay', () {
    test('initialEntries mount in order at construction', () {
      final log = <String>[];
      final owner = BuildOwner();
      owner.mountRoot(
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => _Probe(label: 'A', log: log),
            ),
            OverlayEntry(
              builder: (_) => _Probe(label: 'B', log: log),
            ),
          ],
        ),
      );
      expect(log, ['mount:A', 'mount:B']);
    });

    test('insert appends to the top of the stack', () {
      final log = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => _Probe(label: 'A', log: log),
            ),
          ],
        ),
      );
      final state = _findOverlayState(root);
      final newEntry = OverlayEntry(
        builder: (_) => _Probe(label: 'B', log: log),
      );
      state.insert(newEntry);
      owner.flushBuild();
      expect(log, ['mount:A', 'mount:B']);
      expect(state.entries.length, 2);
      expect(state.entries.last, same(newEntry));
    });

    test('insert below: places the new entry under the anchor', () {
      final owner = BuildOwner();
      final anchorEntry = OverlayEntry(builder: (_) => const Text('anchor'));
      final root = owner.mountRoot(Overlay(initialEntries: [anchorEntry]));
      final state = _findOverlayState(root);
      final lowerEntry = OverlayEntry(builder: (_) => const Text('lower'));
      state.insert(lowerEntry, below: anchorEntry);
      owner.flushBuild();
      expect(state.entries, [lowerEntry, anchorEntry]);
    });

    test('remove unmounts the entry and shrinks the stack', () {
      final log = <String>[];
      final owner = BuildOwner();
      late final OverlayEntry b;
      final root = owner.mountRoot(
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => _Probe(label: 'A', log: log),
            ),
            b = OverlayEntry(
              builder: (_) => _Probe(label: 'B', log: log),
            ),
          ],
        ),
      );
      final state = _findOverlayState(root);
      expect(log, ['mount:A', 'mount:B']);

      b.remove();
      owner.flushBuild();
      expect(log, ['mount:A', 'mount:B', 'unmount:B']);
      expect(state.entries.length, 1);
    });

    test('opaque entry hides lower entries; lower entries with '
        'maintainState=false unmount', () {
      final log = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(
        Overlay(
          initialEntries: [
            OverlayEntry(
              maintainState: false,
              builder: (_) => _Probe(label: 'A', log: log),
            ),
          ],
        ),
      );
      final state = _findOverlayState(root);
      state.insert(
        OverlayEntry(
          opaque: true,
          builder: (_) => _Probe(label: 'opaque', log: log),
        ),
      );
      owner.flushBuild();
      // A is below an opaque entry AND opted out of maintainState,
      // so its subtree gets removed from the Stack and unmounts.
      expect(log, ['mount:A', 'mount:opaque', 'unmount:A']);
    });

    test('opaque entry with maintainState=true (default) keeps the '
        'lower entry mounted', () {
      final log = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(
        Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => _Probe(label: 'A', log: log),
            ),
          ],
        ),
      );
      final state = _findOverlayState(root);
      state.insert(
        OverlayEntry(
          opaque: true,
          builder: (_) => _Probe(label: 'opaque', log: log),
        ),
      );
      owner.flushBuild();
      // A stays mounted (state is preserved across visibility
      // changes); only the opaque entry is added.
      expect(log, ['mount:A', 'mount:opaque']);
    });

    test('markNeedsBuild reaches the entry', () {
      final owner = BuildOwner();
      final entry = OverlayEntry(builder: (_) => const Text('hi'));
      final root = owner.mountRoot(Overlay(initialEntries: [entry]));
      final state = _findOverlayState(root);
      entry.markNeedsBuild();
      // No exception; reachable.
      owner.flushBuild();
      expect(state.entries, [entry]);
    });

    test('disposed entry removes itself and rejects visible mutation', () {
      final owner = BuildOwner();
      final entry = OverlayEntry(builder: (_) => const Text('hi'));
      final root = owner.mountRoot(Overlay(initialEntries: [entry]));
      final state = _findOverlayState(root);

      entry.dispose();
      owner.flushBuild();
      entry.dispose();

      expect(state.entries, isEmpty);
      expect(entry.opaque, isFalse);
      expect(() => entry.remove(), returnsNormally);
      expect(
        () => entry.markNeedsBuild(),
        _stateError('OverlayEntry has been disposed.'),
      );
      expect(
        () => entry.opaque = true,
        _stateError('OverlayEntry has been disposed.'),
      );
    });

    test('disposed entry cannot be inserted', () {
      final owner = BuildOwner();
      final root = owner.mountRoot(Overlay());
      final state = _findOverlayState(root);
      final entry = OverlayEntry(builder: (_) => const Text('disposed'))
        ..dispose();

      expect(
        () => state.insert(entry),
        _stateError('OverlayEntry has been disposed.'),
      );
      expect(state.entries, isEmpty);
    });
  });
}
