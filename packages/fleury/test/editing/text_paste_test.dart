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

    test(
      'takeUpTo never splits graphemes and bulk-slices large remainders',
      () {
        final session = TextPasteSession(
          text: 'a🙂bcdefghij',
          policy: const TextPastePolicy(largePasteThreshold: 1, chunkSize: 2),
        );
        expect(session.takeUpTo(3), 'a🙂');
        expect(session.insertedLength, 3);
        expect(session.takeUpTo(100), 'bcdefghij');
        expect(session.isComplete, isTrue);
      },
    );

    test('nextWork uses bulk slices for a large remainder', () {
      final text = 'x' * (TextPastePolicy.bulkSliceCodeUnits * 2 + 10);
      final session = TextPasteSession(
        text: text,
        policy: const TextPastePolicy(largePasteThreshold: 8, chunkSize: 8),
      );
      final first = session.nextWork()!;
      expect(first.length, TextPastePolicy.bulkSliceCodeUnits);
      final second = session.nextWork()!;
      expect(second.length, TextPastePolicy.bulkSliceCodeUnits);
      // Remainder (10) is below 4×chunkSize, so the policy-sized chunk
      // applies, then the tail.
      expect(session.nextWork()!.length, 8);
      expect(session.nextWork()!.length, 2);
      expect(session.nextWork(), isNull);
    });
  });
}
