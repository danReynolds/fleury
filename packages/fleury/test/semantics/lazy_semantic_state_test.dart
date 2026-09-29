import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

class _BuildProbe extends StatelessWidget {
  const _BuildProbe(this.onBuild);
  final void Function() onBuild;
  @override
  Widget build(BuildContext context) {
    onBuild();
    return const Text('unchanged');
  }
}

class _Presenter implements SemanticFramePresenter {
  final trees = <SemanticTree>[];
  @override
  SemanticPresentationStats present(
    SemanticTree tree, {
    SemanticTreeUpdate? update,
  }) {
    trees.add(tree);
    return SemanticPresentationStats.none;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('state source survives a GlobalKey move exactly once', (tester) {
    final source = _CountingSource();
    addTearDown(source.dispose);
    final key = GlobalKey();
    Widget view(bool moved) {
      final live = Semantics(
        key: key,
        id: const SemanticNodeId('moved'),
        role: SemanticRole.region,
        includeChildren: false,
        stateListenable: source,
        stateBuilder: () => SemanticState({'count': source.value}),
        child: const SizedBox(),
      );
      return Row(
        children: [
          SizedBox(child: moved ? const SizedBox() : live),
          SizedBox(child: moved ? live : const SizedBox()),
        ],
      );
    }

    tester.pumpWidget(view(false));
    tester.pumpWidget(view(true));
    expect(source.subscriptions, 1);
    tester.owner.semanticDirtyTracker.takeDirtySnapshot();
    source.value = 4;
    expect(tester.owner.flushBuild().rebuiltElementCount, 0);
    final update = tester.owner.semanticDirtyTracker.takeDirtySnapshot();
    expect(
      update.leafUpdates[const SemanticNodeId('moved')]!.state['count'],
      4,
    );
    tester.pumpWidget(const SizedBox());
    expect(source.subscriptions, 0);
  });

  testWidgets('state is lazy, snapshot-stable, and does not rebuild content', (
    tester,
  ) {
    final model = ValueNotifier(0);
    addTearDown(model.dispose);
    var reads = 0;
    var builds = 0;
    tester.pumpWidget(
      Semantics(
        id: const SemanticNodeId('live'),
        role: SemanticRole.region,
        includeChildren: false,
        stateListenable: model,
        stateBuilder: () {
          reads++;
          return SemanticState({'count': model.value});
        },
        child: _BuildProbe(() => builds++),
      ),
    );
    expect(reads, 0, reason: 'ordinary rendering does not read semantic state');
    final before = tester.semantics().nodeById(const SemanticNodeId('live'))!;
    expect(before.state['count'], 0);
    final initialBuilds = builds;
    tester.owner.semanticDirtyTracker.takeDirtySnapshot();
    model.value = 1;
    expect(tester.owner.flushBuild().rebuiltElementCount, 0);
    final dirty = tester.owner.semanticDirtyTracker.takeDirtySnapshot();
    expect(dirty.leafUpdates[const SemanticNodeId('live')]!.state['count'], 1);
    expect(before.state['count'], 0);
    expect(builds, initialBuilds);
  });

  for (final includeChildren in [false, true]) {
    testWidgets(
      'model-only changes reach a skipped frame, includeChildren=$includeChildren',
      (tester) {
        final model = ValueNotifier(0);
        addTearDown(model.dispose);
        tester.pumpWidget(
          Semantics(
            id: const SemanticNodeId('live'),
            role: SemanticRole.region,
            includeChildren: includeChildren,
            stateListenable: model,
            stateBuilder: () => SemanticState({'count': model.value}),
            child: const Text('retained child'),
          ),
        );
        final presenter = _Presenter();
        final pipeline = FrameSemanticsPipeline(
          presenter: presenter,
          dirtyTracker: tester.owner.semanticDirtyTracker,
          readRoot: () => tester.root,
          coverageFallback: false,
        );
        addTearDown(pipeline.dispose);
        final frame = TuiFrameLoop().render(
          size: const CellSize(4, 1),
          paint: (_) {},
        )!;
        pipeline.onFramePresented(frame, null);
        pipeline.flushPendingNow('initial');
        var requested = 0;
        tester.owner.onScheduleBuild = () => requested++;
        model.value = 7;
        model.value = 9;
        expect(
          requested,
          1,
          reason: 'coalesce until semantics consume the change',
        );
        expect(tester.owner.flushBuild().rebuiltElementCount, 0);
        pipeline.onFrameSkippedWithPendingWork();
        pipeline.flushPendingNow('state');
        expect(
          presenter.trees.last
              .nodeById(const SemanticNodeId('live'))!
              .state['count'],
          9,
        );
        expect(
          presenter.trees.last.nodeById(const SemanticNodeId('live'))!.children,
          includeChildren ? isNotEmpty : isEmpty,
        );
      },
    );
  }

  testWidgets('subscriptions follow source replacement and unmount', (tester) {
    final first = ValueNotifier(0);
    final second = ValueNotifier(0);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget view(ValueNotifier<int> source) => Semantics(
      role: SemanticRole.region,
      stateListenable: source,
      stateBuilder: () => SemanticState({'count': source.value}),
      child: const SizedBox(),
    );
    tester.pumpWidget(view(first));
    expect(first.hasListeners, isTrue);
    tester.pumpWidget(view(second));
    expect(first.hasListeners, isFalse);
    expect(second.hasListeners, isTrue);
    tester.owner.semanticDirtyTracker.takeDirtySnapshot();
    first.value = 3;
    expect(tester.owner.semanticDirtyTracker.hasDirt, isFalse);
    tester.pumpWidget(const SizedBox());
    expect(second.hasListeners, isFalse);
    second.value = 4; // the widget does not own or dispose the source
  });

  testWidgets(
    'state callback failures are deferred until semantic collection',
    (tester) {
      final source = ValueNotifier(0);
      addTearDown(source.dispose);
      tester.pumpWidget(
        Semantics(
          role: SemanticRole.region,
          stateListenable: source,
          stateBuilder: () => throw StateError('state failed'),
          child: const SizedBox(),
        ),
      );
      source.value = 1;
      expect(tester.semantics, throwsStateError);
    },
  );

  test('state configuration rejects ambiguous sources', () {
    expect(
      () => Semantics(
        role: SemanticRole.region,
        state: const SemanticState(),
        stateBuilder: () => const SemanticState(),
        child: const SizedBox(),
      ),
      throwsA(isA<AssertionError>()),
    );
    final source = ValueNotifier(0);
    addTearDown(source.dispose);
    expect(
      () => Semantics(
        role: SemanticRole.region,
        stateListenable: source,
        child: const SizedBox(),
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}

class _CountingSource extends ValueNotifier<int> {
  _CountingSource() : super(0);
  int subscriptions = 0;
  @override
  void addListener(void Function() listener) {
    subscriptions++;
    super.addListener(listener);
  }

  @override
  void removeListener(void Function() listener) {
    subscriptions--;
    super.removeListener(listener);
  }
}
