// Lifecycle-invariant regression guards from the launch-hardening audit:
//
//   F1 — a subtree deactivated DURING layout (LayoutBuilder swap) must see
//        State.dispose by the end of that same render, not "whenever the
//        next non-idle frame happens" (indefinitely, in an idle TUI).
//   F2 — a flushBuild abort (rebuild-storm cap) must not strand the aborted
//        element with _dirty==true: markNeedsBuild short-circuits on _dirty,
//        so a stranded element could never rebuild again in a session the
//        frame backstop keeps alive.
//   F3 — duplicate local keys among siblings must fail loudly (debug)
//        instead of silently orphaning the shadowed element with a live,
//        never-disposed State.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

class _DisposeProbe extends StatefulWidget {
  const _DisposeProbe(this.log);
  final List<String> log;
  @override
  State<_DisposeProbe> createState() => _DisposeProbeState();
}

class _DisposeProbeState extends State<_DisposeProbe> {
  @override
  void dispose() {
    widget.log.add('disposed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('probe');
}

// A ChangeNotifier the storm widget listens to, so a test can trigger a
// rebuild through the public reactive path (not a protected setState call).
class _Trigger with ChangeNotifier {
  int _value = 0;
  int get value => _value;
  void bump() {
    _value++;
    notifyListeners();
  }
}

final _trigger = _Trigger();

// Storms (re-dirties itself every build) while [storming]; always displays the
// current trigger value and rebuilds when the trigger fires. Mounted clean
// (storming off) first, then armed — so the cap trips on a real rebuild, not
// during initial mount, and afterward we can prove its _dirty was healed by
// firing the trigger again and watching the value update.
class _Storm extends StatefulWidget {
  const _Storm();
  static bool storming = false;
  @override
  State<_Storm> createState() => _StormState();
}

class _StormState extends State<_Storm> {
  @override
  void initState() {
    super.initState();
    _trigger.addListener(_onTrigger);
  }

  @override
  void dispose() {
    _trigger.removeListener(_onTrigger);
    super.dispose();
  }

  void _onTrigger() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (_Storm.storming) setState(() {}); // re-dirties itself every pass
    return Text('trigger:${_trigger.value}');
  }
}

void main() {
  testWidgets('a subtree swapped out during layout disposes the same frame', (
    tester,
  ) {
    // F1: the swap happens inside LayoutBuilder's layout-time rebuild —
    // after this frame's flushBuild already finalized. The post-layout
    // finalize must unmount it before render() returns.
    final log = <String>[];
    tester.pumpWidget(
      LayoutBuilder(
        builder: (context, constraints) => (constraints.maxCols ?? 0) >= 20
            ? _DisposeProbe(log)
            : const Text('narrow'),
      ),
    );
    tester.render(size: const CellSize(30, 3));
    expect(log, isEmpty, reason: 'probe mounted while wide');

    // Shrink: the layout-time rebuild swaps the probe out.
    tester.render(size: const CellSize(10, 3));
    expect(
      log,
      ['disposed'],
      reason:
          'layout-time deactivation must dispose within the same render, '
          'not wait for a future non-idle frame',
    );
  });

  testWidgets('a rebuild-storm abort leaves the element able to rebuild again', (
    tester,
  ) {
    // F2: the convergence-cap throw clears the dirty queue; the aborted
    // element's _dirty flag must be HEALED, or its next setState/markNeedsBuild
    // short-circuits forever (a subtree frozen in a session the frame backstop
    // keeps alive).
    _Storm.storming = false;
    tester.pumpWidget(const _Storm());
    expect(
      tester.renderToString(size: const CellSize(20, 2)),
      contains('trigger:0'),
      reason: 'clean mount',
    );

    // Arm the storm, then drive a rebuild → the cap trips.
    _Storm.storming = true;
    _trigger.bump(); // -> setState -> rebuild storms -> convergence cap
    expect(
      () => tester.render(size: const CellSize(20, 2)),
      throwsA(isA<FleuryError>()),
      reason: 'the storm trips the convergence cap',
    );

    // Storm over. Firing the trigger must still rebuild the (healed) element.
    _Storm.storming = false;
    _trigger.bump();
    expect(
      tester.renderToString(size: const CellSize(20, 2)),
      contains('trigger:2'),
      reason:
          'a stranded _dirty flag would make markNeedsBuild a no-op and '
          'freeze the element at its pre-abort content',
    );
  });

  testWidgets('duplicate sibling keys fail loudly before mutation', (tester) {
    // F3: silently overwriting the key map orphans the shadowed element with a
    // live State that never disposes — a monotonic leak on every rebuild.
    // The collision is detected on the reconcile that partitions old children
    // by key — which happens as the tree builds/renders.
    expect(
      () {
        tester.pumpWidget(
          const Column(
            children: [
              SizedBox(key: ValueKey('dup'), child: Text('a')),
              SizedBox(key: ValueKey('dup'), child: Text('b')),
            ],
          ),
        );
        tester.render(size: const CellSize(20, 3));
      },
      throwsA(isA<StateError>()),
      reason:
          'duplicate local keys must be a release-mode app-author error, not '
          'a debug-only assertion or silent orphan',
    );
  });
}
