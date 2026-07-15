// Round-trip and fuzz tests for the structured serve frames (PLAN,
// SEMANTICS, INPUT_EVENT). The PLAN tests cover the cell-patch wire: a
// build from prev/next, encode/decode, and apply-to-mirror reproducing
// the source frame. Property tests seed a fixed RNG; the fuzz block feeds
// malformed payloads and asserts clean rejection.

import 'dart:math';
import 'dart:typed_data';

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('PLAN frame round-trip', () {
    test('hand-built plan with styled runs survives the wire', () {
      final plan = RemotePlan(
        size: const CellSize(80, 24),
        fullRepaint: true,
        styleTable: const [
          CellStyle.empty,
          CellStyle(foreground: RgbColor(200, 100, 50), bold: true),
          CellStyle(foreground: IndexedColor(120)),
        ],
        patches: const [
          RemoteRowPatch(
            row: 0,
            startCol: 0,
            runs: [
              RemotePatchRun(styleIndex: 1, text: 'hello'),
              RemotePatchRun(styleIndex: 2, text: '世'),
              RemotePatchRun(styleIndex: 0, text: '  '),
            ],
          ),
        ],
      );
      final decoded = decodeRemotePlan(encodeRemotePlan(plan));
      expect(decoded.size, plan.size);
      expect(decoded.fullRepaint, isTrue);
      expect(decoded.scrollUpRows, isNull);
      expect(decoded.styleTable, plan.styleTable);
      expect(decoded.patches, hasLength(1));
      final patch = decoded.patches.single;
      expect(patch.row, 0);
      expect(patch.runs.map((r) => r.text).toList(), ['hello', '世', '  ']);
      expect(patch.runs.map((r) => r.styleIndex).toList(), [1, 2, 0]);
    });

    test('scroll-up plan carries the shift', () {
      final plan = RemotePlan(
        size: const CellSize(40, 12),
        fullRepaint: false,
        scrollUpRows: 3,
        styleTable: const [],
        patches: const [],
      );
      final decoded = decodeRemotePlan(encodeRemotePlan(plan));
      expect(decoded.scrollUpRows, 3);
      expect(decoded.patches, isEmpty);
    });

    test(
      'build -> encode -> decode -> apply reproduces the frame (seeded)',
      () {
        final rng = Random(0x5EED);
        const alphabet = 'abcdefgh 0123#@世界';
        for (var iter = 0; iter < 200; iter++) {
          final cols = 4 + rng.nextInt(40);
          final rows = 1 + rng.nextInt(12);
          final prev = CellBuffer(CellSize(cols, rows));
          final next = CellBuffer(CellSize(cols, rows));
          // Seed prev with some content, then mutate into next.
          for (var r = 0; r < rows; r++) {
            final text = _randomText(rng, alphabet, cols);
            prev.writeText(CellOffset(0, r), text, style: _randomStyle(rng));
          }
          _copyBuffer(prev, next);
          // Mutate a few rows.
          for (var m = 0; m < rng.nextInt(rows + 1); m++) {
            final r = rng.nextInt(rows);
            final text = _randomText(rng, alphabet, cols);
            next.writeText(CellOffset(0, r), text, style: _randomStyle(rng));
          }
          final full = rng.nextInt(5) == 0;
          final plan = buildRemotePlan(prev, next, fullRepaint: full);
          final decoded = decodeRemotePlan(encodeRemotePlan(plan));
          // Apply to a mirror seeded with prev.
          final mirror = CellBuffer(CellSize(cols, rows));
          _copyBuffer(prev, mirror);
          applyRemotePlanToBuffer(decoded, mirror);
          // The mirror's rendered content must match next.
          expect(
            _renderAll(mirror),
            _renderAll(next),
            reason: 'iter $iter (full=$full)',
          );
        }
      },
    );
  });

  group('OSC 8 link carriage (v4 spare-set-mask-bit)', () {
    test('a linked style round-trips losslessly under includeLinks', () {
      final plan = RemotePlan(
        size: const CellSize(6, 1),
        fullRepaint: true,
        includeLinks: true,
        styleTable: const [
          CellStyle(
            foreground: RgbColor(1, 2, 3),
            underline: true,
            linkUri: 'https://example.com/a?b=c',
          ),
        ],
        patches: const [
          RemoteRowPatch(
            row: 0,
            startCol: 0,
            runs: [RemotePatchRun(styleIndex: 0, text: 'link!')],
          ),
        ],
      );
      final decoded = decodeRemotePlan(encodeRemotePlan(plan));
      final style = decoded.styleTable.single;
      expect(style.linkUri, 'https://example.com/a?b=c');
      // The link rides beside the visual style, which is preserved intact.
      expect(style.foreground, const RgbColor(1, 2, 3));
      expect(style.underline, isTrue);
      // Client mirror round-trip: applyRemotePlanToBuffer writes the decoded
      // style straight into the mirror, so linkUri reaches it with no extra
      // plumbing (RFC 0017 §5, the browser mirror source).
      final mirror = CellBuffer(const CellSize(6, 1));
      applyRemotePlanToBuffer(decoded, mirror);
      expect(mirror.atColRow(0, 0).style.linkUri, 'https://example.com/a?b=c');
    });

    test('a link-free plan encodes to the exact v3 golden bytes', () {
      // Pins the v3 cell-style layout: [setMask][valMask][fg][bg] with no link
      // bytes. A link-free frame under v4 must reproduce this byte for byte
      // (the spare bit stays clear, no URI is appended).
      final plan = RemotePlan(
        size: const CellSize(4, 1),
        fullRepaint: true,
        styleTable: const [CellStyle(bold: true)],
        patches: const [
          RemoteRowPatch(
            row: 0,
            startCol: 0,
            runs: [RemotePatchRun(styleIndex: 0, text: 'hi')],
          ),
        ],
      );
      expect(encodeRemotePlan(plan), [
        1, // flags: fullRepaint
        4, // cols
        1, // rows
        1, // styleCount
        1, // setMask: bit 0 (bold) — bit 6 (link) CLEAR
        1, // valMask: bold = true
        0, // fg: null
        0, // bg: null
        1, // patchCount
        0, // patch row
        0, // patch startCol
        1, // runCount
        0, // run styleIndex
        2, // run text length (varint)
        104, 105, // 'hi'
        0, // placementCount
      ]);
    });

    test('includeLinks:false is byte-identical to the same plan link-stripped',
        () {
      // The version-gate invariant at the codec level: a plan carrying links,
      // encoded for a pre-v4 peer, is byte-for-byte identical to the same plan
      // (same table cardinality, same runs) with the links removed. Two styles
      // that differ only by linkUri stay DISTINCT table entries (Stage 1 made
      // == link-aware) but encode to identical bytes when links are off — mild
      // waste, never corruption.
      RemotePlan planWith(List<CellStyle> styles) => RemotePlan(
        size: const CellSize(8, 1),
        fullRepaint: true,
        includeLinks: false,
        styleTable: styles,
        patches: const [
          RemoteRowPatch(
            row: 0,
            startCol: 0,
            runs: [
              RemotePatchRun(styleIndex: 0, text: 'aa'),
              RemotePatchRun(styleIndex: 1, text: 'bb'),
            ],
          ),
        ],
      );
      final linked = planWith(const [
        CellStyle(bold: true, linkUri: 'https://a'),
        CellStyle(italic: true, linkUri: 'https://b'),
      ]);
      final stripped = planWith(const [
        CellStyle(bold: true),
        CellStyle(italic: true),
      ]);
      expect(encodeRemotePlan(linked), encodeRemotePlan(stripped));
    });

    test('a plan built for a v3 peer emits no link bytes (the crux)', () {
      // buildRemotePlan(includeLinks: false) is what presentFrame hands a
      // pre-v4 peer. Even when a cell carries a link, the encoded plan must be
      // byte-identical to the link-free build — otherwise a stale v3 decoder
      // misaligns on the unexpected URI and loses stream framing. The bold
      // attribute makes the linked and stripped buffers split into the same
      // runs, so any byte difference is the link bytes alone.
      final prev = CellBuffer(const CellSize(2, 1));
      final nextLinked = CellBuffer(const CellSize(2, 1))
        ..writeText(
          const CellOffset(0, 0),
          'hi',
          style: const CellStyle(bold: true, linkUri: 'https://x'),
        );
      final nextStripped = CellBuffer(const CellSize(2, 1))
        ..writeText(
          const CellOffset(0, 0),
          'hi',
          style: const CellStyle(bold: true),
        );

      final v3 = encodeRemotePlan(
        buildRemotePlan(prev, nextLinked, fullRepaint: true),
      );
      final linkless = encodeRemotePlan(
        buildRemotePlan(prev, nextStripped, fullRepaint: true),
      );
      expect(
        v3,
        linkless,
        reason: 'includeLinks defaults false: a v3 peer sees no link bytes',
      );

      // And a v4 peer DOES carry the link, so the bytes must differ — proving
      // the gate is what suppresses them, not that the link never encodes.
      final v4 = encodeRemotePlan(
        buildRemotePlan(prev, nextLinked, fullRepaint: true, includeLinks: true),
      );
      expect(v4, isNot(linkless));
      final mirror = CellBuffer(const CellSize(2, 1));
      applyRemotePlanToBuffer(decodeRemotePlan(v4), mirror);
      expect(mirror.atColRow(0, 0).style.linkUri, 'https://x');
    });

    test('a malformed/oversized link length is rejected, never crashes', () {
      // bit 6 set but the URI varint length overruns the payload: the reader's
      // _need guard turns it into a RemoteCodecException, the same clean
      // rejection every other truncated field gets.
      final truncated = Uint8List.fromList([
        0, // flags
        1, // cols
        1, // rows
        1, // styleCount
        0x40, // setMask: bit 6 (has link)
        0, // valMask
        5, // link length = 5, but only one byte follows
        0x68, // 'h'
      ]);
      expect(
        () => decodeRemotePlan(truncated),
        throwsA(isA<RemoteCodecException>()),
      );

      // A link length varint that would exceed the signed-31-bit bound is
      // caught by the varint range guard before any read is attempted.
      final oversized = Uint8List.fromList([
        0, 1, 1, 1, // flags, cols, rows, styleCount
        0x40, 0, // setMask bit 6, valMask
        0xFF, 0xFF, 0xFF, 0xFF, 0x0F, // link length varint out of range
      ]);
      expect(
        () => decodeRemotePlan(oversized),
        throwsA(isA<RemoteCodecException>()),
      );
    });
  });

  group('bounded plan build (dirtyRows damage hint)', () {
    // The contract under test: given SOUND damage (dirtyRows covers every
    // cell that differs between prev and next — the invariant the planner's
    // FramePresentationDamage carries and AnsiRenderer.renderDiff already
    // trusts), the bounded build must produce byte-identical encoded plans
    // to the unbounded build. Rows outside sound damage are equal, so
    // skipping them can drop no patch from a plain diff. Scroll detection
    // must stay exact under ANY sound damage: the rows a scrolling frame
    // leaves untouched (blank tails, static chrome) are often
    // shift-invariant, so beneficial scrolls DO fire under partial damage —
    // and a detected scroll must patch residually across every row, since
    // the mirror shift moves damage onto rows the frame diff never marked.
    Uint8List bytesFor(
      CellBuffer prev,
      CellBuffer next, {
      bool fullRepaint = false,
      TuiDirtyRows? dirtyRows,
    }) => encodeRemotePlan(
      buildRemotePlan(
        prev,
        next,
        fullRepaint: fullRepaint,
        dirtyRows: dirtyRows,
      ),
    );

    test('sound damage yields byte-identical plans (seeded property)', () {
      final rng = Random(0xB07DED);
      const alphabet = 'abcdefgh 0123#@世界';
      for (var iter = 0; iter < 300; iter++) {
        final cols = 4 + rng.nextInt(40);
        final rows = 1 + rng.nextInt(14);
        final prev = CellBuffer(CellSize(cols, rows));
        final next = CellBuffer(CellSize(cols, rows));
        for (var r = 0; r < rows; r++) {
          prev.writeText(
            CellOffset(0, r),
            _randomText(rng, alphabet, cols),
            style: _randomStyle(rng),
          );
        }
        _copyBuffer(prev, next);
        // 0..3 random styled edits at random offsets (0 edits: empty diff).
        for (var m = 0; m < rng.nextInt(4); m++) {
          final r = rng.nextInt(rows);
          final c = rng.nextInt(cols);
          next.writeText(
            CellOffset(c, r),
            _randomText(rng, alphabet, cols - c),
            style: _randomStyle(rng),
          );
        }
        final truth = _trueDirtyRows(prev, next);
        final expected = bytesFor(prev, next);

        // Sound damage variants: the exact changed-row set, the same set
        // padded with extra clean rows, and full damage.
        final padded = {...truth, rng.nextInt(rows), rng.nextInt(rows)};
        final variants = <String, TuiDirtyRows>{
          'exact': TuiDirtyRows.fromRows(truth, rowCount: rows),
          'padded': TuiDirtyRows.fromRows(padded, rowCount: rows),
          'full': TuiDirtyRows.full(rows),
        };
        variants.forEach((name, damage) {
          expect(
            bytesFor(prev, next, dirtyRows: damage),
            expected,
            reason: 'iter $iter, $name damage (true dirty rows: $truth)',
          );
        });
      }
    });

    test('single-row edit under exact single-range damage', () {
      final prev = CellBuffer(const CellSize(20, 6));
      final next = CellBuffer(const CellSize(20, 6));
      for (var r = 0; r < 6; r++) {
        prev.writeText(CellOffset(0, r), 'row $r content');
      }
      _copyBuffer(prev, next);
      next.writeText(
        const CellOffset(4, 3),
        'edited',
        style: const CellStyle(bold: true),
      );
      final expected = bytesFor(prev, next);
      final damage = TuiDirtyRows.range(3, 4, rowCount: 6);
      expect(bytesFor(prev, next, dirtyRows: damage), expected);
      final decoded = decodeRemotePlan(bytesFor(prev, next, dirtyRows: damage));
      expect(decoded.patches.map((p) => p.row).toList(), [3]);
    });

    test('multi-range damage with edits on the range borders', () {
      final prev = CellBuffer(const CellSize(16, 12));
      final next = CellBuffer(const CellSize(16, 12));
      for (var r = 0; r < 12; r++) {
        prev.writeText(CellOffset(0, r), 'line $r ........');
      }
      _copyBuffer(prev, next);
      // Edits at the buffer borders (rows 0, 11) and an adjacent pair
      // (rows 5, 6) that collapses into one range.
      for (final r in const [0, 5, 6, 11]) {
        next.writeText(
          CellOffset(0, r),
          'CHANGED $r',
          style: const CellStyle(italic: true),
        );
      }
      final damage = TuiDirtyRows.fromRows(const [0, 5, 6, 11], rowCount: 12);
      expect(
        damage.ranges.length,
        3,
        reason: 'fromRows collapses adjacent rows into multi-range damage',
      );
      final expected = bytesFor(prev, next);
      expect(bytesFor(prev, next, dirtyRows: damage), expected);
      // Padded with extra clean rows around each range border.
      final paddedDamage = TuiDirtyRows.fromRows(const [
        0,
        1,
        4,
        5,
        6,
        7,
        10,
        11,
      ], rowCount: 12);
      expect(bytesFor(prev, next, dirtyRows: paddedDamage), expected);
    });

    test('empty diff builds an empty plan under any sound damage', () {
      final prev = CellBuffer(const CellSize(10, 5));
      final next = CellBuffer(const CellSize(10, 5));
      for (var r = 0; r < 5; r++) {
        prev.writeText(CellOffset(0, r), 'same $r');
      }
      _copyBuffer(prev, next);
      final expected = bytesFor(prev, next);
      // No cell changed, so ANY damage is sound — including none and rows
      // that are actually clean.
      for (final damage in [
        const TuiDirtyRows.none(),
        TuiDirtyRows.fromRows(const [2], rowCount: 5),
        TuiDirtyRows.full(5),
      ]) {
        expect(bytesFor(prev, next, dirtyRows: damage), expected);
      }
      expect(decodeRemotePlan(expected).patches, isEmpty);
    });

    test('fullRepaint and size-change frames ignore the hint', () {
      final prev = CellBuffer(const CellSize(10, 4));
      final next = CellBuffer(const CellSize(10, 4));
      next.writeText(const CellOffset(0, 1), 'repainted');
      final partial = TuiDirtyRows.fromRows(const [1], rowCount: 4);
      // Full repaint: every row ships regardless of the hint.
      expect(
        bytesFor(prev, next, fullRepaint: true, dirtyRows: partial),
        bytesFor(prev, next, fullRepaint: true),
      );
      expect(
        decodeRemotePlan(
          bytesFor(prev, next, fullRepaint: true, dirtyRows: partial),
        ).patches.map((p) => p.row),
        [0, 1, 2, 3],
      );
      // Size change implies full: the hint is ignored the same way.
      final grown = CellBuffer(const CellSize(12, 5));
      grown.writeText(const CellOffset(0, 1), 'resized');
      expect(
        bytesFor(
          prev,
          grown,
          dirtyRows: TuiDirtyRows.fromRows(const [1], rowCount: 5),
        ),
        bytesFor(prev, grown),
      );
      expect(
        decodeRemotePlan(bytesFor(prev, grown)).fullRepaint,
        isTrue,
        reason: 'a size change is a full repaint on the wire',
      );
    });

    test('a full-screen scroll under full damage still detects the shift', () {
      const cols = 20;
      const rows = 8;
      final prev = CellBuffer(const CellSize(cols, rows));
      final next = CellBuffer(const CellSize(cols, rows));
      String rowText(int i) =>
          String.fromCharCode('a'.codeUnitAt(0) + i) * cols;
      for (var r = 0; r < rows; r++) {
        prev.writeText(CellOffset(0, r), rowText(r));
      }
      // next is prev scrolled up one row, with a new line entering at the
      // bottom — every row changes, so sound damage IS full damage.
      for (var r = 0; r < rows; r++) {
        next.writeText(CellOffset(0, r), rowText(r + 1));
      }
      expect(_trueDirtyRows(prev, next), {for (var r = 0; r < rows; r++) r});
      final expected = bytesFor(prev, next);
      final bounded = bytesFor(prev, next, dirtyRows: TuiDirtyRows.full(rows));
      expect(bounded, expected);
      final decoded = decodeRemotePlan(bounded);
      expect(
        decoded.scrollUpRows,
        1,
        reason: 'full damage keeps scroll detection running',
      );
      expect(
        decoded.patches.map((p) => p.row).toSet(),
        {rows - 1},
        reason: 'residual patches cover only the entering row',
      );
    });

    test('a scroll under sound PARTIAL damage keeps detection and patches '
        'the clean rows the mirror shift disturbs', () {
      // The serve-wire-live regression shape: a scrolling log whose blank
      // tail and static footer do not change, so sound damage is partial —
      // yet the scroll is beneficial (the untouched rows are exactly the
      // shift-invariant ones). Detection must still fire, and the residual
      // walk must cover rows OUTSIDE the damage: after the mirror shifts,
      // the clean footer sits over moved content and needs re-patching.
      const cols = 12;
      const rows = 10;
      final prev = CellBuffer(const CellSize(cols, rows));
      final next = CellBuffer(const CellSize(cols, rows));
      String line(int i) => String.fromCharCode('a'.codeUnitAt(0) + i) * cols;
      // prev: log lines 0..7 at rows 0..7, row 8 blank, footer at row 9.
      for (var r = 0; r < 8; r++) {
        prev.writeText(CellOffset(0, r), line(r));
      }
      prev.writeText(const CellOffset(0, 9), 'FOOT');
      // next: the log scrolled up one line; blank row and footer unchanged.
      for (var r = 0; r < 8; r++) {
        next.writeText(CellOffset(0, r), line(r + 1));
      }
      next.writeText(const CellOffset(0, 9), 'FOOT');
      expect(
        _trueDirtyRows(prev, next),
        {0, 1, 2, 3, 4, 5, 6, 7},
        reason: 'the blank tail and footer are clean: damage is partial',
      );
      final damage = TuiDirtyRows.range(0, 8, rowCount: rows);
      expect(damage.isFull, isFalse);
      final expected = bytesFor(prev, next);
      final bounded = bytesFor(prev, next, dirtyRows: damage);
      expect(bounded, expected);
      final decoded = decodeRemotePlan(bounded);
      expect(
        decoded.scrollUpRows,
        1,
        reason: 'partial sound damage must not lose the beneficial scroll',
      );
      expect(
        decoded.patches.map((p) => p.row).toSet(),
        containsAll(<int>{8, 9}),
        reason:
            'the shift moved content under the clean rows; they must be '
            're-patched even though the frame diff never touched them',
      );
      // Applying the plan to a prev-seeded mirror reproduces the frame.
      final mirror = CellBuffer(const CellSize(cols, rows));
      _copyBuffer(prev, mirror);
      applyRemotePlanToBuffer(decoded, mirror);
      expect(_renderAll(mirror), _renderAll(next));
    });

    test(
      'scrolling frames under sound damage stay byte-identical (seeded)',
      () {
        final rng = Random(0x5C2011);
        const alphabet = 'abcdefghijklmnopqrstuvwxyz';
        for (var iter = 0; iter < 150; iter++) {
          final cols = 6 + rng.nextInt(30);
          final rows = 4 + rng.nextInt(12);
          // A virtual line stream: line i is full-width and distinct from
          // its neighbors, like a scrolling log.
          String line(int i) =>
              '$i ${alphabet[i % alphabet.length] * (cols - 2 - '$i'.length)}';
          final hasHeader = rng.nextInt(4) == 0;
          final hasFooter = rng.nextBool();
          final top = hasHeader ? 1 : 0;
          final maxLog = rows - top - (hasFooter ? 1 : 0);
          final fill = 2 + rng.nextInt(maxLog - 1); // log rows, maybe < region
          final shift = 1 + rng.nextInt(fill - 1); // scroll amount < fill
          final prev = CellBuffer(CellSize(cols, rows));
          final next = CellBuffer(CellSize(cols, rows));
          for (final (buffer, base) in [(prev, 0), (next, shift)]) {
            if (hasHeader) buffer.writeText(const CellOffset(0, 0), 'HEADER');
            for (var r = 0; r < fill; r++) {
              buffer.writeText(CellOffset(0, top + r), line(base + r));
            }
            if (hasFooter) {
              buffer.writeText(CellOffset(0, rows - 1), 'footer bar');
            }
          }
          final truth = _trueDirtyRows(prev, next);
          final expected = bytesFor(prev, next);
          final exact = TuiDirtyRows.fromRows(truth, rowCount: rows);
          final padded = TuiDirtyRows.fromRows({
            ...truth,
            rng.nextInt(rows),
          }, rowCount: rows);
          for (final (name, damage) in [('exact', exact), ('padded', padded)]) {
            final bounded = bytesFor(prev, next, dirtyRows: damage);
            expect(
              bounded,
              expected,
              reason:
                  'iter $iter, $name damage (header=$hasHeader, '
                  'footer=$hasFooter, fill=$fill, shift=$shift, rows=$rows)',
            );
          }
          // Whatever the plan decided, it must reproduce the frame.
          final decoded = decodeRemotePlan(
            bytesFor(prev, next, dirtyRows: exact),
          );
          final mirror = CellBuffer(CellSize(cols, rows));
          _copyBuffer(prev, mirror);
          applyRemotePlanToBuffer(decoded, mirror);
          expect(
            _renderAll(mirror),
            _renderAll(next),
            reason: 'iter $iter: bounded plan must reproduce the frame',
          );
        }
      },
    );

    test('a static image placement survives a bounded steady-state frame', () {
      final imageBytes = Uint8List.fromList([9, 9, 9, 9]);
      final prev = CellBuffer(const CellSize(12, 6))
        ..writeImage(const CellOffset(1, 1), imageBytes, width: 2, height: 2);
      final next = CellBuffer(const CellSize(12, 6))
        ..writeImage(const CellOffset(1, 1), imageBytes, width: 2, height: 2);
      for (var r = 0; r < 6; r++) {
        prev.writeText(CellOffset(6, r), 'txt $r');
        next.writeText(CellOffset(6, r), 'txt $r');
      }
      next.writeText(const CellOffset(6, 4), 'TXT 4');
      // Only the text row changed; the unchanged image rows sit outside
      // the damage. Placements are read from the full per-frame list, not
      // the diff, so the bounded plan must still carry the placement.
      final damage = TuiDirtyRows.fromRows(const [4], rowCount: 6);
      final expected = bytesFor(prev, next);
      final bounded = bytesFor(prev, next, dirtyRows: damage);
      expect(bounded, expected);
      expect(decodeRemotePlan(bounded).placements, hasLength(1));
    });

    test('an empty hint on a clean frame skips detection but stays '
        'byte-identical, even with scroll-candidate content', () {
      // Every row identical: the scroll prefilter WOULD find candidates,
      // but an empty (non-full) hint asserts zero dirty cells, so the
      // early-out skips detection entirely. The unbounded build runs the
      // detector and finds nothing beneficial (zero dirty cells to beat),
      // so the plans must still match byte for byte.
      final prev = CellBuffer(const CellSize(10, 5));
      final next = CellBuffer(const CellSize(10, 5));
      for (var r = 0; r < 5; r++) {
        prev.writeText(CellOffset(0, r), 'same line');
        next.writeText(CellOffset(0, r), 'same line');
      }
      final bounded = bytesFor(
        prev,
        next,
        dirtyRows: const TuiDirtyRows.none(),
      );
      expect(bounded, bytesFor(prev, next));
      expect(decodeRemotePlan(bounded).patches, isEmpty);
      expect(decodeRemotePlan(bounded).scrollUpRows, isNull);
    });

    group('debug contract (asserts enabled under dart test)', () {
      test('the oracle trips on damage that under-covers the diff', () {
        final prev = CellBuffer(const CellSize(8, 3));
        final next = CellBuffer(const CellSize(8, 3));
        next.writeText(const CellOffset(0, 1), 'hi');
        // Damage claims only row 2 changed; the truth is row 1. The bounded
        // build would silently drop the row-1 patch and desync the peer's
        // mirror — the debug oracle (an unbounded rebuild compared byte for
        // byte, the same shape as the semantics encoder's oracle) must make
        // that loud instead.
        expect(
          () => buildRemotePlan(
            prev,
            next,
            fullRepaint: false,
            dirtyRows: TuiDirtyRows.fromRows(const [2], rowCount: 3),
          ),
          throwsA(
            isA<AssertionError>().having(
              (e) => e.message,
              'message',
              contains('under-covers'),
            ),
          ),
        );
      });

      test('an isFull hint built against a smaller row count is rejected', () {
        final prev = CellBuffer(const CellSize(8, 3));
        final next = CellBuffer(const CellSize(8, 3));
        next.writeText(const CellOffset(0, 2), 'tail');
        // full(2) claims full coverage but its single range stops short of
        // next's 3 rows — the tail row would be silently skipped while
        // isFull suppresses the scroll prefilter. Unreachable from the
        // runtime planner (it builds damage against frame.next.size); the
        // consistency assert is the first-line defense for other producers.
        expect(
          () => buildRemotePlan(
            prev,
            next,
            fullRepaint: false,
            dirtyRows: TuiDirtyRows.full(2),
          ),
          throwsA(
            isA<AssertionError>().having(
              (e) => e.message,
              'message',
              contains('does not cover every row'),
            ),
          ),
        );
      });

      test('sound damage never trips the oracle (spot check)', () {
        final prev = CellBuffer(const CellSize(8, 3));
        final next = CellBuffer(const CellSize(8, 3));
        next.writeText(const CellOffset(0, 1), 'hi');
        final plan = buildRemotePlan(
          prev,
          next,
          fullRepaint: false,
          dirtyRows: TuiDirtyRows.fromRows(const [1], rowCount: 3),
        );
        expect(plan.patches.map((p) => p.row).toList(), [1]);
      });
    });
  });

  group('INPUT_EVENT round-trip', () {
    test('key event with code, char, modifiers, type', () {
      const event = KeyEvent(
        keyCode: KeyCode.arrowDown,
        char: 'c',
        modifiers: {KeyModifier.ctrl, KeyModifier.shift},
        type: KeyEventType.repeat,
      );
      final decoded = decodeInputEvent(encodeInputEvent(event)) as KeyEvent;
      expect(decoded, event);
    });

    test('all carried event kinds round-trip (seeded)', () {
      final rng = Random(0xC0DEC);
      for (var iter = 0; iter < 200; iter++) {
        final event = _randomEvent(rng);
        final decoded = decodeInputEvent(encodeInputEvent(event));
        expect(decoded, event, reason: 'iter $iter: $event');
      }
    });

    test('paste, resize, and composition kinds', () {
      final events = <TuiEvent>[
        const PasteEvent('multi\nline\tpaste'),
        const ResizeEvent(CellSize(100, 30)),
        const TextCompositionEvent.update('ko'),
        const TextCompositionEvent.commit('korean'),
        const TextCompositionEvent.cancel(),
        const TextInputEvent('日本語'),
        const MouseEvent(
          kind: MouseEventKind.scrollUp,
          button: MouseButton.none,
          col: 12,
          row: 4,
        ),
      ];
      for (final event in events) {
        expect(decodeInputEvent(encodeInputEvent(event)), event);
      }
    });

    test('through the framing layer', () {
      const event = KeyEvent(keyCode: KeyCode.enter);
      final wire = encodeFrame(const InputEventFrame(event));
      final out = (FrameDecoder()..feed(wire)).drain().toList();
      expect(out, hasLength(1));
      expect((out.single as InputEventFrame).event, event);
    });
  });

  group('framing layer', () {
    test('plan frame round-trips through encode/decode framing', () {
      final prev = CellBuffer(const CellSize(20, 4));
      final next = CellBuffer(const CellSize(20, 4));
      next.writeText(const CellOffset(0, 1), 'changed');
      final plan = buildRemotePlan(prev, next, fullRepaint: false);
      final wire = encodeFrame(PlanFrame(plan));
      final out = (FrameDecoder()..feed(wire)).drain().toList();
      expect(out, hasLength(1));
      final decoded = (out.single as PlanFrame).plan;
      expect(decoded.patches.map((p) => p.row), contains(1));
    });

    test('semantics frame carries JSON bytes verbatim', () {
      final json = Uint8List.fromList('{"nodeCount":3}'.codeUnits);
      final wire = encodeFrame(SemanticsFrame(json));
      final out = (FrameDecoder()..feed(wire)).drain().toList();
      expect((out.single as SemanticsFrame).json, json);
    });

    test('INIT carries the protocol version', () {
      final wire = encodeFrame(
        const InitFrame(
          size: CellSize(80, 24),
          colorMode: ColorMode.truecolor,
          imageProtocol: ImageProtocol.halfBlock,
          tmuxPassthrough: false,
        ),
      );
      final out = (FrameDecoder()..feed(wire)).drain().toList();
      expect((out.single as InitFrame).protocolVersion, remoteProtocolVersion);
    });

    test('INIT without v defaults to protocol version 1', () {
      const body = 'cols=80,rows=24,color=truecolor,image=halfBlock,tmux=0';
      final payload = Uint8List.fromList(body.codeUnits);
      final framed = BytesBuilder()
        ..addByte(FrameType.init.code)
        ..add((ByteData(4)..setUint32(0, payload.length)).buffer.asUint8List())
        ..add(payload);
      final out = (FrameDecoder()..feed(framed.toBytes())).drain().toList();
      expect((out.single as InitFrame).protocolVersion, 1);
    });
  });

  group('malformed payload fuzz', () {
    test('truncated plan payloads throw RemoteCodecException, never hang', () {
      final prev = CellBuffer(const CellSize(30, 8));
      final next = CellBuffer(const CellSize(30, 8));
      for (var r = 0; r < 8; r++) {
        next.writeText(
          CellOffset(0, r),
          'row $r content here',
          style: const CellStyle(bold: true),
        );
      }
      final full = encodeRemotePlan(
        buildRemotePlan(prev, next, fullRepaint: true),
      );
      for (var cut = 0; cut < full.length; cut++) {
        final truncated = Uint8List.sublistView(full, 0, cut);
        expect(
          () => decodeRemotePlan(truncated),
          throwsA(isA<RemoteCodecException>()),
          reason: 'cut at $cut',
        );
      }
    });

    test('random bytes as plan/event payloads reject cleanly', () {
      final rng = Random(0xFADE);
      for (var iter = 0; iter < 500; iter++) {
        final len = rng.nextInt(64);
        final bytes = Uint8List.fromList([
          for (var i = 0; i < len; i++) rng.nextInt(256),
        ]);
        expect(() {
          try {
            decodeRemotePlan(bytes);
          } on RemoteCodecException {
            rethrow;
          }
        }, anyOf(returnsNormally, throwsA(isA<RemoteCodecException>())));
        expect(() {
          try {
            decodeInputEvent(bytes);
          } on RemoteCodecException {
            rethrow;
          }
        }, anyOf(returnsNormally, throwsA(isA<RemoteCodecException>())));
      }
    });

    test('a run referencing an out-of-range style index is rejected', () {
      // Build valid bytes, then corrupt a run's style index to a huge value
      // by hand-crafting a tiny plan with styleTable=[] but a run idx=5.
      final w = BytesBuilder()
        ..addByte(0) // flags
        ..addByte(4) // cols (varint)
        ..addByte(1) // rows
        ..addByte(0) // styleCount = 0
        ..addByte(1) // patchCount = 1
        ..addByte(0) // row
        ..addByte(0) // startCol
        ..addByte(1) // runCount
        ..addByte(5) // styleIndex = 5 (out of range)
        ..addByte(1) // text len = 1
        ..addByte(0x78); // 'x'
      expect(
        () => decodeRemotePlan(w.toBytes()),
        throwsA(isA<RemoteCodecException>()),
      );
    });

    test('plan grids above the shared allocation budget are rejected', () {
      final oversized = RemotePlan(
        size: const CellSize(2000, 1000),
        fullRepaint: false,
        styleTable: const [],
        patches: const [],
      );
      final overArea = RemotePlan(
        size: const CellSize(2000, 501),
        fullRepaint: false,
        styleTable: const [],
        patches: const [],
      );

      // The first shape is over the area cap even though both independent
      // dimensions are legal; the second makes that boundary explicit too.
      for (final plan in [oversized, overArea]) {
        expect(
          () => decodeRemotePlan(encodeRemotePlan(plan)),
          throwsA(isA<RemoteCodecException>()),
        );
      }
    });

    test('patch and image geometry outside structural bounds is rejected', () {
      final outsidePatch = RemotePlan(
        size: const CellSize(10, 4),
        fullRepaint: false,
        styleTable: const [CellStyle.empty],
        patches: const [
          RemoteRowPatch(
            row: 4,
            startCol: 0,
            runs: [RemotePatchRun(styleIndex: 0, text: 'x')],
          ),
        ],
      );
      final oversizedPlacement = RemotePlan(
        size: const CellSize(10, 4),
        fullRepaint: false,
        styleTable: const [],
        patches: const [],
        placements: const [
          ImagePlacement(id: 'image', col: 2, row: 0, cols: 9, rows: 1),
        ],
      );

      for (final plan in [outsidePatch, oversizedPlacement]) {
        expect(
          () => decodeRemotePlan(encodeRemotePlan(plan)),
          throwsA(isA<RemoteCodecException>()),
        );
      }
    });
  });
}

// ---- helpers ---------------------------------------------------------------

/// The exact set of rows containing at least one cell that differs between
/// [prev] and [next] — the ground truth sound damage must cover.
Set<int> _trueDirtyRows(CellBuffer prev, CellBuffer next) {
  final dirty = <int>{};
  for (var r = 0; r < next.size.rows; r++) {
    for (var c = 0; c < next.size.cols; c++) {
      if (prev.atColRow(c, r) != next.atColRow(c, r)) {
        dirty.add(r);
        break;
      }
    }
  }
  return dirty;
}

void _copyBuffer(CellBuffer from, CellBuffer to) {
  for (var r = 0; r < from.size.rows; r++) {
    for (var c = 0; c < from.size.cols; c++) {
      final cell = from.atColRow(c, r);
      if (cell.role == CellRole.leading && cell.grapheme != null) {
        to.writeText(CellOffset(c, r), cell.grapheme!, style: cell.style);
      }
    }
  }
}

String _renderAll(CellBuffer b) {
  final sb = StringBuffer();
  for (var r = 0; r < b.size.rows; r++) {
    for (var c = 0; c < b.size.cols; c++) {
      sb.write(b.atColRow(c, r).grapheme ?? ' ');
    }
    sb.write('\n');
  }
  return sb.toString();
}

String _randomText(Random rng, String alphabet, int maxLen) {
  final n = rng.nextInt(maxLen);
  return [
    for (var i = 0; i < n; i++) alphabet[rng.nextInt(alphabet.length)],
  ].join();
}

CellStyle _randomStyle(Random rng) {
  bool? triState() => switch (rng.nextInt(3)) {
    0 => null,
    1 => true,
    _ => false,
  };
  Color? color() => switch (rng.nextInt(4)) {
    0 => null,
    1 => AnsiColor(rng.nextInt(16)),
    2 => IndexedColor(rng.nextInt(256)),
    _ => RgbColor(rng.nextInt(256), rng.nextInt(256), rng.nextInt(256)),
  };
  return CellStyle(
    foreground: color(),
    background: color(),
    bold: triState(),
    italic: triState(),
    underline: triState(),
  );
}

TuiEvent _randomEvent(Random rng) {
  Set<KeyModifier> mods() => {
    for (final m in KeyModifier.values)
      if (rng.nextBool()) m,
  };
  switch (rng.nextInt(6)) {
    case 0:
      final hasCode = rng.nextBool();
      return KeyEvent(
        keyCode: hasCode
            ? KeyCode.values[rng.nextInt(KeyCode.values.length)]
            : null,
        char: hasCode && rng.nextBool()
            ? null
            : String.fromCharCode(97 + rng.nextInt(26)),
        modifiers: mods(),
        type: KeyEventType.values[rng.nextInt(KeyEventType.values.length)],
      );
    case 1:
      return TextInputEvent(_randomText(rng, 'abc世 \n\t', 5));
    case 2:
      return switch (rng.nextInt(3)) {
        0 => TextCompositionEvent.update(_randomText(rng, 'ko', 4)),
        1 => TextCompositionEvent.commit(
          rng.nextBool() ? _randomText(rng, 'ko', 4) : null,
        ),
        _ => const TextCompositionEvent.cancel(),
      };
    case 3:
      return MouseEvent(
        kind: MouseEventKind.values[rng.nextInt(MouseEventKind.values.length)],
        button: MouseButton.values[rng.nextInt(MouseButton.values.length)],
        col: rng.nextInt(500),
        row: rng.nextInt(200),
        modifiers: mods(),
      );
    case 4:
      return PasteEvent(_randomText(rng, 'abc \n', 6));
    default:
      return ResizeEvent(CellSize(1 + rng.nextInt(300), 1 + rng.nextInt(100)));
  }
}
