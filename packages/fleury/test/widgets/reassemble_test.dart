// Tests for BuildOwner.reassembleApplication. These don't actually
// exercise a VM reload — instead they verify the framework's tree walk
// and rebuild semantics, which is the part the framework owns. The
// VM-level reload semantics are validated separately by
// `tool/hot_reload_probe/`.

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

class _ReassembleCounter extends StatefulWidget {
  const _ReassembleCounter({required this.log});
  final List<String> log;

  @override
  State<_ReassembleCounter> createState() => _ReassembleCounterState();
}

class _ReassembleCounterState extends State<_ReassembleCounter> {
  int count = 0;
  int reassembleCalls = 0;
  int buildCalls = 0;

  /// Test helper to bypass the `@protected` lint on `setState`.
  void poke(VoidCallback fn) => setState(fn);

  @override
  void reassemble() {
    super.reassemble();
    reassembleCalls += 1;
    widget.log.add('reassemble');
  }

  @override
  Widget build(BuildContext context) {
    buildCalls += 1;
    widget.log.add('build:$count');
    return Text('$count');
  }
}

/// Wraps a child in a StatelessWidget so we can verify the walk
/// descends through component elements as well as render-object ones.
class _Wrap extends StatelessWidget {
  const _Wrap({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

List<_ReassembleCounterState> _findStates(Element root) {
  final result = <_ReassembleCounterState>[];
  void visit(Element e) {
    if (e is StatefulElement && e.state is _ReassembleCounterState) {
      result.add(e.state as _ReassembleCounterState);
    }
    e.visitChildren(visit);
  }

  visit(root);
  return result;
}

void main() {
  group('reassembleApplication — tree walk', () {
    test('throws if called before mountRoot', () {
      final owner = BuildOwner();
      expect(owner.reassembleApplication, throwsA(isA<StateError>()));
    });

    test('calls State.reassemble on every StatefulElement', () {
      final log = <String>[];
      final owner = BuildOwner();
      owner.mountRoot(
        _Wrap(
          child: Row(
            children: [
              _ReassembleCounter(log: log),
              _Wrap(child: _ReassembleCounter(log: log)),
            ],
          ),
        ),
      );

      // Drain initial-build log entries.
      log.clear();

      owner.reassembleApplication();

      // Two _ReassembleCounter instances; each should see one
      // reassemble call.
      expect(log.where((e) => e == 'reassemble').length, 2);
    });

    test('every State has its build() invoked again, fields preserved', () {
      final log = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(_ReassembleCounter(log: log));
      final state = _findStates(root).single;
      state.count = 7;
      log.clear();

      owner.reassembleApplication();

      // Field value preserved, build called again.
      expect(state.count, 7);
      expect(log.where((e) => e.startsWith('build:')).length, 1);
      expect(log, contains('build:7'));
    });

    test('State identity is preserved across reassemble', () {
      final log = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(_ReassembleCounter(log: log));
      final stateBefore = _findStates(root).single;
      stateBefore.count = 3;

      owner.reassembleApplication();

      final stateAfter = _findStates(root).single;
      expect(identical(stateAfter, stateBefore), isTrue);
      expect(stateAfter.count, 3);
    });

    test('reassemble in a multi-child tree rebuilds every child', () {
      final log = <String>[];
      final owner = BuildOwner();
      owner.mountRoot(
        Row(
          children: [
            _ReassembleCounter(log: log),
            _ReassembleCounter(log: log),
            _ReassembleCounter(log: log),
          ],
        ),
      );
      log.clear();

      owner.reassembleApplication();

      // Three counters; each built once on reassemble.
      expect(log.where((e) => e.startsWith('build:')).length, 3);
    });

    test('reassemble order: reassemble() runs before build()', () {
      // The framework promises that State.reassemble runs before the
      // element is rebuilt, so subclasses can clear caches that
      // build() reads. Verify by checking the log order.
      final log = <String>[];
      final owner = BuildOwner();
      owner.mountRoot(_ReassembleCounter(log: log));
      log.clear();

      owner.reassembleApplication();

      final reassembleIndex = log.indexOf('reassemble');
      final buildIndex = log.indexWhere((e) => e.startsWith('build:'));
      expect(reassembleIndex, greaterThanOrEqualTo(0));
      expect(buildIndex, greaterThan(reassembleIndex));
    });
  });

  group('onScheduleBuild hook', () {
    test('fires when the dirty queue transitions from empty to non-empty', () {
      final owner = BuildOwner();
      var fires = 0;
      owner.onScheduleBuild = () => fires += 1;

      final log = <String>[];
      final root =
          owner.mountRoot(_ReassembleCounter(log: log)) as StatefulElement;
      final state = root.state as _ReassembleCounterState;
      fires = 0; // ignore initial mount

      // First setState fires.
      state.poke(() => state.count = 1);
      expect(fires, 1);

      // Second setState (without flush in between) doesn't re-fire.
      state.poke(() => state.count = 2);
      expect(
        fires,
        1,
        reason:
            'Subsequent setStates while dirty re-use the '
            'already-scheduled frame.',
      );

      owner.flushBuild();
      // After flushing, a new setState fires again.
      state.poke(() => state.count = 3);
      expect(fires, 2);
    });
  });
}
