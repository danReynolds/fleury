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
}
