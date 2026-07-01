// fleury_widgets_web.dart is a hand-maintained mirror of
// fleury_widgets.dart minus the native-only widgets. Nothing else keeps
// the two in sync: a widget exported from one barrel and not the other
// diverges silently — web users just never see it. This test pins the
// policy: the web barrel exports exactly the native barrel's files minus
// the declared native-only set, with identical show combinators.

import 'dart:io';

import 'package:test/test.dart';

/// The declared native-only exclusions — widgets that depend on dart:io
/// directly (file I/O, log capture, process running) or transitively
/// (built on the log/process widgets). Adding a file here is a policy
/// decision: update the fleury_widgets_web.dart header comment and
/// docs/serving-and-embedding.md alongside it.
const nativeOnly = {
  'src/file_browser.dart',
  'src/file_picker.dart',
  'src/form.dart',
  'src/image.dart',
  'src/log_region.dart',
  'src/process_panel.dart',
  'src/terminal_output_region.dart',
  'src/workflow_snapshot.dart',
};

void main() {
  test('web barrel = native barrel minus the declared native-only set', () {
    final native = _exports(File('lib/fleury_widgets.dart'));
    final web = _exports(File('lib/fleury_widgets_web.dart'));

    final missingFromWeb = native.keys
        .where((path) => !web.containsKey(path) && !nativeOnly.contains(path))
        .toList();
    expect(
      missingFromWeb,
      isEmpty,
      reason:
          'Exported from fleury_widgets.dart but not the web barrel and not '
          'declared native-only. Either add the export to '
          'fleury_widgets_web.dart or add the file to nativeOnly here (and '
          'update the barrel header + docs).',
    );

    final webOnly = web.keys
        .where((path) => !native.containsKey(path))
        .toList();
    expect(
      webOnly,
      isEmpty,
      reason: 'Exported from the web barrel but not fleury_widgets.dart.',
    );

    final wronglyExcluded = nativeOnly
        .where((path) => web.containsKey(path))
        .toList();
    expect(
      wronglyExcluded,
      isEmpty,
      reason: 'Declared native-only but exported from the web barrel.',
    );

    final staleExclusions = nativeOnly
        .where((path) => !native.containsKey(path))
        .toList();
    expect(
      staleExclusions,
      isEmpty,
      reason: 'Declared native-only but not exported from the native barrel.',
    );

    for (final path in web.keys) {
      expect(
        web[path],
        equals(native[path]),
        reason:
            'show-combinator drift for $path: the web barrel must re-export '
            'the same symbols as fleury_widgets.dart.',
      );
    }
  });
}

/// Parses a barrel into {exported file path → sorted show symbols}.
Map<String, List<String>> _exports(File barrel) {
  expect(barrel.existsSync(), isTrue, reason: 'missing ${barrel.path}');
  // Collapse to single spaces so multi-line export directives parse flat.
  final source = barrel
      .readAsStringSync()
      .replaceAll(RegExp(r'//[^\n]*'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
  final result = <String, List<String>>{};
  final pattern = RegExp('''export '([^']+)'(?: show ([^;]+))?;''');
  for (final m in pattern.allMatches(source)) {
    final symbols = (m.group(2) ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList()
      ..sort();
    result[m.group(1)!] = symbols;
  }
  return result;
}
