import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

/// A stateful widget whose `State` is observable by identity. Tests use it to
/// assert that `State<T>` survives reconciliation when runtimeType+key match,
/// and is replaced otherwise.
class _Counter extends StatefulWidget {
  const _Counter({super.key, this.label = 'a'});
  final String label;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  bool disposed = false;
  String? lastDidUpdateOldLabel;

  @override
  void didUpdateWidget(_Counter oldWidget) {
    super.didUpdateWidget(oldWidget);
    lastDidUpdateOldLabel = oldWidget.label;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const EmptyBox();
}

/// A second stateful widget type, distinct from `_Counter`. Used to verify
/// runtimeType mismatch forces a remount.
class _OtherStateful extends StatefulWidget {
  const _OtherStateful();
  @override
  State<_OtherStateful> createState() => _OtherStatefulState();
}

class _OtherStatefulState extends State<_OtherStateful> {
  @override
  Widget build(BuildContext context) => const EmptyBox();
}

void main() {
  group('Widget.canUpdate', () {
    test('matches on runtimeType and key', () {
      expect(Widget.canUpdate(const _Counter(), const _Counter()), isTrue);
      expect(
        Widget.canUpdate(
          const _Counter(key: ValueKey<String>('x')),
          const _Counter(key: ValueKey<String>('x')),
        ),
        isTrue,
      );
    });

    test('rejects different runtimeType', () {
      expect(
        Widget.canUpdate(const _Counter(), const _OtherStateful()),
        isFalse,
      );
    });

    test('rejects different key', () {
      expect(
        Widget.canUpdate(
          const _Counter(key: ValueKey<String>('x')),
          const _Counter(key: ValueKey<String>('y')),
        ),
        isFalse,
      );
    });

    test('rejects keyed vs unkeyed', () {
      expect(
        Widget.canUpdate(
          const _Counter(key: ValueKey<String>('x')),
          const _Counter(),
        ),
        isFalse,
      );
    });
  });

  group('Reconciliation preserves State', () {
    test('same runtimeType + no key: State identity preserved', () {
      final owner = BuildOwner();
      final root =
          owner.mountRoot(const _Counter(label: 'one')) as StatefulElement;
      final stateBefore = root.state as _CounterState;
      stateBefore.count = 5;

      owner.updateRoot(root, const _Counter(label: 'two'));

      final stateAfter = root.state as _CounterState;
      expect(
        identical(stateAfter, stateBefore),
        isTrue,
        reason: 'State<T> identity must survive a compatible widget update.',
      );
      expect(stateAfter.count, 5);
      expect(stateAfter.widget.label, 'two');
      expect(
        stateAfter.lastDidUpdateOldLabel,
        'one',
        reason: 'didUpdateWidget should see the previous widget.',
      );
    });

    test('same runtimeType + matching key: State identity preserved', () {
      final owner = BuildOwner();
      final root =
          owner.mountRoot(
                const _Counter(key: ValueKey<String>('k'), label: 'one'),
              )
              as StatefulElement;
      final stateBefore = root.state as _CounterState;
      stateBefore.count = 11;

      owner.updateRoot(
        root,
        const _Counter(key: ValueKey<String>('k'), label: 'two'),
      );

      final stateAfter = root.state as _CounterState;
      expect(identical(stateAfter, stateBefore), isTrue);
      expect(stateAfter.count, 11);
    });
  });

  group('Reconciliation replaces State', () {
    test('different key forces a remount and State is freshly created', () {
      final owner = BuildOwner();
      final root =
          owner.mountRoot(
                const _Counter(key: ValueKey<String>('a'), label: 'one'),
              )
              as StatefulElement;
      final stateBefore = root.state as _CounterState;
      stateBefore.count = 99;

      final newRoot =
          owner.updateRoot(
                root,
                const _Counter(key: ValueKey<String>('b'), label: 'two'),
              )
              as StatefulElement;
      final stateAfter = newRoot.state as _CounterState;

      expect(identical(newRoot, root), isFalse);
      expect(owner.root, same(newRoot));
      expect(identical(stateAfter, stateBefore), isFalse);
      expect(stateAfter.count, 0);
      expect(stateAfter.widget.label, 'two');
      expect(
        stateBefore.mounted,
        isFalse,
        reason: 'The incompatible old root must be permanently unmounted.',
      );
      expect(
        stateBefore.disposed,
        isTrue,
        reason: 'The incompatible old root State must be disposed.',
      );
    });

    test('updateRoot rejects a stale root element after replacement', () {
      final owner = BuildOwner();
      final root =
          owner.mountRoot(
                const _Counter(key: ValueKey<String>('a'), label: 'one'),
              )
              as StatefulElement;

      owner.updateRoot(root, const _Counter(key: ValueKey<String>('b')));

      expect(
        () => owner.updateRoot(root, const _Counter(label: 'stale')),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Child reconciliation through StatelessWidget', () {
    test('keyed child State survives parent rebuild', () {
      final owner = BuildOwner();
      final root =
          owner.mountRoot(const _Wrap(child: _Counter())) as StatelessElement;
      final counterElement = root.child as StatefulElement;
      final counterStateBefore = counterElement.state as _CounterState;
      counterStateBefore.count = 42;

      // The new Wrap widget instance carries an updated child. Reconciliation
      // should match Wrap (same type) and recurse into Counter (same type),
      // preserving the inner StatefulElement's State.
      owner.updateRoot(root, const _Wrap(child: _Counter(label: 'updated')));

      final counterElementAfter = root.child as StatefulElement;
      final counterStateAfter = counterElementAfter.state as _CounterState;
      expect(
        identical(counterStateAfter, counterStateBefore),
        isTrue,
        reason:
            'Compatible child widget must reuse the child element and State.',
      );
      expect(counterStateAfter.count, 42);
      expect(counterStateAfter.widget.label, 'updated');
    });
  });
}

class _Wrap extends StatelessWidget {
  const _Wrap({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
