import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

/// Records its own lifecycle so a test can tell a rebuild from a remount.
class _Probe extends StatefulWidget {
  const _Probe({required this.log});

  final List<String> log;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.log.add('init');
  }

  @override
  void dispose() {
    widget.log.add('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('body');
}

Widget _app(Widget body) => WhichKey(
  showDelay: Duration.zero,
  child: KeyBindings(
    bindings: [
      KeyBinding(KeySequence.space.f, label: 'Find file', onTrigger: (_) {}),
    ],
    child: Focus(autofocus: true, child: body),
  ),
);

String _render(FleuryTester tester) =>
    tester.renderToString(size: const CellSize(40, 14), emptyMark: ' ');

void main() {
  testWidgets('WhichKey keeps the app subtree mounted across reveal and hide', (
    tester,
  ) {
    // Revealing the popup used to swap the bare child for a Stack in the same
    // slot — a different runtimeType — so every State below WhichKey was
    // destroyed and recreated on every leader press, and again on hide.
    final log = <String>[];
    tester.pumpWidget(_app(_Probe(log: log)));
    tester.render();
    expect(log, ['init']);

    tester.press(KeySequence.space);
    final shown = _render(tester);
    expect(shown, contains('Find file'));
    expect(shown, contains('body'));
    expect(log, ['init'], reason: 'reveal must not remount the app');

    tester.press(KeySequence.f);
    expect(_render(tester), isNot(contains('Find file')));
    expect(log, ['init'], reason: 'hide must not remount the app either');
  });

  testWidgets('the popup has no layout footprint: the app is constrained the '
      'same shown and hidden', (tester) {
    final seen = <CellConstraints>[];
    tester.pumpWidget(
      _app(
        LayoutBuilder(
          builder: (context, constraints) {
            seen.add(constraints);
            return const Text('body');
          },
        ),
      ),
    );
    tester.render(size: const CellSize(40, 14));
    tester.press(KeySequence.space);
    expect(_render(tester), contains('Find file'));
    tester.press(KeySequence.f);
    tester.render(size: const CellSize(40, 14));

    expect(
      seen.toSet(),
      hasLength(1),
      reason: 'the popup changed what the app was given: $seen',
    );
    expect(
      seen.first,
      CellConstraints.loose(const CellSize(40, 14)),
      reason: "the root's constraints, passed through unchanged",
    );
  });
}
