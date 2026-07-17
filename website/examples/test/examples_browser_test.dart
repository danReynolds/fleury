@TestOn('browser')
library;

import 'package:fleury_doc_examples/registry.dart';
import 'package:fleury_doc_examples/frame_flush_scheduler.dart';
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
  void Function() schedule(Duration delay, void Function() flush) {
    _pending = flush;
    return () {
      if (identical(_pending, flush)) _pending = null;
    };
  }

  void fire() {
    final flush = _pending;
    if (flush == null) return;
    _pending = null;
    flush();
  }
}

final class _MountedExample {
  const _MountedExample({
    required this.host,
    required this.flush,
    required this.app,
  });

  final web.Element host;
  final _FakeFlush flush;
  final MountedApp app;
}

Future<_MountedExample> _mountExample(
  String id, {
  bool useManifestSize = false,
}) async {
  final flush = _FakeFlush();
  final host = web.document.createElement('div');
  final info = exampleList.singleWhere((example) => example.id == id);
  final width = useManifestSize ? '${info.cols}ch' : '80ch';
  final height = useManifestSize ? '${info.rows * 18}px' : '240px';
  // The DOM grid sizes itself from the host box + monospace cell metrics; an
  // unsized host yields a 0x0 grid (nothing paints), so give it real dimensions.
  host.setAttribute(
    'style',
    'position:absolute;left:0;top:0;width:$width;height:$height;'
        'font-family:monospace;font-size:16px;line-height:18px;',
  );
  web.document.body!.appendChild(host);
  final app = await mountApp(
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
  await app.awaitSemanticIdle();
  addTearDown(() async {
    await app.dispose();
    host.remove();
  });
  return _MountedExample(host: host, flush: flush, app: app);
}

Future<web.Element> _mount(String id) async => (await _mountExample(id)).host;

Future<web.Element> _mountRoot(Widget Function() builder) async {
  final flush = _FakeFlush();
  final host = web.document.createElement('div');
  host.setAttribute(
    'style',
    'position:absolute;left:0;top:0;width:80ch;height:240px;'
        'font-family:monospace;font-size:16px;line-height:18px;',
  );
  web.document.body!.appendChild(host);
  final app = await mountApp(
    builder,
    into: host,
    flushScheduler: flush.schedule,
  );
  for (var i = 0; i < 4 && flush.pending; i++) {
    flush.fire();
  }
  await app.awaitSemanticIdle();
  addTearDown(() async {
    await app.dispose();
    host.remove();
  });
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
  test('docs fallback cancels a held animation-frame callback', () async {
    void Function()? heldFrame;
    int? canceledFrame;
    var flushes = 0;

    scheduleDocsFrameFlush(
      Duration.zero,
      () => flushes += 1,
      requestAnimationFrame: (callback) {
        heldFrame = callback;
        return 41;
      },
      cancelAnimationFrame: (frameId) => canceledFrame = frameId,
      fallbackDelay: Duration.zero,
    );
    await Future<void>.delayed(Duration.zero);

    expect(flushes, 1);
    expect(canceledFrame, 41);
    heldFrame!();
    expect(flushes, 1, reason: 'the losing rAF cannot flush a second time');
  });

  test('textinput.basic mounts focused and accepts browser text', () async {
    final fixture = await _mountExample('textinput.basic');

    final semantics = fixture.host.querySelector('.fleury-semantics')!;
    final field =
        semantics.querySelector('[role="textbox"]')! as web.HTMLInputElement;
    expect(field.getAttribute('data-fleury-focused'), 'true');
    expect(field.value, 'deploy staging');

    final keyboardCapture =
        fixture.host.querySelector('textarea') as web.HTMLTextAreaElement;
    keyboardCapture.dispatchEvent(
      web.InputEvent(
        'input',
        web.InputEventInit(
          data: '!',
          inputType: 'insertText',
          bubbles: true,
          cancelable: true,
        ),
      ),
    );
    expect(fixture.flush.pending, isTrue);
    fixture.flush.fire();
    await fixture.app.awaitSemanticIdle();

    expect(field.value, 'deploy !');
    expect(fixture.host.textContent, contains('deploy !'));
  });

  test('textarea.basic mounts focused and accepts browser text', () async {
    final fixture = await _mountExample('textarea.basic');

    final semantics = fixture.host.querySelector('.fleury-semantics')!;
    final field =
        semantics.querySelector('textarea[role="textbox"]')!
            as web.HTMLTextAreaElement;
    expect(field.getAttribute('data-fleury-focused'), 'true');
    expect(field.getAttribute('aria-label'), 'Release notes');

    final keyboardCapture =
        fixture.host.querySelector('textarea[aria-hidden="true"]')!
            as web.HTMLTextAreaElement;
    keyboardCapture.dispatchEvent(
      web.InputEvent(
        'input',
        web.InputEventInit(
          data: 'Ship it',
          inputType: 'insertText',
          bubbles: true,
          cancelable: true,
        ),
      ),
    );
    expect(fixture.flush.pending, isTrue);
    fixture.flush.fire();
    await fixture.app.awaitSemanticIdle();

    expect(field.value, 'Ship it');
    expect(fixture.host.textContent, contains('Ship it'));
  });

  test('form.basic mounts its form and field semantics', () async {
    final fixture = await _mountExample('form.basic');

    final semantics = fixture.host.querySelector('.fleury-semantics')!;
    expect(
      semantics.querySelector('[role="form"][aria-label="Project settings"]'),
      isNotNull,
    );
    expect(
      semantics.querySelector('[role="region"][aria-label="Name"]'),
      isNotNull,
    );
    expect(
      semantics.querySelector('[role="region"][aria-label="Private project"]'),
      isNotNull,
    );
  });

  test('formerly source-only web widgets mount as live examples', () async {
    const ids = <String>[
      'canvas.basic',
      'checkbox.basic',
      'formwizard.basic',
      'keyhintbar.basic',
      'markdowntext.basic',
      'multiselect.basic',
      'radio.basic',
      'radiogroup.basic',
      'switch.basic',
      'toggle.basic',
      'tokenmeter.basic',
    ];

    expect(examples.keys, containsAll(ids));
    for (final id in ids) {
      final host = await _mount(id);
      expect(
        host.querySelector('.fleury-screen'),
        isNotNull,
        reason: '$id should paint into the browser DOM grid',
      );
    }
  });

  test('checkbox.basic toggles through the browser semantic control', () async {
    final fixture = await _mountExample('checkbox.basic');
    final checkbox = fixture.host.querySelector(
      '.fleury-semantics [role="checkbox"]',
    )!;

    expect(checkbox.getAttribute('aria-label'), 'Accept terms');
    expect(checkbox.getAttribute('aria-checked'), 'false');

    (checkbox as web.HTMLElement).click();
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 4 && fixture.flush.pending; i++) {
      fixture.flush.fire();
    }
    await fixture.app.awaitSemanticIdle();

    expect(checkbox.getAttribute('aria-checked'), 'true');
    expect(fixture.host.textContent, contains('[x] Accept terms'));
  });

  test(
    'rangeslider.basic fits its live frame and accepts pointer input',
    () async {
      final fixture = await _mountExample(
        'rangeslider.basic',
        useManifestSize: true,
      );
      final info = exampleList.singleWhere(
        (example) => example.id == 'rangeslider.basic',
      );
      final screen = fixture.host.querySelector('.fleury-screen')!;
      final slider = fixture.host.querySelector('[role="slider"]')!;

      expect(fixture.host.textContent, contains('●'));
      expect(fixture.host.textContent, contains('○'));
      expect(fixture.host.textContent, contains('━'));
      expect(slider.getAttribute('data-fleury-value'), '20-70');

      final bounds = screen.getBoundingClientRect();
      final cellWidth = bounds.width / info.cols;
      final cellHeight = bounds.height / info.rows;
      final clientX = (bounds.left + cellWidth * 5.5).round();
      final clientY = (bounds.top + cellHeight * 2.5).round();
      screen.dispatchEvent(
        web.PointerEvent(
          'pointerdown',
          web.PointerEventInit(
            pointerId: 1,
            clientX: clientX,
            clientY: clientY,
            button: 0,
            buttons: 1,
            bubbles: true,
            cancelable: true,
          ),
        ),
      );
      screen.dispatchEvent(
        web.PointerEvent(
          'pointerup',
          web.PointerEventInit(
            pointerId: 1,
            clientX: clientX,
            clientY: clientY,
            button: -1,
            buttons: 0,
            bubbles: true,
            cancelable: true,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 4 && fixture.flush.pending; i++) {
        fixture.flush.fire();
      }
      await fixture.app.awaitSemanticIdle();

      expect(slider.getAttribute('data-fleury-value'), '10-70');
    },
  );

  test('gauge.basic renders its label in the browser DOM grid', () async {
    final host = await _mount('gauge.basic');
    expect(host.querySelector('.fleury-screen'), isNotNull);
    expect(host.textContent, contains('CPU'));
  });

  test('linechart.basic renders client-side (offset fix holds)', () async {
    final host = await _mount('linechart.basic');
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
    expect(host.textContent, contains('q4'));
  });

  test('site-themed examples use the light docs palette', () async {
    final host = await _mountRoot(
      () => themedExampleRoot(
        () => const _ThemeColorProbe(),
        DocsExampleThemeController(DocsExampleStyle.light),
      ),
    );

    expect(_firstSpanColorContaining(host, 'accent'), 'rgb(19, 138, 92)');
  });

  test(
    'digits.basic renders the interactive world-clock timezone tabs',
    () async {
      final host = await _mount('digits.basic');
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

    final params = KnobParams(<String, Object?>{
      'value': 0.30,
      'label': 'CPU',
      'showPercentage': true,
    });
    final app = await mountApp(
      () => knobRoot('gauge', params),
      into: host,
      flushScheduler: flush.schedule,
    );
    addTearDown(() async {
      await app.dispose();
      host.remove();
    });
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
    expect(host.textContent, contains('CounterApp'));
  });

  test('messagelist.basic renders the (now scrollable) transcript', () async {
    final host = await _mount('messagelist.basic');
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

    final params = KnobParams(<String, Object?>{'bins': 4, 'showValues': true});
    final app = await mountApp(
      () => knobRoot('histogram', params),
      into: host,
      flushScheduler: flush.schedule,
    );
    addTearDown(() async {
      await app.dispose();
      host.remove();
    });
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
