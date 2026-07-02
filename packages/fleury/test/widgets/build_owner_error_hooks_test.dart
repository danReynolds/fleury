import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

class _Boom extends StatelessWidget {
  const _Boom();

  @override
  Widget build(BuildContext context) => throw StateError('kaboom');
}

void main() {
  group('BuildOwner error hooks', () {
    test('two owners have independent hooks — no cross-runtime leak', () {
      final testerA = FleuryTester();
      final testerB = FleuryTester();
      addTearDown(testerA.dispose);
      addTearDown(testerB.dispose);

      final seenA = <Object>[];
      final seenB = <Object>[];
      testerA.owner.onBuildError = (e, s) => seenA.add(e);
      testerB.owner.onBuildError = (e, s) => seenB.add(e);

      testerA.pumpWidget(const _Boom());
      testerA.render(size: const CellSize(20, 4));

      expect(seenA, hasLength(1), reason: 'owner A observed its error');
      expect(seenB, isEmpty, reason: 'owner B never sees A\'s errors');
    });

    test('a raw BuildOwner (no errorBuilder) rethrows build errors', () {
      final owner = BuildOwner();
      expect(
        () => owner.mountRoot(const _Boom()),
        throwsA(isA<StateError>()),
        reason:
            'null errorBuilder means "no boundary" — low-level harnesses '
            'keep propagate-on-throw semantics',
      );
    });

    test('customizing one tester\'s builder does not leak to the next', () {
      final testerA = FleuryTester();
      testerA.owner.errorBuilder = (e, s) => const Text('custom panel');
      testerA.pumpWidget(const _Boom());
      final outA = testerA.renderToString(size: const CellSize(20, 2));
      expect(outA.contains('custom panel'), isTrue);
      testerA.dispose();

      final testerB = FleuryTester();
      addTearDown(testerB.dispose);
      testerB.pumpWidget(const _Boom());
      final outB = testerB.renderToString(size: const CellSize(20, 4));
      expect(
        outB.contains('custom panel'),
        isFalse,
        reason: 'fresh owner, fresh default ErrorWidget builder',
      );
      expect(outB.contains('kaboom'), isTrue);
    });
  });
}
