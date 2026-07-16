// TerminalImageEncoder: turns a frame's inline-image placements into the
// active terminal graphics protocol (Kitty / iTerm2 / Sixel).
//
// Widgets never build escape sequences — they place neutral
// [InlineImagePlacement]s into the CellBuffer (bytes + cell box + fit).
// This encoder runs inside the ANSI presenter, diffs the placement set
// frame-over-frame, and emits only what changed. Its output rides the
// renderer's `trailer` so pixels and text land in one synchronized-output
// frame.
//
// Geometry comes from the shared [resolveInlineImageFit] — the same math
// the glyph painters use, so a Kitty letterbox and a half-block letterbox
// land on the same cells.
//
// Per-protocol lifecycle:
//
//  * Kitty — content transmits once per id (`a=t`), placements are
//    created (`a=p`) and deleted (`a=d,d=i`) individually, and data for
//    content no longer on screen is freed (`a=d,d=I`). Kitty renders
//    images on a layer above text, so without explicit deletes a moved or
//    removed image would ghost. `cover`/`none` crops use the protocol's
//    source-rectangle keys (x,y,w,h) — no pixel work app-side.
//
//  * iTerm2 — fire-and-forget OSC 1337 at the resolved sub-rect. Because
//    the protocol has no source-rectangle keys, an image provider can
//    supply a lazy cropped-PNG callback; custom providers without one
//    degrade crop-requiring fits to `contain`. Changed overlapping stacks
//    are cleared and replayed in paint order so replacements cannot ghost.
//
//  * Sixel — rasterized app-side from the placement's decoded-RGBA
//    sidecar ([InlineImage.pixels]) at the conventional 10×20 pixels per
//    cell, median-cut quantized to ≤128 colors. Placements without the
//    sidecar are skipped (PNG cannot be decoded here). Changed overlapping
//    stacks are likewise cleared and replayed in paint order.

import 'dart:convert';
import 'dart:typed_data';

import '../rendering/cell.dart' show CellRole;
import '../rendering/cell_buffer.dart';
import 'capabilities.dart';

/// Encodes a frame's inline-image placements as terminal escape bytes.
///
/// Stateful: keeps the previous frame's placement set (and, for Kitty,
/// which content ids the terminal holds) so unchanged images cost zero
/// bytes. One instance per session, owned by the ANSI presenter.
final class TerminalImageEncoder {
  TerminalImageEncoder({
    required this.protocol,
    this.tmuxPassthrough = false,
    this.cellPixelWidth = 10,
    this.cellPixelHeight = 20,
  }) : assert(
         protocol != ImageProtocol.halfBlock,
         'halfBlock has no escape protocol — widgets paint glyph art '
         'directly; no encoder is involved.',
       );

  final ImageProtocol protocol;

  /// Wrap every escape in tmux's passthrough envelope (`ESC P tmux ;` with
  /// embedded ESC doubled). tmux drops unknown DCS/APC/OSC sequences by
  /// default; the envelope re-emits them to the host terminal. Cursor
  /// moves stay OUTSIDE the envelope — tmux must see and translate those.
  final bool tmuxPassthrough;

  /// Assumed cell pixel density for Sixel rasterization. Terminals scale
  /// the emitted raster to their real cell size via the sixel raster
  /// attributes; 10×20 is a sensible modern average.
  final int cellPixelWidth;
  final int cellPixelHeight;

  // ---- Kitty state ---------------------------------------------------------

  /// Content hash → kitty numeric image id. Stable for the session so a
  /// re-appearing image reuses its id (data may still need retransmit).
  final Map<String, int> _kittyIdByContent = <String, int>{};
  var _nextKittyImageId = 1;
  var _nextKittyPlacementId = 1;

  /// Content ids whose pixel data the terminal currently holds.
  final Set<String> _transmitted = <String>{};

  /// Kitty placements alive on screen after the previous frame.
  List<_KittyPlacement> _kittyLive = <_KittyPlacement>[];

  // ---- iTerm2 / Sixel state ------------------------------------------------

  /// Raster placements emitted in the previous frame, in paint order.
  /// Neither protocol has Kitty's individually-addressable placement model,
  /// so an ordered list (rather than a set) is required: duplicate and
  /// overlapping placements are visually meaningful.
  List<_RasterPlacement> _rasterLive = <_RasterPlacement>[];

  /// Escape bytes for [next]'s placements, diffed against the previous
  /// frame. Empty when nothing image-related changed. [fullRepaint] must
  /// mirror the frame's damage plan: the screen was (or will be) cleared,
  /// so all placement state resets and everything visible re-emits.
  String encodeFrame(CellBuffer next, {required bool fullRepaint}) {
    // Fast path: no images this frame and none left on screen from the last —
    // the common case for an image-free app on an image-capable terminal (the
    // encoder exists whenever the terminal has a protocol, so encodeFrame is
    // called every frame regardless of whether the app uses images). There is
    // nothing to place or delete, so skip the StringBuffer and the per-protocol
    // reconciliation lists/sets entirely. A full repaint still runs the reset
    // below; and if either live set is non-empty (images were on screen and are
    // now gone) the normal path runs to emit the deletions.
    if (!fullRepaint &&
        next.imagePlacements.isEmpty &&
        _kittyLive.isEmpty &&
        _rasterLive.isEmpty) {
      return '';
    }
    final out = StringBuffer();
    if (fullRepaint) _resetForRepaint(out);
    switch (protocol) {
      case ImageProtocol.kitty:
        _encodeKitty(next, out);
      case ImageProtocol.iterm2:
        _encodeIterm2(next, out);
      case ImageProtocol.sixel:
        _encodeSixelFrame(next, out);
      case ImageProtocol.halfBlock:
        break; // unreachable — constructor asserts.
    }
    return out.toString();
  }

  void _resetForRepaint(StringBuffer out) {
    if (protocol == ImageProtocol.kitty && _kittyLive.isNotEmpty) {
      // ED must clear visible kitty placements, but use the uppercase form
      // as a belt-and-braces reset that also frees their stored image data.
      // Otherwise clearing [_transmitted] below would lose the only record
      // from which an unreferenced terminal-side allocation can be freed.
      out.write(_wrap('\x1B_Ga=d,d=A,q=2\x1B\\'));
    }
    _kittyLive = <_KittyPlacement>[];
    // Conservatively assume the terminal may have dropped stored data on
    // a clear; retransmit on next placement. Full repaints are rare
    // (startup, resize), so the retransmit cost is incidental.
    _transmitted.clear();
    _rasterLive = <_RasterPlacement>[];
  }

  // ---- Shared helpers ------------------------------------------------------

  /// Resolves the placement's fit against its content dimensions, or a
  /// whole-box `fill` when the content didn't declare them.
  ResolvedImageFit? _resolve(
    InlineImagePlacement p,
    InlineImage image, {
    int pixelsPerCellX = 1,
    int pixelsPerCellY = 2,
  }) {
    final w = image.sourceWidth;
    final h = image.sourceHeight;
    if (w == null || h == null || w <= 0 || h <= 0) {
      return ResolvedImageFit(
        col: 0,
        row: 0,
        cols: p.cols,
        rows: p.rows,
        cropX: 0,
        cropY: 0,
        cropW: 0,
        cropH: 0,
        sourceWidth: 0,
        sourceHeight: 0,
      );
    }
    return resolveClippedInlineImageFit(
      placement: p,
      sourceWidth: w,
      sourceHeight: h,
      pixelsPerCellX: pixelsPerCellX,
      pixelsPerCellY: pixelsPerCellY,
    );
  }

  /// 1-based absolute cursor move to the resolved sub-rect's anchor.
  String _cup(InlineImagePlacement p, ResolvedImageFit f) =>
      '\x1B[${p.row + f.row + 1};${p.col + f.col + 1}H';

  String _wrap(String payload) {
    if (!tmuxPassthrough) return payload;
    final doubled = payload.replaceAll('\x1B', '\x1B\x1B');
    return '\x1BPtmux;$doubled\x1B\\';
  }

  // ---- Kitty ---------------------------------------------------------------

  void _encodeKitty(CellBuffer next, StringBuffer out) {
    // Resolve this frame's wanted placements.
    final wanted = <_KittyPlacement>[];
    for (final p in next.imagePlacements) {
      final image = next.images[p.id];
      if (image == null) continue;
      final f = _resolve(p, image);
      if (f == null) continue;
      wanted.add(
        _KittyPlacement(
          contentId: p.id,
          placement: p,
          fit: f,
          zIndex: wanted.length,
        ),
      );
    }

    // Multiset-match against the live set: identical (content, geometry)
    // survives untouched; everything else is placed/deleted. The resulting
    // list is built in WANTED order. Each placement also carries an explicit
    // z-index, so a mixture of survivors and additions can never accidentally
    // acquire creation-order stacking instead of paint-order stacking.
    //
    // Exact stable stacks are the hot path. A linear ordered-key check avoids
    // building any reconciliation tables and preserves every live placement
    // id as-is.
    if (wanted.length == _kittyLive.length) {
      var exact = true;
      for (var i = 0; i < wanted.length; i++) {
        if (wanted[i].key == _kittyLive[i].key) continue;
        exact = false;
        break;
      }
      // An exact empty stack can immediately follow a full-repaint reset.
      // In that case stored-data state was cleared but stale content→id
      // mappings still need the normal cleanup below.
      if (exact &&
          (wanted.isNotEmpty ||
              (_kittyIdByContent.isEmpty && _transmitted.isEmpty))) {
        return;
      }
    }

    final reconciled = <_KittyPlacement>[];
    final matchedLive = List<bool>.filled(_kittyLive.length, false);
    final liveOccurrences = <String, List<int>>{};
    for (var liveIndex = 0; liveIndex < _kittyLive.length; liveIndex++) {
      (liveOccurrences[_kittyLive[liveIndex].key] ??= <int>[]).add(liveIndex);
    }
    final occurrenceCursors = <String, int>{};
    for (final desired in wanted) {
      final occurrences = liveOccurrences[desired.key];
      final cursor = occurrenceCursors[desired.key] ?? 0;
      if (occurrences != null && cursor < occurrences.length) {
        final liveIndex = occurrences[cursor];
        occurrenceCursors[desired.key] = cursor + 1;
        matchedLive[liveIndex] = true;
        reconciled.add(_kittyLive[liveIndex]);
      } else {
        reconciled.add(desired);
      }
    }

    // Unmatched live placements remain in their original order, matching the
    // old pool-based reconciliation without its repeated scans/removals.
    for (var liveIndex = 0; liveIndex < _kittyLive.length; liveIndex++) {
      if (matchedLive[liveIndex]) continue;
      final dead = _kittyLive[liveIndex];
      out.write(
        _wrap(
          '\x1B_Ga=d,d=i,i=${dead.kittyImageId},p=${dead.kittyPlacementId},'
          'q=2\x1B\\',
        ),
      );
    }

    for (final place in reconciled) {
      if (place.kittyPlacementId != 0) continue;
      final image = next.images[place.contentId]!;
      final kittyId = _kittyIdByContent.putIfAbsent(
        place.contentId,
        () => _nextKittyImageId++,
      );
      place.kittyImageId = kittyId;
      if (_transmitted.add(place.contentId)) {
        _writeKittyTransmit(out, kittyId, image.bytes);
      }
      place.kittyPlacementId = _nextKittyPlacementId++;
      final f = place.fit;
      final crop = f.sourceWidth > 0 && f.cropsSource
          ? ',x=${f.cropX},y=${f.cropY},w=${f.cropW},h=${f.cropH}'
          : '';
      out.write(_cup(place.placement, f));
      out.write(
        _wrap(
          '\x1B_Ga=p,i=$kittyId,p=${place.kittyPlacementId},'
          'c=${f.cols},r=${f.rows},z=${place.zIndex}$crop,C=1,q=2\x1B\\',
        ),
      );
    }

    // Free terminal-side data for content nothing references anymore
    // (successive animation frames would otherwise accumulate forever).
    // Drop the id mapping too, so the content→id table doesn't grow
    // without bound over a long session of ever-changing images; if the
    // same content returns it simply gets a fresh id and re-transmits.
    final referenced = {for (final s in reconciled) s.contentId};
    for (final contentId in _transmitted.toList()) {
      if (referenced.contains(contentId)) continue;
      final kittyId = _kittyIdByContent[contentId];
      if (kittyId == null) {
        _transmitted.remove(contentId);
        continue;
      }
      out.write(_wrap('\x1B_Ga=d,d=I,i=$kittyId,q=2\x1B\\'));
      _transmitted.remove(contentId);
    }
    _kittyIdByContent.removeWhere(
      (contentId, _) => !referenced.contains(contentId),
    );

    _kittyLive = reconciled;
  }

  /// Transmit-only (`a=t`) upload: PNG bytes pass through untouched
  /// (format 100), base64-wrapped, chunked at 4 KiB with `m=1`
  /// continuations. `q=2` suppresses terminal responses (we don't read
  /// them).
  ///
  /// Under tmux, EACH chunk gets its OWN passthrough envelope rather than
  /// wrapping the whole multi-chunk stream once: tmux caps the size of a
  /// single passthrough sequence and silently drops one that exceeds it,
  /// so a large image wrapped as one envelope would never reach the host
  /// terminal (and _transmitted would then lie about it being delivered).
  /// Per-chunk envelopes keep every piece under the cap.
  void _writeKittyTransmit(StringBuffer out, int kittyId, Uint8List png) {
    final b64 = base64.encode(png);
    const chunkSize = 4096;
    var pos = 0;
    var first = true;
    while (pos < b64.length) {
      final end = (pos + chunkSize < b64.length) ? pos + chunkSize : b64.length;
      final isLast = end == b64.length;
      final chunk = StringBuffer('\x1B_G');
      if (first) {
        chunk.write('a=t,f=100,i=$kittyId,q=2,m=${isLast ? 0 : 1};');
        first = false;
      } else {
        chunk.write('m=${isLast ? 0 : 1};');
      }
      chunk.write(b64.substring(pos, end));
      chunk.write('\x1B\\');
      out.write(_wrap(chunk.toString()));
      pos = end;
    }
  }

  // ---- iTerm2 --------------------------------------------------------------

  void _encodeIterm2(CellBuffer next, StringBuffer out) {
    final wanted = <_RasterPlacement>[];
    final croppers = <Uint8List Function(int, int, int, int)?>[];
    for (final p in next.imagePlacements) {
      final image = next.images[p.id];
      if (image == null) continue;
      var f = _resolve(p, image);
      if (f == null) continue;
      final cropper = image.croppedBytes;
      // Custom providers may omit the lazy PNG crop sidecar. Preserve the
      // historical safe fallback for them: show the complete source with
      // contain geometry inside the visible rectangle rather than stretching
      // or pretending that an unexpressible source crop is exact.
      if (f.sourceWidth > 0 && f.cropsSource && cropper == null) {
        f = resolveInlineImageFit(
          sourceWidth: f.sourceWidth,
          sourceHeight: f.sourceHeight,
          cols: p.cols,
          rows: p.rows,
          fit: InlineImageFit.contain,
        );
      }
      wanted.add(_RasterPlacement(contentId: p.id, placement: p, fit: f));
      croppers.add(cropper);
    }
    final reconciliation = _reconcileRasterStack(wanted);
    if (!reconciliation.hasAffectedPlacements) {
      // This also updates logical paint order for a reorder of disjoint
      // placements, which has no visual work and therefore emits zero bytes.
      _rasterLive = wanted;
      return;
    }

    _clearStaleRasterCells(next, out, reconciliation.affectedOld);
    for (var i = 0; i < wanted.length; i++) {
      if (!reconciliation.affectedNew[i]) continue;
      final place = wanted[i];
      final image = next.images[place.contentId]!;
      final f = place.fit;
      // Keep the common/full-source path byte-for-byte zero-copy. The crop
      // callback is deliberately invoked only after reconciliation proves a
      // changed frame needs emission, and only for a partial source window.
      final cropper = croppers[i];
      final payload = f.sourceWidth > 0 && f.cropsSource && cropper != null
          ? cropper(f.cropX, f.cropY, f.cropW, f.cropH)
          : image.bytes;
      final b64 = base64.encode(payload);
      out.write(_cup(place.placement, f));
      out.write(
        _wrap(
          '\x1B]1337;File=inline=1;size=${payload.length};'
          'width=${f.cols};height=${f.rows};preserveAspectRatio=0:$b64\x07',
        ),
      );
    }
    _rasterLive = wanted;
  }

  // ---- Sixel ---------------------------------------------------------------

  void _encodeSixelFrame(CellBuffer next, StringBuffer out) {
    final wanted = <_RasterPlacement>[];
    for (final p in next.imagePlacements) {
      final image = next.images[p.id];
      if (image == null) continue;
      final pixels = image.pixels;
      final srcW = image.sourceWidth;
      final srcH = image.sourceHeight;
      // Sixel must re-rasterize; without the decoded-RGBA sidecar there
      // is nothing to encode (core cannot decode PNG).
      if (pixels == null ||
          srcW == null ||
          srcH == null ||
          srcW <= 0 ||
          srcH <= 0) {
        continue;
      }
      final f = _resolve(
        p,
        image,
        pixelsPerCellX: cellPixelWidth,
        pixelsPerCellY: cellPixelHeight,
      );
      if (f == null) continue;
      wanted.add(_RasterPlacement(contentId: p.id, placement: p, fit: f));
    }
    final reconciliation = _reconcileRasterStack(wanted);
    if (!reconciliation.hasAffectedPlacements) {
      _rasterLive = wanted;
      return;
    }

    _clearStaleRasterCells(next, out, reconciliation.affectedOld);
    for (var i = 0; i < wanted.length; i++) {
      if (!reconciliation.affectedNew[i]) continue;
      final place = wanted[i];
      final image = next.images[place.contentId]!;
      final pixels = image.pixels!;
      final srcW = image.sourceWidth!;
      final srcH = image.sourceHeight!;
      final f = place.fit;
      final tgtW = f.cols * cellPixelWidth;
      final tgtH = f.rows * cellPixelHeight;
      final rgba = _sampleCrop(pixels(), srcW, srcH, f, tgtW, tgtH);
      out.write(_cup(place.placement, f));
      out.write(_wrap(encodeSixel(rgba, tgtW, tgtH)));
    }
    _rasterLive = wanted;
  }

  _RasterReconciliation _reconcileRasterStack(List<_RasterPlacement> wanted) {
    // The overwhelmingly common path is an exact stable stack. Keep it
    // allocation-light and strictly O(n): no occurrence table, inversion
    // search, or overlap graph is needed when every ordered key matches.
    if (wanted.length == _rasterLive.length) {
      var exact = true;
      for (var i = 0; i < wanted.length; i++) {
        if (wanted[i].key == _rasterLive[i].key) continue;
        exact = false;
        break;
      }
      if (exact) {
        return _RasterReconciliation(
          affectedOld: List<bool>.filled(_rasterLive.length, false),
          affectedNew: List<bool>.filled(wanted.length, false),
        );
      }
    }

    final oldToNew = List<int>.filled(_rasterLive.length, -1);
    final newToOld = List<int>.filled(wanted.length, -1);

    // Multiset match. Duplicate placements are significant, so consume each
    // old occurrence at most once rather than reducing to a key set. Indexing
    // each key's old occurrences once and advancing a cursor keeps matching
    // O(old + wanted), including stacks with many identical duplicates.
    final oldOccurrences = <String, List<int>>{};
    for (var oldIndex = 0; oldIndex < _rasterLive.length; oldIndex++) {
      (oldOccurrences[_rasterLive[oldIndex].key] ??= <int>[]).add(oldIndex);
    }
    final occurrenceCursors = <String, int>{};
    var matchedOldIndicesMonotonic = true;
    var lastMatchedOldIndex = -1;
    for (var newIndex = 0; newIndex < wanted.length; newIndex++) {
      final key = wanted[newIndex].key;
      final occurrences = oldOccurrences[key];
      if (occurrences == null) continue;
      final cursor = occurrenceCursors[key] ?? 0;
      if (cursor >= occurrences.length) continue;
      final oldIndex = occurrences[cursor];
      occurrenceCursors[key] = cursor + 1;
      oldToNew[oldIndex] = newIndex;
      newToOld[newIndex] = oldIndex;
      if (oldIndex < lastMatchedOldIndex) {
        matchedOldIndicesMonotonic = false;
      }
      lastMatchedOldIndex = oldIndex;
    }

    final affectedOld = List<bool>.generate(
      _rasterLive.length,
      (i) => oldToNew[i] == -1,
      growable: false,
    );
    final affectedNew = List<bool>.generate(
      wanted.length,
      (i) => newToOld[i] == -1,
      growable: false,
    );

    // Reordering disjoint rectangles is only a bookkeeping change. An order
    // inversion matters precisely when the two live rectangles overlap. A
    // monotonic matched-index sequence proves there are no inversions at all,
    // avoiding this O(n²) changed-stack scan for stable order plus disjoint
    // insertions/removals.
    if (!matchedOldIndicesMonotonic) {
      for (var a = 0; a < wanted.length; a++) {
        final oldA = newToOld[a];
        if (oldA == -1) continue;
        for (var b = a + 1; b < wanted.length; b++) {
          final oldB = newToOld[b];
          if (oldB == -1 || oldA < oldB || !wanted[a].overlaps(wanted[b])) {
            continue;
          }
          affectedNew[a] = true;
          affectedNew[b] = true;
          affectedOld[oldA] = true;
          affectedOld[oldB] = true;
        }
      }
    }

    // Clearing one stale rectangle can erase any overlapping layer. Expand
    // seeds through the union of old and new overlap graphs (and through each
    // matched old/new occurrence) until every affected connected component is
    // complete. A queue visits each node once, keeping reconciliation O(n²).
    // Non-overlapping placements remain true survivors and never resend their
    // raster payload.
    final queue = <int>[];
    final newBase = _rasterLive.length;
    for (var i = 0; i < affectedOld.length; i++) {
      if (affectedOld[i]) queue.add(i);
    }
    for (var i = 0; i < affectedNew.length; i++) {
      if (affectedNew[i]) queue.add(newBase + i);
    }

    void addOld(int index) {
      if (affectedOld[index]) return;
      affectedOld[index] = true;
      queue.add(index);
    }

    void addNew(int index) {
      if (affectedNew[index]) return;
      affectedNew[index] = true;
      queue.add(newBase + index);
    }

    for (var head = 0; head < queue.length; head++) {
      final node = queue[head];
      if (node < newBase) {
        final oldIndex = node;
        final newIndex = oldToNew[oldIndex];
        if (newIndex != -1) addNew(newIndex);
        for (var other = 0; other < _rasterLive.length; other++) {
          if (_rasterLive[oldIndex].overlaps(_rasterLive[other])) addOld(other);
        }
        for (var other = 0; other < wanted.length; other++) {
          if (_rasterLive[oldIndex].overlaps(wanted[other])) addNew(other);
        }
      } else {
        final newIndex = node - newBase;
        final oldIndex = newToOld[newIndex];
        if (oldIndex != -1) addOld(oldIndex);
        for (var other = 0; other < wanted.length; other++) {
          if (wanted[newIndex].overlaps(wanted[other])) addNew(other);
        }
        for (var other = 0; other < _rasterLive.length; other++) {
          if (wanted[newIndex].overlaps(_rasterLive[other])) addOld(other);
        }
      }
    }

    return _RasterReconciliation(
      affectedOld: affectedOld,
      affectedNew: affectedNew,
    );
  }

  /// Clears stale raster pixels only where the next frame still owns the cell
  /// as an image overlay. Cells that reveal text/emptiness are intentionally
  /// excluded: the ANSI diff has just repainted those, and clearing them in
  /// this trailer would erase the new text. Every current placement is then
  /// replayed in paint order by the caller, restoring any stack this bounded
  /// screen-sized mask intersects.
  void _clearStaleRasterCells(
    CellBuffer next,
    StringBuffer out,
    List<bool> affectedOld,
  ) {
    if (_rasterLive.isEmpty ||
        next.size.isEmpty ||
        !affectedOld.any((affected) => affected)) {
      return;
    }
    final cols = next.size.cols;
    final rows = next.size.rows;
    final clear = Uint8List(cols * rows);
    var any = false;
    for (var i = 0; i < _rasterLive.length; i++) {
      if (!affectedOld[i]) continue;
      final old = _rasterLive[i];
      final left = (old.placement.col + old.fit.col).clamp(0, cols);
      final top = (old.placement.row + old.fit.row).clamp(0, rows);
      final right = (old.placement.col + old.fit.col + old.fit.cols).clamp(
        0,
        cols,
      );
      final bottom = (old.placement.row + old.fit.row + old.fit.rows).clamp(
        0,
        rows,
      );
      for (var row = top; row < bottom; row++) {
        for (var col = left; col < right; col++) {
          if (next.atColRow(col, row).role != CellRole.overlay) continue;
          clear[row * cols + col] = 1;
          any = true;
        }
      }
    }
    if (!any) return;

    out.write('\x1B[0m');
    for (var row = 0; row < rows; row++) {
      var col = 0;
      while (col < cols) {
        while (col < cols && clear[row * cols + col] == 0) {
          col++;
        }
        if (col == cols) break;
        final start = col;
        while (col < cols && clear[row * cols + col] != 0) {
          col++;
        }
        out.write('\x1B[${row + 1};${start + 1}H');
        out.write(''.padRight(col - start));
      }
    }
  }

  /// Bilinearly samples the resolved source crop into a tgtW×tgtH RGBA
  /// buffer, compositing alpha onto black (sixel has no transparency).
  Uint8List _sampleCrop(
    Uint8List src,
    int srcW,
    int srcH,
    ResolvedImageFit f,
    int tgtW,
    int tgtH,
  ) {
    final dst = Uint8List(tgtW * tgtH * 4);
    for (var y = 0; y < tgtH; y++) {
      final sy = f.cropY + (y + 0.5) * f.cropH / tgtH - 0.5;
      final y0 = sy.floor().clamp(0, srcH - 1);
      final y1 = (y0 + 1).clamp(0, srcH - 1);
      final fy = (sy - y0).clamp(0.0, 1.0);
      for (var x = 0; x < tgtW; x++) {
        final sx = f.cropX + (x + 0.5) * f.cropW / tgtW - 0.5;
        final x0 = sx.floor().clamp(0, srcW - 1);
        final x1 = (x0 + 1).clamp(0, srcW - 1);
        final fx = (sx - x0).clamp(0.0, 1.0);
        final di = (y * tgtW + x) * 4;
        for (var c = 0; c < 4; c++) {
          final p00 = src[(y0 * srcW + x0) * 4 + c].toDouble();
          final p10 = src[(y0 * srcW + x1) * 4 + c].toDouble();
          final p01 = src[(y1 * srcW + x0) * 4 + c].toDouble();
          final p11 = src[(y1 * srcW + x1) * 4 + c].toDouble();
          final top = p00 + (p10 - p00) * fx;
          final bottom = p01 + (p11 - p01) * fx;
          dst[di + c] = (top + (bottom - top) * fy).round().clamp(0, 255);
        }
        // Composite onto black: out = α·src.
        final a = dst[di + 3] / 255.0;
        if (a < 1.0) {
          dst[di] = (dst[di] * a).round();
          dst[di + 1] = (dst[di + 1] * a).round();
          dst[di + 2] = (dst[di + 2] * a).round();
        }
      }
    }
    return dst;
  }
}

final class _KittyPlacement {
  _KittyPlacement({
    required this.contentId,
    required this.placement,
    required this.fit,
    required this.zIndex,
  });

  final String contentId;
  final InlineImagePlacement placement;
  final ResolvedImageFit fit;
  final int zIndex;
  int kittyImageId = 0;
  int kittyPlacementId = 0;

  /// Identity for the frame-over-frame multiset match: same content at
  /// the same resolved geometry → the live placement survives untouched.
  ///
  /// Cached (`late final`) so the reconciliation — which compares each wanted
  /// placement's key against the live pool (O(wanted × live)) — builds this
  /// interpolated string once per placement instead of once per comparison.
  late final String key =
      '$contentId|${placement.col},${placement.row}|'
      '${fit.col},${fit.row},${fit.cols},${fit.rows}|'
      '${fit.cropX},${fit.cropY},${fit.cropW},${fit.cropH}|z=$zIndex';
}

final class _RasterPlacement {
  _RasterPlacement({
    required this.contentId,
    required this.placement,
    required this.fit,
  });

  final String contentId;
  final InlineImagePlacement placement;
  final ResolvedImageFit fit;

  late final String key =
      '$contentId|${placement.col},${placement.row}|'
      '${fit.col},${fit.row},${fit.cols},${fit.rows}|'
      '${fit.cropX},${fit.cropY},${fit.cropW},${fit.cropH}';

  int get left => placement.col + fit.col;
  int get top => placement.row + fit.row;
  int get right => left + fit.cols;
  int get bottom => top + fit.rows;

  bool overlaps(_RasterPlacement other) =>
      left < other.right &&
      other.left < right &&
      top < other.bottom &&
      other.top < bottom;
}

final class _RasterReconciliation {
  const _RasterReconciliation({
    required this.affectedOld,
    required this.affectedNew,
  });

  final List<bool> affectedOld;
  final List<bool> affectedNew;

  bool get hasAffectedPlacements =>
      affectedOld.any((affected) => affected) ||
      affectedNew.any((affected) => affected);
}

/// Encodes an RGBA buffer as a Sixel byte stream: raster attributes for
/// 1:1 pixel aspect, a ≤128-color median-cut palette, then per-band
/// per-color column masks with RLE compression. Deterministic for a given
/// input (the bytes are asserted in tests).
///
/// Exposed as a top-level function so tests can pin the byte format
/// without driving the whole encoder lifecycle.
String encodeSixel(Uint8List rgba, int width, int height) {
  final quantized = _medianCut(rgba, width * height, 128);
  final indexed = quantized.indexed;
  final palette = quantized.palette;

  final buf = StringBuffer();
  // DCS introducer. `q` is the Sixel control; no parameters means the
  // terminal applies its default aspect / background settings.
  buf.write('\x1BPq');
  // Raster attributes: pan/pad of 1:1 (square pixels), Ph/Pv = emitted
  // image extent. Terminals use this to scale into cell space.
  buf.write('"1;1;$width;$height');

  // Palette definitions: `# Pc ; 2 ; R ; G ; B` per color, 0..100.
  for (var i = 0; i < palette.length; i++) {
    final c = palette[i];
    final r = (((c >> 16) & 0xFF) * 100 / 255).round().clamp(0, 100);
    final g = (((c >> 8) & 0xFF) * 100 / 255).round().clamp(0, 100);
    final b = ((c & 0xFF) * 100 / 255).round().clamp(0, 100);
    buf.write('#$i;2;$r;$g;$b');
  }

  // Per 6-row band: for each palette color appearing in the band, emit a
  // color-select then a per-column 6-bit mask. Colors are visited in
  // ascending index order for deterministic output.
  for (var bandY = 0; bandY < height; bandY += 6) {
    final bandH = (height - bandY < 6) ? height - bandY : 6;

    final colorsInBand = <int>{};
    for (var y = bandY; y < bandY + bandH; y++) {
      for (var x = 0; x < width; x++) {
        colorsInBand.add(indexed[y * width + x]);
      }
    }
    final sorted = colorsInBand.toList()..sort();

    var first = true;
    for (final color in sorted) {
      // Carriage return resets to column 0 within the same band so
      // subsequent colors overlay onto the same pixel row group.
      if (!first) buf.write(r'$');
      first = false;
      buf.write('#$color');

      // Column sequence as sixel bytes, RLE-compressing runs of identical
      // bytes via `!Pn X` (runs of 4+ save bytes).
      var prevByte = -1;
      var runLen = 0;

      void flushRun() {
        if (runLen == 0) return;
        if (runLen >= 4) {
          buf.write('!$runLen');
          buf.writeCharCode(prevByte);
        } else {
          for (var i = 0; i < runLen; i++) {
            buf.writeCharCode(prevByte);
          }
        }
        runLen = 0;
      }

      for (var x = 0; x < width; x++) {
        var mask = 0;
        for (var by = 0; by < bandH; by++) {
          if (indexed[(bandY + by) * width + x] == color) {
            mask |= 1 << by;
          }
        }
        final byte = 0x3F + mask; // sixel byte is in '?'..'~' range
        if (byte == prevByte) {
          runLen++;
        } else {
          flushRun();
          prevByte = byte;
          runLen = 1;
        }
      }
      flushRun();
    }

    // Advance to the next 6-row band (no `-` after the final band — the
    // terminator handles end-of-image).
    if (bandY + 6 < height) buf.write('-');
  }

  // ST terminator.
  buf.write('\x1B\\');
  return buf.toString();
}

/// Scores the `order[start..end)` box: its widest RGB channel and the
/// split priority (widest range × population). Computed once per box.
({int start, int end, int channel, int score}) _scoreBox(
  Uint32List order,
  Uint8List rgba,
  int start,
  int end,
) {
  final n = end - start;
  if (n < 2) return (start: start, end: end, channel: 0, score: 0);
  var minR = 255, maxR = 0, minG = 255, maxG = 0, minB = 255, maxB = 0;
  for (var i = start; i < end; i++) {
    final o = order[i] * 4;
    final r = rgba[o], g = rgba[o + 1], bl = rgba[o + 2];
    if (r < minR) minR = r;
    if (r > maxR) maxR = r;
    if (g < minG) minG = g;
    if (g > maxG) maxG = g;
    if (bl < minB) minB = bl;
    if (bl > maxB) maxB = bl;
  }
  final rangeR = maxR - minR, rangeG = maxG - minG, rangeB = maxB - minB;
  var channel = 0;
  var widest = rangeR;
  if (rangeG > widest) {
    channel = 1;
    widest = rangeG;
  }
  if (rangeB > widest) {
    channel = 2;
    widest = rangeB;
  }
  return (start: start, end: end, channel: channel, score: widest * n);
}

/// Median-cut color quantization: recursively splits the pixel population
/// on the widest RGB channel at its median until [maxColors] boxes exist,
/// then assigns each box its mean color. Pure Dart, deterministic, no
/// dependencies — quality in the same class as the classic GIF quantizers
/// for the ≤128-color budget sixel gets.
({Uint8List indexed, List<int> palette}) _medianCut(
  Uint8List rgba,
  int pixelCount,
  int maxColors,
) {
  final indexed = Uint8List(pixelCount);
  if (pixelCount == 0) {
    return (indexed: indexed, palette: const <int>[0]);
  }
  // Pixel order table — boxes are ranges of this list.
  final order = Uint32List(pixelCount);
  for (var i = 0; i < pixelCount; i++) {
    order[i] = i;
  }

  // Each box caches its widest channel + split score (range × population),
  // computed ONCE when the box is created. A split re-scores only its two
  // children, so total work is O(pixels × log maxColors) instead of the
  // O(maxColors × pixels) a full rescan-every-box-every-split would cost —
  // the difference between a few ms and hundreds of ms on a full-screen
  // sixel raster.
  final boxes = <({int start, int end, int channel, int score})>[
    _scoreBox(order, rgba, 0, pixelCount),
  ];
  while (boxes.length < maxColors) {
    // Split the box with the largest cached score first — a good proxy for
    // "where quantization error lives". Strict > keeps the earliest box on
    // ties (deterministic output).
    var bestBox = -1;
    var bestScore = 0;
    for (var b = 0; b < boxes.length; b++) {
      if (boxes[b].score > bestScore) {
        bestScore = boxes[b].score;
        bestBox = b;
      }
    }
    if (bestBox < 0) break; // every box is a single color/pixel

    final box = boxes[bestBox];
    final channel = box.channel;
    final slice = order.sublist(box.start, box.end)
      ..sort((a, b) => rgba[a * 4 + channel] - rgba[b * 4 + channel]);
    order.setRange(box.start, box.end, slice);
    final mid = box.start + (box.end - box.start) ~/ 2;
    boxes[bestBox] = _scoreBox(order, rgba, box.start, mid);
    boxes.add(_scoreBox(order, rgba, mid, box.end));
  }

  final palette = <int>[];
  for (var b = 0; b < boxes.length; b++) {
    final box = boxes[b];
    var r = 0, g = 0, bl = 0;
    final n = box.end - box.start;
    for (var i = box.start; i < box.end; i++) {
      final o = order[i] * 4;
      r += rgba[o];
      g += rgba[o + 1];
      bl += rgba[o + 2];
    }
    palette.add(n == 0 ? 0 : ((r ~/ n) << 16) | ((g ~/ n) << 8) | (bl ~/ n));
    for (var i = box.start; i < box.end; i++) {
      indexed[order[i]] = b;
    }
  }
  return (indexed: indexed, palette: palette);
}
