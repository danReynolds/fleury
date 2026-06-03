/// Render-layout activity observed while laying out one frame.
final class RenderLayoutFrameStats {
  const RenderLayoutFrameStats({
    required this.performedCount,
    required this.skippedCount,
  });

  static const empty = RenderLayoutFrameStats(
    performedCount: 0,
    skippedCount: 0,
  );

  /// Render objects that ran `performLayout`.
  final int performedCount;

  /// Render objects that returned a cached same-constraint layout result.
  final int skippedCount;

  int get totalCount => performedCount + skippedCount;
  bool get hasLayouts => totalCount > 0;

  double get skippedRatio => totalCount == 0 ? 0 : skippedCount / totalCount;
}

/// Debug-only collector for render-layout cache activity.
///
/// The collector is opt-in per frame. Normal app frames pay only a branch in
/// `RenderObject.layout`; debug surfaces and scenario benchmarks enable it
/// around the frame they want to inspect.
final class RenderLayoutDebugStats {
  RenderLayoutDebugStats._();

  static bool _enabled = false;
  static int _performedCount = 0;
  static int _skippedCount = 0;

  static void beginFrame({required bool enabled}) {
    _enabled = enabled;
    _resetCounters();
  }

  static RenderLayoutFrameStats takeFrameStats() {
    if (!_enabled) return RenderLayoutFrameStats.empty;
    final stats = RenderLayoutFrameStats(
      performedCount: _performedCount,
      skippedCount: _skippedCount,
    );
    _enabled = false;
    _resetCounters();
    return stats;
  }

  static void recordPerformed() {
    if (!_enabled) return;
    _performedCount += 1;
  }

  static void recordSkipped() {
    if (!_enabled) return;
    _skippedCount += 1;
  }

  static void _resetCounters() {
    _performedCount = 0;
    _skippedCount = 0;
  }
}
