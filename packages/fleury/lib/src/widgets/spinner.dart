// Spinner: ready-to-use loading indicator built on the discrete
// animation lane.
//
// Spinner is the reference consumer of the discrete animation lane
// (FrameBuilder + the shared TickerScheduler). The primitive layer's async
// affordances use it; composed progress widgets live in src/catalog.

import '../rendering/cell.dart';
import 'basic.dart' show Text;
import 'frame_builder.dart';
import 'framework.dart';

/// Visual style of a [Spinner]. `braille` is the modern default;
/// `ascii` is the fallback for terminals that don't render
/// Unicode braille reliably (e.g. some constrained SSH setups).
enum SpinnerStyle { braille, ascii }

/// Animated loading indicator: a cycling glyph with an optional [label]
/// beside it.
///
/// Use it for work whose progress can't be measured. The glyph advances every
/// [frameInterval]. Every spinner shares the app's animation timer, so showing
/// many at once stays cheap. A spinner holds its current glyph while animation
/// is paused around it, such as under `TickerMode(enabled: false)`.
///
/// ```dart
/// Spinner(label: 'Connecting')
/// ```
class Spinner extends StatelessWidget {
  const Spinner({
    super.key,
    this.style = SpinnerStyle.braille,
    this.label,
    this.frameInterval = const Duration(milliseconds: 80),
    this.cellStyle = CellStyle.none,
  });

  /// Glyph set to cycle through.
  final SpinnerStyle style;

  /// Optional label rendered to the right of the glyph, separated
  /// by a single space.
  final String? label;

  /// How long to hold each frame. Defaults to 80 ms, which is the
  /// rate most spinner implementations agree on as "smooth without
  /// being distracting."
  final Duration frameInterval;

  /// Cell style applied to the rendered text.
  final CellStyle cellStyle;

  static const _brailleFrames = <String>[
    '⠋',
    '⠙',
    '⠹',
    '⠸',
    '⠼',
    '⠴',
    '⠦',
    '⠧',
    '⠇',
    '⠏',
  ];
  static const _asciiFrames = <String>['|', '/', '-', r'\'];

  @override
  Widget build(BuildContext context) {
    final frames = style == SpinnerStyle.braille
        ? _brailleFrames
        : _asciiFrames;
    return FrameBuilder(
      interval: frameInterval,
      builder: (ctx, frame, elapsed, delta) {
        final glyph = frames[frame % frames.length];
        final text = label == null ? glyph : '$glyph $label';
        return Text(text, style: cellStyle, softWrap: false);
      },
    );
  }
}
