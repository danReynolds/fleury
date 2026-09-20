import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

Widget fields(FormController form, {void Function()? onSubmit}) => Form(
  controller: form,
  onSubmit: onSubmit ?? () {},
  child: Column(
    children: [
      FormField(
        validator: () => 'Enter a name.',
        child: const TextInput(semanticLabel: 'Name'),
      ),
      const TextInput(semanticLabel: 'Notes', autofocus: true),
    ],
  ),
);

void main() {
  testWidgets('autofocus false displays errors and preserves focus', (
    tester,
  ) async {
    final form = FormController();
    addTearDown(form.dispose);
    tester.pumpWidget(fields(form));
    await tester.field('Notes').focus();
    final validation = form.validate(autofocus: false);
    await tester.settle();
    expect(await validation, isFalse);
    expect(tester.field('Notes'), isFocused);
    expect(tester.renderToString(), contains('Enter a name.'));

    // A later call uses the default, not the preceding pass's policy.
    final next = form.validate();
    await tester.settle();
    expect(await next, isFalse);
    expect(tester.field('Name'), isFocused);
  });

  for (final policy in [(false, false), (false, true), (true, false)]) {
    testWidgets('coalesced validation combines autofocus requests $policy', (
      tester,
    ) async {
      final form = FormController();
      addTearDown(form.dispose);
      tester.pumpWidget(fields(form));
      await tester.field('Notes').focus();
      final first = form.validate(autofocus: policy.$1);
      final second = form.validate(autofocus: policy.$2);
      expect(second, same(first));
      await tester.settle();
      expect(await first, isFalse);
      expect(
        tester.field(policy.$1 || policy.$2 ? 'Name' : 'Notes'),
        isFocused,
      );
    });
  }

  testWidgets('submit requests autofocus when joining a quiet validation', (
    tester,
  ) async {
    final form = FormController();
    addTearDown(form.dispose);
    var submitted = false;
    tester.pumpWidget(fields(form, onSubmit: () => submitted = true));
    await tester.field('Notes').focus();
    final validation = form.validate(autofocus: false);
    final submission = form.submit();
    await tester.settle();
    expect(await validation, isFalse);
    expect(await submission, isFalse);
    expect(submitted, isFalse);
    expect(tester.field('Name'), isFocused);
  });

  testWidgets('autofocus false does not scroll to an offscreen error', (
    tester,
  ) async {
    final form = FormController();
    final scroll = ScrollController();
    addTearDown(form.dispose);
    addTearDown(scroll.dispose);
    tester.pumpWidget(
      Form(
        controller: form,
        onSubmit: () {},
        child: Column(
          children: [
            const TextInput(semanticLabel: 'Notes', autofocus: true),
            SizedBox(
              height: 4,
              child: ScrollView(
                controller: scroll,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    FormField(
                      validator: () => 'Enter a name.',
                      child: const TextInput(semanticLabel: 'Name'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.field('Notes').focus();
    final validation = form.validate(autofocus: false);
    await tester.settle();
    expect(await validation, isFalse);
    expect(scroll.offset, 0);
    expect(tester.field('Notes'), isFocused);
  });
}
