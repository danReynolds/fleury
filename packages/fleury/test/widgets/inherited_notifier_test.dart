import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

class _Model extends ChangeNotifier {
  int value = 0;

  void increment() {
    value++;
    notifyListeners();
  }

  void ping() => notifyListeners();
}

class _ModelScope extends InheritedNotifier<_Model> {
  const _ModelScope({required _Model model, required super.child})
    : super(notifier: model);

  static _Model watch(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ModelScope>()!.notifier;

  static _Model read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ModelScope>()!.notifier;
}

class _Reader extends StatelessWidget {
  const _Reader({required this.log, this.notifyDuringBuild, this.watch = true});

  final List<int> log;
  final _BuildNotification? notifyDuringBuild;
  final bool watch;

  @override
  Widget build(BuildContext context) {
    final model = watch
        ? _ModelScope.watch(context)
        : _ModelScope.read(context);
    log.add(model.value);
    final buildNotification = notifyDuringBuild;
    if (buildNotification != null &&
        !buildNotification.sent &&
        identical(model, buildNotification.model)) {
      buildNotification.sent = true;
      model.ping();
    }
    return const EmptyBox();
  }
}

class _BuildNotification {
  _BuildNotification(this.model);

  final _Model model;
  bool sent = false;
}

class _ThrowOnValue extends StatelessWidget {
  const _ThrowOnValue(this.value);

  final int value;

  @override
  Widget build(BuildContext context) {
    _ModelScope.watch(context);
    if (value == 2) throw StateError('child update failed');
    return const EmptyBox();
  }
}

class _Host extends StatefulWidget {
  const _Host({required this.model, required this.child});

  final _Model model;
  final Widget child;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late _Model model = widget.model;

  void replace(_Model value) => setState(() => model = value);

  @override
  Widget build(BuildContext context) =>
      _ModelScope(model: model, child: widget.child);
}

void main() {
  group('InheritedNotifier', () {
    test('notifier events rebuild watching dependents', () {
      final owner = BuildOwner();
      final model = _Model();
      final log = <int>[];
      owner.mountRoot(
        _ModelScope(
          model: model,
          child: _Reader(log: log),
        ),
      );

      model.increment();
      owner.flushBuild();

      expect(log, [0, 1]);
    });

    test('replacement notifier is live during the child update', () {
      final owner = BuildOwner();
      final first = _Model();
      final second = _Model()..value = 2;
      final log = <int>[];
      final root =
          owner.mountRoot(
                _Host(
                  model: first,
                  child: _Reader(
                    log: log,
                    notifyDuringBuild: _BuildNotification(second),
                  ),
                ),
              )
              as StatefulElement;

      (root.state as _HostState).replace(second);
      owner.flushBuild();

      expect(log, [0, 2, 2]);
      expect(first.hasListeners, isFalse);
      expect(second.hasListeners, isTrue);
    });

    test('replacement detaches the old notifier', () {
      final owner = BuildOwner();
      final first = _Model();
      final second = _Model();
      final log = <int>[];
      final root =
          owner.mountRoot(
                _Host(
                  model: first,
                  child: _Reader(log: log),
                ),
              )
              as StatefulElement;

      (root.state as _HostState).replace(second);
      owner.flushBuild();
      log.clear();
      first.increment();
      owner.flushBuild();

      expect(log, isEmpty);
      expect(first.hasListeners, isFalse);
      expect(second.hasListeners, isTrue);
    });

    test('failed child update remains attached to the exposed notifier', () {
      final owner = BuildOwner();
      final first = _Model();
      final second = _Model();
      final root = owner.mountRoot(
        _ModelScope(model: first, child: const _ThrowOnValue(1)),
      );

      expect(
        () => owner.updateRoot(
          root,
          _ModelScope(model: second, child: const _ThrowOnValue(2)),
        ),
        throwsA(isA<StateError>()),
      );

      expect(first.hasListeners, isFalse);
      expect(second.hasListeners, isTrue);
    });

    test('unmount detaches the notifier', () {
      final owner = BuildOwner();
      final model = _Model();
      final root = owner.mountRoot(
        _ModelScope(
          model: model,
          child: _Reader(log: <int>[]),
        ),
      );

      expect(model.hasListeners, isTrue);
      root.unmount();

      expect(model.hasListeners, isFalse);
    });

    test('non-watching reads do not rebuild', () {
      final owner = BuildOwner();
      final model = _Model();
      final log = <int>[];
      owner.mountRoot(
        _ModelScope(
          model: model,
          child: _Reader(log: log, watch: false),
        ),
      );

      model.increment();
      owner.flushBuild();

      expect(log, [0]);
    });
  });
}
