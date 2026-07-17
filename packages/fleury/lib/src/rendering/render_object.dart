import 'package:meta/meta.dart';

import '../debug/debug_invalidation.dart';
import '../foundation/fleury_error.dart';
import '../foundation/geometry.dart';
import 'cell_buffer.dart';
import 'layout.dart';
import 'render_layout_stats.dart';

/// Frame-level signal for whether the terminal presenter can trust
/// paint-buffer damage bounds.
///
/// Paint-only mutations can be bounded by the cells repainted into the frame
/// buffer. Layout-affecting mutations cannot: cells may disappear or move
/// without being rewritten, so the presenter must fall back to full-buffer
/// diffing for that frame.
///
/// One instance is owned per [BuildOwner]/runtime: render objects publish
/// into the tracker attached at their tree's root, so two Fleury runtimes in
/// one isolate never observe each other's damage. The signal accumulates
/// across frames until [takeRequiresFullDiff] consumes it, so deferred
/// consumers can coalesce several invalidations into one read.
final class RenderDamageTracker {
  bool _requiresFullDiff = false;
  bool _visualChange = false;

  void recordLayoutOrConservativePaint() {
    _requiresFullDiff = true;
    _visualChange = true;
  }

  /// Records that some render object's visual output may differ next frame
  /// (audited paint-only invalidations included). Cleared when a frame
  /// consumes it via [takeVisualChange].
  void recordVisualChange() {
    _visualChange = true;
  }

  /// Whether any invalidation has been recorded since the last rendered
  /// frame. While false (and the buffer pool is warm), a frame request can
  /// skip build/layout/paint entirely: the front buffer is still exact.
  bool get hasVisualChange => _visualChange;

  bool takeVisualChange() {
    final result = _visualChange;
    _visualChange = false;
    return result;
  }

  bool takeRequiresFullDiff() {
    final result = _requiresFullDiff;
    _requiresFullDiff = false;
    return result;
  }

  void reset() {
    _requiresFullDiff = false;
    _visualChange = false;
  }
}

typedef SemanticPaintBoundsCallback = void Function(CellRect? bounds);

CellRect _translatePaintRect(CellRect rect, CellOffset offset) {
  return CellRect(offset: offset + rect.offset, size: rect.size);
}

CellOffset _inversePaintOffset(CellOffset offset) {
  return CellOffset(-offset.col, -offset.row);
}

/// A clip constraint carried by retained paint geometry.
///
/// `clipRect == null` in the public paint API means unbounded, while the
/// intersection of two real clips can be empty. Keeping those states distinct
/// prevents a fully clipped cached record from being mistaken for an
/// unbounded one during nested-boundary replay.
final class _PaintGeometryClip {
  const _PaintGeometryClip.unbounded() : isBounded = false, bounds = null;
  const _PaintGeometryClip.bounded(this.bounds) : isBounded = true;

  factory _PaintGeometryClip.fromPaintRect(CellRect? clipRect) {
    return clipRect == null
        ? const _PaintGeometryClip.unbounded()
        : _PaintGeometryClip.bounded(clipRect);
  }

  final bool isBounded;

  /// The bounded clip, or null when a bounded intersection is empty.
  final CellRect? bounds;

  bool sameAs(_PaintGeometryClip other) {
    return isBounded == other.isBounded && bounds == other.bounds;
  }

  _PaintGeometryClip translate(CellOffset offset) {
    if (!isBounded || bounds == null) return this;
    return _PaintGeometryClip.bounded(_translatePaintRect(bounds!, offset));
  }

  _PaintGeometryClip intersect(_PaintGeometryClip other) {
    if (!isBounded) return other;
    if (!other.isBounded) return this;
    final first = bounds;
    final second = other.bounds;
    if (first == null || second == null) {
      return const _PaintGeometryClip.bounded(null);
    }
    return _PaintGeometryClip.bounded(first.intersect(second));
  }

  CellRect? applyTo(CellRect rect) {
    if (!isBounded) return rect;
    return bounds?.intersect(rect);
  }
}

final class _PaintGeometryClipScope {
  _PaintGeometryClipScope._();

  static final List<_PaintGeometryClip> _stack = <_PaintGeometryClip>[];

  static int get _depth => _stack.length;

  /// Whether an enclosing repaint boundary is currently retaining paint
  /// geometry. Clip parents use this to keep painting locally hidden content
  /// into that boundary's cache so it can become visible on a later cache hit
  /// when only an ancestor clip changes.
  static bool get isCapturing =>
      SemanticPaintBoundsCapture.isActive ||
      PointerRegionCapture.isActive ||
      FocusGeometryCapture.isActive ||
      RetainedPaintGeometryCapture.isActive;

  static _PaintGeometryClip _clipSince(int depth) {
    var result = const _PaintGeometryClip.unbounded();
    for (var index = depth; index < _stack.length; index += 1) {
      result = result.intersect(_stack[index]);
    }
    return result;
  }

  static void paintWithClip(CellRect screenClip, void Function() paint) {
    // Outside a retained-geometry capture the scope carries no observable
    // state. This keeps the common uncached paint path allocation-free while
    // still preserving scopes whenever an enclosing boundary is collecting.
    if (!isCapturing) {
      paint();
      return;
    }
    _stack.add(_PaintGeometryClip.bounded(screenClip));
    try {
      paint();
    } finally {
      _stack.removeLast();
    }
  }
}

_PaintGeometryClip _capturedLocalClip({
  required int scopeDepth,
  required _PaintGeometryClip rootClip,
  required _PaintGeometryClip effectiveClip,
  _PaintGeometryClip explicitLocalClip = const _PaintGeometryClip.unbounded(),
}) {
  final scopedClip = _PaintGeometryClipScope._clipSince(scopeDepth);
  final localClip = scopedClip.intersect(explicitLocalClip);
  if (localClip.isBounded) return localClip;

  // Compatibility fallback for a custom clip-introducing render object that
  // has not adopted RenderObject.paintWithGeometryClip yet. It is conservative
  // rather than provenance-perfect, but preserves the pre-scope behavior instead of
  // silently dropping an observable tighter clip.
  return effectiveClip.sameAs(rootClip) ? localClip : effectiveClip;
}

/// Refreshes arbitrary paint-owned screen geometry on repaint-boundary cache
/// hits.
///
/// [bounds] is the full paint rectangle, while [clipRect] is the effective
/// screen clip. A null [bounds] retires geometry that is no longer painted. A
/// null [clipRect] means unbounded; a bounded-empty clip is represented by a
/// zero-sized rectangle so consumers can distinguish it from unbounded paint.
typedef RetainedPaintGeometryCallback =
    void Function(CellRect? bounds, CellRect? clipRect);

CellRect? _paintGeometryCallbackClip(
  _PaintGeometryClip clip,
  CellOffset emptyOrigin,
) {
  if (!clip.isBounded) return null;
  return clip.bounds ?? CellRect(offset: emptyOrigin, size: CellSize.zero);
}

/// A generic paint-owned geometry callback plus its cache-local bounds and
/// clip provenance.
///
/// Focus, pointer, and semantic geometry have specialized replay semantics.
/// This record covers the remaining screen-space state populated during paint:
/// selection bounds, anchor links, and contained-error presentation regions.
final class RetainedPaintGeometryRecord {
  const RetainedPaintGeometryRecord._({
    required this.update,
    required this.localBounds,
    required _PaintGeometryClip localClip,
  }) : _localClip = localClip;

  final RetainedPaintGeometryCallback update;

  /// Bounds relative to the owning boundary's captured screen origin.
  final CellRect localBounds;
  final _PaintGeometryClip _localClip;

  void publishToActiveCapture({
    required CellOffset screenOffset,
    required CellRect? clipRect,
  }) {
    if (!RetainedPaintGeometryCapture.isActive) return;
    final effectiveClip = _resolvedClip(screenOffset, clipRect);
    RetainedPaintGeometryCapture._recordResolved(
      update,
      _translatePaintRect(localBounds, screenOffset),
      effectiveClip,
      explicitLocalClip: _localClip.translate(screenOffset),
    );
  }

  void replay({required CellOffset screenOffset, required CellRect? clipRect}) {
    final screenBounds = _translatePaintRect(localBounds, screenOffset);
    final resolvedClip = _resolvedClip(screenOffset, clipRect);
    RetainedPaintGeometryCapture._recordResolved(
      update,
      screenBounds,
      resolvedClip,
      explicitLocalClip: _localClip.translate(screenOffset),
    );
    update(
      screenBounds,
      _paintGeometryCallbackClip(resolvedClip, screenBounds.offset),
    );
  }

  void clear() => update(null, null);

  _PaintGeometryClip _resolvedClip(
    CellOffset screenOffset,
    CellRect? inheritedClip,
  ) {
    return _localClip
        .translate(screenOffset)
        .intersect(_PaintGeometryClip.fromPaintRect(inheritedClip));
  }
}

final class _RetainedPaintGeometryCollector {
  _RetainedPaintGeometryCollector({
    required this.records,
    required CellOffset screenOrigin,
    required this.rootClip,
    required this.scopeDepth,
  }) : _inverseScreenOrigin = _inversePaintOffset(screenOrigin);

  final List<RetainedPaintGeometryRecord> records;
  final _PaintGeometryClip rootClip;
  final int scopeDepth;
  final CellOffset _inverseScreenOrigin;

  void record(
    RetainedPaintGeometryCallback update,
    CellRect screenBounds,
    _PaintGeometryClip effectiveClip, {
    _PaintGeometryClip explicitLocalClip = const _PaintGeometryClip.unbounded(),
  }) {
    final localClip = _capturedLocalClip(
      scopeDepth: scopeDepth,
      rootClip: rootClip,
      effectiveClip: effectiveClip,
      explicitLocalClip: explicitLocalClip,
    );
    records.add(
      RetainedPaintGeometryRecord._(
        update: update,
        localBounds: _translatePaintRect(screenBounds, _inverseScreenOrigin),
        localClip: localClip.translate(_inverseScreenOrigin),
      ),
    );
  }
}

/// Stack-scoped collector for general paint-owned screen geometry.
final class RetainedPaintGeometryCapture {
  RetainedPaintGeometryCapture._();

  static final List<_RetainedPaintGeometryCollector> _stack =
      <_RetainedPaintGeometryCollector>[];

  static bool get isActive => _stack.isNotEmpty;

  static void collect(
    List<RetainedPaintGeometryRecord> records, {
    required CellOffset screenOrigin,
    required CellRect? clipRect,
    required void Function() paint,
  }) {
    _stack.add(
      _RetainedPaintGeometryCollector(
        records: records,
        screenOrigin: screenOrigin,
        rootClip: _PaintGeometryClip.fromPaintRect(clipRect),
        scopeDepth: _PaintGeometryClipScope._depth,
      ),
    );
    try {
      paint();
    } finally {
      _stack.removeLast();
    }
  }

  static void record(
    RetainedPaintGeometryCallback update,
    CellRect screenBounds, {
    required CellRect? clipRect,
  }) {
    if (_stack.isEmpty) return;
    _recordResolved(
      update,
      screenBounds,
      _PaintGeometryClip.fromPaintRect(clipRect),
    );
  }

  static void _recordResolved(
    RetainedPaintGeometryCallback update,
    CellRect screenBounds,
    _PaintGeometryClip effectiveClip, {
    _PaintGeometryClip explicitLocalClip = const _PaintGeometryClip.unbounded(),
  }) {
    if (_stack.isEmpty) return;
    _stack.last.record(
      update,
      screenBounds,
      effectiveClip,
      explicitLocalClip: explicitLocalClip,
    );
  }
}

/// A paint-captured semantic bounds callback plus its cache-local bounds.
///
/// Repaint boundaries paint children into scratch buffers, then copy cached
/// cells on later frames. Semantic bounds still need to be refreshed in
/// screen coordinates on those cached frames. Records captured while painting
/// into a boundary cache let the boundary replay the callback without
/// re-walking the visual paint path.
final class SemanticPaintBoundsRecord {
  const SemanticPaintBoundsRecord._({
    required this.onPaintBounds,
    required this.localBounds,
    required _PaintGeometryClip localClip,
  }) : _localClip = localClip;

  final SemanticPaintBoundsCallback onPaintBounds;

  /// Bounds relative to the owning boundary's captured screen origin.
  final CellRect localBounds;
  final _PaintGeometryClip _localClip;

  void publishToActiveCapture({
    required CellOffset screenOffset,
    required CellRect? clipRect,
  }) {
    if (!SemanticPaintBoundsCapture.isActive) return;
    final effectiveClip = _resolvedClip(screenOffset, clipRect);
    SemanticPaintBoundsCapture._recordResolved(
      onPaintBounds,
      _translatePaintRect(localBounds, screenOffset),
      effectiveClip,
      explicitLocalClip: _localClip.translate(screenOffset),
    );
  }

  void replay({required CellOffset screenOffset, required CellRect? clipRect}) {
    final screenBounds = _translatePaintRect(localBounds, screenOffset);
    final resolvedClip = _resolvedClip(screenOffset, clipRect);
    SemanticPaintBoundsCapture._recordResolved(
      onPaintBounds,
      screenBounds,
      resolvedClip,
      explicitLocalClip: _localClip.translate(screenOffset),
    );
    onPaintBounds(resolvedClip.applyTo(screenBounds));
  }

  _PaintGeometryClip _resolvedClip(
    CellOffset screenOffset,
    CellRect? inheritedClip,
  ) {
    return _localClip
        .translate(screenOffset)
        .intersect(_PaintGeometryClip.fromPaintRect(inheritedClip));
  }
}

final class _SemanticPaintBoundsCollector {
  _SemanticPaintBoundsCollector({
    required this.records,
    required CellOffset screenOrigin,
    required this.rootClip,
    required this.scopeDepth,
  }) : _inverseScreenOrigin = _inversePaintOffset(screenOrigin);

  final List<SemanticPaintBoundsRecord> records;
  final _PaintGeometryClip rootClip;
  final int scopeDepth;
  final CellOffset _inverseScreenOrigin;

  void record(
    SemanticPaintBoundsCallback onPaintBounds,
    CellRect screenBounds,
    _PaintGeometryClip effectiveClip, {
    _PaintGeometryClip explicitLocalClip = const _PaintGeometryClip.unbounded(),
  }) {
    final localClip = _capturedLocalClip(
      scopeDepth: scopeDepth,
      rootClip: rootClip,
      effectiveClip: effectiveClip,
      explicitLocalClip: explicitLocalClip,
    );
    records.add(
      SemanticPaintBoundsRecord._(
        onPaintBounds: onPaintBounds,
        localBounds: _translatePaintRect(screenBounds, _inverseScreenOrigin),
        localClip: localClip.translate(_inverseScreenOrigin),
      ),
    );
  }
}

/// Stack-scoped collector for semantic bounds produced during paint.
final class SemanticPaintBoundsCapture {
  SemanticPaintBoundsCapture._();

  static final List<_SemanticPaintBoundsCollector> _stack =
      <_SemanticPaintBoundsCollector>[];

  static bool get isActive => _stack.isNotEmpty;

  static void collect(
    List<SemanticPaintBoundsRecord> records, {
    required CellOffset screenOrigin,
    required CellRect? clipRect,
    required void Function() paint,
  }) {
    _stack.add(
      _SemanticPaintBoundsCollector(
        records: records,
        screenOrigin: screenOrigin,
        rootClip: _PaintGeometryClip.fromPaintRect(clipRect),
        scopeDepth: _PaintGeometryClipScope._depth,
      ),
    );
    try {
      paint();
    } finally {
      _stack.removeLast();
    }
  }

  static void record(
    SemanticPaintBoundsCallback onPaintBounds,
    CellRect screenBounds, {
    required CellRect? clipRect,
  }) {
    if (_stack.isEmpty) return;
    _recordResolved(
      onPaintBounds,
      screenBounds,
      _PaintGeometryClip.fromPaintRect(clipRect),
    );
  }

  static void _recordResolved(
    SemanticPaintBoundsCallback onPaintBounds,
    CellRect screenBounds,
    _PaintGeometryClip effectiveClip, {
    _PaintGeometryClip explicitLocalClip = const _PaintGeometryClip.unbounded(),
  }) {
    if (_stack.isEmpty) return;
    _stack.last.record(
      onPaintBounds,
      screenBounds,
      effectiveClip,
      explicitLocalClip: explicitLocalClip,
    );
  }
}

/// Re-registers a pointer region at [screenRect] — the replay counterpart of
/// [RenderPointerListener]'s in-paint registration.
typedef PointerRegionRegister = void Function(CellRect? screenRect);

/// A pointer region registered during a paint that a [RenderRepaintBoundary]
/// cached. Pointer hit-testing in Fleury is fed by *paint-order registration*
/// (regions re-register every frame as they paint), so a cached boundary that
/// skips the subtree walk would drop every region inside it — the item, or a
/// button within it, silently stops responding on cache-hit frames. This is
/// the exact problem [SemanticPaintBoundsRecord] solves for semantics; pointer
/// regions get the same capture-and-replay treatment so the boundary stays
/// transparent to input.
final class PointerRegionRecord {
  const PointerRegionRecord._({
    required this.register,
    required this.localBounds,
    required _PaintGeometryClip localClip,
  }) : _localClip = localClip;

  final PointerRegionRegister register;

  /// Bounds relative to the owning boundary's captured screen origin.
  final CellRect localBounds;
  final _PaintGeometryClip _localClip;

  void publishToActiveCapture({
    required CellOffset screenOffset,
    required CellRect? clipRect,
  }) {
    if (!PointerRegionCapture.isActive) return;
    final effectiveClip = _resolvedClip(screenOffset, clipRect);
    PointerRegionCapture._recordResolved(
      register,
      _translatePaintRect(localBounds, screenOffset),
      effectiveClip,
      explicitLocalClip: _localClip.translate(screenOffset),
    );
  }

  void replay({required CellOffset screenOffset, required CellRect? clipRect}) {
    // Re-record into an enclosing boundary's capture (nested boundaries), then
    // re-register only the currently visible portion at the current screen
    // position.
    final screenBounds = _translatePaintRect(localBounds, screenOffset);
    final resolvedClip = _resolvedClip(screenOffset, clipRect);
    PointerRegionCapture._recordResolved(
      register,
      screenBounds,
      resolvedClip,
      explicitLocalClip: _localClip.translate(screenOffset),
    );
    register(resolvedClip.applyTo(screenBounds));
  }

  _PaintGeometryClip _resolvedClip(
    CellOffset screenOffset,
    CellRect? inheritedClip,
  ) {
    return _localClip
        .translate(screenOffset)
        .intersect(_PaintGeometryClip.fromPaintRect(inheritedClip));
  }
}

final class _PointerRegionCollector {
  _PointerRegionCollector({
    required this.records,
    required CellOffset screenOrigin,
    required this.rootClip,
    required this.scopeDepth,
  }) : _inverseScreenOrigin = _inversePaintOffset(screenOrigin);

  final List<PointerRegionRecord> records;
  final _PaintGeometryClip rootClip;
  final int scopeDepth;
  final CellOffset _inverseScreenOrigin;

  void record(
    PointerRegionRegister register,
    CellRect screenBounds,
    _PaintGeometryClip effectiveClip, {
    _PaintGeometryClip explicitLocalClip = const _PaintGeometryClip.unbounded(),
  }) {
    final localClip = _capturedLocalClip(
      scopeDepth: scopeDepth,
      rootClip: rootClip,
      effectiveClip: effectiveClip,
      explicitLocalClip: explicitLocalClip,
    );
    records.add(
      PointerRegionRecord._(
        register: register,
        localBounds: _translatePaintRect(screenBounds, _inverseScreenOrigin),
        localClip: localClip.translate(_inverseScreenOrigin),
      ),
    );
  }
}

/// Stack-scoped collector for pointer regions registered during paint — the
/// pointer counterpart of [SemanticPaintBoundsCapture].
final class PointerRegionCapture {
  PointerRegionCapture._();

  static final List<_PointerRegionCollector> _stack =
      <_PointerRegionCollector>[];

  /// Whether a boundary is currently capturing. Regions check this before
  /// building their record so an unenclosed region — the common case — does
  /// no per-paint allocation at all.
  static bool get isActive => _stack.isNotEmpty;

  static void collect(
    List<PointerRegionRecord> records, {
    required CellOffset screenOrigin,
    required CellRect? clipRect,
    required void Function() paint,
  }) {
    _stack.add(
      _PointerRegionCollector(
        records: records,
        screenOrigin: screenOrigin,
        rootClip: _PaintGeometryClip.fromPaintRect(clipRect),
        scopeDepth: _PaintGeometryClipScope._depth,
      ),
    );
    try {
      paint();
    } finally {
      _stack.removeLast();
    }
  }

  static void record(
    PointerRegionRegister register,
    CellRect screenBounds, {
    required CellRect? clipRect,
  }) {
    if (_stack.isEmpty) return;
    _recordResolved(
      register,
      screenBounds,
      _PaintGeometryClip.fromPaintRect(clipRect),
    );
  }

  static void _recordResolved(
    PointerRegionRegister register,
    CellRect screenBounds,
    _PaintGeometryClip effectiveClip, {
    _PaintGeometryClip explicitLocalClip = const _PaintGeometryClip.unbounded(),
  }) {
    if (_stack.isEmpty) return;
    _stack.last.record(
      register,
      screenBounds,
      effectiveClip,
      explicitLocalClip: explicitLocalClip,
    );
  }
}

/// Updates focus-owned paint geometry in current screen coordinates.
///
/// Focus bounds and editable carets are populated during paint, just like
/// semantics and pointer regions. A repaint-boundary cache hit skips that paint
/// walk, so the boundary captures their cache-local rectangles and replays the
/// callbacks at its current screen position.
typedef FocusGeometryCallback = void Function(CellRect? bounds);

final class FocusGeometryRecord {
  const FocusGeometryRecord._({
    required this.update,
    required this.localBounds,
    required this.clipToBounds,
    required _PaintGeometryClip localClip,
  }) : _localClip = localClip;

  final FocusGeometryCallback update;

  /// Bounds relative to the owning boundary's captured screen origin.
  final CellRect localBounds;
  final bool clipToBounds;
  final _PaintGeometryClip _localClip;

  void publishToActiveCapture({
    required CellOffset screenOffset,
    required CellRect? clipRect,
  }) {
    if (!FocusGeometryCapture.isActive) return;
    final effectiveClip = _resolvedClip(screenOffset, clipRect);
    FocusGeometryCapture._recordResolved(
      update,
      _translatePaintRect(localBounds, screenOffset),
      effectiveClip,
      clipToBounds: clipToBounds,
      explicitLocalClip: _localClip.translate(screenOffset),
    );
  }

  void replay({required CellOffset screenOffset, required CellRect? clipRect}) {
    // Preserve the record for an enclosing cached boundary, then update the
    // live FocusNode in screen space for this frame.
    final screenBounds = _translatePaintRect(localBounds, screenOffset);
    final resolvedClip = _resolvedClip(screenOffset, clipRect);
    FocusGeometryCapture._recordResolved(
      update,
      screenBounds,
      resolvedClip,
      clipToBounds: clipToBounds,
      explicitLocalClip: _localClip.translate(screenOffset),
    );
    final visible = resolvedClip.applyTo(screenBounds);
    update(clipToBounds ? visible : (visible == null ? null : screenBounds));
  }

  void clear() => update(null);

  _PaintGeometryClip _resolvedClip(
    CellOffset screenOffset,
    CellRect? inheritedClip,
  ) {
    return _localClip
        .translate(screenOffset)
        .intersect(_PaintGeometryClip.fromPaintRect(inheritedClip));
  }
}

final class _FocusGeometryCollector {
  _FocusGeometryCollector({
    required this.records,
    required CellOffset screenOrigin,
    required this.rootClip,
    required this.scopeDepth,
  }) : _inverseScreenOrigin = _inversePaintOffset(screenOrigin);

  final List<FocusGeometryRecord> records;
  final _PaintGeometryClip rootClip;
  final int scopeDepth;
  final CellOffset _inverseScreenOrigin;

  void record(
    FocusGeometryCallback update,
    CellRect screenBounds,
    _PaintGeometryClip effectiveClip, {
    required bool clipToBounds,
    _PaintGeometryClip explicitLocalClip = const _PaintGeometryClip.unbounded(),
  }) {
    final localClip = _capturedLocalClip(
      scopeDepth: scopeDepth,
      rootClip: rootClip,
      effectiveClip: effectiveClip,
      explicitLocalClip: explicitLocalClip,
    );
    records.add(
      FocusGeometryRecord._(
        update: update,
        localBounds: _translatePaintRect(screenBounds, _inverseScreenOrigin),
        clipToBounds: clipToBounds,
        localClip: localClip.translate(_inverseScreenOrigin),
      ),
    );
  }
}

/// Stack-scoped collector for focus/caret geometry produced during paint.
final class FocusGeometryCapture {
  FocusGeometryCapture._();

  static final List<_FocusGeometryCollector> _stack =
      <_FocusGeometryCollector>[];

  static bool get isActive => _stack.isNotEmpty;

  static void collect(
    List<FocusGeometryRecord> records, {
    required CellOffset screenOrigin,
    required CellRect? clipRect,
    required void Function() paint,
  }) {
    _stack.add(
      _FocusGeometryCollector(
        records: records,
        screenOrigin: screenOrigin,
        rootClip: _PaintGeometryClip.fromPaintRect(clipRect),
        scopeDepth: _PaintGeometryClipScope._depth,
      ),
    );
    try {
      paint();
    } finally {
      _stack.removeLast();
    }
  }

  static void record(
    FocusGeometryCallback update,
    CellRect screenBounds, {
    required CellRect? clipRect,
    bool clipToBounds = true,
  }) {
    if (_stack.isEmpty) return;
    _recordResolved(
      update,
      screenBounds,
      _PaintGeometryClip.fromPaintRect(clipRect),
      clipToBounds: clipToBounds,
    );
  }

  static void _recordResolved(
    FocusGeometryCallback update,
    CellRect screenBounds,
    _PaintGeometryClip effectiveClip, {
    bool clipToBounds = true,
    _PaintGeometryClip explicitLocalClip = const _PaintGeometryClip.unbounded(),
  }) {
    if (_stack.isEmpty) return;
    _stack.last.record(
      update,
      screenBounds,
      effectiveClip,
      clipToBounds: clipToBounds,
      explicitLocalClip: explicitLocalClip,
    );
  }
}

/// Parent-attached layout metadata.
///
/// Multi-child render objects (Flex, Stack) keep per-child layout state
/// (offset, flex factor, alignment) here so children don't need to know
/// about their parent's layout discipline. Mirrors Flutter's
/// `ParentData` abstraction at a much smaller scope.
abstract class ParentData {
  /// Subclasses can override this to release any resources tied to the
  /// child's previous parent. Today this is a no-op; the hook exists so
  /// future multi-child layouts can implement it.
  @mustCallSuper
  void detach() {}
}

/// Base for everything that participates in layout and paint.
///
/// The contract is the Flutter constraints-down / sizes-up protocol,
/// translated to integer cell coordinates:
///
///   1. Parent calls `layout(constraints)`.
///   2. Subclass `performLayout(constraints)` returns the chosen [CellSize]
///      and lays out any children (calling `layout` on them in turn).
///   3. Paint placement is the parent's responsibility — there is no
///      `setOffset` on the child. Each parent remembers where it decided
///      to put each child (e.g. `RenderFlex` keeps a child→offset map,
///      `RenderAlign` a single child offset) and applies that during its
///      own `paint` by calling `child.paint(buffer, offset + childOffset)`.
///      So offsets live in the parent, not as state on the child. (A
///      [ParentData] slot exists for parents that prefer to stash
///      layout bookkeeping on the child, but most parents use their own
///      fields.)
///   4. Parent calls `paint(buffer, offset)` during the paint pass. The
///      `offset` passed in is the absolute position in the buffer.
///
/// Subclasses must call `super.layout` (or invoke the protocol on each
/// child themselves); the framework relies on `_size` being current after
/// every layout pass.
abstract class RenderObject {
  RenderObject? _parent;
  ParentData? parentData;

  CellConstraints? _constraints;
  CellSize? _size;
  bool _needsLayout = true;

  // Cache-invalidation flag, meaningful only at [isRepaintBoundary] render
  // objects. Non-boundary nodes always re-paint, so the flag is just the
  // walk-up target; the boundary clears it after painting its cache.
  bool _needsPaint = true;

  /// Whether the enclosing boundary's cache has been invalidated. Set true
  /// by [markNeedsPaint]; subclasses that implement a paint cache clear it
  /// once they have re-painted into their cache.
  @protected
  bool get needsPaint => _needsPaint;

  @protected
  set needsPaint(bool value) => _needsPaint = value;

  /// Whether this render object must run [performLayout] the next time it is
  /// reached with the same constraints. Constraints changes always force a new
  /// layout even when this flag is false.
  @protected
  bool get needsLayout => _needsLayout;

  /// Whether this render object owns its own paint cache (a `CellBuffer`
  /// it can blit instead of re-walking its subtree's paint). Override to
  /// true in subclasses that implement the cache discipline.
  bool get isRepaintBoundary => false;

  /// The frame damage tracker for this render tree, held at the root.
  ///
  /// Set by the frame driver (via [attachFrameDamageTracker]) on the root
  /// render object only. Invalidation walks ([_markNeedsLayoutUp]) terminate
  /// at the root and publish there, so per-object storage stays nil and two
  /// runtimes in one isolate never share damage state.
  RenderDamageTracker? _frameDamage;

  /// Attaches the per-runtime damage tracker at this (root) render object.
  ///
  /// Returns true when the tracker was not already attached — a fresh root —
  /// so callers can record conservative damage for invalidations that may
  /// have happened while the subtree was being built detached.
  bool attachFrameDamageTracker(RenderDamageTracker tracker) {
    final isNew = !identical(_frameDamage, tracker);
    _frameDamage = tracker;
    return isNew;
  }

  /// The damage tracker attached at this tree's root, if any.
  RenderDamageTracker? get _rootFrameDamage {
    RenderObject node = this;
    while (true) {
      final parent = node._parent;
      if (parent == null) return node._frameDamage;
      node = parent;
    }
  }

  /// Marks this render object and its ancestors as needing layout, and marks
  /// the nearest enclosing repaint boundary as dirty. Use this for changes
  /// that can affect size, child constraints, child offsets, or layout-derived
  /// paint state.
  void markNeedsLayout() {
    DebugInvalidations.recordLayout(runtimeType.toString());
    _markNeedsLayoutUp();
    _markEnclosingRepaintBoundariesDirty();
  }

  void _markNeedsLayoutUp() {
    _needsLayout = true;
    final parent = _parent;
    if (parent == null) {
      // Terminal node of the invalidation walk: publish frame damage at the
      // root so the presenter falls back to a full diff this frame.
      _frameDamage?.recordLayoutOrConservativePaint();
      return;
    }
    parent._markNeedsLayoutUp();
  }

  /// Marks this render object as visually stale and conservatively marks
  /// layout dirty.
  ///
  /// This remains the compatibility-safe default for unaudited setters. Use
  /// [markNeedsLayout] when the value can change size, child constraints,
  /// offsets, or layout-derived paint state. Use [markNeedsPaintOnly] only
  /// after verifying that the value cannot affect layout.
  void markNeedsPaint() {
    DebugInvalidations.recordPaint(runtimeType.toString());
    _markNeedsLayoutUp();
    _markEnclosingRepaintBoundariesDirty();
  }

  /// Marks only the nearest enclosing repaint boundary as visually stale.
  ///
  /// Subclasses should use this for audited visual-only mutations such as
  /// color, text style, cursor blink, or paint-time visibility toggles. It
  /// intentionally does not mark this render object or its ancestors as layout
  /// dirty, so the next same-constraint layout call can reuse cached sizes.
  @protected
  void markNeedsPaintOnly() {
    DebugInvalidations.recordPaint(runtimeType.toString());
    _rootFrameDamage?.recordVisualChange();
    _markEnclosingRepaintBoundariesDirty();
  }

  // Marks EVERY enclosing repaint boundary dirty, not just the nearest — an
  // outer boundary's cached blit embeds the inner boundary's painted cells, so
  // a change under the inner boundary makes the outer's cache stale too. Marking
  // only the nearest leaves the outer to cache-hit and blit stale cells (and,
  // with pointer/semantic replay, re-register regions from a subtree that has
  // since changed). An already-dirty boundary short-circuits: it was marked by
  // an earlier walk this frame that already continued to the root, so its
  // ancestors are dirty too. (Named for the audited paint-only path; also used
  // by the conservative markNeedsPaint. Layout dirtiness is handled separately.)
  void _markEnclosingRepaintBoundariesDirty() {
    if (isRepaintBoundary) {
      if (_needsPaint) return;
      _needsPaint = true;
    }
    _parent?._markEnclosingRepaintBoundariesDirty();
  }

  /// Marks every repaint boundary STRICTLY ABOVE this node as needing paint.
  ///
  /// For a node that gains caching authority at runtime ([isRepaintBoundary]
  /// flipping true — `RenderRepaintBoundary.cachingEnabled`): setting its own
  /// [needsPaint] is not enough, because enclosing boundary caches embed this
  /// subtree's painted cells, and every later invalidation from inside the
  /// subtree short-circuits at this now-dirty boundary — the ancestors would
  /// never be told. Deliberately starts at the parent: the self-inclusive
  /// walk ([_markEnclosingRepaintBoundariesDirty]) would see this boundary
  /// already dirty and stop before reaching any ancestor.
  @protected
  void markAncestorRepaintBoundariesDirty() {
    _parent?._markEnclosingRepaintBoundariesDirty();
  }

  /// The constraints from the most recent layout pass.
  CellConstraints get constraints {
    final c = _constraints;
    if (c == null) {
      throw FleuryError(
        summary: '$runtimeType has no constraints — layout has not run yet.',
        details:
            'Constraints are recorded inside `layout()`, which the '
            'framework calls during the layout phase. Reading them before '
            'then means the render object was queried out-of-order.',
        hint:
            'If you are reading constraints inside `performLayout`, use '
            'the `constraints` argument directly. If you are reading them '
            'from `paint`, the render object has already laid out so this '
            'should not happen — it indicates the parent skipped the '
            'layout call.',
      );
    }
    return c;
  }

  /// The size computed by the most recent layout pass.
  CellSize get size {
    final s = _size;
    if (s == null) {
      throw FleuryError(
        summary: '$runtimeType has no size — layout has not run yet.',
        details:
            'Sizes are recorded inside `layout()`, which the framework '
            'calls during the layout phase. Reading the size before then '
            'means the render object was queried out-of-order.',
        hint:
            'If you are reading `size` from a paint or hit-test method, '
            'the framework has skipped the layout pass for this node — '
            'check that the parent forwarded `child.layout(constraints)`.',
      );
    }
    return s;
  }

  RenderObject? get parent => _parent;

  /// Attaches [child] to this render object as its parent. Subclasses
  /// that hold children call this whenever they accept one; it also
  /// gives the parent a chance to ensure [RenderObject.parentData] is the right
  /// type via [setupParentData].
  @protected
  void adoptChild(RenderObject child) {
    assert(child._parent == null, 'Render object adopted twice.');
    child._parent = this;
    setupParentData(child);
    markNeedsLayout();
  }

  /// Detaches [child] from this render object.
  @protected
  void dropChild(RenderObject child) {
    assert(child._parent == this, 'dropChild called on the wrong parent.');
    child.parentData?.detach();
    child.parentData = null;
    child._parent = null;
    markNeedsLayout();
  }

  /// Override to install a subclass of [ParentData] on the child. The
  /// default is a no-op; multi-child render objects override this so a
  /// child's `parentData` is always the type that parent expects.
  @protected
  void setupParentData(RenderObject child) {}

  /// Lays out this render object against [constraints] and returns the
  /// chosen size. Subclasses implement [performLayout] rather than
  /// overriding this; the framework needs the bookkeeping around it.
  CellSize layout(CellConstraints constraints) {
    final cachedSize = _size;
    if (!_needsLayout && cachedSize != null && _constraints == constraints) {
      RenderLayoutDebugStats.recordSkipped();
      return cachedSize;
    }
    final previousSize = _size;
    _constraints = constraints;
    final result = performLayout(constraints);
    if (!constraints.isSatisfiedBy(result)) {
      throw FleuryError(
        summary:
            '$runtimeType.performLayout returned $result, which does '
            'not satisfy $constraints.',
        details:
            'The widget tried to size itself outside the bounds its '
            'parent allowed. This usually means a child Widget asked for '
            'more space than its parent will give it (a SizedBox bigger '
            'than the available cells, a Container in unbounded constraints '
            'with no width/height), or a custom `performLayout` returned a '
            "size that doesn't respect its own constraints argument.",
        hint:
            'Wrap the child in a Flexible or Expanded, give it explicit '
            'width/height that fit inside the parent, or check that '
            "performLayout uses `constraints.constrain(...)` on its result.",
      );
    }
    _size = result;
    _needsLayout = false;
    RenderLayoutDebugStats.recordPerformed();
    if (previousSize != null && previousSize != result) {
      _rootFrameDamage?.recordLayoutOrConservativePaint();
      _markEnclosingRepaintBoundariesDirty();
    }
    return result;
  }

  /// Override to compute the chosen size and lay out children. Must
  /// return a size that satisfies [constraints].
  @protected
  CellSize performLayout(CellConstraints constraints);

  /// Paints this render object into [buffer] at the absolute [offset].
  ///
  /// Subclasses that hold children compute each child's absolute offset
  /// (their own [offset] plus the child's per-parent layout position)
  /// and recursively call [paint] on them.
  ///
  /// **Screen-space context.** [screenOffset] is the cumulative screen
  /// position that [offset] in this [buffer] corresponds to. For nearly
  /// every paint, [buffer] IS the screen and `screenOffset == offset`.
  /// Render objects that paint into a scratch buffer (notably
  /// [ScrollView]) pass the visible-on-screen position so descendants
  /// can capture screen-space bounds for hit-testing.
  ///
  /// **Clipping.** [clipRect] is the visible screen rectangle for this
  /// subtree. Anything painted (or hit-tested) outside it is clipped
  /// out. Null means "no clip" — the full screen is visible. Render
  /// objects that introduce clipping (scrollables, future overlays)
  /// intersect their own clip with the inherited [clipRect] and pass
  /// the intersection down.
  ///
  /// Defaults preserve the legacy contract: when omitted, screenOffset
  /// equals offset and there is no clip — so paints not involved with
  /// selection or hit-testing don't need to thread anything through.
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  });

  /// Whether an enclosing repaint boundary is currently retaining geometry.
  ///
  /// A clip parent that would normally skip a fully hidden child must still
  /// walk and paint it into the boundary-local cache while this is true. Pass
  /// a bounded-empty effective `clipRect` to the child so semantics, pointer,
  /// focus, and caret geometry remain hidden until a later replay reveals it.
  @protected
  bool get isRetainingPaintGeometry => _PaintGeometryClipScope.isCapturing;

  /// Paints descendants under a clip introduced by this render object.
  ///
  /// [screenClip] is this object's own screen-space clip before intersection
  /// with the inherited `clipRect`. The callback remains responsible for
  /// passing the effective intersection to descendants. Recording provenance
  /// separately lets repaint-boundary cache hits reapply changing ancestor
  /// clips without losing this stable descendant clip.
  @protected
  void paintWithGeometryClip(CellRect screenClip, void Function() paint) {
    _PaintGeometryClipScope.paintWithClip(screenClip, paint);
  }

  // ---- Intrinsic sizing -------------------------------------------------
  //
  // Subclasses override these to report the size they'd naturally take
  // given a cross-axis constraint. Used by widgets like [IntrinsicWidth]
  // and intrinsic-sized [Table] columns to size a child "tight to content"
  // instead of expanding it to the available space.
  //
  // Pass `null` for `height` / `width` to mean "no cross-axis constraint."
  // Defaults return 0 — a render object that doesn't care declares no
  // intrinsic preference.

  /// The widest this render object would want to be at the given [height].
  /// Most relevant override: text returns its unwrapped width.
  int computeMaxIntrinsicWidth(int? height) => 0;

  /// The narrowest width below which content would clip. Defaults to 0;
  /// text-like leaves can return a longest-token width if they word-wrap.
  int computeMinIntrinsicWidth(int? height) => 0;

  /// The tallest this render object would want to be at the given [width].
  int computeMaxIntrinsicHeight(int? width) => 0;

  /// The shortest this render object can be at the given [width].
  int computeMinIntrinsicHeight(int? width) => 0;
}

/// Marker interface for render objects that hold exactly one child. The
/// element layer uses this to attach/detach the child render object when
/// the widget tree changes.
abstract class RenderObjectWithSingleChild implements RenderObject {
  /// The single child render object, if any.
  RenderObject? get child;

  /// Replaces (or clears, with null) the single child render object.
  set child(RenderObject? value);
}

/// Marker interface for render objects that hold an ordered list of
/// children. The multi-child element layer manages the list explicitly
/// during reconciliation via [replaceAllChildren] rather than the
/// single-child attach/detach hooks.
abstract class RenderObjectWithChildren implements RenderObject {
  /// The current ordered list of children. Mutating the returned list
  /// is not supported; use [replaceAllChildren] instead.
  List<RenderObject> get children;

  /// Replaces the entire children list with [newChildren] in the given
  /// order. Implementations must adopt children that are new and drop
  /// children that are no longer present.
  void replaceAllChildren(List<RenderObject> newChildren);
}

/// Whether two render-child lists contain the same child identities in the
/// same order.
///
/// Multi-child render objects call this before reconciling children so ordinary
/// widget rebuilds that preserve child identity do not accidentally dirty
/// layout.
@protected
bool hasSameRenderChildrenInOrder(
  List<RenderObject> current,
  List<RenderObject> next,
) {
  if (current.length != next.length) return false;
  for (var i = 0; i < current.length; i++) {
    if (!identical(current[i], next[i])) return false;
  }
  return true;
}
