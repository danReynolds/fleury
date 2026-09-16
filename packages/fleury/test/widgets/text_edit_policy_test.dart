import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test_support.dart';
import 'package:test/test.dart';

bool printableAscii(int point) => point >= 32 && point <= 126;
const policy = TextEditPolicy(maxCodeUnits: 12, allowCodePoint: printableAscii);

void main() {
  test('rejection preserves directional selection, notifications and redo', () {
    final rejected = <TextEditRejection>[];
    final c = TextEditingController(
      text: 'acme/key',
      editPolicy: policy,
      onEditRejected: rejected.add,
    );
    addTearDown(c.dispose);
    c.insert('!');
    c.undo();
    c.selection = const TextSelection(baseOffset: 8, extentOffset: 5);
    final before = c.value;
    var notifications = 0;
    c.addListener(() => notifications++);
    for (final edit in <void Function()>[
      () => c.insert('🔑'),
      () => c.paste('x' * 1000000),
      () => c.text = 'bad\nvalue',
      () => c.value = TextEditingValue(text: 'bad🔑'),
      () => c.replaceRange(const TextRange(start: 5, end: 8), '🔑'),
    ]) {
      edit();
      expect(c.value, before);
      expect(c.canRedo, isTrue);
    }
    expect(notifications, 0);
    expect(rejected, hasLength(5));
    c.redo();
    expect(c.text, 'acme/key!');
  });

  test('length counts replacement rather than selection plus input', () {
    final c = TextEditingController(text: 'abcdefghijkl', editPolicy: policy);
    addTearDown(c.dispose);
    c.selection = const TextSelection(baseOffset: 9, extentOffset: 12);
    c.paste('XYZ');
    expect(c.text, 'abcdefghiXYZ');
    c.undo();
    expect(c.text, 'abcdefghijkl');
    expect(c.selection, const TextSelection(baseOffset: 9, extentOffset: 12));
  });

  test('oversized input is rejected before its characters are visited', () {
    var visited = 0;
    final c = TextEditingController(
      editPolicy: TextEditPolicy(
        maxCodeUnits: 12,
        allowCodePoint: (_) {
          visited++;
          return true;
        },
      ),
    );
    addTearDown(c.dispose);
    c.paste('x' * 1000000);
    expect(visited, 0);
    expect(c.text, isEmpty);
    expect(c.canUndo, isFalse);
  });

  test('composition rejection preserves accepted preedit and cancellation', () {
    final c = TextEditingController(text: 'acme/key', editPolicy: policy);
    addTearDown(c.dispose);
    c.selection = const TextSelection(baseOffset: 5, extentOffset: 8);
    final original = c.value;
    c.updateComposingText('token');
    final accepted = c.value;
    c.updateComposingText('🔑');
    expect(c.value, accepted);
    c.commitComposing(text: 'x' * 1000000);
    expect(c.value, accepted);
    c.cancelComposing();
    expect(c.value, original);
    expect(c.canUndo, isFalse);
    c.updateComposingText('token');
    c.commitComposing();
    expect(c.text, 'acme/token');
    c.undo();
    expect(c.value, original);
  });

  test('rejected first composition does not intercept the next undo', () {
    final c = TextEditingController(editPolicy: policy)..insert('key');
    addTearDown(c.dispose);
    c.updateComposingText('🔑');
    c.undo();
    expect(c.text, isEmpty);
  });

  test('invalid paste does not cancel a live composition', () {
    final c = TextEditingController(text: 'key', editPolicy: policy);
    addTearDown(c.dispose);
    c.updateComposingText('X');
    final accepted = c.value;
    c.paste('🔑');
    expect(c.value, accepted);
    c.commitComposing();
    c.undo();
    expect(c.text, 'key');
  });

  test('yank obeys policy and leaves history unchanged on rejection', () {
    final old = TextEditingModel.killRing;
    addTearDown(() => TextEditingModel.killRing = old);
    final c = TextEditingController(text: 'key', editPolicy: policy);
    addTearDown(c.dispose);
    TextEditingModel.killRing = '🔑';
    c.yank();
    expect(c.text, 'key');
    expect(c.canUndo, isFalse);
  });

  test('initial invalid text is rejected without exposing it in the error', () {
    expect(
      () => TextEditingController(text: '🔑', editPolicy: policy),
      throwsArgumentError,
    );
  });

  test('unconstrained exact-text controllers retain their contract', () {
    final c = TextEditingController(preserveText: true);
    addTearDown(c.dispose);
    c.paste('🔑\r\n\x1b');
    expect(c.text, '🔑\r\n\x1b');
    c.undo();
    expect(c.text, isEmpty);
  });

  test('normalized rejection preserves composition and undo', () {
    final c = TextEditingController(
      editPolicy: TextEditPolicy(
        maxCodeUnits: 12,
        allowCodePoint: (point) => point != 0xfffd,
      ),
    );
    addTearDown(c.dispose);
    c.insert('key');
    c.updateComposingText('X');
    final before = c.value;
    c.paste('\x1b[31m');
    expect(c.value, before);
    c.cancelComposing();
    c.updateComposingText('\x1b[31m');
    c.undo();
    expect(c.text, isEmpty);
  });

  for (final multiline in [false, true]) {
    test(
      'bounded ${multiline ? 'TextArea' : 'TextInput'} admits complete paste atomically',
      () async {
        final rejected = <TextEditRejection>[];
        final c = TextEditingController(
          text: 'acme/key',
          editPolicy: policy,
          onEditRejected: rejected.add,
        );
        final focus = FocusNode();
        final tester = FleuryTester();
        addTearDown(tester.dispose);
        addTearDown(c.dispose);
        addTearDown(focus.dispose);
        tester.pumpWidget(
          multiline
              ? TextArea(controller: c, focusNode: focus, autofocus: true)
              : TextInput(controller: c, focusNode: focus, autofocus: true),
        );
        tester.pump();
        final claimant = focus.textInputClaimant!;
        c.selection = const TextSelection(baseOffset: 5, extentOffset: 8);
        final before = c.value;
        final paste = claimant as PasteEventClaimant;
        paste.onPasteEvent(
          const PasteEvent.segment(
            'abc',
            pasteId: 1,
            phase: PasteEventPhase.start,
          ),
        );
        expect(c.value, before);
        paste.onPasteEvent(
          const PasteEvent.segment(
            'x',
            pasteId: 1,
            phase: PasteEventPhase.continuation,
          ),
        );
        expect(c.value, before);
        paste.onPasteEvent(
          PasteEvent.segment(
            'y' * 1000000,
            pasteId: 1,
            phase: PasteEventPhase.end,
          ),
        );
        expect(c.value, before);
        expect(c.canUndo, isFalse);
        expect(rejected, [TextEditRejection.lengthLimit]);
        paste.onPasteEvent(
          const PasteEvent.segment(
            'tok',
            pasteId: 2,
            phase: PasteEventPhase.start,
          ),
        );
        paste.onPasteEvent(
          const PasteEvent.segment(
            'en',
            pasteId: 2,
            phase: PasteEventPhase.end,
          ),
        );
        expect(c.text, 'acme/token');
        c.undo();
        expect(c.value, before);
        paste.onPasteEvent(
          const PasteEvent.segment(
            'ok',
            pasteId: 3,
            phase: PasteEventPhase.start,
          ),
        );
        paste.onPasteEvent(
          const PasteEvent.segment(
            '🔑',
            pasteId: 3,
            phase: PasteEventPhase.continuation,
          ),
        );
        paste.onPasteEvent(
          const PasteEvent.segment(
            'tail',
            pasteId: 3,
            phase: PasteEventPhase.end,
          ),
        );
        expect(c.value, before);
        expect(c.canRedo, isTrue);
        // A key edit interrupts an incomplete paste; its tail must not land later.
        paste.onPasteEvent(
          const PasteEvent.segment(
            'X',
            pasteId: 4,
            phase: PasteEventPhase.start,
          ),
        );
        claimant.onTextInput('Z');
        final edited = c.value;
        paste.onPasteEvent(
          const PasteEvent.segment('Y', pasteId: 4, phase: PasteEventPhase.end),
        );
        expect(c.value, edited);
        paste.onPasteEvent(
          const PasteEvent.segment(
            'Q',
            pasteId: 5,
            phase: PasteEventPhase.start,
          ),
        );
        c.caretOffset = 0;
        final moved = c.value;
        paste.onPasteEvent(
          const PasteEvent.segment('R', pasteId: 5, phase: PasteEventPhase.end),
        );
        expect(c.value, moved);
        await tester.invokeSemanticAction(
          SemanticAction.setValue,
          role: multiline ? SemanticRole.textArea : SemanticRole.textField,
          payload: 'bad🔑',
        );
        expect(c.value, moved);
      },
    );
  }
}
