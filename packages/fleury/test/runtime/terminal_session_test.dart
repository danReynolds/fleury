// The terminal session is reachable from the tree under runApp.
//
// runApp captures stdio; a child that inherits it outside a handoff gets the
// capture pipes, not the terminal, and the app looks frozen while $EDITOR eats
// keystrokes. The driver that performs the handoff used to be unreachable
// from a default runApp. TerminalSession.of(context) is the way in.

import 'dart:async';

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

class _Probe extends StatelessWidget {
  const _Probe({required this.onBuild});

  final void Function(BuildContext context) onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild(context);
    return const Text('x');
  }
}

void main() {
  test('TerminalSession.of resolves the session driver and hands the terminal '
      'off through it', () async {
    final driver = FakeTerminalDriver(size: const CellSize(20, 4));
    TerminalSession? seen;
    final future = runApp(
      _Probe(onBuild: (context) => seen = TerminalSession.of(context)),
      driver: driver,
      enableHotReload: false,
    );
    try {
      await _settle();
      expect(seen, isNotNull);
      expect(identical(seen!.driver, driver), isTrue, reason: 'one owner');
      expect(seen!.supportsHandoff, isTrue);

      var ran = false;
      await seen!.runWithHandoff(() async {
        ran = true;
        expect(
          driver.isActive,
          isFalse,
          reason: 'the terminal belongs to the operation while it runs',
        );
      });
      expect(ran, isTrue);
      expect(driver.handoffSuspendCallCount, 1);
      expect(driver.handoffResumeCallCount, 1);
      expect(driver.isActive, isTrue, reason: 'and comes back');
    } finally {
      driver.enqueue(
        const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
      );
      await future.timeout(const Duration(seconds: 2));
      await driver.dispose();
    }
  });

  testWidgets('maybeOf is null outside a scope; of() says how to get one', (
    tester,
  ) {
    TerminalSession? seen;
    Object? thrown;
    tester.pumpWidget(
      _Probe(
        onBuild: (context) {
          seen = TerminalSession.maybeOf(context);
          try {
            TerminalSession.of(context);
          } catch (error) {
            thrown = error;
          }
        },
      ),
    );
    tester.render(size: const CellSize(10, 2));
    expect(seen, isNull);
    expect(thrown, isA<StateError>());
    expect('$thrown', contains('runApp'));
  });

  test('a floating overlay entry resolves the session too', () async {
    // Menus, tooltips, toasts and pickers are Overlay entries — siblings of
    // the app root, not its descendants. The scope used to sit inside the
    // root entry, so a context-menu action that hands the terminal to
    // $EDITOR threw with advice ("run under runApp") the caller already
    // followed.
    final driver = FakeTerminalDriver(size: const CellSize(20, 4));
    TerminalSession? fromEntry;
    final future = runApp(
      _EntryInserter(
        builder: (context) {
          fromEntry = TerminalSession.maybeOf(context);
          return const Text('float');
        },
      ),
      driver: driver,
      enableHotReload: false,
    );
    try {
      await _settle();
      await _settle();
      expect(fromEntry, isNotNull, reason: 'the scope is above the Overlay');
      expect(identical(fromEntry!.driver, driver), isTrue);
    } finally {
      driver.enqueue(
        const KeyEvent(KeyCode.char('c'), modifiers: {KeyModifier.ctrl}),
      );
      await future.timeout(const Duration(seconds: 2));
      await driver.dispose();
    }
  });
}

/// Inserts one overlay entry built by [builder] once it has a context.
class _EntryInserter extends StatefulWidget {
  const _EntryInserter({required this.builder});

  final Widget Function(BuildContext context) builder;

  @override
  State<_EntryInserter> createState() => _EntryInserterState();
}

class _EntryInserterState extends State<_EntryInserter> {
  var _inserted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inserted) return;
    _inserted = true;
    Overlay.of(context).insert(OverlayEntry(builder: widget.builder));
  }

  @override
  Widget build(BuildContext context) => const Text('base');
}
