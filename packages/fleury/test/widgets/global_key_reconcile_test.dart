import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

/// Pins the four GlobalKey reconciliation findings from the 2026-07-17
/// pre-launch audit (docs/audits/2026-07-17-prelaunch-bug-audit.md):
/// in-place wrap under the same multi-child parent, reclaim out of an
/// already-deactivated sibling subtree, a spurious duplicate claim across
/// two passes of one flush, and a real duplicate that must throw loudly
/// instead of committing one element at two positions.
class _Probe extends StatefulWidget {
  const _Probe({super.key, this.onInit});
  final void Function()? onInit;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  static int initCount = 0;
  static int disposeCount = 0;
  static int deactivateCount = 0;

  static void reset() {
    initCount = 0;
    disposeCount = 0;
    deactivateCount = 0;
  }

  @override
  void initState() {
    super.initState();
    initCount++;
    widget.onInit?.call();
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
  Widget build(BuildContext context) => const Text('probe');
}

class _Host extends StatefulWidget {
  const _Host({super.key, required this.probeKey, required this.wrapInPlace});
  final GlobalKey<_ProbeState> probeKey;
  final bool wrapInPlace;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int phase = 0;
  void advance() => setState(() => phase++);

  @override
  Widget build(BuildContext context) {
    final probe = _Probe(key: widget.probeKey);
    if (widget.wrapInPlace) {
      // Finding framework.dart:1896 — frame 0 bare keyed child; frame 1 the
      // same child wrapped in place under the same Row.
      return switch (phase) {
        0 => Row(children: [probe, const Text('b')]),
        1 => Row(children: [const Text('a'), Center(child: probe)]),
        _ => Row(children: [const Text('z'), Center(child: probe)]),
      };
    }
    // Finding framework.dart:596 — frame 0 nested under a wrapper at slot 0;
    // frame 1 reclaimed by a new wrapper at slot 1 after slot 0's subtree
    // was deactivated earlier in the same reconcile.
    return phase == 0
        ? Row(children: [Center(child: probe), const Text('b')])
        : Row(children: [const Text('a'), Align(child: probe)]);
  }
}

/// Host for the two-pass claim scenario (finding framework.dart:1236): the
/// probe's initState reports back, the host responds with a setState during
/// the same flush (the supported registration pattern), and the second pass
/// wraps the just-inflated keyed child.
class _TwoPassHost extends StatefulWidget {
  const _TwoPassHost({super.key, required this.probeKey});
  final GlobalKey<_ProbeState> probeKey;
  @override
  State<_TwoPassHost> createState() => _TwoPassHostState();
}

class _TwoPassHostState extends State<_TwoPassHost> {
  // The keyed child must first inflate inside a *flush* (not the mount,
  // whose claims are released when flushBuild starts), so the tree mounts
  // without it and the test flips [shown] before pumping.
  bool shown = false;
  bool wrapped = false;
  void show() => setState(() => shown = true);

  @override
  Widget build(BuildContext context) {
    if (!shown) return const Text('empty');
    final probe = _Probe(
      key: widget.probeKey,
      onInit: () {
        if (!wrapped) setState(() => wrapped = true);
      },
    );
    return wrapped ? Center(child: probe) : probe;
  }
}

/// Host for the true-duplicate scenario (finding framework.dart:1856): the
/// second frame uses the same GlobalKey twice, once nested under a new
/// unkeyed sibling — which must fail loudly, not corrupt.
class _DuplicateHost extends StatefulWidget {
  const _DuplicateHost({super.key, required this.probeKey});
  final GlobalKey<_ProbeState> probeKey;
  @override
  State<_DuplicateHost> createState() => _DuplicateHostState();
}

class _DuplicateHostState extends State<_DuplicateHost> {
  bool duplicated = false;
  void advance() => setState(() => duplicated = true);

  @override
  Widget build(BuildContext context) {
    final probe = _Probe(key: widget.probeKey);
    return duplicated
        ? Row(children: [Center(child: probe), _Probe(key: widget.probeKey)])
        : Row(children: [probe, const Text('x')]);
  }
}

/// Mirror ordering of [_DuplicateHost]: the bare keyed occurrence comes
/// FIRST, so the reconcile matches it before the later slot's inflate
/// steals it — probing the commit-time validation rather than the
/// stale-candidate match guard.
class _MirrorDuplicateHost extends StatefulWidget {
  const _MirrorDuplicateHost({super.key, required this.probeKey});
  final GlobalKey<_ProbeState> probeKey;
  @override
  State<_MirrorDuplicateHost> createState() => _MirrorDuplicateHostState();
}

class _MirrorDuplicateHostState extends State<_MirrorDuplicateHost> {
  bool duplicated = false;
  void advance() => setState(() => duplicated = true);

  @override
  Widget build(BuildContext context) {
    final probe = _Probe(key: widget.probeKey);
    return duplicated
        ? Row(children: [probe, Center(child: _Probe(key: widget.probeKey))])
        : Row(children: [probe, const Text('x')]);
  }
}

void main() {
  setUp(_ProbeState.reset);

  testWidgets('wrapping a GlobalKey child in place keeps its State', (
    tester,
  ) {
    final hostKey = GlobalKey<_HostState>();
    final probeKey = GlobalKey<_ProbeState>();
    tester.pumpWidget(
      _Host(key: hostKey, probeKey: probeKey, wrapInPlace: true),
    );
    expect(_ProbeState.initCount, 1);

    hostKey.currentState!.advance();
    tester.pump();
    expect(
      _ProbeState.disposeCount,
      0,
      reason: 'in-place wrap must relocate, not dispose, the keyed State',
    );
    expect(_ProbeState.deactivateCount, 1,
        reason: 'one deactivate per move, not a second from stale cleanup');
    expect(probeKey.currentState, isNotNull);

    hostKey.currentState!.advance();
    tester.pump(); // must not crash on the next unrelated rebuild
    expect(probeKey.currentState, isNotNull);
  });

  testWidgets('reclaiming a GlobalKey from a deactivated sibling subtree', (
    tester,
  ) {
    final hostKey = GlobalKey<_HostState>();
    final probeKey = GlobalKey<_ProbeState>();
    tester.pumpWidget(
      _Host(key: hostKey, probeKey: probeKey, wrapInPlace: false),
    );
    expect(_ProbeState.initCount, 1);

    hostKey.currentState!.advance();
    tester.pump();
    expect(
      _ProbeState.disposeCount,
      0,
      reason: 'reparent via GlobalKey must not destroy the State',
    );
    expect(
      _ProbeState.deactivateCount,
      1,
      reason: 'deactivate must fire once, not twice, per move',
    );
    expect(probeKey.currentState, isNotNull);
  });

  testWidgets(
      'a keyed child inflated and wrapped across two passes of one flush '
      'is a move, not a duplicate', (tester) {
    final hostKey = GlobalKey<_TwoPassHostState>();
    final probeKey = GlobalKey<_ProbeState>();
    tester.pumpWidget(_TwoPassHost(key: hostKey, probeKey: probeKey));
    expect(_ProbeState.initCount, 0);

    // One pump, two passes: pass 1 inflates the keyed child (claims the
    // key); its initState setState re-dirties the host; pass 2 of the SAME
    // flush wraps the child — a legitimate sequential move.
    hostKey.currentState!.show();
    tester.pump();
    expect(_ProbeState.initCount, 1,
        reason: 'the same State must survive the second pass');
    expect(_ProbeState.disposeCount, 0);
    expect(probeKey.currentState, isNotNull);
  });

  testWidgets(
      'a real duplicate GlobalKey nested under a new sibling throws the '
      'designed error instead of corrupting the tree', (tester) {
    final hostKey = GlobalKey<_DuplicateHostState>();
    final probeKey = GlobalKey<_ProbeState>();
    tester.pumpWidget(_DuplicateHost(key: hostKey, probeKey: probeKey));

    hostKey.currentState!.advance();
    expect(
      tester.pump,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Duplicate GlobalKey'),
        ),
      ),
      reason: 'one element committed at two positions must fail loudly',
    );
  });

  testWidgets(
      'a real duplicate whose bare occurrence precedes the nested one '
      'throws the designed error at commit, not a corrupt adopt', (
    tester,
  ) {
    final hostKey = GlobalKey<_MirrorDuplicateHostState>();
    final probeKey = GlobalKey<_ProbeState>();
    tester.pumpWidget(
      _MirrorDuplicateHost(key: hostKey, probeKey: probeKey),
    );

    hostKey.currentState!.advance();
    expect(
      tester.pump,
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Duplicate GlobalKey'),
        ),
      ),
      reason: 'the matched-then-stolen ordering must fail the same way',
    );
  });
}
