import '../foundation/geometry.dart';
import '../widgets/pointer.dart';
import 'text_editing.dart';

/// Shared mouse-selection state for single- and multi-line editors. Rendering
/// supplies the UTF-16 offset, so this never guesses at glyph widths or scrolling.
class TextPointerSelection {
  final Stopwatch _clock = Stopwatch()..start();
  Duration? _lastDown;
  CellOffset? _lastPosition;
  int _clicks = 0;
  TextSelection? _anchor;

  TextSelection down(
    TextEditingValue value,
    int offset,
    PointerDetails details, {
    bool obscured = false,
  }) {
    final now = _clock.elapsed;
    final last = _lastDown;
    final close = _lastPosition == details.globalPosition;
    _clicks =
        last != null &&
            now - last < const Duration(milliseconds: 500) &&
            close &&
            !details.hasShift
        ? (_clicks % 3) + 1
        : 1;
    _lastDown = now;
    _lastPosition = details.globalPosition;
    final selection = details.hasShift
        ? TextSelection(
            baseOffset: value.selection.baseOffset,
            extentOffset: offset,
          )
        : _range(value.text, offset, obscured: obscured);
    _anchor = selection;
    return selection;
  }

  TextSelection? drag(
    TextEditingValue value,
    int offset, {
    bool obscured = false,
  }) {
    final anchor = _anchor;
    if (anchor == null) return null;
    final next = _range(value.text, offset, obscured: obscured);
    if (_clicks == 1) {
      return TextSelection(baseOffset: anchor.baseOffset, extentOffset: offset);
    }
    return offset < anchor.start
        ? TextSelection(baseOffset: anchor.end, extentOffset: next.start)
        : TextSelection(baseOffset: anchor.start, extentOffset: next.end);
  }

  void end() => _anchor = null;

  TextSelection _range(String text, int offset, {required bool obscured}) {
    if (_clicks == 1) return TextSelection.collapsed(offset: offset);
    // A password's word boundaries must not disclose its hidden structure.
    if (obscured) {
      return TextSelection(baseOffset: 0, extentOffset: text.length);
    }
    if (_clicks == 3) {
      final start = TextEditingModel.lineStartOffset(text, offset);
      final end = TextEditingModel.lineEndOffset(text, offset);
      return TextSelection(
        baseOffset: start,
        extentOffset: end < text.length ? end + 1 : end,
      );
    }
    if (text.isEmpty) return const TextSelection.collapsed(offset: 0);
    var start = offset == text.length
        ? TextEditingModel.previousGraphemeBoundary(text, offset)
        : offset;
    var end = TextEditingModel.nextGraphemeBoundary(text, start);
    final whitespace = text.substring(start, end).trim().isEmpty;
    while (start > 0) {
      final previous = TextEditingModel.previousGraphemeBoundary(text, start);
      if (text.substring(previous, start).trim().isEmpty != whitespace) break;
      start = previous;
    }
    while (end < text.length) {
      final next = TextEditingModel.nextGraphemeBoundary(text, end);
      if (text.substring(end, next).trim().isEmpty != whitespace) break;
      end = next;
    }
    return TextSelection(baseOffset: start, extentOffset: end);
  }
}
