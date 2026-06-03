// Selection demo — exercises every visible feature of the
// SelectionArea + Clipboard stack from a real, runnable app.
//
// Run with:
//
//     dart run example/selection_demo.dart
//
// Then:
//
//   - Drag the mouse across any paragraph to highlight it. The
//     selected cells render with inverse video.
//   - Double-click on a word to select just that word.
//   - Triple-click anywhere on a line to select the whole line.
//   - Drag from one paragraph into another — selection crosses the
//     boundary and the joined text includes a newline.
//   - Ctrl+A selects everything below the SelectionArea.
//   - Ctrl+C writes the current selection to your clipboard via
//     OSC 52 (or a platform tool when available).
//   - Esc clears the selection.
//   - Shift+Arrow extends the selection one grapheme at a time —
//     CJK and emoji cross in a single keystroke.
//   - Shift+Up/Down hops the cursor across paragraph boundaries.
//   - Shift+Click extends an existing selection to the click point
//     without disturbing the anchor (and falls through to a fresh
//     anchor when nothing is selected yet).
//   - The "skip me" line uses `Text(allowSelect: false)` — Ctrl+A
//     leaves it out and dragging over it produces no highlight.
//
// The status bar at the bottom mirrors the live selection via
// `onSelectionChanged` so you can see what's being captured.

import 'package:fleury/fleury.dart';

Future<void> main() => runTui(const SelectionDemo());

class SelectionDemo extends StatefulWidget {
  const SelectionDemo({super.key});

  @override
  State<SelectionDemo> createState() => _SelectionDemoState();
}

class _SelectionDemoState extends State<SelectionDemo> {
  String _selectionText = '';

  @override
  Widget build(BuildContext context) {
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyChord.ctrl.c,
          onEvent: (event) {
            event.bubble();
          },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            border: const BoxBorder(style: BorderStyle.rounded),
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: const Text(
              'fleury selection demo',
              style: CellStyle(bold: true, foreground: AnsiColor(14)),
            ),
          ),
          Expanded(
            child: SelectionArea(
              copyOnRelease: true,
              onSelectionChanged: (sel) {
                setState(() => _selectionText = sel?.plainText ?? '');
              },
              child: Container(
                padding: const EdgeInsets.all(1),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Drag to select. Double-click a word. Triple-click a line.',
                    ),
                    Text(''),
                    Text(
                      'Cross-paragraph selections include a newline at the '
                      'row transition, so paste preserves layout.',
                      softWrap: true,
                    ),
                    Text(''),
                    Text(
                      'CJK characters are single-grapheme words — try '
                      'double-clicking 日本語 or 中文 below.',
                    ),
                    Text('  日本語   中文   한국어'),
                    Text(''),
                    Text(
                      'Shift+Arrow extends by one grapheme at a time. '
                      'Ctrl+A selects everything (except the next line). '
                      'Esc clears.',
                    ),
                    Text(''),
                    Text(
                      '[this line opts out of selection]',
                      style: CellStyle(dim: true),
                      allowSelect: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            border: const BoxBorder(style: BorderStyle.rounded),
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Text(
              _selectionText.isEmpty
                  ? ' (drag, double-click, triple-click, or Ctrl+A · Ctrl+C to copy · Esc to clear · Ctrl+C with empty selection to quit) '
                  : ' selected: ${_renderForStatus(_selectionText)} ',
              style: const CellStyle(dim: true),
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _renderForStatus(String s) {
    // Replace embedded newlines so the status fits on one line.
    return '"${s.replaceAll('\n', '↵')}"';
  }
}
