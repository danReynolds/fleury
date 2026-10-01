// Hot reload demo — edit the constants marked EDIT ME, then save.
// Run from packages/fleury with:
//
//   dart run fleury run example/hot_reload_demo.dart
//
// Press → to change the counter before editing. Reload updates the title
// and behavior while the existing count and focus remain. Ctrl+G opens the
// debugger; F5 there restarts the app and resets its state.
//
// An editor debug session can request the same Dart VM-service reloadSources
// RPC. Generated projects enable reload-on-save; in this checkout, use
// Dart: Hot Reload or configure dart.hotReloadOnSave: "allIfDirty".
//
// Existing State fields and initialized globals survive reload; their
// initializers do not run again. Animation primitives run their documented
// reassemble behavior. See doc/hot_reload.md for runtime details.

import 'package:fleury/fleury.dart';

Future<void> main() async {
  // enableHotReload defaults to true; spelled out here so the example
  // is self-explanatory when copied into a real app.
  await runApp(
    const HotReloadDemo(),
    enableHotReload: true,
    onEvent: (event) {
      if (event is KeyEvent && event.hasCtrl && event.code.character == 'c') {
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
    switch (event.code) {
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
    return KeyDetector(
      onKey: (event) {
        if ((_onKey)(event) == KeyEventResult.handled) event.consume();
      },
      child: Focus(
        autofocus: true,
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
              // A handmade bar to demonstrate editing the rendering on reload.
              // Apps can also use `ProgressBar(value: _count / _max)`.
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
      ),
    );
  }
}
