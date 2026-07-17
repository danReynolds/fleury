import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('drives a widget and disposes automatically', (tester) {
    tester.pumpWidget(const Text('hello'));

    expect(tester.find(text('hello')), hasLength(1));
    expect(
      tester.renderToString(size: const CellSize(8, 1)),
      contains('hello'),
    );
  });

  test('findOne reports package:test failures', () {
    final tester = FleuryTester();
    try {
      tester.pumpWidget(const Text('hello'));
      expect(
        () => tester.findOne(text('missing')),
        throwsA(isA<TestFailure>()),
      );
    } finally {
      tester.dispose();
    }
  });
}
