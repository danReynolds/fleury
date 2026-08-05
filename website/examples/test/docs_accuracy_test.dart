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
      // RFC 0018 renamed KeyChord to KeySequence and made `onTrigger` the
      // common handler; `onEvent` survives only on `KeyBinding.event`. The
      // compiling mirrors in doc_snippets/ were swept, but prose fences are
      // hand-copied, so they silently kept teaching the removed API. Match
      // `KeyBinding(` specifically — `KeyBinding(…, onTrigger:)` is
      // correct and must keep passing.
      //
      // `[^)]` (newlines allowed, via dotAll on the argument run) catches the
      // wrapped form too, which is how docs usually write a binding with a
      // label:
      //
      //     KeyBinding(
      //       KeySequence.ctrl.s,
      //       onTrigger: (_) => save(),   // ← still caught
      //     )
      final defaultCtorOnEvent = RegExp(
        r'KeyBinding\([^)]*onTrigger:',
        dotAll: true,
      );
      final rawStringSemanticId = RegExp(
        r'''Semantics\s*\(\s*id:\s*(?:const\s+)?['"]''',
      );

      for (final file in files) {
        final text = file.readAsStringSync();
        for (final (label, pattern) in <(String, Pattern)>[
          ('hard-coded package test count', hardCodedPackageTests),
          ('consumer import from package src', privatePackageImport),
          ('nonexistent `fleury mcp` command', 'fleury mcp'),
          ('removed KeyChord type (now KeySequence)', 'KeyChord'),
          (
            'onEvent on the default KeyBinding constructor (use onTrigger, '
                'or KeyBinding.event)',
            defaultCtorOnEvent,
          ),
          (
            'raw String passed as Semantics.id (use SemanticNodeId)',
            rawStringSemanticId,
          ),
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
          ('unowned Fleury domain', 'fleury.dev'),
          ('obsolete scaffold entrypoint', 'bin/my_app.dart'),
          ('obsolete root scaffold entrypoint', 'dart run my_app.dart'),
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

    test('fleury_web README embeds the compile-checked mountApp example', () {
      final readme = File(
        p.join(repo.path, 'packages/fleury_web/README.md'),
      ).readAsStringSync();
      final compiledSnippet = File(
        p.join(repo.path, 'website/examples/doc_snippets/web_app_shell.dart'),
      ).readAsStringSync();
      final firstImport = compiledSnippet.indexOf(
        "import 'package:fleury/fleury_core.dart';",
      );

      expect(firstImport, isNonNegative);
      expect(
        _firstDartFence(readme).trim(),
        compiledSnippet.substring(firstImport).trim(),
      );
    });

    test('agent guide uses typed semantic ids in inline examples', () {
      final guide = File(
        p.join(
          repo.path,
          'website/src/content/docs/guides/driving-with-agents.md',
        ),
      ).readAsStringSync();
      final compiledSnippet = File(
        p.join(
          repo.path,
          'website/examples/doc_snippets/semantic_actions.dart',
        ),
      ).readAsStringSync();

      expect(
        guide,
        contains("Semantics(id: const SemanticNodeId('submit'), …)"),
      );
      expect(
        RegExp(r'''Semantics\s*\(\s*id:\s*(?:const\s+)?['"]''').hasMatch(guide),
        isFalse,
      );
      expect(compiledSnippet, contains("id: SemanticNodeId('save')"));
    });

    test('fleury_mcp README matches its publishable package boundary', () {
      final readme = File(
        p.join(repo.path, 'packages/fleury_mcp/README.md'),
      ).readAsStringSync();

      expect(readme, contains('fleury: 0.1.0'));
      expect(readme, contains('pubspec_overrides.yaml'));
      expect(readme, isNot(contains('publish_to: none')));
      expect(readme, isNot(contains('path dependency on')));
    });

    test('getting started follows the generated project contract', () {
      final guide = File(
        p.join(repo.path, 'website/src/content/docs/getting-started.mdx'),
      ).readAsStringSync();
      expect(guide, contains('fleury create my_app --dependency-source=git'));
      expect(guide, contains('fleury create my_app'));
      expect(guide, contains('dart run bin/run_app.dart'));
      expect(guide, contains('title="lib/app.dart"'));
      expect(guide, contains('title="test/app_test.dart"'));
      expect(guide, contains('class MyApp extends StatelessWidget'));
      expect(
        guide,
        contains("Change the test expectation from `uptime: 0s` to `CPU`"),
      );
      expect(guide, isNot(contains('dart create my_app')));
      expect(guide, isNot(contains('title="bin/my_app.dart"')));

      expect(guide, contains('path: packages/fleury_web'));
      expect(guide, contains('web: ^1.1.1'));
      expect(guide, contains('title="lib/status_app.dart"'));
      expect(guide, contains("package:my_app/status_app.dart"));
    });

    test('testing guide uses the current Git package boundary', () {
      final guide = File(
        p.join(repo.path, 'website/src/content/docs/guides/testing.md'),
      ).readAsStringSync();
      expect(guide, contains('path: packages/fleury_test'));
      expect(guide, contains('fleury_test: ^0.1.0'));
      expect(guide, contains('After the packages are published together'));
    });

    test('layout guidance preserves cell width-over-height semantics', () {
      final basic = File(
        p.join(repo.path, 'packages/fleury/lib/src/widgets/basic.dart'),
      ).readAsStringSync();
      final layout = File(
        p.join(repo.path, 'website/src/content/docs/guides/layout.md'),
      ).readAsStringSync();
      final flutter = File(
        p.join(repo.path, 'website/src/content/docs/coming-from-flutter.md'),
      ).readAsStringSync();

      expect(basic, contains('AspectRatio(aspectRatio: 2.0, ...)'));
      expect(basic, isNot(contains('AspectRatio(aspectRatio: 0.5, ...)')));
      expect(layout, contains('`aspectRatio: 2.0` reads as visually square'));
      expect(flutter, contains('`AspectRatio` around `2.0`'));
      expect(basic, isNot(contains('fill the rest of this row/column')));
      expect(basic, contains('use [Expanded] or [Flexible]'));
    });

    test('serve docs describe semantics as a separate change stream', () {
      final guide = File(
        p.join(repo.path, 'docs/serving-and-embedding.md'),
      ).readAsStringSync();
      expect(guide, contains('semantic updates are diffed and sent'));
      expect(guide, contains('when the exposed tree or its painted coverage'));
      expect(guide, isNot(contains('cell-diff + semantics frames')));
    });

    test('hot-reload guidance requires a real VM source reload', () {
      final surfaces = <File>[
        File(p.join(repo.path, 'packages/fleury/doc/hot_reload.md')),
        File(p.join(repo.path, 'packages/fleury/example/hot_reload_demo.dart')),
        File(p.join(repo.path, 'packages/fleury/example/counter_demo.dart')),
      ];
      final combined = surfaces.map((file) => file.readAsStringSync()).join();

      expect(combined, contains('reloadSources'));
      expect(combined, isNot(contains('kill -SIGUSR1')));
      expect(combined, isNot(contains('package:hotreloader')));
      expect(combined, isNot(contains('dart pub global activate hotreloader')));
    });

    test('shipped Fleury examples do not link the unowned domain', () {
      final surfaces = <File>[
        File(p.join(repo.path, 'packages/storybook/lib/src/catalog.dart')),
        File(
          p.join(
            repo.path,
            'packages/fleury_example_console/lib/fleury_example_console.dart',
          ),
        ),
        File(p.join(repo.path, 'packages/samples/bin/osc8_demo_app.dart')),
        File(
          p.join(
            repo.path,
            'packages/fleury/lib/src/foundation/fleury_error.dart',
          ),
        ),
      ];
      for (final surface in surfaces) {
        final source = surface.readAsStringSync();
        expect(
          source,
          isNot(contains('fleury.dev')),
          reason: p.relative(surface.path, from: repo.path),
        );
      }
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
    File(p.join(repo.path, 'packages/fleury_test/README.md')),
    File(p.join(repo.path, 'packages/fleury_themes/README.md')),
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

String _firstDartFence(String markdown) {
  final match = RegExp(r'```dart[^\n]*\n([\s\S]*?)\n```').firstMatch(markdown);
  if (match == null) {
    throw StateError('No Dart code fence found.');
  }
  return match.group(1)!;
}

extension on String {
  bool containsPattern(Pattern pattern) {
    if (pattern is RegExp) return pattern.hasMatch(this);
    return this.contains(pattern);
  }
}
