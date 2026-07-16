@TestOn('browser')
library;

import 'package:fleury_doc_examples/registry.dart';
import 'package:fleury/fleury_host.dart';
import 'package:fleury_web/fleury_web.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';
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
  await mountApp(
    () => themedExampleRoot(
      examples[id]!,
      DocsExampleThemeController(DocsExampleStyle.dark),
    ),
    into: host,
    flushScheduler: flush.schedule,
  );
  // Drain the initial frame(s) so the DOM grid is painted.
  for (var i = 0; i < 4 && flush.pending; i++) {
    flush.fire();
  }
  return host;
}

Future<web.Element> _mountRoot(Widget Function() builder) async {
  final flush = _FakeFlush();
  final host = web.document.createElement('div');
  host.setAttribute(
    'style',
    'position:absolute;left:0;top:0;width:80ch;height:240px;'
        'font-family:monospace;font-size:16px;line-height:18px;',
  );
  web.document.body!.appendChild(host);
  await mountApp(builder, into: host, flushScheduler: flush.schedule);
  for (var i = 0; i < 4 && flush.pending; i++) {
    flush.fire();
  }
  return host;
}

final class _ThemeColorProbe extends StatelessWidget {
  const _ThemeColorProbe();

  @override
  Widget build(BuildContext context) => Text(
    'accent',
    style: CellStyle(foreground: Theme.of(context).colorScheme.primary),
  );
}

String? _firstSpanColorContaining(web.Element host, String text) {
  final spans = host.querySelectorAll('.fleury-row span');
  for (var i = 0; i < spans.length; i++) {
    final span = spans.item(i);
    if (span is! web.Element) continue;
    if (!(span.textContent ?? '').contains(text)) continue;
    return web.window.getComputedStyle(span).color;
  }
  return null;
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

  test('docs example root supplies Tab traversal in the browser', () async {
    final flush = _FakeFlush();
    final host = web.document.createElement('div');
    host.setAttribute(
      'style',
      'position:absolute;left:0;top:0;width:40ch;height:120px;'
          'font-family:monospace;font-size:16px;line-height:18px;',
    );
    web.document.body!.appendChild(host);
    addTearDown(() => host.remove());

    final mounted = await mountApp(
      () => themedExampleRoot(
        () => Column(
          children: <Widget>[
            Button(label: 'First', onPressed: () {}),
            Button(label: 'Second', onPressed: () {}),
          ],
        ),
        DocsExampleThemeController(DocsExampleStyle.dark),
      ),
      into: host,
      flushScheduler: flush.schedule,
    );
    addTearDown(mounted.dispose);
    while (flush.pending) {
      flush.fire();
    }

    final keyboardCapture =
        host.querySelector('textarea') as web.HTMLTextAreaElement;
    keyboardCapture.dispatchEvent(
      web.KeyboardEvent(
        'keydown',
        web.KeyboardEventInit(key: 'Tab', bubbles: true, cancelable: true),
      ),
    );
    expect(flush.pending, isTrue);
    flush.fire();
    await mounted.awaitSemanticIdle();

    final focused = host.querySelector(
      '.fleury-semantics [role="button"][data-fleury-focused="true"]',
    );
    expect(focused?.textContent, contains('First'));
  });

  test('barchart.basic renders its categories', () async {
    final host = await _mount('barchart.basic');
    addTearDown(() => host.remove());
    expect(host.textContent, contains('q4'));
  });

  test('site-themed examples use the light docs palette', () async {
    final host = await _mountRoot(
      () => themedExampleRoot(
        () => const _ThemeColorProbe(),
        DocsExampleThemeController(DocsExampleStyle.light),
      ),
    );
    addTearDown(() => host.remove());

    expect(_firstSpanColorContaining(host, 'accent'), 'rgb(19, 138, 92)');
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
    await mountApp(
      () => knobRoot('gauge', params),
      into: host,
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
    await mountApp(
      () => knobRoot('histogram', params),
      into: host,
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
