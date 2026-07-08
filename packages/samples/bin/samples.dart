import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury_samples/samples.dart';

/// Runnable showcase apps for Fleury, mirroring the storybook CLI:
///
///   dart run packages/samples/bin/samples.dart <app>
///   fleury dev samples <app>            (via tool/fleury_dev.dart)
///
/// Apps: dashboard | files | agent.
const Map<String, (String, Widget Function())> _apps =
    <String, (String, Widget Function())>{
      'dashboard': ('htop-style live system monitor', DashboardApp.new),
      'files': ('two-pane keyboard file manager', FileManagerApp.new),
      'agent': ('Claude-Code-style coding-agent TUI', AgentApp.new),
      'debug': ('debug-shell + agent-devtools playground', DebugPlaygroundApp.new),
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

  await runApp(
    entry.$2(),
    mode: const TerminalMode(mouse: true),
    onEvent: (event) {
      if (event is KeyEvent &&
          ((event.hasCtrl && event.char == 'c') || event.char == 'q')) {
        return const ExitRequested();
      }
      return null;
    },
  );
}

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
