// Regressions from the pre-merge review of the app-feedback branch — each
// test pins a probe-confirmed finding:
//   1. protocol (image) cells survive inside a settled route
//   2. focus rects are screen-correct in an offset navigator once settled
//   3. a covered route's late autofocus cannot steal focus (modal stays
//      keyboard-dismissable)
//   4. maybePop refuses a non-dismissible modal (pop stays unconditional)
//   5. pop restores focus held OUTSIDE the navigator (fallback snapshot)
//   6. present() honors the Navigator-wide transition default
//   7. keyed children mount once (no duplicate build / spurious
//      didUpdateWidget(identical))

import 'dart:typed_data';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

import '../support/reactive_helpers.dart';

/// Captures the BuildContext its build runs under.
class _Cap extends StatelessWidget {
  const _Cap({required this.sink, required this.label});
  final void Function(BuildContext) sink;
  final String label;
  @override
  Widget build(BuildContext context) {
    sink(context);
    return Text(label);
  }
}

/// Home screen that late-mounts an autofocus Focus when [flag] flips —
/// the async-data-arrives-while-covered pattern.
class _LateMountHome extends StatefulWidget {
  const _LateMountHome({
    required this.flag,
    required this.late,
    required this.sink,
  });
  final Flag flag;
  final FocusNode late;
  final void Function(BuildContext) sink;
  @override
  State<_LateMountHome> createState() => _LateMountHomeState();
}

class _LateMountHomeState extends State<_LateMountHome> {
  @override
  void initState() {
    super.initState();
    widget.flag.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.flag.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.sink(context);
    return Column(
      children: [
        const Text('home'),
        if (widget.flag.value)
          Focus(
            focusNode: widget.late,
            autofocus: true,
            child: const Text('late'),
          ),
      ],
    );
  }
}

/// Leaf that records an inline-image placement — the overlay cell shape a
/// Kitty/Sixel/browser surface renders as pixels.
class _ProtocolBox extends LeafRenderObjectWidget {
  const _ProtocolBox();
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderProtocolBox();
  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {}
}

class _RenderProtocolBox extends RenderObject {
  @override
  CellSize performLayout(CellConstraints constraints) =>
      constraints.constrain(const CellSize(2, 1));

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    buffer.writeImage(
      offset,
      Uint8List.fromList('IMG-BYTES'.codeUnits),
      width: 2,
      height: 1,
    );
  }
}

bool _hasOverlay(CellBuffer buf) {
  for (var r = 0; r < buf.size.rows; r++) {
    for (var c = 0; c < buf.size.cols; c++) {
      if (buf.atColRow(c, r).role == CellRole.overlay) return true;
    }
  }
  return false;
}

/// Keyed stateful child that counts builds and didUpdateWidget calls.
class _Counting extends StatefulWidget {
  const _Counting({
    super.key,
    required this.builds,
    required this.updates,
    required this.id,
  });
  final Map<String, int> builds;
  final Map<String, int> updates;
  final String id;
  @override
  State<_Counting> createState() => _CountingState();
}

class _CountingState extends State<_Counting> {
  @override
  void didUpdateWidget(_Counting oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.updates[widget.id] = (widget.updates[widget.id] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) {
    widget.builds[widget.id] = (widget.builds[widget.id] ?? 0) + 1;
    return Text(widget.id);
  }
}

void main() {
  testWidgets('overlay (image) cells render inside a settled pushed route', (
    tester,
  ) {
    BuildContext? home;
    tester.pumpWidget(
      Navigator(
        home: _Cap(sink: (x) => home = x, label: 'home'),
      ),
    );
    home!.push<void>(const _ProtocolBox()); // default fade transition
    tester.pump(const Duration(milliseconds: 300)); // settle fully
    final buf = tester.render(size: const CellSize(10, 3));
    expect(
      _hasOverlay(buf),
      isTrue,
      reason:
          'a settled route paints through (passthrough), so the image '
          'placement survives to the buffer',
    );
  });

  testWidgets('focus rects are screen-correct in an offset navigator once '
      'settled', (tester) {
    BuildContext? home;
    final f = FocusNode(debugLabel: 'target');
    tester.pumpWidget(
      Container(
        padding: const EdgeInsets.only(left: 5, top: 2),
        child: Navigator(
          home: _Cap(sink: (x) => home = x, label: 'home'),
        ),
      ),
    );
    home!.push<void>(
      Focus(focusNode: f, autofocus: true, child: const Text('x')),
    );
    tester.pump(const Duration(milliseconds: 300)); // settle fully
    tester.render(size: const CellSize(20, 6));
    expect(f.rect, isNotNull);
    expect(
      f.rect!.offset,
      const CellOffset(5, 2),
      reason:
          'settled routes must record true screen coordinates, not '
          'scratch-local ones — click-to-focus targets these rects',
    );
  });

  testWidgets('a covered route cannot steal focus; the modal stays '
      'keyboard-dismissable', (tester) {
    BuildContext? home;
    final flag = Flag();
    final late = FocusNode(debugLabel: 'late');
    tester.pumpWidget(
      Navigator(
        home: _LateMountHome(flag: flag, late: late, sink: (x) => home = x),
      ),
    );
    home!.present<void>(
      const Focus(autofocus: true, child: Text('modal')),
      transition: RouteTransition.none,
    );
    tester.pump();
    final modalNode = tester.focusManager.focusedNode;
    expect(modalNode?.debugLabel, isNot('late'));

    flag.enable(); // covered home late-mounts an autofocus field
    tester.pump();
    expect(
      tester.focusManager.focusedNode,
      same(modalNode),
      reason:
          'occluded routes are focus-inert (ExcludeFocus) — a late '
          'autofocus must not yank focus out of the modal',
    );

    tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
    tester.pump();
    expect(home!.navigator.depth, 1, reason: 'Esc still dismisses the modal');
  });

  testWidgets('maybePop refuses a non-dismissible modal; pop() stays '
      'unconditional', (tester) {
    BuildContext? home;
    tester.pumpWidget(
      Navigator(
        home: _Cap(sink: (x) => home = x, label: 'home'),
      ),
    );
    home!.present<void>(
      const Text('confirm'),
      barrierDismissible: false,
      transition: RouteTransition.none,
    );
    tester.pump();
    expect(home!.navigator.depth, 2);

    expect(
      home!.navigator.maybePop(),
      isFalse,
      reason: 'semantic/back dismissal must respect barrierDismissible',
    );
    expect(home!.navigator.depth, 2);

    home!.navigator.pop();
    tester.pump();
    expect(home!.navigator.depth, 1, reason: 'programmatic pop still works');
  });

  testWidgets('pop restores focus held outside the navigator', (tester) {
    BuildContext? home;
    final sidebar = FocusNode(debugLabel: 'sidebar');
    tester.pumpWidget(
      Column(
        children: [
          Focus(focusNode: sidebar, child: const Text('side')),
          Navigator(
            home: _Cap(sink: (x) => home = x, label: 'home'),
          ),
        ],
      ),
    );
    sidebar.requestFocus();
    tester.pump();
    expect(tester.focusManager.focusedNode, same(sidebar));

    home!.present<void>(const Text('modal'), transition: RouteTransition.none);
    tester.pump();
    home!.navigator.pop();
    tester.pump();
    expect(
      tester.focusManager.focusedNode,
      same(sidebar),
      reason:
          'no route scope recorded the sidebar — the push-time '
          'snapshot fallback must restore it',
    );
  });

  testWidgets('present() honors the Navigator-wide transition default', (
    tester,
  ) {
    BuildContext? home;
    tester.pumpWidget(
      Navigator(
        transition: RouteTransition.none,
        home: _Cap(sink: (x) => home = x, label: 'home'),
      ),
    );
    home!.present<void>(const Text('modal'));
    tester.pump(); // no duration: an animated modal would still be mid-fade
    expect(
      tester.renderToString(size: const CellSize(10, 2)),
      contains('modal'),
      reason: 'Navigator(transition: none) must apply to present() too',
    );
  });

  testWidgets('pointer hit-targets use screen coordinates inside a '
      'composited (mid-transition) route', (tester) {
    BuildContext? home;
    var taps = 0;
    tester.pumpWidget(
      Container(
        padding: const EdgeInsets.only(left: 5, top: 2),
        child: Navigator(
          home: _Cap(sink: (x) => home = x, label: 'home'),
        ),
      ),
    );
    home!.push<void>(
      GestureDetector(onTap: () => taps++, child: const Text('btn')),
    ); // default fade — mid-transition the route paints via a scratch buffer
    tester.pump(const Duration(milliseconds: 100));
    tester.render(size: const CellSize(20, 6)); // registers pointer rects

    // 'btn' sits at screen (5,2): the padded navigator's origin. A
    // scratch-local rect would claim (0,0) and this tap would miss.
    tester.sendMouse(
      const MouseEvent(
        kind: MouseEventKind.down,
        button: MouseButton.left,
        col: 6,
        row: 2,
      ),
    );
    tester.sendMouse(
      const MouseEvent(
        kind: MouseEventKind.up,
        button: MouseButton.left,
        col: 6,
        row: 2,
      ),
    );
    expect(
      taps,
      1,
      reason:
          'hit-testing must use absolute terminal coordinates even '
          'while the route paints through the effect scratch buffer',
    );
  });

  testWidgets('keyed children mount once — no duplicate build, no '
      'didUpdateWidget(identical)', (tester) {
    final builds = <String, int>{};
    final updates = <String, int>{};
    tester.pumpWidget(
      Column(
        children: [
          _Counting(
            key: const ValueKey('a'),
            builds: builds,
            updates: updates,
            id: 'a',
          ),
          _Counting(
            key: const ValueKey('b'),
            builds: builds,
            updates: updates,
            id: 'b',
          ),
        ],
      ),
    );
    expect(
      builds,
      {'a': 1, 'b': 1},
      reason:
          'the attach-time re-reconcile must skip identical keyed '
          'widget instances',
    );
    expect(
      updates,
      isEmpty,
      reason:
          'didUpdateWidget must never fire with oldWidget identical '
          'to widget',
    );
  });
}
