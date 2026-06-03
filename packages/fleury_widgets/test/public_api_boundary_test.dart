import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'first-party widget render implementations stay out of public barrel',
    () {
      final source = File('lib/fleury_widgets.dart').readAsStringSync();

      for (final symbol in <String>[
        'RenderBarChart',
        'RenderCalendarHeatmap',
        'RenderCanvas',
        'RenderDataTable',
        'RenderDigits',
        'RenderGauge',
        'RenderHeatmap',
        'RenderImage',
        'RenderLineChart',
        'RenderProgressBar',
        'RenderSparkline',
        'RenderTable',
      ]) {
        expect(
          source,
          isNot(contains(symbol)),
          reason:
              '$symbol is a first-party widget implementation detail; expose '
              'the widget, data, controller, and copy/export APIs until a real '
              'extension contract proves the render class should be public.',
        );
      }
    },
  );
}
