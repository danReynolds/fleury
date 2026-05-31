// DebugShell layout + escape-hatch dispatch tests.
//
// Two surfaces under test:
//   1. The WIDGET layout: off/docked/fullscreen render correctly given
//      a controller's mode. Driven by toggling the controller directly
//      (the visual contract — the renderer doesn't care how mode
//      changes happened).
//   2. The escape-hatch dispatcher: `tryConsumeDebugKey` interprets a
//      KeyEvent against the controller. Lives outside the widget tree
//      so it can fire even inside Navigator's modal-route suppression,
//      so it's tested directly rather than through the tester's focus
//      chain (which doesn't simulate runTui's pre-dispatcher tier).

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury/src/debug/debug_shell.dart';
import 'package:fleury/src/debug/debug_state.dart';
import 'package:test/test.dart';

KeyEvent _ctrl(String c) =>
    KeyEvent(char: c, modifiers: const {KeyModifier.ctrl});
KeyEvent _key(KeyCode k) => KeyEvent(keyCode: k);

void main() {
  group('DebugShell — widget layout', () {
    testWidgets('off mode is a pass-through (app paints into full viewport)', (
      tester,
    ) {
      final controller = DebugController(const DebugConfig());
      tester.pumpWidget(
        DebugShell(controller: controller, child: const Text('hello')),
      );
      final buf = tester.render(size: const CellSize(40, 4));
      expect(controller.mode, DebugMode.off);
      expect(buf.atColRow(0, 0).grapheme, 'h');
      // No panel content anywhere.
      var anyPanelGlyph = false;
      for (var c = 10; c < 40; c++) {
        for (var r = 0; r < 4; r++) {
          final g = buf.atColRow(c, r).grapheme;
          if (g != null && g != ' ' && g != 'e' && g != 'l' && g != 'o') {
            anyPanelGlyph = true;
          }
        }
      }
      expect(
        anyPanelGlyph,
        isFalse,
        reason: 'off mode mounts no panel widgets',
      );
    });

    testWidgets('docked reflows the app into the remaining cells', (tester) {
      final controller = DebugController(
        const DebugConfig(startMode: DebugMode.docked, panelWidth: 10),
      );
      tester.pumpWidget(
        DebugShell(controller: controller, child: const Text('hello')),
      );
      final buf = tester.render(size: const CellSize(30, 4));
      expect(buf.atColRow(0, 0).grapheme, 'h');
      var panelHasContent = false;
      for (var c = 20; c < 30; c++) {
        for (var r = 0; r < 4; r++) {
          final g = buf.atColRow(c, r).grapheme;
          if (g != null && g != ' ') {
            panelHasContent = true;
          }
        }
      }
      expect(
        panelHasContent,
        isTrue,
        reason: 'docked panel must paint into its allocated region',
      );
    });

    testWidgets('disabled config short-circuits to pure pass-through', (
      tester,
    ) {
      final controller = DebugController(const DebugConfig(enabled: false));
      tester.pumpWidget(
        DebugShell(controller: controller, child: const Text('app')),
      );
      final buf = tester.render(size: const CellSize(10, 1));
      expect(buf.atColRow(0, 0).grapheme, 'a');
      // Even an explicit mode flip is honoured by the layout — the
      // disabled gate only skips structural wrapping, not the
      // controller itself.
      controller.toggleOnOff();
      expect(controller.mode, DebugMode.docked);
      // But the shell still doesn't render the panel because disabled
      // returns child verbatim.
      final buf2 = tester.render(size: const CellSize(10, 1));
      expect(
        buf2.atColRow(0, 0).grapheme,
        'a',
        reason:
            'disabled shell never mounts the panel even if mode '
            'changes',
      );
    });
  });

  group('tryConsumeDebugKey — escape-hatch dispatch', () {
    test('Ctrl+G toggles off ↔ last-used open mode', () {
      final c = DebugController(const DebugConfig());
      expect(c.mode, DebugMode.off);
      expect(tryConsumeDebugKey(c, _ctrl('g')), isTrue);
      expect(c.mode, DebugMode.docked);
      expect(tryConsumeDebugKey(c, _ctrl('g')), isTrue);
      expect(c.mode, DebugMode.off);
    });

    test('Ctrl+G remembers fullscreen across off cycles', () {
      final c = DebugController(const DebugConfig());
      tryConsumeDebugKey(c, _ctrl('g')); // off → docked
      c.toggleExpand(); // docked → fullscreen
      tryConsumeDebugKey(c, _ctrl('g')); // fullscreen → off
      tryConsumeDebugKey(c, _ctrl('g')); // off → fullscreen (restored)
      expect(c.mode, DebugMode.fullscreen);
    });

    test('F11 expands/collapses only while open', () {
      final c = DebugController(const DebugConfig());
      expect(
        tryConsumeDebugKey(c, _key(KeyCode.f11)),
        isFalse,
        reason: 'F11 must not consume while off — app may use it',
      );
      c.toggleOnOff(); // → docked
      expect(tryConsumeDebugKey(c, _key(KeyCode.f11)), isTrue);
      expect(c.mode, DebugMode.fullscreen);
    });

    test('Esc only consumes in fullscreen', () {
      final c = DebugController(
        const DebugConfig(startMode: DebugMode.fullscreen),
      );
      expect(tryConsumeDebugKey(c, _key(KeyCode.escape)), isTrue);
      expect(c.mode, DebugMode.docked);
      expect(
        tryConsumeDebugKey(c, _key(KeyCode.escape)),
        isFalse,
        reason: 'docked: Esc passes through to the app',
      );
      c.toggleOnOff(); // → off
      expect(
        tryConsumeDebugKey(c, _key(KeyCode.escape)),
        isFalse,
        reason: 'off: Esc passes through to the app',
      );
    });

    test('F12 opens with Logs / toggles closed when already on Logs', () {
      final c = DebugController(const DebugConfig());
      expect(tryConsumeDebugKey(c, _key(KeyCode.f12)), isTrue);
      expect(c.mode, DebugMode.docked);
      expect(c.tab, DebugTab.logs);
      // F12 again, still on Logs → close.
      expect(tryConsumeDebugKey(c, _key(KeyCode.f12)), isTrue);
      expect(c.mode, DebugMode.off);
    });

    test('F12 switches tab when open on a different tab (no close)', () {
      final c = DebugController(const DebugConfig());
      c.toggleOnOff(); // open on Live (default)
      expect(c.tab, DebugTab.live);
      expect(tryConsumeDebugKey(c, _key(KeyCode.f12)), isTrue);
      expect(
        c.mode,
        DebugMode.docked,
        reason: 'switching to Logs from another tab must not close',
      );
      expect(c.tab, DebugTab.logs);
    });

    test('p toggles paint-flash only while open, otherwise passes through', () {
      final c = DebugController(const DebugConfig());
      expect(
        tryConsumeDebugKey(c, const KeyEvent(char: 'p')),
        isFalse,
        reason: 'p must pass through when shell is off',
      );
      c.toggleOnOff(); // → docked
      expect(tryConsumeDebugKey(c, const KeyEvent(char: 'p')), isTrue);
      expect(c.paintFlash, isTrue);
      expect(tryConsumeDebugKey(c, const KeyEvent(char: 'p')), isTrue);
      expect(c.paintFlash, isFalse);
      // Ctrl+P / Alt+P are NOT debug bindings — must pass through even
      // when shell is open (user app may use them).
      expect(tryConsumeDebugKey(c, _ctrl('p')), isFalse);
    });

    test('disabled controller consumes nothing', () {
      final c = DebugController(const DebugConfig(enabled: false));
      expect(tryConsumeDebugKey(c, _ctrl('g')), isFalse);
      expect(tryConsumeDebugKey(c, _key(KeyCode.f12)), isFalse);
      expect(c.mode, DebugMode.off);
    });
  });
}
