@TestOn('vm')
library;

// Regression guard for the served "screen clears when I hit Cancel" bug.
//
// The Dialog story (`_OverlayStory`) returns a `Toaster` whose child triggers
// `Toaster.show(context, …)` — but `context` is the story's *build* context,
// which sits ABOVE that Toaster, so the ancestor lookup finds nothing and
// throws `Bad state: No Toaster above this BuildContext`. That unhandled async
// exception tears the whole session down; over `fleury serve` it drops the
// socket and blanks the browser until reload.
//
// StorybookApp wraps the entire app in a Toaster, which sits above every
// story's build context, so the call resolves. These tests pin both the bug
// (no app-wide Toaster -> throws) and the fix (app-wide Toaster -> resolves),
// using the exact shape that bit us: a build context above a child Toaster.

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

class _Capture extends StatelessWidget {
  const _Capture(this.sink);
  final Widget Function(BuildContext) sink;
  @override
  Widget build(BuildContext context) => sink(context);
}

void main() {
  testWidgets(
      'Toaster.show from a build context above a child Toaster throws without '
      'an app-wide Toaster (the Dialog-story crash)', (tester) {
    late BuildContext storyBuildContext;
    tester.pumpWidget(
      _Capture((context) {
        // Same shape as _OverlayStory.build: this context is the parent of the
        // Toaster it returns, so it has no Toaster ancestor of its own.
        storyBuildContext = context;
        return const Toaster(child: Text('story body'));
      }),
    );
    tester.render(size: const CellSize(40, 10));

    expect(
      () => Toaster.show(storyBuildContext, 'Dialog result: cancelled'),
      throwsA(isA<StateError>()),
      reason: 'reproduces the unhandled exception that crashed the session',
    );
  });

  testWidgets(
      'an app-wide Toaster above the story build context resolves the call',
      (tester) {
    late BuildContext storyBuildContext;
    Object? thrown;
    tester.pumpWidget(
      // The StorybookApp fix: a Toaster wrapping the whole app, above every
      // story's build context.
      _Capture((outer) {
        return Toaster(
          child: _Capture((context) {
            storyBuildContext = context;
            return const Toaster(child: Text('story body'));
          }),
        );
      }),
    );
    tester.render(size: const CellSize(40, 10));

    try {
      Toaster.show(storyBuildContext, 'Dialog result: cancelled');
    } catch (e) {
      thrown = e;
    }
    expect(thrown, isNull,
        reason: 'app-wide Toaster resolves the story build context');
  });
}
