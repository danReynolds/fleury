import 'package:fleury/fleury_core.dart';

/// A [ThemeData] with a display name — what a theme picker, gallery, or
/// settings screen needs to show a user their options.
final class NamedTheme {
  const NamedTheme(this.name, this.data);

  /// Human-readable label, e.g. `'Tokyo Night'`.
  final String name;

  /// The theme itself.
  final ThemeData data;

  @override
  String toString() => 'NamedTheme($name)';
}
