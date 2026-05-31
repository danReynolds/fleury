import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

class _Boom extends StatelessWidget {
  const _Boom();
  @override
  Widget build(BuildContext context) => throw StateError('kaboom');
}

void main() {
  testWidgets('a thrown build renders an error panel, not a crash', (tester) {
    tester.pumpWidget(const _Boom());
    final out = tester.renderToString(size: const CellSize(20, 4));
    expect(out.contains('kaboom'), isTrue, reason: 'error shown, app survived');
  });

  testWidgets('a sibling survives a broken widget', (tester) {
    tester.pumpWidget(const Column(children: [_Boom(), Text('still here')]));
    final out = tester.renderToString(size: const CellSize(20, 6));
    expect(out.contains('kaboom'), isTrue);
    expect(out.contains('still here'), isTrue, reason: 'sibling unaffected');
  });

  testWidgets('onBuildError observes the error', (tester) {
    Object? seen;
    Element.onBuildError = (e, s) => seen = e;
    addTearDown(() => Element.onBuildError = null);
    tester.pumpWidget(const _Boom());
    tester.render(size: const CellSize(20, 4));
    expect(seen, isA<StateError>());
  });

  testWidgets('a custom ErrorWidget.builder is used', (tester) {
    final previous = ErrorWidget.builder;
    ErrorWidget.builder = (e, s) => const Text('custom failure');
    addTearDown(() => ErrorWidget.builder = previous);
    tester.pumpWidget(const _Boom());
    final out = tester.renderToString(size: const CellSize(20, 2));
    expect(out.contains('custom failure'), isTrue);
  });
}
