import 'package:fleury/fleury.dart';
import 'package:fleury_doc_examples/testing/preferences.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('edits only the work preferences', (tester) async {
    tester.pumpWidget(preferencesPair());
    final work = tester.target(type: Preferences, key: const ValueKey('work'));

    await work.field('Name').fill('Ada');
    await work.checkbox('Email updates').check();

    expect(work.field('Name'), hasValue('Ada'));
    expect(work.checkbox('Email updates'), isChecked);
    final personal = tester.target(key: const ValueKey('personal'));
    expect(personal.field('Name'), hasValue(''));
    expect(personal.checkbox('Email updates'), isUnchecked);
  });
}
