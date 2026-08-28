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
  int? cols,
  int? rows,
}) async {
  final flush = _FakeFlush();
  final host = web.document.createElement('div');
  final info = exampleList.singleWhere((example) => example.id == id);
  final effectiveCols = cols ?? (useManifestSize ? info.cols : null);
  final effectiveRows = rows ?? (useManifestSize ? info.rows : null);
  final width = effectiveCols != null ? '${effectiveCols}ch' : '80ch';
  final height = effectiveRows != null ? '${effectiveRows * 18}px' : '240px';
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

int _nextPointerId = 1;

/// Activates the painted terminal control a browser user actually clicks.
///
/// Semantic controls intentionally have a direct activation path for agents
/// and assistive technology. Navigation examples also need coverage through
/// the cell grid's pointer hit testing, which is the path exercised by the
/// guide itself.
void _tapPaintedText(web.Element host, String label) {
  final spans = host.querySelectorAll('.fleury-screen .fleury-row span');
  web.Element? painted;
  for (var i = 0; i < spans.length; i++) {
    final span = spans.item(i);
    if (span is! web.Element) continue;
    if ((span.textContent ?? '').contains(label)) {
      painted = span;
      break;
    }
  }
  if (painted == null) fail('No painted text named "$label"');

  final rect = painted.getBoundingClientRect();
  final clientX = (rect.left + rect.width / 2).round();
  final clientY = (rect.top + rect.height / 2).round();
  final screen = host.querySelector('.fleury-screen')!;
  final pointerId = _nextPointerId++;
  screen.dispatchEvent(
    web.PointerEvent(
      'pointerdown',
      web.PointerEventInit(
        pointerId: pointerId,
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
        pointerId: pointerId,
        clientX: clientX,
        clientY: clientY,
        button: -1,
        buttons: 0,
        bubbles: true,
        cancelable: true,
      ),
    ),
  );
  // Real browsers release pointer capture before delivering the compatibility
  // click. Replaying the full sequence guards against one physical tap being
  // interpreted twice by the web host.
  screen.dispatchEvent(
    web.PointerEvent(
      'lostpointercapture',
      web.PointerEventInit(
        pointerId: pointerId,
        clientX: clientX,
        clientY: clientY,
        button: -1,
        buttons: 0,
        bubbles: true,
      ),
    ),
  );
  screen.dispatchEvent(
    web.MouseEvent(
      'click',
      web.MouseEventInit(
        clientX: clientX,
        clientY: clientY,
        button: 0,
        detail: 1,
        bubbles: true,
        cancelable: true,
      ),
    ),
  );
}

String? _rootRouteDepth(web.Element host) => host
    .querySelector(
      '.fleury-semantics [role="navigation"]'
      '[aria-label="root navigator"]',
    )
    ?.getAttribute('data-fleury-value');

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

    // A semantic flush may reconcile this control by replacing its DOM node;
    // assert against the current accessibility surface, not the stale handle
    // captured before the edit.
    final updatedField =
        semantics.querySelector('[role="textbox"]')! as web.HTMLInputElement;
    expect(updatedField.value, 'deploy !');
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
    // The demo seeds multi-line content (with the caret parked at the end) so it
    // reads as a filled editor rather than an empty field.
    expect(field.value, contains('Ship v1.4.0'));

    final keyboardCapture =
        fixture.host.querySelector('textarea[aria-hidden="true"]')!
            as web.HTMLTextAreaElement;
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

    // Browser text is accepted — appended to (not replacing) the seeded value.
    expect(
      field.value,
      'Ship v1.4.0\n\n- Add a --version flag\n'
      '- Fix the Windows resize crash!',
    );
    expect(fixture.host.textContent, contains('resize crash!'));
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

  // Guard for the whole catalog: every example must paint *visible* content at
  // the exact frame size the docs page gives it. sparkline.basic and
  // progressbar.basic shipped blank because their host (rows: 2) was too short
  // for a 1-row widget inside `_framed` (Padding.all(1) needs pad + content +
  // pad = 3 rows), so the padding squeezed the widget to zero height. It only
  // appeared once Expand grew the host. The check reads `.fleury-screen` — the
  // painted grid — not `host.textContent`, because the offscreen
  // `.fleury-semantics` layer carries the value text even when nothing paints.
  //
  // Mounts and disposes each example in turn (one live app at a time) so the
  // whole ~60-example sweep — including the large showcase apps — stays within
  // the time budget instead of piling every app up until a shared teardown.
  test(
    'every registered example paints visible content at its frame',
    () async {
      final blank = <String>[];
      for (final info in exampleList) {
        final flush = _FakeFlush();
        final host = web.document.createElement('div');
        host.setAttribute(
          'style',
          'position:absolute;left:0;top:0;width:${info.cols}ch;'
              'height:${info.rows * 18}px;'
              'font-family:monospace;font-size:16px;line-height:18px;',
        );
        web.document.body!.appendChild(host);
        final app = await mountApp(
          () => themedExampleRoot(
            examples[info.id]!,
            DocsExampleThemeController(DocsExampleStyle.dark),
          ),
          into: host,
          flushScheduler: flush.schedule,
        );
        for (var i = 0; i < 4 && flush.pending; i++) {
          flush.fire();
        }
        await app.awaitSemanticIdle();
        final screen = host.querySelector('.fleury-screen');
        final painted = (screen?.textContent ?? '').trim();
        if (painted.isEmpty)
          blank.add('${info.id} (${info.cols}x${info.rows})');
        await app.dispose();
        host.remove();
      }
      expect(
        blank,
        isEmpty,
        reason:
            'These live demos render blank at their manifest frame size — the '
            'host is too short for the framed content. Give them more rows in '
            'website/examples/lib/registry.dart. Blank: $blank',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  // Beyond "not blank": these demos previously clipped the widget's *point*
  // while still painting something, so the non-blank guard above wouldn't catch
  // them. button.basic showed "Pressed 0×" but not the button; approvalprompt
  // hid its Approve/Deny actions; commandpalette cut its shortcut column;
  // table dropped its last row. Assert the essential content survives at the
  // manifest frame size so an undersized frame fails loudly.
  test('key demos render their essential content, not just something', () async {
    final checks = <String, List<String>>{
      'button.basic': <String>['Press me'],
      'approvalprompt.basic': <String>['Approve', 'Deny'],
      'commandpalette.basic': <String>['Ctrl-P'],
      'table.basic': <String>['lin'],
      // Full blocks are deliberately converted to exact CSS rectangles by the
      // web renderer, so assert painted fill rather than a font glyph.
      'progressbar.basic': <String>[],
      // Demos seeded/expanded/sized for a more legible resting state.
      'tree.basic': <String>['main.dart'], // expanded, not a lone "▸ lib/"
      'treetable.basic': <String>['main.dart'], // 'lib' branch expanded
      'passwordinput.basic': <String>['•'], // obscured value, not a placeholder
      'textarea.basic': <String>['Ship v1.4.0'], // seeded multi-line content
      'conversationnavigator.basic': <String>['Docs site'], // both entries fit
      'tooltip.basic': <String>['Saves the current file'], // tip shows on focus
      'modelstatusbar.basic': <String>[
        'Context',
        '%',
      ], // full bar, meter intact
      'autocomplete.basic': <String>['Apple'], // seeded query opens the matches
      'tracetimeline.basic': <String>['Publish report'], // third event fits
      // The preview's text can fit while its final border row is clipped.
      'animation.presence': <String>['✓ Publish'],
      // The tutorial-page embed: the full language list fits its frame.
      'tutorial.filter': <String>['10 of 10', 'Dart', 'Haskell'],
    };
    final missing = <String>[];
    for (final entry in checks.entries) {
      final fixture = await _mountExample(entry.key, useManifestSize: true);
      if (entry.key == 'animation.presence') {
        // Let the initial fade reach its passthrough state; at progress zero
        // the effect intentionally recolors every cell and is not a useful
        // oracle for the resting border geometry.
        await Future<void>.delayed(const Duration(milliseconds: 450));
        for (var i = 0; i < 4 && fixture.flush.pending; i++) {
          fixture.flush.fire();
        }
      }
      final painted =
          fixture.host.querySelector('.fleury-screen')?.textContent ?? '';
      if (entry.key == 'progressbar.basic') {
        final spans = fixture.host.querySelectorAll('.fleury-screen span');
        var hasPaintedFill = false;
        for (var i = 0; i < spans.length; i++) {
          final style = (spans.item(i) as web.Element).getAttribute('style');
          if (style != null && style.contains('background-image:')) {
            hasPaintedFill = true;
            break;
          }
        }
        if (!hasPaintedFill) missing.add('progressbar.basic → painted fill');
      }
      if (entry.key == 'animation.presence') {
        final rows = fixture.host.querySelectorAll('.fleury-row');
        var publishRow = -1;
        for (var i = 0; i < rows.length; i++) {
          if (((rows.item(i) as web.Element).textContent ?? '').contains(
            '✓ Publish',
          )) {
            publishRow = i;
            break;
          }
        }
        var hasBottomBorder = false;
        if (publishRow >= 0 && publishRow + 1 < rows.length) {
          final spans = (rows.item(publishRow + 1) as web.Element)
              .querySelectorAll('span');
          for (var i = 0; i < spans.length; i++) {
            final style = (spans.item(i) as web.Element).getAttribute('style');
            if (style != null && style.contains('background-image:')) {
              hasBottomBorder = true;
              break;
            }
          }
        }
        if (!hasBottomBorder) {
          missing.add('animation.presence → painted bottom border');
        }
      }
      for (final needle in entry.value) {
        if (!painted.contains(needle)) missing.add('${entry.key} → "$needle"');
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          'Essential demo content is clipped at the manifest frame size — give '
          'the example more cols/rows in registry.dart. Missing: $missing',
    );
  });

  // The landing/onboarding pages (index / getting-started / comparison .mdx)
  // embed catalog demos at their OWN cols/rows, overriding the manifest — so the
  // manifest-size guards above never exercise what those high-traffic pages
  // actually render. Guard them at their real embedded sizes. Keep this list in
  // sync with the `<FleuryExample ... cols={} rows={} />` embeds in those pages.
  test('landing-page demos render at their embedded sizes', () async {
    const embeds = <({String id, int cols, int rows, String needle})>[
      (id: 'digits.basic', cols: 56, rows: 11, needle: 'UTC'), // index.mdx
      (
        id: 'datatable.basic',
        cols: 48,
        rows: 8,
        needle: 'COMMITS',
      ), // index.mdx
      (id: 'barchart.basic', cols: 52, rows: 12, needle: 'q4'), // index.mdx
      (
        id: 'home.monitor',
        cols: 34,
        rows: 9,
        needle: 'CPU',
      ), // getting-started, comparison
    ];
    final missing = <String>[];
    for (final e in embeds) {
      final fixture = await _mountExample(e.id, cols: e.cols, rows: e.rows);
      final painted =
          fixture.host.querySelector('.fleury-screen')?.textContent ?? '';
      if (!painted.contains(e.needle)) {
        missing.add('${e.id} (${e.cols}x${e.rows}) → "${e.needle}"');
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          'A landing-page demo renders blank/clipped at its embedded size — fix '
          'the embed size in the .mdx (or the widget). Missing: $missing',
    );
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

  test(
    'navigation.basics makes push, present, and both pop paths explicit',
    () async {
      final fixture = await _mountExample(
        'navigation.basics',
        useManifestSize: true,
      );

      web.Element? focusedButton() => fixture.host.querySelector(
        '.fleury-semantics [role="button"][data-fleury-focused="true"]',
      );

      Future<void> settle() async {
        await Future<void>.delayed(Duration.zero);
        for (var i = 0; i < 6 && fixture.flush.pending; i++) {
          fixture.flush.fire();
          await Future<void>.delayed(Duration.zero);
        }
        await fixture.app.awaitSemanticIdle();
      }

      expect(fixture.host.textContent, contains('HOME · STACK DEPTH 1'));
      expect(focusedButton()?.textContent, contains('Push details'));
      expect(_rootRouteDepth(fixture.host), '1');

      _tapPaintedText(fixture.host, 'Push details');
      await settle();
      expect(fixture.host.textContent, contains('DETAILS · STACK DEPTH 2'));
      expect(focusedButton()?.textContent, contains('Present dialog'));
      expect(_rootRouteDepth(fixture.host), '2');

      _tapPaintedText(fixture.host, 'Present dialog');
      await settle();
      expect(fixture.host.textContent, contains('PRESENTED DIALOG'));
      expect(focusedButton()?.textContent, contains('Confirm and pop'));
      expect(_rootRouteDepth(fixture.host), '3');
      expect(
        fixture.host.querySelector('.fleury-screen')?.textContent,
        contains('Confirm and pop'),
        reason: 'the dialog action must be painted, not only semantic',
      );

      _tapPaintedText(fixture.host, 'Confirm and pop');
      await settle();
      expect(fixture.host.textContent, contains('dialog: confirmed'));
      expect(focusedButton()?.textContent, contains('Present dialog'));
      expect(_rootRouteDepth(fixture.host), '2');

      _tapPaintedText(fixture.host, 'Pop without result');
      await settle();
      expect(fixture.host.textContent, contains('result: none'));
      expect(_rootRouteDepth(fixture.host), '1');

      _tapPaintedText(fixture.host, 'Push details');
      await settle();
      expect(_rootRouteDepth(fixture.host), '2');
      _tapPaintedText(fixture.host, 'Pop with result');
      await settle();
      expect(fixture.host.textContent, contains('result: done'));
      expect(focusedButton()?.textContent, contains('Push details'));
      expect(_rootRouteDepth(fixture.host), '1');
    },
  );

  test('navigation.placement moves a real presented route', () async {
    final fixture = await _mountExample(
      'navigation.placement',
      useManifestSize: true,
    );
    final keyboardCapture =
        fixture.host.querySelector('textarea') as web.HTMLTextAreaElement;

    Future<void> settle() async {
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 6 && fixture.flush.pending; i++) {
        fixture.flush.fire();
        await Future<void>.delayed(Duration.zero);
      }
      await fixture.app.awaitSemanticIdle();
    }

    Future<void> press(String key) async {
      keyboardCapture.dispatchEvent(
        web.KeyboardEvent(
          'keydown',
          web.KeyboardEventInit(
            key: key,
            code: key,
            bubbles: true,
            cancelable: true,
          ),
        ),
      );
      await settle();
    }

    web.Element buttonNamed(String label) {
      final buttons = fixture.host.querySelectorAll(
        '.fleury-semantics [role="button"]',
      );
      for (var i = 0; i < buttons.length; i++) {
        final button = buttons.item(i)! as web.Element;
        if ((button.textContent ?? '').contains(label)) return button;
      }
      fail('No semantic button named "$label"');
    }

    web.Element paintedText(String label) {
      final spans = fixture.host.querySelectorAll(
        '.fleury-screen .fleury-row span',
      );
      for (var i = 0; i < spans.length; i++) {
        final span = spans.item(i)! as web.Element;
        if ((span.textContent ?? '').contains(label)) return span;
      }
      fail('No painted text named "$label"');
    }

    web.HTMLElement placementSelect() =>
        fixture.host.querySelector(
              '.fleury-semantics [role="button"][aria-label="Dialog placement"]',
            )!
            as web.HTMLElement;

    placementSelect().click();
    await settle();
    await press('ArrowUp');
    await press('Enter');
    final topLeft = paintedText('PLACED DIALOG').getBoundingClientRect();
    final hostBounds = fixture.host.getBoundingClientRect();
    expect(topLeft.left - hostBounds.left, lessThan(hostBounds.width / 3));
    expect(topLeft.top - hostBounds.top, lessThan(hostBounds.height / 3));

    (buttonNamed('Close') as web.HTMLElement).click();
    await settle();
    placementSelect().click();
    await settle();
    await press('ArrowDown');
    await press('ArrowDown');
    await press('Enter');
    final bottomRight = paintedText('PLACED DIALOG').getBoundingClientRect();
    expect(bottomRight.left, greaterThan(topLeft.left));
    expect(bottomRight.top, greaterThan(topLeft.top));
  });

  test(
    'navigation.guard blocks only after editing and allows back after save',
    () async {
      final fixture = await _mountExample(
        'navigation.guard',
        useManifestSize: true,
      );
      final keyboardCapture =
          fixture.host.querySelector('textarea[aria-hidden="true"]')!
              as web.HTMLTextAreaElement;

      Future<void> settle() async {
        await Future<void>.delayed(Duration.zero);
        for (var i = 0; i < 6 && fixture.flush.pending; i++) {
          fixture.flush.fire();
          await Future<void>.delayed(Duration.zero);
        }
        await fixture.app.awaitSemanticIdle();
      }

      expect(_rootRouteDepth(fixture.host), '1');
      _tapPaintedText(fixture.host, 'Edit draft');
      await settle();
      expect(_rootRouteDepth(fixture.host), '2');

      _tapPaintedText(fixture.host, 'Back');
      await settle();
      expect(fixture.host.textContent, contains('DRAFTS'));
      expect(_rootRouteDepth(fixture.host), '1');

      _tapPaintedText(fixture.host, 'Edit draft');
      await settle();
      expect(_rootRouteDepth(fixture.host), '2');
      final draftField = fixture.host.querySelector(
        '.fleury-semantics [role="textbox"][aria-label="Draft text"]',
      );
      expect(draftField, isNotNull);
      (draftField! as web.HTMLElement).click();
      await settle();
      keyboardCapture.dispatchEvent(
        web.InputEvent(
          'input',
          web.InputEventInit(
            data: ' updated',
            inputType: 'insertText',
            bubbles: true,
            cancelable: true,
          ),
        ),
      );
      await settle();
      expect(fixture.host.textContent, contains('Unsaved changes'));

      _tapPaintedText(fixture.host, 'Back');
      await settle();
      expect(fixture.host.textContent, contains('Back blocked — save first'));
      expect(fixture.host.textContent, contains('EDITOR'));
      expect(_rootRouteDepth(fixture.host), '2');

      _tapPaintedText(fixture.host, 'Save');
      await settle();
      _tapPaintedText(fixture.host, 'Back');
      await settle();
      expect(fixture.host.textContent, contains('DRAFTS'));
      expect(
        fixture.host.textContent,
        contains('saved: Release notes updated'),
      );
      expect(fixture.host.textContent, isNot(contains('EDITOR')));
      expect(_rootRouteDepth(fixture.host), '1');

      _tapPaintedText(fixture.host, 'Edit draft');
      await settle();
      final reopenedDraftField = fixture.host.querySelector(
        '.fleury-semantics [role="textbox"][aria-label="Draft text"]',
      );
      expect(reopenedDraftField, isA<web.HTMLInputElement>());
      expect(
        (reopenedDraftField! as web.HTMLInputElement).value,
        'Release notes updated',
      );
    },
  );

  test('navigation.transitions exposes animated and instant choices', () async {
    final fixture = await _mountExample(
      'navigation.transitions',
      useManifestSize: true,
    );

    Future<void> settle({Duration delay = Duration.zero}) async {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      for (var i = 0; i < 12 && fixture.flush.pending; i++) {
        fixture.flush.fire();
        await Future<void>.delayed(Duration.zero);
      }
      await fixture.app.awaitSemanticIdle();
    }

    web.Element buttonNamed(String label) {
      final buttons = fixture.host.querySelectorAll(
        '.fleury-semantics [role="button"]',
      );
      for (var i = 0; i < buttons.length; i++) {
        final button = buttons.item(i)! as web.Element;
        if ((button.textContent ?? '').contains(label)) return button;
      }
      fail('No semantic button named "$label"');
    }

    _tapPaintedText(fixture.host, 'Slide');
    await settle();
    expect(
      fixture.host.querySelector('.fleury-semantics [role="menu"]'),
      isNotNull,
      reason: 'clicking the picker opens it',
    );
    _tapPaintedText(fixture.host, 'Slide');
    await settle();
    expect(
      fixture.host.querySelector('.fleury-semantics [role="menu"]'),
      isNull,
      reason: 'clicking the open picker closes it',
    );

    (buttonNamed('Preview push') as web.HTMLElement).click();
    await settle(delay: const Duration(milliseconds: 260));
    expect(fixture.host.textContent, contains('SLIDE · PUSHED SCREEN'));
    (buttonNamed('Preview pop') as web.HTMLElement).click();
    await settle(delay: const Duration(milliseconds: 260));
    expect(fixture.host.textContent, contains('ROUTE TRANSITIONS'));
  });

  test(
    'navigation.nested-flow completes its inner stack as one outer route',
    () async {
      final fixture = await _mountExample(
        'navigation.nested-flow',
        useManifestSize: true,
      );
      final keyboardCapture =
          fixture.host.querySelector('textarea') as web.HTMLTextAreaElement;

      Future<void> settle() async {
        await Future<void>.delayed(Duration.zero);
        for (var i = 0; i < 6 && fixture.flush.pending; i++) {
          fixture.flush.fire();
          await Future<void>.delayed(Duration.zero);
        }
        await fixture.app.awaitSemanticIdle();
      }

      web.Element buttonNamed(String label) {
        final buttons = fixture.host.querySelectorAll(
          '.fleury-semantics [role="button"]',
        );
        for (var i = 0; i < buttons.length; i++) {
          final button = buttons.item(i)! as web.Element;
          if ((button.textContent ?? '').contains(label)) return button;
        }
        fail('No semantic button named "$label"');
      }

      Future<void> pressEscape() async {
        keyboardCapture.dispatchEvent(
          web.KeyboardEvent(
            'keydown',
            web.KeyboardEventInit(
              key: 'Escape',
              code: 'Escape',
              bubbles: true,
              cancelable: true,
            ),
          ),
        );
        await settle();
      }

      expect(fixture.host.textContent, contains('PROJECTS · OUTER STACK 1'));
      expect(_rootRouteDepth(fixture.host), '1');
      (buttonNamed('Start setup') as web.HTMLElement).click();
      await settle();
      expect(fixture.host.textContent, contains('SETUP · OUTER STACK 2'));
      expect(fixture.host.textContent, contains('INNER STEP 1 OF 3'));
      expect(_rootRouteDepth(fixture.host), '2');
      (buttonNamed('Next step') as web.HTMLElement).click();
      await settle();
      expect(fixture.host.textContent, contains('INNER STEP 2 OF 3'));
      expect(fixture.host.textContent, contains('SETUP · OUTER STACK 2'));
      expect(_rootRouteDepth(fixture.host), '2');
      (buttonNamed('Next step') as web.HTMLElement).click();
      await settle();
      expect(fixture.host.textContent, contains('INNER STEP 3 OF 3'));
      await pressEscape();
      expect(fixture.host.textContent, contains('INNER STEP 2 OF 3'));
      expect(fixture.host.textContent, contains('SETUP · OUTER STACK 2'));
      (buttonNamed('Next step') as web.HTMLElement).click();
      await settle();
      (buttonNamed('Finish setup') as web.HTMLElement).click();
      await settle();
      expect(
        fixture.host.textContent,
        contains('PROJECT READY · OUTER STACK 2'),
      );
      expect(fixture.host.textContent, isNot(contains('INNER STEP')));
      expect(_rootRouteDepth(fixture.host), '2');
      (buttonNamed('Back to projects') as web.HTMLElement).click();
      await settle();
      expect(fixture.host.textContent, contains('PROJECTS · OUTER STACK 1'));
      expect(_rootRouteDepth(fixture.host), '1');
    },
  );

  test(
    'forms.project exposes validation and a successful typed submit',
    () async {
      final fixture = await _mountExample(
        'forms.project',
        useManifestSize: true,
      );
      final keyboardCapture =
          fixture.host.querySelector('textarea[aria-hidden="true"]')!
              as web.HTMLTextAreaElement;

      Future<void> settle() async {
        await Future<void>.delayed(Duration.zero);
        for (var i = 0; i < 6 && fixture.flush.pending; i++) {
          fixture.flush.fire();
          await Future<void>.delayed(Duration.zero);
        }
        await fixture.app.awaitSemanticIdle();
      }

      Future<void> typeText(String value) async {
        keyboardCapture.dispatchEvent(
          web.InputEvent(
            'input',
            web.InputEventInit(
              data: value,
              inputType: 'insertText',
              bubbles: true,
              cancelable: true,
            ),
          ),
        );
        await settle();
      }

      web.Element buttonNamed(String label) {
        final buttons = fixture.host.querySelectorAll(
          '.fleury-semantics [role="button"]',
        );
        for (var i = 0; i < buttons.length; i++) {
          final button = buttons.item(i)! as web.Element;
          if ((button.textContent ?? '').contains(label)) return button;
        }
        fail('No semantic button named "$label"');
      }

      expect(fixture.host.textContent, contains('Fill in the project details'));
      (buttonNamed('Create') as web.HTMLElement).click();
      await settle();
      expect(fixture.host.textContent, contains('status: Fix 2 field(s)'));
      expect(
        fixture.host.querySelector('.fleury-screen')?.textContent,
        allOf(contains('Name is required'), contains('Slug is required')),
        reason: 'field errors must be painted beside the controls',
      );

      final textboxes = fixture.host.querySelectorAll(
        '.fleury-semantics [role="textbox"]',
      );
      (textboxes.item(0)! as web.HTMLElement).click();
      await settle();
      await typeText('Fleury');
      (textboxes.item(1)! as web.HTMLElement).click();
      await settle();
      await typeText('fleury-app');
      final checkbox = fixture.host.querySelector(
        '.fleury-semantics [role="checkbox"]',
      )!;
      (checkbox as web.HTMLElement).click();
      await settle();
      (buttonNamed('Create') as web.HTMLElement).click();
      await settle();

      expect(fixture.host.textContent, contains('status: Created Fleury'));
      expect(
        fixture.host
            .querySelector('.fleury-semantics [role="checkbox"]')
            ?.getAttribute('aria-checked'),
        'true',
      );
    },
  );

  test(
    'lists.tasks pages, activates, and keeps the selection visible',
    () async {
      final fixture = await _mountExample('lists.tasks', useManifestSize: true);
      final keyboardCapture =
          fixture.host.querySelector('textarea') as web.HTMLTextAreaElement;

      Future<void> press(String key, {String? code}) async {
        keyboardCapture.dispatchEvent(
          web.KeyboardEvent(
            'keydown',
            web.KeyboardEventInit(
              key: key,
              code: code ?? key,
              bubbles: true,
              cancelable: true,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        for (var i = 0; i < 6 && fixture.flush.pending; i++) {
          fixture.flush.fire();
          await Future<void>.delayed(Duration.zero);
        }
        await fixture.app.awaitSemanticIdle();
      }

      expect(fixture.host.textContent, contains('selected: 1 / 1000'));
      await press('ArrowDown');
      expect(fixture.host.textContent, contains('selected: 2 / 1000'));
      await press('PageDown');
      expect(
        fixture.host.textContent,
        isNot(contains('selected: 2 / 1000')),
        reason: 'PageDown should advance by the visible page',
      );
      await press('End');
      expect(fixture.host.textContent, contains('selected: 1000 / 1000'));
      expect(
        fixture.host.querySelector('.fleury-screen')?.textContent,
        contains('Task 1000'),
        reason: 'the viewport must follow the selected row',
      );
      await press('Enter', code: 'Enter');
      expect(fixture.host.textContent, contains('last: Opened task 1000'));
      await press('Home');
      expect(fixture.host.textContent, contains('selected: 1 / 1000'));
    },
  );

  test(
    'layout.responsive changes actual pane geometry at its breakpoint',
    () async {
      final fixture = await _mountExample(
        'layout.responsive',
        useManifestSize: true,
      );

      Future<void> settle() async {
        await Future<void>.delayed(Duration.zero);
        for (var i = 0; i < 6 && fixture.flush.pending; i++) {
          fixture.flush.fire();
          await Future<void>.delayed(Duration.zero);
        }
        await fixture.app.awaitSemanticIdle();
      }

      web.Element paintedText(String label) {
        final spans = fixture.host.querySelectorAll(
          '.fleury-screen .fleury-row span',
        );
        for (var i = 0; i < spans.length; i++) {
          final span = spans.item(i)! as web.Element;
          if ((span.textContent ?? '').trim() == label) return span;
        }
        fail('No painted text named "$label"');
      }

      web.Element buttonNamed(String label) {
        final buttons = fixture.host.querySelectorAll(
          '.fleury-semantics [role="button"]',
        );
        for (var i = 0; i < buttons.length; i++) {
          final button = buttons.item(i)! as web.Element;
          if ((button.textContent ?? '').contains(label)) return button;
        }
        fail('No semantic button named "$label"');
      }

      expect(fixture.host.textContent, contains('WIDE · TWO PANES'));
      final wideFiles = paintedText('Files').getBoundingClientRect();
      final widePreview = paintedText('Preview').getBoundingClientRect();
      expect(widePreview.left, greaterThan(wideFiles.right));
      expect((widePreview.top - wideFiles.top).abs(), lessThan(2));

      (buttonNamed('Narrow') as web.HTMLElement).click();
      await settle();
      expect(fixture.host.textContent, contains('NARROW · STACKED'));
      final narrowFiles = paintedText('Files').getBoundingClientRect();
      final narrowPreview = paintedText('Preview').getBoundingClientRect();
      expect(narrowPreview.top, greaterThan(narrowFiles.bottom));
      expect((narrowPreview.left - narrowFiles.left).abs(), lessThan(2));

      (buttonNamed('Wide') as web.HTMLElement).click();
      await settle();
      expect(fixture.host.textContent, contains('WIDE · TWO PANES'));
    },
  );

  test('focus.explorer demonstrates traversal and a trapped modal', () async {
    final fixture = await _mountExample(
      'focus.explorer',
      useManifestSize: true,
    );
    final keyboardCapture =
        fixture.host.querySelector('textarea') as web.HTMLTextAreaElement;

    web.Element? focusedButton() => fixture.host.querySelector(
      '.fleury-semantics [role="button"][data-fleury-focused="true"]',
    );

    Future<void> settle() async {
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 4 && fixture.flush.pending; i++) {
        fixture.flush.fire();
      }
      await fixture.app.awaitSemanticIdle();
    }

    Future<void> press(String key, {String? code, bool shift = false}) async {
      keyboardCapture.dispatchEvent(
        web.KeyboardEvent(
          'keydown',
          web.KeyboardEventInit(
            key: key,
            code: code ?? key,
            shiftKey: shift,
            bubbles: true,
            cancelable: true,
          ),
        ),
      );
      await settle();
    }

    web.Element buttonNamed(String label) {
      final buttons = fixture.host.querySelectorAll(
        '.fleury-semantics [role="button"]',
      );
      for (var i = 0; i < buttons.length; i++) {
        final button = buttons.item(i)! as web.Element;
        if ((button.textContent ?? '').contains(label)) return button;
      }
      fail('No semantic button named "$label"');
    }

    expect(focusedButton()?.textContent, contains('New file'));
    expect(fixture.host.textContent, contains('AUTOMATIC'));
    final primaryButtons = fixture.host.querySelectorAll(
      '.fleury-semantics [role="button"]',
    );
    expect(primaryButtons.length, 6);
    final buttonWidths = <int>{};
    for (var i = 0; i < primaryButtons.length; i++) {
      final button = primaryButtons.item(i)! as web.Element;
      buttonWidths.add(button.getBoundingClientRect().width.round());
    }
    expect(
      buttonWidths,
      hasLength(1),
      reason: 'the two action columns should use one consistent button width',
    );
    expect(
      fixture.host.querySelector('.fleury-screen')?.textContent,
      contains(RegExp(r'\[\s+Publish…\s+\]')),
      reason: 'the full button label and closing bracket must be painted',
    );

    await press('Tab', code: 'Tab');
    expect(
      focusedButton()?.textContent,
      contains('Refresh'),
      reason: 'Tab follows painted row-major reading order',
    );
    await press('Tab', code: 'Tab', shift: true);
    expect(focusedButton()?.textContent, contains('New file'));

    await press('ArrowRight');
    expect(focusedButton()?.textContent, contains('Refresh'));
    expect(fixture.host.textContent, contains('active: Preview'));
    await press('ArrowDown');
    expect(focusedButton()?.textContent, contains('Inspect'));
    await press('ArrowLeft');
    expect(focusedButton()?.textContent, contains('Open file'));

    (buttonNamed('Publish') as web.HTMLElement).click();
    await settle();
    expect(fixture.host.textContent, contains('Publish?'));
    expect(focusedButton()?.textContent, contains('Cancel'));

    await press('Tab', code: 'Tab');
    expect(focusedButton()?.textContent, contains('Publish'));
    await press('Tab', code: 'Tab');
    expect(
      focusedButton()?.textContent,
      contains('Cancel'),
      reason: 'Tab must wrap inside the modal instead of reaching the panes',
    );

    await press('Enter', code: 'Enter');
    // Navigator completes the dialog future after the removal frame; yield
    // once more so the awaiting screen can publish its result state.
    await settle();
    expect(fixture.host.textContent, isNot(contains('Publish?')));
    expect(focusedButton()?.textContent, contains('Publish'));
    expect(fixture.host.textContent, contains('Publish canceled'));
  });

  test('focusnode.programmatic visibly hands focus to its target', () async {
    final fixture = await _mountExample(
      'focusnode.programmatic',
      useManifestSize: true,
    );
    final keyboardCapture =
        fixture.host.querySelector('textarea') as web.HTMLTextAreaElement;

    web.Element? focusedControl() => fixture.host.querySelector(
      '.fleury-semantics [data-fleury-focused="true"]',
    );

    expect(focusedControl()?.textContent, contains('Focus search'));
    expect(
      fixture.host.querySelector('.fleury-screen')?.textContent,
      allOf(contains('Focus search'), contains('Search files')),
    );

    keyboardCapture.dispatchEvent(
      web.KeyboardEvent(
        'keydown',
        web.KeyboardEventInit(
          key: 'Enter',
          code: 'Enter',
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

    final searchField = fixture.host.querySelector(
      '.fleury-semantics [role="textbox"][data-fleury-focused="true"]',
    );
    expect(searchField, isNotNull);
    expect(searchField?.getAttribute('aria-label'), 'Search files');
    expect(fixture.host.textContent, contains('Focus moved to Search files'));

    keyboardCapture.dispatchEvent(
      web.InputEvent(
        'input',
        web.InputEventInit(
          data: 'logs',
          inputType: 'insertText',
          bubbles: true,
          cancelable: true,
        ),
      ),
    );
    expect(fixture.flush.pending, isTrue);
    fixture.flush.fire();
    await fixture.app.awaitSemanticIdle();

    final updatedSearchField =
        fixture.host.querySelector(
              '.fleury-semantics [role="textbox"][data-fleury-focused="true"]',
            )
            as web.HTMLInputElement;
    expect(updatedSearchField.value, 'logs');
    expect(fixture.host.textContent, contains('Searching for "logs"'));
  });

  test(
    'focusdetector.basic reports subtree crossings, not child moves',
    () async {
      final fixture = await _mountExample(
        'focusdetector.basic',
        useManifestSize: true,
      );
      final keyboardCapture =
          fixture.host.querySelector('textarea') as web.HTMLTextAreaElement;

      web.Element? focusedButton() => fixture.host.querySelector(
        '.fleury-semantics [role="button"][data-fleury-focused="true"]',
      );

      Future<void> pressTab() async {
        keyboardCapture.dispatchEvent(
          web.KeyboardEvent(
            'keydown',
            web.KeyboardEventInit(
              key: 'Tab',
              code: 'Tab',
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
      }

      expect(focusedButton()?.textContent, contains('Title'));
      expect(fixture.host.textContent, contains('boundary changes: 1'));
      expect(
        fixture.host.querySelector('.fleury-screen')?.textContent,
        allOf(contains('Title'), contains('Body'), contains('Preview')),
        reason: 'the teaching controls must be painted, not only semantic',
      );

      await pressTab();
      expect(focusedButton()?.textContent, contains('Body'));
      expect(
        fixture.host.textContent,
        contains('boundary changes: 1'),
        reason: 'moving inside the editor must not emit a boundary change',
      );

      await pressTab();
      expect(focusedButton()?.textContent, contains('Preview'));
      expect(fixture.host.textContent, contains('editor: inactive'));
      expect(fixture.host.textContent, contains('boundary changes: 2'));
      expect(
        fixture.host.querySelector('.fleury-screen')?.textContent,
        allOf(contains('Title'), contains('Body'), contains('Preview')),
        reason: 'the observed region must stay visible after focus leaves',
      );
    },
  );

  test('keydetector.basic makes consumption and bubbling visible', () async {
    final fixture = await _mountExample(
      'keydetector.basic',
      useManifestSize: true,
    );
    final keyboardCapture =
        fixture.host.querySelector('textarea') as web.HTMLTextAreaElement;

    Future<void> pressDown() async {
      keyboardCapture.dispatchEvent(
        web.KeyboardEvent(
          'keydown',
          web.KeyboardEventInit(
            key: 'ArrowDown',
            code: 'ArrowDown',
            bubbles: true,
            cancelable: true,
          ),
        ),
      );
      expect(fixture.flush.pending, isTrue);
      fixture.flush.fire();
      await fixture.app.awaitSemanticIdle();
    }

    await pressDown();
    await pressDown();
    expect(fixture.host.textContent, contains('PANE  HANDLED · moved'));
    expect(fixture.host.textContent, contains('APP   — not reached'));
    expect(fixture.host.textContent, contains('pane 2 · app 0'));

    await pressDown();
    expect(fixture.host.textContent, contains('PANE  PASSED · at edge'));
    expect(fixture.host.textContent, contains('APP   HANDLED'));
    expect(fixture.host.textContent, contains('pane 2 · app 1'));
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
    // Assert on content near the top of the sample: the view is scrollable and
    // only paints the visible rows, so a token lower in the file (e.g. the
    // CounterApp class) can fall below the fold as the sample grows.
    expect(host.textContent, contains('runApp'));
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
