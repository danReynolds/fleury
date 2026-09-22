import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

class _Build extends StatelessWidget {
  const _Build(this.builder);

  final Widget Function(BuildContext) builder;

  @override
  Widget build(BuildContext context) => builder(context);
}

class _CustomSource implements Listenable {
  final listeners = <VoidCallback>[];
  int count = 0;

  @override
  void addListener(VoidCallback listener) => listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => listeners.remove(listener);

  void increment() {
    count += 1;
    for (final listener in List<VoidCallback>.of(listeners)) {
      listener();
    }
  }
}

class _EqualSource extends _CustomSource {
  @override
  bool operator ==(Object other) => other is _EqualSource;

  @override
  int get hashCode => 0;
}

class _Capture extends StatefulWidget {
  const _Capture();

  @override
  State<_Capture> createState() => _CaptureState();
}

class _CaptureState extends State<_Capture> {
  int builds = 0;

  @override
  Widget build(BuildContext context) {
    builds += 1;
    return const Text('inner');
  }
}

_CaptureState _findCapture(Element root) {
  _CaptureState? found;
  void visit(Element element) {
    if (found != null) return;
    if (element is StatefulElement && element.state is _CaptureState) {
      found = element.state as _CaptureState;
      return;
    }
    element.visitChildren(visit);
  }

  visit(root);
  return found ?? (throw StateError('No _Capture below this element.'));
}

void main() {
  group('NotifierBuilder', () {
    test(
      'infers the notifier type and confines rebuilding to the consumer',
      () {
        final count = ValueNotifier(0);
        addTearDown(count.dispose);
        final owner = BuildOwner();
        var parentBuilds = 0;
        final seen = <int>[];
        final root = owner.mountRoot(
          _Build((context) {
            parentBuilds += 1;
            return NotifierBuilder(
              notifier: count,
              builder: (context, current) {
                expect(identical(current, count), isTrue);
                seen.add(current.value);
                return Text('${current.value}');
              },
            );
          }),
        );
        addTearDown(root.unmount);

        count.value = 1;
        owner.flushBuild();

        expect(seen, [0, 1]);
        expect(parentBuilds, 1);
      },
    );

    test('switches subscriptions when its notifier changes', () {
      final first = ValueNotifier(1);
      final second = ValueNotifier(10);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final owner = BuildOwner();
      final seen = <int>[];
      Widget consumer(ValueNotifier<int> notifier) => NotifierBuilder(
        notifier: notifier,
        builder: (context, current) {
          seen.add(current.value);
          return Text('${current.value}');
        },
      );
      final root = owner.mountRoot(consumer(first));
      addTearDown(root.unmount);

      owner.updateRoot(root, consumer(second));
      expect(first.hasListeners, isFalse);
      expect(second.hasListeners, isTrue);
      first.value = 2;
      owner.flushBuild();
      expect(seen, [1, 10]);

      second.value = 11;
      owner.flushBuild();
      expect(seen, [1, 10, 11]);
    });

    test('replaces an equal but distinct notifier by identity', () {
      final first = _EqualSource();
      final second = _EqualSource()..count = 10;
      final owner = BuildOwner();
      final seen = <int>[];
      Widget consumer(_EqualSource notifier) => NotifierBuilder(
        notifier: notifier,
        builder: (context, current) {
          seen.add(current.count);
          return Text('${current.count}');
        },
      );
      final root = owner.mountRoot(consumer(first));
      addTearDown(root.unmount);

      owner.updateRoot(root, consumer(second));
      expect(first.listeners, isEmpty);
      expect(second.listeners, hasLength(1));
      first.increment();
      owner.flushBuild();
      expect(seen, [0, 10]);

      second.increment();
      owner.flushBuild();
      expect(seen, [0, 10, 11]);
    });

    test('replaced animations stop rebuilding after reading their values', () {
      final first = Animation(0);
      final second = Animation(10);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final owner = BuildOwner();
      final seen = <int>[];
      Widget consumer(Animation<int> notifier) => NotifierBuilder(
        notifier: notifier,
        builder: (context, current) {
          seen.add(current.value);
          return Text('${current.value}');
        },
      );
      final root = owner.mountRoot(consumer(first));
      addTearDown(root.unmount);

      owner.updateRoot(root, consumer(second));
      first.snap(1);
      owner.flushBuild();
      expect(seen, [0, 10]);

      second.snap(11);
      owner.flushBuild();
      expect(seen, [0, 10, 11]);
    });

    test(
      'explicit animation reads replace earlier implicit reads in a build',
      () {
        final showAnimation = ValueNotifier(true);
        final animation = Animation(0);
        addTearDown(showAnimation.dispose);
        addTearDown(animation.dispose);
        final owner = BuildOwner();
        var builds = 0;
        final root = owner.mountRoot(
          NotifierBuilder(
            notifier: showAnimation,
            builder: (context, current) {
              builds += 1;
              if (!current.value) return const Text('off');
              // Read first: context.listen must transfer the implicit dependency
              // into its reconciled subscription even in this order.
              final value = animation.value;
              context.listen(animation);
              return Text('$value');
            },
          ),
        );
        addTearDown(root.unmount);

        showAnimation.value = false;
        owner.flushBuild();
        expect(builds, 2);
        animation.snap(1);
        owner.flushBuild();
        expect(builds, 2);
      },
    );

    test(
      'a later implicit animation read survives an old explicit subscription',
      () {
        final animation = Animation(0);
        addTearDown(animation.dispose);
        final owner = BuildOwner();
        final seen = <int>[];
        Widget consumer({required bool explicit}) => _Build((context) {
          if (explicit) context.listen(animation);
          seen.add(animation.value);
          return Text('${animation.value}');
        });
        final root = owner.mountRoot(consumer(explicit: true));
        addTearDown(root.unmount);

        owner.updateRoot(root, consumer(explicit: false));
        animation.snap(1);
        owner.flushBuild();

        expect(seen, [0, 0, 1]);
      },
    );

    test('supports custom Listenable models without owning their lifetime', () {
      final source = _CustomSource();
      final owner = BuildOwner();
      final seen = <int>[];
      final root = owner.mountRoot(
        NotifierBuilder(
          notifier: source,
          builder: (context, current) {
            seen.add(current.count);
            return Text('${current.count}');
          },
        ),
      );

      expect(source.listeners, hasLength(1));
      source.increment();
      owner.flushBuild();
      root.unmount();

      expect(source.listeners, isEmpty);
      source.increment();
      owner.flushBuild();
      expect(seen, [0, 1]);
      expect(source.count, 2);
    });

    test(
      'additional context reads subscribe the builder and follow each build',
      () {
        final primary = ValueNotifier(true);
        final secondary = ValueNotifier(0);
        addTearDown(primary.dispose);
        addTearDown(secondary.dispose);
        final owner = BuildOwner();
        var parentBuilds = 0;
        var consumerBuilds = 0;
        final root = owner.mountRoot(
          _Build((context) {
            parentBuilds += 1;
            return NotifierBuilder(
              notifier: primary,
              builder: (context, current) {
                consumerBuilds += 1;
                return Text(
                  current.value ? '${context.listen(secondary).value}' : 'off',
                );
              },
            );
          }),
        );
        addTearDown(root.unmount);

        secondary.value = 1;
        owner.flushBuild();
        expect(consumerBuilds, 2);
        expect(parentBuilds, 1);

        primary.value = false;
        owner.flushBuild();
        expect(secondary.hasListeners, isFalse);
        secondary.value = 2;
        owner.flushBuild();
        expect(consumerBuilds, 3);
        expect(parentBuilds, 1);
      },
    );

    test('an observer error is reported without stranding the builder', () {
      final notifier = ValueNotifier(0);
      addTearDown(notifier.dispose);
      final error = StateError('observer failed');
      final errors = <Object>[];
      var rendered = -1;
      notifier.addListener(() => throw error);
      final owner = BuildOwner();
      final root = owner.mountRoot(
        NotifierBuilder(
          notifier: notifier,
          builder: (context, current) {
            rendered = current.value;
            return Text('value=${current.value}');
          },
        ),
      );
      addTearDown(root.unmount);

      for (var value = 1; value <= 2; value++) {
        runZonedGuarded(() => notifier.value = value, (e, _) => errors.add(e));
        owner.flushBuild();
        expect(rendered, value);
      }
      expect(errors, [same(error), same(error)]);
    });

    test('a prebuilt subtree captured by the builder is reused', () {
      // The replacement for ListenableBuilder's `child:`: a widget built
      // outside the builder is the same instance on every rebuild, so
      // reconciliation keeps its element and State without rebuilding them.
      final notifier = ValueNotifier(0);
      addTearDown(notifier.dispose);
      const reused = _Capture();
      final owner = BuildOwner();
      final root = owner.mountRoot(
        NotifierBuilder(
          notifier: notifier,
          builder: (context, current) =>
              Column(children: [Text('${current.value}'), reused]),
        ),
      );
      addTearDown(root.unmount);
      final state = _findCapture(root);
      final builds = state.builds;

      notifier.value = 1;
      owner.flushBuild();
      notifier.value = 2;
      owner.flushBuild();

      expect(identical(_findCapture(root), state), isTrue);
      expect(state.builds, builds);
    });
  });
}
