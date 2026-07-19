// Hot reload demo — edit any of the constants marked `EDIT ME` below,
// save the file, and watch the running terminal update without losing
// the counter value or the cursor position.
//
// Supported workflow:
//
//   1. VS Code: open packages/fleury, press F5. fleury ships a
//      `.vscode/launch.json` that points Dart-Code at an integrated
//      terminal. After editing, run `Dart: Hot Reload` from the command
//      palette. To reload on save, opt into
//      `dart.hotReloadOnSave: "allIfDirty"` in your user settings.
//
//   2. Another debugger or tool may use the same Dart VM-service
//      `reloadSources` RPC. Merely enabling the VM service or watching
//      files is not enough: a VM-service client must request the reload.
//
// What hot reload DOES preserve: counter value, focus position,
// scroll offsets, and State fields. Animation primitives run their
// documented reassemble behavior.
// What it does NOT preserve: anything you compute in main() or
// top-level state that is set once at startup.

import 'package:fleury/fleury.dart';

Future<void> main() async {
  // enableHotReload defaults to true; spelled out here so the example
  // is self-explanatory when copied into a real app.
  await runApp(
    const HotReloadDemo(),
    enableHotReload: true,
    onEvent: (event) {
      if (event is KeyEvent && event.hasCtrl && event.char == 'c') {
        return const ExitRequested();
      }
      return null;
    },
  );
}

String _renderBar(double t, int width) {
  final filled = (t.clamp(0.0, 1.0) * width).round();
  return '${'█' * filled}${'░' * (width - filled)}';
}

class HotReloadDemo extends StatefulWidget {
  const HotReloadDemo({super.key});
  @override
  State<HotReloadDemo> createState() => _HotReloadDemoState();
}

class _HotReloadDemoState extends State<HotReloadDemo> {
  int _count = 0;

  // EDIT ME ↓ — change this string, save the file, watch the title
  // update in place. The counter stays where it is.
  static const _title = ' fleury hot reload — try editing me ';

  // EDIT ME ↓ — flip between AnsiColor(1)/2/3/4/5/6 to see the title
  // recolor live without losing focus.
  static const _titleColor = AnsiColor(4);

  // EDIT ME ↓ — try changing this Step or the upper bound.
  static const _step = 1;
  static const _max = 100;

  void _inc() => setState(() => _count = (_count + _step).clamp(0, _max));
  void _dec() => setState(() => _count = (_count - _step).clamp(0, _max));

  KeyEventResult _onKey(KeyEvent event) {
    switch (event.keyCode) {
      case KeyCode.arrowRight:
        _inc();
        return KeyEventResult.handled;
      case KeyCode.arrowLeft:
        _dec();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      autofocus: true,
      onKey: _onKey,
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _title,
              style: CellStyle(
                bold: true,
                foreground: const AnsiColor(15),
                background: _titleColor,
              ),
            ),
            const SizedBox(height: 1),
            // EDIT ME ↓ — switch this whole block out for a Row,
            // a different widget tree, etc.
            Text('count: $_count', style: const CellStyle(bold: true)),
            const SizedBox(height: 1),
            // A handmade bar so this example needs only fleury — no
            // fleury_widgets dependency. Real apps would just drop in
            // `ProgressBar(value: _count / _max)`.
            Text(_renderBar(_count / _max, 30)),
            const SizedBox(height: 1),
            Text(
              '←/→: −$_step / +$_step    ctrl+c: quit',
              style: theme.mutedStyle,
            ),
            const SizedBox(height: 2),
            Text(
              'edit the constants marked EDIT ME in this file, save, '
              'and watch this app update without restarting',
              style: theme.mutedStyle,
            ),
            Text(
              'counter survives the reload — try +1 a few times before editing',
              style: theme.mutedStyle,
            ),
            const SizedBox(height: 1),
            Text('ctrl+c quits', style: theme.mutedStyle),
          ],
        ),
      ),
    );
  }
}
