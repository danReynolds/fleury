/// Test helpers for `fleury`. Import from test files only.
///
///     import 'package:fleury/fleury.dart';
///     import 'package:fleury/fleury_test.dart';
///     import 'package:test/test.dart';
///
///     void main() {
///       testWidgets('autofocus claims focus', (tester) {
///         tester.pumpWidget(TextInput(autofocus: true));
///         expect(tester.find(byType(TextInput)), hasLength(1));
///       });
///     }
///
/// Follows the `flutter_test` convention: a second public library
/// alongside the main one, used only in test files so production
/// builds don't depend on `dart:io` or test harness machinery.
library;

export 'src/testing/fleury_tester.dart' show FleuryTester, testWidgets;
export 'src/testing/finders.dart'
    show Finder, byKey, byPredicate, byType, descendantOf, text;
export 'src/testing/goldens.dart' show matchesGolden;
