import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('TextPastePolicy', () {
    test('does not chunk text below the threshold', () {
      const policy = TextPastePolicy(largePasteThreshold: 10, chunkSize: 2);

      expect(policy.shouldChunk('hello'), isFalse);
      expect(policy.chunks('hello').toList(), ['hello']);
    });

    test('chunks large text without splitting grapheme clusters', () {
      const policy = TextPastePolicy(largePasteThreshold: 1, chunkSize: 2);

      expect(policy.chunks('a🙂b').toList(), ['a', '🙂', 'b']);
    });
  });

  group('TextPasteSession', () {
    test('tracks inserted length and completes after the last chunk', () {
      final session = TextPasteSession(
        text: 'abcdef',
        policy: const TextPastePolicy(largePasteThreshold: 1, chunkSize: 2),
      );

      expect(session.progress.active, isTrue);
      expect(session.progress.insertedLength, 0);
      expect(session.progress.totalLength, 6);

      expect(session.nextChunk(), 'ab');
      expect(session.progress.insertedLength, 2);
      expect(session.isComplete, isFalse);

      expect(session.nextChunk(), 'cd');
      expect(session.progress.insertedLength, 4);

      expect(session.nextChunk(), 'ef');
      expect(session.isComplete, isTrue);
      expect(session.progress.active, isFalse);
      expect(session.nextChunk(), isNull);
    });
  });
}
