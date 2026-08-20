import 'dart:io';

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

  test('a missing golden fails without creating a baseline', () {
    final tempDir = Directory.systemTemp.createTempSync('fleury_goldens_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final file = File('${tempDir.path}/missing.txt');

    expect(
      () => expect(
        'actual\n',
        matchesGolden('missing.txt', directory: tempDir.path),
      ),
      throwsA(
        isA<TestFailure>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('golden file not found'),
            contains('FLEURY_UPDATE_GOLDENS=1'),
          ),
        ),
      ),
    );
    expect(file.existsSync(), isFalse);
  });
}
