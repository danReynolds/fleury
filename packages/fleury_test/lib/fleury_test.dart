/// Widget testing and semantic assertion helpers for Fleury applications.
library;

export 'package:fleury/fleury_test_support.dart' hide FleuryTester;
export 'src/fleury_tester.dart'
    show
        FleuryTester,
        ambiguousWidePolicy,
        testWidgets,
        testWidgetsOnBothTextPolicies;
export 'src/goldens.dart' show matchesGolden;
