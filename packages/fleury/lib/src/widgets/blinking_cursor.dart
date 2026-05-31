// BlinkingCursor: cursor that alternates between visible and
// invisible on the discrete animation lane.

import '../rendering/cell.dart';
import 'basic.dart' show Text;
import 'frame_builder.dart';
import 'framework.dart';

/// A single-cell cursor that blinks at the configured cadence.
/// Even-numbered frames show the [glyph]; odd-numbered frames show
/// a space (same width, preserves layout).
///
/// Idiomatic TextInput cursor is `BlinkingCursor()` at the default
/// 500 ms interval. For a non-blinking cursor (e.g. when the
/// widget is unfocused) use [Text] directly.
class BlinkingCursor extends StatelessWidget {
  const BlinkingCursor({
    super.key,
    this.glyph = '█',
    this.style = const CellStyle(inverse: true),
    this.blinkInterval = const Duration(milliseconds: 500),
  });

  /// Single-character glyph painted on "on" frames.
  final String glyph;

  /// Cell style for the cursor glyph. Defaults to inverse, which
  /// reads as a block cursor on most terminals.
  final CellStyle style;

  /// On/off cadence. Defaults to 500 ms, matching the convention
  /// of most native terminal cursors.
  final Duration blinkInterval;

  @override
  Widget build(BuildContext context) {
    return FrameBuilder(
      interval: blinkInterval,
      builder: (ctx, frame, elapsed, delta) {
        final visible = frame.isEven;
        return Text(
          visible ? glyph : ' ',
          style: visible ? style : CellStyle.empty,
          softWrap: false,
        );
      },
    );
  }
}
