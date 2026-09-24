// A GlobalKey move into a LayoutBuilder keeps its State.
//
// LayoutBuilder builds during layout. The build flush used to finalize (dispose)
// every subtree it had deactivated before layout ran, so a GlobalKey'd subtree
// moving from a build-phase parent into a LayoutBuilder was disposed and
// re-created instead of moved: maximizing a panel into a LayoutBuilder wiped
// its State.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';
import '../support/harness.dart';

int _inits = 0;
int _disposes = 0;

class _Probe extends StatefulWidget {
  const _Probe({super.key, this.tag = ''});
  final String tag;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int count = 0;

  @override
  void initState() {
    super.initState();
    _inits++;
  }

  @override
  void dispose() {
    _disposes++;
    super.dispose();
  }

  void bump() => setState(() => count++);

  @override
  Widget build(BuildContext context) => Text('${widget.tag}c=$count');
}

class _Host extends StatefulWidget {
  const _Host({super.key, required this.panelKey});
  final GlobalKey panelKey;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool maximized = false;
  void flip() => setState(() => maximized = !maximized);

  @override
  Widget build(BuildContext context) {
    final panel = _Probe(key: widget.panelKey);
    return maximized
        ? LayoutBuilder(builder: (_, _) => panel)
        : Column(children: [panel, const Text('other')]);
  }
}

/// A panel that docks into a LayoutBuilder below 40 columns, as a
/// responsive layout does when the terminal shrinks.
class _Responsive extends StatelessWidget {
  const _Responsive({required this.panelKey});
  final GlobalKey panelKey;

  @override
  Widget build(BuildContext context) {
    final panel = _Probe(key: panelKey);
    return MediaQuery.sizeOf(context).cols < 40
        ? LayoutBuilder(builder: (_, _) => panel)
        : Column(children: [panel, const Text('other')]);
  }
}

/// A panel that maximizes into a LayoutBuilder on Enter.
class _Maximizer extends StatefulWidget {
  const _Maximizer({required this.panelKey});
  final GlobalKey panelKey;
  @override
  State<_Maximizer> createState() => _MaximizerState();
}

class _MaximizerState extends State<_Maximizer> {
  bool maximized = false;

  @override
  Widget build(BuildContext context) {
    final panel = _Probe(key: widget.panelKey);
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyCode.enter,
          onTrigger: (_) => setState(() => maximized = true),
        ),
      ],
      child: Focus(
        autofocus: true,
        child: maximized
            ? LayoutBuilder(builder: (_, _) => panel)
            : Column(children: [panel, const Text('other')]),
      ),
    );
  }
}

void main() {
  setUp(() {
    _inits = 0;
    _disposes = 0;
  });

  testWidgets(
    'a GlobalKey moved into a LayoutBuilder and back keeps its State',
    (tester) {
      final panelKey = GlobalKey<_ProbeState>();
      final hostKey = GlobalKey<_HostState>();
      tester.pumpWidget(_Host(key: hostKey, panelKey: panelKey));
      panelKey.currentState!.bump();
      tester.pump();
      final state = panelKey.currentState;

      hostKey.currentState!.flip();
      tester.pump();
      expect(panelKey.currentState, same(state));
      hostKey.currentState!.flip();
      tester.pump();
      expect(panelKey.currentState, same(state));
      expect(state!.count, 1);
      expect((_inits, _disposes), (1, 0));
    },
  );

  // Every path that builds before its frame's layout — a resize, the
  // harness's pump, input — keeps the move a move.
  test(
    'a resize that docks the panel into a LayoutBuilder keeps its State',
    () {
      final runtime = TuiRuntime();
      var size = const CellSize(60, 4);
      final panelKey = GlobalKey<_ProbeState>();
      final driver = FrameDriver(
        runtime: runtime,
        frameLoop: TuiFrameLoop(renderDamage: runtime.renderDamageTracker),
        readViewport: () => FrameViewportSnapshot(size),
        presenter: const _NullPresenter(),
      );
      addTearDown(driver.dispose);
      driver.mountRoot(
        () => MediaQuery(
          data: MediaQueryData(size: size),
          child: _Responsive(panelKey: panelKey),
        ),
      );
      driver.renderNow('first');
      final state = panelKey.currentState;

      size = const CellSize(30, 4);
      driver.renderNow('resized');

      expect(panelKey.currentState, same(state));
      expect((_inits, _disposes), (1, 0));
    },
  );

  testWidgets('a viewport change that docks the panel keeps its State', (
    tester,
  ) {
    final panelKey = GlobalKey<_ProbeState>();
    tester.pumpWidget(_Responsive(panelKey: panelKey));
    final state = panelKey.currentState;

    tester.render(size: const CellSize(30, 4));

    expect(panelKey.currentState, same(state));
    expect((_inits, _disposes), (1, 0));
  });

  testWidgets('pumpWidget moving the panel into a LayoutBuilder keeps its '
      'State', (tester) {
    final panelKey = GlobalKey<_ProbeState>();
    tester.pumpWidget(Column(children: [_Probe(key: panelKey)]));
    final state = panelKey.currentState;

    tester.pumpWidget(LayoutBuilder(builder: (_, _) => _Probe(key: panelKey)));

    expect(panelKey.currentState, same(state));
    expect((_inits, _disposes), (1, 0));
  });

  testWidgets('a key press that maximizes the panel keeps its State', (tester) {
    final panelKey = GlobalKey<_ProbeState>();
    tester.pumpWidget(_Maximizer(panelKey: panelKey));
    final state = panelKey.currentState;

    tester.sendKey(const KeyEvent(KeyCode.enter));
    tester.pump();

    expect(panelKey.currentState, same(state));
    expect((_inits, _disposes), (1, 0));
  });

  testWidgets('a GlobalKey used in both the build and layout phase is a '
      'duplicate, not a steal-back loop', (tester) {
    final key = GlobalKey();
    // The first frame's layout steals the key from the build-phase child;
    // the build phase stealing it back on the next frame collides with a
    // live claim. Before, the two phases stole it from each other every
    // frame, forever, with one slot blank and no error.
    expect(
      () {
        tester.pumpWidget(
          Column(
            children: [
              SizedBox(
                height: 1,
                child: _Probe(key: key, tag: 'A'),
              ),
              SizedBox(
                height: 1,
                child: LayoutBuilder(
                  builder: (_, _) => _Probe(key: key, tag: 'B'),
                ),
              ),
            ],
          ),
        );
        tester.pump();
      },
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Duplicate GlobalKey'),
        ),
      ),
    );
  });
}

final class _NullPresenter implements FramePresenter {
  const _NullPresenter();

  @override
  bool get wantsPresentationPlan => false;

  @override
  void presentFrame(TuiRenderedFrame frame, FramePresentInfo info) {}

  @override
  void onFrameCommitted(TuiRenderedFrame frame, FramePresentInfo info) {}

  @override
  FrameDiffStats? frameDiffStats(
    TuiRenderedFrame frame,
    FramePresentInfo info,
  ) => null;
}
