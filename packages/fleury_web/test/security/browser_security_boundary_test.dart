@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/dom_grid/cell_grid_html.dart';
import 'package:fleury_web/src/dom_grid/dom_grid_surface.dart';
import 'package:fleury_web/src/semantics/semantic_dom_presenter.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

CellBuffer _frame(int cols, int rows, void Function(CellBuffer buffer) paint) {
  final buffer = CellBuffer(CellSize(cols, rows));
  paint(buffer);
  return buffer;
}

void main() {
  group('browser security boundaries', () {
    test('static HTML renderer escapes markup-looking cell text', () {
      final html = renderFrameHtml(
        _frame(
          36,
          1,
          (buffer) => buffer.writeText(
            const CellOffset(0, 0),
            '<img src=x onerror=alert(1)>&',
          ),
        ),
      );

      expect(html, contains('&lt;img src=x onerror=alert(1)&gt;&amp;'));
      expect(html, isNot(contains('<img src=x onerror=alert(1)>')));
    });

    test(
      'retained DOM grid writes unsafe-looking text through textContent',
      () {
        final root = web.document.createElement('div');
        final surface = DomGridSurface(root: root, size: const CellSize(36, 1));
        final damage = RenderDamageTracker();
        final loop = TuiFrameLoop(renderDamage: damage);
        final frame = loop.render(
          size: const CellSize(36, 1),
          paint: (buffer) => buffer.writeText(
            const CellOffset(0, 0),
            '<img src=x onerror=alert(1)>',
          ),
        )!;

        surface.present(
          frame.previous,
          frame.next,
          const FramePresentationPlanner().build(
            reason: 'initial',
            frame: frame,
          ),
        );

        final row = surface.rowElements.single;
        expect(row.textContent, contains('<img src=x onerror=alert(1)>'));
        expect(row.querySelector('img'), isNull);
      },
    );

    test('unsafe semantic links are exposed as data, not navigation', () {
      final root = web.document.createElement('div');
      final presenter = SemanticDomPresenter(root: root);

      presenter.present(
        const SemanticTree(
          root: SemanticNode(
            id: SemanticNodeId('root'),
            role: SemanticRole.app,
            children: [
              SemanticNode(
                id: SemanticNodeId('bad-link'),
                role: SemanticRole.link,
                label: '<script>alert(1)</script>',
                value: 'javascript:alert(1)',
                state: SemanticState({'linkUrl': 'javascript:alert(1)'}),
              ),
            ],
          ),
        ),
      );

      final link = root.querySelector('[data-fleury-semantic-id="bad-link"]')!;
      expect(link.localName, 'a');
      expect(link.textContent, '<script>alert(1)</script>');
      expect(link.querySelector('script'), isNull);
      expect(link.getAttribute('href'), isNull);
      expect(link.getAttribute('target'), isNull);
      expect(link.getAttribute('rel'), isNull);
      expect(link.getAttribute('data-fleury-link-url'), 'javascript:alert(1)');
    });

    test('inline-image regions expose no bytes and no id to the DOM', () {
      // Image bytes never enter cells under the overlay model (there is
      // no API that would put escape payloads in a cell at all); the
      // remaining leak surface is the content-hash id — assert the grid
      // carries neither.
      final root = web.document.createElement('div');
      final surface = DomGridSurface(root: root, size: const CellSize(6, 1));
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      final frame = loop.render(
        size: const CellSize(6, 1),
        paint: (buffer) => buffer.writeImage(
          const CellOffset(1, 0),
          Uint8List.fromList('SECRET_IMAGE_PAYLOAD'.codeUnits),
          width: 2,
          height: 1,
        ),
      )!;

      surface.present(
        frame.previous,
        frame.next,
        const FramePresentationPlanner().build(reason: 'initial', frame: frame),
      );

      expect(
        surface.rowElements.single.textContent,
        isNot(contains('SECRET_IMAGE_PAYLOAD')),
      );
      expect(root.innerHTML, isNot(contains('SECRET_IMAGE_PAYLOAD')));
      expect(
        root.innerHTML,
        isNot(contains(frame.next.imagePlacements.single.id)),
      );
    });
  });
}
