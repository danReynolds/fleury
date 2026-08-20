// File-backed golden matcher.
//
// Usage:
//
//     expect(
//       tester.renderToString(),
//       matchesGolden('text_input_focused.txt'),
//     );
//
// When FLEURY_UPDATE_GOLDENS=1 is set in the environment, the matcher
// writes the actual output to the golden file and passes. Otherwise it
// loads the existing file and asserts equality, failing when the file is
// missing or with a unified diff when the contents don't match.
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
/// create or rewrite goldens instead of asserting. Without update mode,
/// a missing golden is a test failure.
///
/// [directory] overrides the default `test/goldens` root, resolved
/// relative to [Directory.current].
Matcher matchesGolden(String name, {String directory = 'test/goldens'}) =>
    _GoldenMatcher(name: name, directory: directory);

class _GoldenMatcher extends Matcher {
  _GoldenMatcher({required this.name, required this.directory});

  final String name;
  final String directory;

  static final _expectedKey = Object();
  static final _actualKey = Object();
  static final _pathKey = Object();
  static final _missingKey = Object();

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    final actual = item.toString();
    final file = File('$directory/$name');

    if (_updateRequested) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(actual);
      return true;
    }

    if (!file.existsSync()) {
      matchState[_actualKey] = actual;
      matchState[_pathKey] = file.path;
      matchState[_missingKey] = true;
      return false;
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
    if (matchState[_missingKey] == true) {
      return mismatchDescription
        ..add('\ngolden file not found: $path')
        ..add(
          '\n\nTo create it: re-run with FLEURY_UPDATE_GOLDENS=1 set, '
          'then review the new file before committing.',
        );
    }
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
