/// Widget testing and semantic assertion helpers for Fleury applications.
library;

export 'package:fleury/fleury_test_support.dart' hide FleuryTester;
export 'src/fleury_tester.dart'
    show
        FleuryTester,
        FleuryTarget,
        ambiguousWidePolicy,
        testWidgets,
        testWidgetsOnBothTextPolicies,
        hasCount,
        hasValue,
        isEnabled,
        isDisabled,
        isChecked,
        isUnchecked,
        isFocused;
export 'src/goldens.dart' show matchesGolden;
