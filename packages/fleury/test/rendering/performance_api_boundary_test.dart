import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('render performance internals stay out of production libraries', () {
    final productionLibraries = <String>[
      'lib/fleury.dart',
      'lib/fleury_core.dart',
    ];

    for (final path in productionLibraries) {
      final file = File(path);
      final text = file.readAsStringSync();
      final exportLines = file
          .readAsLinesSync()
          .map((line) => line.trimLeft())
          .where((line) => line.startsWith('export '))
          .join('\n');

      expect(
        exportLines,
        isNot(contains('render_layout_stats.dart')),
        reason:
            '$path must not export layout debug counters as production API; '
            'they belong to package:fleury/fleury_test.dart.',
      );
      expect(
        text,
        isNot(contains('RenderLayoutDebugStats')),
        reason:
            '$path must not expose debug-only layout counters as production '
            'rendering API.',
      );
      expect(
        text,
        isNot(contains('RepaintBoundaryFrameStats')),
        reason:
            '$path must not expose repaint-boundary debug counters as '
            'production rendering API.',
      );
      expect(
        text,
        isNot(contains('hasSameRenderChildrenInOrder')),
        reason:
            '$path must not freeze the child-list identity helper as public '
            'API before a real extension contract exists.',
      );
      expect(
        text,
        isNot(contains('_isOutsidePaintBuffer')),
        reason:
            '$path must not expose private viewport paint-culling machinery.',
      );
      expect(
        text,
        isNot(contains('_subtreeNeedsOffscreenPaint')),
        reason: '$path must not expose selectable offscreen-paint internals.',
      );
    }
  });

  test('test library owns render performance diagnostics', () {
    final testLibrary = File('lib/fleury_test.dart').readAsStringSync();

    expect(testLibrary, contains('render_layout_stats.dart'));
    expect(testLibrary, contains('RenderLayoutDebugStats'));
    expect(testLibrary, contains('RenderLayoutFrameStats'));
    expect(testLibrary, contains('RepaintBoundaryFrameStats'));
  });
}
