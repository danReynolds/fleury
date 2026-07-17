@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final repo = _findRepoRoot();

  group('launch-facing documentation', () {
    test('does not restore known volatile or inaccurate claims', () {
      final files = _publicDocs(repo);
      final failures = <String>[];
      final hardCodedPackageTests = RegExp(
        r'\b\d[\d,]* tests? in this package\b',
        caseSensitive: false,
      );
      final privatePackageImport = RegExp(r'package:[^/\s`"\x27]+/src/');
      final unchangedCrossTargetClaim = RegExp(
        r'the same (?:app|code) runs[^\n]*unchanged',
        caseSensitive: false,
      );

      for (final file in files) {
        final text = file.readAsStringSync();
        for (final (label, pattern) in <(String, Pattern)>[
          ('hard-coded package test count', hardCodedPackageTests),
          ('consumer import from package src', privatePackageImport),
          ('nonexistent `fleury mcp` command', 'fleury mcp'),
          (
            'legacy bundled testing-package import',
            'package:fleury/fleury_test.dart',
          ),
          ('legacy tester shell helper', 'pumpApp('),
          ('unchanged cross-target code claim', unchangedCrossTargetClaim),
          ('obsolete browser test command', 'run_tui_web_test.dart'),
          ('obsolete platform claim', 'POSIX today'),
          ('overbroad platform evidence claim', 'POSIX launch matrix'),
          ('universal semantic-node claim', 'every node already carries'),
          (
            'tester-retains-semantics claim',
            'browser hosts, the headless tester',
          ),
          (
            'build-every-frame claim',
            'every frame this widget needs to repaint',
          ),
          ('state parity absolute', "Flutter's, unchanged"),
          ('layout parity absolute', 'lays out exactly like Flutter'),
          ('universal debug-shell claim', 'Every fleury app ships'),
        ]) {
          if (text.containsPattern(pattern)) {
            failures.add('${p.relative(file.path, from: repo.path)}: $label');
          }
        }
      }

      expect(failures, isEmpty, reason: failures.join('\n'));
    });

    test('every Dart test file named in maintained commands exists', () {
      final docs = <File>[
        ..._publicDocs(repo),
        File(p.join(repo.path, 'docs/implementation/web-rfc-review-packet.md')),
      ];
      final dartFiles = Directory(repo.path)
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => p.normalize(file.path))
          .toList(growable: false);
      final missing = <String>[];
      final dartPath = RegExp(r'(?<![\w.])([\w./-]+\.dart)\b');

      for (final doc in docs.where((file) => file.existsSync())) {
        for (final line in doc.readAsLinesSync()) {
          if (!line.contains('dart test')) continue;
          for (final match in dartPath.allMatches(line)) {
            final referenced = p.normalize(match.group(1)!);
            final suffix =
                p.separator + referenced.replaceAll('/', p.separator);
            if (!dartFiles.any((path) => path.endsWith(suffix))) {
              missing.add(
                '${p.relative(doc.path, from: repo.path)}: $referenced',
              );
            }
          }
        }
      }

      expect(missing, isEmpty, reason: missing.join('\n'));
    });

    test('compile-checked browser shell uses only web-safe barrels', () {
      final snippet = File(
        p.join(repo.path, 'website/examples/doc_snippets/web_app_shell.dart'),
      ).readAsStringSync();
      final sharedTree = File(
        p.join(repo.path, 'website/examples/doc_snippets/status_app.dart'),
      ).readAsStringSync();
      expect(snippet, contains("package:fleury/fleury_core.dart"));
      expect(snippet, contains("package:fleury_web/fleury_web.dart"));
      expect(
        '$snippet\n$sharedTree',
        contains("package:fleury_widgets/fleury_widgets_web.dart"),
      );
      expect(snippet, isNot(contains("package:fleury/fleury.dart")));
      expect(
        '$snippet\n$sharedTree',
        isNot(contains("package:fleury_widgets/fleury_widgets.dart")),
      );
    });

    test('getting started declares and imports its browser dependencies', () {
      final guide = File(
        p.join(repo.path, 'website/src/content/docs/getting-started.mdx'),
      ).readAsStringSync();
      expect(guide, contains('path: packages/fleury_web'));
      expect(guide, contains('web: ^1.1.1'));
      expect(guide, contains('title="lib/status_app.dart"'));
      expect(guide, contains("package:my_app/status_app.dart"));
    });

    test('serve guide documents every public lifecycle and safety flag', () {
      final guide = File(
        p.join(repo.path, 'website/src/content/docs/guides/deployment.md'),
      ).readAsStringSync();
      for (final flag in const <String>[
        '--port=<n>',
        '--host=<addr>',
        '--allow-origin=<origin>',
        '--token=<secret>',
        '--debug',
        '--max-sessions=<n>',
        '--spawn <cmd …>',
      ]) {
        expect(guide, contains(flag), reason: 'Missing serve flag: $flag');
      }
    });
  });
}

Directory _findRepoRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (File(p.join(current.path, 'website/package.json')).existsSync() &&
        Directory(p.join(current.path, 'packages/fleury')).existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not locate the Fleury repository root.');
    }
    current = parent;
  }
}

List<File> _publicDocs(Directory repo) {
  final files = <File>[
    File(p.join(repo.path, 'README.md')),
    File(p.join(repo.path, 'packages/fleury/README.md')),
    File(p.join(repo.path, 'packages/fleury_widgets/README.md')),
    File(p.join(repo.path, 'packages/fleury_web/README.md')),
    File(p.join(repo.path, 'packages/fleury_mcp/README.md')),
    for (final name in const <String>[
      'architecture.md',
      'architecture-overview.md',
      'architecture-deep-dive.md',
      'core-and-targets.md',
      'serving-and-embedding.md',
      'agents-and-semantics.md',
      'performance.md',
    ])
      File(p.join(repo.path, 'docs', name)),
    ...Directory(p.join(repo.path, 'website/src/content/docs'))
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where(
          (file) => file.path.endsWith('.md') || file.path.endsWith('.mdx'),
        ),
  ];
  return files.where((file) => file.existsSync()).toList(growable: false);
}

extension on String {
  bool containsPattern(Pattern pattern) {
    if (pattern is RegExp) return pattern.hasMatch(this);
    return this.contains(pattern);
  }
}
