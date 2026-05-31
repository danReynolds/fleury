import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

class _Counter extends StatefulWidget {
  const _Counter({super.key});
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  void bump() => setState(() => count++);
  @override
  Widget build(BuildContext context) => Text('count=$count');
}

// An unrelated State type, used to check the `state is T` cast in
// GlobalKey.currentState.
class _OtherState extends State<_Counter> {
  @override
  Widget build(BuildContext context) => const Text('other');
}

void main() {
  testWidgets('currentState reaches a mounted widget imperatively', (tester) {
    final key = GlobalKey<_CounterState>();
    tester.pumpWidget(_Counter(key: key));
    expect(
      tester.renderToString(size: const CellSize(10, 1)).trim(),
      'count=0',
    );

    key.currentState!.bump(); // drive it from outside the build
    tester.pump();
    expect(
      tester.renderToString(size: const CellSize(10, 1)).trim(),
      'count=1',
    );
  });

  testWidgets('currentContext is set while mounted, null after unmount', (
    tester,
  ) {
    final key = GlobalKey<_CounterState>();
    tester.pumpWidget(_Counter(key: key));
    expect(key.currentContext, isNotNull);
    expect(key.currentWidget, isA<_Counter>());

    tester.pumpWidget(const Text('gone'));
    expect(key.currentContext, isNull, reason: 'deregistered on unmount');
    expect(key.currentState, isNull);
  });

  testWidgets('state survives an in-place rebuild with the same key', (tester) {
    final key = GlobalKey<_CounterState>();
    tester.pumpWidget(_Counter(key: key));
    key.currentState!.bump();
    key.currentState!.bump();
    tester.pump();
    expect(
      tester.renderToString(size: const CellSize(10, 1)).trim(),
      'count=2',
    );

    // Rebuild the same widget+key at the same position → element reused.
    tester.pumpWidget(_Counter(key: key));
    expect(
      tester.renderToString(size: const CellSize(10, 1)).trim(),
      'count=2',
      reason: 'state preserved across rebuild',
    );
  });

  test('distinct GlobalKey instances are unequal (identity equality)', () {
    expect(GlobalKey() == GlobalKey(), isFalse);
    final k = GlobalKey();
    expect(k == k, isTrue);
  });

  testWidgets('currentState is null for a non-stateful keyed widget', (tester) {
    final key = GlobalKey();
    tester.pumpWidget(SizedBox(key: key, width: 1, height: 1));
    expect(key.currentContext, isNotNull);
    expect(key.currentWidget, isA<SizedBox>());
    expect(key.currentState, isNull, reason: 'SizedBox carries no State');
  });

  testWidgets('currentState is null when the State type does not match', (
    tester,
  ) {
    // Typed to _OtherState, but _Counter builds a _CounterState.
    final key = GlobalKey<_OtherState>();
    tester.pumpWidget(_Counter(key: key));
    expect(key.currentContext, isNotNull, reason: 'mounted — just wrong type');
    expect(key.currentState, isNull, reason: 'state is not an _OtherState');
  });

  testWidgets('reusing one key on two same-type widgets at once throws', (
    tester,
  ) {
    final key = GlobalKey();
    expect(
      () => tester.pumpWidget(
        Column(
          children: [
            SizedBox(key: key, width: 1, height: 1),
            SizedBox(key: key, width: 1, height: 1),
          ],
        ),
      ),
      throwsA(isA<StateError>()),
      reason:
          'a same-type duplicate would otherwise self-retake and corrupt '
          'the tree rather than error',
    );
  });

  testWidgets('reusing one key on two different-type widgets at once throws', (
    tester,
  ) {
    final key = GlobalKey();
    expect(
      () => tester.pumpWidget(
        Column(
          children: [
            SizedBox(key: key, width: 1, height: 1),
            Text('x', key: key),
          ],
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
