// A paste is canonicalized once, before batching.
//
// Batches applied through prepareInput sanitized each batch on its own, so a
// 2 KiB batch boundary inside an escape sequence stored one replacement glyph
// plus the tail of the sequence as literal text: an ANSI-coloured log paste
// showed stray `31m` / `[0m` fragments, and a split OSC dumped its payload.

import 'package:fleury/fleury.dart';
import '../support/harness.dart';
import 'package:test/test.dart';

void main() {
  testWidgets('an escape sequence straddling a batch boundary becomes ONE '
      'replacement glyph', (tester) {
    final ctl = TextEditingController();
    tester.pumpWidget(TextArea(controller: ctl, autofocus: true));
    // Default policy: 8 KiB threshold, 2 KiB chunks. Place ESC[31m so the
    // first batch ends inside it.
    final text = '${'a' * 2045}\x1B[31m${'b' * 7000}';
    tester.paste(text);
    for (var i = 0; i < 64 && ctl.text.length < 2045 + 1 + 7000; i++) {
      tester.pump();
    }
    expect(ctl.text, '${'a' * 2045}�${'b' * 7000}');
    expect(ctl.text, isNot(contains('31m')));
  });

  testWidgets('a single-line field canonicalizes its paste once too', (tester) {
    final ctl = TextEditingController();
    tester.pumpWidget(TextInput(controller: ctl, autofocus: true));
    final text = '${'a' * 2045}\x1B]8;;http://x\x07${'b' * 7000}';
    tester.paste(text);
    for (var i = 0; i < 64 && ctl.text.length < 2045 + 1 + 7000; i++) {
      tester.pump();
    }
    expect(ctl.text, '${'a' * 2045}�${'b' * 7000}');
    expect(ctl.text, isNot(contains('http://x')));
  });
}
