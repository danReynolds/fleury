@TestOn('browser')
library;

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/dom_grid/dom_row_factory.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

/// Builds a buffer and paints [paint] into it with the real width resolver and
/// grapheme segmentation, then renders row 0 through the live [DomRowFactory]
/// into a detached container so the resulting DOM can be queried — the exact
/// state the serve/embed client's `CellBuffer` mirror reaches once the wire
/// codec delivers `linkUri`.
web.Element _render(int cols, void Function(CellBuffer b) paint) {
  final buffer = CellBuffer(CellSize(cols, 1));
  paint(buffer);
  final row = const CellSpanBuilder().buildRow(buffer, 0);
  final root = web.document.createElement('div');
  DomRowFactory().replaceChildren(root, row, null);
  return root;
}

void main() {
  group('DomRowFactory style cache bounds', () {
    test('distinct styles do not grow the CSS cache without bound', () {
      // One factory (as a DomGridSurface owns for the whole session), fed rows
      // whose style never repeats — the pulsing/interpolating-truecolor case.
      // Without a bound the cache retains one entry per distinct style forever;
      // it must stay at or below the cap while still serving the common
      // repeated-style working set.
      final factory = DomRowFactory();
      final root = web.document.createElement('div');
      final cap = DomRowFactory.styleCacheCapacityForTest;
      final distinct = cap + 500;
      for (var i = 0; i < distinct; i++) {
        final buffer = CellBuffer(const CellSize(1, 1));
        buffer.writeText(
          const CellOffset(0, 0),
          'x',
          // (i % 256, i ~/ 256, 0) is a bijection over i < 65536, so every
          // iteration's foreground — and therefore its CellStyle key — is
          // distinct.
          style: CellStyle(foreground: RgbColor(i & 0xFF, (i >> 8) & 0xFF, 0)),
        );
        final row = const CellSpanBuilder().buildRow(buffer, 0);
        factory.replaceChildren(root, row, null);
      }

      expect(factory.styleCacheEntryCountForTest, lessThanOrEqualTo(cap));
      expect(
        factory.styleCacheEntryCountForTest,
        lessThan(distinct),
        reason: 'the cache is bounded, not one entry per distinct style',
      );
    });

    test('a small repeated style set stays fully cached (common case)', () {
      final factory = DomRowFactory();
      final root = web.document.createElement('div');
      for (var frame = 0; frame < 200; frame++) {
        for (var s = 0; s < 8; s++) {
          final buffer = CellBuffer(const CellSize(1, 1));
          buffer.writeText(
            const CellOffset(0, 0),
            'x',
            style: CellStyle(foreground: RgbColor(s, 0, 0)),
          );
          final row = const CellSpanBuilder().buildRow(buffer, 0);
          factory.replaceChildren(root, row, null);
        }
      }
      // 8 recurring styles, never evicted regardless of how many frames render.
      expect(factory.styleCacheEntryCountForTest, 8);
    });
  });

  group('DomRowFactory OSC 8 links', () {
    test('an allow-listed scheme becomes a clickable <a href>', () {
      final root = _render(
        20,
        (b) => b.writeText(
          const CellOffset(0, 0),
          'docs',
          style: const CellStyle(linkUri: 'https://example.com/a'),
        ),
      );

      final anchor = root.querySelector('a');
      expect(anchor, isNotNull);
      // href is set via setAttribute (verbatim), rel/target harden the tab.
      expect(anchor!.getAttribute('href'), 'https://example.com/a');
      expect(anchor.getAttribute('rel'), 'noopener noreferrer');
      expect(anchor.getAttribute('target'), '_blank');
      // Visible text carried through textContent exactly as a span would.
      expect(anchor.textContent, 'docs');
    });

    test('a mailto scheme is allow-listed too', () {
      final root = _render(
        20,
        (b) => b.writeText(
          const CellOffset(0, 0),
          'x',
          style: const CellStyle(linkUri: 'mailto:a@b.com'),
        ),
      );
      expect(root.querySelector('a')?.getAttribute('href'), 'mailto:a@b.com');
    });

    test('a file: scheme is NOT in the default allow-list — plain span', () {
      // RFC 0013 gates file: behind an explicit opt-in the framework does not
      // enable by default, so the canonical isSafeLinkScheme drops it (matching
      // the producer and semantic-DOM surfaces). It renders as plain text.
      final root = _render(
        20,
        (b) => b.writeText(
          const CellOffset(0, 0),
          'x',
          style: const CellStyle(linkUri: 'file:///etc/hosts'),
        ),
      );
      expect(root.querySelector('a'), isNull);
      final span = root.querySelector('span');
      expect(span, isNotNull);
      expect(span!.getAttribute('href'), isNull);
    });

    test('a javascript: URI is dropped — plain span, no anchor, no href', () {
      final root = _render(
        20,
        (b) => b.writeText(
          const CellOffset(0, 0),
          'click',
          style: const CellStyle(linkUri: 'javascript:alert(1)'),
        ),
      );

      expect(root.querySelector('a'), isNull);
      expect(root.querySelectorAll('a').length, 0);
      final span = root.querySelector('span');
      expect(span, isNotNull);
      expect(span!.getAttribute('href'), isNull);
      // The label is still shown, just not navigable.
      expect(root.textContent, contains('click'));
    });

    test('a link with no explicit fg gets the default foreground, not UA blue', () {
      // The <a> would otherwise fall to the UA link color (#0000EE). Pin it to
      // the grid default foreground so a link reads as default-fg + underline.
      final root = _render(
        20,
        (b) => b.writeText(
          const CellOffset(0, 0),
          'docs',
          style: const CellStyle(underline: true, linkUri: 'https://example.com'),
        ),
      );
      final style = root.querySelector('a')!.getAttribute('style') ?? '';
      expect(style, contains('color:rgb(208, 208, 208)'));
    });

    test('a link-free run with no fg emits no color (byte-identical)', () {
      final root = _render(
        20,
        (b) => b.writeText(const CellOffset(0, 0), 'plain'),
      );
      final style = root.querySelector('span')!.getAttribute('style') ?? '';
      expect(style, isNot(contains('color:')));
    });

    test('a multi-word link is ONE contiguous anchor (spaces included)', () {
      // The link style rides the internal spaces (RenderRichText fix), so the
      // whole phrase is one run → one <a>, not one anchor per word.
      final root = _render(
        30,
        (b) => b.writeText(
          const CellOffset(0, 0),
          'open an issue',
          style: const CellStyle(underline: true, linkUri: 'https://x'),
        ),
      );
      expect(root.querySelectorAll('a').length, 1);
      expect(root.querySelector('a')!.textContent, 'open an issue');
    });

    test('a link-free run renders as a <span> with no anchor', () {
      final root = _render(
        20,
        (b) => b.writeText(const CellOffset(0, 0), 'plain'),
      );

      expect(root.querySelector('a'), isNull);
      final span = root.querySelector('span');
      expect(span, isNotNull);
      expect(span!.textContent, contains('plain'));
    });

    test('per-run styling is preserved on the anchor', () {
      final root = _render(
        20,
        (b) => b.writeText(
          const CellOffset(0, 0),
          'x',
          style: const CellStyle(
            foreground: Colors.green,
            underline: true,
            linkUri: 'https://a.b',
          ),
        ),
      );

      final anchor = root.querySelector('a')!;
      final style = anchor.getAttribute('style') ?? '';
      expect(style, contains('color:'));
      expect(style, contains('text-decoration:underline'));
    });
  });
}
