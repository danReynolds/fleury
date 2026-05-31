// TextInput: a single-line editable text widget for terminal apps.
//
// Composed of three pieces:
//   - TextEditingController — a ChangeNotifier holding the current
//     text and the cursor's code-unit index.
//   - TextInput — the widget. Creates a Focus node tagged as a
//     TextInputClaimant, so the InputDispatcher routes
//     TextInputEvents (typed printable text) directly to it. Handles
//     special chords (Backspace, arrows, Enter, etc.) via Focus.onKey.
//   - RenderTextInput — paints the text plus a one-cell inverse
//     cursor at the current selection position.
//
// What's intentionally not here yet:
//   - Multi-line text (Enter inserts a newline + wraps); v0 is
//     single-line and Enter calls onSubmit.
//   - Grapheme-cluster-aware cursor movement. v0 uses code-unit
//     indices, which works for ASCII / BMP characters but can split
//     emoji surrogate pairs. Documented; promoted to grapheme-
//     indexed editing in a polish slice.
//   - Horizontal scrolling for text longer than the available width.
//     v0 clips at the right edge; the cursor disappears off-screen.
//   - Selection ranges (only a single cursor index).

import 'package:characters/characters.dart';

import '../animation/animation_policy.dart';
import '../animation/frame_ticker.dart';
import '../foundation/change_notifier.dart';
import '../foundation/geometry.dart';
import '../rendering/cell.dart';
import '../rendering/cell_buffer.dart';
import '../rendering/layout.dart';
import '../rendering/render_object.dart';
import '../rendering/text_sanitizer.dart';
import '../rendering/width_resolver.dart';
import '../terminal/events.dart';
import 'focus.dart';
import 'framework.dart';
import 'tui_binding.dart';

/// Mutable model for a [TextInput]: the current text and cursor
/// position.
///
/// `selection` is a **code-unit index** into [text] (0 = before
/// the first code unit, `text.length` = after the last). For ASCII
/// and BMP characters this is the same as grapheme-cluster
/// indexing; emoji and other supplementary-plane characters can
/// theoretically be split with the v0 API.
class TextEditingController extends ChangeNotifier {
  TextEditingController({String text = ''})
    : _text = text,
      _selection = text.length;

  String _text;
  int _selection;

  String get text => _text;
  set text(String value) {
    if (_text == value) return;
    _text = value;
    _selection = _selection.clamp(0, value.length);
    notifyListeners();
  }

  /// Cursor index in code units. Always in `0..text.length`.
  int get selection => _selection;
  set selection(int value) {
    final clamped = value.clamp(0, _text.length);
    if (_selection == clamped) return;
    _selection = clamped;
    notifyListeners();
  }

  void clear() {
    if (_text.isEmpty && _selection == 0) return;
    _text = '';
    _selection = 0;
    notifyListeners();
  }

  /// Inserts [s] at the current cursor and advances the cursor past
  /// the inserted text. No-op if [s] is empty.
  void insert(String s) {
    if (s.isEmpty) return;
    _text = _text.substring(0, _selection) + s + _text.substring(_selection);
    _selection += s.length;
    notifyListeners();
  }

  /// Deletes the character before the cursor and moves the cursor
  /// left. No-op when the cursor is at the start.
  void backspace() {
    if (_selection == 0) return;
    _text = _text.substring(0, _selection - 1) + _text.substring(_selection);
    _selection -= 1;
    notifyListeners();
  }

  /// Deletes the character at the cursor (the one to its right).
  /// No-op when the cursor is at the end.
  void delete() {
    if (_selection >= _text.length) return;
    _text = _text.substring(0, _selection) + _text.substring(_selection + 1);
    notifyListeners();
  }

  void moveCursorLeft() {
    if (_selection == 0) return;
    _selection -= 1;
    notifyListeners();
  }

  void moveCursorRight() {
    if (_selection >= _text.length) return;
    _selection += 1;
    notifyListeners();
  }

  void moveCursorToStart() {
    if (_selection == 0) return;
    _selection = 0;
    notifyListeners();
  }

  void moveCursorToEnd() {
    if (_selection == _text.length) return;
    _selection = _text.length;
    notifyListeners();
  }
}

/// A single-line editable text widget.
///
/// The widget claims insertable input (printable ASCII / Unicode,
/// arriving as [TextInputEvent]s from the parser) via
/// [TextInputClaimant], so an ancestor `KeyBindings` doesn't see
/// typed characters that should go into the text. Modifier chords
/// like `Ctrl+S` arrive as [KeyEvent]s and still bubble normally.
///
/// Special chords handled directly:
///   - Backspace, Delete, Arrow Left / Right, Home, End — edit the
///     controller's selection / text.
///   - Enter — fires [onSubmit] with the current text. Up to the
///     caller to clear the controller or keep the typed value.
///   - Escape — fires [onEscape], or bubbles if [onEscape] is null.
///   - Tab and other unhandled special chords — bubble.
class TextInput extends StatefulWidget {
  const TextInput({
    super.key,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.onSubmit,
    this.onEscape,
    this.placeholder = '',
    this.placeholderStyle = const CellStyle(dim: true),
    this.style = CellStyle.empty,
    this.cursorStyle = const CellStyle(inverse: true),
    this.blinkInterval = const Duration(milliseconds: 500),
    this.enableBlink = true,
    this.obscureText = false,
    this.obscuringCharacter = '•',
  });

  /// External controller for the text. If null, the widget creates
  /// its own and disposes it on unmount.
  final TextEditingController? controller;

  /// External [FocusNode]. Provide one when a parent needs to drive
  /// focus (e.g. Tab cycling between panes). If null, the widget
  /// creates its own and disposes it on unmount.
  final FocusNode? focusNode;

  /// Whether to request focus on first mount.
  final bool autofocus;

  /// Called with the current text when the user presses Enter.
  final void Function(String text)? onSubmit;

  /// Called when the user presses Escape. If null, Escape bubbles
  /// up the focus chain normally.
  final void Function()? onEscape;

  /// Hint text shown when the field is empty. Cleared as soon as the
  /// user types.
  final String placeholder;

  /// Style for the [placeholder] text. Defaults to dim.
  final CellStyle placeholderStyle;

  /// Base style for the rendered text.
  final CellStyle style;

  /// Style merged on top of [style] at the cursor cell. Defaults to
  /// `inverse: true` — a block cursor.
  final CellStyle cursorStyle;

  /// On/off cadence for the blinking cursor. Default matches
  /// native terminal conventions (~500 ms).
  final Duration blinkInterval;

  /// When true (default), the cursor blinks while the widget is
  /// focused. When false, the cursor is rendered solid whenever
  /// the widget is focused. The cursor is always suppressed when
  /// the widget is unfocused.
  final bool enableBlink;

  /// When true, each grapheme of the field's text is replaced with
  /// [obscuringCharacter] at paint time. The controller still holds
  /// the real text — only the displayed glyphs are masked. Use for
  /// password / secret entry.
  final bool obscureText;

  /// The glyph used to replace each character when [obscureText] is
  /// true. Defaults to `•`.
  final String obscuringCharacter;

  @override
  State<TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<TextInput> implements TextInputClaimant {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;

  /// Blink ticker — lazily created in [didChangeDependencies]
  /// because we need a `TuiBinding` to source the scheduler, which
  /// requires a `BuildContext` that's done its first dependency
  /// pass. Started/stopped from [_syncBlinkToFocus] as focus
  /// changes.
  FrameTicker? _blinkTicker;

  /// Latest "on" phase of the blink. Toggled on each ticker frame.
  /// `true` means the cursor cell renders with [cursorStyle]; false
  /// means it renders as normal text (or empty, if the cursor is
  /// past the last character).
  bool _blinkOn = true;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChange);
    // Note: don't set _focusNode.onKey here — the Focus widget's
    // State.initState assigns onKey from `widget.onKey`, overwriting
    // anything we set. We pass `_handleKey` to the Focus widget
    // below instead. We do set `textInputClaimant` since the Focus
    // widget never touches it.
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'TextInput');
    _focusNode.textInputClaimant = this;
    _ownsFocusNode = widget.focusNode == null;
  }

  @override
  void didUpdateWidget(TextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller.removeListener(_onControllerChange);
      if (_ownsController) _controller.dispose();
      _controller = widget.controller ?? TextEditingController();
      _ownsController = widget.controller == null;
      _controller.addListener(_onControllerChange);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      // Stop claiming text on the old node before letting it go.
      _focusNode.textInputClaimant = null;
      if (_ownsFocusNode) _focusNode.dispose();
      _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'TextInput');
      _focusNode.textInputClaimant = this;
      _ownsFocusNode = widget.focusNode == null;
    }
    if (widget.blinkInterval != oldWidget.blinkInterval ||
        widget.enableBlink != oldWidget.enableBlink) {
      _disposeBlinkTicker();
      // Recreate next didChangeDependencies / build pass.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Rebuild on focus change so cursor visibility flips.
    // dependOnInheritedWidgetOfExactType subscribes us to the
    // FocusManagerScope.
    Focus.maybeOf(context);
    _syncBlinkToFocus();
  }

  void _syncBlinkToFocus() {
    if (!widget.enableBlink) {
      _disposeBlinkTicker();
      _blinkOn = true; // solid cursor when blink disabled
      return;
    }
    if (!_focusNode.hasFocus) {
      _disposeBlinkTicker();
      _blinkOn = true; // resting state when unfocused
      return;
    }
    // Focused + blink enabled. Ensure ticker; mute under
    // AnimationPolicy.disabled (cursor stays solid; ticker
    // remains registered so we don't repeatedly create/destroy
    // it if the policy toggles).
    _ensureBlinkTicker();
    final policy =
        TuiBinding.maybeOf(context)?.animationPolicy ?? AnimationPolicy.enabled;
    if (policy == AnimationPolicy.disabled) {
      _blinkTicker?.muted = true;
      _blinkOn = true;
    } else {
      _blinkTicker?.muted = false;
    }
  }

  void _ensureBlinkTicker() {
    if (_blinkTicker != null) return;
    final binding = TuiBinding.maybeOf(context);
    if (binding == null) return; // no binding: no blink (tests, etc.)
    _blinkTicker =
        FrameTicker(
            interval: widget.blinkInterval,
            scheduler: binding.tickerScheduler,
          )
          ..addListener(_onBlink)
          ..start();
  }

  void _disposeBlinkTicker() {
    final t = _blinkTicker;
    if (t == null) return;
    t.removeListener(_onBlink);
    t.dispose();
    _blinkTicker = null;
  }

  void _onBlink() {
    if (!mounted) return;
    setState(() {
      _blinkOn = !_blinkOn;
    });
  }

  void _onControllerChange() {
    setState(() {
      // Typing resets the blink to ON so the cursor is immediately
      // visible after a keystroke — matches native terminal cursor
      // behavior. Without this, a cursor in its OFF phase would
      // briefly stay invisible during typing, which feels broken.
      _blinkOn = true;
    });
  }

  KeyEventResult _handleKey(KeyEvent event) {
    final code = event.keyCode;
    if (code == null) return KeyEventResult.ignored;
    switch (code) {
      case KeyCode.backspace:
        _controller.backspace();
        return KeyEventResult.handled;
      case KeyCode.delete:
        _controller.delete();
        return KeyEventResult.handled;
      case KeyCode.arrowLeft:
        _controller.moveCursorLeft();
        return KeyEventResult.handled;
      case KeyCode.arrowRight:
        _controller.moveCursorRight();
        return KeyEventResult.handled;
      case KeyCode.home:
        _controller.moveCursorToStart();
        return KeyEventResult.handled;
      case KeyCode.end:
        _controller.moveCursorToEnd();
        return KeyEventResult.handled;
      case KeyCode.enter:
        widget.onSubmit?.call(_controller.text);
        return KeyEventResult.handled;
      case KeyCode.escape:
        if (widget.onEscape != null) {
          widget.onEscape!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  KeyEventResult onTextInput(String text) {
    // Single-line field: a pasted blob may carry newlines — collapse them
    // to spaces so the value stays on one line (typed input never has any).
    final flat = text.contains('\n') || text.contains('\r')
        ? text.replaceAll('\r\n', ' ').replaceAll(RegExp('[\n\r]'), ' ')
        : text;
    _controller.insert(flat);
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _disposeBlinkTicker();
    _controller.removeListener(_onControllerChange);
    if (_ownsController) _controller.dispose();
    _focusNode.textInputClaimant = null;
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Compute cursor visibility from focus + blink state. The
    // ticker (lazily started in didChangeDependencies) toggles
    // _blinkOn; when unfocused we suppress the cursor entirely.
    final focused = _focusNode.hasFocus;
    final cursorVisible = focused && (!widget.enableBlink || _blinkOn);
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKey: _handleKey,
      child: _TextInputDisplay(
        text: _controller.text,
        selection: _controller.selection,
        placeholder: widget.placeholder,
        placeholderStyle: widget.placeholderStyle,
        style: widget.style,
        cursorStyle: widget.cursorStyle,
        cursorVisible: cursorVisible,
        obscureText: widget.obscureText,
        obscuringCharacter: widget.obscuringCharacter,
      ),
    );
  }
}

class _TextInputDisplay extends LeafRenderObjectWidget {
  const _TextInputDisplay({
    required this.text,
    required this.selection,
    required this.placeholder,
    required this.placeholderStyle,
    required this.style,
    required this.cursorStyle,
    required this.cursorVisible,
    required this.obscureText,
    required this.obscuringCharacter,
  });

  final String text;
  final int selection;
  final String placeholder;
  final CellStyle placeholderStyle;
  final CellStyle style;
  final CellStyle cursorStyle;
  final bool cursorVisible;
  final bool obscureText;
  final String obscuringCharacter;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderTextInput(
      text: text,
      selection: selection,
      placeholder: placeholder,
      placeholderStyle: placeholderStyle,
      style: style,
      cursorStyle: cursorStyle,
      cursorVisible: cursorVisible,
      obscureText: obscureText,
      obscuringCharacter: obscuringCharacter,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderTextInput renderObject,
  ) {
    renderObject
      ..text = text
      ..selection = selection
      ..placeholder = placeholder
      ..placeholderStyle = placeholderStyle
      ..style = style
      ..cursorStyle = cursorStyle
      ..cursorVisible = cursorVisible
      ..obscureText = obscureText
      ..obscuringCharacter = obscuringCharacter;
  }
}

/// Paints the [text] of a [TextInput] with a one-cell inverse cursor
/// at the current [selection] code-unit index.
///
/// Layout: width = text intrinsic width (in cells) + 1 for the
/// trailing cursor position, clipped to constraints. Height = 1.
class RenderTextInput extends RenderObject {
  RenderTextInput({
    required String text,
    required int selection,
    String placeholder = '',
    CellStyle placeholderStyle = const CellStyle(dim: true),
    CellStyle style = CellStyle.empty,
    CellStyle cursorStyle = const CellStyle(inverse: true),
    bool cursorVisible = true,
    bool obscureText = false,
    String obscuringCharacter = '•',
    WidthResolver widthResolver = const DefaultWidthResolver(),
    TerminalProfile profile = TerminalProfile.standard,
  }) : _text = sanitizeForDisplay(text),
       _selection = selection.clamp(0, text.length),
       _placeholder = sanitizeForDisplay(placeholder),
       _placeholderStyle = placeholderStyle,
       _style = style,
       _cursorStyle = cursorStyle,
       _cursorVisible = cursorVisible,
       _obscureText = obscureText,
       _obscuringCharacter = obscuringCharacter,
       _widthResolver = widthResolver,
       _profile = profile;

  String _text;
  int _selection;
  String _placeholder;
  CellStyle _placeholderStyle;
  CellStyle _style;
  CellStyle _cursorStyle;
  bool _cursorVisible;
  bool _obscureText;
  String _obscuringCharacter;
  final WidthResolver _widthResolver;
  final TerminalProfile _profile;

  set text(String value) {
    final sanitized = sanitizeForDisplay(value);
    if (sanitized == _text) return;
    _text = sanitized;
    _selection = _selection.clamp(0, _text.length);
  }

  set placeholder(String value) {
    final sanitized = sanitizeForDisplay(value);
    if (sanitized == _placeholder) return;
    _placeholder = sanitized;
  }

  set placeholderStyle(CellStyle value) {
    if (_placeholderStyle == value) return;
    _placeholderStyle = value;
  }

  set selection(int value) {
    final clamped = value.clamp(0, _text.length);
    if (_selection == clamped) return;
    _selection = clamped;
  }

  set style(CellStyle value) {
    if (_style == value) return;
    _style = value;
  }

  set cursorStyle(CellStyle value) {
    if (_cursorStyle == value) return;
    _cursorStyle = value;
  }

  /// When false, the cursor cell renders with the regular [style]
  /// rather than [cursorStyle.merge(style)]. Used to implement
  /// cursor blink (toggle this off/on every ~500 ms) and to
  /// suppress the cursor when the input is unfocused.
  set cursorVisible(bool value) {
    if (_cursorVisible == value) return;
    _cursorVisible = value;
  }

  set obscureText(bool value) {
    if (_obscureText == value) return;
    _obscureText = value;
  }

  set obscuringCharacter(String value) {
    if (_obscuringCharacter == value) return;
    _obscuringCharacter = value;
  }

  @override
  CellSize performLayout(CellConstraints constraints) {
    final int intrinsic;
    if (_text.isEmpty && _placeholder.isNotEmpty) {
      intrinsic = _widthResolver.widthOfText(_placeholder, _profile);
    } else if (_obscureText) {
      // When obscured, the displayed width is N × width(obscureChar).
      // The grapheme count drives the visible cell count.
      final n = _text.characters.length;
      final w = _widthResolver.widthOfGrapheme(_obscuringCharacter, _profile);
      intrinsic = n * w + 1;
    } else {
      intrinsic = _widthResolver.widthOfText(_text, _profile) + 1;
    }
    final maxCols = constraints.maxCols;
    final cols = maxCols == null ? intrinsic : intrinsic.clamp(0, maxCols);
    return constraints.constrain(CellSize(cols, 1));
  }

  @override
  void paint(
    CellBuffer buffer,
    CellOffset offset, {
    CellOffset? screenOffset,
    CellRect? clipRect,
  }) {
    if (size.isEmpty) return;
    final row = offset.row;
    var col = offset.col;
    final maxCol = offset.col + size.cols;

    // Empty field: paint the placeholder (with the cursor over its first
    // cell when visible) instead of the text + trailing cursor.
    if (_text.isEmpty && _placeholder.isNotEmpty) {
      var first = true;
      for (final grapheme in _placeholder.characters) {
        if (col >= maxCol) break;
        final style = (first && _cursorVisible)
            ? _placeholderStyle.merge(_cursorStyle)
            : _placeholderStyle;
        buffer.writeGrapheme(
          CellOffset(col, row),
          grapheme,
          style: style,
          widthResolver: _widthResolver,
          profile: _profile,
        );
        col += _widthResolver.widthOfGrapheme(grapheme, _profile);
        first = false;
      }
      return;
    }

    var codeUnitOffset = 0;
    var paintedCursor = false;

    for (final grapheme in _text.characters) {
      if (col >= maxCol) break;
      final atCursor = codeUnitOffset == _selection;
      // Only apply cursorStyle when the cursor is currently visible
      // (focused + blink-on). When invisible, the cursor cell
      // renders with the base style so the character underneath
      // (or a blank if past EOL) reads normally.
      final cellStyle = (atCursor && _cursorVisible)
          ? _style.merge(_cursorStyle)
          : _style;
      // Mask the displayed glyph when obscureText is on. The real text
      // (and the cursor's code-unit position) is unchanged — only the
      // pixel rendering is replaced.
      final displayed = _obscureText ? _obscuringCharacter : grapheme;
      buffer.writeGrapheme(
        CellOffset(col, row),
        displayed,
        style: cellStyle,
        widthResolver: _widthResolver,
        profile: _profile,
      );
      col += _widthResolver.widthOfGrapheme(displayed, _profile);
      codeUnitOffset += grapheme.length;
      if (atCursor) paintedCursor = true;
    }

    // Cursor past the last character.
    if (!paintedCursor && col < maxCol) {
      if (_cursorVisible) {
        buffer.writeGrapheme(
          CellOffset(col, row),
          ' ',
          style: _style.merge(_cursorStyle),
        );
      }
      // When the cursor is invisible past-EOL, we deliberately
      // leave the cell empty — same as the rest of the trailing
      // space.
    }
  }
}
