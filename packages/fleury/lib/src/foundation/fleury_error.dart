// FleuryError — a small structured-error helper. The framework's
// throw sites used to be `throw StateError('terse message')`, which
// is correct but useless for a new dev: it tells you WHAT went wrong
// without telling you WHY it happens or HOW to fix it.
//
// Flutter solved this with FlutterError + ErrorSummary/Description/
// Hint nodes. We need much less than that for now — a few structured
// fields and a formatted toString — but the API leaves room to
// grow without forcing every site to migrate twice.

/// A framework error with a brief summary, optional details, and an
/// actionable hint for the developer.
///
/// Thrown by fleury internals in place of bare `StateError`s. The debug
/// overlay, error widget, and crash output all render it via `toString()`,
/// which produces a readable multi-line block — summary first, then the
/// optional details, hint, and docs URL — that pastes cleanly into a bug
/// report.
///
/// ```dart
/// throw FleuryError(
///   summary: 'RenderFlex children have non-zero flex but '
///       'incoming maxCols constraints are unbounded.',
///   details: 'A Row inside a horizontal ScrollView has Expanded '
///       'children; the ScrollView gives the Row unbounded width '
///       'so Expanded cannot decide how much space to take.',
///   hint: 'Wrap Expanded children in a SizedBox(width: …) or '
///       'switch the ScrollView to vertical.',
///   docs: 'https://fleury.dev/errors/unbounded-flex',
/// );
/// ```
class FleuryError extends Error {
  FleuryError({required this.summary, this.details, this.hint, this.docs});

  /// One-line description suitable for a UI error widget. The
  /// shortest sentence that uniquely identifies the failure.
  final String summary;

  /// Optional context — what was expected, what was given, what
  /// state the framework was in. Reads as the second paragraph.
  final String? details;

  /// Optional actionable advice — the most common fix or the next
  /// thing to investigate. Reads as the third paragraph, prefixed
  /// with "How to fix this:".
  final String? hint;

  /// Optional documentation URL. Surfaced as a final line.
  final String? docs;

  @override
  String toString() {
    final buf = StringBuffer(summary);
    final d = details;
    if (d != null && d.isNotEmpty) {
      buf.writeln();
      buf.writeln();
      buf.write(d);
    }
    final h = hint;
    if (h != null && h.isNotEmpty) {
      buf.writeln();
      buf.writeln();
      buf.write('How to fix this: $h');
    }
    final u = docs;
    if (u != null && u.isNotEmpty) {
      buf.writeln();
      buf.write('See: $u');
    }
    return buf.toString();
  }
}
