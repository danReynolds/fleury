// Type names that are safe to show: a widget's class name identifies it for
// tests, agents, and debugging, but only in builds that keep class names.

/// The source name of [value]'s runtime type, or null when this build does not
/// keep type names.
///
/// The VM, the development compiler, and dart2js at `-O0`/`-O1` keep class
/// names. Optimized dart2js and dart2wasm builds (`-O2` and up) minify them to
/// opaque tokens such as `minified:jg`, which must never reach a user — a
/// screen reader would announce one as a page's name.
String? readableTypeName(Object value) =>
    _typeNamesPreserved ? value.runtimeType.toString() : null;

/// Whether `runtimeType.toString()` returns source class names in this build,
/// decided once by asking a class whose name is known.
final bool _typeNamesPreserved =
    const _TypeNameProbe().runtimeType.toString() == '_TypeNameProbe';

final class _TypeNameProbe {
  const _TypeNameProbe();
}
