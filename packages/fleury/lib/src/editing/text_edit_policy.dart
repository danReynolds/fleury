/// Why a bounded text edit was rejected. Rejection never clips the input.
enum TextEditRejection { lengthLimit, disallowedCharacter }

/// An immutable admission policy for short editable fields.
///
/// [maxCodeUnits] bounds the resulting text in UTF-16 code units, not displayed
/// characters or UTF-8 bytes. Incoming text is checked before normalization or
/// grapheme layout, so oversized input is rejected without scanning its body.
/// [allowCodePoint] checks each Unicode scalar in the raw input. It should be
/// pure and stable for the controller's lifetime. Empty text is always allowed;
/// required-field and submission validation belong on the form.
///
/// The policy rejects an entire edit, preserving text, selection and history.
/// It is not a secret-erasure or byte-budget policy.
final class TextEditPolicy {
  const TextEditPolicy({required this.maxCodeUnits, this.allowCodePoint})
    : assert(maxCodeUnits >= 0);

  final int maxCodeUnits;
  final bool Function(int codePoint)? allowCodePoint;

  /// Null means accepted. [retainedCodeUnits] counts text outside the replaced
  /// range, plus any previously received segments of the same paste.
  TextEditRejection? check(String input, {int retainedCodeUnits = 0}) {
    if (retainedCodeUnits + input.length > maxCodeUnits) {
      return TextEditRejection.lengthLimit;
    }
    final allows = allowCodePoint;
    if (allows != null) {
      for (final point in input.runes) {
        if (!allows(point)) return TextEditRejection.disallowedCharacter;
      }
    }
    return null;
  }
}
