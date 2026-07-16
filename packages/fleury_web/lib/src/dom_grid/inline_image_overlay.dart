import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fleury/fleury_host.dart'
    show
        ImagePlacement,
        InlineImageCacheLedger,
        InlineImageCachePolicy,
        defaultInlineImageCachePolicy;
import 'package:web/web.dart' as web;

import '../metrics/cell_metrics.dart';

/// The browser inline-image layer: an absolutely-positioned, non-interactive
/// `<img>` overlay above the cell grid. Bytes arrive once per content-hash id
/// (cached as blob URLs); each frame's [ImagePlacement]s are reconciled into
/// positioned `<img>` elements. Pulled out of `RemoteSurfaceClient` so the DOM
/// reconcile — occurrence keying, eviction, the canvas-offset placement — is
/// unit-testable in a real browser, not just by manual inspection.
class InlineImageOverlay {
  InlineImageOverlay(
    this._host, {
    InlineImageCachePolicy cachePolicy = defaultInlineImageCachePolicy,
  }) : _imageCache = InlineImageCacheLedger(cachePolicy) {
    // The grid replaceChildren's its own root, so the overlay must be a sibling
    // of it under the host; absolutely positioned over the grid, with
    // pointer-events:none so clicks fall through to the cells.
    final overlay = web.document.createElement('div') as web.HTMLElement;
    overlay.style
      ..setProperty('position', 'absolute')
      ..setProperty('left', '0')
      ..setProperty('top', '0')
      ..setProperty('width', '100%')
      ..setProperty('height', '100%')
      // Clip an image that would extend past the grid to the host bounds.
      ..setProperty('overflow', 'hidden')
      ..setProperty('pointer-events', 'none');
    _host.appendChild(overlay);
    _overlay = overlay;
  }

  final web.HTMLElement _host;
  final InlineImageCacheLedger _imageCache;
  bool _ownsHostPosition = false;
  String _previousHostInlinePosition = '';
  String _previousHostInlinePositionPriority = '';
  web.HTMLElement? _overlay;

  // Blob URLs by content-hash id (so the same image at several spots shares one
  // decode); <img> elements and last-applied geometry by 'id#occurrence' so
  // repeated placements of one image each get a distinct element.
  final Map<String, String> _blobUrls = <String, String>{};
  final Map<String, Uint8List> _pendingImages = <String, Uint8List>{};
  int _pendingImageBytes = 0;
  final Map<String, web.HTMLImageElement> _els =
      <String, web.HTMLImageElement>{};
  final Map<String, String> _rects = <String, String>{};
  List<ImagePlacement> _last = const <ImagePlacement>[];

  /// Number of live `<img>` elements — for tests/diagnostics.
  int get imageElementCount => _els.length;

  /// Number of blob URLs held by the encoded-image cache.
  int get cachedImageCount => _imageCache.entryCount;

  /// Total encoded bytes represented by the blob-URL cache.
  int get cachedImageBytes => _imageCache.totalBytes;

  /// Images received since the last presentation plan. Kept separately so a
  /// sender that never completes its plan cannot grow the blob cache forever.
  int get pendingImageCount => _pendingImages.length;
  int get pendingImageBytes => _pendingImageBytes;

  /// Stages one inline image until the presentation plan that references it.
  ///
  /// Returns false without retaining [bytes] when the pending one-plan batch
  /// would exceed the cache policy. Normal Fleury senders enforce the same
  /// per-plan working-set bound, so false identifies a malformed or skewed
  /// stream. Staging keeps the committed cache and the in-flight generation
  /// independently bounded while preserving the wire's images-before-plan
  /// ordering.
  bool cacheImage(String id, Uint8List bytes) {
    if (_overlay == null) return false;
    if (_imageCache.contains(id) || _pendingImages.containsKey(id)) return true;
    if (bytes.length > _imageCache.policy.maxBytes ||
        _pendingImages.length >= _imageCache.policy.maxEntries ||
        _pendingImageBytes + bytes.length > _imageCache.policy.maxBytes) {
      return false;
    }
    _pendingImages[id] = bytes;
    _pendingImageBytes += bytes.length;
    return true;
  }

  /// Re-applies the most recent placement set against [box] — used on resize so
  /// images track the new cell pitch even without a fresh frame.
  void reapply(MeasuredCellBox box) => apply(_last, box);

  /// Commits the staged image batch for an actual presentation plan.
  ///
  /// Wire clients call this as soon as a plan is decoded, before the fallible
  /// grid apply. A later resize only calls [reapply], so it cannot consume
  /// bytes that belong to a not-yet-arrived plan.
  void commitPendingForPlan(List<ImagePlacement> placements) {
    _commitPending(<String>{for (final placement in placements) placement.id});
  }

  /// Commits and reconciles one locally-produced plan in a single call.
  /// Remote hosts split these phases with [commitPendingForPlan] and [apply].
  void presentPlan(List<ImagePlacement> placements, MeasuredCellBox box) {
    commitPendingForPlan(placements);
    apply(placements, box);
  }

  /// Reconciles the `<img>` overlay against this frame's [placements] (the full
  /// current set) measured against [box]. Pending bytes must already have been
  /// committed at the real plan boundary.
  void apply(List<ImagePlacement> placements, MeasuredCellBox box) {
    _last = placements;
    final overlay = _overlay;
    if (overlay == null) return;
    if (!_ownsHostPosition && box.hostPositionIsStatic) {
      // The computed value is authoritative. Inline tokens such as `inherit`,
      // `initial`, `unset`, or `var(...)` can all resolve to static too; leaving
      // one untouched would position the overlay against an ancestor instead of
      // this host. Preserve the exact token so dispose can restore ownership.
      _previousHostInlinePosition = _host.style
          .getPropertyValue('position')
          .trim();
      _previousHostInlinePositionPriority = _host.style.getPropertyPriority(
        'position',
      );
      _host.style.setProperty('position', 'relative');
      _ownsHostPosition = true;
    }
    final placedIds = <String>{for (final p in placements) p.id};
    final cw = box.cssCellWidth;
    final ch = box.cssCellHeight;
    // This overlay is absolute inside the positioned host, so its coordinates
    // are host-local. Viewport coordinates (used by the fixed IME capture
    // element) would count the host's page position twice here.
    final ox = box.cssCanvasInsetLeft;
    final oy = box.cssCanvasInsetTop;
    final seen = <String>{};
    final occurrence = <String, int>{};
    for (final p in placements) {
      final occ = occurrence[p.id] = (occurrence[p.id] ?? 0) + 1;
      final key = '${p.id}#$occ';
      seen.add(key);
      final url = _blobUrls[p.id];
      if (url == null) continue; // bytes not arrived yet; a later frame retries
      var el = _els[key];
      if (el == null) {
        el = web.document.createElement('img') as web.HTMLImageElement;
        el.style.setProperty('position', 'absolute');
        // Decorative: assistive tech reads the separate semantics DOM, so an
        // empty alt keeps the image from being announced twice.
        el.alt = '';
        // A corrupt payload would otherwise show the broken-image glyph; hide
        // it so a bad frame degrades to blank.
        el.onerror = (web.Event _) {
          _els[key]?.style.setProperty('visibility', 'hidden');
        }.toJS;
        el.src = url;
        overlay.appendChild(el);
        _els[key] = el;
      } else if (el.src != url) {
        // Bytes re-shipped under a new blob URL: point at the fresh URL and
        // clear any error-hidden state.
        el.src = url;
        el.style.removeProperty('visibility');
        _rects.remove(key);
      }
      // Re-style only when the geometry changed (static images hold their rect).
      final left = ox + p.col * cw;
      final top = oy + p.row * ch;
      final rect = '$left|$top|${p.cols * cw}|${p.rows * ch}|${p.fit.name}';
      if (_rects[key] != rect) {
        _rects[key] = rect;
        el.style
          ..setProperty('left', '${left}px')
          ..setProperty('top', '${top}px')
          ..setProperty('width', '${p.cols * cw}px')
          ..setProperty('height', '${p.rows * ch}px')
          // InlineImageFit names ARE the CSS object-fit keywords, so the source
          // fit maps straight through (without it, fill would stretch).
          ..setProperty('object-fit', p.fit.name);
      }
    }
    for (final key in _els.keys.toList()) {
      if (!seen.contains(key)) {
        _els.remove(key)?.remove();
        _rects.remove(key);
      }
    }
    _evictStale(placedIds);
  }

  /// Commits only pending images referenced by the next plan. Existing stale
  /// blobs are evicted *before* the new generation is materialized, using the
  /// same projected-fit policy as the app-side sender. This preserves their
  /// cache ledgers exactly without ever holding an unbounded image-only stream.
  void _commitPending(Set<String> placedIds) {
    if (_pendingImages.isEmpty) return;
    final additions = <MapEntry<String, Uint8List>>[
      for (final entry in _pendingImages.entries)
        if (placedIds.contains(entry.key) && !_imageCache.contains(entry.key))
          entry,
    ];
    final additionalBytes = additions.fold<int>(
      0,
      (total, entry) => total + entry.value.length,
    );
    _revoke(
      _imageCache.evictStaleToFit(
        placedIds,
        additionalEntries: additions.length,
        additionalBytes: additionalBytes,
      ),
    );

    for (final entry in additions) {
      // A malformed plan may declare a placed working set larger than the
      // policy. Keep the cache hard-bounded and degrade excess images to blank;
      // a conforming sender is filtered to the same policy before transmission.
      if (!_imageCache.canFit(
        additionalEntries: 1,
        additionalBytes: entry.value.length,
      )) {
        continue;
      }
      final blob = web.Blob(
        <JSAny>[entry.value.toJS].toJS,
        web.BlobPropertyBag(type: 'image/png'),
      );
      _blobUrls[entry.key] = web.URL.createObjectURL(blob);
      _imageCache.add(entry.key, entry.value.length);
    }
    _pendingImages.clear();
    _pendingImageBytes = 0;
  }

  /// Bounds the blob-URL cache by count and encoded bytes, revoking the oldest
  /// ids not currently placed. The producer bounds a conforming on-screen set;
  /// [_commitPending] drops excess additions from a malformed plan.
  void _evictStale(Set<String> placed) {
    _revoke(_imageCache.evictStale(placed));
  }

  void _revoke(Iterable<String> ids) {
    for (final id in ids) {
      final url = _blobUrls.remove(id);
      if (url != null) web.URL.revokeObjectURL(url);
    }
  }

  /// Revokes every blob URL and removes the overlay from the DOM.
  void dispose() {
    for (final url in _blobUrls.values) {
      web.URL.revokeObjectURL(url);
    }
    _blobUrls.clear();
    _pendingImages.clear();
    _pendingImageBytes = 0;
    _imageCache.clear();
    _els.clear();
    _rects.clear();
    _last = const <ImagePlacement>[];
    _overlay?.remove();
    _overlay = null;
    // Restore only the positioning value this overlay installed. If the
    // embedder replaced it with a different value while mounted, that newer
    // value remains authoritative.
    if (_ownsHostPosition &&
        _host.style.getPropertyValue('position') == 'relative' &&
        _host.style.getPropertyPriority('position').isEmpty) {
      if (_previousHostInlinePosition.isEmpty) {
        _host.style.removeProperty('position');
      } else {
        _host.style.setProperty(
          'position',
          _previousHostInlinePosition,
          _previousHostInlinePositionPriority,
        );
      }
    }
  }
}
