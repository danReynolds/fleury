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
