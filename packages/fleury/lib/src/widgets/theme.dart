import '../foundation/key.dart';
import '../rendering/border.dart';
import '../rendering/cell.dart';
import 'framework.dart';

/// Whether a theme is tuned for a dark or light terminal background. A
/// hint apps and [ThemeExtension]s can branch on; the framework does not
/// auto-detect the terminal background (that probe is unreliable).
enum Brightness { dark, light }

/// A small set of semantic color roles an app draws from. Deliberately
/// lean (unlike Material's couple-dozen roles): the handful a terminal UI
/// actually reaches for. [foreground]/[background] default to null, which
/// means "use the terminal's own default" — the right baseline for a TUI,
/// since the user's color scheme should show through unless overridden.
final class ColorScheme {
  const ColorScheme({
    this.foreground,
    this.background,
    this.surface,
    this.primary = Colors.mint,
    this.success = const AnsiColor(2),
    this.warning = const AnsiColor(3),
    this.error = const AnsiColor(1),
    this.info = const AnsiColor(6),
  });

  /// Default text/background — null means the terminal's own.
  final Color? foreground;
  final Color? background;

  /// Opaque fill for raised surfaces and modal content — a [Surface] widget,
  /// or content shown via [NavigatorState.present]. Unlike [background]
  /// (nullable = the terminal's own, i.e. effectively transparent), a surface
  /// must fully cover the cells it occupies so nothing painted beneath shows
  /// through. null derives a concrete fill from the theme brightness
  /// (near-black on dark terminals, near-white on light).
  final Color? surface;

  /// Accent for interactive/active affordances.
  final Color primary;

  /// Status roles.
  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  /// The default scheme: terminal-default fg/bg, ANSI status roles, and a
  /// cool spring-green [primary] ([Colors.mint]) — the one truecolor role,
  /// which downsamples cleanly on 256/16-color terminals.
  static const ColorScheme standard = ColorScheme();

  /// Builds a scheme from a single accent [seed]. Unlike Material's
  /// `fromSeed`, the seed is preserved verbatim as [primary] (no tonal
  /// remap that surprises you) — derive shades predictably with
  /// `seed.toRgb().lighten()` / `.darken()`. Status colors stay standard
  /// so "error" always reads as red, etc.
  factory ColorScheme.fromSeed(Color seed) => ColorScheme(primary: seed);

  ColorScheme copyWith({
    Color? foreground,
    Color? background,
    Color? surface,
    Color? primary,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
  }) => ColorScheme(
    foreground: foreground ?? this.foreground,
    background: background ?? this.background,
    surface: surface ?? this.surface,
    primary: primary ?? this.primary,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    error: error ?? this.error,
    info: info ?? this.info,
  );

  @override
  bool operator ==(Object other) =>
      other is ColorScheme &&
      other.foreground == foreground &&
      other.background == background &&
      other.surface == surface &&
      other.primary == primary &&
      other.success == success &&
      other.warning == warning &&
      other.error == error &&
      other.info == info;

  @override
  int get hashCode => Object.hash(
    foreground,
    background,
    surface,
    primary,
    success,
    warning,
    error,
    info,
  );
}

/// The themeable defaults shared down the tree via [Theme]. Widgets read
/// these as the *fallback* for their style parameters: a `null` style
/// arg resolves to the matching theme role, and an explicit arg always
/// wins. The default [ThemeData] reproduces the framework's built-in
/// looks, so wrapping (or not wrapping) a subtree in a [Theme] changes
/// nothing until you actually customize a field.
final class ThemeData {
  const ThemeData({
    this.brightness = Brightness.dark,
    this.textStyle = CellStyle.empty,
    this.mutedStyle = const CellStyle(dim: true),
    this.selectionStyle = const CellStyle(inverse: true),
    this.focusedStyle = const CellStyle(bold: true),
    this.borderStyle = BorderStyle.rounded,
    this.colorScheme = ColorScheme.standard,
    this.extensions = const [],
  });

  /// A preset accent tuned for dark terminals (the common case).
  factory ThemeData.dark({List<Object> extensions = const []}) => ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(const RgbColor(0x61, 0xAF, 0xEF)),
    extensions: extensions,
  );

  /// A preset accent tuned for light terminals.
  factory ThemeData.light({List<Object> extensions = const []}) => ThemeData(
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(const RgbColor(0x00, 0x5F, 0xAF)),
    extensions: extensions,
  );

  /// Dark or light tuning — a hint for app/extension color choices.
  final Brightness brightness;

  /// Typed, app-defined theme extensions. Unlike Flutter's
  /// `ThemeExtension`, an extension here is any plain object — no
  /// mandatory `copyWith`/`lerp`/`==` boilerplate. Retrieve one by type
  /// with [extension]; the first assignable entry wins.
  final List<Object> extensions;

  /// Base style cascaded onto [Text] via [DefaultTextStyle] at the root.
  final CellStyle textStyle;

  /// De-emphasized text (separators, hints, disabled rows).
  final CellStyle mutedStyle;

  /// Highlight for the selected/active row or item.
  final CellStyle selectionStyle;

  /// Cue for a focused control.
  final CellStyle focusedStyle;

  /// Default box-drawing style for framed surfaces.
  final BorderStyle borderStyle;

  /// Semantic colors.
  final ColorScheme colorScheme;

  /// Returned by [Theme.of] when no [Theme] is in scope. Matches the
  /// framework's built-in widget looks.
  static const ThemeData fallback = ThemeData();

  /// The registered extension assignable to [T], or null. O(n) over a
  /// handful of extensions.
  T? extension<T extends Object>() {
    for (final e in extensions) {
      if (e is T) return e;
    }
    return null;
  }

  ThemeData copyWith({
    Brightness? brightness,
    CellStyle? textStyle,
    CellStyle? mutedStyle,
    CellStyle? selectionStyle,
    CellStyle? focusedStyle,
    BorderStyle? borderStyle,
    ColorScheme? colorScheme,
    List<Object>? extensions,
  }) => ThemeData(
    brightness: brightness ?? this.brightness,
    textStyle: textStyle ?? this.textStyle,
    mutedStyle: mutedStyle ?? this.mutedStyle,
    selectionStyle: selectionStyle ?? this.selectionStyle,
    focusedStyle: focusedStyle ?? this.focusedStyle,
    borderStyle: borderStyle ?? this.borderStyle,
    colorScheme: colorScheme ?? this.colorScheme,
    extensions: extensions ?? this.extensions,
  );

  @override
  bool operator ==(Object other) =>
      other is ThemeData &&
      other.brightness == brightness &&
      other.textStyle == textStyle &&
      other.mutedStyle == mutedStyle &&
      other.selectionStyle == selectionStyle &&
      other.focusedStyle == focusedStyle &&
      other.borderStyle == borderStyle &&
      other.colorScheme == colorScheme &&
      _listEquals(other.extensions, extensions);

  @override
  int get hashCode => Object.hash(
    brightness,
    textStyle,
    mutedStyle,
    selectionStyle,
    focusedStyle,
    borderStyle,
    colorScheme,
    Object.hashAll(extensions),
  );
}

bool _listEquals(List<Object> a, List<Object> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Shares a [ThemeData] with its subtree. Read it with `Theme.of(context)`
/// (which falls back to [ThemeData.fallback] when absent, so widgets can
/// always resolve a theme without a required ancestor).
///
/// Wrapping a subtree in a [Theme] also cascades [ThemeData.textStyle] as
/// the [DefaultTextStyle], so a base text color/dim can be set app-wide in
/// one place.
class Theme extends StatelessWidget {
  const Theme({super.key, required this.data, required this.child});

  final ThemeData data;
  final Widget child;

  static ThemeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ThemeScope>()?.data ??
      ThemeData.fallback;

  static ThemeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ThemeScope>()?.data;

  @override
  Widget build(BuildContext context) => _ThemeScope(
    data: data,
    child: DefaultTextStyle(style: data.textStyle, child: child),
  );
}

class _ThemeScope extends InheritedWidget {
  const _ThemeScope({required this.data, required super.child});

  final ThemeData data;

  @override
  bool updateShouldNotify(_ThemeScope oldWidget) => data != oldWidget.data;
}

/// Cascades a base [CellStyle] onto descendant [Text] widgets, which merge
/// their own style on top. Nest it to restyle a subtree (e.g. dim a whole
/// panel) without touching each `Text`.
class DefaultTextStyle extends InheritedWidget {
  const DefaultTextStyle({
    super.key,
    required this.style,
    required super.child,
  });

  final CellStyle style;

  /// The cascaded style in scope, or [CellStyle.empty] when none.
  static CellStyle of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DefaultTextStyle>()?.style ??
      CellStyle.empty;

  /// Layers [style] *on top of* the ambient default for [child], rather
  /// than replacing it — so an inner scope can add a color without
  /// dropping an outer bold. (Plain [DefaultTextStyle] replaces.)
  static Widget merge({
    Key? key,
    required CellStyle style,
    required Widget child,
  }) => _MergeDefaultTextStyle(key: key, style: style, child: child);

  @override
  bool updateShouldNotify(DefaultTextStyle oldWidget) =>
      style != oldWidget.style;
}

class _MergeDefaultTextStyle extends StatelessWidget {
  const _MergeDefaultTextStyle({
    super.key,
    required this.style,
    required this.child,
  });

  final CellStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
    style: DefaultTextStyle.of(context).merge(style),
    child: child,
  );
}

/// Ergonomic shortcuts for the most-typed Theme accessors. Saves the
/// `Theme.of(context).colorScheme.error` mouthful in app code; the
/// dependency tracking is identical (each getter ultimately calls
/// `Theme.of(context)`, which establishes the InheritedWidget link).
///
/// ```dart
/// Text('!', style: CellStyle(foreground: context.colors.error))
/// // instead of
/// Text('!', style: CellStyle(foreground: Theme.of(context).colorScheme.error))
/// ```
extension FleuryThemeContext on BuildContext {
  /// Shorthand for `Theme.of(this)`. Establishes a dependency.
  ThemeData get theme => Theme.of(this);

  /// Shorthand for `Theme.of(this).colorScheme`. Establishes a
  /// dependency on the same InheritedWidget — equivalent to
  /// [theme]`.colorScheme`.
  ColorScheme get colors => Theme.of(this).colorScheme;
}
