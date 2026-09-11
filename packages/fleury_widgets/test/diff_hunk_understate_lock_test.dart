// Lock test (audit 9.c): understated @@ hunk counts end the hunk body early,
// demoting real +/- / context lines to metadata. Blank mid-hunk lines clear
// hunkIndex for subsequent body rows (orphan from the containing hunk).
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

void main() {
  test('understated hunk counts keep remaining body lines as edits', () {
    const source = '''
diff --git a/f b/f
--- a/f
+++ b/f
@@ -1,1 +1,1 @@
 context1
-old
+new
 context2
''';
    final doc = parseUnifiedDiff(source);
    final kinds = doc.rows.map((r) => r.kind).toList();
    expect(
      kinds.where((k) => k == DiffLineKind.metadata),
      isEmpty,
      reason:
          'understated @@ counts must not demote remaining hunk body to metadata',
    );
    expect(doc.rows.where((r) => r.kind == DiffLineKind.deletion).length, 1);
    expect(doc.rows.where((r) => r.kind == DiffLineKind.addition).length, 1);
  });

  test('blank mid-hunk line preserves hunkIndex for following body', () {
    const source = '''
diff --git a/f b/f
--- a/f
+++ b/f
@@ -1,4 +1,4 @@
 line1
 line2

 line3
-old
+new
''';
    final doc = parseUnifiedDiff(source);
    final after = doc.rows.where(
      (r) => r.text == ' line3' || r.text == '-old' || r.text == '+new',
    );
    for (final row in after) {
      expect(
        row.hunkIndex,
        0,
        reason: '${row.text} orphaned from hunk after blank line',
      );
    }
  });
}
