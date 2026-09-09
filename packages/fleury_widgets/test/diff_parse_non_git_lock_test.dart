// Lock tests for the two ends of the hunk-body rule.
//
// Neither the declared counts nor the open hunk can decide it alone:
//   * counts alone break an UNDERSTATED `@@ -1,1 +1,1 @@`, whose body runs
//     past the counters — those rows must stay edits;
//   * the open hunk alone breaks plain `diff -u`, which has no `diff --git`
//     line, so the next file's `---`/`+++` follow the last body line directly
//     and were read as a deletion and an addition.
// A `--- x` / `+++ y` / `@@` run settles it.
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  test('plain diff -u keeps each file separate', () {
    const source =
        '--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+new\n'
        '--- a/y\n+++ b/y\n@@ -1 +1 @@\n-old2\n+new2\n';
    final parsed = parseUnifiedDiff(source);

    final secondHeaders = parsed.rows
        .where((r) => r.text == '--- a/y' || r.text == '+++ b/y')
        .toList();
    expect(secondHeaders, hasLength(2));
    for (final row in secondHeaders) {
      expect(
        row.kind,
        DiffLineKind.fileHeader,
        reason: 'the second file\'s headers are headers, not edits',
      );
    }
    expect(parsed.additionCount, 2);
    expect(parsed.deletionCount, 2);
  });

  test('the header lookahead never fires inside a git hunk body', () {
    // A deletion of `-- x` followed by an addition of `++ y` and then the
    // next hunk header looks exactly like a file-header run. In a git diff it
    // cannot be one — `diff --git` already marked the boundary — and reading
    // it as one DELETED two real edits from the rendered diff.
    const source =
        'diff --git a/q.sql b/q.sql\n--- a/q.sql\n+++ b/q.sql\n'
        '@@ -1,3 +1,3 @@\n select 1\n--- deprecated helper\n+++ new helper\n'
        '@@ -9,1 +9,1 @@\n-x\n+y\n';
    final parsed = parseUnifiedDiff(source);

    expect(parsed.deletionCount, 2, reason: 'the SQL comment line is an edit');
    expect(parsed.additionCount, 2);
    expect(
      parsed.rows.last.oldPath,
      'q.sql',
      reason: 'and the file path is not rewritten to the comment text',
    );
  });

  test('plain diff -u gives each file its own index', () {
    const source =
        '--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+new\n'
        '--- a/y\n+++ b/y\n@@ -1 +1 @@\n-old2\n+new2\n';
    final parsed = parseUnifiedDiff(source);

    expect(
      parsed.fileCount,
      2,
      reason:
          'no `diff --git` line bumps the index here, so the header run has '
          'to — otherwise everything that groups by file merges them',
    );
    expect(parsed.rows.map((r) => r.fileIndex).toSet(), {0, 1});
  });

  test('an understated hunk keeps its extra body lines as edits', () {
    const source = '--- a/x\n+++ b/x\n@@ -1,1 +1,1 @@\n-one\n-two\n+three\n';
    final parsed = parseUnifiedDiff(source);

    expect(
      parsed.deletionCount,
      2,
      reason: 'the body runs past the declared count and stays edits',
    );
    expect(parsed.additionCount, 1);
  });

  test('a blank body line is an empty context line and advances both sides', () {
    // A context line whose single leading space was stripped in transit.
    const source =
        '--- a/z\n+++ b/z\n@@ -1,4 +1,4 @@\n alpha\n\n-beta\n+gamma\n delta\n';
    final parsed = parseUnifiedDiff(source);

    final delta = parsed.rows.firstWhere((r) => r.text == ' delta');
    expect(
      [delta.oldLine, delta.newLine],
      [4, 4],
      reason:
          'alpha=1, the blank=2, beta=3 — leaving the cursors on the blank put '
          'every later row off by one and gave two rows the same old line',
    );
    final olds = parsed.rows.map((r) => r.oldLine).whereType<int>().toList();
    expect(
      olds.toSet().length,
      olds.length,
      reason: 'no two rows claim the same old line',
    );
  });
}
