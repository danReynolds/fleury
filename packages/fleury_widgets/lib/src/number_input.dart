import 'package:fleury/fleury.dart';

/// A numeric variant of [TextInput] — accepts digits, an optional
/// leading `-`, and (when [allowDecimal] is true) one `.`. Anything
/// else is silently rejected so the field's text always parses, and
/// [onChanged] fires with the parsed [num] (or `null` for empty /
/// in-progress edits like `"-"` or `"1."`).
///
/// Wraps [TextInput] under the hood — all of its placeholder, focus,
/// cursor, and Enter/Esc semantics carry over. Use this when you'd
/// otherwise pair a [TextInput] with `int.tryParse` everywhere.
///
/// ```dart
/// NumberInput(
///   initialValue: 42,
///   min: 0,
///   max: 100,
///   onChanged: (v) => setState(() => count = v),
/// )
/// ```
class NumberInput extends StatefulWidget {
  const NumberInput({
    super.key,
    this.initialValue,
    this.onChanged,
    this.onSubmit,
    this.min,
    this.max,
    this.allowNegative = true,
    this.allowDecimal = false,
    this.placeholder = '',
    this.placeholderStyle = const CellStyle(dim: true),
    this.style = CellStyle.empty,
    this.cursorStyle = const CellStyle(inverse: true),
    this.focusNode,
    this.autofocus = false,
  });

  /// Initial parsed value to seed the field with. `null` starts empty.
  final num? initialValue;

  /// Called with the parsed value on every change. `null` is passed
  /// when the field is empty or holds an in-progress token like `"-"`
  /// or `"1."` that doesn't yet parse to a [num].
  final void Function(num? value)? onChanged;

  /// Called with the final parsed value when the user presses Enter.
  /// Same `null` semantics as [onChanged].
  final void Function(num? value)? onSubmit;

  /// Clamps the parsed value (after the user finishes editing) to this
  /// lower bound. Per-keystroke values *below* the bound are still
  /// accepted while the user is typing — the clamp applies on submit.
  /// Set to enforce a non-negative budget, percentage, etc.
  final num? min;

  /// Upper-bound mirror of [min].
  final num? max;

  /// When false, the field rejects `-` entirely.
  final bool allowNegative;

  /// When true, the field accepts one `.` for decimal entry. When false,
  /// only integer digits are accepted.
  final bool allowDecimal;

  /// Forwarded to the inner [TextInput] verbatim.
  final String placeholder;
  final CellStyle placeholderStyle;
  final CellStyle style;
  final CellStyle cursorStyle;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<NumberInput> createState() => _NumberInputState();
}

class _NumberInputState extends State<NumberInput> {
  late TextEditingController _controller;
  String _lastAccepted = '';
  // Suppresses the listener when we programmatically revert the
  // controller — otherwise the revert would fire onChanged a second
  // time with the previous value, looking like a phantom edit.
  bool _suppress = false;

  @override
  void initState() {
    super.initState();
    _lastAccepted = widget.initialValue == null
        ? ''
        : _stringify(widget.initialValue!);
    _controller = TextEditingController(text: _lastAccepted);
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  String _stringify(num v) {
    if (widget.allowDecimal) return v.toString();
    return v.toInt().toString();
  }

  bool _isValid(String s) {
    if (s.isEmpty) return true;
    var i = 0;
    if (s[0] == '-') {
      if (!widget.allowNegative) return false;
      i = 1;
      if (s.length == 1) return true; // "-" alone is a valid in-progress token
    }
    var sawDot = false;
    for (; i < s.length; i++) {
      final c = s[i];
      if (c == '.') {
        if (!widget.allowDecimal || sawDot) return false;
        sawDot = true;
        continue;
      }
      if (c.codeUnitAt(0) < 0x30 || c.codeUnitAt(0) > 0x39) return false;
    }
    return true;
  }

  num? _parse(String s) {
    if (s.isEmpty || s == '-' || s == '.' || s == '-.') return null;
    if (s.endsWith('.')) return null; // "1." — in-progress, not yet a number
    return widget.allowDecimal ? num.tryParse(s) : int.tryParse(s);
  }

  void _onChanged() {
    if (_suppress) return;
    final text = _controller.text;
    if (!_isValid(text)) {
      // Revert to the last accepted value without firing onChanged.
      // The cursor jumps to the end on revert — same UX as a paste of
      // an invalid value being rejected.
      _suppress = true;
      _controller
        ..text = _lastAccepted
        ..selection = _lastAccepted.length;
      _suppress = false;
      return;
    }
    _lastAccepted = text;
    widget.onChanged?.call(_parse(text));
  }

  num? _clampedSubmit(num? v) {
    if (v == null) return null;
    if (widget.min != null && v < widget.min!) return widget.min!;
    if (widget.max != null && v > widget.max!) return widget.max!;
    return v;
  }

  @override
  Widget build(BuildContext context) {
    return TextInput(
      controller: _controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      placeholder: widget.placeholder,
      placeholderStyle: widget.placeholderStyle,
      style: widget.style,
      cursorStyle: widget.cursorStyle,
      onSubmit: (text) {
        final parsed = _parse(text);
        final clamped = _clampedSubmit(parsed);
        // If clamping changed the value, update the field to reflect it.
        if (clamped != null && clamped != parsed) {
          final s = _stringify(clamped);
          _lastAccepted = s;
          _suppress = true;
          _controller
            ..text = s
            ..selection = s.length;
          _suppress = false;
        }
        widget.onSubmit?.call(clamped);
      },
    );
  }
}
