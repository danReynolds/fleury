// FrameSemanticsPipeline: the shared semantics engine every structured
// surface (embed, serve, web backend) runs. These pin two engine contracts
// that hosts depend on but no host-level test covered:
//   - dispose() completes any outstanding awaitIdle() future (teardown race);
//   - an input-dirtied frame takes the full tree walk, so a contributor whose
//     live state the dirty tracker never saw is not shipped stale via the
//     retained-leaf fast path.

import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

class _CapturingPresenter implements SemanticFramePresenter {
  final List<SemanticTree> presented = <SemanticTree>[];

  @override
  SemanticPresentationStats present(
    SemanticTree tree, {
    SemanticTreeUpdate? update,
  }) {
    presented.add(tree);
    return SemanticPresentationStats.none;
  }

  @override
  Future<void> dispose() async {}
}

TuiRenderedFrame _renderFrame() {
  final loop = TuiFrameLoop();
  return loop.render(size: const CellSize(4, 1), paint: (_) {})!;
}

/// A semantic contributor whose node content is derived from [value] read LIVE
/// at collection time, and which records NO semantic dirt when [value] changes.
///
/// This reproduces first-party contributors (`DataTable`, the app/command
/// scopes) whose `buildSemanticNode` reads live render/controller state the
/// [SemanticDirtyTracker] never observes — the class of node that goes stale
/// when a sibling leaf (a `Text`) takes the retained-leaf fast path.
final class _LiveContributorWidget extends ProxyWidget {
  const _LiveContributorWidget({
    required this.nodeId,
    required this.value,
    required super.child,
  });

  final String nodeId;
  final String value;

  @override
  Element createElement() => _LiveContributorElement(this);
}

final class _LiveContributorElement extends ComponentElement
    implements SemanticContributor, SemanticChildrenProvider {
  _LiveContributorElement(_LiveContributorWidget super.widget);

  @override
  _LiveContributorWidget get widget => super.widget as _LiveContributorWidget;

  @override
  void update(covariant _LiveContributorWidget newWidget) {
    super.update(newWidget);
    // Reconcile the child so a sibling leaf change is picked up — but
    // DELIBERATELY record no semantic dirt of our own, so the tracker never
    // learns our node's live [value] changed.
    rebuild(force: true);
  }

  @override
  Widget buildChild() => widget.child;

  @override
  void visitSemanticChildren(void Function(Element child) visitor) =>
      visitChildren(visitor);

  @override
  SemanticNode buildSemanticNode(List<SemanticNode> children) {
    return SemanticNode(
      id: SemanticNodeId(widget.nodeId),
      role: SemanticRole.region,
      label: widget.value,
      value: widget.value,
      children: children,
    );
  }
}

void main() {
  test(
    'dispose completes a pending awaitIdle instead of stranding it',
    () async {
      final pipeline = FrameSemanticsPipeline(
        presenter: _CapturingPresenter(),
        dirtyTracker: SemanticDirtyTracker(),
        readRoot: () => null,
        // A real timer we never pump: the flush stays outstanding until
        // dispose cancels it, exactly like the embed host teardown race.
        flushScheduler: TimerSemanticFlushScheduler(),
        coverageFallback: false,
      );

      // A frame with pending semantic work schedules a deferred flush, so
      // awaitIdle() returns a still-pending future (its only pending state).
      pipeline.onFramePresented(_renderFrame(), null);

      var completed = false;
      // ignore: unawaited_futures
      pipeline.awaitIdle().then((_) => completed = true);

      // Teardown before the deferred flush runs: dispose cancels the flush.
      // It must still complete the outstanding awaitIdle (the documented
      // dispose-completes-pending contract) rather than hang the caller.
      pipeline.dispose();
      await pumpEventQueue();

      expect(
        completed,
        isTrue,
        reason: 'dispose must complete outstanding awaitIdle futures',
      );
    },
  );

  testWidgets(
    'an input-dirtied frame full-walks so an untracked contributor is not '
    'shipped stale via the retained-leaf path',
    (tester) {
      final presenter = _CapturingPresenter();
      final pipeline = FrameSemanticsPipeline(
        presenter: presenter,
        dirtyTracker: tester.owner.semanticDirtyTracker,
        readRoot: () => tester.root,
        flushScheduler: MicrotaskSemanticFlushScheduler(),
        // Coverage fallback is orthogonal here; disabling it isolates the
        // retained-leaf-vs-full-walk decision from text-coverage state.
        coverageFallback: false,
      );

      Widget build({required String contrib, required String leaf}) {
        return _LiveContributorWidget(
          nodeId: 'contrib',
          value: contrib,
          child: Semantics(
            id: const SemanticNodeId('leaf'),
            role: SemanticRole.text,
            label: leaf,
            includeChildren: false,
            child: const SizedBox(),
          ),
        );
      }

      // Frame 1 establishes the retained tree: contributor 'A', leaf 'X'.
      tester.pumpWidget(build(contrib: 'A', leaf: 'X'));
      pipeline.onFramePresented(_renderFrame(), null);
      pipeline.flushNow('t1');
      expect(
        presenter.presented.last.nodeById(const SemanticNodeId('contrib'))?.label,
        'A',
      );

      // Frame 2: the contributor's live value changes to 'B' (recording no
      // dirt) IN THE SAME frame the leaf changes to 'Y' (a recorded leaf
      // update). markSemanticsDirty models run_app's per-input-dispatch mark:
      // "handler state may have changed invisibly, so take the full walk."
      tester.pumpWidget(build(contrib: 'B', leaf: 'Y'));
      pipeline.markSemanticsDirty();
      pipeline.onFramePresented(_renderFrame(), null);

      // Under the bug the retained-leaf path patches only the leaf, leaving
      // the contributor node stale — which the divergence oracle throws on in
      // debug, or ships stale in release. The full walk must run instead.
      pipeline.flushNow('t2');

      final contribNode = presenter.presented.last.nodeById(
        const SemanticNodeId('contrib'),
      );
      expect(
        contribNode?.label,
        'B',
        reason: 'the untracked contributor must reflect its live state, not a '
            'stale retained node',
      );
      final leafNode = presenter.presented.last.nodeById(
        const SemanticNodeId('leaf'),
      );
      expect(leafNode?.label, 'Y');
    },
  );
}
