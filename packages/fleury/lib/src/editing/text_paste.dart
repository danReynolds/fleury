import 'package:characters/characters.dart';

/// Policy for deciding when paste should be applied over multiple frames.
final class TextPastePolicy {
  const TextPastePolicy({
    this.largePasteThreshold = 8192,
    this.chunkSize = 2048,
  }) : assert(largePasteThreshold >= 0),
       assert(chunkSize > 0);

  /// Pasted text longer than this many Dart string code units is chunked.
  final int largePasteThreshold;

  /// Maximum approximate chunk size in Dart string code units.
  ///
  /// Chunks never split extended grapheme clusters, so an individual chunk may
  /// exceed this value when one grapheme is larger than [chunkSize].
  final int chunkSize;

  /// Per-frame code-unit slice for a large remaining paste. One coalesced
  /// insert of this size is O(n); hundreds of [chunkSize] inserts are O(n²).
  static const int bulkSliceCodeUnits = 32 * 1024;

  /// Wall time a single paste tick may spend applying slices before yielding
  /// so the event loop can take SIGINT / input.
  static const Duration frameBudget = Duration(milliseconds: 8);

  bool shouldChunk(String text) => text.length > largePasteThreshold;

  Iterable<String> chunks(String text) sync* {
    if (text.isEmpty) return;
    if (!shouldChunk(text)) {
      yield text;
      return;
    }

    var buffer = StringBuffer();
    var size = 0;
    for (final grapheme in text.characters) {
      final nextSize = size + grapheme.length;
      if (size > 0 && nextSize > chunkSize) {
        yield buffer.toString();
        buffer = StringBuffer();
        size = 0;
      }
      buffer.write(grapheme);
      size += grapheme.length;
    }
    if (size > 0) yield buffer.toString();
  }
}

/// Progress for an active chunked paste session.
final class TextPasteProgress {
  const TextPasteProgress({
    required this.active,
    required this.insertedLength,
    required this.totalLength,
  });

  static const inactive = TextPasteProgress(
    active: false,
    insertedLength: 0,
    totalLength: 0,
  );

  final bool active;
  final int insertedLength;
  final int totalLength;

  double get fraction {
    if (totalLength <= 0) return active ? 0 : 1;
    return insertedLength / totalLength;
  }
}

/// Mutable iterator over one paste operation.
final class TextPasteSession {
  TextPasteSession({required String text, required TextPastePolicy policy})
    : _text = text,
      totalLength = text.length,
      _chunkSize = policy.chunkSize,
      _chunks = policy.chunks(text).iterator;

  final String _text;
  final int totalLength;
  final int _chunkSize;
  final Iterator<String> _chunks;
  int _insertedLength = 0;
  bool _complete = false;

  int get insertedLength => _insertedLength;
  bool get isComplete => _complete;

  TextPasteProgress get progress => _complete
      ? TextPasteProgress.inactive
      : TextPasteProgress(
          active: true,
          insertedLength: _insertedLength,
          totalLength: totalLength,
        );

  String? nextChunk() {
    if (_complete) return null;
    if (!_chunks.moveNext()) {
      _complete = true;
      return null;
    }
    final chunk = _chunks.current;
    _insertedLength += chunk.length;
    if (_insertedLength >= totalLength) _complete = true;
    return chunk;
  }

  /// Next work item: a policy-sized piece for small remainders, otherwise a
  /// grapheme-safe bulk slice so a megabyte paste is tens of inserts, not
  /// hundreds. Uses [takeUpTo] so the cursor stays consistent with bulk
  /// drain; do not mix with [nextChunk] on the same session.
  String? nextWork() {
    final remaining = totalLength - _insertedLength;
    if (remaining <= 0) {
      _complete = true;
      return null;
    }
    final cap = remaining > _chunkSize * 4
        ? TextPastePolicy.bulkSliceCodeUnits
        : _chunkSize;
    return takeUpTo(cap);
  }

  /// Takes up to [maxCodeUnits] of unapplied text, never splitting a grapheme.
  /// A single grapheme larger than [maxCodeUnits] is still emitted whole.
  String? takeUpTo(int maxCodeUnits) {
    assert(maxCodeUnits > 0);
    if (_complete) return null;
    final remaining = totalLength - _insertedLength;
    if (remaining <= 0) {
      _complete = true;
      return null;
    }
    if (remaining <= maxCodeUnits) return takeRemaining();
    final rest = _text.substring(_insertedLength);
    var size = 0;
    final buffer = StringBuffer();
    for (final grapheme in rest.characters) {
      final nextSize = size + grapheme.length;
      if (size > 0 && nextSize > maxCodeUnits) break;
      buffer.write(grapheme);
      size = nextSize;
    }
    final slice = buffer.toString();
    _insertedLength += slice.length;
    if (_insertedLength >= totalLength) _complete = true;
    return slice.isEmpty ? null : slice;
  }

  /// Takes all unapplied text as one bulk chunk.
  ///
  /// Normal progress remains frame-chunked. Queue-pressure and ordering
  /// barriers use this escape hatch to avoid hundreds of synchronous
  /// whole-string edits while preserving every code unit already accepted.
  String? takeRemaining() {
    if (_complete) return null;
    final remaining = _text.substring(_insertedLength);
    _insertedLength = totalLength;
    _complete = true;
    return remaining.isEmpty ? null : remaining;
  }
}
