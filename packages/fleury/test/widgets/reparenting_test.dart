import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

/// A stateful probe that records its lifecycle calls (statically, so a
/// fresh-from-scratch rebuild is distinguishable from a reparent) and holds
/// a counter so we can prove the *same* state survived a move.
class _Probe extends StatefulWidget {
  const _Probe({super.key});
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  static int initCount = 0;
  static int disposeCount = 0;
  static int activateCount = 0;
  static int deactivateCount = 0;

  static void reset() {
    initCount = 0;
    disposeCount = 0;
    activateCount = 0;
    deactivateCount = 0;
  }

  int count = 0;
  void bump() => setState(() => count++);

  @override
  void initState() {
    super.initState();
    initCount++;
  }

  @override
  void activate() {
    super.activate();
    activateCount++;
  }

  @override
  void deactivate() {
    deactivateCount++;
    super.deactivate();
  }

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('count=$count');
}

/// Hosts the probe under one of two distinct parents and flips between them
/// on [swap]. With [multiChild] true the parents are `Row`s (multi-child
/// render-object elements); otherwise they are `Center`s (single-child).
class _Reparent extends StatefulWidget {
  const _Reparent({
    super.key,
    required this.probeKey,
    required this.multiChild,
  });
  final GlobalKey<_ProbeState> probeKey;
  final bool multiChild;
  @override
  State<_Reparent> createState() => _ReparentState();
}

class _ReparentState extends State<_Reparent> {
  bool first = true;
  void swap() => setState(() => first = !first);

  @override
  Widget build(BuildContext context) {
    final probe = _Probe(key: widget.probeKey);
    if (widget.multiChild) {
      return Column(
        children: [
          Row(children: first ? [probe] : const [Text('-')]),
          Row(children: first ? const [Text('-')] : [probe]),
        ],
      );
    }
    return Column(
      children: [
        Center(child: first ? probe : const Text('-')),
        Center(child: first ? const Text('-') : probe),
      ],
    );
  }
}

/// An inherited value used to prove a moved widget re-resolves its
/// dependencies against the new ancestor chain.
class _Tag extends InheritedWidget {
  const _Tag({required this.label, required super.child});
  final String label;
  static String of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<_Tag>()!.label;
  @override
  bool updateShouldNotify(_Tag old) => old.label != label;
}

/// Reads the ambient [_Tag] and counts dependency-change notifications.
class _DepProbe extends StatefulWidget {
  const _DepProbe({super.key});
  @override
  State<_DepProbe> createState() => _DepProbeState();
}

class _DepProbeState extends State<_DepProbe> {
  int depChanges = 0;
  String tag = '?';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    depChanges++;
  }

  @override
  Widget build(BuildContext context) {
    tag = _Tag.of(context);
    return Text('tag=$tag');
  }
}

/// Hosts a [_DepProbe] under one of two distinct [_Tag] subtrees.
class _DepHost extends StatefulWidget {
  const _DepHost({super.key, required this.probeKey});
  final GlobalKey<_DepProbeState> probeKey;
  @override
  State<_DepHost> createState() => _DepHostState();
}

class _DepHostState extends State<_DepHost> {
  bool first = true;
  void swap() => setState(() => first = !first);
  @override
  Widget build(BuildContext context) {
    final probe = _DepProbe(key: widget.probeKey);
    return Column(
      children: [
        _Tag(
          label: 'A',
          child: Center(child: first ? probe : const Text('-')),
        ),
        _Tag(
          label: 'B',
          child: Center(child: first ? const Text('-') : probe),
        ),
      ],
    );
  }
}

/// Moves the probe between a MultiChild parent (`Row`) and a SingleChild
/// parent (`Center`) to cover the cross-parent-type attach/detach paths.
class _MixedHost extends StatefulWidget {
  const _MixedHost({super.key, required this.probeKey});
  final GlobalKey<_ProbeState> probeKey;
  @override
  State<_MixedHost> createState() => _MixedHostState();
}

class _MixedHostState extends State<_MixedHost> {
  bool first = true;
  void swap() => setState(() => first = !first);
  @override
  Widget build(BuildContext context) {
    final probe = _Probe(key: widget.probeKey);
    return Column(
      children: [
        Row(children: first ? [probe] : const [Text('-')]),
        Center(child: first ? const Text('-') : probe),
      ],
    );
  }
}

/// A probe carrying a configuration field, to verify didUpdateWidget fires
/// (with the prior config) when a global-keyed widget is reparented with a
/// changed configuration.
class _ConfigProbe extends StatefulWidget {
  const _ConfigProbe({super.key, required this.slot});
  final String slot;
  @override
  State<_ConfigProbe> createState() => _ConfigProbeState();
}

class _ConfigProbeState extends State<_ConfigProbe> {
  final List<String> oldSlots = [];
  @override
  void didUpdateWidget(_ConfigProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldSlots.add(oldWidget.slot);
  }

  @override
  Widget build(BuildContext context) => Text('slot=${widget.slot}');
}

class _ConfigHost extends StatefulWidget {
  const _ConfigHost({super.key, required this.probeKey});
  final GlobalKey<_ConfigProbeState> probeKey;
  @override
  State<_ConfigHost> createState() => _ConfigHostState();
}

class _ConfigHostState extends State<_ConfigHost> {
  bool first = true;
  void swap() => setState(() => first = !first);
  @override
  Widget build(BuildContext context) {
    // The slot prop tracks position, so a move also changes configuration.
    final probe = _ConfigProbe(key: widget.probeKey, slot: first ? 'A' : 'B');
    return Column(
      children: [
        Center(child: first ? probe : const Text('-')),
        Center(child: first ? const Text('-') : probe),
      ],
    );
  }
}

/// Hosts a CACHED, identical [LayoutBuilder] instance inside a GlobalKey'd
/// wrapper that moves between two [_Tag] subtrees. Because the child instance
/// is identical across the wrapper's rebuilds, `updateChild` SKIPS it on the
/// move — so re-registering the builder's severed inherited dependency depends
/// on reactivation forcing a rebuild (an element that had dependencies when
/// deactivated must rebuild on activate). The builder reads `_Tag.of(ctx)`, so
/// the LayoutBuilder element itself carries the dependency.
class _CachedLbHost extends StatefulWidget {
  const _CachedLbHost({super.key, required this.wrapperKey});
  final GlobalKey wrapperKey;
  @override
  State<_CachedLbHost> createState() => _CachedLbHostState();
}

class _CachedLbHostState extends State<_CachedLbHost> {
  late final Widget _lb = LayoutBuilder(
    builder: (ctx, c) => Text('tag=${_Tag.of(ctx)}'),
  );
  bool first = true;
  void swap() => setState(() => first = !first);
  @override
  Widget build(BuildContext context) {
    final wrapper = Center(key: widget.wrapperKey, child: _lb);
    return Column(
      children: [
        _Tag(
          label: 'A',
          child: Center(child: first ? wrapper : const Text('-')),
        ),
        _Tag(
          label: 'B',
          child: Center(child: first ? const Text('-') : wrapper),
        ),
      ],
    );
  }
}

/// A LayoutBuilder whose builder output is a GlobalKey'd probe that another
/// slot then reclaims — exercising _LayoutBuilderElement.forgetChild (the
/// built child must be cleared when its element moves out, or the next build
/// updateChild()s an element now active elsewhere).
class _LbForgetHost extends StatefulWidget {
  const _LbForgetHost({super.key, required this.probeKey});
  final GlobalKey<_ProbeState> probeKey;
  @override
  State<_LbForgetHost> createState() => _LbForgetHostState();
}

class _LbForgetHostState extends State<_LbForgetHost> {
  bool inLb = true;
  void moveOut() => setState(() => inLb = false);
  @override
  Widget build(BuildContext context) {
    final probe = _Probe(key: widget.probeKey);
    return Column(
      children: [
        LayoutBuilder(builder: (ctx, c) => inLb ? probe : const Text('-')),
        inLb ? const Text('-') : probe,
      ],
    );
  }
}

List<String> _lines(FleuryTester tester) {
  final lines = tester
      .renderToString(size: const CellSize(10, 2))
      .split('\n')
      .map((l) => l.trimRight())
      .toList();
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines;
}

void main() {
  setUp(_ProbeState.reset);

  for (final multiChild in [true, false]) {
    final kind = multiChild ? 'MultiChild (Row)' : 'SingleChild (Center)';

    testWidgets('reparenting across $kind parents preserves state', (tester) {
      final swapKey = GlobalKey<_ReparentState>();
      final probeKey = GlobalKey<_ProbeState>();
      tester.pumpWidget(
        _Reparent(key: swapKey, probeKey: probeKey, multiChild: multiChild),
      );

      final probe = probeKey.currentState!;
      probe.bump();
      probe.bump();
      tester.pump();
      expect(probeKey.currentState!.count, 2);
      expect(_ProbeState.initCount, 1);
      expect(_lines(tester), [
        'count=2',
        '-',
      ], reason: 'probe starts in slot A');

      // A -> B. Slot A (built first) is the *old* parent: it deactivates the
      // probe, then slot B reclaims it from the inactive set.
      swapKey.currentState!.swap();
      tester.pump();
      expect(
        identical(probeKey.currentState, probe),
        isTrue,
        reason: 'the same State object survived the move',
      );
      expect(
        probeKey.currentState!.count,
        2,
        reason: 'state preserved — a rebuild-from-scratch would reset to 0',
      );
      expect(_ProbeState.initCount, 1, reason: 'moved, not recreated');
      expect(_ProbeState.disposeCount, 0, reason: 'not disposed mid-move');
      expect(_ProbeState.deactivateCount, 1);
      expect(_ProbeState.activateCount, 1);
      expect(_lines(tester), ['-', 'count=2'], reason: 'probe now in slot B');

      // Still live after the move.
      probe.bump();
      tester.pump();
      expect(probeKey.currentState!.count, 3);

      // B -> A. Slot A (built first) is now the *new* parent: it reclaims the
      // probe while it is still active under slot B (exercises forgetChild +
      // deactivate-from-old-parent at retake time).
      swapKey.currentState!.swap();
      tester.pump();
      expect(identical(probeKey.currentState, probe), isTrue);
      expect(probeKey.currentState!.count, 3);
      expect(_ProbeState.initCount, 1);
      expect(_ProbeState.disposeCount, 0);
      expect(_ProbeState.deactivateCount, 2);
      expect(_ProbeState.activateCount, 2);
      expect(_lines(tester), ['count=3', '-']);

      // Removing the host entirely finalizes the probe for good.
      tester.pumpWidget(const Text('gone'));
      expect(probeKey.currentState, isNull);
      expect(_ProbeState.disposeCount, 1);
    });
  }

  testWidgets(
    'a global-keyed subtree carries its descendants when reparented',
    (tester) {
      // The probe is nested below a non-keyed wrapper so the moved unit spans
      // more than one element / render object.
      final swapKey = GlobalKey<_ReparentState>();
      final probeKey = GlobalKey<_ProbeState>();
      tester.pumpWidget(
        _Reparent(key: swapKey, probeKey: probeKey, multiChild: true),
      );
      probeKey.currentState!.bump();
      tester.pump();

      final stateBefore = probeKey.currentState;
      swapKey.currentState!.swap();
      tester.pump();
      expect(identical(probeKey.currentState, stateBefore), isTrue);
      expect(probeKey.currentState!.count, 1);
    },
  );

  testWidgets('a moved widget re-resolves inherited dependencies at its new '
      'position', (tester) {
    final hostKey = GlobalKey<_DepHostState>();
    final probeKey = GlobalKey<_DepProbeState>();
    tester.pumpWidget(_DepHost(key: hostKey, probeKey: probeKey));

    final probe = probeKey.currentState!;
    expect(probe.tag, 'A', reason: 'reads the _Tag above its first slot');
    expect(probe.depChanges, 1, reason: 'initial didChangeDependencies');

    hostKey.currentState!.swap();
    tester.pump();
    expect(
      identical(probeKey.currentState, probe),
      isTrue,
      reason: 'same State — it moved, not rebuilt',
    );
    expect(
      probe.tag,
      'B',
      reason: 'now reads the _Tag above its new slot, not the stale one',
    );
    expect(
      probe.depChanges,
      2,
      reason: 'didChangeDependencies fires for the move',
    );

    // The old _Tag must no longer drive this widget: rebuilding it (here, by
    // moving back) must not double-notify or resurrect the stale value.
    hostKey.currentState!.swap();
    tester.pump();
    expect(probe.tag, 'A');
    expect(probe.depChanges, 3);
  });

  testWidgets('reparenting between a MultiChild and a SingleChild parent '
      'preserves state', (tester) {
    final hostKey = GlobalKey<_MixedHostState>();
    final probeKey = GlobalKey<_ProbeState>();
    tester.pumpWidget(_MixedHost(key: hostKey, probeKey: probeKey));

    final probe = probeKey.currentState!;
    probe.bump();
    tester.pump();
    expect(_lines(tester), ['count=1', '-'], reason: 'starts in the Row');

    hostKey.currentState!.swap(); // Row -> Center
    tester.pump();
    expect(identical(probeKey.currentState, probe), isTrue);
    expect(probeKey.currentState!.count, 1);
    expect(_ProbeState.initCount, 1);
    expect(_ProbeState.disposeCount, 0);
    expect(_lines(tester), ['-', 'count=1'], reason: 'now in the Center');

    hostKey.currentState!.swap(); // Center -> Row
    tester.pump();
    expect(identical(probeKey.currentState, probe), isTrue);
    expect(probeKey.currentState!.count, 1);
    expect(_lines(tester), ['count=1', '-']);
  });

  testWidgets('a moved subtree re-registers a SKIPPED child\'s severed '
      'inherited dependency (cached identical LayoutBuilder)', (tester) {
    final wrapperKey = GlobalKey();
    final hostKey = GlobalKey<_CachedLbHostState>();
    tester.pumpWidget(_CachedLbHost(key: hostKey, wrapperKey: wrapperKey));
    expect(_lines(tester), ['tag=A', '-'], reason: 'reads _Tag above slot A');

    // Move the wrapper A -> B. Its cached child (the LayoutBuilder) is the same
    // instance, so updateChild skips it — only reactivation forcing a rebuild
    // re-reads _Tag. Pre-fix this stayed 'tag=A' (dep severed, never re-run).
    hostKey.currentState!.swap();
    tester.pump();
    expect(
      _lines(tester),
      ['-', 'tag=B'],
      reason: 'the skipped child re-resolved _Tag at its new position',
    );

    // And back, to prove the old _Tag no longer drives it.
    hostKey.currentState!.swap();
    tester.pump();
    expect(_lines(tester), ['tag=A', '-']);
  });

  testWidgets('a GlobalKey child of a LayoutBuilder reclaimed by another slot '
      'clears the builder\'s reference (forgetChild)', (tester) {
    final hostKey = GlobalKey<_LbForgetHostState>();
    final probeKey = GlobalKey<_ProbeState>();
    tester.pumpWidget(_LbForgetHost(key: hostKey, probeKey: probeKey));
    // The LB builds its child during layout, so render before reaching in.
    _lines(tester);
    probeKey.currentState!.bump();
    expect(_lines(tester), ['count=1', '-'], reason: 'probe built by the LB');
    final probe = probeKey.currentState!;

    // Reclaim the probe into the sibling slot; the LayoutBuilder now builds
    // Text('-'). Without forgetChild, the LB's stale _child pointer would make
    // the next builder run updateChild() an element active elsewhere.
    hostKey.currentState!.moveOut();
    tester.pump();
    expect(
      identical(probeKey.currentState, probe),
      isTrue,
      reason: 'the probe moved (same State), was not recreated',
    );
    expect(probeKey.currentState!.count, 1, reason: 'state survived the move');
    expect(
      _lines(tester),
      ['-', 'count=1'],
      reason: 'LB shows its new child; probe renders in the sibling slot',
    );
  });

  testWidgets('a reparent with a changed configuration fires didUpdateWidget', (
    tester,
  ) {
    final hostKey = GlobalKey<_ConfigHostState>();
    final probeKey = GlobalKey<_ConfigProbeState>();
    tester.pumpWidget(_ConfigHost(key: hostKey, probeKey: probeKey));

    final probe = probeKey.currentState!;
    expect(probe.widget.slot, 'A');
    expect(probe.oldSlots, isEmpty, reason: 'no update yet');

    hostKey.currentState!.swap(); // moves A -> B, slot prop changes A -> B
    tester.pump();
    expect(identical(probeKey.currentState, probe), isTrue);
    expect(probe.widget.slot, 'B', reason: 'new configuration applied');
    expect(
      probe.oldSlots,
      ['A'],
      reason: 'didUpdateWidget saw the prior configuration across the move',
    );
  });
}
