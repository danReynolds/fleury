import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury_samples/samples.dart';

/// Runnable showcase apps for Fleury, mirroring the storybook CLI:
///
///   dart run packages/samples/bin/samples.dart <app>
///   fleury dev samples <app>            (via tool/fleury_dev.dart)
///
/// Apps: dashboard | files | editor | agent | finance | asteroids | sprite |
/// debug.
const Map<String, (String, Widget Function())> _apps =
    <String, (String, Widget Function())>{
      'dashboard': ('htop-style live system monitor', DashboardApp.new),
      'files': ('two-pane keyboard file manager', FileManagerApp.new),
      'editor': ('nano/vim file editor you can toggle live', EditorApp.new),
      'agent': ('Claude-Code-style coding-agent TUI', AgentApp.new),
      'finance': (
        'personal finance dashboard and transaction explorer',
        FinanceApp.new,
      ),
      'asteroids': ('real-time neon vector arcade game', NeonAsteroidsApp.new),
      'sprite': (
        'paint and animate portable ANSI sprites',
        AnsiSpriteStudioApp.new,
      ),
      'debug': (
        'debug-shell + agent-devtools playground',
        DebugPlaygroundApp.new,
      ),
    };

Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('-')).toList();
  if (args.contains('-h') || args.contains('--help')) {
    _printUsage();
    return;
  }
  if (positional.isEmpty || positional.first == 'list') {
    _printUsage();
    return;
  }

  final name = positional.first;
  final entry = _apps[name];
  if (entry == null) {
    stderr.writeln('Unknown app: $name');
    _printUsage();
    exit(2);
  }

  // `asteroids --turbo`: the RFC 0021 pixel ceiling — the same game,
  // rasterized to real antialiased pixels where the surface supports it.
  final home = name == 'asteroids' && args.contains('--turbo')
      ? const NeonAsteroidsApp(turbo: true)
      : entry.$2();

  await runApp(
    FleuryApp(title: 'Fleury $name sample', home: withQuitKey(home)),
    // No keyboard flags: `asteroids` needs real key releases and `dashboard`
    // does not, and neither has to say so. The framework asks the terminal for
    // everything it can safely give and negotiates down transactionally.
    mode: const TerminalMode(mouse: true),
    // Which sample to run comes from argv, and a dev hot-restart re-runs this
    // entrypoint — so hand argv over or the respawn lands on the usage banner.
    args: args,
  );
}

/// Wraps a sample's root so the advertised `q` key quits.
///
/// Typed printables arrive as [TextInputEvent]s (the parser never emits a
/// bare `KeyEvent` for them), so quit must be a widget-level [KeyBinding]
/// routed through the dispatcher — an `onEvent` match on `KeyEvent.char`
/// can never fire, and matching the raw [TextInputEvent] there would quit
/// while the user types `q` into the agent sample's prompt. Bound this
/// way, a focused text field claims the character first and [requestExit]
/// fires only when nothing does. (Ctrl+C keeps working via runApp's
/// built-in unhandled-Ctrl+C escape hatch.)
Widget withQuitKey(Widget app) => KeyBindings(
  bindings: [
    KeyBinding(KeySequence.q, onTrigger: (_) => requestExit(), label: 'Quit'),
  ],
  child: app,
);

void _printUsage() {
  stdout.writeln('Fleury sample apps');
  stdout.writeln('');
  stdout.writeln('Usage: dart run bin/samples.dart <app>');
  stdout.writeln('');
  stdout.writeln('Apps:');
  for (final entry in _apps.entries) {
    stdout.writeln('  ${entry.key.padRight(11)} ${entry.value.$1}');
  }
  stdout.writeln('');
  stdout.writeln('Press q or Ctrl-C to quit a running app.');
}
