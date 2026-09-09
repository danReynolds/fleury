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
