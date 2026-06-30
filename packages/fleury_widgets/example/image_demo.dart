// Image rendering demo. Builds a 32×32 gradient in memory, then shows
// it at three different fits side-by-side in a 60×16 layout. Lets you
// eyeball how the half-block renderer handles aspect, letterboxing,
// and edge sampling.
//
// Run (from packages/fleury_widgets):
//
//   dart run example/image_demo.dart
//
// Hot reload works — edit the gradient generator or the fit values
// below, save, watch the image redraw in place.

import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:image/image.dart' as img;

Future<void> main() async {
  // Pre-decode once at startup; the same ImageSource gets fed to each
  // Image widget below so they all share the same cached pixel buffer.
  final source = ImageSource.decoded(_gradient(32, 32));

  await runApp(
    _ImageShowcase(source: source),
    onEvent: (event) {
      if (event is KeyEvent && event.hasCtrl && event.char == 'c') {
        return const ExitRequested();
      }
      return null;
    },
  );
}

/// A 32×32 red→green diagonal gradient with a darker bottom-right
/// quadrant — picked because the contrast makes fit boundaries easy
/// to spot.
img.Image _gradient(int w, int h) {
  final i = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final r = (255 * x / w).round();
      final g = (255 * y / h).round();
      final dark = (x > w / 2 && y > h / 2) ? 0.5 : 1.0;
      i.setPixel(
        x,
        y,
        img.ColorRgb8(
          (r * dark).round(),
          (g * dark).round(),
          ((255 - r) * dark).round(),
        ),
      );
    }
  }
  return i;
}

class _ImageShowcase extends StatelessWidget {
  const _ImageShowcase({required this.source});
  final ImageSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ' fleury image rendering — half-block ',
            style: CellStyle(
              bold: true,
              foreground: const AnsiColor(15),
              background: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 1),
          SizedBox(
            height: 10,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Panel(
                    label: 'fit: fill (stretches)',
                    image: Image(source: source, fit: ImageFit.fill),
                  ),
                ),
                const SizedBox(width: 1),
                Expanded(
                  child: _Panel(
                    label: 'fit: contain (letterbox)',
                    image: Image(source: source, fit: ImageFit.contain),
                  ),
                ),
                const SizedBox(width: 1),
                Expanded(
                  child: _Panel(
                    label: 'fit: cover (crop)',
                    image: Image(source: source, fit: ImageFit.cover),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 1),
          Text(
            'Each cell uses ▀ with truecolor fg/bg — two pixels per cell. '
            'AnsiRenderer downsamples to your terminal\'s color depth.',
            style: theme.mutedStyle,
          ),
          Text('ctrl+c quits', style: theme.mutedStyle),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.label, required this.image});
  final String label;
  final Widget image;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: theme.mutedStyle),
        Expanded(child: image),
      ],
    );
  }
}
