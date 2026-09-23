import 'package:fleury/fleury.dart';
import 'package:fleury/src/widgets/framework.dart' show dependOnListenable;
import 'package:test/test.dart';

// A listenable read implicitly by a value getter, the way `Animation.value`
// subscribes the widget whose build reads it.
class _Source implements Listenable {
  _Source(this.name, {this.throwOnRemove = false});
  final String name;
  final bool throwOnRemove;
  final listeners = <VoidCallback>[];
  int additions = 0;
  int removals = 0;

  @override
  void addListener(VoidCallback listener) {
    additions++;
    listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    removals++;
    if (throwOnRemove) throw StateError('remove $name');
    listeners.remove(listener);
  }

  void notify() {
    for (final listener in listeners.toList()) {
      listener();
    }
  }

  String get value {
    final element = Element.current;
    if (element != null) dependOnListenable(element, this);
    return name;
  }
}

// Supplies a source by position without being a Listenable itself, so the
// scope does not notify on the source's behalf.
class _Holder {
  const _Holder(this.source);
  final _Source source;
}

class _Reader extends StatelessWidget {
  const _Reader({super.key, required this.log, this.second});
  final List<String> log;
  final _Source? second;
  @override
  Widget build(BuildContext context) {
    final source = context.scope<_Holder>().source;
    source.value;
    context.listen(source);
    log.add(source.value);
    second?.value;
    return const EmptyBox();
  }
}

class _ReadInDependencies extends StatefulWidget {
  const _ReadInDependencies(this.source);
  final _Source source;
  @override
  State<_ReadInDependencies> createState() => _ReadInDependenciesState();
}

class _ReadInDependenciesState extends State<_ReadInDependencies> {
  String? seen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    seen = widget.source.value;
  }

  @override
  Widget build(BuildContext context) => const EmptyBox();
}

void main() {
  test('implicit and explicit reads share one subscription', () {
    final owner = BuildOwner();
    final source = _Source('one');
    final log = <String>[];
    final root = owner.mountRoot(
      Scope(_Holder(source), child: _Reader(log: log)),
    );
    expect(source.listeners, hasLength(1));
    source.notify();
    owner.flushBuild();
    expect(log, ['one', 'one']);
    expect(source.additions, 1);
    root.unmount();
    expect(source.removals, 1);
    expect(source.listeners, isEmpty);
  });

  test('a throwing source cannot strand other dependency edges on unmount', () {
    final owner = BuildOwner();
    final first = _Source('first', throwOnRemove: true);
    final second = _Source('second');
    final root = owner.mountRoot(
      Scope(
        _Holder(first),
        child: _Reader(log: [], second: second),
      ),
    );
    expect(root.unmount, throwsStateError);
    expect(first.removals, 1);
    expect(second.removals, 1);
    expect(second.listeners, isEmpty);
    first.notify(); // its callback is still registered, but inert
    second.notify();
    expect(owner.hasScheduledBuilds, isFalse);
  });

  test('a GlobalKey move reads the source at the new position', () {
    final owner = BuildOwner();
    final first = _Source('first');
    final second = _Source('second');
    final log = <String>[];
    final key = GlobalKey();
    final reader = _Reader(key: key, log: log);
    Widget scene(bool moved) => Row(
      children: [
        Scope(_Holder(first), child: moved ? const EmptyBox() : reader),
        Scope(_Holder(second), child: moved ? reader : const EmptyBox()),
      ],
    );
    final root = owner.mountRoot(scene(false));
    addTearDown(root.unmount);
    final element = key.currentContext;
    owner.updateRoot(root, scene(true));
    expect(key.currentContext, same(element));
    expect(first.listeners, isEmpty);
    expect(first.removals, 1);
    expect(second.listeners, hasLength(1));
    expect(log.last, 'second');
    first.notify();
    expect(owner.hasScheduledBuilds, isFalse);
    second.notify();
    expect(owner.hasScheduledBuilds, isTrue);
    owner.flushBuild();
    expect(log.last, 'second');
    expect(second.additions, 1);
  });

  test('an implicit read in didChangeDependencies is an ordinary read', () {
    // context.listen throws there; a value getter must not.
    final owner = BuildOwner();
    final source = _Source('value');
    final root = owner.mountRoot(_ReadInDependencies(source));
    addTearDown(root.unmount);
    final state = (root as StatefulElement).state as _ReadInDependenciesState;
    expect(state.seen, 'value');
  });
}
