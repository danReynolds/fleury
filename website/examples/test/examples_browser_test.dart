@TestOn('browser')
library;

import 'package:fleury_doc_examples/registry.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

// A controllable frame flush so the test can force the first paint
// synchronously (mirrors fleury_web's own DOM demo test).
final class _FakeFlush {
  void Function()? _pending;
  bool get pending => _pending != null;
  void schedule(Duration delay, void Function() flush) => _pending = flush;
  void fire() {
    final flush = _pending;
    if (flush == null) return;
    _pending = null;
    flush();
  }
}

final class _MountedExample {
  _MountedExample({
    required this.host,
    required this.surface,
    required this.flush,
  });

  final web.Element host;
  final TuiSurfaceHost surface;
  final _FakeFlush flush;

  Future<void> dispose() async {
    await surface.dispose();
    host.remove();
  }
}

Future<web.Element> _mount(String id) async {
  final flush = _FakeFlush();
  final host = web.document.createElement('div');
  // The DOM grid sizes itself from the host box + monospace cell metrics; an
  // unsized host yields a 0x0 grid (nothing paints), so give it real dimensions.
  host.setAttribute(
    'style',
    'position:absolute;left:0;top:0;width:80ch;height:240px;'
        'font-family:monospace;font-size:16px;line-height:18px;',
  );
  web.document.body!.appendChild(host);
  await runTuiWebDom(
    examples[id]!,
    hostElement: host,
    flushScheduler: flush.schedule,
  );
  // Drain the initial frame(s) so the DOM grid is painted.
  for (var i = 0; i < 4 && flush.pending; i++) {
    flush.fire();
  }
  return host;
}

Future<_MountedExample> _mountWithHandle(String id) async {
  final flush = _FakeFlush();
  final host = web.document.createElement('div');
  host.setAttribute(
    'style',
    'position:absolute;left:0;top:0;width:80ch;height:240px;'
        'font-family:monospace;font-size:16px;line-height:18px;',
  );
  web.document.body!.appendChild(host);
  final surface = await runTuiWebDom(
    examples[id]!,
    hostElement: host,
    flushScheduler: flush.schedule,
  );
  _drain(flush);
  return _MountedExample(host: host, surface: surface, flush: flush);
}

void _drain(_FakeFlush flush) {
  for (var i = 0; i < 4 && flush.pending; i++) {
    flush.fire();
  }
}

void _click(web.Element target, {int? clientX, int? clientY}) {
  final rect = target.getBoundingClientRect();
  final x = clientX ?? (rect.left + rect.width / 2).round();
  final y = clientY ?? (rect.top + rect.height / 2).round();
  target.dispatchEvent(
    web.PointerEvent(
      'pointerdown',
      web.PointerEventInit(
        pointerId: 1,
        clientX: x,
        clientY: y,
        button: 0,
        buttons: 1,
        bubbles: true,
        cancelable: true,
      ),
    ),
  );
  target.dispatchEvent(
    web.PointerEvent(
      'pointerup',
      web.PointerEventInit(
        pointerId: 1,
        clientX: x,
        clientY: y,
        button: 0,
        buttons: 0,
        bubbles: true,
        cancelable: true,
      ),
    ),
  );
}

bool _selectedClockTab(web.Element host, String label) {
  final spans = host.querySelectorAll('.fleury-row[data-row="1"] span');
  for (var i = 0; i < spans.length; i++) {
    final span = spans.item(i);
    if (span is! web.Element) continue;
    if (span.textContent?.trim() != label) continue;
    final style = web.window.getComputedStyle(span);
    return style.backgroundColor != 'rgba(0, 0, 0, 0)';
  }
  return false;
}

void _clickClockTab(_MountedExample mounted, String label) {
  final rowSpans = mounted.host.querySelectorAll(
    '.fleury-row[data-row="1"] span',
  );
  final utcLabel = rowSpans.item(1) as web.Element;
  final cellWidth = utcLabel.getBoundingClientRect().width / 5;
  var labelStartCol = 1;
  for (final tabLabel in const ['UTC', 'EST', 'PST', 'CET', 'JST']) {
    if (tabLabel == label) break;
    labelStartCol += tabLabel.length + 2;
  }
  final screen = mounted.host.querySelector('.fleury-screen') as web.Element;
  final screenRect = screen.getBoundingClientRect();
  final rowRect = utcLabel.getBoundingClientRect();
  _click(
    screen,
    clientX: (screenRect.left + cellWidth * (labelStartCol + 2.5)).round(),
    clientY: (rowRect.top + rowRect.height / 2).round(),
  );
  _drain(mounted.flush);
}

void main() {
  test('gauge.basic renders its label in the browser DOM grid', () async {
    final host = await _mount('gauge.basic');
    addTearDown(() => host.remove());
    expect(host.querySelector('.fleury-screen'), isNotNull);
    expect(host.textContent, contains('CPU'));
  });

  test('linechart.basic renders client-side (offset fix holds)', () async {
    final host = await _mount('linechart.basic');
    addTearDown(() => host.remove());
    expect(host.textContent, contains('load')); // the series legend label
  });

  test('barchart.basic renders its categories', () async {
    final host = await _mount('barchart.basic');
    addTearDown(() => host.remove());
    expect(host.textContent, contains('q4'));
  });

  test(
    'digits.basic renders the interactive world-clock timezone tabs',
    () async {
      final host = await _mount('digits.basic');
      addTearDown(() => host.remove());
      // The timezone tab labels are real text; the clock itself is block glyphs.
      expect(host.textContent, contains('UTC'));
      expect(host.textContent, contains('PST'));
    },
  );

  test('digits.basic switches timezone tabs on pointer click', () async {
    final mounted = await _mountWithHandle('digits.basic');
    addTearDown(mounted.dispose);

    expect(_selectedClockTab(mounted.host, 'UTC'), isTrue);
    expect(_selectedClockTab(mounted.host, 'EST'), isFalse);

    _clickClockTab(mounted, 'EST');

    expect(_selectedClockTab(mounted.host, 'EST'), isTrue);
  });

  test('digits.basic switches timezone tabs after host layout moves', () async {
    final mounted = await _mountWithHandle('digits.basic');
    addTearDown(mounted.dispose);

    mounted.host.setAttribute(
      'style',
      'position:absolute;left:48px;top:72px;width:80ch;height:240px;'
          'font-family:monospace;font-size:16px;line-height:18px;',
    );

    expect(_selectedClockTab(mounted.host, 'UTC'), isTrue);

    _clickClockTab(mounted, 'EST');

    expect(_selectedClockTab(mounted.host, 'EST'), isTrue);
  });

  test('gauge knobs re-render in place when a prop changes', () async {
    final flush = _FakeFlush();
    final host = web.document.createElement('div');
    host.setAttribute(
      'style',
      'position:absolute;left:0;top:0;width:60ch;height:160px;'
          'font-family:monospace;font-size:16px;line-height:18px;',
    );
    web.document.body!.appendChild(host);
    addTearDown(() => host.remove());

    final params = KnobParams(<String, Object?>{
      'value': 0.30,
      'label': 'CPU',
      'showPercentage': true,
    });
    await runTuiWebDom(
      () => knobRoot('gauge', params),
      hostElement: host,
      flushScheduler: flush.schedule,
    );
    for (var i = 0; i < 4 && flush.pending; i++) {
      flush.fire();
    }
    expect(host.textContent, contains('30%'));

    // Push a new value through the notifier; the widget should rebuild in place.
    params.value = <String, Object?>{
      'value': 0.90,
      'label': 'CPU',
      'showPercentage': true,
    };
    for (var i = 0; i < 4 && flush.pending; i++) {
      flush.fire();
    }
    expect(host.textContent, contains('90%'));
    expect(host.textContent, isNot(contains('30%')));
  });

  test('codeview.basic renders the (now scrollable) source', () async {
    final host = await _mount('codeview.basic');
    addTearDown(() => host.remove());
    expect(host.textContent, contains('CounterApp'));
  });

  test('messagelist.basic renders the (now scrollable) transcript', () async {
    final host = await _mount('messagelist.basic');
    addTearDown(() => host.remove());
    expect(host.textContent, contains('Ship it'));
  });

  test('histogram knobs re-render when the bin count changes', () async {
    final flush = _FakeFlush();
    final host = web.document.createElement('div');
    host.setAttribute(
      'style',
      'position:absolute;left:0;top:0;width:80ch;height:240px;'
          'font-family:monospace;font-size:16px;line-height:18px;',
    );
    web.document.body!.appendChild(host);
    addTearDown(() => host.remove());

    final params = KnobParams(<String, Object?>{'bins': 4, 'showValues': true});
    await runTuiWebDom(
      () => knobRoot('histogram', params),
      hostElement: host,
      flushScheduler: flush.schedule,
    );
    for (var i = 0; i < 4 && flush.pending; i++) {
      flush.fire();
    }
    final fourBins = host.textContent;

    params.value = <String, Object?>{'bins': 16, 'showValues': true};
    for (var i = 0; i < 4 && flush.pending; i++) {
      flush.fire();
    }
    expect(host.textContent, isNot(equals(fourBins))); // re-binned in place
  });
}
