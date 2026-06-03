import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'widget implementation render objects stay out of production barrels',
    () {
      final coreLibrary = File('lib/fleury_core.dart').readAsStringSync();

      expect(
        coreLibrary,
        contains('LayoutBuilder'),
        reason: 'LayoutBuilder is the public responsive-layout widget.',
      );
      expect(
        coreLibrary,
        contains('LayoutWidgetBuilder'),
        reason: 'The builder typedef is part of the public widget API.',
      );
      expect(
        coreLibrary,
        isNot(contains('RenderLayoutBuilder')),
        reason:
            'RenderLayoutBuilder is the private implementation behind '
            'LayoutBuilder and should not be frozen as production API.',
      );
      for (final symbol in <String>[
        'RenderTextInput',
        'RenderTextArea',
        'RenderRichText',
        'RenderScrollbar',
        'ScrollbarGeometry',
        'ScrollbarMetrics',
      ]) {
        expect(
          coreLibrary,
          isNot(contains(symbol)),
          reason:
              '$symbol is widget implementation plumbing and should not be '
              'exported as production API.',
        );
      }
    },
  );
}
