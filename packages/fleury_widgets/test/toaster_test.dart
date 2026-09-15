import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

import '../example/toast_lifecycle.dart';

class _Capture extends StatelessWidget {
  const _Capture(this.sink);
  final void Function(BuildContext) sink;
  @override
  Widget build(BuildContext context) {
    sink(context);
    return const Text('app');
  }
}

String _screen(FleuryTester tester, {int cols = 20, int rows = 8}) =>
    tester.renderToString(size: CellSize(cols, rows), emptyMark: ' ');

void main() {
  testWidgets(
    'the lifecycle example replaces failures and cleans up on removal',
    (tester) async {
      tester.pumpWidget(const Toaster(maxToasts: 1, child: ToastDemo()));
      tester.render(size: const CellSize(60, 12));
      await tester
          .target(role: SemanticRole.button, label: 'Copy fails')
          .press();
      tester.pump(const Duration(minutes: 1));
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.notification)
            .state
            .severity,
        'error',
      );
      await tester
          .target(role: SemanticRole.button, label: 'Copy succeeds')
          .press();
      tester.pump();
      expect(
        tester.semantics().single(role: SemanticRole.notification).label,
        'Copied',
      );
      tester.pumpWidget(const Toaster(maxToasts: 1, child: Text('next route')));
      tester.pump();
      expect(
        tester.semantics().where(role: SemanticRole.notification),
        isEmpty,
      );
    },
  );
  group('lifecycle', () {
    for (final size in [const CellSize(40, 24), const CellSize(80, 20)]) {
      testWidgets(
        'a single persistent error wraps at $size without taking focus',
        (tester) {
          late BuildContext ctx;
          final focus = FocusNode();
          tester.pumpWidget(
            Toaster(
              maxToasts: 1,
              child: Column(
                children: [
                  _Capture((c) => ctx = c),
                  TextInput(focusNode: focus, autofocus: true),
                ],
              ),
            ),
          );
          tester.render(size: size);
          const message =
              'Copy could not be confirmed. The clipboard may have changed. Try again.';
          Toaster.show(
            ctx,
            message,
            persistent: true,
            severity: ToastSeverity.error,
          );
          tester.pump();
          final screen = tester.renderToString(size: size, emptyMark: ' ');
          expect(screen, contains('Copy could not be confirmed.'));
          expect(screen, contains('Try'));
          expect(screen, contains('again.'));
          final toast = tester.semantics().single(label: message);
          expect(toast.bounds!.left, greaterThanOrEqualTo(0));
          expect(toast.bounds!.top, greaterThanOrEqualTo(0));
          expect(toast.bounds!.right, lessThanOrEqualTo(size.cols));
          expect(toast.bounds!.bottom, lessThanOrEqualTo(size.rows));
          expect(focus.hasFocus, isTrue);
          tester.pumpWidget(const EmptyBox());
          focus.dispose();
        },
      );
    }
    testWidgets('replacement resets expiry and invalidates the old handle', (
      tester,
    ) {
      late BuildContext ctx;
      tester.pumpWidget(Toaster(child: _Capture((c) => ctx = c)));
      final first = Toaster.show(
        ctx,
        'first',
        id: 'operation',
        duration: const Duration(seconds: 2),
      );
      tester.pump(const Duration(seconds: 1));
      final second = Toaster.show(
        ctx,
        'second',
        id: 'operation',
        duration: const Duration(seconds: 4),
      );
      first.dismiss();
      tester.pump(const Duration(seconds: 1));
      expect(
        tester.semantics().where(role: SemanticRole.notification),
        hasLength(1),
      );
      expect(_screen(tester), contains('second'));
      tester.pump(const Duration(seconds: 2));
      expect(_screen(tester), contains('second'));
      tester.pump(const Duration(seconds: 1));
      expect(_screen(tester), isNot(contains('second')));
      second.dismiss();
      second.dismiss();
    });

    testWidgets(
      'persistent replacement has no expiry and can become transient',
      (tester) {
        late BuildContext ctx;
        tester.pumpWidget(Toaster(child: _Capture((c) => ctx = c)));
        Toaster.show(
          ctx,
          'success',
          id: 'copy',
          duration: const Duration(seconds: 1),
        );
        Toaster.show(
          ctx,
          'failure',
          id: 'copy',
          persistent: true,
          severity: ToastSeverity.error,
        );
        tester.pump(const Duration(minutes: 30));
        final error = tester.semantics().single(label: 'failure');
        expect(error.hint, 'Persistent notification');
        expect(error.state['autoDismissMs'], isNull);
        expect(error.state.severity, 'error');
        Toaster.show(
          ctx,
          'recovered',
          id: 'copy',
          duration: const Duration(seconds: 2),
        );
        tester.pump();
        expect(_screen(tester), isNot(contains('failure')));
        tester.pump(const Duration(seconds: 2));
        expect(
          tester.semantics().where(role: SemanticRole.notification),
          isEmpty,
        );
      },
    );

    testWidgets('capacity evicts oldest with no queued replay', (tester) {
      late BuildContext ctx;
      tester.pumpWidget(Toaster(maxToasts: 2, child: _Capture((c) => ctx = c)));
      final evicted = Toaster.show(ctx, 'first', persistent: true);
      Toaster.show(ctx, 'second', persistent: true);
      final last = Toaster.show(ctx, 'third', persistent: true);
      evicted.dismiss();
      tester.pump();
      expect(_screen(tester), isNot(contains('first')));
      expect(_screen(tester), contains('second'));
      expect(_screen(tester), contains('third'));
      last.dismiss();
      tester.pump(const Duration(minutes: 1));
      expect(
        tester.semantics().where(role: SemanticRole.notification),
        hasLength(1),
      );
      expect(_screen(tester), contains('second'));
      expect(_screen(tester), isNot(contains('first')));
    });

    testWidgets('a burst with the same ID remains one toast', (tester) {
      late BuildContext ctx;
      tester.pumpWidget(Toaster(maxToasts: 1, child: _Capture((c) => ctx = c)));
      final id = Object();
      for (var i = 0; i < 20; i++) {
        Toaster.show(ctx, 'copy $i', id: id);
      }
      tester.pump();
      expect(
        tester.semantics().where(role: SemanticRole.notification),
        hasLength(1),
      );
      expect(_screen(tester), contains('copy 19'));
    });

    testWidgets(
      'replacements keep position and changed capacity trims oldest',
      (tester) {
        late BuildContext ctx;
        Widget host(int limit) =>
            Toaster(maxToasts: limit, child: _Capture((c) => ctx = c));
        tester.pumpWidget(host(3));
        Toaster.show(ctx, 'first', id: 1, persistent: true);
        Toaster.show(ctx, 'second', id: 2, persistent: true);
        Toaster.show(ctx, 'new first', id: 1, persistent: true);
        tester.pump();
        expect(
          tester
              .semantics()
              .single(label: 'new first')
              .state['notificationIndex'],
          1,
        );
        tester.pumpWidget(host(1));
        tester.pump();
        expect(
          tester.semantics().where(role: SemanticRole.notification),
          hasLength(1),
        );
        expect(_screen(tester), contains('second'));
      },
    );

    testWidgets('host disposal revokes handles and action callbacks', (tester) {
      late BuildContext ctx;
      tester.pumpWidget(Toaster(child: _Capture((c) => ctx = c)));
      final handle = Toaster.show(ctx, 'old', id: 'id');
      tester.pumpWidget(const Text('next'));
      handle.dismiss();
      tester.pump(const Duration(minutes: 1));
      expect(_screen(tester), contains('next'));
      expect(
        tester.semantics().where(role: SemanticRole.notification),
        isEmpty,
      );
    });

    testWidgets('replacement revokes the previous action', (tester) {
      late BuildContext ctx;
      var actions = 0;
      tester.pumpWidget(
        Toaster(child: Focus(autofocus: true, child: _Capture((c) => ctx = c))),
      );
      Toaster.show(
        ctx,
        'old',
        id: 'id',
        action: ToastAction(
          label: 'Undo',
          key: KeySequence.alt.u,
          onPressed: () => actions++,
        ),
      );
      Toaster.show(ctx, 'new', id: 'id', persistent: true);
      tester.pump();
      tester.sendKey(
        const KeyEvent(KeyCode.char('u'), modifiers: {KeyModifier.alt}),
      );
      expect(actions, 0);
      expect(_screen(tester), contains('new'));
    });

    testWidgets(
      'inner Escape takes precedence over persistent toast dismissal',
      (tester) async {
        late BuildContext ctx;
        var intercept = true;
        tester.pumpWidget(
          Toaster(
            child: KeyBindings(
              bindings: [
                KeyBinding(
                  KeyCode.escape,
                  onTrigger: (event) {
                    if (intercept) {
                      intercept = false;
                    } else {
                      event.bubble();
                    }
                  },
                ),
              ],
              child: Focus(autofocus: true, child: _Capture((c) => ctx = c)),
            ),
          ),
        );
        Toaster.show(ctx, 'failure', persistent: true);
        tester.pump();
        tester.sendKey(const KeyEvent(KeyCode.escape));
        tester.pump();
        expect(_screen(tester), contains('failure'));
        await tester
            .target(role: SemanticRole.notification, label: 'failure')
            .perform(SemanticAction.dismiss);
        tester.pump();
        expect(_screen(tester), isNot(contains('failure')));
        Toaster.show(ctx, 'another', persistent: true);
        tester.pump();
        tester.sendKey(const KeyEvent(KeyCode.escape));
        tester.pump();
        expect(_screen(tester), isNot(contains('another')));
      },
    );

    testWidgets('persistence and explicit duration are contradictory', (
      tester,
    ) {
      late BuildContext ctx;
      tester.pumpWidget(Toaster(child: _Capture((c) => ctx = c)));
      expect(
        () =>
            Toaster.show(ctx, 'bad', persistent: true, duration: Duration.zero),
        throwsArgumentError,
      );
    });

    testWidgets('nonpositive expiry is rejected before showing a toast', (
      tester,
    ) {
      late BuildContext ctx;
      tester.pumpWidget(Toaster(child: _Capture((c) => ctx = c)));
      expect(
        () => Toaster.show(ctx, 'zero', duration: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => Toaster.show(
          ctx,
          'negative',
          duration: const Duration(seconds: -1),
        ),
        throwsArgumentError,
      );
      tester.pump();
      expect(
        tester.semantics().where(role: SemanticRole.notification),
        isEmpty,
      );
    });
  });

  testWidgets('shows a toast and auto-dismisses after the duration', (
    tester,
  ) async {
    late BuildContext ctx;
    tester.pumpWidget(
      Toaster(
        duration: const Duration(seconds: 2),
        child: _Capture((c) => ctx = c),
      ),
    );

    Toaster.show(ctx, 'Saved');
    tester.pump();
    expect(_screen(tester).contains('Saved'), isTrue);

    // After the duration the auto-dismiss timer fires and removes it.
    tester.pump(const Duration(seconds: 2));
    await Future<void>.delayed(Duration.zero);
    tester.pump();
    expect(_screen(tester).contains('Saved'), isFalse);
  });

  testWidgets('stacks multiple toasts', (tester) {
    late BuildContext ctx;
    tester.pumpWidget(Toaster(child: _Capture((c) => ctx = c)));

    Toaster.show(ctx, 'first');
    Toaster.show(ctx, 'second');
    tester.pump();
    final out = _screen(tester);
    expect(out.contains('first'), isTrue);
    expect(out.contains('second'), isTrue);
  });

  testWidgets('Esc dismisses the most recent toast', (tester) {
    late BuildContext ctx;
    tester.pumpWidget(
      Toaster(
        child: Column(
          children: [
            _Capture((c) => ctx = c),
            Button(text: 'x', autofocus: true, onPressed: () {}),
          ],
        ),
      ),
    );

    Toaster.show(ctx, 'first');
    Toaster.show(ctx, 'second');
    tester.pump();
    expect(_screen(tester, rows: 10).contains('second'), isTrue);

    tester.sendKey(const KeyEvent(KeyCode.escape));
    tester.pump();
    final out = _screen(tester, rows: 10);
    expect(out.contains('second'), isFalse, reason: 'latest toast dismissed');
    expect(out.contains('first'), isTrue, reason: 'older toast remains');
  });

  testWidgets('toasts float over a presented modal', (tester) async {
    // The Toaster's overlay entry sits above the navigator, so a toast
    // shows on top of a dialog presented on the navigator.
    late BuildContext ctx;
    tester.pumpWidget(
      Toaster(child: Navigator(home: _Capture((c) => ctx = c))),
    );
    Navigator.of(ctx).present<void>(const Text('dialog'));
    tester.pump(const Duration(milliseconds: 300));

    Toaster.show(ctx, 'notice');
    tester.pump();
    expect(_screen(tester).contains('notice'), isTrue);
  });

  testWidgets('throws without a Toaster ancestor', (tester) {
    late BuildContext ctx;
    tester.pumpWidget(_Capture((c) => ctx = c));
    expect(() => Toaster.show(ctx, 'x'), throwsStateError);
  });

  testWidgets('severity colors the status dot, not the message', (tester) {
    late BuildContext ctx;
    tester.pumpWidget(Toaster(child: _Capture((c) => ctx = c)));
    Toaster.show(ctx, 'oops', severity: ToastSeverity.error);
    tester.pump();
    final buf = tester.render(size: const CellSize(20, 8));
    var dotColored = false;
    var messageNeutral = false;
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 20; c++) {
        final cell = buf.atColRow(c, r);
        if (cell.grapheme == '●') {
          expect(
            cell.style.foreground,
            const AnsiColor(1),
            reason: 'the status dot carries the error color',
          );
          dotColored = true;
        }
        // The 'oo' of 'oops' — the message itself stays neutral.
        if (cell.grapheme == 'o' && buf.atColRow(c + 1, r).grapheme == 'o') {
          expect(cell.style.foreground, isNull, reason: 'message not tinted');
          messageNeutral = true;
        }
      }
    }
    expect(dotColored, isTrue, reason: 'rendered a colored status dot');
    expect(messageNeutral, isTrue, reason: 'rendered the neutral message');
  });

  group('action', () {
    testWidgets('renders the action label and key hint', (tester) {
      late BuildContext ctx;
      tester.pumpWidget(
        Toaster(child: Focus(autofocus: true, child: _Capture((c) => ctx = c))),
      );
      tester.render(size: const CellSize(40, 8));
      Toaster.show(
        ctx,
        'Deleted',
        action: ToastAction(
          label: 'Undo',
          key: KeySequence.alt.u,
          onPressed: () {},
        ),
      );
      tester.pump();
      final out = _screen(tester, cols: 40);
      expect(out.contains('Deleted'), isTrue);
      expect(out.contains('Alt+U'), isTrue, reason: 'key hint shown');
      expect(out.contains('Undo'), isTrue);
    });

    testWidgets('the hotkey fires onPressed and dismisses the toast', (tester) {
      late BuildContext ctx;
      var undone = 0;
      tester.pumpWidget(
        Toaster(child: Focus(autofocus: true, child: _Capture((c) => ctx = c))),
      );
      tester.render(size: const CellSize(40, 8));
      Toaster.show(
        ctx,
        'Deleted',
        action: ToastAction(
          label: 'Undo',
          key: KeySequence.alt.u,
          onPressed: () => undone++,
        ),
      );
      tester.pump();
      expect(_screen(tester, cols: 40).contains('Undo'), isTrue);

      tester.sendKey(
        const KeyEvent(KeyCode.char('u'), modifiers: {KeyModifier.alt}),
      );
      expect(undone, 1);
      tester.pump();
      expect(
        _screen(tester, cols: 40).contains('Undo'),
        isFalse,
        reason: 'toast dismissed after the action ran',
      );
    });
  });

  testWidgets('shows a leading status dot colored by severity', (tester) {
    late BuildContext ctx;
    tester.pumpWidget(Toaster(child: _Capture((c) => ctx = c)));
    Toaster.show(ctx, 'Saved', severity: ToastSeverity.success);
    tester.pump();
    final buf = tester.render(size: const CellSize(24, 8));
    var found = false;
    for (var r = 0; r < 8 && !found; r++) {
      for (var c = 0; c < 24; c++) {
        if (buf.atColRow(c, r).grapheme == '●') {
          // A non-null foreground = colored (the success accent, not neutral).
          expect(
            buf.atColRow(c, r).style.foreground,
            isNotNull,
            reason: 'success toast shows a colored status dot',
          );
          found = true;
          break;
        }
      }
    }
    expect(found, isTrue, reason: 'rendered a leading status dot');
  });

  testWidgets('info severity stays neutral (uncolored)', (tester) {
    late BuildContext ctx;
    tester.pumpWidget(Toaster(child: _Capture((c) => ctx = c)));
    Toaster.show(ctx, 'plain');
    tester.pump();
    final buf = tester.render(size: const CellSize(20, 8));
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 20; c++) {
        if (buf.atColRow(c, r).grapheme == 'p' &&
            buf.atColRow(c + 1, r).grapheme == 'l') {
          expect(buf.atColRow(c, r).style.foreground, isNull);
          return;
        }
      }
    }
    fail('did not find the toast text');
  });

  group('lazy overlay entry', () {
    // beginFrame flips a process-global; never leak recording across tests.
    tearDown(() => RepaintBoundaryDebugStats.beginFrame(enabled: false));

    testWidgets('mounts the layer entry only while toasts exist', (tester) {
      // App-shaped fixture: an explicit Overlay hosts the Toaster'd app as
      // its base entry, so the Toaster's layer lands in an overlay whose
      // adaptive per-entry boundaries are observable (the tester's harness
      // overlay holds one pass-through entry, so its boundary never engages).
      final overlayKey = GlobalKey<OverlayState>();
      late BuildContext ctx;
      tester.pumpWidget(
        Overlay(
          key: overlayKey,
          initialEntries: [
            OverlayEntry(
              builder: (_) => Toaster(
                duration: const Duration(seconds: 2),
                child: _Capture((c) => ctx = c),
              ),
            ),
          ],
        ),
      );
      const size = CellSize(20, 8);
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      tester.render(size: size);
      var stats = RepaintBoundaryDebugStats.takeFrameStats();
      expect(
        overlayKey.currentState!.entries,
        hasLength(1),
        reason: 'no toasts → the layer entry is not mounted',
      );
      expect(
        stats.boundaryCount,
        0,
        reason:
            'single visible entry → boundaries stay pass-through: an '
            'idle Toaster must not tax app frames',
      );

      // Enqueue: the entry mounts on the same turn and boundaries engage.
      Toaster.show(ctx, 'Saved');
      tester.pump();
      expect(overlayKey.currentState!.entries, hasLength(2));
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      expect(_screen(tester).contains('Saved'), isTrue);
      stats = RepaintBoundaryDebugStats.takeFrameStats();
      expect(
        stats.boundaryCount,
        2,
        reason: 'two visible entries → both boundaries engaged',
      );

      // Auto-dismiss empties the toasts: the entry unmounts and the
      // overlay returns to single-entry pass-through.
      tester.pump(const Duration(seconds: 2));
      expect(
        overlayKey.currentState!.entries,
        hasLength(1),
        reason: 'last toast expired → the layer entry unmounts',
      );
      RepaintBoundaryDebugStats.beginFrame(enabled: true);
      expect(_screen(tester).contains('Saved'), isFalse);
      stats = RepaintBoundaryDebugStats.takeFrameStats();
      expect(stats.boundaryCount, 0, reason: 'idle again: pass-through');
    });
  });

  group('semantics', () {
    testWidgets('exposes toasts as notification nodes with safe state', (
      tester,
    ) {
      late BuildContext ctx;
      tester.pumpWidget(
        Toaster(
          duration: const Duration(seconds: 4),
          child: _Capture((c) => ctx = c),
        ),
      );

      Toaster.show(ctx, 'Saved', severity: ToastSeverity.success);
      tester.pump();

      final node = tester.semantics().single(
        role: SemanticRole.notification,
        label: 'Saved',
      );

      expect(node.hint, 'Transient notification');
      expect(node.actions, contains(SemanticAction.dismiss));
      expect(node.actions, isNot(contains(SemanticAction.activate)));
      expect(node.state.severity, 'success');
      expect(node.state['notificationIndex'], 1);
      expect(node.state['notificationCount'], 1);
      expect(node.state['autoDismissMs'], 4000);
    });

    testWidgets('semantic dismiss removes the toast', (tester) async {
      late BuildContext ctx;
      tester.pumpWidget(Toaster(child: _Capture((c) => ctx = c)));

      Toaster.show(ctx, 'Saved');
      tester.pump();
      expect(
        tester.semantics().where(role: SemanticRole.notification),
        isNotEmpty,
      );

      await tester
          .target(role: SemanticRole.notification, label: 'Saved')
          .perform(SemanticAction.dismiss);
      tester.pump();

      expect(tester.target(role: SemanticRole.notification), hasCount(0));
      expect(_screen(tester).contains('Saved'), isFalse);
    });

    testWidgets('semantic activate runs the toast action and dismisses it', (
      tester,
    ) async {
      late BuildContext ctx;
      var undone = 0;
      tester.pumpWidget(
        Toaster(child: Focus(autofocus: true, child: _Capture((c) => ctx = c))),
      );

      Toaster.show(
        ctx,
        'Deleted',
        action: ToastAction(
          label: 'Undo',
          key: KeySequence.alt.u,
          onPressed: () => undone++,
        ),
      );
      tester.pump();

      final node = tester.semantics().single(
        role: SemanticRole.notification,
        label: 'Deleted',
      );
      expect(node.actions, contains(SemanticAction.activate));
      expect(node.actions, contains(SemanticAction.dismiss));
      expect(node.state['notificationActionLabel'], 'Undo');
      expect(node.state['notificationActionKey'], 'Alt+U');

      await tester.target(id: node.id).press();
      expect(undone, 1);
      tester.pump();
      expect(tester.target(role: SemanticRole.notification), hasCount(0));
    });

    testWidgets('accessibility snapshot summarizes notification actions', (
      tester,
    ) {
      late BuildContext ctx;
      tester.pumpWidget(Toaster(child: _Capture((c) => ctx = c)));
      Toaster.show(
        ctx,
        'Deleted',
        severity: ToastSeverity.warning,
        action: ToastAction(
          label: 'Undo',
          key: KeySequence.alt.u,
          onPressed: () {},
        ),
      );
      tester.pump();

      final node = tester.accessibilitySnapshot().single(
        role: SemanticRole.notification,
        label: 'Deleted',
      );

      expect(node.roleLabel, 'notification');
      expect(node.states, contains('severity warning'));
      expect(
        node.states,
        contains(
          'notification 1 of 1, action Undo, key Alt+U, auto dismiss 5000ms',
        ),
      );
      expect(node.actions, contains(SemanticAction.activate));
      expect(node.actions, contains(SemanticAction.dismiss));
    });
  });
  testWidgets('a toast is opaque — app content does not bleed through it', (
    tester,
  ) {
    // A toast floats in an OverlayEntry, compositing over the app. Without its
    // own background the wall of X's behind it shows through the frame.
    late BuildContext ctx;
    tester.pumpWidget(
      Toaster(
        child: Column(
          children: [
            _Capture((c) => ctx = c),
            for (var i = 0; i < 8; i++) Text('X' * 20),
          ],
        ),
      ),
    );
    tester.pump();
    Toaster.show(ctx, 'Saved');
    tester.pump();

    final row = _screen(
      tester,
    ).split('\n').firstWhere((line) => line.contains('Saved'));
    // The toast is bottom-right aligned; cells between the frame edge and the
    // message are inside the toast, so the wall must not show there.
    expect(
      row.substring(row.indexOf('Saved')),
      isNot(contains('X')),
      reason: 'the wall behind bled through the toast',
    );
  });
}
