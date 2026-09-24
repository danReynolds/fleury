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
