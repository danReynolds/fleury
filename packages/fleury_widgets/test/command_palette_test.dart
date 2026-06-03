import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

/// Captures a BuildContext under a Navigator so we can present the
/// palette from it.
class _Capture extends StatelessWidget {
  const _Capture(this.sink);
  final void Function(BuildContext) sink;
  @override
  Widget build(BuildContext context) {
    sink(context);
    return const Text('home');
  }
}

/// Presents the palette and lets the entrance settle (its TextInput
/// autofocuses on build — no focus hack needed under present).
void _open(FleuryTester tester, BuildContext ctx, List<Command> cmds) {
  Navigator.of(ctx).present<void>(CommandPalette(commands: cmds));
  tester.pump(const Duration(milliseconds: 300));
  tester.render();
}

void _openAppPalette(FleuryTester tester, BuildContext ctx) {
  Navigator.of(ctx).present<void>(const AppCommandPalette());
  tester.pump(const Duration(milliseconds: 300));
  tester.render();
}

List<SemanticNode> _paletteCommandRows(FleuryTester tester) {
  return tester
      .semantics()
      .byRole(SemanticRole.command)
      .where((node) => node.state['rowIndex'] != null)
      .toList();
}

/// Pumps out a dismissal transition so the route is fully removed.
Future<void> _settleClose(FleuryTester tester) async {
  tester.pump(const Duration(milliseconds: 300));
  await Future<void>.delayed(Duration.zero);
  tester.pump();
}

void main() {
  late BuildContext ctx;
  List<Command> commands(void Function(String) onRun) => [
    Command(label: 'Open File', onInvoke: () => onRun('open')),
    Command(label: 'Save File', onInvoke: () => onRun('save')),
    Command(label: 'Close Window', onInvoke: () => onRun('close')),
  ];

  testWidgets('filters by fuzzy query and invokes on Enter', (tester) async {
    String? ran;
    tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));
    _open(tester, ctx, commands((v) => ran = v));
    expect(Navigator.of(ctx).depth, 2, reason: 'palette is open');

    tester.type('save'); // matches only "Save File"
    tester.pump();
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    expect(ran, 'save');

    await _settleClose(tester);
    expect(Navigator.of(ctx).depth, 1, reason: 'palette closed on invoke');
  });

  testWidgets('Up/Down move the selection before invoking', (tester) async {
    String? ran;
    tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));
    _open(tester, ctx, commands((v) => ran = v));

    // No query → all three; selection starts at 0 (Open File).
    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown)); // → Save File
    tester.sendKey(
      const KeyEvent(keyCode: KeyCode.arrowDown),
    ); // → Close Window
    tester.pump();
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    expect(ran, 'close');
  });

  testWidgets('Esc dismisses without invoking', (tester) async {
    var ran = false;
    tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));
    _open(tester, ctx, [
      Command(label: 'Dangerous', onInvoke: () => ran = true),
    ]);

    tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
    await _settleClose(tester);

    expect(ran, isFalse);
    expect(Navigator.of(ctx).depth, 1, reason: 'palette dismissed');
  });

  testWidgets('dismissed palette does not leave stale semantic actions', (
    tester,
  ) async {
    tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));
    _open(tester, ctx, commands((_) {}));
    expect(tester.semantics().byRole(SemanticRole.commandPalette), isNotEmpty);

    tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
    await _settleClose(tester);

    expect(tester.semantics().byRole(SemanticRole.commandPalette), isEmpty);
    final result = await tester.invokeSemanticAction(
      SemanticAction.submit,
      role: SemanticRole.commandPalette,
    );
    expect(result.status, SemanticActionInvocationStatus.notFound);
  });

  testWidgets('repeated palette cycles do not retain stale modal semantics', (
    tester,
  ) async {
    var calls = 0;
    tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));

    for (var i = 0; i < 4; i++) {
      _open(tester, ctx, [
        Command(label: 'Run Cycle $i', onInvoke: () => calls += 1),
      ]);
      tester.type('Run Cycle $i');
      tester.pump();
      expect(
        tester.semantics().byRole(SemanticRole.commandPalette),
        hasLength(1),
      );
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      await _settleClose(tester);
      expect(Navigator.of(ctx).depth, 1);
      expect(tester.semantics().byRole(SemanticRole.commandPalette), isEmpty);
    }

    expect(calls, 4);
  });

  testWidgets('exposes palette and command semantics', (tester) {
    tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));
    _open(tester, ctx, commands((_) {}));

    var tree = tester.semantics();
    var palette = tree.single(role: SemanticRole.commandPalette);
    expect(palette.label, 'Command palette');
    expect(palette.value, '');
    expect(palette.actions, contains(SemanticAction.submit));
    expect(palette.actions, contains(SemanticAction.dismiss));
    expect(palette.state.collectionRowCount, 3);
    expect(palette.state.selectedKey, 0);

    final open = tree.single(role: SemanticRole.command, label: 'Open File');
    expect(open.selected, isTrue);
    expect(open.actions, contains(SemanticAction.activate));
    expect(open.state.commandId, 'Open File');

    tester.type('save');
    tester.pump();

    tree = tester.semantics();
    palette = tree.single(role: SemanticRole.commandPalette);
    expect(palette.value, 'save');
    expect(palette.state.filterText, 'save');
    expect(palette.state.collectionRowCount, 1);
    final save = tree.single(role: SemanticRole.command, label: 'Save File');
    expect(save.selected, isTrue);
  });

  testWidgets('large palettes expose bounded visible row semantics', (tester) {
    tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));
    _open(tester, ctx, [
      for (var i = 0; i < 200; i++)
        Command(label: 'Command $i', onInvoke: () {}),
    ]);

    final tree = tester.semantics();
    final palette = tree.single(role: SemanticRole.commandPalette);
    final rows = _paletteCommandRows(tester);
    expect(palette.state.collectionRowCount, 200);
    expect(rows.length, lessThan(200));
    expect(rows, isNotEmpty);
    expect(palette.state.values['visibleRangeStart'], 0);
    expect(palette.state.values['visibleRangeEnd'], rows.length - 1);
  });

  testWidgets('semantic submit invokes selected command and closes', (
    tester,
  ) async {
    String? ran;
    tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));
    _open(tester, ctx, commands((v) => ran = v));
    tester.type('save');
    tester.pump();

    final result = await tester.invokeSemanticAction(
      SemanticAction.submit,
      role: SemanticRole.commandPalette,
    );

    expect(result.completed, isTrue);
    expect(ran, 'save');
    await _settleClose(tester);
    expect(Navigator.of(ctx).depth, 1);
  });

  testWidgets('semantic command activate invokes that row and closes', (
    tester,
  ) async {
    String? ran;
    tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));
    _open(tester, ctx, commands((v) => ran = v));

    final result = await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.command,
      label: 'Close Window',
    );

    expect(result.completed, isTrue);
    expect(ran, 'close');
    await _settleClose(tester);
    expect(Navigator.of(ctx).depth, 1);
  });

  testWidgets('semantic dismiss closes without invoking', (tester) async {
    var ran = false;
    tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));
    _open(tester, ctx, [
      Command(label: 'Dangerous', onInvoke: () => ran = true),
    ]);

    final result = await tester.invokeSemanticAction(
      SemanticAction.dismiss,
      role: SemanticRole.commandPalette,
    );

    expect(result.completed, isTrue);
    await _settleClose(tester);
    expect(ran, isFalse);
    expect(Navigator.of(ctx).depth, 1);
  });

  group('edges', () {
    testWidgets('shows a no-match message when nothing matches', (
      tester,
    ) async {
      tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));
      _open(tester, ctx, commands((_) {}));
      tester.type('zzzz');
      tester.pump();
      expect(tester.exists(text('No matching commands')), isTrue);
    });

    testWidgets('selection resets to the top when the query changes', (
      tester,
    ) async {
      String? ran;
      tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));
      _open(tester, ctx, commands((v) => ran = v));

      // Move off the top, then type — 's' matches Save + Close, and the
      // selection should snap back to the first match (Save), not stay at 1.
      tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
      tester.type('s');
      tester.pump();
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      expect(ran, 'save', reason: 'selection reset to the first match');
    });

    testWidgets('an empty command list is inert, not a crash', (tester) async {
      tester.pumpWidget(Navigator(home: _Capture((c) => ctx = c)));
      _open(tester, ctx, const []);
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      tester.pump();
      expect(
        Navigator.of(ctx).depth,
        2,
        reason: 'still open; Enter was a no-op',
      );
    });
  });

  group('AppCommandPalette', () {
    testWidgets('invokes active registry commands through the registry', (
      tester,
    ) async {
      final calls = <String>[];
      tester.pumpWidget(
        FleuryApp(
          title: 'App',
          commands: [
            AppCommand(
              id: const CommandId('file.open'),
              title: 'Open File',
              shortcuts: [KeyChord.ctrl.o],
              run: (_) {
                calls.add('open');
              },
            ),
            AppCommand(
              id: const CommandId('file.save'),
              title: 'Save File',
              description: 'Write changes',
              category: 'File',
              shortcuts: [KeyChord.ctrl.s],
              run: (_) {
                calls.add('save');
              },
            ),
          ],
          child: Navigator(home: _Capture((c) => ctx = c)),
        ),
      );

      _openAppPalette(tester, ctx);
      tester.type('save');
      tester.pump();
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));

      expect(calls, ['save']);
      await _settleClose(tester);
      expect(Navigator.of(ctx).depth, 1);
    });

    testWidgets('filters by stable command id', (tester) async {
      final calls = <String>[];
      tester.pumpWidget(
        FleuryApp(
          title: 'App',
          commands: [
            AppCommand(
              id: const CommandId('workspace.reload'),
              title: 'Reload Workspace',
              run: (_) {
                calls.add('reload');
              },
            ),
            AppCommand(
              id: const CommandId('workspace.reset'),
              title: 'Reset Workspace',
              run: (_) {
                calls.add('reset');
              },
            ),
          ],
          child: Navigator(home: _Capture((c) => ctx = c)),
        ),
      );

      _openAppPalette(tester, ctx);
      tester.type('workspace.reload');
      tester.pump();

      final row = _paletteCommandRows(tester).single;
      expect(row.label, 'Reload Workspace');
      expect(row.state.commandId, 'workspace.reload');

      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      await _settleClose(tester);
      expect(calls, ['reload']);
    });

    testWidgets('repeated app palette cycles do not retain stale semantics', (
      tester,
    ) async {
      final calls = <String>[];
      tester.pumpWidget(
        FleuryApp(
          title: 'App',
          commands: [
            AppCommand(
              id: const CommandId('cycle.one'),
              title: 'Cycle One',
              run: (_) {
                calls.add('one');
              },
            ),
            AppCommand(
              id: const CommandId('cycle.two'),
              title: 'Cycle Two',
              run: (_) {
                calls.add('two');
              },
            ),
          ],
          child: Navigator(home: _Capture((c) => ctx = c)),
        ),
      );

      for (final title in ['Cycle One', 'Cycle Two', 'Cycle One']) {
        _openAppPalette(tester, ctx);
        tester.type(title);
        tester.pump();
        expect(
          tester.semantics().byRole(SemanticRole.commandPalette),
          hasLength(1),
        );
        tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
        await _settleClose(tester);
        expect(Navigator.of(ctx).depth, 1);
        expect(tester.semantics().byRole(SemanticRole.commandPalette), isEmpty);
      }

      expect(calls, ['one', 'two', 'one']);
    });

    testWidgets('app palette handles large repeated exact-query cycles', (
      tester,
    ) async {
      final calls = <String>[];
      String id(int index) =>
          'scenario.command.${index.toString().padLeft(5, '0')}';
      String title(int index) =>
          'Scenario Command ${index.toString().padLeft(5, '0')}';
      tester.pumpWidget(
        FleuryApp(
          title: 'App',
          commands: [
            for (var i = 0; i < 128; i++)
              AppCommand(
                id: CommandId(id(i)),
                title: title(i),
                enabled: (_) => i % 17 != 0,
                run: (_) {
                  calls.add(id(i));
                },
              ),
          ],
          screens: [
            FleuryScreen(
              id: const ScreenId('overview'),
              title: 'Overview',
              commands: [
                AppCommand(
                  id: const CommandId('screen.refresh'),
                  title: 'Active Screen Refresh',
                  run: (_) {
                    calls.add('screen.refresh');
                  },
                ),
              ],
              builder: (_) => const Text('Overview body'),
            ),
          ],
          child: Navigator(home: _Capture((c) => ctx = c)),
        ),
      );

      for (final target in [1, 38, 75, 112]) {
        _openAppPalette(tester, ctx);
        tester.type(title(target));
        tester.pump();
        final row = _paletteCommandRows(tester).single;
        expect(row.state.commandId, id(target));
        tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
        await _settleClose(tester);
        expect(Navigator.of(ctx).depth, 1);
        expect(tester.semantics().byRole(SemanticRole.commandPalette), isEmpty);
      }

      expect(calls, [id(1), id(38), id(75), id(112)]);
    });

    testWidgets('app palette mixed repeated semantic and keyboard cycles', (
      tester,
    ) async {
      final calls = <String>[];
      tester.pumpWidget(
        FleuryApp(
          title: 'App',
          commands: [
            AppCommand(
              id: const CommandId('cycle.alpha'),
              title: 'Cycle Alpha',
              run: (_) {
                calls.add('alpha');
              },
            ),
            AppCommand(
              id: const CommandId('cycle.beta'),
              title: 'Cycle Beta',
              run: (_) {
                calls.add('beta');
              },
            ),
          ],
          child: Navigator(home: _Capture((c) => ctx = c)),
        ),
      );

      for (var i = 0; i < 5; i++) {
        final title = i.isEven ? 'Cycle Alpha' : 'Cycle Beta';
        _openAppPalette(tester, ctx);
        tester.type(title);
        tester.pump();
        if (i == 0) {
          tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
        } else if (i == 1) {
          await tester.invokeSemanticAction(
            SemanticAction.submit,
            role: SemanticRole.commandPalette,
          );
        } else if (i == 2) {
          final row = _paletteCommandRows(
            tester,
          ).where((node) => node.label == title).single;
          await tester.invokeSemanticAction(SemanticAction.activate, node: row);
        } else if (i == 3) {
          tester.sendKey(const KeyEvent(keyCode: KeyCode.escape));
        } else {
          await tester.invokeSemanticAction(
            SemanticAction.dismiss,
            role: SemanticRole.commandPalette,
          );
        }
        await _settleClose(tester);
        expect(Navigator.of(ctx).depth, 1, reason: 'cycle $i closed');
        expect(tester.semantics().byRole(SemanticRole.commandPalette), isEmpty);
      }

      expect(calls, ['alpha', 'beta', 'alpha']);
    });

    testWidgets('exposes app command metadata in palette semantics', (tester) {
      tester.pumpWidget(
        FleuryApp(
          title: 'App',
          commands: [
            AppCommand(
              id: const CommandId('file.save'),
              title: 'Save File',
              description: 'Write changes',
              category: 'File',
              shortcuts: [KeyChord.ctrl.s],
              run: (_) {},
            ),
          ],
          child: Navigator(home: _Capture((c) => ctx = c)),
        ),
      );

      _openAppPalette(tester, ctx);

      final command = _paletteCommandRows(tester).single;
      expect(command.label, 'Save File');
      expect(command.state.commandId, 'file.save');
      expect(command.state.shortcut, 'Ctrl+S');
      expect(command.state.commandCategory, 'File');
      expect(command.value, 'Write changes');
    });

    testWidgets('disabled app commands are visible but inert', (tester) async {
      var calls = 0;
      tester.pumpWidget(
        FleuryApp(
          title: 'App',
          commands: [
            AppCommand(
              id: const CommandId('danger.delete'),
              title: 'Delete Everything',
              enabled: (_) => false,
              run: (_) {
                calls += 1;
              },
            ),
          ],
          child: Navigator(home: _Capture((c) => ctx = c)),
        ),
      );

      _openAppPalette(tester, ctx);
      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      await Future<void>.delayed(Duration.zero);
      tester.pump();

      expect(calls, 0);
      expect(Navigator.of(ctx).depth, 2, reason: 'disabled command stays open');
      final command = _paletteCommandRows(tester).single;
      expect(command.label, 'Delete Everything');
      expect(command.enabled, isFalse);
    });

    testWidgets('includes active screen commands before app commands', (
      tester,
    ) async {
      const refresh = CommandId('refresh');
      final calls = <String>[];
      tester.pumpWidget(
        FleuryApp(
          title: 'App',
          commands: [
            AppCommand(
              id: refresh,
              title: 'Global Refresh',
              run: (_) {
                calls.add('global');
              },
            ),
          ],
          screens: [
            FleuryScreen(
              id: const ScreenId('overview'),
              title: 'Overview',
              commands: [
                AppCommand(
                  id: refresh,
                  title: 'Refresh Overview',
                  run: (_) {
                    calls.add('screen');
                  },
                ),
              ],
              builder: (_) => const Text('Overview body'),
            ),
          ],
          child: Navigator(home: _Capture((c) => ctx = c)),
        ),
      );

      _openAppPalette(tester, ctx);

      final paletteCommands = _paletteCommandRows(tester);
      expect(paletteCommands.map((node) => node.label), ['Refresh Overview']);
      expect(paletteCommands.single.state.commandId, 'refresh');

      tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
      await Future<void>.delayed(Duration.zero);

      expect(calls, ['screen']);
      await _settleClose(tester);
      expect(Navigator.of(ctx).depth, 1);
    });
  });
}
