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
//      chain (which doesn't simulate runApp's pre-dispatcher tier).

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury/src/debug/debug_shell.dart';
import 'package:fleury/src/debug/debug_state.dart';
import 'package:test/test.dart';

KeyEvent _ctrl(String c) =>
    KeyEvent(char: c, modifiers: const {KeyModifier.ctrl});
KeyEvent _key(KeyCode k) => KeyEvent(keyCode: k);
TextInputEvent _text(String s) => TextInputEvent(s);

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('DebugController lifecycle', () {
    test('dispose is idempotent and keeps final readable state', () {
      final controller =
          DebugController(const DebugConfig(startMode: DebugMode.docked))
            ..selectTab(DebugTab.tree)
            ..togglePaintFlash()
            ..moveSemanticCursor(3);
      controller.setSemanticTreeProvider(
        () => const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            label: 'Debug root',
          ),
        ),
      );
      controller.setTerminalDiagnosisProvider(
        () => throw StateError('stale terminal diagnosis provider'),
      );

      controller.dispose();
      controller.dispose();

      expect(controller.config.startMode, DebugMode.docked);
      expect(controller.mode, DebugMode.docked);
      expect(controller.tab, DebugTab.tree);
      expect(controller.paintFlash, isTrue);
      expect(controller.semanticCursorIndex, 3);
      expect(controller.semanticSnapshot(), isNull);
      expect(controller.terminalDiagnosisSnapshot(), isNull);
    });

    test('mutating after dispose throws a lifecycle error', () {
      final controller = DebugController(
        const DebugConfig(startMode: DebugMode.fullscreen),
      )..dispose();

      const message = 'DebugController has been disposed.';
      expect(controller.toggleOnOff, _stateError(message));
      expect(controller.toggleExpand, _stateError(message));
      expect(controller.collapseFromFullscreen, _stateError(message));
      expect(() => controller.selectTab(DebugTab.logs), _stateError(message));
      expect(controller.togglePaintFlash, _stateError(message));
      expect(() => controller.moveSemanticCursor(1), _stateError(message));
      expect(controller.resetSemanticCursor, _stateError(message));
      expect(
        () => controller.setSemanticTreeProvider(() => null),
        _stateError(message),
      );
      expect(
        () => controller.setTerminalDiagnosisProvider(() => null),
        _stateError(message),
      );
    });
  });

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

    testWidgets('docked floats the panel over the app\'s edge', (tester) {
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

    testWidgets('the floating panel absorbs clicks (no tap-through)', (tester) {
      // Pointer regions resolve topmost-by-paint-order PER HANDLER KIND, so a
      // panel body with no tap region would let a click fall through to an app
      // button invisibly underneath — impossible under the old split dock,
      // real under float. The panel-wide absorber closes it.
      var appTaps = 0;
      final controller = DebugController(
        const DebugConfig(startMode: DebugMode.docked, panelWidth: 12),
      );
      tester.pumpWidget(
        DebugShell(
          controller: controller,
          // Full-width tappable row: spans under the floating panel too.
          child: GestureDetector(
            onTap: () => appTaps++,
            child: const Text('tap target spanning the full app width'),
          ),
        ),
      );
      tester.render(size: const CellSize(30, 6));

      // Click the app OUTSIDE the panel (col 2) — proves the target works.
      tester.sendMouse(
        const MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: 2,
          row: 0,
        ),
      );
      tester.sendMouse(
        const MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: 2,
          row: 0,
        ),
      );
      expect(appTaps, 1, reason: 'the uncovered app region is tappable');

      // Click the panel BODY (col 25 — inside the float, not a tab chip):
      // absorbed, the hidden app target must not fire.
      tester.sendMouse(
        const MouseEvent(
          kind: MouseEventKind.down,
          button: MouseButton.left,
          col: 25,
          row: 0,
        ),
      );
      tester.sendMouse(
        const MouseEvent(
          kind: MouseEventKind.up,
          button: MouseButton.left,
          col: 25,
          row: 0,
        ),
      );
      expect(
        appTaps,
        1,
        reason: 'a click on the floating panel must not reach the app under it',
      );
    });

    testWidgets('the floating docked panel is opaque (no app bleed-through)', (
      tester,
    ) {
      final controller = DebugController(
        const DebugConfig(startMode: DebugMode.docked, panelWidth: 12),
      );
      // A full-width app line runs under where the panel floats.
      tester.pumpWidget(
        DebugShell(
          controller: controller,
          child: const Text('app content behind the panel'),
        ),
      );
      final buf = tester.render(size: const CellSize(30, 6));
      // The panel floats over cols [18, 30). EVERY covered cell must carry a
      // background (the opaque Surface fill) so nothing behind bleeds through.
      var bleedCells = 0;
      for (var c = 18; c < 30; c++) {
        for (var r = 0; r < 6; r++) {
          if (buf.atColRow(c, r).style.background == null) bleedCells++;
        }
      }
      expect(
        bleedCells,
        0,
        reason: 'a floating panel must paint every cell it covers',
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

    testWidgets('tree tab renders semantic summary when provider is set', (
      tester,
    ) {
      final controller = DebugController(
        const DebugConfig(startMode: DebugMode.fullscreen),
      )..selectTab(DebugTab.tree);
      controller.setSemanticTreeProvider(
        () => const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: SemanticNodeId('text'),
                role: SemanticRole.text,
                label: 'hello',
                focused: true,
              ),
            ],
          ),
        ),
      );

      tester.pumpWidget(
        DebugShell(controller: controller, child: const Text('app')),
      );
      final output = tester.renderToString(
        size: const CellSize(42, 14),
        emptyMark: ' ',
      );

      expect(output, contains('Semantic nodes  2'));
      expect(output, contains('Inspection  v1'));
      expect(output, contains('Actions  0'));
      expect(output, contains('Focus id  text'));
      expect(output, contains('Focused  text hello'));
      expect(output, contains('text  1'));
    });

    testWidgets('tree tab renders a semantic graph outline', (tester) {
      final controller = DebugController(
        const DebugConfig(startMode: DebugMode.fullscreen),
      )..selectTab(DebugTab.tree);
      controller.setSemanticTreeProvider(
        () => const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            label: 'Root',
            children: [
              SemanticNode(
                id: SemanticNodeId('screen:runs'),
                role: SemanticRole.screen,
                label: 'Runs',
                focused: true,
                children: [
                  SemanticNode(
                    id: SemanticNodeId('button:start'),
                    role: SemanticRole.button,
                    label: 'Start',
                    enabled: false,
                    actions: {SemanticAction.activate},
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      tester.pumpWidget(
        DebugShell(controller: controller, child: const Text('app')),
      );
      final output = tester.renderToString(
        size: const CellSize(88, 28),
        emptyMark: ' ',
      );

      expect(output, contains('— semantic graph —'));
      expect(output, contains('[↑/↓] select semantic node'));
      expect(output, contains('Cursor  1/3 app Root'));
      expect(output, contains('— selected node —'));
      expect(output, contains('ID  root'));
      expect(output, contains('app  Root'));
      expect(output, contains('screen  Runs focused'));
      expect(output, contains('button  Start disabled actions:activate'));
    });

    testWidgets('tree tab semantic cursor shows selected node details', (
      tester,
    ) {
      final controller = DebugController(
        const DebugConfig(startMode: DebugMode.fullscreen),
      )..selectTab(DebugTab.tree);
      controller.setSemanticTreeProvider(
        () => const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            label: 'Root',
            children: [
              SemanticNode(
                id: SemanticNodeId('screen:runs'),
                role: SemanticRole.screen,
                label: 'Runs',
                focused: true,
                state: SemanticState({'screenId': 'runs'}),
                children: [
                  SemanticNode(
                    id: SemanticNodeId('button:start'),
                    role: SemanticRole.button,
                    label: 'Start',
                    enabled: false,
                    actions: {SemanticAction.activate},
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      tester.pumpWidget(
        DebugShell(controller: controller, child: const Text('app')),
      );

      expect(tryConsumeDebugKey(controller, _key(KeyCode.arrowDown)), isTrue);
      tester.pump();
      var output = tester.renderToString(
        size: const CellSize(88, 34),
        emptyMark: ' ',
      );

      expect(controller.semanticCursorIndex, 1);
      expect(output, contains('Cursor  2/3 screen Runs'));
      expect(output, contains('ID  screen:runs'));
      expect(output, contains('Role  screen'));
      expect(output, contains('Label  Runs'));
      expect(output, contains('Flags  focused'));
      expect(output, contains('State  screenId:runs'));

      expect(tryConsumeDebugKey(controller, _key(KeyCode.arrowUp)), isTrue);
      tester.pump();
      output = tester.renderToString(
        size: const CellSize(88, 34),
        emptyMark: ' ',
      );

      expect(controller.semanticCursorIndex, 0);
      expect(output, contains('Cursor  1/3 app Root'));
      expect(output, contains('ID  root'));
    });

    testWidgets('tree tab redacts selected semantic node details', (tester) {
      final controller = DebugController(
        const DebugConfig(startMode: DebugMode.fullscreen),
      )..selectTab(DebugTab.tree);
      controller.setSemanticTreeProvider(
        () => const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: SemanticNodeId('field:token'),
                role: SemanticRole.textField,
                label: 'Token',
                value: 'secret-token',
                validationError: 'secret-token invalid',
                state: SemanticState({
                  'redactedValue': true,
                  'text': 'secret-token',
                  'apiToken': 'secret-token',
                  'historyCount': 1,
                }),
              ),
            ],
          ),
        ),
      );

      tester.pumpWidget(
        DebugShell(controller: controller, child: const Text('app')),
      );

      expect(tryConsumeDebugKey(controller, _key(KeyCode.arrowDown)), isTrue);
      tester.pump();
      final output = tester.renderToString(
        size: const CellSize(88, 34),
        emptyMark: ' ',
      );

      expect(output, contains('Cursor  2/2 textField Token'));
      expect(output, contains('Value  <redacted>'));
      expect(output, contains('Error  <redacted>'));
      expect(output, contains('text:<redacted>'));
      expect(output, contains('apiToken:<redacted>'));
      expect(output, contains('Redacted nodes  1'));
      expect(output, isNot(contains('secret-token')));
    });

    testWidgets('tree tab renders app command state from semantics', (tester) {
      final controller = DebugController(
        const DebugConfig(startMode: DebugMode.fullscreen),
      )..selectTab(DebugTab.tree);
      controller.setSemanticTreeProvider(
        () => const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: SemanticNodeId('app'),
                role: SemanticRole.app,
                label: 'Ops Console',
                state: SemanticState({
                  'activeScreenId': 'runs',
                  'screenCount': 2,
                  'commandCount': 1,
                  'statusCount': 1,
                  'lastCommandId': 'refresh',
                  'lastCommandStatus': 'failed',
                }),
                children: [
                  SemanticNode(
                    id: SemanticNodeId('command:go.runs'),
                    role: SemanticRole.command,
                    label: 'Go to Runs',
                    state: SemanticState({
                      'commandId': 'go.runs',
                      'shortcut': 'Ctrl+R',
                      'commandCategory': 'Navigation',
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      tester.pumpWidget(
        DebugShell(controller: controller, child: const Text('app')),
      );
      final output = tester.renderToString(
        size: const CellSize(64, 20),
        emptyMark: ' ',
      );

      expect(output, contains('Active screen  runs'));
      expect(output, contains('Screens  2'));
      expect(output, contains('Commands  1'));
      expect(output, contains('Status  1'));
      expect(output, contains('Last command  refresh failed'));
      expect(output, contains('Go to Runs  go.runs Ctrl+R Navigation'));
    });

    testWidgets('tree tab renders task and capability state from semantics', (
      tester,
    ) {
      final controller = DebugController(
        const DebugConfig(startMode: DebugMode.fullscreen),
      )..selectTab(DebugTab.tree);
      controller.setSemanticTreeProvider(
        () => const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: SemanticNodeId('task:build'),
                role: SemanticRole.task,
                label: 'Build task',
                state: SemanticState({
                  'taskId': 'build',
                  'taskStatus': 'running',
                  'progressCurrent': 3,
                  'progressTotal': 5,
                  'taskEventCount': 8,
                  'lastTaskEventKind': 'output',
                }),
              ),
              SemanticNode(
                id: SemanticNodeId('task:test'),
                role: SemanticRole.task,
                label: 'Test task',
                state: SemanticState({
                  'taskId': 'test',
                  'taskStatus': 'failed',
                  'taskEventCount': 2,
                  'lastTaskEventKind': 'failed',
                }),
              ),
              SemanticNode(
                id: SemanticNodeId('image'),
                role: SemanticRole.image,
                label: 'Preview',
                state: SemanticState({
                  'terminalCapability': 'inlineImages',
                  'capabilityRequirement': 'preferred',
                  'capabilityResolution': 'degraded',
                  'activeFallback': 'glyph image',
                }),
              ),
              SemanticNode(
                id: SemanticNodeId('copy'),
                role: SemanticRole.button,
                label: 'Copy output',
                state: SemanticState({
                  'clipboardCapability': 'osc52Clipboard',
                  'clipboardCapabilityResolution': 'disabledByPolicy',
                  'clipboardFallback': 'in-process register',
                }),
              ),
              SemanticNode(
                id: SemanticNodeId('image:unsafe'),
                role: SemanticRole.image,
                label: 'Native image',
                state: SemanticState({
                  'terminalCapability': 'inlineImages',
                  'capabilityRequirement': 'required',
                  'capabilityResolution': 'unsafe',
                  'activeFallback': 'glyph image',
                }),
              ),
              SemanticNode(
                id: SemanticNodeId('mouse:unsupported'),
                role: SemanticRole.region,
                label: 'Mouse overlay',
                state: SemanticState({
                  'terminalCapability': 'mouse',
                  'capabilityRequirement': 'optional',
                  'capabilityResolution': 'unsupported',
                }),
              ),
              SemanticNode(
                id: SemanticNodeId('log:unsafe'),
                role: SemanticRole.log,
                label: 'Sanitized log',
                state: SemanticState({
                  'outputSanitized': true,
                  'outputTruncated': true,
                  'outputOriginalLength': 4096,
                }),
              ),
              SemanticNode(
                id: SemanticNodeId('trace:output'),
                role: SemanticRole.traceEvent,
                label: 'Task output event',
                state: SemanticState({
                  'taskOutputSanitized': true,
                  'taskOutputOriginalLength': 8192,
                }),
              ),
            ],
          ),
        ),
      );

      tester.pumpWidget(
        DebugShell(controller: controller, child: const Text('app')),
      );
      final output = tester.renderToString(
        size: const CellSize(110, 48),
        emptyMark: ' ',
      );

      expect(output, contains('— effects/tasks —'));
      expect(output, contains('Total  2'));
      expect(output, contains('Running  1'));
      expect(output, contains('Failed  1'));
      expect(output, contains('Events  10'));
      expect(
        output,
        contains('Build task  build running progress:3/5 events:8 last:output'),
      );
      expect(output, contains('Test task  test failed events:2 last:failed'));
      expect(output, contains('— capabilities —'));
      expect(output, contains('Capability nodes  4'));
      expect(output, contains('Degraded  1'));
      expect(output, contains('Policy blocked  1'));
      expect(output, contains('Unsupported  1'));
      expect(output, contains('Unsafe  1'));
      expect(output, contains('Required blocked  1'));
      expect(output, contains('— capability attention —'));
      expect(
        output,
        contains('Copy output  osc52Clipboard clipboard:disabledByPolicy'),
      );
      expect(
        output,
        contains('Native image  inlineImages required unsafe fallback:glyph'),
      );
      expect(output, contains('Mouse overlay  mouse optional unsupported'));
      expect(output, contains('Preview  preferred degraded fallback:glyph'));
      expect(output, contains('Copy output  clipboard:disabledByPolicy'));
      expect(output, contains('— safety state —'));
      expect(output, contains('Sanitized output  2 nodes'));
      expect(output, contains('Truncated output  1 nodes'));
      expect(output, contains('Largest original  8192 chars'));
    });

    testWidgets('tree tab renders terminal diagnosis and capability profile', (
      tester,
    ) {
      final controller = DebugController(
        const DebugConfig(startMode: DebugMode.fullscreen),
      )..selectTab(DebugTab.tree);
      controller.setTerminalDiagnosisProvider(
        () => const TerminalDiagnosis(
          terminal: TerminalProfileReport(
            size: CellSize(80, 24),
            isInteractive: false,
            stdinIsTerminal: false,
            stdoutIsTerminal: false,
            term: 'xterm-256color',
            termProgram: 'Ghostty',
            termProgramVersion: '1.2.3',
          ),
          environment: TerminalEnvironmentReport(
            ssh: true,
            tmux: true,
            noColor: false,
            clicolorForce: false,
            ci: false,
          ),
          capabilities: TerminalCapabilityReport(
            colorMode: ColorMode.truecolor,
            glyphTier: GlyphTier.unicode,
            imageProtocol: ImageProtocol.kitty,
            alternateScreen: false,
            hideCursor: true,
            tmuxPassthrough: true,
            ambiguousCharWidth: AmbiguousCharWidth.narrow,
          ),
          fallbacks: [
            TerminalDiagnosticMessage(
              severity: TerminalDiagnosticSeverity.warning,
              code: 'alternate_screen_unavailable',
              message: 'alt screen unavailable',
            ),
          ],
          warnings: [
            TerminalDiagnosticMessage(
              severity: TerminalDiagnosticSeverity.info,
              code: 'terminal_multiplexer',
              message: 'tmux active',
            ),
          ],
          unsupportedFeatures: ['alternateScreen'],
          compatibility: TerminalCompatibilityReport(
            findings: [
              TerminalCompatibilityFinding(
                feature: TerminalFeature.kittyKeyboard,
                label: 'Kitty keyboard protocol',
                passiveSupported: true,
                passiveEvidence: 'capabilities.kittyKeyboard=confirmed',
                status: TerminalCompatibilityStatus.confirmed,
                probeId: 'kittyKeyboardStatus',
                activeStatus: TerminalProbeStatus.confirmed,
              ),
              TerminalCompatibilityFinding(
                feature: TerminalFeature.imageKitty,
                label: 'Kitty graphics protocol',
                passiveSupported: false,
                passiveEvidence: 'capabilities.imageProtocol=halfBlock',
                status: TerminalCompatibilityStatus.activeConfirmed,
                probeId: 'kittyGraphicsQuery',
                activeStatus: TerminalProbeStatus.confirmed,
                detail: 'probe confirmed image support',
              ),
            ],
          ),
        ),
      );

      tester.pumpWidget(
        DebugShell(controller: controller, child: const Text('app')),
      );
      final output = tester.renderToString(
        size: const CellSize(104, 40),
        emptyMark: ' ',
      );

      expect(output, contains('— terminal profile —'));
      expect(output, contains('Size  80×24'));
      expect(output, contains('Interactive  no'));
      expect(output, contains('TERM  xterm-256color'));
      expect(output, contains('Program  Ghostty 1.2.3'));
      expect(output, contains('Session  ssh tmux'));
      expect(output, contains('— terminal capabilities —'));
      expect(output, contains('Color  truecolor'));
      expect(output, contains('Images  kitty'));
      expect(output, contains('Alt screen  no'));
      expect(output, contains('Fallbacks  1'));
      expect(
        output,
        contains('fallback  alternate_screen_unavailable warning'),
      );
      expect(output, contains('warning  terminal_multiplexer info'));
      expect(output, contains('Unsupported  alternateScreen'));
      expect(output, contains('— active compatibility —'));
      expect(output, contains('Findings  2'));
      expect(output, contains('Confirmed  1'));
      expect(output, contains('Active confirmed  1'));
      expect(
        output,
        contains(
          'Kitty keyboard protocol  confirmed passive:yes active:confirmed',
        ),
      );
      expect(
        output,
        contains(
          'Kitty graphics protocol  activeConfirmed passive:no active:confirmed',
        ),
      );
      expect(output, contains('Semantic tree unavailable'));
    });

    testWidgets('rebuilds tab renders frame reason and timing diagnostics', (
      tester,
    ) async {
      final controller = DebugController(
        const DebugConfig(startMode: DebugMode.fullscreen),
      )..selectTab(DebugTab.rebuilds);
      tester.pumpWidget(
        DebugShell(controller: controller, child: const Text('app')),
      );

      DebugEvents.emitFrame(
        FrameEvent(
          frameNumber: 7,
          reason: 'key:enter',
          build: const Duration(microseconds: 1200),
          layout: const Duration(microseconds: 2300),
          paint: const Duration(microseconds: 3400),
          diff: const Duration(microseconds: 4500),
          dirtyCells: 12,
          dirtyBounds: CellRect.fromLTWH(2, 3, 4, 5),
          dirtySpans: const DirtySpanFrameStats(
            rowCount: 3,
            spanCount: 4,
            coveredCellCount: 12,
            longestSpan: 5,
          ),
          dirtySources: const [
            'build:DemoWidget/_DemoState',
            'paint:RenderText',
          ],
          layoutStats: const RenderLayoutFrameStats(
            performedCount: 8,
            skippedCount: 3,
          ),
          repaintBoundaries: const RepaintBoundaryFrameStats(
            boundaryCount: 2,
            repaintedCount: 1,
            cachedCount: 1,
            emptyCount: 0,
            copiedCellCount: 24,
          ),
          bufferSize: const CellSize(80, 24),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      tester.pump();

      final output = tester.renderToString(
        size: const CellSize(88, 28),
        emptyMark: ' ',
      );
      expect(output, contains('Last frame  #7 key:enter'));
      expect(output, contains('Dirty cells  12/1920'));
      expect(output, contains('Dirty bounds  2,3 4×5'));
      expect(output, contains('Dirty spans  4 spans / 3 rows'));
      expect(output, contains('Layouts  8 run, 3 skipped'));
      expect(
        output,
        contains('Boundaries  2 total, 1 repainted, 1 cached, 24 cells'),
      );
      expect(
        output,
        contains('Sources  build:DemoWidget/_DemoState, paint:RenderText'),
      );
      expect(output, contains('— dirty sources —'));
      expect(output, contains('build:DemoWidget/_DemoState'));
      expect(output, contains('Worst frame  #7 11ms'));
      expect(output, contains('— recent frames —'));
      expect(output, contains('#7  key:enter 11ms 12 dirty 2,3 4×5'));
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
      // 'p' is printable, so it arrives as text (TextInputEvent) and is handled
      // by tryConsumeDebugText — NOT the KeyEvent path.
      final c = DebugController(const DebugConfig());
      expect(
        tryConsumeDebugText(c, _text('p')),
        isFalse,
        reason: 'p must pass through when shell is off',
      );
      c.toggleOnOff(); // → docked
      expect(tryConsumeDebugText(c, _text('p')), isTrue);
      expect(c.paintFlash, isTrue);
      expect(tryConsumeDebugText(c, _text('p')), isTrue);
      expect(c.paintFlash, isFalse);
      // Ctrl+P is a key chord (not text) and is NOT a debug binding — it must
      // pass through even when the shell is open (the app may use it).
      expect(tryConsumeDebugKey(c, _ctrl('p')), isFalse);
    });

    test('Left / Right arrows cycle the panel tabs while open', () {
      final c = DebugController(const DebugConfig(startMode: DebugMode.docked));
      expect(c.tab, DebugTab.live);
      expect(tryConsumeDebugKey(c, _key(KeyCode.arrowRight)), isTrue);
      expect(c.tab, DebugTab.tree);
      expect(tryConsumeDebugKey(c, _key(KeyCode.arrowLeft)), isTrue);
      expect(c.tab, DebugTab.live);
      // Closed → arrows pass through to the app.
      c.toggleOnOff();
      expect(c.mode, DebugMode.off);
      expect(tryConsumeDebugKey(c, _key(KeyCode.arrowRight)), isFalse);
    });

    test('tree cursor keys are scoped to an open Tree tab', () {
      final c = DebugController(
        const DebugConfig(startMode: DebugMode.fullscreen),
      );
      expect(tryConsumeDebugKey(c, _key(KeyCode.arrowDown)), isFalse);
      expect(c.semanticCursorIndex, 0);

      c.selectTab(DebugTab.tree);
      expect(tryConsumeDebugKey(c, _key(KeyCode.arrowDown)), isTrue);
      expect(c.semanticCursorIndex, 1);
      expect(tryConsumeDebugKey(c, _key(KeyCode.arrowUp)), isTrue);
      expect(c.semanticCursorIndex, 0);

      c.moveSemanticCursor(4);
      expect(c.semanticCursorIndex, 4);
      expect(tryConsumeDebugKey(c, _key(KeyCode.home)), isTrue);
      expect(c.semanticCursorIndex, 0);

      c.toggleOnOff();
      expect(c.mode, DebugMode.off);
      expect(tryConsumeDebugKey(c, _key(KeyCode.arrowDown)), isFalse);
    });

    test('left/right arrows cycle tabs while the shell is open', () {
      final c = DebugController(const DebugConfig(startMode: DebugMode.docked));
      expect(c.tab, DebugTab.live);
      expect(tryConsumeDebugKey(c, _key(KeyCode.arrowRight)), isTrue);
      expect(c.tab, DebugTab.tree, reason: 'right advances');
      expect(tryConsumeDebugKey(c, _key(KeyCode.arrowLeft)), isTrue);
      expect(c.tab, DebugTab.live, reason: 'left goes back');
      // Inert while a Logs search owns the arrows, and when the shell is off.
      c
        ..selectTab(DebugTab.logs)
        ..startLogSearch();
      expect(tryConsumeDebugKey(c, _key(KeyCode.arrowRight)), isFalse);
      c.cancelLogSearch();
      c.toggleOnOff();
      expect(c.mode, DebugMode.off);
      expect(tryConsumeDebugKey(c, _key(KeyCode.arrowLeft)), isFalse);
    });

    test('disabled controller consumes nothing', () {
      final c = DebugController(const DebugConfig(enabled: false));
      expect(tryConsumeDebugKey(c, _ctrl('g')), isFalse);
      expect(tryConsumeDebugKey(c, _key(KeyCode.f12)), isFalse);
      expect(c.mode, DebugMode.off);
    });
  });

  group('Logs tab — search & filter (DT3)', () {
    DebugController open() =>
        DebugController(const DebugConfig(startMode: DebugMode.docked))
          ..selectTab(DebugTab.logs);

    test(
      '/ opens search; typing edits the query; Enter commits; Esc clears',
      () {
        final c = open();
        // Printables (incl. '/') arrive as TextInputEvent, not KeyEvent — the
        // parser emits text for printable ASCII. So they route through the text
        // consumer, while Enter/Backspace/Esc are key codes.
        expect(tryConsumeDebugText(c, _text('/')), isTrue);
        expect(c.logSearching, isTrue);
        expect(c.logQuery, isEmpty);

        // Typed characters — including 's' and 'p', which are shortcuts OUTSIDE
        // search — land in the query while the field is open, not the panel.
        for (final ch in ['s', 'p', 'a', 'm']) {
          expect(tryConsumeDebugText(c, _text(ch)), isTrue);
        }
        expect(c.logQuery, 'spam');
        expect(c.paintFlash, isFalse, reason: "'p' typed a char, not a toggle");

        expect(tryConsumeDebugKey(c, _key(KeyCode.backspace)), isTrue);
        expect(c.logQuery, 'spa');

        // Enter leaves input mode but keeps the query as the active filter.
        expect(tryConsumeDebugKey(c, _key(KeyCode.enter)), isTrue);
        expect(c.logSearching, isFalse);
        expect(c.logQuery, 'spa');

        // Esc (a key code) clears the committed query.
        expect(tryConsumeDebugKey(c, _key(KeyCode.escape)), isTrue);
        expect(c.logQuery, isEmpty);
      },
    );

    test('Esc while searching cancels and clears', () {
      final c = open();
      tryConsumeDebugText(c, _text('/'));
      tryConsumeDebugText(c, _text('x'));
      expect(c.logQuery, 'x');
      expect(tryConsumeDebugKey(c, _key(KeyCode.escape)), isTrue);
      expect(c.logSearching, isFalse);
      expect(c.logQuery, isEmpty);
    });

    test('s cycles the source filter all → stdout → stderr → all', () {
      final c = open();
      expect(c.logSourceFilter, LogSourceFilter.all);
      expect(tryConsumeDebugText(c, _text('s')), isTrue);
      expect(c.logSourceFilter, LogSourceFilter.stdout);
      tryConsumeDebugText(c, _text('s'));
      expect(c.logSourceFilter, LogSourceFilter.stderr);
      tryConsumeDebugText(c, _text('s'));
      expect(c.logSourceFilter, LogSourceFilter.all);
    });

    test('p toggles paint-flash via the text path on any open tab', () {
      final c = open()..selectTab(DebugTab.live);
      expect(c.paintFlash, isFalse);
      expect(tryConsumeDebugText(c, _text('p')), isTrue);
      expect(c.paintFlash, isTrue);
    });

    test('/ and s are inert outside the Logs tab', () {
      final c = DebugController(const DebugConfig(startMode: DebugMode.docked))
        ..selectTab(DebugTab.live);
      expect(tryConsumeDebugText(c, _text('/')), isFalse);
      expect(c.logSearching, isFalse);
      expect(tryConsumeDebugText(c, _text('s')), isFalse);
      expect(c.logSourceFilter, LogSourceFilter.all);
    });

    test('while searching, Tab (a key code) still cycles tabs', () {
      final c = open();
      tryConsumeDebugText(c, _text('/'));
      expect(tryConsumeDebugKey(c, _key(KeyCode.tab)), isTrue);
      expect(c.tab, DebugTab.errors, reason: 'logs → errors is the next tab');
    });

    test('shortcuts are inert when the shell is closed', () {
      final c = DebugController(const DebugConfig())..selectTab(DebugTab.logs);
      expect(c.mode, DebugMode.off);
      expect(tryConsumeDebugText(c, _text('/')), isFalse);
      expect(tryConsumeDebugText(c, _text('p')), isFalse);
      expect(c.logSearching, isFalse);
    });

    testWidgets('the Logs tab renders the query and source filters', (tester) {
      final buf = LogBuffer()
        ..add(const LogLine('starting up', LogSource.stdout))
        ..add(const LogLine('boom failure', LogSource.stderr))
        ..add(const LogLine('all good', LogSource.stdout));
      final controller = DebugController(
        const DebugConfig(startMode: DebugMode.docked),
      )..selectTab(DebugTab.logs);
      tester.pumpWidget(
        LogBufferScope(
          buffer: buf,
          child: DebugShell(controller: controller, child: const Text('app')),
        ),
      );
      String out() => tester.renderToString(size: const CellSize(64, 12));

      // Unfiltered: every captured line shows.
      expect(out(), contains('starting up'));
      expect(out(), contains('boom failure'));
      expect(out(), contains('all good'));

      // A search narrows to matching lines.
      controller
        ..startLogSearch()
        ..appendLogQuery('boom');
      final searched = out();
      expect(searched, contains('boom failure'));
      expect(searched, isNot(contains('starting up')));

      // Source filter to stdout hides the stderr line.
      controller.cancelLogSearch();
      controller.cycleLogSource(); // all → stdout
      final stdoutOnly = out();
      expect(stdoutOnly, contains('starting up'));
      expect(stdoutOnly, isNot(contains('boom failure')));
    });
  });
}
