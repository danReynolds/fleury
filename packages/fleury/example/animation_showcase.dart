// Animation showcase. Exercises the animation system in one screen:
//
//   - Spinner (braille and ascii style)        [discrete lane]
//   - BlinkingCursor                           [discrete lane]
//   - TypingIndicator (see _TypingIndicator)   [discrete lane]
//   - AnimatedProgressBar — value-tracks-state Animation<int>
//   - Continuous slide — looping Animation<int>
//
// Run:
//   cd packages/fleury
//   dart pub get
//   dart run example/animation_showcase.dart
//
//   Press Space to bump the progress bar forward.
//   Press Ctrl+C to exit.

import 'package:fleury/fleury.dart';

Future<void> main() async {
  await runApp(
    const _ShowcaseApp(),
    onEvent: (event) {
      if (event is KeyEvent && event.hasCtrl && event.char == 'c') {
        return const ExitRequested();
      }
      return null;
    },
  );
}

class _ShowcaseApp extends StatefulWidget {
  const _ShowcaseApp();

  @override
  State<_ShowcaseApp> createState() => _ShowcaseAppState();
}

class _ShowcaseAppState extends State<_ShowcaseApp> {
  double _progress = 0.0;
  // A looping Animation drives the slide — no controller, no vsync mixin.
  late final Animation<int> _slide = Animation(0)
    ..loop(
      between: (0, 30),
      period: const Duration(seconds: 2),
      curve: Curves.easeInOut,
    );

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  void _bumpProgress() {
    setState(() {
      _progress = (_progress + 0.1).clamp(0.0, 1.0);
      if (_progress >= 1.0) _progress = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyChord.char(' '),
          label: 'bump progress',
          onEvent: (_) => _bumpProgress(),
        ),
      ],
      child: Container(
        border: const BoxBorder(style: BorderStyle.rounded),
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              ' fleury animation showcase ',
              style: CellStyle(bold: true, foreground: AnsiColor(14)),
            ),
            const Text(''),
            Row(
              children: [
                const SizedBox(width: 22, child: Text(' Spinner (braille)')),
                const Spinner(),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 22, child: Text(' Spinner + label')),
                const Spinner(label: 'Connecting'),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 22, child: Text(' Spinner (ascii)')),
                const Spinner(style: SpinnerStyle.ascii),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 22, child: Text(' BlinkingCursor')),
                const BlinkingCursor(),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 22, child: Text(' TypingIndicator')),
                const _TypingIndicator(),
              ],
            ),
            const Text(''),
            const Text(' Progress (Space to bump):'),
            _AnimatedProgressBar(value: _progress, width: 30),
            const Text(''),
            const Text(' Continuous slide (looping Animation<int>):'),
            Text('${' ' * _slide.value}●', softWrap: false),
            const Text(''),
            const Text(' Ctrl+C exits.', style: CellStyle(dim: true)),
          ],
        ),
      ),
    );
  }
}

/// Three-dot typing indicator built on the discrete animation lane.
/// Cycles `.`, `..`, `...` at 400 ms per state.
class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return FrameBuilder(
      interval: const Duration(milliseconds: 400),
      builder: (ctx, frame, elapsed, delta) {
        final dots = '.' * ((frame % 3) + 1);
        return Text(
          'typing$dots   ', // trailing spaces clear leftover dots
          softWrap: false,
        );
      },
    );
  }
}

/// A horizontal progress bar that smoothly animates between value
/// changes. The value-tracks-state pattern: an `Animation<int>` whose
/// target follows `widget.value`. Retargeting preserves the current
/// fill, so successive bumps chain smoothly with no bookkeeping.
class _AnimatedProgressBar extends StatefulWidget {
  const _AnimatedProgressBar({required this.value, required this.width});
  final double value;
  final int width;

  @override
  State<_AnimatedProgressBar> createState() => _AnimatedProgressBarState();
}

class _AnimatedProgressBarState extends State<_AnimatedProgressBar> {
  late final Animation<int> _fill = Animation(
    (widget.value * widget.width).round(),
  );

  @override
  void didUpdateWidget(_AnimatedProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value || widget.width != oldWidget.width) {
      _fill.to(
        (widget.value * widget.width).round(),
        curve: Curves.easeOut,
        duration: const Duration(milliseconds: 300),
      );
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cells = _fill.value.clamp(0, widget.width);
    return Text(
      '${'█' * cells}${'░' * (widget.width - cells)}',
      softWrap: false,
    );
  }
}
