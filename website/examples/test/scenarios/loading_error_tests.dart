import 'dart:async';

import 'package:fleury/fleury_core.dart' show CellSize, SizedBox;
import 'package:fleury_doc_examples/registry.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart' show Select;
import 'package:test/test.dart';

Future<List<Object>> captureUnhandledErrors(Future<void> Function() body) {
  final errors = <Object>[];
  final settled = Completer<List<Object>>();
  runZonedGuarded(() async {
    try {
      await body();
      await Future<void>.delayed(Duration.zero);
    } catch (error) {
      errors.add(error);
    } finally {
      settled.complete(errors);
    }
  }, (error, stack) => errors.add(error));
  return settled.future;
}

// A semantic tester action completes a frame immediately. Invoke the actual
// input callback here so we can hold the next frame, as a browser waiting for
// rAF does. Dynamic dispatch preserves the demo's private enum type.
void _selectWithoutFrame(FleuryTester tester, String label) {
  final dynamic select = tester
      .findOne(byPredicate((widget) => widget is Select))
      .widget;
  final dynamic option = select.options.singleWhere(
    (dynamic option) => option.label == label,
  );
  select.onChanged(option.value);
}

void liveLoadingErrorTests() {
  for (final next in ['Error', 'Success', 'unmount']) {
    test('live failure is handled before a delayed $next frame', () async {
      final example = exampleList.singleWhere(
        (entry) => entry.id == 'loading.snapshot',
      );
      final size = CellSize(example.cols, example.rows);
      final tester = FleuryTester(viewportSize: size);
      addTearDown(tester.dispose);
      tester.pumpWidget(example.builder());

      final errors = await captureUnhandledErrors(() async {
        _selectWithoutFrame(tester, 'Error');
        if (next == 'Success') _selectWithoutFrame(tester, 'Success');
        if (next == 'unmount') tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        tester.pump();
        await Future<void>.delayed(Duration.zero);
        tester.pump();
      });
      expect(errors, isEmpty);
      final output = tester.renderToString(size: size, emptyMark: ' ');
      if (next == 'Error') {
        expect(output, contains('ERROR'));
        expect(output, contains('Connection lost'));
      } else if (next == 'Success') {
        expect(output, contains('READY'));
        expect(output, contains('alpha.log'));
        expect(output, isNot(contains('ERROR')));
      }
    });
  }

  testWidgets('the semantic selector still reaches the ERROR card', (
    tester,
  ) async {
    final example = exampleList.singleWhere(
      (entry) => entry.id == 'loading.snapshot',
    );
    final size = CellSize(example.cols, example.rows);
    tester.viewportSize = size;
    tester.pumpWidget(example.builder());
    await tester.button('Snapshot state').setValue('Error');
    await tester.settle();
    expect(tester.renderToString(size: size), contains('ERROR'));
  });
}
