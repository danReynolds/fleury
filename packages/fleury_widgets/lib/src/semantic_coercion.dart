/// Coercion helpers for [SemanticAction.setValue] payloads.
///
/// A `setValue` value arrives from an agent/host as a JSON-ish scalar — a
/// `bool`, a `num`, or a `String` — but each value widget wants a specific
/// type (a checkbox wants a bool, a slider a number). These read a payload
/// leniently and return `null` when it can't be read as the wanted type, so a
/// handler can no-op on garbage (reporting "no change") rather than guess.
library;

/// Reads [value] as a bool, or null if it isn't one. Accepts a real `bool`, a
/// `num` (0 ⇒ false, else true), and the common string spellings an agent
/// might emit (`"true"`, `"on"`, `"1"`, `"checked"`, …), case-insensitively.
bool? coerceSemanticBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true' || '1' || 'yes' || 'on' || 'checked' || 'enabled':
        return true;
      case 'false' || '0' || 'no' || 'off' || 'unchecked' || 'disabled':
        return false;
    }
  }
  return null;
}

/// Reads [value] as a double, or null if it isn't numeric. Accepts a `num`, a
/// `bool` (1/0), and a numeric `String`.
double? coerceSemanticNum(Object? value) {
  if (value is num) return value.toDouble();
  if (value is bool) return value ? 1 : 0;
  if (value is String) return double.tryParse(value.trim());
  return null;
}

/// Reads [value] as an int, or null. Accepts an integral `num`, a `bool`, and
/// an integer `String`. A non-integral number (e.g. `2.5`) is rejected rather
/// than silently truncated, so an index/step set can't land off-target.
int? coerceSemanticInt(Object? value) {
  if (value is int) return value;
  if (value is double) return value == value.roundToDouble() ? value.toInt() : null;
  if (value is bool) return value ? 1 : 0;
  if (value is String) return int.tryParse(value.trim());
  return null;
}
