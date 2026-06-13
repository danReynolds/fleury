@TestOn('browser')
library;

import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/src/dom_grid/dom_grid_surface.dart';
import 'package:fleury_web/src/metrics/cell_metrics.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  const size = CellSize(8, 3);
  const planner = FramePresentationPlanner();

  group('DomGridSurface', () {
    test('scroll plans move retained row elements instead of rebuilding', () {
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      const planner = FramePresentationPlanner();
      final root = web.document.createElement('div');
      const size = CellSize(6, 4);
      final surface = DomGridSurface(root: root, size: size);

      final first = loop.render(
        size: size,
        paint: (buffer) {
          buffer.writeText(const CellOffset(0, 0), 'aaaa');
          buffer.writeText(const CellOffset(0, 1), 'bbbb');
          buffer.writeText(const CellOffset(0, 2), 'cccc');
          buffer.writeText(const CellOffset(0, 3), 'dddd');
        },
      )!;
      surface.present(
        first.previous,
        first.next,
        planner.build(reason: 'initial', frame: first),
      );
      loop.commit(first);
      final retainedRowB = surface.rowElements[1];

      final second = loop.render(
        size: size,
        paint: (buffer) {
          buffer.writeText(const CellOffset(0, 0), 'bbbb');
          buffer.writeText(const CellOffset(0, 1), 'cccc');
          buffer.writeText(const CellOffset(0, 2), 'dddd');
          buffer.writeText(const CellOffset(0, 3), 'eeee');
          damage.recordLayoutOrConservativePaint();
        },
      )!;
      final plan = planner.build(reason: 'scroll', frame: second);
      final stats = surface.present(second.previous, second.next, plan);

      // Only the entering row was rebuilt; the rest MOVED.
      expect(plan.scrollUpRows, 1);
      expect(stats.rowsReplaced, 1);
      expect(
        [for (final row in surface.rowElements) row.textContent],
        ['bbbb  ', 'cccc  ', 'dddd  ', 'eeee  '],
      );
      // The element that held row 1 ('bbbb') is now row 0 — moved, not
      // recreated.
      expect(identical(surface.rowElements[0], retainedRowB), isTrue);
      expect(
        [for (final row in surface.rowElements) row.getAttribute('data-row')],
        ['0', '1', '2', '3'],
      );
    });

    test('configures an aria-hidden retained visual grid', () {
      final root = web.document.createElement('div');
      final surface = DomGridSurface(root: root, size: size);

      expect(root.className, 'fleury-screen');
      expect(root.ariaHidden, 'true');
      expect(root.getAttribute('role'), 'presentation');
      final style = root.getAttribute('style')!;
      expect(style, contains('user-select:none'));
      expect(style, contains('white-space:pre'));
      expect(style, contains('tab-size:1'));
      expect(style, contains('font-kerning:none'));
      expect(style, contains('font-variant-ligatures:none'));
      expect(style, contains('font-feature-settings:"liga" 0,"clig" 0'));
      expect(style, contains('letter-spacing:0'));
      expect(root.children.length, size.rows);
      expect(surface.rowElements.map((row) => row.className), [
        'fleury-row',
        'fleury-row',
        'fleury-row',
      ]);
    });

    test('retains row elements and replaces only dirty row children', () {
      final root = web.document.createElement('div');
      final surface = DomGridSurface(root: root, size: size);
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);

      final first = loop.render(
        size: size,
        paint: (buffer) {
          buffer.writeText(const CellOffset(0, 0), 'zero');
          buffer.writeText(const CellOffset(0, 1), 'one');
          buffer.writeText(const CellOffset(0, 2), 'two');
        },
      )!;
      final firstPlan = planner.build(reason: 'initial', frame: first);
      surface.present(first.previous, first.next, firstPlan);
      loop.commit(first);

      final retainedRows = List<web.Element>.of(surface.rowElements);
      final retainedCleanChild = retainedRows[0].firstChild;
      final retainedDirtyChild = retainedRows[1].firstChild;

      final second = loop.render(
        size: size,
        paint: (buffer) {
          buffer.withoutDamageTracking(() {
            buffer.copyRectFrom(
              first.next,
              CellRect.fromLTWH(0, 0, size.cols, 1),
              const CellOffset(0, 0),
            );
            buffer.copyRectFrom(
              first.next,
              CellRect.fromLTWH(0, 2, size.cols, 1),
              const CellOffset(0, 2),
            );
          });
          buffer.writeText(const CellOffset(0, 1), 'ONE');
        },
      )!;
      final secondPlan = planner.build(reason: 'paint', frame: second);
      surface.present(second.previous, second.next, secondPlan);

      expect(surface.rowElements, retainedRows);
      expect(root.children.length, size.rows);
      expect(surface.rowReplaceCount, size.rows + 1);
      expect(retainedRows[0].firstChild, same(retainedCleanChild));
      expect(retainedRows[1].firstChild, isNot(same(retainedDirtyChild)));
      expect(retainedRows[1].textContent, 'ONE     ');
    });

    test('reports DOM node creation and style cache stats', () {
      final root = web.document.createElement('div');
      final surface = DomGridSurface(root: root, size: size);
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      final frame = loop.render(
        size: size,
        paint: (buffer) {
          buffer.writeText(const CellOffset(0, 0), 'one');
          buffer.writeText(const CellOffset(0, 1), 'two');
        },
      )!;
      final plan = planner.build(reason: 'initial', frame: frame);

      final stats = surface.present(frame.previous, frame.next, plan);

      expect(stats.rowsReplaced, 3);
      expect(stats.domNodesCreated, 3);
      expect(stats.styleCacheMisses, 1);
      expect(stats.styleCacheHits, 2);
    });

    test('uses textContent, preserving unsafe-looking text as text', () {
      final root = web.document.createElement('div');
      final surface = DomGridSurface(root: root, size: const CellSize(8, 1));
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      final frame = loop.render(
        size: const CellSize(8, 1),
        paint: (buffer) => buffer.writeText(const CellOffset(0, 0), '<a&b>'),
      )!;
      final plan = planner.build(reason: 'initial', frame: frame);

      surface.present(frame.previous, frame.next, plan);

      final row = surface.rowElements.single;
      expect(row.textContent, '<a&b>   ');
      expect(row.children.length, 1);
      expect(row.children.item(0)!.textContent, '<a&b>   ');
      expect(row.querySelector('a'), isNull);
    });

    test('marks protocol cells as unsupported inline-image placeholders', () {
      final root = web.document.createElement('div');
      final surface = DomGridSurface(root: root, size: const CellSize(4, 1));
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      final frame = loop.render(
        size: const CellSize(4, 1),
        paint: (buffer) => buffer.writeProtocol(
          const CellOffset(1, 0),
          'image-bytes',
          width: 2,
          height: 1,
        ),
      )!;
      final plan = planner.build(reason: 'initial', frame: frame);

      surface.present(frame.previous, frame.next, plan);

      final placeholder = surface.rowElements.single.querySelector('.proto')!;
      expect(placeholder.textContent, '▩');
      expect(placeholder.getAttribute('title'), 'unsupported inline image');
      expect(
        placeholder.getAttribute('data-fleury-cell-kind'),
        'protocol-placeholder',
      );
      expect(
        placeholder.getAttribute('data-fleury-unsupported'),
        'inline-image',
      );
      expect(
        surface.rowElements.single.textContent,
        isNot(contains('image-bytes')),
      );
    });

    test('renders wide and styled spans from the shared span model', () {
      const metrics = MeasuredCellBox(
        cssCellWidth: 10,
        cssCellHeight: 20,
        cssCanvasWidth: 60,
        cssCanvasHeight: 20,
        devicePixelRatio: 2,
        cols: 6,
        rows: 1,
      );
      final root = web.document.createElement('div');
      final surface = DomGridSurface(root: root, size: const CellSize(6, 1));
      surface.resize(const CellSize(6, 1), metrics: metrics);
      final damage = RenderDamageTracker();
      final loop = TuiFrameLoop(renderDamage: damage);
      final frame = loop.render(
        size: const CellSize(6, 1),
        paint: (buffer) {
          buffer.writeText(
            const CellOffset(0, 0),
            '状',
            style: const CellStyle(foreground: Colors.green, bold: true),
          );
        },
      )!;
      final plan = planner.build(reason: 'initial', frame: frame);

      final firstStats = surface.present(frame.previous, frame.next, plan);

      final wide = surface.rowElements.single.children.item(0)!;
      expect(wide.className, 'w2');
      expect(wide.textContent, '状');
      expect(wide.getAttribute('style'), contains('width:20px'));
      expect(wide.getAttribute('style'), contains('color:rgb(0, 205, 0)'));
      expect(wide.getAttribute('style'), contains('font-weight:700'));
      expect(firstStats.widthCacheMisses, 1);
      expect(firstStats.widthCacheHits, 0);

      final secondStats = surface.present(frame.previous, frame.next, plan);

      expect(secondStats.widthCacheMisses, 0);
      expect(secondStats.widthCacheHits, 1);
    });

    test('dispose clears retained rows and root children', () async {
      final root = web.document.createElement('div');
      final surface = DomGridSurface(root: root, size: size);

      await surface.dispose();

      expect(surface.rowElements, isEmpty);
      expect(root.children.length, 0);
    });
  });
}
