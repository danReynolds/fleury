// Teardown of an element whose inflate threw must not compound the error.
//
// `RenderObjectElement.renderObject` throws when the element never got a
// render object — a `createRenderObject` that threw. Teardown overrides that
// reached it (`unmount`/`deactivate` releasing a registration) raised a
// second, misleading StateError on top of the original while the tree was
// already unwinding.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

class _BoomAnchor extends BoundsAnchor {
  const _BoomAnchor({required super.notifier, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      throw StateError('boom');
}

void main() {
  testWidgets('a BoundsAnchor whose inflate threw tears down without a '
      'second error', (tester) {
    final chip = BoundsNotifier();
    expect(
      () => tester.pumpWidget(
        _BoomAnchor(notifier: chip, child: const Text('x')),
      ),
      throwsA(isA<StateError>().having((e) => e.message, 'message', 'boom')),
      reason: 'the inflate error itself surfaces',
    );

    // Replacing the tree unmounts the failed element. That must be the end
    // of it — not a second StateError from a teardown override reaching for
    // a render object that never existed.
    tester.pumpWidget(const Text('after'));
    tester.render(size: const CellSize(10, 2));
  });
}
