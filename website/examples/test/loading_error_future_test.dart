// The loading-data guide's error preview must not hand `FutureBuilder` an
// ALREADY-failed future.
//
// `setState` schedules a rebuild; `FutureBuilder` subscribes in that rebuild,
// one microtask (or more) after the assignment. A future built with
// `Future.error(...)` — or, measurably, `Future.sync(() => throw ...)`, which
// completes the same way — reports its error to the zone before that listener
// exists. The card renders the ERROR state correctly and the terminal runtime
// then paints its unhandled-error banner straight over it.
//
// The fix is a future that is not yet complete when it is assigned. These
// tests reproduce the real subscription timing rather than trusting a
// rendered string, so they fail on the old spelling and pass on the new one.
@TestOn('vm')
library;

import 'dart:async';

import 'package:fleury/fleury_core.dart'
    show CellSize, SemanticAction, SemanticRole;
import 'package:fleury_doc_examples/registry.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

import '../doc_snippets/loading_data.dart' as loading_data;

/// Runs [body] in a guarded zone and returns every error that reached the zone
/// without a listener, after the microtask queue and one timer turn drained.
Future<List<Object>> _unhandledErrorsFrom(void Function() body) {
  final errors = <Object>[];
  final settled = Completer<List<Object>>();
  runZonedGuarded(
    () {
      body();
      Timer(const Duration(milliseconds: 50), () {
        if (!settled.isCompleted) settled.complete(errors);
      });
    },
    (error, stack) {
      errors.add(error);
      if (!settled.isCompleted) settled.complete(errors);
    },
  );
  return settled.future;
}

void main() {
  test('the guide snippet error preview is not already-failed', () async {
    final errors = await _unhandledErrorsFrom(() {
      final future = loading_data.futureFor(loading_data.SnapshotPreview.error)!;
      // Subscribe a microtask later — what a setState-scheduled rebuild does.
      scheduleMicrotask(() {
        future.then((_) {}, onError: (Object _) {});
      });
    });
    expect(
      errors,
      isEmpty,
      reason:
          'futureFor(error) completed before FutureBuilder could subscribe; '
          'build a future that fails asynchronously instead',
    );
  });

  test('the live demo error preview is not already-failed', () async {
    final example = exampleList.singleWhere(
      (example) => example.id == 'loading.snapshot',
    );
    final errors = await _unhandledErrorsFrom(() {
      final tester = FleuryTester();
      tester.pumpWidget(example.builder());
      unawaited(
        tester
            .invokeSemanticAction(
              SemanticAction.setValue,
              role: SemanticRole.button,
              label: 'Snapshot state',
              payload: 'Error',
            )
            .then((_) => tester.pump()),
      );
    });
    expect(
      errors,
      isEmpty,
      reason:
          'switching the demo to Error surfaced an unhandled future error, '
          'which the terminal runtime paints as a banner over the card',
    );
  });

  // Failing later must still fail: the point of the demo is the ERROR card.
  testWidgets('the live demo still reaches the ERROR card', (tester) async {
    final example = exampleList.singleWhere(
      (example) => example.id == 'loading.snapshot',
    );
    tester.pumpWidget(example.builder());
    await tester.invokeSemanticAction(
      SemanticAction.setValue,
      role: SemanticRole.button,
      label: 'Snapshot state',
      payload: 'Error',
    );
    // Let the zero-duration timer that fails the future actually run.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    tester.pump();
    final output = tester.renderToString(
      size: CellSize(example.cols, example.rows),
      emptyMark: ' ',
    );
    expect(output, contains('ERROR'));
    expect(output, contains('Connection lost'));
  });
}
