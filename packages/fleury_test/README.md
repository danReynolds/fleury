# fleury_test

Deterministic widget tests for [Fleury](https://github.com/danReynolds/fleury).
The package keeps `package:test`, matcher, and file-backed golden support out of
the production `fleury` dependency graph.

Add it as a dev dependency:

```yaml
dev_dependencies:
  fleury_test: ^0.1.0
  test: ^1.26.3
```

Then drive the same widget tree used by the terminal and browser hosts:

```dart
import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('renders and exposes semantics', (tester) {
    tester.pumpWidget(const Semantics(
      role: SemanticRole.button,
      label: 'Save',
      child: Text('Save'),
    ));

    expect(tester.renderToString(), contains('Save'));
    expect(tester.semantics().byLabel('Save'), hasLength(1));
  });
}
```

`testWidgets` creates and disposes a fresh `FleuryTester`. Use `pumpWidget` for
the exact root you supply, `pumpFleuryHome` only when you want the tester to
construct a canonical `FleuryApp(home: ...)` shell, `sendKey` and semantic
actions for interaction, and `matchesGolden` for file-backed screen snapshots.

Benchmarks and non-test snapshot tools that deliberately do not want
`package:test` can use the lower-level
`package:fleury/fleury_test_support.dart` harness.
