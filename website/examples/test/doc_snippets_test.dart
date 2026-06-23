@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Guards the compile-checked source behind the prose docs.
///
/// Every program under `doc_snippets/` is the real, finished code that a docs
/// page (tutorial, guide) walks through in steps. Analyzing the directory means
/// a hand-written doc can never drift to reference an API that no longer exists:
/// the moment a snippet stops compiling against the live framework, this test
/// fails. See `doc_snippets/README.md` for the convention.
void main() {
  test('doc_snippets analyze cleanly against the real API', () {
    final result = Process.runSync(
      'dart',
      const ['analyze', 'doc_snippets'],
      workingDirectory: Directory.current.path,
    );
    printOnFailure(result.stdout.toString());
    printOnFailure(result.stderr.toString());
    expect(
      result.exitCode,
      0,
      reason: 'A docs code snippet no longer compiles. Update the program under '
          'doc_snippets/ AND the prose in website/src/content/docs that mirrors '
          'it.',
    );
  });
}
