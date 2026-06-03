import 'package:characters/characters.dart';

/// Policy for deciding when paste should be applied over multiple frames.
final class TextPastePolicy {
  const TextPastePolicy({
    this.largePasteThreshold = 8192,
    this.chunkSize = 2048,
  })  : assert(largePasteThreshold >= 0),
        assert(chunkSize > 0);

  /// Pasted text longer than this many Dart string code units is chunked.
  final int largePasteThreshold;

  /// Maximum approximate chunk size in Dart string code units.
  ///
  /// Chunks never split extended grapheme clusters, so an individual chunk may
  /// exceed this value when one grapheme is larger than [chunkSize].
  final int chunkSize;

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
  TextPasteSession({
    required String text,
    required TextPastePolicy policy,
  })  : totalLength = text.length,
        _chunks = policy.chunks(text).iterator;

  final int totalLength;
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
}
