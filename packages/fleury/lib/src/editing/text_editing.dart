import 'dart:math' as math;

import 'package:characters/characters.dart';

/// A half-open text range: [start] is included, [end] is excluded.
final class TextRange {
  const TextRange({required this.start, required this.end});

  const TextRange.collapsed(int offset) : start = offset, end = offset;

  static const empty = TextRange(start: 0, end: 0);

  final int start;
  final int end;

  bool get isCollapsed => start == end;
  int get normalizedStart => math.min(start, end);
  int get normalizedEnd => math.max(start, end);

  TextRange clamp(int textLength) {
    final length = math.max(0, textLength);
    return TextRange(
      start: _clampInt(start, 0, length),
      end: _clampInt(end, 0, length),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TextRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TextRange($start, $end)';
}

/// A directional selection. [baseOffset] is the anchor, [extentOffset] is the
/// moving edge/caret.
final class TextSelection {
  const TextSelection({required this.baseOffset, required this.extentOffset});

  const TextSelection.collapsed(int offset)
    : baseOffset = offset,
      extentOffset = offset;

  final int baseOffset;
  final int extentOffset;

  bool get isCollapsed => baseOffset == extentOffset;
  int get start => math.min(baseOffset, extentOffset);
  int get end => math.max(baseOffset, extentOffset);
  TextRange get range => TextRange(start: start, end: end);

  TextSelection copyWith({int? baseOffset, int? extentOffset}) {
    return TextSelection(
      baseOffset: baseOffset ?? this.baseOffset,
      extentOffset: extentOffset ?? this.extentOffset,
    );
  }

  TextSelection normalizeForText(String text) {
    return TextSelection(
      baseOffset: TextEditingModel.snapOffsetToGraphemeBoundary(
        text,
        baseOffset,
      ),
      extentOffset: TextEditingModel.snapOffsetToGraphemeBoundary(
        text,
        extentOffset,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TextSelection &&
      other.baseOffset == baseOffset &&
      other.extentOffset == extentOffset;

  @override
  int get hashCode => Object.hash(baseOffset, extentOffset);

  @override
  String toString() => isCollapsed
      ? 'TextSelection.collapsed($extentOffset)'
      : 'TextSelection($baseOffset, $extentOffset)';
}

/// Immutable editing value shared by single-line and multiline fields.
final class TextEditingValue {
  TextEditingValue({
    required this.text,
    TextSelection? selection,
    TextRange composing = TextRange.empty,
  }) : selection = (selection ?? TextSelection.collapsed(text.length))
           .normalizeForText(text),
       composing = composing.clamp(text.length);

  factory TextEditingValue.empty() => TextEditingValue(text: '');

  final String text;
  final TextSelection selection;
  final TextRange composing;

  TextEditingValue copyWith({
    String? text,
    TextSelection? selection,
    TextRange? composing,
  }) {
    final nextText = text ?? this.text;
    return TextEditingValue(
      text: nextText,
      selection: selection ?? this.selection,
      composing: composing ?? this.composing,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TextEditingValue &&
      other.text == text &&
      other.selection == selection &&
      other.composing == composing;

  @override
  int get hashCode => Object.hash(text, selection, composing);

  @override
  String toString() => 'TextEditingValue(text: $text, selection: $selection)';
}

/// Pure editing operations over [TextEditingValue].
///
/// Public offsets remain Dart string offsets for compatibility with existing
/// controller APIs, but every operation snaps to extended-grapheme-cluster
/// boundaries before mutating. That keeps emoji, CJK, and combining sequences
/// from being split by cursor movement or deletion.
final class TextEditingModel {
  const TextEditingModel._();

  static String normalizeSingleLineInput(String text) {
    if (!text.contains('\n') && !text.contains('\r')) return text;
    return text
        .replaceAll('\r\n', ' ')
        .replaceAll('\n\r', ' ')
        .replaceAll(RegExp('[\n\r]'), ' ');
  }

  static TextEditingValue insert(
    TextEditingValue value,
    String text, {
    bool singleLine = false,
  }) {
    final input = singleLine ? normalizeSingleLineInput(text) : text;
    if (input.isEmpty && value.selection.isCollapsed) return value;
    return replaceSelection(value, input);
  }

  static TextEditingValue replaceSelection(
    TextEditingValue value,
    String replacement,
  ) {
    return replaceRange(value, value.selection.range, replacement);
  }

  static TextEditingValue replaceRange(
    TextEditingValue value,
    TextRange range,
    String replacement, {
    bool singleLine = false,
  }) {
    final input = singleLine
        ? normalizeSingleLineInput(replacement)
        : replacement;
    final snappedRange = TextRange(
      start: snapOffsetToGraphemeBoundary(value.text, range.start),
      end: snapOffsetToGraphemeBoundary(value.text, range.end),
    ).clamp(value.text.length);
    final nextText = value.text.replaceRange(
      snappedRange.normalizedStart,
      snappedRange.normalizedEnd,
      input,
    );
    final nextOffset = snappedRange.normalizedStart + input.length;
    return TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(nextOffset),
    );
  }

  static TextEditingValue setComposingRange(
    TextEditingValue value,
    TextRange range,
  ) {
    return value.copyWith(
      composing: TextRange(
        start: snapOffsetToGraphemeBoundary(value.text, range.start),
        end: snapOffsetToGraphemeBoundary(value.text, range.end),
      ).clamp(value.text.length),
    );
  }

  static TextEditingValue clearComposing(TextEditingValue value) {
    if (value.composing.isCollapsed) return value;
    return value.copyWith(composing: TextRange.empty);
  }

  /// Replaces the active composing range with [text] and marks the inserted
  /// text as the new composing range.
  ///
  /// When no composing range is active, the current selection is replaced.
  static TextEditingValue updateComposing(
    TextEditingValue value,
    String text, {
    bool singleLine = false,
  }) {
    final input = singleLine ? normalizeSingleLineInput(text) : text;
    final range = value.composing.isCollapsed
        ? value.selection.range
        : value.composing;
    final snappedRange = TextRange(
      start: snapOffsetToGraphemeBoundary(value.text, range.start),
      end: snapOffsetToGraphemeBoundary(value.text, range.end),
    ).clamp(value.text.length);
    final nextText = value.text.replaceRange(
      snappedRange.normalizedStart,
      snappedRange.normalizedEnd,
      input,
    );
    final nextStart = snappedRange.normalizedStart;
    final nextEnd = nextStart + input.length;
    return TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(nextEnd),
      composing: TextRange(start: nextStart, end: nextEnd),
    );
  }

  /// Commits the current composing range.
  ///
  /// If [text] is provided, it replaces the composing range (or selection when
  /// no composing range is active). The returned value always clears
  /// composition.
  static TextEditingValue commitComposing(
    TextEditingValue value, {
    String? text,
    bool singleLine = false,
  }) {
    if (text == null) return clearComposing(value);
    final range = value.composing.isCollapsed
        ? value.selection.range
        : value.composing;
    return replaceRange(value, range, text, singleLine: singleLine);
  }

  static TextEditingValue backspace(TextEditingValue value) {
    if (!value.selection.isCollapsed) {
      return replaceSelection(value, '');
    }
    final offset = value.selection.extentOffset;
    if (offset <= 0) return value;
    final start = previousGraphemeBoundary(value.text, offset);
    return TextEditingValue(
      text: value.text.replaceRange(start, offset, ''),
      selection: TextSelection.collapsed(start),
    );
  }

  static TextEditingValue delete(TextEditingValue value) {
    if (!value.selection.isCollapsed) {
      return replaceSelection(value, '');
    }
    final offset = value.selection.extentOffset;
    if (offset >= value.text.length) return value;
    final end = nextGraphemeBoundary(value.text, offset);
    return TextEditingValue(
      text: value.text.replaceRange(offset, end, ''),
      selection: TextSelection.collapsed(offset),
    );
  }

  static TextEditingValue moveLeft(
    TextEditingValue value, {
    bool extend = false,
  }) {
    final selection = value.selection;
    if (!selection.isCollapsed && !extend) {
      return value.copyWith(
        selection: TextSelection.collapsed(selection.start),
      );
    }
    final next = previousGraphemeBoundary(value.text, selection.extentOffset);
    return value.copyWith(
      selection: extend
          ? selection.copyWith(extentOffset: next).normalizeForText(value.text)
          : TextSelection.collapsed(next),
    );
  }

  static TextEditingValue moveRight(
    TextEditingValue value, {
    bool extend = false,
  }) {
    final selection = value.selection;
    if (!selection.isCollapsed && !extend) {
      return value.copyWith(selection: TextSelection.collapsed(selection.end));
    }
    final next = nextGraphemeBoundary(value.text, selection.extentOffset);
    return value.copyWith(
      selection: extend
          ? selection.copyWith(extentOffset: next).normalizeForText(value.text)
          : TextSelection.collapsed(next),
    );
  }

  static TextEditingValue moveWordLeft(
    TextEditingValue value, {
    bool extend = false,
  }) {
    final next = previousWordBoundary(value.text, value.selection.extentOffset);
    return value.copyWith(
      selection: extend
          ? value.selection
                .copyWith(extentOffset: next)
                .normalizeForText(value.text)
          : TextSelection.collapsed(next),
    );
  }

  static TextEditingValue moveWordRight(
    TextEditingValue value, {
    bool extend = false,
  }) {
    final next = nextWordBoundary(value.text, value.selection.extentOffset);
    return value.copyWith(
      selection: extend
          ? value.selection
                .copyWith(extentOffset: next)
                .normalizeForText(value.text)
          : TextSelection.collapsed(next),
    );
  }

  static TextEditingValue moveToStart(
    TextEditingValue value, {
    bool extend = false,
  }) {
    return value.copyWith(
      selection: extend
          ? value.selection.copyWith(extentOffset: 0)
          : const TextSelection.collapsed(0),
    );
  }

  static TextEditingValue moveToEnd(
    TextEditingValue value, {
    bool extend = false,
  }) {
    return value.copyWith(
      selection: extend
          ? value.selection.copyWith(extentOffset: value.text.length)
          : TextSelection.collapsed(value.text.length),
    );
  }

  static TextEditingValue moveToLineStart(
    TextEditingValue value, {
    bool extend = false,
  }) {
    final next = lineStartOffset(value.text, value.selection.extentOffset);
    return value.copyWith(
      selection: extend
          ? value.selection.copyWith(extentOffset: next)
          : TextSelection.collapsed(next),
    );
  }

  static TextEditingValue moveToLineEnd(
    TextEditingValue value, {
    bool extend = false,
  }) {
    final next = lineEndOffset(value.text, value.selection.extentOffset);
    return value.copyWith(
      selection: extend
          ? value.selection.copyWith(extentOffset: next)
          : TextSelection.collapsed(next),
    );
  }

  static TextEditingValue moveLineUp(
    TextEditingValue value, {
    bool extend = false,
  }) {
    final text = value.text;
    final selection = value.selection.extentOffset;
    final currentStart = lineStartOffset(text, selection);
    if (currentStart == 0) return value;
    final column = graphemeColumn(text, currentStart, selection);
    final previousEnd = currentStart - 1;
    final previousStart = lineStartOffset(text, previousEnd);
    final nextOffset = offsetForGraphemeColumn(
      text,
      previousStart,
      previousEnd,
      column,
    );
    return value.copyWith(
      selection: extend
          ? value.selection.copyWith(extentOffset: nextOffset)
          : TextSelection.collapsed(nextOffset),
    );
  }

  static TextEditingValue moveLineDown(
    TextEditingValue value, {
    bool extend = false,
  }) {
    final text = value.text;
    final selection = value.selection.extentOffset;
    final currentEnd = lineEndOffset(text, selection);
    if (currentEnd == text.length) return value;
    final currentStart = lineStartOffset(text, selection);
    final column = graphemeColumn(text, currentStart, selection);
    final nextStart = currentEnd + 1;
    final nextEnd = lineEndOffset(text, nextStart);
    final nextOffset = offsetForGraphemeColumn(
      text,
      nextStart,
      nextEnd,
      column,
    );
    return value.copyWith(
      selection: extend
          ? value.selection.copyWith(extentOffset: nextOffset)
          : TextSelection.collapsed(nextOffset),
    );
  }

  static int lineStartOffset(String text, int offset) {
    final clamped = snapOffsetToGraphemeBoundary(text, offset);
    if (clamped <= 0) return 0;
    final newline = text.lastIndexOf('\n', clamped - 1);
    return newline == -1 ? 0 : newline + 1;
  }

  static int lineEndOffset(String text, int offset) {
    final clamped = snapOffsetToGraphemeBoundary(text, offset);
    final newline = text.indexOf('\n', clamped);
    return newline == -1 ? text.length : newline;
  }

  static int previousWordBoundary(String text, int offset) {
    var cursor = snapOffsetToGraphemeBoundary(text, offset);
    while (cursor > 0) {
      final previous = previousGraphemeBoundary(text, cursor);
      if (!_isWhitespaceGrapheme(text.substring(previous, cursor))) break;
      cursor = previous;
    }
    while (cursor > 0) {
      final previous = previousGraphemeBoundary(text, cursor);
      if (_isWhitespaceGrapheme(text.substring(previous, cursor))) break;
      cursor = previous;
    }
    return cursor;
  }

  static int nextWordBoundary(String text, int offset) {
    var cursor = snapOffsetToGraphemeBoundary(text, offset);
    while (cursor < text.length) {
      final next = nextGraphemeBoundary(text, cursor);
      if (!_isWhitespaceGrapheme(text.substring(cursor, next))) break;
      cursor = next;
    }
    while (cursor < text.length) {
      final next = nextGraphemeBoundary(text, cursor);
      if (_isWhitespaceGrapheme(text.substring(cursor, next))) break;
      cursor = next;
    }
    return cursor;
  }

  static int graphemeColumn(String text, int lineStart, int offset) {
    final start = _clampInt(lineStart, 0, text.length);
    final end = _clampInt(offset, start, text.length);
    return text.substring(start, end).characters.length;
  }

  static int offsetForGraphemeColumn(
    String text,
    int lineStart,
    int lineEnd,
    int column,
  ) {
    final start = _clampInt(lineStart, 0, text.length);
    final end = _clampInt(lineEnd, start, text.length);
    var offset = start;
    var count = 0;
    for (final grapheme in text.substring(start, end).characters) {
      if (count >= column) break;
      offset += grapheme.length;
      count += 1;
    }
    return offset;
  }

  static int previousGraphemeBoundary(String text, int offset) {
    final clamped = _clampInt(offset, 0, text.length);
    if (clamped == 0) return 0;
    var index = 0;
    for (final grapheme in text.characters) {
      final next = index + grapheme.length;
      if (next >= clamped) return index;
      index = next;
    }
    return 0;
  }

  static int nextGraphemeBoundary(String text, int offset) {
    final clamped = _clampInt(offset, 0, text.length);
    if (clamped == text.length) return text.length;
    var index = 0;
    for (final grapheme in text.characters) {
      final next = index + grapheme.length;
      if (next > clamped) return next;
      index = next;
    }
    return text.length;
  }

  static int snapOffsetToGraphemeBoundary(String text, int offset) {
    final clamped = _clampInt(offset, 0, text.length);
    if (clamped == 0 || clamped == text.length) return clamped;
    var index = 0;
    for (final grapheme in text.characters) {
      final next = index + grapheme.length;
      if (clamped == index || clamped == next) return clamped;
      if (clamped > index && clamped < next) {
        final before = clamped - index;
        final after = next - clamped;
        return before < after ? index : next;
      }
      index = next;
    }
    return text.length;
  }
}

bool _isWhitespaceGrapheme(String grapheme) => grapheme.trim().isEmpty;

int _clampInt(int value, int min, int max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}
