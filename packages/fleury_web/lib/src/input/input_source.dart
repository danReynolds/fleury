import 'package:fleury/fleury_host.dart';

import '../metrics/cell_metrics.dart';

typedef TuiInputSink = void Function(TuiEvent event);

/// Source of already-normalized Fleury input events for a web host.
abstract interface class TuiInputSource {
  /// Starts forwarding host input events to [onEvent].
  void start(TuiInputSink onEvent);

  /// Synchronizes host caret affordances after a frame has painted.
  ///
  /// Implementations must not read layout here. [metrics] is the last
  /// measurement produced during the host read phase; [caretRect] is the latest
  /// focused text caret rect in screen-cell coordinates.
  void syncCaretGeometry(CellRect? caretRect, MeasuredCellBox? metrics);

  /// Stops forwarding events and releases host resources.
  void dispose();
}

/// Optional capability for sources that own browser keyboard capture.
abstract interface class KeyboardCaptureTarget {
  /// Restores keyboard/IME capture to the hidden browser input target.
  void ensureKeyboardCapture();
}
