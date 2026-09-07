// Scope: the tree-local state primitive. Lookup (type-keyed, nearest wins),
// plain-value replacement, Listenable subscription (attach-before-mount,
// swap-on-update, detach-on-unmount), Scope.create ownership, and the
// lifecycle edges a reader can hit (initState, dispose).

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

class _Model extends ChangeNotifier {
  _Model([this.value = 0]);

  int value;
  bool disposed = false;

  void increment() {
    value++;
    notifyListeners();
  }

  void ping() => notifyListeners();

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// A plain (non-Listenable) value with `==`, as a settings object would be.
final class _Config {
  const _Config(this.n);
  final int n;
  @override
  bool operator ==(Object other) => other is _Config && other.n == n;
  @override
  int get hashCode => n;
}

class _Base {
  const _Base(this.name);
  final String name;
}

class _Derived extends _Base {
  const _Derived(super.name);
}

/// Logs the model value on every build; optionally pings the model during
/// its build (the "descendant notifies while mounting/updating" case).
class _Reader extends StatelessWidget {
  const _Reader({required this.log, this.pingOnce, this.subscribe = true});

  final List<int> log;
  final _Ping? pingOnce;
  final bool subscribe;

  @override
  Widget build(BuildContext context) {
    final model = subscribe
        ? Scope.of<_Model>(context)
        : Scope.maybeOfWithoutDependency<_Model>(context)!;
    log.add(model.value);
    final ping = pingOnce;
    if (ping != null && !ping.sent && identical(model, ping.model)) {
      ping.sent = true;
      model.ping();
    }
    return const EmptyBox();
  }
}

class _Ping {
  _Ping(this.model);
  final _Model model;
  bool sent = false;
}

/// Reads the config on every build and counts didChangeDependencies.
class _ConfigReader extends StatefulWidget {
  const _ConfigReader({super.key, required this.log});
  final List<String> log;
  @override
  State<_ConfigReader> createState() => _ConfigReaderState();
}

class _ConfigReaderState extends State<_ConfigReader> {
  int dependencyChanges = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    dependencyChanges++;
  }

  @override
  Widget build(BuildContext context) {
    widget.log.add('build:${Scope.of<_Config>(context).n}');
    return const EmptyBox();
  }
}

/// Rebuilds with a fresh config on demand, so a scope can be replaced in
/// place (rather than re-inflating the whole tree via updateRoot).
class _ConfigHost extends StatefulWidget {
  const _ConfigHost({required this.child, this.narrow = false});
  final Widget child;
  final bool narrow;
  @override
  State<_ConfigHost> createState() => _ConfigHostState();
}

class _ConfigHostState extends State<_ConfigHost> {
  _Config config = const _Config(1);
  void set(_Config next) => setState(() => config = next);

  @override
  Widget build(BuildContext context) => widget.narrow
      ? _ParityScope(value: config, child: widget.child)
      : Scope<_Config>(value: config, child: widget.child);
}

/// A subclass narrowing [updateShouldNotify]: readers care about parity only.
class _ParityScope extends Scope<_Config> {
  const _ParityScope({required this.value, required super.child})
    : super(value: value);

  final _Config value;

  @override
  bool updateShouldNotify(_ParityScope oldWidget) =>
      value.n.isEven != oldWidget.value.n.isEven;
}

class _ModelHost extends StatefulWidget {
  const _ModelHost({required this.model, required this.child});
  final _Model model;
  final Widget child;
  @override
  State<_ModelHost> createState() => _ModelHostState();
}

class _ModelHostState extends State<_ModelHost> {
  late _Model model = widget.model;
  void replace(_Model next) => setState(() => model = next);

  @override
  Widget build(BuildContext context) =>
      Scope<_Model>(value: model, child: widget.child);
}

class _ThrowOnValue extends StatelessWidget {
  const _ThrowOnValue(this.value);
  final int value;

  @override
  Widget build(BuildContext context) {
    Scope.of<_Model>(context);
    if (value == 2) throw StateError('child update failed');
    return const EmptyBox();
  }
}

/// Reads the scope in initState only; build does not touch it.
class _InitStateReader extends StatefulWidget {
  const _InitStateReader({required this.log});
  final List<String> log;
  @override
  State<_InitStateReader> createState() => _InitStateReaderState();
}

class _InitStateReaderState extends State<_InitStateReader> {
  late final _Model model;
  int builds = 0;

  @override
  void initState() {
    super.initState();
    model = Scope.of<_Model>(context);
    widget.log.add('init:${model.value}');
  }

  @override
  Widget build(BuildContext context) {
    builds++;
    widget.log.add('build');
    return const EmptyBox();
  }
}

/// Looks the scope up from dispose and records what happens.
class _DisposeReader extends StatefulWidget {
  const _DisposeReader({required this.log});
  final List<String> log;
  @override
  State<_DisposeReader> createState() => _DisposeReaderState();
}

class _DisposeReaderState extends State<_DisposeReader> {
  @override
  void dispose() {
    try {
      Scope.of<_Model>(context);
      widget.log.add('read');
    } on StateError catch (error) {
      widget.log.add('error:${error.message}');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const EmptyBox();
}

/// Switches one tree position between a sharing scope and an owning one.
class _VariantHost extends StatefulWidget {
  const _VariantHost({
    required this.shared,
    required this.created,
    required this.child,
  });
  final _Model shared;
  final List<_Model> created;
  final Widget child;
  @override
  State<_VariantHost> createState() => _VariantHostState();
}

class _VariantHostState extends State<_VariantHost> {
  bool owning = false;
  void toggle() => setState(() => owning = !owning);

  @override
  Widget build(BuildContext context) => owning
      ? Scope<_Model>.create(
          create: (_) {
            final model = _Model(100);
            widget.created.add(model);
            return model;
          },
          child: widget.child,
        )
      : Scope<_Model>(value: widget.shared, child: widget.child);
}

class _Plain {
  int disposeCalls = 0;
}

/// Starts as an owning scope; [share] rebuilds the same position as a sharing
/// scope of whatever object is handed in (possibly the created one).
class _HandoffHost extends StatefulWidget {
  const _HandoffHost({required this.child});
  final Widget child;
  @override
  State<_HandoffHost> createState() => _HandoffHostState();
}

class _HandoffHostState extends State<_HandoffHost> {
  _Model? created;
  _Model? shared;
  void share(_Model model) => setState(() => shared = model);

  @override
  Widget build(BuildContext context) {
    final shared = this.shared;
    if (shared != null) {
      return Scope<_Model>(value: shared, child: widget.child);
    }
    return Scope<_Model>.create(
      create: (_) => created = _Model(7),
      child: widget.child,
    );
  }
}

/// Runs [builder] with its own context (Fleury has no `Builder` widget).
class _Build extends StatelessWidget {
  const _Build(this.builder);
  final Widget Function(BuildContext context) builder;
  @override
  Widget build(BuildContext context) => builder(context);
}

void main() {
  group('Scope lookup', () {
    test('of reads the nearest value; maybeOf is null when absent', () {
      final owner = BuildOwner();
      _Config? found;
      _Model? missing;
      owner.mountRoot(
        Scope<_Config>(
          value: const _Config(7),
          child: _Build((context) {
            found = Scope.of<_Config>(context);
            missing = Scope.maybeOf<_Model>(context);
            return const EmptyBox();
          }),
        ),
      );
      expect(found, const _Config(7));
      expect(missing, isNull);
    });

    test('of throws a StateError naming the missing scope', () {
      final owner = BuildOwner();
      Object? error;
      owner.mountRoot(
        _Build((context) {
          try {
            Scope.of<_Model>(context);
          } catch (e) {
            error = e;
          }
          return const EmptyBox();
        }),
      );
      expect(error, isA<StateError>());
      expect('$error', contains('no Scope<_Model> above this context'));
    });

    test('a missing type argument is an assertion, not a silent miss', () {
      final owner = BuildOwner();
      Object? error;
      owner.mountRoot(
        Scope<_Config>(
          value: const _Config(1),
          child: _Build((context) {
            try {
              Scope.maybeOf(context);
            } catch (e) {
              error = e;
            }
            return const EmptyBox();
          }),
        ),
      );
      expect(error, isA<AssertionError>());
    });

    test('the nearest scope of the requested type wins', () {
      final owner = BuildOwner();
      final seen = <String>[];
      owner.mountRoot(
        Scope<_Config>(
          value: const _Config(1),
          child: Scope<_Base>(
            value: const _Base('outer'),
            child: Column(
              children: [
                _Build((context) {
                  seen.add('a:${Scope.of<_Base>(context).name}');
                  return const EmptyBox();
                }),
                Scope<_Base>(
                  value: const _Base('inner'),
                  child: _Build((context) {
                    seen.add('b:${Scope.of<_Base>(context).name}');
                    seen.add('c:${Scope.of<_Config>(context).n}');
                    return const EmptyBox();
                  }),
                ),
              ],
            ),
          ),
        ),
      );
      expect(seen, ['a:outer', 'b:inner', 'c:1']);
    });

    test('the type argument is matched exactly, not by subtype', () {
      final owner = BuildOwner();
      _Base? base;
      _Derived? derived;
      owner.mountRoot(
        Scope<_Base>(
          value: const _Base('base'),
          child: Scope<_Derived>(
            value: const _Derived('derived'),
            child: _Build((context) {
              base = Scope.of<_Base>(context);
              derived = Scope.of<_Derived>(context);
              return const EmptyBox();
            }),
          ),
        ),
      );
      expect(base!.name, 'base', reason: 'Scope<_Derived> is not a match');
      expect(derived!.name, 'derived');
    });
  });

  group('Scope with a plain value', () {
    test('a replacement that is not equal rebuilds readers', () {
      final owner = BuildOwner();
      final log = <String>[];
      final root =
          owner.mountRoot(_ConfigHost(child: _ConfigReader(log: log)))
              as StatefulElement;
      expect(log, ['build:1']);
      log.clear();

      (root.state as _ConfigHostState).set(const _Config(2));
      owner.flushBuild();
      expect(log, ['build:2']);
    });

    test('an equal replacement does not rebuild readers', () {
      final owner = BuildOwner();
      final log = <String>[];
      final root =
          owner.mountRoot(_ConfigHost(child: _ConfigReader(log: log)))
              as StatefulElement;
      log.clear();

      (root.state as _ConfigHostState).set(const _Config(1));
      owner.flushBuild();
      expect(log, isEmpty);
    });

    test('a notification runs didChangeDependencies before the build', () {
      final owner = BuildOwner();
      final log = <String>[];
      final readerKey = GlobalKey<_ConfigReaderState>();
      final root =
          owner.mountRoot(
                _ConfigHost(
                  child: _ConfigReader(key: readerKey, log: log),
                ),
              )
              as StatefulElement;
      expect(readerKey.currentState!.dependencyChanges, 1);

      (root.state as _ConfigHostState).set(const _Config(3));
      owner.flushBuild();
      expect(readerKey.currentState!.dependencyChanges, 2);
    });

    test('a subclass can narrow updateShouldNotify', () {
      final owner = BuildOwner();
      final log = <String>[];
      final root =
          owner.mountRoot(
                _ConfigHost(narrow: true, child: _ConfigReader(log: log)),
              )
              as StatefulElement;
      log.clear();
      final host = root.state as _ConfigHostState;

      host.set(const _Config(3)); // odd -> odd: no notification
      owner.flushBuild();
      expect(log, isEmpty);

      host.set(const _Config(4)); // odd -> even
      owner.flushBuild();
      expect(log, ['build:4']);
    });
  });

  group('Scope with a Listenable value', () {
    test('notifications rebuild subscribed readers', () {
      final owner = BuildOwner();
      final model = _Model();
      final log = <int>[];
      owner.mountRoot(
        Scope<_Model>(
          value: model,
          child: _Reader(log: log),
        ),
      );

      model.increment();
      owner.flushBuild();

      expect(log, [0, 1]);
    });

    test('the scope listens before its child mounts', () {
      // An earlier sibling reads the model, then a later sibling notifies it
      // during its own first build. The reader must be marked dirty by that
      // notification, which requires the scope to be subscribed already.
      final owner = BuildOwner();
      final model = _Model();
      final log = <int>[];
      owner.mountRoot(
        Scope<_Model>(
          value: model,
          child: Column(
            children: [
              _Reader(log: log),
              _Reader(log: <int>[], pingOnce: _Ping(model)),
            ],
          ),
        ),
      );
      owner.flushBuild();
      expect(log, [0, 0], reason: 'the ping during mount reached the reader');
    });

    test('a replacement notifier is live during the child update', () {
      final owner = BuildOwner();
      final first = _Model();
      final second = _Model(2);
      final log = <int>[];
      final root =
          owner.mountRoot(
                _ModelHost(
                  model: first,
                  child: _Reader(log: log, pingOnce: _Ping(second)),
                ),
              )
              as StatefulElement;

      (root.state as _ModelHostState).replace(second);
      owner.flushBuild();

      expect(log, [0, 2, 2]);
      expect(first.hasListeners, isFalse);
      expect(second.hasListeners, isTrue);
    });

    test('a replacement detaches the old notifier', () {
      final owner = BuildOwner();
      final first = _Model();
      final second = _Model();
      final log = <int>[];
      final root =
          owner.mountRoot(
                _ModelHost(
                  model: first,
                  child: _Reader(log: log),
                ),
              )
              as StatefulElement;

      (root.state as _ModelHostState).replace(second);
      owner.flushBuild();
      log.clear();
      first.increment();
      owner.flushBuild();

      expect(log, isEmpty);
      expect(first.hasListeners, isFalse);
      expect(second.hasListeners, isTrue);
    });

    test('a failed child update stays attached to the exposed notifier', () {
      final owner = BuildOwner();
      final first = _Model();
      final second = _Model();
      final root = owner.mountRoot(
        Scope<_Model>(value: first, child: const _ThrowOnValue(1)),
      );

      expect(
        () => owner.updateRoot(
          root,
          Scope<_Model>(value: second, child: const _ThrowOnValue(2)),
        ),
        throwsA(isA<StateError>()),
      );

      expect(first.hasListeners, isFalse);
      expect(second.hasListeners, isTrue);
    });

    test('unmount detaches the notifier and never disposes a shared value', () {
      final owner = BuildOwner();
      final model = _Model();
      final root = owner.mountRoot(
        Scope<_Model>(
          value: model,
          child: _Reader(log: <int>[]),
        ),
      );

      expect(model.hasListeners, isTrue);
      root.unmount();

      expect(model.hasListeners, isFalse);
      expect(model.disposed, isFalse);
    });

    test('a non-subscribing read does not rebuild', () {
      final owner = BuildOwner();
      final model = _Model();
      final log = <int>[];
      owner.mountRoot(
        Scope<_Model>(
          value: model,
          child: _Reader(log: log, subscribe: false),
        ),
      );

      model.increment();
      owner.flushBuild();

      expect(log, [0]);
    });

    test('a read from initState subscribes the reader', () {
      final owner = BuildOwner();
      final model = _Model(5);
      final log = <String>[];
      owner.mountRoot(
        Scope<_Model>(
          value: model,
          child: _InitStateReader(log: log),
        ),
      );
      expect(log, ['init:5', 'build']);

      model.increment();
      owner.flushBuild();
      expect(log, ['init:5', 'build', 'build']);
    });

    test('a read from dispose fails with a pointed message', () {
      final owner = BuildOwner();
      final model = _Model();
      final log = <String>[];
      final root = owner.mountRoot(
        Scope<_Model>(
          value: model,
          child: _DisposeReader(log: log),
        ),
      );
      root.unmount();
      expect(log, hasLength(1));
      expect(log.single, startsWith('error:'));
      expect(log.single, contains('no longer in the tree'));
    });
  });

  group('Scope.create', () {
    test('creates once at mount with a context that reads scopes above', () {
      final owner = BuildOwner();
      var creates = 0;
      final log = <int>[];
      final root = owner.mountRoot(
        Scope<_Config>(
          value: const _Config(40),
          child: Scope<_Model>.create(
            create: (context) {
              creates++;
              return _Model(Scope.of<_Config>(context).n + 2);
            },
            child: _Reader(log: log),
          ),
        ),
      );
      expect(log, [42]);
      expect(creates, 1);

      // Rebuilding the scope widget keeps the object; create does not rerun.
      owner.updateRoot(
        root,
        Scope<_Config>(
          value: const _Config(40),
          child: Scope<_Model>.create(
            create: (context) {
              creates++;
              return _Model(-1);
            },
            child: _Reader(log: log),
          ),
        ),
      );
      expect(creates, 1);
      expect(log, [42, 42]);
    });

    test('the created value notifies readers like a shared one', () {
      final owner = BuildOwner();
      _Model? created;
      final log = <int>[];
      owner.mountRoot(
        Scope<_Model>.create(
          create: (_) => created = _Model(),
          child: _Reader(log: log),
        ),
      );
      created!.increment();
      owner.flushBuild();
      expect(log, [0, 1]);
    });

    test('a ChangeNotifier is disposed on unmount by default', () {
      final owner = BuildOwner();
      _Model? created;
      final root = owner.mountRoot(
        Scope<_Model>.create(
          create: (_) => created = _Model(),
          child: _Reader(log: <int>[]),
        ),
      );
      expect(created!.disposed, isFalse);
      root.unmount();
      expect(created!.disposed, isTrue);
      expect(created!.hasListeners, isFalse);
    });

    test('an explicit dispose callback runs instead', () {
      final owner = BuildOwner();
      final plain = _Plain();
      final root = owner.mountRoot(
        Scope<_Plain>.create(
          create: (_) => plain,
          dispose: (value) => value.disposeCalls++,
          child: _Build((context) {
            Scope.of<_Plain>(context);
            return const EmptyBox();
          }),
        ),
      );
      root.unmount();
      expect(plain.disposeCalls, 1);
    });

    test('children are unmounted before the created value is disposed', () {
      final owner = BuildOwner();
      final order = <String>[];
      final root = owner.mountRoot(
        Scope<_Plain>.create(
          create: (_) => _Plain(),
          dispose: (_) => order.add('dispose'),
          child: _OrderProbe(order: order),
        ),
      );
      root.unmount();
      expect(order, ['child', 'dispose']);
    });

    test('handing the owned object over as a shared value keeps it alive', () {
      final owner = BuildOwner();
      final log = <int>[];
      final root =
          owner.mountRoot(_HandoffHost(child: _Reader(log: log)))
              as StatefulElement;
      final host = root.state as _HandoffHostState;
      final model = host.created!;
      expect(log, [7]);

      // The parent now supplies the very object the scope created: ownership
      // passes to the parent, nothing is disposed, the scope keeps listening.
      host.share(model);
      owner.flushBuild();
      expect(model.disposed, isFalse);
      expect(model.hasListeners, isTrue);
      model.increment();
      owner.flushBuild();
      expect(log, [7, 7, 8]);

      root.unmount();
      expect(
        model.disposed,
        isFalse,
        reason: 'a shared value is never disposed',
      );
      expect(model.hasListeners, isFalse);
    });

    test('a failed hand-off leaves the object owned and disposes it later', () {
      final owner = BuildOwner();
      final root =
          owner.mountRoot(_HandoffHost(child: _Reader(log: <int>[])))
              as StatefulElement;
      final host = root.state as _HandoffHostState;
      final created = host.created!;

      // A disposed notifier refuses listeners, so the swap fails before the
      // scope adopts it; the created object must still be released later.
      host.share(_Model()..dispose());
      expect(owner.flushBuild, throwsStateError);
      expect(created.disposed, isFalse);
      expect(created.hasListeners, isTrue, reason: 'still the live value');

      root.unmount();
      expect(created.disposed, isTrue);
      expect(created.hasListeners, isFalse);
    });

    test('switching between a shared and an owned value at one position', () {
      final owner = BuildOwner();
      final shared = _Model(1);
      final created = <_Model>[];
      final log = <int>[];
      final root =
          owner.mountRoot(
                _VariantHost(
                  shared: shared,
                  created: created,
                  child: _Reader(log: log),
                ),
              )
              as StatefulElement;
      final host = root.state as _VariantHostState;
      expect(log, [1]);

      host.toggle(); // shared -> owned
      owner.flushBuild();
      expect(created, hasLength(1));
      expect(log, [1, 100]);
      expect(shared.hasListeners, isFalse);
      expect(created.single.hasListeners, isTrue);

      host.toggle(); // owned -> shared: the created model is released
      owner.flushBuild();
      expect(log, [1, 100, 1]);
      expect(created.single.disposed, isTrue);
      expect(shared.hasListeners, isTrue);
      expect(shared.disposed, isFalse);
    });
  });
}

class _OrderProbe extends StatefulWidget {
  const _OrderProbe({required this.order});
  final List<String> order;
  @override
  State<_OrderProbe> createState() => _OrderProbeState();
}

class _OrderProbeState extends State<_OrderProbe> {
  @override
  void dispose() {
    widget.order.add('child');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Scope.of<_Plain>(context);
    return const EmptyBox();
  }
}
