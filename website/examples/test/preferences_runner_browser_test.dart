@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:test/test.dart';

import '../web/preferences_test.dart' as runner;

@JS('fleuryCreatePreferencesTest')
external JSObject _createRun();

Future<JSObject> _next(JSObject run) =>
    run.callMethod<JSPromise<JSObject>>('next'.toJS).toDart;

void _dispose(JSObject run) => run.callMethod<JSAny?>('dispose'.toJS);

void main() {
  setUp(runner.main);

  test('browser runner executes seven steps and four assertions', () async {
    final run = _createRun();
    addTearDown(() => _dispose(run));
    var steps = 0;
    var assertions = 0;
    String lastFrame = '';
    while (true) {
      final step = await _next(run);
      if ((step['done'] as JSBoolean).toDart) break;
      steps++;
      if ((step['assertion'] as JSBoolean).toDart) assertions++;
      lastFrame = (step['html'] as JSString).toDart;
    }
    expect(steps, 7);
    expect(assertions, 4);
    expect(lastFrame, contains('Updates for Ada'));
    expect(lastFrame, contains('Email updates off'));
  });

  test('stopping and replaying gives the next run fresh forms', () async {
    final first = _createRun();
    await _next(first);
    await _next(first);
    _dispose(first);
    _dispose(first); // Teardown is idempotent.
    await expectLater(_next(first), throwsA(anything));

    final replay = _createRun();
    addTearDown(() => _dispose(replay));
    final initial = await _next(replay);
    expect((initial['html'] as JSString).toDart, isNot(contains('Ada')));
    expect((initial['label'] as JSString).toDart, 'Start with two fresh forms');
  });
}
