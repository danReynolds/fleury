// Focus-on-entry behaviours (the scope-aware element model): scope-gated +
// deferred autofocus, and focus restoration. These capture the bugs that forced
// consumers to sprinkle `Future.microtask(() => node.requestFocus())` across
// screens. They are written to be RED against the global-gated, immediate
// autofocus and GREEN once autofocus is deferred + scope-gated.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

/// Flips a flag and rebuilds its listeners — lets a test mount a second scope
/// (or swap content) in a later frame, after the first scope is focused.
class _Flag extends ChangeNotifier {
  bool value = false;
  void enable() {
    value = true;
    notifyListeners();
  }
}

/// Scope A is always present (autofocus a). Scope B appears once [flag] flips.
class _TwoScopes extends StatefulWidget {
  const _TwoScopes({required this.flag, required this.a, required this.b});
  final _Flag flag;
  final FocusNode a;
  final FocusNode b;
  @override
  State<_TwoScopes> createState() => _TwoScopesState();
}

class _TwoScopesState extends State<_TwoScopes> {
  @override
  void initState() {
    super.initState();
    widget.flag.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.flag.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          FocusScope(
            child: Focus(
              focusNode: widget.a,
              autofocus: true,
              child: const EmptyBox(),
            ),
          ),
          if (widget.flag.value)
            FocusScope(
              child: Focus(
                focusNode: widget.b,
                autofocus: true,
                child: const EmptyBox(),
              ),
            ),
        ],
      );
}

void main() {
  testWidgets('autofocus claims a fresh scope even while another scope is '
      'focused (scope-gated)', (tester) {
    final a = FocusNode(debugLabel: 'a');
    final b = FocusNode(debugLabel: 'b');
    final flag = _Flag();
    tester.pumpWidget(_TwoScopes(flag: flag, a: a, b: b));
    expect(tester.focusManager.focusedNode, same(a),
        reason: 'a autofocuses on first mount');

    flag.enable(); // scope B mounts in a later frame, while A holds focus
    tester.pump();
    expect(tester.focusManager.focusedNode, same(b),
        reason: 'b autofocuses into its empty scope despite scope A holding '
            'focus — the global gate would have skipped it');
  });

  testWidgets('a still-focused sibling in the SAME scope is not stolen from',
      (tester) {
    // The preserved contract (mirrors focus_test.dart): two autofocus nodes in
    // ONE scope — the first wins; the second must not steal.
    final first = FocusNode(debugLabel: 'first');
    final second = FocusNode(debugLabel: 'second');
    tester.pumpWidget(
      FocusScope(
        child: Column(
          children: [
            Focus(focusNode: first, autofocus: true, child: const EmptyBox()),
            Focus(focusNode: second, autofocus: true, child: const EmptyBox()),
          ],
        ),
      ),
    );
    expect(tester.focusManager.focusedNode, same(first),
        reason: 'one scope, one focused child — the first autofocus wins');
  });
}
