// Spinner: ready-to-use loading indicator built on the discrete
// animation lane.

import '../rendering/cell.dart';
import 'basic.dart' show Text;
import 'frame_builder.dart';
import 'framework.dart';

/// Visual style of a [Spinner]. `braille` is the modern default;
/// `ascii` is the fallback for terminals that don't render
/// Unicode braille reliably (e.g. some constrained SSH setups).
enum SpinnerStyle { braille, ascii }

/// Animated loading indicator that cycles through a small set of
/// glyphs at the configured cadence. Driven by [FrameBuilder] —
/// shares the runtime's TickerScheduler with every other animation,
/// so N concurrent spinners still produce only one underlying
/// timer.
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
    this.cellStyle = CellStyle.empty,
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
