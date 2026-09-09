// Lock test: a commit that arrives after its composition was already resolved
// INSERTS. It never rewinds, because every edit that can resolve a preedit
// early — a keystroke, a paste, a clear — is an edit whose result the user has
// already seen, and rewinding deletes it with no way to tell which one it was.
//
// The tempting case is `git che` + `X` + commit(`checkout`): rewinding reads
// `git checkout` instead of `git Xcheckout`. The same rewind deletes a paste
// made during composition, which is reachable in a browser — the DOM source
// suppresses keydown and input while composing, but not paste.
import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('a late composition commit never deletes existing text', () {
    test('after an interrupting keystroke it appends', () {
      final c = TextEditingController(text: 'git ');
      addTearDown(c.dispose);
      c.updateComposingText('che');
      c.insert('X', coalesce: true);
      c.commitComposing(text: 'checkout');

      expect(
        c.text,
        'git Xcheckout',
        reason: 'the typed X survives; the late commit lands after it',
      );
    });

    test('a paste made during composition survives', () {
      final c = TextEditingController(text: 'git ');
      addTearDown(c.dispose);
      c.updateComposingText('che');
      c.paste('~/Downloads/report.pdf');
      c.commitComposing(text: 'checkout');

      expect(
        c.text,
        contains('~/Downloads/report.pdf'),
        reason:
            'clipboard content the user pasted and watched appear cannot be '
            'silently replaced by a late commit',
      );
    });

    test('a deliberate clear stays cleared', () {
      final c = TextEditingController(text: 'git ');
      addTearDown(c.dispose);
      c.updateComposingText('che');
      c.clear();
      c.commitComposing(text: 'checkout');

      expect(
        c.text,
        'checkout',
        reason:
            'the commit inserts into the cleared field, it does not '
            'restore what clear() removed',
      );
    });

    test('a whole typing run survives a commit that follows it', () {
      final c = TextEditingController();
      addTearDown(c.dispose);
      for (final ch in ['h', 'e', 'l', 'l', 'o']) {
        c.insert(ch, coalesce: true);
      }
      c.commitComposing(text: 'zzz');

      expect(c.text, 'hellozzz', reason: 'a coalesced run is not a preedit');
    });

    test('a commit cannot rewind past the user own undo', () {
      final c = TextEditingController(text: 'git ');
      addTearDown(c.dispose);
      c.updateComposingText('che');
      c.insert('X', coalesce: true);
      c.undo();
      final afterUndo = c.text;
      c.commitComposing(text: 'checkout');

      expect(
        c.text,
        startsWith(afterUndo),
        reason: 'undo decided what the text is; the commit only adds to it',
      );
    });
  });
}
