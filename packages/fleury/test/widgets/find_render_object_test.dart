// Tests for BuildContext.findRenderObject — the bridge between the
// element tree and painted geometry.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

/// Captures its build context once per build so a test can later call
/// `findRenderObject()` from outside the build itself.
class _ContextHolder extends StatelessWidget {
  const _ContextHolder({required this.onBuild, required this.child});
  final void Function(BuildContext) onBuild;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    onBuild(context);
    return child;
  }
}

class _RecordSize extends StatefulWidget {
  const _RecordSize({required this.onPostFrame});
  final void Function(BuildContext) onPostFrame;

  @override
  State<_RecordSize> createState() => _RecordSizeState();
}

class _RecordSizeState extends State<_RecordSize> {
  @override
  void initState() {
    super.initState();
    TuiBinding.of(context).addPostFrameCallback((_) {
      if (mounted) widget.onPostFrame(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 12, height: 4, child: Text('hi'));
  }
}

void main() {
  group('BuildContext.findRenderObject', () {
    testWidgets(
      'returns the nearest descendant RO for a Padding-wrapped Text',
      (tester) {
        BuildContext? captured;
        tester.pumpWidget(
          _ContextHolder(
            onBuild: (ctx) => captured = ctx,
            child: const Padding(padding: EdgeInsets.all(2), child: Text('hi')),
          ),
        );
        tester.render(size: const CellSize(20, 5));
        final ro = captured!.findRenderObject();
        expect(ro, isNotNull);
        expect(ro!.size.cols, greaterThan(0));
        expect(ro.size.rows, greaterThan(0));
      },
    );

    testWidgets(
      'returns null when the underlying element is no longer mounted',
      (tester) {
        BuildContext? captured;
        tester.pumpWidget(
          _ContextHolder(
            onBuild: (ctx) => captured = ctx,
            child: const Text('hi'),
          ),
        );
        // Replace the user widget with something that doesn't include
        // _ContextHolder. The old element unmounts.
        tester.pumpWidget(const Text('replaced'));
        expect(captured!.mounted, isFalse);
        expect(captured!.findRenderObject(), isNull);
      },
    );

    testWidgets('works inside a post-frame callback to read painted size', (
      tester,
    ) {
      CellSize? sizeFromCallback;
      tester.pumpWidget(
        _RecordSize(
          onPostFrame: (ctx) {
            // The runtime's renderFrame would have laid out before draining;
            // the test mirrors that by rendering first (see render() below).
            sizeFromCallback = ctx.findRenderObject()?.size;
          },
        ),
      );
      // Lay out + paint, then pump drains the post-frame queue.
      tester.render();
      tester.pump();
      expect(sizeFromCallback, isNotNull);
      // SizedBox(width: 12, height: 4) → at least 12×4.
      expect(sizeFromCallback!.cols, 12);
      expect(sizeFromCallback!.rows, 4);
    });

    testWidgets('returns null when no descendant render object exists', (
      tester,
    ) {
      // EmptyBox is a non-render leaf — by design it produces no render
      // object so it doesn't claim cells. A context whose only
      // descendant is an EmptyBox has nothing to find.
      BuildContext? captured;
      tester.pumpWidget(
        _ContextHolder(
          onBuild: (ctx) => captured = ctx,
          child: const EmptyBox(),
        ),
      );
      expect(captured!.findRenderObject(), isNull);
    });

    testWidgets('returns null when called pre-first-build', (tester) {
      // A StatefulElement's State.context is reachable from initState,
      // but at that moment the child hasn't been built yet — there's no
      // descendant render object.
      RenderObject? roInInitState;
      bool initStateRan = false;
      tester.pumpWidget(
        _CapturePreBuildContext(
          onInitState: (ctx) {
            initStateRan = true;
            roInInitState = ctx.findRenderObject();
          },
        ),
      );
      expect(initStateRan, isTrue);
      expect(roInInitState, isNull);
    });

    testWidgets(
      'skips defunct descendants while still walking active subtrees',
      (tester) {
        // The walk in `findRootRenderObject` previously recursed into every
        // child. A defunct (unmounted) descendant has no live render
        // object, so probing it could yield a stale reference. The guard
        // skips defunct children — inactive (mid-activate) children are
        // still walked so a global-keyed move stays findable.
        BuildContext? topCtx;
        tester.pumpWidget(
          _ContextHolder(
            onBuild: (ctx) => topCtx = ctx,
            child: const Padding(padding: EdgeInsets.all(1), child: Text('hi')),
          ),
        );
        tester.render(size: const CellSize(10, 3));

        // After this pump the original subtree is replaced; the old
        // _ContextHolder element is unmounted (defunct).
        tester.pumpWidget(const Text('replaced'));
        // Asking findRenderObject on the old context must return null
        // (defunct branch) and NOT walk into a freed render object.
        expect(topCtx!.findRenderObject(), isNull);
      },
    );
  });
}

class _CapturePreBuildContext extends StatefulWidget {
  const _CapturePreBuildContext({required this.onInitState});
  final void Function(BuildContext) onInitState;

  @override
  State<_CapturePreBuildContext> createState() =>
      _CapturePreBuildContextState();
}

class _CapturePreBuildContextState extends State<_CapturePreBuildContext> {
  @override
  void initState() {
    super.initState();
    widget.onInitState(context);
  }

  @override
  Widget build(BuildContext context) => const Text('child');
}
