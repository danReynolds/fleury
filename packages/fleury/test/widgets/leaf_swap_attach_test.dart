// Regression: a render-object swap driven by a DESCENDANT rebuilding alone
// (an InheritedNotifier dependent, or a setState below a multi-child render
// widget) must attach the new render object into the multi-child parent.
// MultiChildRenderObjectElement.insertChildRenderObject used to be a no-op —
// it relied on its own performRebuild to install children, so a leaf-driven
// swap eagerly removed the old render object and silently dropped the new
// one: the child vanished from the screen until the parent happened to
// rebuild. (Found via KeyHintBar: EmptyBox -> Text on a focus change.)

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

class _Flag extends ChangeNotifier {
  bool value = false;
  void set(bool v) {
    value = v;
    notifyListeners();
  }
}

/// Rebuilds alone when [flag] fires — a leaf dependent, like the hint bar.
class _Listen extends StatefulWidget {
  const _Listen({required this.flag, required this.builder});
  final _Flag flag;
  final Widget Function(bool on) builder;
  @override
  State<_Listen> createState() => _ListenState();
}

class _ListenState extends State<_Listen> {
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
  Widget build(BuildContext context) => widget.builder(widget.flag.value);
}

void main() {
  testWidgets(
      'a leaf-rebuilt EmptyBox -> Text swap under a Column attaches and paints',
      (tester) {
    final flag = _Flag();
    tester.pumpWidget(
      Column(children: [
        const Text('head'),
        _Listen(
          flag: flag,
          builder: (on) => on ? const Text('shown') : const EmptyBox(),
        ),
        const Text('tail'),
      ]),
    );
    String flat() =>
        tester.renderToString(size: const CellSize(12, 4)).replaceAll('\n', '|');
    expect(flat(), contains('head|tail'),
        reason: 'EmptyBox contributes no cells initially');

    // Only the leaf _Listen rebuilds — the Column element does not.
    flag.set(true);
    tester.pump();
    expect(flat(), contains('head|shown|tail'),
        reason: 'the new render object must be attached (and ordered) even '
            'though the Column never rebuilt');

    // And back again: the removal path stays correct.
    flag.set(false);
    tester.pump();
    expect(flat(), contains('head|tail'));
    expect(flat(), isNot(contains('shown')));
  });
}
