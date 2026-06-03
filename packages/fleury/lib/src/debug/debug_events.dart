// Debug-event stream — the source of truth that every debug surface
// (in-terminal panel, future browser DevTools, golden-test fixtures)
// subscribes to. Single broadcast stream means the framework emits
// timing/lifecycle events exactly once, and any number of consumers
// can render or record them however they like.
//
// Events are sealed so consumers can exhaustively switch on them.
// Wire format is the in-memory shape; serialisation to JSON for the
// future browser panel is a thin pass.

import 'dart:async';

import '../foundation/geometry.dart';
import '../rendering/render_layout_stats.dart';
import '../rendering/render_repaint_boundary.dart';
import '../terminal/diagnostics.dart';
import '../terminal/events.dart';

/// One frame's per-phase timing breakdown plus the headline counters
/// the live overlay shows. Emitted once per rendered frame.
final class FrameEvent {
  const FrameEvent({
    required this.frameNumber,
    required this.reason,
    required this.build,
    required this.layout,
    required this.paint,
    required this.diff,
    required this.dirtyCells,
    this.dirtyBounds,
    this.dirtySources = const <String>[],
    this.layoutStats = RenderLayoutFrameStats.empty,
    this.repaintBoundaries = RepaintBoundaryFrameStats.empty,
    required this.bufferSize,
  });

  /// Monotonically increasing, never wraps.
  final int frameNumber;

  /// Best-effort reason the frame was scheduled.
  final String reason;
  final Duration build;
  final Duration layout;
  final Duration paint;
  final Duration diff;
  final int dirtyCells;

  /// Bounding rectangle for emitted dirty cells, or null when the frame
  /// produced no diff.
  final CellRect? dirtyBounds;

  /// Best-effort build/layout/paint invalidation sources that caused this
  /// frame.
  final List<String> dirtySources;

  /// Render-layout cache activity observed during the layout phase.
  final RenderLayoutFrameStats layoutStats;

  /// Repaint-boundary cache activity observed during the paint phase.
  final RepaintBoundaryFrameStats repaintBoundaries;

  final CellSize bufferSize;

  Duration get total => build + layout + paint + diff;
}

/// Sealed parent — gives consumers exhaustive switch coverage and
/// leaves room for future event types (`RebuildEvent`, `LayoutEvent`,
/// `LogEvent`) without breaking existing matches.
sealed class DebugEvent {
  const DebugEvent();
}

final class FrameDebugEvent extends DebugEvent {
  const FrameDebugEvent(this.frame);
  final FrameEvent frame;
}

final class InputDebugEvent extends DebugEvent {
  const InputDebugEvent({
    required this.kind,
    required this.summary,
    this.resizeSize,
  });

  factory InputDebugEvent.fromTuiEvent(TuiEvent event) {
    return switch (event) {
      KeyEvent(:final keyCode, :final char, :final modifiers, :final type) =>
        InputDebugEvent(
          kind: 'key',
          summary: [
            if (modifiers.isNotEmpty)
              modifiers.map((modifier) => modifier.name).join('+'),
            keyCode?.name ?? char ?? '?',
            if (type != KeyEventType.down) type.name,
          ].join('+'),
        ),
      TextInputEvent(:final text) => InputDebugEvent(
        kind: 'text',
        summary: '${text.length} chars',
      ),
      PasteEvent(:final text) => InputDebugEvent(
        kind: 'paste',
        summary: '${text.length} chars',
      ),
      ResizeEvent(:final size) => InputDebugEvent(
        kind: 'resize',
        summary: '${size.cols}x${size.rows}',
        resizeSize: size,
      ),
      MouseEvent(:final kind, :final button, :final col, :final row) =>
        InputDebugEvent(
          kind: 'mouse',
          summary: '${kind.name}:${button.name}@$col,$row',
        ),
    };
  }

  final String kind;
  final String summary;
  final CellSize? resizeSize;
}

final class TerminalDebugEvent extends DebugEvent {
  const TerminalDebugEvent(this.diagnosis);
  final TerminalDiagnosis diagnosis;
}

/// Global broadcast bus. Always alive (no setup), so framework code
/// can emit unconditionally — `runTui` wires this through to the
/// debug panel; tests or external observers can also subscribe.
///
/// When no one is listening, broadcast streams drop events on the
/// floor — so the cost is one StreamController.add() per frame even
/// in production. Cheap.
final class DebugEvents {
  DebugEvents._();

  static final StreamController<DebugEvent> _controller =
      StreamController<DebugEvent>.broadcast();

  /// Subscribe to every event the framework emits. Hot stream — late
  /// subscribers miss past events by design.
  static Stream<DebugEvent> get stream => _controller.stream;

  /// True if any subscriber is currently listening. Callers should
  /// gate the *cost* of producing an event on this — measurement
  /// itself (Stopwatches, structured record allocation) is much more
  /// expensive than the `.add()` skipped inside [emitFrame] when no
  /// one's listening. Production with no debug surface attached pays
  /// nothing.
  static bool get hasListeners => _controller.hasListener;

  /// Emit a frame-timing record. Called from `runTui.renderFrame`.
  /// Callers should gate the *capture* on [hasListeners] (skipping
  /// Stopwatch + record allocation) — this method's own no-listener
  /// short-circuit only avoids the broadcast cost.
  static void emitFrame(FrameEvent frame) {
    if (!_controller.hasListener) return;
    _controller.add(FrameDebugEvent(frame));
  }

  static void emitInput(TuiEvent event) {
    if (!_controller.hasListener) return;
    _controller.add(InputDebugEvent.fromTuiEvent(event));
  }

  static void emitTerminalDiagnosis(TerminalDiagnosis diagnosis) {
    if (!_controller.hasListener) return;
    _controller.add(TerminalDebugEvent(diagnosis));
  }
}
