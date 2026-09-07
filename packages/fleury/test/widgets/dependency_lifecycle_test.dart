import 'package:fleury/fleury.dart';
import 'package:fleury/src/widgets/framework.dart' show ElementDependency;
import 'package:test/test.dart';

class _Source implements ElementDependency {
  _Source(this.name, {this.throwOnRemove = false});
  final String name;
  final bool throwOnRemove;
  final elements = <Element>{};
  int additions = 0;
  int removals = 0;
  void Function(Element)? onRemove;

  @override
  void addDependent(Element element) {
    additions++;
    elements.add(element);
  }

  @override
  void removeDependent(Element element) {
    removals++;
    elements.remove(element);
    onRemove?.call(element);
    if (throwOnRemove) throw StateError('remove $name');
  }

  void notify() {
    for (final element in elements.toList()) {
      element.markNeedsBuild();
    }
  }
}

class _Reader extends StatelessWidget {
  const _Reader({super.key, required this.log, this.second});
  final List<String> log;
  final _Source? second;
  @override
  Widget build(BuildContext context) {
    final source = Scope.of<_Source>(context);
    final element = context as Element;
    element.dependOnExternal(source);
    element.dependOnExternal(source);
    if (second case final other?) element.dependOnExternal(other);
    log.add(source.name);
    return const EmptyBox();
  }
}

void main() {
  test('repeated external reads register once and detach once', () {
    final owner = BuildOwner();
    final source = _Source('one');
    final log = <String>[];
    final root = owner.mountRoot(
      Scope<_Source>(
        value: source,
        child: _Reader(log: log),
      ),
    );
    source.notify();
    owner.flushBuild();
    expect(log, ['one', 'one']);
    expect(source.additions, 1);
    root.unmount();
    expect(source.removals, 1);
    expect(source.elements, isEmpty);
  });

  test('a throwing source cannot strand other dependency edges on unmount', () {
    final owner = BuildOwner();
    final first = _Source('first', throwOnRemove: true);
    final second = _Source('second');
    final root = owner.mountRoot(
      Scope<_Source>(
        value: first,
        child: _Reader(log: [], second: second),
      ),
    );
    expect(root.unmount, throwsStateError);
    expect(first.elements, isEmpty);
    expect(second.elements, isEmpty);
    expect(first.removals, 1);
    expect(second.removals, 1);
    first.notify();
    second.notify();
    expect(owner.hasScheduledBuilds, isFalse);
  });

  for (final reentrant in [false, true]) {
    test('GlobalKey moves replace dependencies (reentrant: $reentrant)', () {
      final owner = BuildOwner();
      final first = _Source('first');
      final second = _Source('second');
      if (reentrant) {
        first.onRemove = (element) => element.dependOnExternal(second);
      }
      final log = <String>[];
      final key = GlobalKey();
      final reader = _Reader(key: key, log: log);
      Widget scene(bool moved) => Row(
        children: [
          Scope<_Source>(
            value: first,
            child: moved ? const EmptyBox() : reader,
          ),
          Scope<_Source>(
            value: second,
            child: moved ? reader : const EmptyBox(),
          ),
        ],
      );
      final root = owner.mountRoot(scene(false));
      addTearDown(root.unmount);
      final element = key.currentContext;
      owner.updateRoot(root, scene(true));
      expect(key.currentContext, same(element));
      expect(first.elements, isEmpty);
      expect(first.removals, 1);
      expect(second.elements, contains(element));
      expect(second.additions, 1);
      expect(log.last, 'second');
      first.notify();
      expect(owner.hasScheduledBuilds, isFalse);
      second.notify();
      expect(owner.hasScheduledBuilds, isTrue);
      owner.flushBuild();
      expect(log.last, 'second');
      expect(second.additions, 1);
    });
  }
}
