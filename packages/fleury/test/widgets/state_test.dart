import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// Records lifecycle calls so tests can assert on the sequence the framework
/// invokes them in.
class _Lifecycle extends StatefulWidget {
  const _Lifecycle({required this.log, this.value = 0});
  final List<String> log;
  final int value;

  @override
  State<_Lifecycle> createState() => _LifecycleState();
}

class _LifecycleState extends State<_Lifecycle> {
  int internalCounter = 0;

  /// Test helper: exposes `setState` so tests can drive the framework without
  /// tripping the `@protected` lint on `State.setState`.
  void poke(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    widget.log.add('initState(value=${widget.value})');
  }

  @override
  void didUpdateWidget(_Lifecycle oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.log.add(
      'didUpdateWidget(old=${oldWidget.value}, new=${widget.value})',
    );
  }

  @override
  void dispose() {
    widget.log.add('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.log.add('build(value=${widget.value})');
    return const EmptyBox();
  }
}

void main() {
  group('State lifecycle', () {
    test('initState runs once on mount, before build', () {
      final log = <String>[];
      final owner = BuildOwner();
      owner.mountRoot(_Lifecycle(log: log));

      expect(log, ['initState(value=0)', 'build(value=0)']);
    });

    test('didUpdateWidget runs on widget update before the rebuild', () {
      final log = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(_Lifecycle(log: log));
      log.clear();

      owner.updateRoot(root, _Lifecycle(log: log, value: 1));

      expect(log, ['didUpdateWidget(old=0, new=1)', 'build(value=1)']);
    });

    test('dispose runs on unmount', () {
      final log = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(_Lifecycle(log: log));
      log.clear();

      // Force unmount by walking the element tree directly.
      root.unmount();

      expect(log, contains('dispose'));
    });

    test('State.widget is typed and reflects the latest widget', () {
      final log = <String>[];
      final owner = BuildOwner();
      final root =
          owner.mountRoot(_Lifecycle(log: log, value: 7)) as StatefulElement;
      final state = root.state as _LifecycleState;
      expect(state.widget.value, 7);

      owner.updateRoot(root, _Lifecycle(log: log, value: 9));
      expect(state.widget.value, 9);
    });

    test('mounted flips to false after dispose', () {
      final log = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(_Lifecycle(log: log)) as StatefulElement;
      final state = root.state as _LifecycleState;
      expect(state.mounted, isTrue);

      root.unmount();
      expect(state.mounted, isFalse);
    });
  });

  group('setState', () {
    test('marks the element dirty and rebuilds on next flush', () {
      final log = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(_Lifecycle(log: log)) as StatefulElement;
      final state = root.state as _LifecycleState;
      log.clear();

      state.poke(() {
        state.internalCounter = 1;
      });

      // markNeedsBuild enqueued the element; no synchronous rebuild yet.
      expect(
        log,
        isEmpty,
        reason: 'setState should not rebuild synchronously.',
      );
      expect(root.dirty, isTrue);

      owner.flushBuild();

      expect(log, ['build(value=0)']);
      expect(root.dirty, isFalse);
      expect(state.internalCounter, 1);
    });

    test('setState after dispose throws StateError', () {
      final log = <String>[];
      final owner = BuildOwner();
      final root = owner.mountRoot(_Lifecycle(log: log)) as StatefulElement;
      final state = root.state as _LifecycleState;

      root.unmount();
      expect(() => state.poke(() {}), throwsA(isA<StateError>()));
    });
  });
}
