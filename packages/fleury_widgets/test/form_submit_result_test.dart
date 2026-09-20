import 'dart:async';

import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  for (final choice in [false, true]) {
    testWidgets(
      'submit returns false for a server error after restoring ${choice ? 'choice' : 'text'} editing',
      (tester) async {
        final form = FormController();
        final error = ValueNotifier<String?>(null);
        addTearDown(form.dispose);
        addTearDown(error.dispose);
        final pending = Completer<void>();
        Future<bool>? reentrant;
        var called = false;
        tester.pumpWidget(
          ListenableBuilder(
            listenable: error,
            builder: (context, _) => ListenableBuilder(
              listenable: form,
              builder: (context, _) => Form(
                controller: form,
                onSubmit: () async {
                  await pending.future;
                  called = true;
                  error.value = 'Rejected by server';
                },
                child: FormField(
                  error: error.value,
                  child: choice
                      ? Checkbox(
                          value: true,
                          label: 'Choice',
                          onChanged: form.isSubmitting ? null : (_) {},
                        )
                      : TextInput(
                          semanticLabel: 'Name',
                          readOnly: form.isSubmitting,
                        ),
                ),
              ),
            ),
          ),
        );
        form.addListener(() {
          if (called && form.isBusy && !form.isSubmitting) {
            reentrant = form.submit();
          }
        });
        final result = form.submit();
        await tester.settle();
        expect(form.isSubmitting, isTrue);
        if (choice) {
          expect(tester.checkbox('Choice'), isDisabled);
        } else {
          expect(tester.field('Name').snapshot.state.readOnly, isTrue);
        }
        pending.complete();
        await tester.settle();
        expect(await result, isFalse);
        expect(reentrant, same(result));
        expect(tester.renderToString(), contains('Rejected by server'));
        expect(
          choice ? tester.checkbox('Choice') : tester.field('Name'),
          isFocused,
        );
        expect(form.isBusy, isFalse);
      },
    );
  }

  testWidgets(
    'submit checks refreshed validator feedback after callback changes',
    (tester) async {
      final form = FormController();
      final value = TextEditingController(text: 'valid');
      addTearDown(form.dispose);
      addTearDown(value.dispose);
      tester.pumpWidget(
        Form(
          controller: form,
          onSubmit: () => value.text = '',
          child: FormField(
            validator: () => value.text.isEmpty ? 'Required' : null,
            child: TextInput(controller: value),
          ),
        ),
      );
      final result = form.submit();
      await tester.settle();
      expect(await result, isFalse);
      expect(tester.renderToString(), contains('Required'));
    },
  );

  testWidgets('successful save can reset values and clear feedback', (
    tester,
  ) async {
    final form = FormController();
    final value = TextEditingController(text: 'valid');
    addTearDown(form.dispose);
    addTearDown(value.dispose);
    tester.pumpWidget(
      Form(
        controller: form,
        onSubmit: () {
          value.text = '';
          form.clearErrors();
        },
        child: FormField(
          validator: () => value.text.isEmpty ? 'Required' : null,
          child: TextInput(controller: value),
        ),
      ),
    );
    final result = form.submit();
    await tester.settle();
    expect(await result, isTrue);
    expect(value.text, isEmpty);
    expect(tester.renderToString(), isNot(contains('Required')));
  });

  for (final replace in [false, true]) {
    testWidgets(
      'successful callback can ${replace ? 'replace its controller' : 'close its form'}',
      (tester) async {
        final first = FormController();
        final second = FormController();
        final done = ValueNotifier(false);
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        addTearDown(done.dispose);
        tester.pumpWidget(
          ListenableBuilder(
            listenable: done,
            builder: (context, _) => done.value && !replace
                ? const Text('Closed')
                : Form(
                    controller: done.value ? second : first,
                    onSubmit: () => done.value = true,
                    child: done.value
                        ? FormField(
                            error: 'New form error',
                            child: const TextInput(),
                          )
                        : const Text('Ready'),
                  ),
          ),
        );
        final result = first.submit();
        await tester.settle();
        expect(await result, isTrue);
        expect(first.isAttached, isFalse);
        expect(first.isBusy, isFalse);
      },
    );
  }
}
