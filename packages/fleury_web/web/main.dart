import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/fleury_web.dart';

void main() {
  runTuiWeb(() => const _Demo());
}

/// A small interactive demo: a focused counter driven by the arrow keys —
/// enough to prove the whole pipeline (input → state → layout → ANSI →
/// xterm.js) works live in a browser.
class _Demo extends StatefulWidget {
  const _Demo();
  @override
  State<_Demo> createState() => _DemoState();
}

class _DemoState extends State<_Demo> {
  int count = 0;

  KeyEventResult _onKey(KeyEvent event) {
    switch (event.keyCode) {
      case KeyCode.arrowUp:
        setState(() => count++);
        return KeyEventResult.handled;
      case KeyCode.arrowDown:
        setState(() => count--);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Focus(
        autofocus: true,
        onKey: _onKey,
        child: Container(
          border: const BoxBorder(
            style: BorderStyle.rounded,
            cellStyle: CellStyle(foreground: AnsiColor(4)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'fleury · live in your browser',
                style: CellStyle(bold: true),
              ),
              const Text(''),
              Text(
                'count  $count',
                style: const CellStyle(foreground: AnsiColor(4), bold: true),
              ),
              const Text(''),
              const Text('↑ / ↓  to change', style: CellStyle(dim: true)),
            ],
          ),
        ),
      ),
    );
  }
}
