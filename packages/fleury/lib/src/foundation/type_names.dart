// A widget's class name, as a developer-facing identifier. It tells routes
// apart for tests, agents, and debugging; it is not a name for people, and a
// minified build replaces it with an opaque token.

/// The name of [value]'s runtime type, or null when this build does not keep
/// class names.
///
/// The VM, the development compiler, and dart2js at `-O0`/`-O1` keep class
/// names (dart2js may add a numeric suffix to tell same-named classes apart).
/// Optimized dart2js and dart2wasm builds (`-O2` and up) and obfuscated builds
/// replace them with opaque tokens such as `minified:jg`, which must never
/// reach a user: a screen reader would announce one as a page's name.
String? readableTypeName(Object value) =>
    _typeNamesPreserved ? value.runtimeType.toString() : null;

/// Whether `runtimeType.toString()` returns class names in this build, decided
/// once by asking a class whose name is known. A prefix match tolerates the
/// suffix dart2js adds when another library declares a class of the same name;
/// minified and obfuscated names never start with it.
final bool _typeNamesPreserved = const _TypeNameProbe().runtimeType
    .toString()
    .startsWith('_TypeNameProbe');

final class _TypeNameProbe {
  const _TypeNameProbe();
}
