// Binary codecs for the structured remote frames (PLAN, INPUT_EVENT).
//
// The serve transport carries fleury's own presentation plans and input
// events instead of raw ANSI — see remote_protocol.dart for framing and
// serve-dom-client-plan.md for the why. These codecs are version-locked:
// server and client ship from the same fleury build, so enum indices are
// a stable wire contract within a session (the INIT version byte guards
// across builds).
//
// All integers big-endian. Strings are u32 length + UTF-8 bytes.

import 'dart:convert';
import 'dart:typed_data';

import '../foundation/geometry.dart';
import '../rendering/cell.dart';
import '../rendering/cell_buffer.dart';
import '../terminal/events.dart';

/// A frame reduced to its changed cells for the wire: the grid size,
/// repaint/scroll flags, a per-frame style table, and the changed
/// column-range patches. The client applies the patches to a [CellBuffer]
/// mirror and rebuilds the dirty rows from it (reusing the span builder),
/// so only changed cells travel — the efficiency ANSI gets implicitly.
final class RemotePlan {
  const RemotePlan({
    required this.size,
    required this.fullRepaint,
    required this.styleTable,
    required this.patches,
    this.scrollUpRows,
  });

  final CellSize size;
  final bool fullRepaint;
  final int? scrollUpRows;

  /// Distinct styles used by the patches, referenced by index from runs.
  final List<CellStyle> styleTable;

  /// Changed column-range patches.
  final List<RemoteRowPatch> patches;
}

/// One contiguous changed column range in a row.
final class RemoteRowPatch {
  const RemoteRowPatch({
    required this.row,
    required this.startCol,
    required this.runs,
  });

  final int row;
  final int startCol;

  /// Runs grouped by style, laid out left to right from [startCol]. The
  /// run text's grapheme widths advance the column (wide glyphs occupy 2).
  final List<RemotePatchRun> runs;
}

/// A run of same-style cells within a patch.
final class RemotePatchRun {
  const RemotePatchRun({required this.styleIndex, required this.text});

  final int styleIndex;
  final String text;
}

/// Thrown when a structured frame payload is malformed.
final class RemoteCodecException implements Exception {
  const RemoteCodecException(this.message);
  final String message;
  @override
  String toString() => 'RemoteCodecException: $message';
}

// ---- writer / reader -------------------------------------------------------

class _Writer {
  // copy:true is required — multi-byte writes share one scratch buffer, so a
  // non-copying builder would alias every view to the last value written.
  final BytesBuilder _b = BytesBuilder();
  final ByteData _scratch = ByteData(4);

  void u8(int v) => _b.addByte(v & 0xFF);

  void u16(int v) {
    _scratch.setUint16(0, v);
    _b.add(_scratch.buffer.asUint8List(0, 2));
  }

  void u32(int v) {
    _scratch.setUint32(0, v);
    _b.add(_scratch.buffer.asUint8List(0, 4));
  }

  void i32(int v) {
    _scratch.setInt32(0, v);
    _b.add(_scratch.buffer.asUint8List(0, 4));
  }

  void str(String s) {
    final bytes = utf8.encode(s);
    u32(bytes.length);
    _b.add(bytes);
  }

  /// LEB128 unsigned varint — small values (the common case: columns,
  /// counts, style indices) cost one byte instead of the fixed 2–4.
  void varint(int v) {
    assert(v >= 0, 'varint is unsigned');
    var x = v;
    while (x >= 0x80) {
      _b.addByte((x & 0x7F) | 0x80);
      x >>= 7;
    }
    _b.addByte(x);
  }

  /// Varint-length-prefixed UTF-8 string.
  void vstr(String s) {
    final bytes = utf8.encode(s);
    varint(bytes.length);
    _b.add(bytes);
  }

  void boolean(bool v) => u8(v ? 1 : 0);

  Uint8List take() => _b.toBytes();
}

class _Reader {
  _Reader(this._data);
  final Uint8List _data;
  int _pos = 0;

  int u8() {
    _need(1);
    return _data[_pos++];
  }

  int u16() {
    _need(2);
    final v = ByteData.sublistView(_data, _pos, _pos + 2).getUint16(0);
    _pos += 2;
    return v;
  }

  int u32() {
    _need(4);
    final v = ByteData.sublistView(_data, _pos, _pos + 4).getUint32(0);
    _pos += 4;
    return v;
  }

  int i32() {
    _need(4);
    final v = ByteData.sublistView(_data, _pos, _pos + 4).getInt32(0);
    _pos += 4;
    return v;
  }

  String str() {
    final len = u32();
    _need(len);
    final s = utf8.decode(_data.sublist(_pos, _pos + len), allowMalformed: true);
    _pos += len;
    return s;
  }

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final byte = u8();
      result |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) {
        // Counts and lengths are well under this; a value that would set
        // the sign bit (or otherwise exceed a sane bound) is malformed —
        // reject it rather than let a negative length reach `sublist`.
        if (result < 0 || result > 0x7FFFFFFF) {
          throw const RemoteCodecException('varint out of range');
        }
        return result;
      }
      // 5 continuation bytes (35 bits) is far more than any real count;
      // cap the shift so a malicious stream can't build a huge/negative int.
      shift += 7;
      if (shift > 35) {
        throw const RemoteCodecException('varint too long');
      }
    }
  }

  String vstr() {
    final len = varint();
    _need(len);
    final s = utf8.decode(_data.sublist(_pos, _pos + len), allowMalformed: true);
    _pos += len;
    return s;
  }

  bool boolean() => u8() != 0;

  void _need(int n) {
    if (_pos + n > _data.length) {
      throw const RemoteCodecException('truncated payload');
    }
  }

  void expectEnd() {
    if (_pos != _data.length) {
      throw const RemoteCodecException('trailing bytes after frame');
    }
  }

  T enumValue<T>(List<T> values) {
    final i = u8();
    if (i < 0 || i >= values.length) {
      throw RemoteCodecException('enum index $i out of range');
    }
    return values[i];
  }
}

// ---- color / style ---------------------------------------------------------

void _writeColor(_Writer w, Color? c) {
  switch (c) {
    case null:
      w.u8(0);
    case AnsiColor():
      w.u8(1);
      w.u8(c.index);
    case IndexedColor():
      w.u8(2);
      w.u8(c.index);
    case RgbColor():
      w.u8(3);
      w
        ..u8(c.r)
        ..u8(c.g)
        ..u8(c.b);
  }
}

Color? _readColor(_Reader r) {
  final tag = r.u8();
  switch (tag) {
    case 0:
      return null;
    case 1:
      final index = r.u8();
      if (index > 15) {
        throw RemoteCodecException('AnsiColor index $index out of range');
      }
      return AnsiColor(index);
    case 2:
      return IndexedColor(r.u8());
    case 3:
      return RgbColor(r.u8(), r.u8(), r.u8());
    default:
      throw RemoteCodecException('unknown color tag $tag');
  }
}

// CellStyle bool? attributes pack into two bytes: a "set" mask and a
// "value" mask, so the tri-state (null / true / false) round-trips exactly.
void _writeStyle(_Writer w, CellStyle s) {
  var setMask = 0;
  var valMask = 0;
  void bit(int i, bool? v) {
    if (v == null) return;
    setMask |= 1 << i;
    if (v) valMask |= 1 << i;
  }

  bit(0, s.boldOrNull);
  bit(1, s.dimOrNull);
  bit(2, s.italicOrNull);
  bit(3, s.underlineOrNull);
  bit(4, s.inverseOrNull);
  bit(5, s.strikethroughOrNull);
  w
    ..u8(setMask)
    ..u8(valMask);
  _writeColor(w, s.foreground);
  _writeColor(w, s.background);
}

CellStyle _readStyle(_Reader r) {
  final setMask = r.u8();
  final valMask = r.u8();
  bool? bit(int i) =>
      (setMask & (1 << i)) == 0 ? null : (valMask & (1 << i)) != 0;
  final fg = _readColor(r);
  final bg = _readColor(r);
  return CellStyle(
    foreground: fg,
    background: bg,
    bold: bit(0),
    dim: bit(1),
    italic: bit(2),
    underline: bit(3),
    inverse: bit(4),
    strikethrough: bit(5),
  );
}

// ---- plan ------------------------------------------------------------------

/// Encodes a [RemotePlan] to wire bytes.
///
/// Wire shape (the cell-patch design): only the changed column ranges
/// ship, each as runs grouped by style, with styles deduplicated into a
/// per-frame table referenced by varint index. Integers are varints. This
/// keeps the wire close to "only changed cells, style once per run" — the
/// efficiency ANSI gets implicitly — so it stays competitive with (and
/// usually beats) a deflated ANSI stream over the socket.
Uint8List encodeRemotePlan(RemotePlan plan) {
  final w = _Writer();
  var flags = 0;
  if (plan.fullRepaint) flags |= 1;
  if (plan.scrollUpRows != null) flags |= 2;
  w
    ..u8(flags)
    ..varint(plan.size.cols)
    ..varint(plan.size.rows);
  if (plan.scrollUpRows != null) w.varint(plan.scrollUpRows!);
  w.varint(plan.styleTable.length);
  for (final style in plan.styleTable) {
    _writeStyle(w, style);
  }
  w.varint(plan.patches.length);
  for (final patch in plan.patches) {
    w
      ..varint(patch.row)
      ..varint(patch.startCol)
      ..varint(patch.runs.length);
    for (final run in patch.runs) {
      w
        ..varint(run.styleIndex)
        ..vstr(run.text);
    }
  }
  return w.take();
}

/// Decodes a [RemotePlan] from wire bytes.
RemotePlan decodeRemotePlan(Uint8List bytes) {
  final r = _Reader(bytes);
  final flags = r.u8();
  final cols = r.varint();
  final rows = r.varint();
  final scrollUp = (flags & 2) != 0 ? r.varint() : null;
  final styleCount = r.varint();
  final styleTable = <CellStyle>[
    for (var i = 0; i < styleCount; i++) _readStyle(r),
  ];
  final patchCount = r.varint();
  final patches = <RemoteRowPatch>[];
  for (var i = 0; i < patchCount; i++) {
    final row = r.varint();
    final startCol = r.varint();
    final runCount = r.varint();
    final runs = <RemotePatchRun>[];
    for (var j = 0; j < runCount; j++) {
      final styleIndex = r.varint();
      if (styleIndex >= styleTable.length) {
        throw RemoteCodecException('style index $styleIndex out of range');
      }
      runs.add(RemotePatchRun(styleIndex: styleIndex, text: r.vstr()));
    }
    patches.add(
      RemoteRowPatch(
        row: row,
        startCol: startCol,
        runs: List.unmodifiable(runs),
      ),
    );
  }
  r.expectEnd();
  return RemotePlan(
    size: CellSize(cols, rows),
    fullRepaint: (flags & 1) != 0,
    scrollUpRows: scrollUp,
    styleTable: List.unmodifiable(styleTable),
    patches: List.unmodifiable(patches),
  );
}

// ---- plan build / apply ----------------------------------------------------

/// Builds a [RemotePlan] from the rendered [prev]/[next] buffers — the
/// changed column ranges only, grouped into same-style runs with a
/// per-frame style table. On [fullRepaint] (or a size change) every row
/// is treated as changed.
RemotePlan buildRemotePlan(
  CellBuffer prev,
  CellBuffer next, {
  required bool fullRepaint,
}) {
  final full = fullRepaint || prev.size != next.size;
  final cols = next.size.cols;
  final rows = next.size.rows;
  final styleIndices = <CellStyle, int>{};
  final styleTable = <CellStyle>[];
  int styleIndex(CellStyle s) =>
      styleIndices.putIfAbsent(s, () {
        styleTable.add(s);
        return styleTable.length - 1;
      });

  final patches = <RemoteRowPatch>[];
  for (var row = 0; row < rows; row++) {
    var col = 0;
    while (col < cols) {
      // Find the start of the next changed run.
      if (!full && _cellEqual(prev, next, col, row)) {
        col++;
        continue;
      }
      final startCol = col;
      final runs = <RemotePatchRun>[];
      // Extend the patch over contiguous changed cells, grouping by style.
      while (col < cols && (full || !_cellEqual(prev, next, col, row))) {
        final style = next.atColRow(col, row).style;
        final buffer = StringBuffer();
        while (col < cols &&
            (full || !_cellEqual(prev, next, col, row)) &&
            next.atColRow(col, row).style == style) {
          final cell = next.atColRow(col, row);
          // continuation cells contribute nothing (the leading cell's
          // grapheme already spans them); empty/blank render as a space.
          if (cell.role != CellRole.continuation) {
            buffer.write(cell.grapheme ?? ' ');
          }
          col++;
        }
        runs.add(
          RemotePatchRun(styleIndex: styleIndex(style), text: buffer.toString()),
        );
      }
      patches.add(
        RemoteRowPatch(row: row, startCol: startCol, runs: runs),
      );
    }
  }

  return RemotePlan(
    size: next.size,
    fullRepaint: full,
    styleTable: styleTable,
    patches: patches,
  );
}

bool _cellEqual(CellBuffer a, CellBuffer b, int col, int row) =>
    a.atColRow(col, row) == b.atColRow(col, row);

/// Applies a decoded [plan] to a [CellBuffer] mirror, reproducing the
/// server's frame. The client rebuilds the dirty DOM rows from the mirror
/// afterward. Returns the row indices the plan touched.
Set<int> applyRemotePlanToBuffer(RemotePlan plan, CellBuffer mirror) {
  final touched = <int>{};
  for (final patch in plan.patches) {
    if (patch.row < 0 || patch.row >= mirror.size.rows) continue;
    touched.add(patch.row);
    var col = patch.startCol;
    for (final run in patch.runs) {
      if (run.styleIndex < 0 || run.styleIndex >= plan.styleTable.length) {
        continue;
      }
      final style = plan.styleTable[run.styleIndex];
      final advanced = mirror.writeText(
        CellOffset(col, patch.row),
        run.text,
        style: style,
      );
      col += advanced == 0 ? run.text.length : advanced;
    }
  }
  return touched;
}

// ---- input events ----------------------------------------------------------

const int _evKey = 1;
const int _evText = 2;
const int _evComposition = 3;
const int _evMouse = 4;
const int _evPaste = 5;
const int _evResize = 6;

void _writeModifiers(_Writer w, Set<KeyModifier> mods) {
  var mask = 0;
  for (final m in mods) {
    mask |= 1 << m.index;
  }
  w.u8(mask);
}

Set<KeyModifier> _readModifiers(_Reader r) {
  final mask = r.u8();
  return {
    for (final m in KeyModifier.values)
      if ((mask & (1 << m.index)) != 0) m,
  };
}

/// Encodes a [TuiEvent] to wire bytes. Throws [RemoteCodecException] for an
/// event kind not carried by the serve protocol.
Uint8List encodeInputEvent(TuiEvent event) {
  final w = _Writer();
  switch (event) {
    case KeyEvent e:
      w.u8(_evKey);
      // keyCode is optional; encode presence then index.
      w.boolean(e.keyCode != null);
      if (e.keyCode != null) w.u8(e.keyCode!.index);
      w.boolean(e.char != null);
      if (e.char != null) w.str(e.char!);
      _writeModifiers(w, e.modifiers);
      w.u8(e.type.index);
    case TextInputEvent e:
      w.u8(_evText);
      w.str(e.text);
    case TextCompositionEvent e:
      w.u8(_evComposition);
      w.u8(e.kind.index);
      w.boolean(e.text != null);
      if (e.text != null) w.str(e.text!);
    case MouseEvent e:
      w.u8(_evMouse);
      w
        ..u8(e.kind.index)
        ..u8(e.button.index)
        ..i32(e.col)
        ..i32(e.row);
      _writeModifiers(w, e.modifiers);
    case PasteEvent e:
      w.u8(_evPaste);
      w.str(e.text);
    case ResizeEvent e:
      w.u8(_evResize);
      w
        ..u16(e.size.cols)
        ..u16(e.size.rows);
  }
  return w.take();
}

/// Decodes a [TuiEvent] from wire bytes.
TuiEvent decodeInputEvent(Uint8List bytes) {
  final r = _Reader(bytes);
  final tag = r.u8();
  final TuiEvent event;
  switch (tag) {
    case _evKey:
      final keyCode = r.boolean() ? r.enumValue(KeyCode.values) : null;
      final char = r.boolean() ? r.str() : null;
      final mods = _readModifiers(r);
      final type = r.enumValue(KeyEventType.values);
      if (keyCode == null && char == null) {
        throw const RemoteCodecException(
          'key event must carry a keyCode or char',
        );
      }
      event = KeyEvent(
        keyCode: keyCode,
        char: char,
        modifiers: mods,
        type: type,
      );
    case _evText:
      event = TextInputEvent(r.str());
    case _evComposition:
      final kind = r.enumValue(TextCompositionEventKind.values);
      final text = r.boolean() ? r.str() : null;
      event = switch (kind) {
        TextCompositionEventKind.update => TextCompositionEvent.update(
          text ?? '',
        ),
        TextCompositionEventKind.commit => TextCompositionEvent.commit(text),
        TextCompositionEventKind.cancel => const TextCompositionEvent.cancel(),
      };
    case _evMouse:
      final kind = r.enumValue(MouseEventKind.values);
      final button = r.enumValue(MouseButton.values);
      final col = r.i32();
      final row = r.i32();
      final mods = _readModifiers(r);
      event = MouseEvent(
        kind: kind,
        button: button,
        col: col,
        row: row,
        modifiers: mods,
      );
    case _evPaste:
      event = PasteEvent(r.str());
    case _evResize:
      event = ResizeEvent(CellSize(r.u16(), r.u16()));
    default:
      throw RemoteCodecException('unknown input-event tag $tag');
  }
  r.expectEnd();
  return event;
}
