import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fleury/src/remote/remote_codec.dart' show ImagePlacement;
import 'package:web/web.dart' as web;

import '../metrics/cell_metrics.dart';

/// The browser inline-image layer: an absolutely-positioned, non-interactive
/// `<img>` overlay above the cell grid. Bytes arrive once per content-hash id
/// (cached as blob URLs); each frame's [ImagePlacement]s are reconciled into
/// positioned `<img>` elements. Pulled out of `RemoteSurfaceClient` so the DOM
/// reconcile — occurrence keying, eviction, the canvas-offset placement — is
/// unit-testable in a real browser, not just by manual inspection.
class InlineImageOverlay {
  InlineImageOverlay(this._host) {
    // The grid replaceChildren's its own root, so the overlay must be a sibling
    // of it under the host; absolutely positioned over the grid, with
    // pointer-events:none so clicks fall through to the cells.
    _host.style.setProperty('position', 'relative');
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
  web.HTMLElement? _overlay;

  // Blob URLs by content-hash id (so the same image at several spots shares one
  // decode); <img> elements and last-applied geometry by 'id#occurrence' so
  // repeated placements of one image each get a distinct element.
  final Map<String, String> _blobUrls = <String, String>{};
  final Map<String, web.HTMLImageElement> _els = <String, web.HTMLImageElement>{};
  final Map<String, String> _rects = <String, String>{};
  List<ImagePlacement> _last = const <ImagePlacement>[];

  // The host re-ships an image whenever it (re)appears, so the overlay may
  // freely evict ids that are NOT currently placed once the cache grows past
  // this bound — the on-screen working set is never dropped.
  static const int _maxCachedImages = 512;

  /// Number of live `<img>` elements — for tests/diagnostics.
  int get imageElementCount => _els.length;

  /// Caches one inline image's bytes as a blob URL, keyed by content-hash id.
  /// Idempotent: a re-send (after eviction) just refreshes the URL.
  void cacheImage(String id, Uint8List bytes) {
    if (_blobUrls.containsKey(id)) return;
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    _blobUrls[id] = web.URL.createObjectURL(blob);
  }

  /// Re-applies the most recent placement set against [box] — used on resize so
  /// images track the new cell pitch even without a fresh frame.
  void reapply(MeasuredCellBox box) => apply(_last, box);

  /// Reconciles the `<img>` overlay against this frame's [placements] (the full
  /// current set) measured against [box].
  void apply(List<ImagePlacement> placements, MeasuredCellBox box) {
    _last = placements;
    final overlay = _overlay;
    if (overlay == null) return;
    final cw = box.cssCellWidth;
    final ch = box.cssCellHeight;
    // Match the grid's origin convention (see DomInputSource caret math): the
    // canvas may be inset within the host, so add its offset.
    final ox = box.cssCanvasLeft;
    final oy = box.cssCanvasTop;
    final seen = <String>{};
    final placedIds = <String>{};
    final occurrence = <String, int>{};
    for (final p in placements) {
      placedIds.add(p.id);
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

  /// Bounds the blob-URL cache, revoking only ids not currently placed once it
  /// exceeds [_maxCachedImages]; the on-screen set is never dropped.
  void _evictStale(Set<String> placed) {
    if (_blobUrls.length <= _maxCachedImages) return;
    for (final id in _blobUrls.keys.toList()) {
      if (_blobUrls.length <= _maxCachedImages) break;
      if (placed.contains(id)) continue;
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
    _els.clear();
    _rects.clear();
    _last = const <ImagePlacement>[];
    _overlay?.remove();
    _overlay = null;
  }
}
