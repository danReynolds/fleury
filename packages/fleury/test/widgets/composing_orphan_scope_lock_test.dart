// Lock test: a late peer commit resolves the composition an edit orphaned —
// and NOTHING else. The rewind that places it correctly deletes the edit it
// replaces, so it must be reachable only from the edit that did the orphaning.
// Keyed on "was a composition orphaned, and how long ago", not on "the last
// transaction happened to be typing", which is also true of an ordinary run.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('orphaned-composition commit is scoped to its own edit', () {
    test('the orphaning keystroke is replaced by the late commit', () {
      final c = TextEditingController(text: 'git ');
      addTearDown(c.dispose);
      c.updateComposingText('che');
      c.insert('X', coalesce: true);
      c.commitComposing(text: 'checkout');

      expect(
        c.text,
        'git checkout',
        reason: 'the commit resolves the preedit the keystroke interrupted',
      );
    });

    test('typing on past the interruption keeps every typed character', () {
      final c = TextEditingController(text: 'git ');
      addTearDown(c.dispose);
      c.updateComposingText('che');
      c.insert('X', coalesce: true);
      for (final ch in ['a', 'b', 'c']) {
        c.insert(ch, coalesce: true);
      }
      c.commitComposing(text: 'checkout');

      expect(
        c.text,
        'git Xabccheckout',
        reason:
            'the run coalesces into one undo entry, so rewinding it would '
            'delete Xabc — four characters the user typed and watched appear',
      );
    });

    test('a commit with no composition behind it cannot eat a typing run', () {
      final c = TextEditingController();
      addTearDown(c.dispose);
      for (final ch in ['h', 'e', 'l', 'l', 'o']) {
        c.insert(ch, coalesce: true);
      }
      // No composition was ever started here — a spurious or stale peer
      // commit must insert, never rewind.
      c.commitComposing(text: 'zzz');

      expect(c.text, 'hellozzz');
    });

    test('a destructive edit that stops at the cancel still resolves', () {
      final c = TextEditingController(text: 'git ');
      addTearDown(c.dispose);
      c.updateComposingText('che');
      // backspace resolves the preedit and stops, applying no edit of its own.
      c.backspace();
      expect(c.text, 'git ');
      c.commitComposing(text: 'checkout');

      expect(
        c.text,
        'git checkout',
        reason: 'delta of zero edits is still the orphaning edit',
      );
    });

    test('the record is single use', () {
      final c = TextEditingController(text: 'git ');
      addTearDown(c.dispose);
      c.updateComposingText('che');
      c.insert('X', coalesce: true);
      c.commitComposing(text: 'checkout');
      expect(c.text, 'git checkout');

      // A second late commit has no orphan left to resolve.
      c.commitComposing(text: 'status');
      expect(
        c.text,
        'git checkoutstatus',
        reason: 'the first commit consumed the record; the second inserts',
      );
    });
  });
}
