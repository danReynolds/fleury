// Loaded only when a reader runs the Preferences test. The ordinary examples
// bundle does not include the test harness or matcher dependencies.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:fleury/fleury_core.dart';
import 'package:fleury_test/fleury_test.dart';
// Internal docs tooling: reuse the browser renderer's escaped cell markup.
import 'package:fleury_web/src/dom_grid/cell_grid_html.dart';
import 'package:test/test.dart' show Matcher, StringDescription, TestFailure;

import '../test/scenarios/preferences_test.dart';

@JS('fleuryCreatePreferencesTest')
external set _createPreferencesTest(JSFunction value);

void main() {
  _createPreferencesTest = (() {
    final tester = FleuryTester(viewportSize: const CellSize(32, 11));
    final steps = StreamIterator(runPreferencesTest(tester, expect: _expect));
    var disposed = false;
    final handle = JSObject();
    Future<JSObject> next() async {
      if (disposed) throw StateError('The test has been stopped.');
      final more = await steps.moveNext();
      final result = JSObject();
      result['done'] = (!more).toJS;
      if (more) {
        final step = steps.current;
        result['label'] = step.label.toJS;
        result['code'] = step.code.toJS;
        result['assertion'] = step.assertion.toJS;
        result['html'] = renderFrameHtml(tester.render()).toJS;
      }
      return result;
    }

    handle['next'] = (() => next().toJS).toJS;
    handle['dispose'] = (() {
      if (disposed) return;
      disposed = true;
      unawaited(steps.cancel().whenComplete(tester.dispose));
    }).toJS;
    return handle;
  }).toJS;
}

// package:test's expect needs a running test zone. Here we evaluate the same
// synchronous Matcher contract and throw a real TestFailure on mismatch.
void _expect(Object? actual, Matcher matcher) {
  final state = <Object?, Object?>{};
  if (matcher.matches(actual, state)) return;
  final expected = matcher.describe(StringDescription());
  final mismatch = matcher.describeMismatch(
    actual,
    StringDescription(),
    state,
    false,
  );
  throw TestFailure('Expected: $expected\n$mismatch');
}
