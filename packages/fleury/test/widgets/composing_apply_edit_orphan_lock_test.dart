// Lock test: any _applyEdit during an active IME composition must resolve the
// composition first (cancel back to the preedit baseline), the same way paste
// already does. Today insert / backspace / delete / kill / yank / replaceRange
// / clear null `_compositionBase` while leaving the interim preedit committed,
// so cancel becomes a no-op, undo restores a half-composed value, and a peer
// IME commit that still thinks composition is live lands a duplicate.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('TextEditingController edits during composition', () {
    test('insert cancels the preedit, then inserts against the baseline', () {
      final c = TextEditingController(text: 'git ');
      addTearDown(c.dispose);
      c.updateComposingText('che');
      expect(c.text, 'git che');
      expect(c.composing, const TextRange(start: 4, end: 7));

      c.insert('X', coalesce: true);

      expect(
        c.text,
        'git X',
        reason:
            'insert mid-composition must cancel back to the pre-composition '
            'value first (same contract as paste), then insert — not keep the '
            'abandoned preedit',
      );
      expect(c.composing, TextRange.empty);
      c.cancelComposing();
      expect(
        c.text,
        'git X',
        reason: 'cancel is a no-op once composition was resolved',
      );
      c.undo();
      expect(c.text, 'git ');
    });

    test('backspace cancels the preedit instead of eating into it', () {
      final c = TextEditingController(text: 'git ');
      addTearDown(c.dispose);
      c.updateComposingText('che');

      c.backspace();

      expect(
        c.text,
        'git ',
        reason:
            'backspace mid-composition must cancel the preedit (restore '
            'baseline), not delete one grapheme of the interim text and orphan '
            'the composition base',
      );
      expect(c.composing, TextRange.empty);
      c.cancelComposing();
      expect(c.text, 'git ');
    });

    test('delete cancels the preedit instead of eating into it', () {
      final c = TextEditingController(text: 'git ');
      addTearDown(c.dispose);
      c.updateComposingText('che');
      c.caretOffset = 4;

      c.delete();

      expect(c.text, 'git ');
      expect(c.composing, TextRange.empty);
      c.cancelComposing();
      expect(c.text, 'git ');
    });

    test('killToLineStart cancels before cutting, and does not capture preedit',
        () {
      TextEditingModel.killRing = '';
      final c = TextEditingController(text: 'git ');
      addTearDown(c.dispose);
      c.updateComposingText('che');

      c.killToLineStart();

      expect(
        c.text,
        'git ',
        reason: 'kill mid-composition must cancel first, not cut the preedit',
      );
      expect(
        TextEditingModel.killRing,
        isEmpty,
        reason:
            'cancelling composition is not a kill — the abandoned preedit must '
            'not enter the process-wide kill ring',
      );
      expect(c.composing, TextRange.empty);
    });

    test('yank cancels the preedit, then yanks against the baseline', () {
      TextEditingModel.killRing = 'ZZ';
      final c = TextEditingController(text: 'git ');
      addTearDown(c.dispose);
      c.updateComposingText('che');

      c.yank();

      expect(c.text, 'git ZZ');
      expect(c.composing, TextRange.empty);
      c.cancelComposing();
      expect(c.text, 'git ZZ');
    });

    test('replaceRange cancels the preedit before replacing', () {
      final c = TextEditingController(text: 'git ');
      addTearDown(c.dispose);
      c.updateComposingText('che');

      c.replaceRange(const TextRange(start: 0, end: 3), 'svn');

      expect(c.text, 'svn ');
      expect(c.composing, TextRange.empty);
      c.cancelComposing();
      expect(c.text, 'svn ');
    });

    test(
      'a later peer commit after an orphaning insert must not duplicate',
      () {
        final c = TextEditingController(text: 'git ');
        addTearDown(c.dispose);
        c.updateComposingText('che');
        c.insert('X', coalesce: true);
        // Peer IME still believes composition is live and commits.
        c.commitComposing(text: 'checkout');

        expect(
          c.text,
          'git checkout',
          reason:
              'after a mid-composition insert resolved the preedit, a stale '
              'peer commit must replace/apply cleanly — not append onto the '
              'orphaned interim text (git cheXcheckout)',
        );
      },
    );
  });
}
