// The guide snippet and live preview own failures before rendering subscribes.
@TestOn('vm')
library;

import 'package:test/test.dart';

import '../doc_snippets/loading_data.dart' as loading_data;
import 'scenarios/loading_error_tests.dart';

void main() {
  for (final delay in [Duration.zero, const Duration(milliseconds: 20)]) {
    test(
      'guide failure remains handled with a $delay subscription delay',
      () async {
        Object? receivedError;
        final errors = await captureUnhandledErrors(() async {
          final future = loading_data.futureFor(
            loading_data.SnapshotPreview.error,
          )!;
          await Future<void>.delayed(delay);
          await future.then<void>(
            (_) {},
            onError: (Object error) {
              receivedError = error;
            },
          );
        });
        expect(errors, isEmpty);
        expect(receivedError, isA<StateError>());
        expect(receivedError.toString(), contains('Connection lost'));
      },
    );
  }

  liveLoadingErrorTests();
}
