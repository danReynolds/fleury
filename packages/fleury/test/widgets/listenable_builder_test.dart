// ListenableBuilder tests. Verifies the listener contract, child-
// subtree reuse, and animation swap on didUpdateWidget.

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

T _findState<T extends State>(Element root) {
  T? found;
  void visit(Element e) {
    if (found != null) return;
    if (e is StatefulElement && e.state is T) {
      found = e.state as T;
      return;
    }
    e.visitChildren(visit);
  }

  visit(root);
  if (found == null) throw StateError('No $T below this element.');
  return found!;
}

class _CountingNotifier extends ChangeNotifier {
  void poke() => notifyListeners();
}

class _Capture extends StatefulWidget {
  const _Capture();
  @override
  State<_Capture> createState() => CaptureState();
}

class CaptureState extends State<_Capture> {
  int buildCount = 0;
  @override
  Widget build(BuildContext context) {
    buildCount += 1;
    return const Text('inner');
  }
}

void main() {
  group('ListenableBuilder lifecycle', () {
    test('rebuilds on listener notify', () {
      final notifier = _CountingNotifier();
      var builds = 0;
      final owner = BuildOwner();
      owner.mountRoot(
        ListenableBuilder(
          listenable: notifier,
          builder: (ctx, child) {
            builds += 1;
            return const Text('x');
          },
        ),
      );
      expect(builds, 1);
      notifier.poke();
      owner.flushBuild();
      expect(builds, 2);
      notifier.poke();
      owner.flushBuild();
      expect(builds, 3);
    });

    test('child subtree is preserved across rebuilds', () {
      final notifier = _CountingNotifier();
      final owner = BuildOwner();
      final root = owner.mountRoot(
        ListenableBuilder(
          listenable: notifier,
          child: const _Capture(),
          builder: (ctx, child) => child!,
        ),
      );
      final initialState = _findState<CaptureState>(root);
      final firstBuilds = initialState.buildCount;

      notifier.poke();
      owner.flushBuild();
      notifier.poke();
      owner.flushBuild();

      final stillSame = _findState<CaptureState>(root);
      expect(
        identical(initialState, stillSame),
        isTrue,
        reason: 'child State identity preserved across rebuilds',
      );
      expect(
        stillSame.buildCount,
        firstBuilds,
        reason: 'child not rebuilt — its widget didn\'t change',
      );
    });

    test('didUpdateWidget swaps the listener subscription', () {
      final a = _CountingNotifier();
      final b = _CountingNotifier();
      var builds = 0;
      final owner = BuildOwner();
      final root = owner.mountRoot(
        ListenableBuilder(
          listenable: a,
          builder: (ctx, child) {
            builds += 1;
            return const Text('x');
          },
        ),
      );
      expect(builds, 1);

      // Swap to a different animation.
      owner.updateRoot(
        root,
        ListenableBuilder(
          listenable: b,
          builder: (ctx, child) {
            builds += 1;
            return const Text('x');
          },
        ),
      );
      // updateRoot triggers a rebuild via update->rebuild(force: true).
      final afterSwap = builds;

      // Old animation should no longer drive rebuilds.
      a.poke();
      owner.flushBuild();
      expect(builds, afterSwap, reason: 'old animation should be unsubscribed');

      // New animation drives rebuilds.
      b.poke();
      owner.flushBuild();
      expect(builds, afterSwap + 1);
    });

    test('unsubscribes on dispose', () {
      final notifier = _CountingNotifier();
      var builds = 0;
      final owner = BuildOwner();
      final root = owner.mountRoot(
        ListenableBuilder(
          listenable: notifier,
          builder: (ctx, child) {
            builds += 1;
            return const Text('x');
          },
        ),
      );
      root.unmount();
      final after = builds;
      // notifier.poke would normally drive a rebuild; after unmount
      // the listener should have been removed.
      notifier.poke();
      expect(builds, after);
    });
  });
}
