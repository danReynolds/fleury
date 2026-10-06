// The fleury README's counter, at the path its test fence imports.
//
// The README tells readers to save the counter as
// `example/counter_quickstart.dart` and its test as
// `test/counter_quickstart_test.dart`. This re-export gives this package the
// same layout, so `../test/counter_quickstart_test.dart` is the README's test
// fence verbatim and runs against the counter the README's first fence pins
// (see `../test/docs_accuracy_test.dart`).
export '../../../packages/fleury/example/counter_quickstart.dart';
