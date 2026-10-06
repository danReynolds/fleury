import 'dart:async';

import 'package:fleury_doc_examples/testing/save_status.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('chooses when the save finishes', (tester) async {
    final request = Completer<void>();
    tester.pumpWidget(SaveStatus(save: () => request.future));

    await tester.button('Save').press();
    expect(tester.exists(text('Saving…')), isTrue);
    expect(tester.button('Save'), isDisabled);

    request.complete();
    await tester.settle();
    expect(tester.exists(text('Saved')), isTrue);
    expect(tester.button('Save'), isEnabled);
  });
}
