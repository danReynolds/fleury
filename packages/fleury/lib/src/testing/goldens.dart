// File-backed golden matcher.
//
// Usage:
//
//     expect(
//       tester.renderToString(),
//       matchesGolden('text_input_focused.txt'),
//     );
//
// On first run (or when FLEURY_UPDATE_GOLDENS=1 is set in the
// environment), the matcher writes the actual output to the golden
// file and passes. On subsequent runs it loads the file and asserts
// equality, failing with a unified diff when they don't match.
//
// File resolution: goldens live under <package_root>/test/goldens/
// by default. `package_root` is the working directory `dart test`
// is invoked from — which is the package directory in our setup.
// Tests in nested folders pass a sub-path:
//
//     matchesGolden('widgets/text_input/focused.txt')
//
// Updating: re-run the suite with the env var set:
//
//     FLEURY_UPDATE_GOLDENS=1 dart test
//
// Review the file diff before committing — automated golden updates
// are how subtle regressions get committed silently.

// ignore_for_file: depend_on_referenced_packages
// The `matcher` package is a transitive dep of `test`; once we split
// into a dedicated fleury_test package this import becomes
// first-party and the suppression goes away.

import 'dart:io';

import 'package:matcher/matcher.dart';

/// Whether goldens should be (re)written on this run.
bool get _updateRequested {
  final v = Platform.environment['FLEURY_UPDATE_GOLDENS'];
  return v == '1' || v == 'true';
}

/// Matches a string against the contents of a golden file under
/// `test/goldens/`.
///
/// Set the `FLEURY_UPDATE_GOLDENS` environment variable to `1` to
/// rewrite goldens instead of asserting. Missing goldens are
/// always written (so first runs bootstrap themselves).
///
/// [directory] overrides the default `test/goldens` root, resolved
/// relative to [Directory.current].
Matcher matchesGolden(String name, {String directory = 'test/goldens'}) =>
    _GoldenMatcher(name: name, directory: directory);

class _GoldenMatcher extends Matcher {
  _GoldenMatcher({required this.name, required this.directory});

  final String name;
  final String directory;

  static const _expectedKey = Object();
  static const _actualKey = Object();
  static const _pathKey = Object();
  static const _wroteKey = Object();

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    final actual = item.toString();
    final file = File('$directory/$name');

    if (_updateRequested || !file.existsSync()) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(actual);
      matchState[_wroteKey] = file.path;
      return true;
    }

    final expected = file.readAsStringSync();
    if (actual == expected) return true;

    matchState[_expectedKey] = expected;
    matchState[_actualKey] = actual;
    matchState[_pathKey] = file.path;
    return false;
  }

  @override
  Description describe(Description description) =>
      description.add('matches golden file $directory/$name');

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    final expected = matchState[_expectedKey] as String? ?? '';
    final actual = matchState[_actualKey] as String? ?? '';
    final path = matchState[_pathKey] as String? ?? '?';
    return mismatchDescription
      ..add('\n--- expected (from $path) ---\n')
      ..add(expected)
      ..add('\n--- actual ---\n')
      ..add(actual)
      ..add(
        '\n\nTo update: re-run with FLEURY_UPDATE_GOLDENS=1 set, '
        'then review the diff before committing.',
      );
  }
}
