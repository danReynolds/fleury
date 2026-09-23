import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

class _Build extends StatelessWidget {
  const _Build(this.builder, {super.key});

  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) => builder(context);
}

class _StickyReader extends StatefulWidget {
  const _StickyReader({super.key, required this.watch, required this.onBuild});

  final bool watch;
  final VoidCallback onBuild;

  @override
  State<_StickyReader> createState() => _StickyReaderState();
}

class _StickyReaderState extends State<_StickyReader> {
  @override
  void initState() {
    super.initState();
    context.scope<_Model>();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.watch) context.scope<_Model>();
    widget.onBuild();
    return const EmptyBox();
  }
}

class _DependencyReader extends StatefulWidget {
  const _DependencyReader({super.key});

  @override
  State<_DependencyReader> createState() => _DependencyReaderState();
}

class _DependencyReaderState extends State<_DependencyReader> {
  int dependencyChanges = 0;
  int seen = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    dependencyChanges++;
    seen = context.scope<_Model>().count;
  }

  void poke() => setState(() {});

  @override
  Widget build(BuildContext context) => const EmptyBox();
}

class _Label {
  const _Label(this.text);
  final String text;

  @override
  bool operator ==(Object other) => other is _Label && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

// A render-object widget reading its scope where render-object widgets
// configure themselves.
class _LabelLeaf extends LeafRenderObjectWidget {
  const _LabelLeaf();

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLabel()..text = context.scope<_Label>().text;

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderLabel).text = context.scope<_Label>().text;
  }
}

class _RenderLabel extends RenderObject {
  static String last = '';
  String _text = '';
  set text(String value) {
    _text = value;
    last = value;
  }

  String get text => _text;

  @override
  CellSize performLayout(CellConstraints constraints) =>
      constraints.constrain(const CellSize(1, 1));

  @override
  void performPaint(CellBuffer buffer, CellOffset offset) {}
}

class _ListenInDependencies extends StatefulWidget {
  const _ListenInDependencies(this.model);
  final _Model model;

  @override
  State<_ListenInDependencies> createState() => _ListenInDependenciesState();
}

class _ListenInDependenciesState extends State<_ListenInDependencies> {
  Object? error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      context.listen(widget.model);
    } catch (e) {
      error = e;
    }
  }

  @override
  Widget build(BuildContext context) => const EmptyBox();
}

class _FilteredAnimationScope extends Scope<Animation<int>> {
  const _FilteredAnimationScope(super.value, {required super.child});

  @override
  bool updateShouldNotify(covariant _FilteredAnimationScope oldWidget) => false;
}

class _Model extends Notifier {
  _Model([this.count = 0]);

  int count;
  int disposals = 0;

  void increment() {
    count++;
    notify();
  }

  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}

class _EqualModel extends _Model {
  _EqualModel(super.count);

  @override
  bool operator ==(Object other) => other is _EqualModel;

  @override
  int get hashCode => 1;
}

class _Snapshot {
  const _Snapshot(this.name);

  final String name;

  @override
  bool operator ==(Object other) => other is _Snapshot && name == other.name;

  @override
  int get hashCode => name.hashCode;
}

class _SpecialSnapshot extends _Snapshot {
  const _SpecialSnapshot(super.name);
}

class _CustomSource implements Listenable {
  final callbacks = <VoidCallback>[];

  @override
  void addListener(VoidCallback listener) => callbacks.add(listener);

  @override
  void removeListener(VoidCallback listener) => callbacks.remove(listener);

  void fire() {
    for (final callback in callbacks.toList()) {
      callback();
    }
  }
}

class _FailingSource extends _CustomSource {
  @override
  void addListener(VoidCallback listener) => throw StateError('attach failed');
}

class _FaultySource extends _CustomSource {
  _FaultySource({this.failAttach = false, this.failDetach = false});

  final bool failAttach;
  final bool failDetach;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (failAttach) throw StateError('attach failed after registration');
  }

  @override
  void removeListener(VoidCallback listener) {
    if (failDetach) throw StateError('detach failed');
    super.removeListener(listener);
  }
}

void main() {
  group('Scope snapshots', () {
    test('reads the nearest scope for each declared type', () {
      final owner = BuildOwner();
      final seen = <Object>[];
      final root = owner.mountRoot(
        Scope<String>(
          'outer',
          child: Scope<int>(
            7,
            child: Scope<String>(
              'inner',
              child: _Build((context) {
                seen.add(context.scope<String>());
                seen.add(context.scope<int>());
                return const EmptyBox();
              }),
            ),
          ),
        ),
      );

      expect(seen, ['inner', 7]);
      root.unmount();
    });

    test('a subtype scope does not shadow a declared supertype scope', () {
      final owner = BuildOwner();
      final seen = <String>[];
      final root = owner.mountRoot(
        Scope<_Snapshot>(
          const _Snapshot('base'),
          child: Scope<_SpecialSnapshot>(
            const _SpecialSnapshot('special'),
            child: _Build((context) {
              seen.add(context.scope<_Snapshot>().name);
              seen.add(context.scope<_SpecialSnapshot>().name);
              return const EmptyBox();
            }),
          ),
        ),
      );

      expect(seen, ['base', 'special']);
      root.unmount();
    });

    test('reports the missing scope and requested type', () {
      final owner = BuildOwner();
      expect(
        () => owner.mountRoot(
          _Build((context) {
            context.scope<_Model>();
            return const EmptyBox();
          }),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('No Scope<_Model>'),
          ),
        ),
      );
    });

    test('only unequal snapshots invalidate a retained consumer', () {
      final owner = BuildOwner();
      final seen = <String>[];
      final reader = _Build((context) {
        seen.add(context.scope<_Snapshot>().name);
        return const EmptyBox();
      });
      final root = owner.mountRoot(Scope(_Snapshot('first'), child: reader));

      owner.updateRoot(root, Scope(_Snapshot('first'), child: reader));
      expect(seen, ['first']);

      owner.updateRoot(root, Scope(_Snapshot('second'), child: reader));
      expect(seen, ['first', 'second']);
      root.unmount();
    });

    test('requires its own active build context', () {
      final owner = BuildOwner();
      late BuildContext captured;
      final root = owner.mountRoot(
        Scope<int>(
          1,
          child: _Build((context) {
            captured = context;
            context.scope<int>();
            return const EmptyBox();
          }),
        ),
      );

      expect(() => captured.scope<int>(), throwsStateError);
      root.unmount();
    });
  });

  group('Scope notifications', () {
    test('ScopeBuilder rebuilds only its own subtree on notifications', () {
      final owner = BuildOwner();
      final model = _Model();
      final seen = <int>[];
      var parentBuilds = 0;
      final root = owner.mountRoot(
        Scope(
          model,
          child: _Build((context) {
            parentBuilds++;
            return ScopeBuilder<_Model>(
              builder: (context, model) {
                seen.add(model.count);
                return const EmptyBox();
              },
            );
          }),
        ),
      );

      model.increment();
      model.increment();
      owner.flushBuild();

      expect(seen, [0, 2]);
      expect(parentBuilds, 1);
      root.unmount();
      expect(model.hasListeners, isFalse);
      expect(model.disposals, 0);
    });

    test('distinct equal notifiers replace identity and subscriptions', () {
      final owner = BuildOwner();
      final first = _EqualModel(1);
      final second = _EqualModel(2);
      final seen = <_EqualModel>[];
      final reader = _Build((context) {
        seen.add(context.scope<_EqualModel>());
        return const EmptyBox();
      });
      final root = owner.mountRoot(Scope(first, child: reader));

      owner.updateRoot(root, Scope(second, child: reader));
      expect(seen.length, 2);
      expect(identical(seen.last, second), isTrue);
      expect(first.hasListeners, isFalse);
      expect(second.hasListeners, isTrue);

      first.increment();
      owner.flushBuild();
      expect(seen.length, 2);
      second.increment();
      owner.flushBuild();
      expect(seen.length, 3);
      root.unmount();
    });

    test('supports custom Listenable sources without owning them', () {
      final owner = BuildOwner();
      final source = _CustomSource();
      var builds = 0;
      final root = owner.mountRoot(
        Scope(
          source,
          child: ScopeBuilder<_CustomSource>(
            builder: (context, value) {
              expect(identical(value, source), isTrue);
              builds++;
              return const EmptyBox();
            },
          ),
        ),
      );

      source.fire();
      owner.flushBuild();
      expect(builds, 2);
      root.unmount();
      expect(source.callbacks, isEmpty);
    });

    test('a read stays subscribed after a later build stops reading', () {
      // A subscription belongs to the element until it leaves the tree, like
      // any Flutter-style dependency; a build that stops reading pays at most
      // an extra rebuild, never a missed one.
      final owner = BuildOwner();
      final model = _Model();
      var builds = 0;
      Widget reader(bool watch) => _Build((context) {
        if (watch) context.scope<_Model>();
        builds++;
        return const EmptyBox();
      });
      final root = owner.mountRoot(Scope(model, child: reader(true)));
      owner.updateRoot(root, Scope(model, child: reader(false)));
      final afterUpdate = builds;

      model.increment();
      owner.flushBuild();

      expect(builds, afterUpdate + 1);
      root.unmount();
      expect(model.hasListeners, isFalse);
    });

    test('a read in didChangeDependencies survives a plain setState', () {
      // didChangeDependencies is where a State reacts to its dependencies. A
      // plain setState does not call it, so a read made there must not be
      // dropped by the rebuild that follows.
      final owner = BuildOwner();
      final model = _Model();
      final key = GlobalKey<_DependencyReaderState>();
      final root = owner.mountRoot(
        Scope(model, child: _DependencyReader(key: key)),
      );
      final state = key.currentState!;
      model.increment();
      owner.flushBuild();
      final beforeSetState = state.dependencyChanges;

      state.poke();
      owner.flushBuild();
      model.increment();
      owner.flushBuild();

      expect(state.dependencyChanges, beforeSetState + 1);
      expect(state.seen, 2);
      root.unmount();
      expect(model.hasListeners, isFalse);
    });

    test('an initState read follows the element across a GlobalKey move', () {
      // initState never runs again, so the move must carry the subscription
      // to the scope of the same type at the element's new position.
      final owner = BuildOwner();
      final left = _Model();
      final right = _Model();
      final key = GlobalKey();
      var builds = 0;
      Widget tree(bool onLeft) {
        Widget slot(bool here) => here
            ? _StickyReader(key: key, watch: false, onBuild: () => builds++)
            : const EmptyBox();
        return Column(
          children: [
            Scope(left, child: slot(onLeft)),
            Scope(right, child: slot(!onLeft)),
          ],
        );
      }

      final root = owner.mountRoot(tree(true));
      owner.updateRoot(root, tree(false));
      owner.flushBuild();
      final afterMove = builds;

      right.increment();
      owner.flushBuild();
      expect(builds, afterMove + 1, reason: 'subscribed at the new position');

      left.increment();
      owner.flushBuild();
      expect(builds, afterMove + 1, reason: 'no longer bound to the old one');

      root.unmount();
      expect(left.hasListeners, isFalse);
      expect(right.hasListeners, isFalse);
    });

    test('a global-keyed consumer follows its new nearest scope', () {
      final owner = BuildOwner();
      final first = _Model(1);
      final second = _Model(10);
      final seen = <int>[];
      final reader = _Build((context) {
        seen.add(context.scope<_Model>().count);
        return const EmptyBox();
      }, key: GlobalKey());
      Widget tree(bool move) => Row(
        children: [
          Scope(first, child: move ? const EmptyBox() : reader),
          Scope(second, child: move ? reader : const EmptyBox()),
        ],
      );
      final root = owner.mountRoot(tree(false));

      owner.updateRoot(root, tree(true));
      expect(seen, [1, 10]);
      first.increment();
      owner.flushBuild();
      expect(seen, [1, 10]);
      second.increment();
      owner.flushBuild();
      expect(seen, [1, 10, 11]);
      root.unmount();
    });

    test('replacement is attached before a descendant notifies in build', () {
      final owner = BuildOwner();
      final first = _Model(1);
      final second = _Model(10);
      final seen = <int>[];
      var sent = false;
      final reader = _Build((context) {
        final model = context.scope<_Model>();
        seen.add(model.count);
        if (identical(model, second) && !sent) {
          sent = true;
          model.increment();
        }
        return const EmptyBox();
      });
      final root = owner.mountRoot(Scope(first, child: reader));

      owner.updateRoot(root, Scope(second, child: reader));

      expect(seen, [1, 10, 11]);
      root.unmount();
    });

    test('a failed descendant rebuild keeps the replacement subscribed', () {
      final owner = BuildOwner();
      final first = _Model();
      final second = _Model();
      var fail = false;
      var builds = 0;
      final reader = _Build((context) {
        context.scope<_Model>();
        builds++;
        if (fail) throw StateError('child failed');
        return const EmptyBox();
      });
      final root = owner.mountRoot(Scope(first, child: reader));

      fail = true;
      expect(
        () => owner.updateRoot(root, Scope(second, child: reader)),
        throwsStateError,
      );
      expect(first.hasListeners, isFalse);
      expect(second.hasListeners, isTrue);

      fail = false;
      second.increment();
      owner.flushBuild();
      expect(builds, 3);
      root.unmount();
    });

    test('failed replacement attachment preserves the existing value', () {
      final owner = BuildOwner();
      final first = _Model(1);
      final rejected = _Model(10)..dispose();
      final seen = <int>[];
      final reader = _Build((context) {
        seen.add(context.scope<_Model>().count);
        return const EmptyBox();
      });
      final root = owner.mountRoot(Scope(first, child: reader));

      expect(
        () => owner.updateRoot(root, Scope(rejected, child: reader)),
        throwsStateError,
      );
      first.increment();
      owner.flushBuild();

      expect(seen, [1, 2]);
      root.unmount();
      expect(first.hasListeners, isFalse);
    });

    for (final failDetach in [false, true]) {
      test(
        'failed attachment deactivates the rejected callback ($failDetach)',
        () {
          final owner = BuildOwner();
          final first = _CustomSource();
          final rejected = _FaultySource(
            failAttach: true,
            failDetach: failDetach,
          );
          var builds = 0;
          final reader = _Build((context) {
            expect(identical(context.scope<_CustomSource>(), first), isTrue);
            builds++;
            return const EmptyBox();
          });
          final root = owner.mountRoot(
            Scope<_CustomSource>(first, child: reader),
          );

          expect(
            () => owner.updateRoot(
              root,
              Scope<_CustomSource>(rejected, child: reader),
            ),
            throwsA(
              predicate<Object>(
                (error) => error.toString().contains('attach failed'),
                'preserves the attach error alongside any cleanup error',
              ),
            ),
          );
          expect(rejected.callbacks.length, failDetach ? 1 : 0);

          rejected.fire();
          owner.flushBuild();
          expect(builds, 1);
          first.fire();
          owner.flushBuild();
          expect(builds, 2);
          root.unmount();
          expect(rejected.fire, returnsNormally);
        },
      );
    }

    test('failed removal leaves the old callback inert after replacement', () {
      final owner = BuildOwner();
      final first = _FaultySource(failDetach: true);
      final second = _CustomSource();
      final seen = <_CustomSource>[];
      final reader = _Build((context) {
        seen.add(context.scope<_CustomSource>());
        return const EmptyBox();
      });
      final root = owner.mountRoot(Scope<_CustomSource>(first, child: reader));

      expect(
        () =>
            owner.updateRoot(root, Scope<_CustomSource>(second, child: reader)),
        throwsStateError,
      );
      owner.flushBuild();
      expect(seen, [first, second]);
      first.fire();
      owner.flushBuild();
      expect(seen, [first, second]);
      second.fire();
      owner.flushBuild();
      expect(seen, [first, second, second]);
      root.unmount();
      expect(first.fire, returnsNormally);
    });
  });

  group('Scope animation dependencies', () {
    test('a filtered replacement cannot notify through its old animation', () {
      final owner = BuildOwner();
      final first = Animation(1, debugLabel: 'first');
      final second = Animation(2, debugLabel: 'second');
      final seen = <String?>[];
      final reader = _Build((context) {
        seen.add(context.scope<Animation<int>>().debugLabel);
        return const EmptyBox();
      });
      final root = owner.mountRoot(
        _FilteredAnimationScope(first, child: reader),
      );
      owner.updateRoot(root, _FilteredAnimationScope(second, child: reader));
      expect(seen, ['first']);
      expect(first.hasListeners, isFalse);
      first.snap(3);
      owner.flushBuild();
      expect(seen, ['first']);
      second.snap(4);
      owner.flushBuild();
      expect(seen, ['first', 'second']);
      root.unmount();
      first.dispose();
      second.dispose();
    });

    test('explicit listening survives a filtered scope replacement', () {
      final owner = BuildOwner();
      final first = Animation(1);
      final second = Animation(2);
      var builds = 0;
      final reader = _Build((context) {
        context.listen(first);
        context.scope<Animation<int>>();
        builds++;
        return const EmptyBox();
      });
      final root = owner.mountRoot(
        _FilteredAnimationScope(first, child: reader),
      );
      owner.updateRoot(root, _FilteredAnimationScope(second, child: reader));
      expect(builds, 1);
      first.snap(3);
      owner.flushBuild();
      expect(builds, 2);
      root.unmount();
      expect(first.hasListeners, isFalse);
      expect(second.hasListeners, isFalse);
      first.dispose();
      second.dispose();
    });

    test('an implicit animation read takes over after a scoped read ends', () {
      final owner = BuildOwner();
      final animation = Animation(1);
      final seen = <int>[];
      Widget reader(bool scoped) => _Build((context) {
        if (scoped) context.scope<Animation<int>>();
        seen.add(animation.value);
        return const EmptyBox();
      });
      final root = owner.mountRoot(Scope(animation, child: reader(true)));
      owner.updateRoot(root, Scope(animation, child: reader(false)));
      animation.snap(2);
      owner.flushBuild();
      expect(seen, [1, 1, 2]);
      root.unmount();
      expect(animation.hasListeners, isFalse);
      animation.dispose();
    });

    for (final implicitFirst in [false, true]) {
      test(
        'replacement drops the old animation (implicit first: $implicitFirst)',
        () {
          final owner = BuildOwner();
          final first = Animation(1);
          final second = Animation(10);
          var current = first;
          final seen = <int>[];
          final reader = _Build((context) {
            if (implicitFirst) current.value;
            seen.add(context.scope<Animation<int>>().value);
            return const EmptyBox();
          });
          final root = owner.mountRoot(Scope(first, child: reader));

          current = second;
          owner.updateRoot(root, Scope(second, child: reader));
          expect(seen, [1, 10]);

          first.snap(2);
          owner.flushBuild();
          expect(seen, [
            1,
            10,
          ], reason: 'the replaced animation is no longer read');
          second.snap(11);
          owner.flushBuild();
          expect(seen, [1, 10, 11]);

          root.unmount();
          expect(first.hasListeners, isFalse);
          expect(second.hasListeners, isFalse);
          first.dispose();
          second.dispose();
        },
      );

      test('a conditional read keeps one subscription (implicit first: '
          '$implicitFirst)', () {
        final owner = BuildOwner();
        final animation = Animation(1);
        final seen = <int>[];
        Widget reader(bool watch) => _Build((context) {
          if (watch) {
            if (implicitFirst) animation.value;
            seen.add(context.scope<Animation<int>>().value);
          } else {
            seen.add(-1);
          }
          return const EmptyBox();
        });
        final root = owner.mountRoot(Scope(animation, child: reader(true)));

        owner.updateRoot(root, Scope(animation, child: reader(false)));
        expect(seen, [1, -1]);
        animation.snap(2);
        owner.flushBuild();
        expect(seen, [
          1,
          -1,
          -1,
        ], reason: 'one rebuild through the scope; the implicit read retired');

        root.unmount();
        expect(animation.hasListeners, isFalse);
        animation.dispose();
      });
    }
  });

  group('Scope.create ownership', () {
    test('creates once and retains the original disposer across rebuilds', () {
      final owner = BuildOwner();
      final model = _Model();
      var creations = 0;
      var originalDisposals = 0;
      var replacementDisposals = 0;
      final root = owner.mountRoot(
        Scope<_Model>.create(
          () {
            creations++;
            return model;
          },
          dispose: (value) {
            expect(identical(value, model), isTrue);
            originalDisposals++;
          },
          child: const EmptyBox(),
        ),
      );

      owner.updateRoot(
        root,
        Scope<_Model>.create(
          () {
            creations++;
            return _Model();
          },
          dispose: (_) => replacementDisposals++,
          child: const EmptyBox(),
        ),
      );
      root.unmount();

      expect(creations, 1);
      expect(originalDisposals, 1);
      expect(replacementDisposals, 0);
      expect(
        model.disposals,
        0,
        reason: 'explicit cleanup replaces the default',
      );
      expect(model.hasListeners, isFalse);
    });

    test('automatically disposes created Notifiers when remounted', () {
      final owner = BuildOwner();
      final created = <_Model>[];
      Widget scope(String key) => Scope<_Model>.create(
        () {
          final model = _Model();
          created.add(model);
          return model;
        },
        key: ValueKey(key),
        child: const EmptyBox(),
      );
      var root = owner.mountRoot(scope('first'));

      root = owner.updateRoot(root, scope('second'));
      expect(created.length, 2);
      expect(created.first.disposals, 1);
      expect(created.last.disposals, 0);
      root.unmount();
      expect(created.last.disposals, 1);
    });

    test('supports explicit cleanup of other created resources', () {
      final owner = BuildOwner();
      final source = _CustomSource();
      var cleaned = false;
      final root = owner.mountRoot(
        Scope<_CustomSource>.create(
          () => source,
          dispose: (value) {
            expect(identical(value, source), isTrue);
            expect(value.callbacks, isEmpty);
            cleaned = true;
          },
          child: const EmptyBox(),
        ),
      );

      root.unmount();
      expect(cleaned, isTrue);
    });

    test('a throwing factory preserves its original error', () {
      final owner = BuildOwner();
      final failure = StateError('factory failed');
      expect(
        () => owner.mountRoot(
          Scope<_Model>.create(() => throw failure, child: const EmptyBox()),
        ),
        throwsA(same(failure)),
      );
    });

    test('failed first child build still disposes the created model', () {
      final owner = BuildOwner();
      final model = _Model();

      expect(
        () => owner.mountRoot(
          Scope<_Model>.create(
            () => model,
            child: _Build((context) {
              context.scope<_Model>();
              throw StateError('child failed');
            }),
          ),
        ),
        throwsStateError,
      );

      expect(model.disposals, 1);
      expect(model.hasListeners, isFalse);
    });

    test('failed source attachment still cleans up the created resource', () {
      final owner = BuildOwner();
      var cleaned = false;

      expect(
        () => owner.mountRoot(
          Scope<_FailingSource>.create(
            _FailingSource.new,
            dispose: (_) => cleaned = true,
            child: const EmptyBox(),
          ),
        ),
        throwsStateError,
      );
      expect(cleaned, isTrue);
    });

    test('throwing custom cleanup does not retain source listeners', () {
      final owner = BuildOwner();
      final model = _Model();
      final root = owner.mountRoot(
        Scope<_Model>.create(
          () => model,
          dispose: (_) => throw StateError('cleanup failed'),
          child: const EmptyBox(),
        ),
      );

      expect(root.unmount, throwsStateError);
      expect(model.hasListeners, isFalse);
      expect(root.mounted, isFalse);
    });

    test('failed source removal still cleans up the owned resource', () {
      final owner = BuildOwner();
      final source = _FaultySource(failDetach: true);
      var cleaned = false;
      final root = owner.mountRoot(
        Scope<_FaultySource>.create(
          () => source,
          dispose: (_) => cleaned = true,
          child: const EmptyBox(),
        ),
      );

      expect(root.unmount, throwsStateError);
      expect(cleaned, isTrue);
      expect(root.mounted, isFalse);
      expect(source.fire, returnsNormally);
    });

    for (final initiallyOwned in [false, true]) {
      test('ownership can change at one position ($initiallyOwned)', () {
        final owner = BuildOwner();
        final original = _Model();
        final replacement = _Model();
        var replacementCreations = 0;
        final root = owner.mountRoot(
          initiallyOwned
              ? Scope<_Model>.create(() => original, child: const EmptyBox())
              : Scope(original, child: const EmptyBox()),
        );
        owner.updateRoot(
          root,
          initiallyOwned
              ? Scope(replacement, child: const EmptyBox())
              : Scope<_Model>.create(() {
                  replacementCreations++;
                  return replacement;
                }, child: const EmptyBox()),
        );
        expect(original.disposals, initiallyOwned ? 1 : 0);
        expect(original.hasListeners, isFalse);
        expect(replacement.hasListeners, isTrue);
        expect(replacementCreations, initiallyOwned ? 0 : 1);
        root.unmount();
        expect(replacement.disposals, initiallyOwned ? 0 : 1);
      });
    }
  });

  group('Where scopes can be read', () {
    test('a handler read throws and leaves no subscription', () {
      final owner = BuildOwner();
      final model = _Model();
      late BuildContext captured;
      var builds = 0;
      final root = owner.mountRoot(
        Scope(
          model,
          child: _Build((context) {
            captured = context;
            builds++;
            return const EmptyBox();
          }),
        ),
      );

      expect(
        () => captured.scope<_Model>(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('keep it for event handlers'),
          ),
        ),
      );
      model.increment();
      owner.flushBuild();
      expect(builds, 1);
      root.unmount();
    });

    test('context.listen in didChangeDependencies throws', () {
      final owner = BuildOwner();
      final model = _Model();
      late _ListenInDependenciesState state;
      final root = owner.mountRoot(
        _Build((context) => _ListenInDependencies(model)),
      );
      void visit(Element element) {
        if (element is StatefulElement &&
            element.state is _ListenInDependenciesState) {
          state = element.state as _ListenInDependenciesState;
        }
        element.visitChildren(visit);
      }

      visit(root);
      expect(state.error, isA<StateError>());
      expect(model.hasListeners, isFalse);
      root.unmount();
    });

    test(
      'an optional read is null when absent and subscribes when present',
      () {
        final owner = BuildOwner();
        final model = _Model();
        final seen = <int?>[];
        Widget reader() => _Build((context) {
          seen.add(context.scope<_Model?>()?.count);
          return const EmptyBox();
        });

        final absent = owner.mountRoot(reader());
        expect(seen, [null]);
        absent.unmount();

        final present = owner.mountRoot(Scope(model, child: reader()));
        model.increment();
        owner.flushBuild();
        expect(seen, [null, 0, 1]);
        present.unmount();
        expect(model.hasListeners, isFalse);
      },
    );

    test('ScopeBuilder takes a nullable type the same way', () {
      final owner = BuildOwner();
      final seen = <int?>[];
      final root = owner.mountRoot(
        ScopeBuilder<_Model?>(
          builder: (context, model) {
            seen.add(model?.count);
            return const EmptyBox();
          },
        ),
      );
      expect(seen, [null]);
      root.unmount();
    });

    test('a render-object widget follows a scope read while configuring', () {
      final owner = BuildOwner();
      const leaf = _LabelLeaf(); // identical instance: no widget update
      final root = owner.mountRoot(const Scope(_Label('first'), child: leaf));
      expect(_RenderLabel.last, 'first');

      owner.updateRoot(root, const Scope(_Label('second'), child: leaf));
      owner.flushBuild();
      expect(_RenderLabel.last, 'second');
      root.unmount();
    });
  });
}
