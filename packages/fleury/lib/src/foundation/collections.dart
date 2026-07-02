// Small collection utilities shared across the framework.

/// Whether [a] and [b] have equal length and pairwise-equal elements
/// (by `==`). Identical lists short-circuit true. The one list-equality
/// used framework-wide — don't hand-roll per-file copies.
bool listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
