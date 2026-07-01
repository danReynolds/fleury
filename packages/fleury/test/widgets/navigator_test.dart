// Navigator: imperative screen stack — push/pop with results, focus
// trap + restore, Esc back, transitions, and state preservation of
// lower routes.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:test/test.dart';

/// Renders the visible (top) screen as trimmed text.
String _screen(FleuryTester tester, {int cols = 12, int rows = 1}) {
  final buf = tester.render(size: CellSize(cols, rows));
  final out = <String>[];
  for (var r = 0; r < rows; r++) {
    final sb = StringBuffer();
    for (var c = 0; c < cols; c++) {
      final cell = buf.atColRow(c, r);
      sb.write(cell.role == CellRole.leading ? cell.grapheme : ' ');
    }
    out.add(sb.toString().trimRight());
  }
  return out.join('\n').trimRight();
}

/// Captures the BuildContext its build runs under.
class _Capture extends StatelessWidget {
  const _Capture({required this.sink, required this.label});
  final void Function(BuildContext) sink;
  final String label;
  @override
  Widget build(BuildContext context) {
    sink(context);
    return Text(label);
  }
}

/// Like [_Capture] but renders an arbitrary child (for screens that need
/// real content, e.g. a focusable TextInput).
class _CaptureChild extends StatelessWidget {
  const _CaptureChild({required this.sink, required this.child});
  final void Function(BuildContext) sink;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    sink(context);
    return child;
  }
}

/// Distinct screen types so `popUntil<T>` has something to target.
class _Alpha extends StatelessWidget {
  const _Alpha();
  @override
  Widget build(BuildContext context) => const Text('alpha');
}

class _Beta extends StatelessWidget {
  const _Beta();
  @override
  Widget build(BuildContext context) => const Text('beta');
}

void main() {
  testWidgets('renders the home route', (tester) {
    tester.pumpWidget(Navigator(home: const Text('home')));
    expect(_screen(tester), 'home');
  });

  testWidgets('push shows a new screen; pop returns its result', (
    tester,
  ) async {
    BuildContext? home;
    tester.pumpWidget(
      Navigator(
        home: _Capture(sink: (x) => home = x, label: 'home'),
      ),
    );
    expect(home!.navigator.depth, 1);

    final future = home!.push<int>(const Text('picker'));
    tester.pump(const Duration(milliseconds: 300)); // finish enter
    expect(_screen(tester), 'picker');
    expect(home!.navigator.depth, 2);

    home!.navigator.pop(42);
    final result = await future;
    expect(result, 42);

    tester.pump(const Duration(milliseconds: 300)); // finish exit
    expect(_screen(tester), 'home');
    expect(home!.navigator.depth, 1);
  });

  testWidgets('RouteTransition.none settles in a single pump (instant)', (
    tester,
  ) {
    BuildContext? home;
    tester.pumpWidget(
      Navigator(home: _Capture(sink: (x) => home = x, label: 'home')),
    );
    // No duration is pumped: an animated push would still be mid-fade, but
    // RouteTransition.none snaps the route fully present in one frame.
    home!.push<void>(const Text('instant'), transition: RouteTransition.none);
    tester.pump();
    expect(_screen(tester), 'instant');
    expect(home!.navigator.depth, 2);
  });

  testWidgets('present() puts content on an opaque Surface (no bleed-through)', (
    tester,
  ) {
    BuildContext? home;
    tester.pumpWidget(
      Navigator(home: _Capture(sink: (x) => home = x, label: 'ABCDEFGH')),
    );
    // A modal box wider than its text: without an opaque surface, the empty
    // cells inside its box would composite the home text beneath (the leak).
    home!.present<void>(
      const SizedBox(width: 8, height: 1, child: Text('X')),
      transition: RouteTransition.none,
    );
    tester.pump();
    expect(
      _screen(tester, cols: 8),
      'X',
      reason: 'the opaque Surface covers the home row — no bleed-through',
    );
  });

  testWidgets('present(barrierColor:) fills the surround over the screen behind',
      (tester) {
    BuildContext? home;
    tester.pumpWidget(
      Navigator(home: _Capture(sink: (x) => home = x, label: 'ABCDEFGH')),
    );
    home!.present<void>(
      const Text('X'),
      barrierColor: Colors.black,
      transition: RouteTransition.none,
    );
    tester.pump();
    final out = _screen(tester, cols: 8);
    expect(out, contains('X'));
    expect(
      out,
      isNot(contains('A')),
      reason: 'the barrier fills the surround, covering the home row',
    );
  });

  testWidgets('present(barrierDismissible: false) ignores Esc', (tester) {
    BuildContext? home;
    tester.pumpWidget(
      Navigator(home: _Capture(sink: (x) => home = x, label: 'home')),
    );
    home!.present<void>(
      const Focus(autofocus: true, child: Text('locked')),
      barrierDismissible: false,
      transition: RouteTransition.none,
    );
    tester.pump();
    expect(home!.navigator.depth, 2);
    expect(_screen(tester), contains('locked'));

    tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
    tester.pump();
    expect(
      home!.navigator.depth,
      2,
      reason: 'a non-dismissible modal stays put on Esc',
    );
  });

  testWidgets('pop at the root is a no-op; canPop reflects depth', (tester) {
    BuildContext? home;
    tester.pumpWidget(
      Navigator(
        home: _Capture(sink: (x) => home = x, label: 'home'),
      ),
    );
    expect(home!.navigator.canPop, isFalse);
    home!.navigator.pop(); // no-op
    expect(_screen(tester), 'home');

    home!.push<void>(const Text('two'));
    tester.pump(const Duration(milliseconds: 300));
    expect(home!.navigator.canPop, isTrue);
  });

  testWidgets('Esc pops the top route', (tester) {
    BuildContext? home;
    tester.pumpWidget(
      Navigator(
        home: _Capture(sink: (x) => home = x, label: 'home'),
      ),
    );
    // A focusable screen so Esc routes through the focus chain to the
    // route's Esc binding (screens normally have focusable content).
    home!.push<void>(const Focus(autofocus: true, child: Text('detail')));
    tester.pump(const Duration(milliseconds: 300));
    expect(_screen(tester), 'detail');

    tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
    tester.pump(const Duration(milliseconds: 300));
    expect(_screen(tester), 'home');
  });

  testWidgets('Esc pops a pushed route that has no focusable content', (
    tester,
  ) {
    BuildContext? home;
    tester.pumpWidget(
      Navigator(home: _Capture(sink: (x) => home = x, label: 'home')),
    );
    // No autofocus target on the pushed route — its own Esc binding must still
    // be reachable (the route claims focus on entry), or keys get dropped.
    home!.push<void>(const Text('detail'), transition: RouteTransition.none);
    tester.pump();
    expect(_screen(tester), 'detail');

    tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
    tester.pump();
    expect(
      _screen(tester),
      'home',
      reason: 'Esc reaches the route binding despite no autofocus target',
    );
  });

  testWidgets('focus traps to the pushed screen and restores on pop', (tester) {
    BuildContext? home;
    final homeInput = TextEditingController();
    final detailInput = TextEditingController();

    tester.pumpWidget(
      Navigator(
        home: _CaptureChild(
          sink: (x) => home = x,
          child: TextInput(controller: homeInput, autofocus: true),
        ),
      ),
    );
    tester.type('a');
    expect(homeInput.text, 'a', reason: 'home has focus initially');

    home!.push<void>(TextInput(controller: detailInput, autofocus: true));
    tester.pump(const Duration(milliseconds: 300));
    tester.type('b');
    expect(detailInput.text, 'b', reason: 'pushed screen captured focus');
    expect(homeInput.text, 'a', reason: 'home no longer receives input');

    home!.navigator.pop();
    tester.pump(const Duration(milliseconds: 300));
    tester.type('c');
    expect(homeInput.text, 'ac', reason: 'focus restored to home');
  });

  testWidgets('popUntil restores focus to the target route', (tester) {
    // The old priorFocus chain pointed into intermediate routes that popUntil
    // removes — restore died with them. Scope memory lives on the TARGET
    // route's own FocusScope, so it survives.
    BuildContext? home;
    final homeInput = TextEditingController();
    tester.pumpWidget(
      Navigator(
        home: _CaptureChild(
          sink: (x) => home = x,
          child: TextInput(controller: homeInput, autofocus: true),
        ),
      ),
    );
    tester.type('a');
    expect(homeInput.text, 'a');

    home!.push<void>(TextInput(controller: TextEditingController(), autofocus: true));
    tester.pump(const Duration(milliseconds: 300));
    home!.push<void>(TextInput(controller: TextEditingController(), autofocus: true));
    tester.pump(const Duration(milliseconds: 300));

    home!.navigator.popToRoot();
    tester.pump(const Duration(milliseconds: 300));
    tester.type('b');
    expect(homeInput.text, 'ab',
        reason: 'focus restored to home across removed intermediates');
  });

  testWidgets("pushReplacement: popping the replacement restores the covered "
      "route's focus", (tester) async {
    BuildContext? home;
    final homeInput = TextEditingController();
    tester.pumpWidget(
      Navigator(
        home: _CaptureChild(
          sink: (x) => home = x,
          child: TextInput(controller: homeInput, autofocus: true),
        ),
      ),
    );
    tester.type('a');

    home!.push<void>(const Text('interim'));
    tester.pump(const Duration(milliseconds: 300));
    home!.navigator.pushReplacement<void>(const Text('replacement'));
    tester.pump(const Duration(milliseconds: 300));
    // The replaced route is removed in the settle callback (a microtask);
    // yield so it runs — otherwise pop below reveals the zombie interim.
    await tester.settle();

    home!.navigator.pop();
    tester.pump(const Duration(milliseconds: 300));
    tester.type('b');
    expect(homeInput.text, 'ab',
        reason: "the covered route's own scope memory survives replacement");
  });

  testWidgets(
    'page routes allow ancestor bindings while modals suppress them',
    (tester) {
      BuildContext? home;
      final focus = FocusNode(debugLabel: 'home-focus');
      addTearDown(focus.dispose);
      final calls = <String>[];
      tester.pumpWidget(
        KeyBindings(
          bindings: [
            KeyBinding(
              KeyChord.ctrl.k,
              onEvent: (_) {
                calls.add('ancestor');
              },
            ),
          ],
          child: Navigator(
            home: Focus(
              focusNode: focus,
              autofocus: true,
              child: _Capture(sink: (x) => home = x, label: 'home'),
            ),
          ),
        ),
      );
      tester.render();
      focus.requestFocus();
      tester.pump();

      tester.sendKey(const KeyEvent(char: 'k', modifiers: {KeyModifier.ctrl}));
      expect(calls, ['ancestor']);

      home!.present<void>(const Focus(autofocus: true, child: Text('modal')));
      tester.pump(const Duration(milliseconds: 300));
      tester.render();
      tester.sendKey(const KeyEvent(char: 'k', modifiers: {KeyModifier.ctrl}));

      expect(calls, ['ancestor']);
    },
  );

  testWidgets('exposes navigator and route semantics', (tester) {
    BuildContext? home;
    tester.pumpWidget(
      Navigator(
        home: _Capture(sink: (x) => home = x, label: 'home'),
      ),
    );

    var tree = tester.semantics();
    var nav = tree.single(role: SemanticRole.navigation);
    expect(nav.label, 'root navigator');
    expect(nav.value, 1);
    expect(nav.actions, contains(SemanticAction.navigate));
    expect(nav.actions, isNot(contains(SemanticAction.close)));
    expect(nav.state.values['routeDepth'], 1);
    expect(nav.state.values['root'], isTrue);

    var activeRoutes = tree.where(role: SemanticRole.route, selected: true);
    expect(activeRoutes, hasLength(1));
    expect(activeRoutes.single.state.routeName, '_Capture');

    home!.push<void>(const Text('detail'));
    tester.pump(const Duration(milliseconds: 300));

    tree = tester.semantics();
    nav = tree.single(role: SemanticRole.navigation);
    expect(nav.value, 2);
    expect(nav.actions, contains(SemanticAction.close));
    expect(nav.state.values['canPop'], isTrue);

    activeRoutes = tree.where(role: SemanticRole.route, selected: true);
    expect(activeRoutes, hasLength(1));
    final active = activeRoutes.single;
    expect(active.state.routeName, 'Text');
    expect(active.state.values['routeDepth'], 2);
    expect(active.actions, contains(SemanticAction.close));
  });

  testWidgets('semantic navigator close pops the top route', (tester) async {
    BuildContext? home;
    tester.pumpWidget(
      Navigator(
        home: _Capture(sink: (x) => home = x, label: 'home'),
      ),
    );
    home!.push<void>(const Text('detail'));
    tester.pump(const Duration(milliseconds: 300));
    expect(_screen(tester), 'detail');

    final result = await tester.invokeSemanticAction(
      SemanticAction.close,
      role: SemanticRole.navigation,
    );
    tester.pump(const Duration(milliseconds: 300));

    expect(result.completed, isTrue);
    expect(_screen(tester), 'home');
    expect(home!.navigator.depth, 1);
  });

  testWidgets('semantic route close pops an active page route', (tester) async {
    BuildContext? home;
    tester.pumpWidget(
      Navigator(
        home: _Capture(sink: (x) => home = x, label: 'home'),
      ),
    );
    home!.push<void>(const Text('detail'));
    tester.pump(const Duration(milliseconds: 300));

    final result = await tester.invokeSemanticAction(
      SemanticAction.close,
      role: SemanticRole.route,
      selected: true,
    );
    tester.pump(const Duration(milliseconds: 300));

    expect(result.completed, isTrue);
    expect(_screen(tester), 'home');
  });

  testWidgets('semantic route dismiss closes an active modal route', (
    tester,
  ) async {
    BuildContext? home;
    tester.pumpWidget(
      Navigator(
        home: _Capture(sink: (x) => home = x, label: 'home'),
      ),
    );
    home!.present<void>(const Text('modal'));
    tester.pump(const Duration(milliseconds: 300));
    expect(home!.navigator.depth, 2);

    final modalRoute = tester.semantics().single(
      role: SemanticRole.route,
      selected: true,
      action: SemanticAction.dismiss,
    );
    expect(modalRoute.state.values['modal'], isTrue);

    final result = await tester.invokeSemanticAction(
      SemanticAction.dismiss,
      node: modalRoute,
    );
    tester.pump(const Duration(milliseconds: 300));

    expect(result.completed, isTrue);
    expect(home!.navigator.depth, 1);
    expect(_screen(tester), 'home');
  });

  testWidgets('lower routes stay mounted — state survives back-nav', (tester) {
    BuildContext? home;
    tester.pumpWidget(
      Navigator(
        home: _Capture(sink: (x) => home = x, label: 'home'),
      ),
    );
    final ctl = _CounterCtl();
    home!.push<void>(_Counter(ctl));
    tester.pump(const Duration(milliseconds: 300));
    ctl.bump(); // value 0 -> 1
    expect(ctl.value, 1);

    // Push deeper and pop back. If the counter screen had been
    // unmounted, its State would reset to 0 and bumping would give 1;
    // since lower routes stay mounted, it continues from 1.
    home!.navigator.push<void>(const Text('deeper'));
    tester.pump(const Duration(milliseconds: 300));
    home!.navigator.pop();
    tester.pump(const Duration(milliseconds: 300));
    ctl.bump();
    expect(ctl.value, 2, reason: 'State survived — continued from 1');
  });

  testWidgets('fade transition: pushed screen is mid-fade before settle', (
    tester,
  ) {
    BuildContext? home;
    tester.pumpWidget(
      Navigator(
        home: _Capture(sink: (x) => home = x, label: 'home'),
      ),
    );
    home!.push<void>(
      const Text('x', style: CellStyle(foreground: RgbColor(255, 255, 255))),
      transition: RouteTransition(
        enter: Effects.fadeIn(),
        exit: Effects.fadeOut(),
        curve: Curves.linear,
        duration: const Duration(milliseconds: 200),
      ),
    );
    tester.pump(const Duration(milliseconds: 100)); // mid-fade
    final fg = tester
        .render(size: const CellSize(2, 1))
        .atColRow(0, 0)
        .style
        .foreground;
    expect(fg, isA<RgbColor>());
    final c = fg as RgbColor;
    expect(c.r, inExclusiveRange(0, 255), reason: 'partway faded in');
  });

  group('robustness', () {
    testWidgets('pop during the entrance keeps the screen beneath '
        'visible (B1: no stale opaque flip)', (tester) async {
      BuildContext? home;
      tester.pumpWidget(
        Navigator(
          home: _Capture(sink: (x) => home = x, label: 'home'),
          transition: RouteTransition(
            enter: Effects.slideIn(from: Edge.right, distance: 6),
            exit: Effects.slideOut(to: Edge.right, distance: 6),
            curve: Curves.linear,
            duration: const Duration(milliseconds: 200),
          ),
        ),
      );
      home!.push<void>(const Text('X'));
      tester.pump(const Duration(milliseconds: 80)); // mid-entrance
      home!.navigator.pop(); // pop before it settled
      // Drain the cancelled entrance's completion microtask — WITHOUT
      // the B1 guard this would flip the (now-leaving) route opaque,
      // covering the screen beneath during its exit.
      await Future<void>.delayed(Duration.zero);

      tester.pump(const Duration(milliseconds: 40)); // mid-exit
      // 'X' has slid right, vacating column 0 — home's 'h' shows there
      // only if the leaving route is non-opaque (the fix).
      final cell = tester.render(size: const CellSize(8, 1)).atColRow(0, 0);
      expect(cell.role, CellRole.leading);
      expect(
        cell.grapheme,
        'h',
        reason: 'screen beneath is painted during the exit',
      );

      tester.pump(const Duration(milliseconds: 400));
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      expect(home!.navigator.depth, 1);
    });

    testWidgets('a settled screen occludes the one beneath — no '
        'bleed-through (O1)', (tester) async {
      BuildContext? home;
      tester.pumpWidget(
        Navigator(
          home: _Capture(sink: (x) => home = x, label: 'HOMEHOME'),
        ),
      );
      // Push a SHORT screen over the long home.
      home!.push<void>(const Text('A'));
      tester.pump(const Duration(milliseconds: 300)); // finish entrance
      await Future<void>.delayed(Duration.zero); // drain the opaque flip
      tester.pump(); // overlay recomputes occlusion

      // Only 'A' shows; the home tail (cols 1-7) is occluded. Before
      // the O1 fix, dynamic opaque didn't recompute and home bled
      // through as 'AOMEHOME'.
      expect(_screen(tester, cols: 8), 'A');
    });

    testWidgets('disposing the Navigator completes pending push futures '
        'with null (B2)', (tester) async {
      BuildContext? home;
      tester.pumpWidget(
        Navigator(
          home: _Capture(sink: (x) => home = x, label: 'home'),
        ),
      );
      final future = home!.push<int>(const Text('screen'));
      tester.pump(const Duration(milliseconds: 300));

      // Tear the Navigator out of the tree without popping.
      tester.pumpWidget(const Text('gone'));
      final result = await future.timeout(const Duration(seconds: 1));
      expect(result, isNull, reason: 'no hung await on teardown');
    });
  });

  group('root registration', () {
    testWidgets('a root-level navigator registers on the binding', (tester) {
      expect(tester.binding.rootNavigator, isNull, reason: 'none before mount');
      tester.pumpWidget(Navigator(home: const Text('home')));
      expect(tester.binding.rootNavigator, isNotNull);
      expect(tester.binding.rootNavigator!.canPop, isFalse);
    });

    testWidgets('disposing the root navigator clears the registration', (
      tester,
    ) {
      tester.pumpWidget(Navigator(home: const Text('home')));
      expect(tester.binding.rootNavigator, isNotNull);
      tester.pumpWidget(const Text('gone'));
      expect(tester.binding.rootNavigator, isNull);
    });
  });

  group('nesting', () {
    testWidgets('of(context) finds the nearest; rootNavigator finds the '
        'top-level one', (tester) {
      BuildContext? innerLeaf;
      tester.pumpWidget(
        Navigator(
          home: Navigator(
            home: _Capture(sink: (x) => innerLeaf = x, label: 'inner'),
          ),
        ),
      );

      final root = tester.binding.rootNavigator!;
      final nearest = Navigator.of(innerLeaf!);
      expect(nearest, isNot(same(root)), reason: 'inner != root');
      expect(Navigator.of(innerLeaf!, rootNavigator: true), same(root));
    });

    testWidgets('nested navigators keep independent stacks', (tester) async {
      BuildContext? innerLeaf;
      tester.pumpWidget(
        Navigator(
          home: Navigator(
            home: _Capture(sink: (x) => innerLeaf = x, label: 'inner-home'),
          ),
        ),
      );
      final root = tester.binding.rootNavigator!;
      final inner = Navigator.of(innerLeaf!);
      expect(root.depth, 1);
      expect(inner.depth, 1);

      // Push a SHORT screen over the long home; finish the entrance and
      // drain the opaque flip so occlusion recomputes (same async gap as
      // the O1 case above).
      inner.push<void>(const Text('inner-2'));
      tester.pump(const Duration(milliseconds: 300));
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      expect(inner.depth, 2, reason: 'inner grew');
      expect(root.depth, 1, reason: 'root is untouched');
      expect(_screen(tester), 'inner-2');
    });

    testWidgets('focus reaches a nested navigator\'s screen', (tester) {
      final innerInput = TextEditingController();
      tester.pumpWidget(
        Navigator(
          home: Navigator(
            home: TextInput(controller: innerInput, autofocus: true),
          ),
        ),
      );
      // Input lands on the inner screen despite the outer navigator's
      // modal focus scope wrapping it.
      tester.type('hi');
      expect(innerInput.text, 'hi');
    });
  });

  group('embedding', () {
    testWidgets('a navigator renders within its layout slot', (tester) {
      tester.pumpWidget(
        Column(
          children: [
            const Text('header'),
            Navigator(home: const Text('body')),
          ],
        ),
      );
      // Header occupies row 0; the navigator's slot is row 1.
      expect(_screen(tester, cols: 12, rows: 2), 'header\nbody');
    });

    testWidgets('an embedded push stays inside the navigator slot', (tester) {
      BuildContext? body;
      tester.pumpWidget(
        Column(
          children: [
            const Text('header'),
            Navigator(
              home: _Capture(sink: (x) => body = x, label: 'body'),
            ),
          ],
        ),
      );
      body!.push<void>(const Text('next'));
      tester.pump(const Duration(milliseconds: 300));
      // Header is undisturbed; only the navigator's slot changed.
      expect(_screen(tester, cols: 12, rows: 2), 'header\nnext');
    });
  });

  group('extended operations', () {
    testWidgets('pushReplacement swaps the top route — the old one is gone', (
      tester,
    ) async {
      tester.pumpWidget(Navigator(home: const Text('login')));
      final nav = tester.binding.rootNavigator!;

      nav.pushReplacement<void>(const Text('home'));
      tester.pump(const Duration(milliseconds: 300));
      await Future<void>.delayed(Duration.zero); // settle → drop the replaced
      tester.pump();

      expect(_screen(tester), 'home');
      expect(nav.depth, 1, reason: 'login was replaced, not stacked');
      expect(nav.canPop, isFalse, reason: 'nothing to pop back to');
    });

    testWidgets('pushReplacement completes the replaced route\'s future', (
      tester,
    ) async {
      BuildContext? home;
      tester.pumpWidget(
        Navigator(
          home: _Capture(sink: (x) => home = x, label: 'home'),
        ),
      );
      final replaced = home!.push<String>(const Text('first'));
      tester.pump(const Duration(milliseconds: 300));

      home!.navigator.pushReplacement<void>(
        const Text('second'),
        result: 'bye',
      );
      tester.pump(const Duration(milliseconds: 300)); // settle 'second'
      expect(await replaced, 'bye');
    });

    testWidgets('popToRoot returns to the root in a single transition', (
      tester,
    ) async {
      BuildContext? home;
      tester.pumpWidget(
        Navigator(
          home: _Capture(sink: (x) => home = x, label: 'root'),
        ),
      );
      final nav = home!.navigator;
      nav.push<void>(const Text('a'));
      tester.pump(const Duration(milliseconds: 300));
      nav.push<void>(const Text('b'));
      tester.pump(const Duration(milliseconds: 300));
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      expect(nav.depth, 3);

      nav.popToRoot();
      tester.pump(const Duration(milliseconds: 300));
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      expect(nav.depth, 1);
      expect(_screen(tester), 'root');
    });

    testWidgets('popUntil<T> pops to the nearest screen of that type', (
      tester,
    ) async {
      BuildContext? home;
      tester.pumpWidget(
        Navigator(
          home: _Capture(sink: (x) => home = x, label: 'root'),
        ),
      );
      final nav = home!.navigator;
      nav.push<void>(const _Alpha());
      tester.pump(const Duration(milliseconds: 300));
      nav.push<void>(const _Beta());
      tester.pump(const Duration(milliseconds: 300));
      nav.push<void>(const Text('top'));
      tester.pump(const Duration(milliseconds: 300));
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      expect(nav.depth, 4);

      nav.popUntil<_Alpha>();
      tester.pump(const Duration(milliseconds: 300));
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      expect(nav.depth, 2, reason: 'root + alpha remain');
      expect(_screen(tester), 'alpha');
    });

    testWidgets('pushAndClear resets the stack to the new screen', (
      tester,
    ) async {
      BuildContext? home;
      tester.pumpWidget(
        Navigator(
          home: _Capture(sink: (x) => home = x, label: 'splash'),
        ),
      );
      final nav = home!.navigator;
      nav.push<void>(const Text('login'));
      tester.pump(const Duration(milliseconds: 300));
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      expect(nav.depth, 2);

      nav.pushAndClear<void>(const Text('home'));
      tester.pump(const Duration(milliseconds: 300));
      await Future<void>.delayed(Duration.zero);
      tester.pump();
      expect(nav.depth, 1, reason: 'splash + login both cleared');
      expect(nav.canPop, isFalse);
      expect(_screen(tester), 'home');
    });
  });

  group('PopScope', () {
    testWidgets('a blocking PopScope vetoes Esc and fires onBlocked', (tester) {
      var blocked = 0;
      tester.pumpWidget(
        Navigator(
          home: _Capture(sink: (x) {}, label: 'home'),
        ),
      );
      final nav = tester.binding.rootNavigator!;
      nav.push<void>(
        PopScope(
          canPop: false,
          onBlocked: () => blocked++,
          child: const Focus(autofocus: true, child: Text('editor')),
        ),
      );
      tester.pump(const Duration(milliseconds: 300));
      expect(_screen(tester), 'editor');

      tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
      tester.pump(const Duration(milliseconds: 300));
      expect(blocked, 1, reason: 'Esc was intercepted');
      expect(_screen(tester), 'editor', reason: 'still on the guarded screen');
      expect(nav.depth, 2, reason: 'pop was vetoed');
    });

    testWidgets('semantic route close respects a blocking PopScope', (
      tester,
    ) async {
      var blocked = 0;
      tester.pumpWidget(
        Navigator(
          home: _Capture(sink: (x) {}, label: 'home'),
        ),
      );
      final nav = tester.binding.rootNavigator!;
      nav.push<void>(
        PopScope(
          canPop: false,
          onBlocked: () => blocked++,
          child: const Focus(autofocus: true, child: Text('editor')),
        ),
      );
      tester.pump(const Duration(milliseconds: 300));

      final result = await tester.invokeSemanticAction(
        SemanticAction.close,
        role: SemanticRole.route,
        selected: true,
      );
      tester.pump(const Duration(milliseconds: 300));

      expect(result.completed, isTrue);
      expect(blocked, 1, reason: 'semantic close used maybePop');
      expect(_screen(tester), 'editor', reason: 'still on the guarded screen');
      expect(nav.depth, 2, reason: 'semantic close was vetoed');
    });

    testWidgets('an allowing PopScope lets Esc through', (tester) {
      tester.pumpWidget(
        Navigator(
          home: _Capture(sink: (x) {}, label: 'home'),
        ),
      );
      final nav = tester.binding.rootNavigator!;
      nav.push<void>(
        const PopScope(
          canPop: true,
          child: Focus(autofocus: true, child: Text('editor')),
        ),
      );
      tester.pump(const Duration(milliseconds: 300));

      tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
      tester.pump(const Duration(milliseconds: 300));
      expect(nav.depth, 1, reason: 'pop allowed');
      expect(_screen(tester), 'home');
    });

    testWidgets('explicit pop() bypasses the guard', (tester) {
      tester.pumpWidget(
        Navigator(
          home: _Capture(sink: (x) {}, label: 'home'),
        ),
      );
      final nav = tester.binding.rootNavigator!;
      nav.push<void>(const PopScope(canPop: false, child: Text('editor')));
      tester.pump(const Duration(milliseconds: 300));

      nav.pop(); // programmatic — not gated
      tester.pump(const Duration(milliseconds: 300));
      expect(nav.depth, 1, reason: 'pop() is unconditional');
    });
  });
}

/// Mutable controller held outside the (immutable) widget.
class _CounterCtl {
  void Function()? _bump;
  int value = 0;
  void bump() => _bump?.call();
}

class _Counter extends StatefulWidget {
  const _Counter(this.ctl);
  final _CounterCtl ctl;
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  @override
  void initState() {
    super.initState();
    widget.ctl._bump = () => setState(() => widget.ctl.value++);
  }

  @override
  Widget build(BuildContext context) => Text('count ${widget.ctl.value}');
}
