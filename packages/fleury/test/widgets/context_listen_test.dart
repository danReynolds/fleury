import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

class _Build extends StatelessWidget {
  const _Build(this.builder, {super.key});
  final Widget Function(BuildContext) builder;

  @override
  Widget build(BuildContext context) => builder(context);
}

class _Source implements Listenable {
  final listeners = <VoidCallback>[];
  bool throwOnAdd = false;
  bool throwOnRemove = false;

  @override
  void addListener(VoidCallback listener) {
    listeners.add(listener);
    if (throwOnAdd) throw StateError('add failed');
  }

  @override
  void removeListener(VoidCallback listener) {
    if (throwOnRemove) throw StateError('remove failed');
    listeners.remove(listener);
  }

  void emit() {
    for (final callback in List<VoidCallback>.of(listeners)) {
      callback();
    }
  }
}

class _EqualSource extends _Source {
  @override
  bool operator ==(Object other) => other is _EqualSource;
  @override
  int get hashCode => 0;
}

void main() {
  test(
    'deduplicates reads and coalesces notifications until the next build',
    () {
      final source = _Source();
      final owner = BuildOwner();
      var builds = 0;
      final root = owner.mountRoot(
        _Build((context) {
          builds++;
          expect(identical(context.listen(source), source), isTrue);
          context.listen(source);
          return const Text('read');
        }),
      );
      addTearDown(root.unmount);
      expect(source.listeners, hasLength(1));
      source.emit();
      source.emit();
      expect(builds, 1);
      owner.flushBuild();
      expect(builds, 2);
      expect(source.listeners, hasLength(1));
    },
  );

  test('drops conditional dependencies and preserves remaining ones', () {
    final first = _Source();
    final second = _Source();
    final owner = BuildOwner();
    var useFirst = true;
    var builds = 0;
    final root = owner.mountRoot(
      _Build((context) {
        builds++;
        if (useFirst) context.listen(first);
        context.listen(second);
        return const Text('read');
      }),
    );
    addTearDown(root.unmount);
    useFirst = false;
    second.emit();
    owner.flushBuild();
    expect(first.listeners, isEmpty);
    expect(second.listeners, hasLength(1));
    first.emit();
    owner.flushBuild();
    expect(builds, 2);
    second.emit();
    owner.flushBuild();
    expect(builds, 3);
  });

  test('a repeated read cannot keep a dropped source subscribed', () {
    // A build that reads one source twice and drops another must still
    // detach the dropped one: repeats are not distinct reads.
    final kept = _Source();
    final dropped = _Source();
    final owner = BuildOwner();
    var both = true;
    final root = owner.mountRoot(
      _Build((context) {
        context.listen(kept);
        context.listen(kept);
        if (both) context.listen(dropped);
        return const Text('read');
      }),
    );
    addTearDown(root.unmount);
    both = false;
    kept.emit();
    owner.flushBuild();
    expect(kept.listeners, hasLength(1));
    expect(dropped.listeners, isEmpty);
  });

  test('an Animation.value read follows the same per-build rule', () {
    // Reading an animation in build subscribes like context.listen: once a
    // build stops reading it, the animation stops rebuilding the widget.
    final animation = Animation(1);
    final owner = BuildOwner();
    var read = true;
    var builds = 0;
    Widget consumer() => _Build((context) {
      builds++;
      if (read) animation.value;
      return const Text('read');
    });
    final root = owner.mountRoot(consumer());
    addTearDown(() {
      root.unmount();
      animation.dispose();
    });
    animation.snap(2);
    owner.flushBuild();
    expect(builds, 2);

    read = false;
    owner.updateRoot(root, consumer());
    expect(builds, 3);
    animation.snap(3);
    owner.flushBuild();
    expect(builds, 3, reason: 'the build that stopped reading unsubscribed');
    expect(animation.hasListeners, isFalse);
  });

  test(
    'distinct equal sources have separate identities and replace correctly',
    () {
      final first = _EqualSource();
      final second = _EqualSource();
      final owner = BuildOwner();
      Widget consumer(List<_Source> sources) => _Build((context) {
        for (final source in sources) {
          context.listen(source);
        }
        return const Text('read');
      });
      final root = owner.mountRoot(consumer([first, second]));
      addTearDown(root.unmount);
      expect(first.listeners, hasLength(1));
      expect(second.listeners, hasLength(1));
      owner.updateRoot(root, consumer([second]));
      expect(first.listeners, isEmpty);
      expect(second.listeners, hasLength(1));
    },
  );

  test('rejects event-time reads and another widget\'s context', () {
    final source = _Source();
    final owner = BuildOwner();
    late BuildContext parentContext;
    final root = owner.mountRoot(
      _Build((context) {
        parentContext = context;
        return _Build((childContext) {
          expect(() => parentContext.listen(source), throwsStateError);
          childContext.listen(source);
          return const Text('child');
        });
      }),
    );
    expect(() => parentContext.listen(source), throwsStateError);
    root.unmount();
    expect(source.listeners, isEmpty);
    expect(() => parentContext.listen(source), throwsStateError);
  });

  test(
    'failed builds retain current reads and drop stale reads for recovery',
    () {
      final first = _Source();
      final second = _Source();
      var fail = false;
      var builds = 0;
      final error = StateError('build failed');
      final caught = <Object>[];
      final owner = BuildOwner()
        ..errorBuilder = ((error, stack) => const Text('error'))
        ..onBuildError = ((error, stack) => caught.add(error));
      final root = owner.mountRoot(
        _Build((context) {
          builds++;
          if (fail) {
            context.listen(second);
            throw error;
          }
          context.listen(first);
          return const Text('okay');
        }),
      );
      addTearDown(root.unmount);
      fail = true;
      first.emit();
      owner.flushBuild();
      expect(caught, [same(error)]);
      expect(first.listeners, isEmpty);
      expect(second.listeners, hasLength(1));
      fail = false;
      second.emit();
      owner.flushBuild();
      expect(builds, 3);
      expect(first.listeners, hasLength(1));
      expect(second.listeners, isEmpty);
      expect(Element.current, isNull);
    },
  );

  test(
    'failed listener attachment cleans up a partially registered callback',
    () {
      final source = _Source()..throwOnAdd = true;
      final owner = BuildOwner()
        ..errorBuilder = (error, stack) => const Text('error');
      final root = owner.mountRoot(
        _Build((context) {
          context.listen(source);
          return const Text('unreachable');
        }),
      );
      addTearDown(root.unmount);
      expect(source.listeners, isEmpty);
      expect(Element.current, isNull);
    },
  );

  test('failed removal cannot retain or invalidate a detached consumer', () {
    final source = _Source();
    final owner = BuildOwner();
    final root = owner.mountRoot(
      _Build((context) {
        context.listen(source);
        return const Text('read');
      }),
    );
    source.throwOnRemove = true;
    expect(root.unmount, throwsStateError);
    expect(root.mounted, isFalse);
    source.emit();
    expect(root.dirty, isFalse);
  });

  testWidgets('identical globally keyed consumers resubscribe after a move', (
    tester,
  ) {
    final source = _Source();
    var builds = 0;
    final child = _Build((context) {
      context.listen(source);
      builds++;
      return const Text('read');
    }, key: GlobalKey());
    Widget tree(bool right) => Row(
      children: [
        SizedBox(width: 5, child: right ? const Text('left') : child),
        SizedBox(width: 5, child: right ? child : const Text('right')),
      ],
    );
    tester.pumpWidget(tree(false));
    expect(source.listeners, hasLength(1));
    tester.pumpWidget(tree(true));
    expect(source.listeners, hasLength(1));
    final before = builds;
    source.emit();
    tester.pump();
    expect(builds, before + 1);
    tester.pumpWidget(const Text('gone'));
    expect(source.listeners, isEmpty);
  });

  testWidgets(
    'layout-time readers reconcile subscriptions at unchanged constraints',
    (tester) {
      final count = ValueNotifier(0);
      addTearDown(count.dispose);
      var listening = true;
      final widget = LayoutBuilder(
        builder: (context, constraints) {
          return Text(listening ? '${context.listen(count).value}' : 'done');
        },
      );
      tester.pumpWidget(widget);
      expect(tester.renderToString(size: const CellSize(8, 1)).trim(), '0');
      count.value = 1;
      tester.pump();
      expect(tester.renderToString(size: const CellSize(8, 1)).trim(), '1');
      listening = false;
      count.value = 2;
      tester.pump();
      expect(tester.renderToString(size: const CellSize(8, 1)).trim(), 'done');
      expect(count.hasListeners, isFalse);
    },
  );
}
