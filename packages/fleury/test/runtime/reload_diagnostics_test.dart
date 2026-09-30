import 'package:fleury/src/runtime/runtime_error_overlay.dart';
import 'package:test/test.dart';

void main() {
  test('failed edits retain history without a fake stack or runtime storm', () {
    final logs = <String>[];
    final reporter = RuntimeErrorReporter(
      onLog: logs.add,
      autoDismiss: Duration.zero,
    );
    addTearDown(reporter.dispose);
    for (var i = 0; i < 55; i++) {
      reporter.reportReloadFailure(
        'Hot reload failed: lib/app.dart:$i:1: Error',
      );
    }
    expect(reporter.isStorming, isFalse);
    expect(reporter.history, hasLength(50));
    expect(reporter.history.first.error.toString(), contains('app.dart:5:1'));
    expect(reporter.current!.stackTrace.toString(), isEmpty);
    expect(reporter.current!.isReloadFailure, isTrue);
    expect(logs, hasLength(55));
    expect(logs.join(), isNot(contains('Uncaught runtime error')));
    expect(logs.join(), isNot(contains('Bad state')));

    reporter.dismissReloadFailure();
    expect(reporter.current, isNull);
    expect(reporter.history, hasLength(50));
  });

  test('successful reload does not dismiss a newer application exception', () {
    final logs = <String>[];
    final reporter = RuntimeErrorReporter(
      onLog: logs.add,
      autoDismiss: Duration.zero,
    );
    addTearDown(reporter.dispose);
    reporter.reportReloadFailure('Hot reload failed');
    reporter.report(
      StateError('save failed'),
      StackTrace.fromString('app.dart:42'),
    );
    reporter.dismissReloadFailure();
    expect(reporter.current!.error, isA<StateError>());
    expect(reporter.current!.isReloadFailure, isFalse);
    expect(logs.last, contains('Uncaught runtime error'));
    expect(logs.last, contains('app.dart:42'));
  });

  test('failed edits do not hide a genuine application error storm', () {
    final reporter = RuntimeErrorReporter(autoDismiss: Duration.zero);
    addTearDown(reporter.dispose);
    for (var i = 0; i < 24; i++) {
      reporter.report(StateError('loop'), StackTrace.empty);
      reporter.reportReloadFailure('Hot reload failed');
    }
    expect(reporter.isStorming, isTrue);
  });

  test('late reload reports do not revive a disposed reporter', () {
    final logs = <String>[];
    final reporter = RuntimeErrorReporter(onLog: logs.add)..dispose();
    reporter.reportReloadFailure('too late');
    reporter.dismissReloadFailure();
    expect(logs, isEmpty);
    expect(reporter.history, isEmpty);
    expect(reporter.current, isNull);
  });
}
