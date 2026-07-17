/// Test-only registration and matcher helpers for Fleury's own core suite.
///
/// External packages use `package:fleury_test/fleury_test.dart`. Keeping this
/// adapter under `test/` lets the foundational `fleury` package publish before
/// its companion without a circular hosted dev-dependency.
library;

export 'package:fleury/fleury_test_support.dart';
export 'goldens.dart' show matchesGolden;
export 'test_widgets.dart' show testWidgets;
