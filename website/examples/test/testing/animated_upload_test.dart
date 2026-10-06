import 'package:fleury_doc_examples/testing/animated_upload.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('inspects the upload halfway through its animation', (
    tester,
  ) async {
    tester.pumpWidget(const AnimatedUpload());
    await tester.button('Animate').press();
    final upload = tester.target(role: SemanticRole.progress, label: 'Upload');

    tester.pump(const Duration(milliseconds: 500));
    expect(upload, hasValue(0.5));

    tester.pumpAndSettle();
    expect(upload, hasValue(1.0));
  });
}
