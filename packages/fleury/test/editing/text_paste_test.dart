import 'package:characters/characters.dart';
import 'package:fleury/fleury.dart';
// TextPasteDriver is the widgets' internal paste state machine, deliberately
// not exported by the production barrels; reached here like other internals.
import 'package:fleury/src/editing/text_paste.dart' show TextPasteDriver;
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

      expect(session.nextBatch(0), 'ab');
      expect(session.progress.insertedLength, 2);
      expect(session.isComplete, isFalse);

      expect(session.nextBatch(0), 'cd');
      expect(session.progress.insertedLength, 4);

      expect(session.nextBatch(0), 'ef');
      expect(session.isComplete, isTrue);
      expect(session.progress.active, isFalse);
      expect(session.nextBatch(0), isNull);
    });

    test('a batch takes whole chunks up to the requested minimum', () {
      final session = TextPasteSession(
        text: 'abcdefghij',
        policy: const TextPastePolicy(largePasteThreshold: 1, chunkSize: 2),
      );

      // Five 2-code-unit chunks. A minimum of 5 rounds up to three of them.
      expect(session.nextBatch(5), 'abcdef');
      expect(session.insertedLength, 6);
      expect(session.isComplete, isFalse);

      // A minimum past the end returns the remainder, not null.
      expect(session.nextBatch(1000), 'ghij');
      expect(session.isComplete, isTrue);
      expect(session.nextBatch(1000), isNull);
    });

    test('a batch never splits a grapheme cluster', () {
      final session = TextPasteSession(
        text: 'a🙂b🙂c',
        policy: const TextPastePolicy(largePasteThreshold: 1, chunkSize: 1),
      );

      // 3 code units requested; the emoji straddles the boundary, so the
      // batch rounds up to the whole cluster rather than splitting it.
      final batch = session.nextBatch(3)!;
      expect(batch, 'a🙂');
      expect(batch.characters.length, 2);
    });
  });

  group('TextPasteDriver', () {
    test('a paste arriving through a reentrant finish keeps every accepted '
        'transaction', () {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final pending = <void Function()>[];
      late final TextPasteDriver driver;
      driver = TextPasteDriver(
        policy: () =>
            const TextPastePolicy(largePasteThreshold: 0, chunkSize: 2),
        documentLength: () => controller.text.length,
        applyEdit: (text, {required coalesce}) =>
            controller.paste(text, coalesce: coalesce),
        isAttached: () => true,
        onProgressChanged: () {},
        schedulePostFrame: pending.add,
      );
      driver.start(const PasteEvent('abcdef'), 'abcdef');
      var nested = false;
      controller.addListener(() {
        if (nested) return;
        nested = true;
        driver.start(const PasteEvent('UVWXYZ12'), 'UVWXYZ12');
      });
      // Flushing abcdef invokes the listener, which starts another paste
      // before this caller can begin inserting its own payload.
      driver.start(const PasteEvent('!'), '!');
      for (var step = 0; pending.isNotEmpty && step < 20; step++) {
        pending.removeAt(0)();
      }
      expect(controller.text, 'abcdefUVWXYZ12!');
      controller.undo();
      expect(controller.text, 'abcdefUVWXYZ12');
      controller.undo();
      expect(controller.text, 'abcdef');
      controller.undo();
      expect(controller.text, isEmpty);
      expect(driver.isActive, isFalse);
    });

    for (final trigger in ['first step', 'later step', 'finish']) {
      test('a listener starting another paste during $trigger keeps both '
          'payloads and undo transactions', () {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final pending = <void Function()>[];
        late final TextPasteDriver driver;
        driver = TextPasteDriver(
          policy: () =>
              const TextPastePolicy(largePasteThreshold: 0, chunkSize: 2),
          documentLength: () => controller.text.length,
          applyEdit: (text, {required coalesce}) =>
              controller.paste(text, coalesce: coalesce),
          isAttached: () => true,
          onProgressChanged: () {},
          schedulePostFrame: pending.add,
        );
        var edits = 0;
        var replaced = false;
        controller.addListener(() {
          edits++;
          if (!replaced && edits == (trigger == 'first step' ? 1 : 2)) {
            replaced = true;
            driver.start(const PasteEvent('UVWXYZ12'), 'UVWXYZ12');
          }
        });
        driver.start(const PasteEvent('abcdef'), 'abcdef');
        if (trigger == 'finish') driver.finish();
        for (var step = 0; pending.isNotEmpty && step < 20; step++) {
          pending.removeAt(0)();
        }
        expect(controller.text, 'abcdefUVWXYZ12');
        expect(driver.isActive, isFalse);
        expect(driver.progress.active, isFalse);
        controller.undo();
        expect(controller.text, 'abcdef', reason: 'new paste is one undo');
        controller.undo();
        expect(controller.text, isEmpty, reason: 'original paste is one undo');
      });
    }

    test('applies a large paste in O(log n) edits and linear copying', () {
      final model = _FakeModel();
      final pending = <void Function()>[];
      const policy = TextPastePolicy(chunkSize: 2048);
      final driver = TextPasteDriver(
        policy: () => policy,
        documentLength: () => model.text.length,
        applyEdit: model.apply,
        isAttached: () => true,
        onProgressChanged: () {},
        schedulePostFrame: pending.add,
      );

      final payload = 'y' * (512 * 1024);
      driver.start(const PasteEvent('unused'), payload);
      var steps = 0;
      while (pending.isNotEmpty && steps < 4096) {
        pending.removeAt(0)();
        steps++;
      }

      expect(model.text, payload, reason: 'every code unit lands, in order');
      expect(driver.isActive, isFalse);
      // 512 KiB / 2 KiB = 256 fixed chunks; growing steps need log2(256) + 1.
      expect(model.edits.length, lessThan(16));
      expect(
        model.copiedCodeUnits,
        lessThan(4 * payload.length),
        reason:
            'each edit rebuilds the whole string, so a fixed chunk size made '
            'total copying quadratic: 256 edits copied ~64 MiB for 512 KiB',
      );
    });

    test('finishing mid-paste applies the tail in one edit', () {
      final model = _FakeModel();
      final pending = <void Function()>[];
      const policy = TextPastePolicy(largePasteThreshold: 0, chunkSize: 2);
      final driver = TextPasteDriver(
        policy: () => policy,
        documentLength: () => model.text.length,
        applyEdit: model.apply,
        isAttached: () => true,
        onProgressChanged: () {},
        schedulePostFrame: pending.add,
      );

      driver.start(const PasteEvent('unused'), 'abcdefgh');
      expect(model.text, 'ab');
      expect(driver.progress.active, isTrue);
      expect(driver.progress.insertedLength, 2);
      expect(driver.progress.totalLength, 8);

      driver.finish();

      expect(model.text, 'abcdefgh');
      expect(model.edits, [2, 6], reason: 'the tail is one bulk edit');
      expect(driver.isActive, isFalse);
      expect(driver.progress.active, isFalse);
    });
  });
}

/// Stands in for [TextEditingController]: the model rebuilds its whole string
/// on every edit, which is the cost the growing step size amortizes.
final class _FakeModel {
  var text = '';
  final edits = <int>[];
  var copiedCodeUnits = 0;

  void apply(String batch, {required bool coalesce}) {
    copiedCodeUnits += text.length + batch.length;
    text += batch;
    edits.add(batch.length);
  }
}
