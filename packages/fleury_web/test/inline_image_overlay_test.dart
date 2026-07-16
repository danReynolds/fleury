// End-to-end browser coverage for the inline-image `<img>` overlay — the
// DOM-reconcile half of the serve image path that VM tests structurally can't
// exercise. Drives the real InlineImageOverlay against a real host element and
// asserts the resulting <img> elements, their positions (including the canvas
// offset), object-fit, and lifecycle (dedup occurrence keying, removal,
// dispose). Runs on Chrome via `dart test -p chrome`.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:fleury/fleury_host.dart'
    show InlineImageCachePolicy, InlineImageFit;
import 'package:fleury/src/remote/remote_codec.dart' show ImagePlacement;
import 'package:fleury_web/src/metrics/cell_metrics.dart';
import 'package:fleury_web/src/dom_grid/inline_image_overlay.dart';
import 'package:fleury_web/src/metrics/dom_cell_metrics.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

MeasuredCellBox _box({
  double cw = 10,
  double ch = 20,
  double insetX = 0,
  double insetY = 0,
  bool hostPositionIsStatic = true,
}) => MeasuredCellBox(
  cssCellWidth: cw,
  cssCellHeight: ch,
  cssCanvasWidth: cw * 80,
  cssCanvasHeight: ch * 24,
  devicePixelRatio: 1,
  cols: 80,
  rows: 24,
  cssCanvasInsetLeft: insetX,
  cssCanvasInsetTop: insetY,
  hostPositionIsStatic: hostPositionIsStatic,
);

ImagePlacement _place(
  String id,
  int col,
  int row,
  int cols,
  int rows, [
  InlineImageFit fit = InlineImageFit.contain,
]) => ImagePlacement(
  id: id,
  col: col,
  row: row,
  cols: cols,
  rows: rows,
  fit: fit,
);

List<web.HTMLImageElement> _imgs(web.HTMLElement host) {
  final nodes = host.querySelectorAll('img');
  return [
    for (var i = 0; i < nodes.length; i++)
      nodes.item(i)! as web.HTMLImageElement,
  ];
}

web.HTMLElement _makeHost() {
  final host = web.document.createElement('div') as web.HTMLElement;
  web.document.body!.appendChild(host);
  return host;
}

void main() {
  test('renders one positioned <img> with object-fit + canvas offset', () {
    final host = _makeHost();
    final overlay = InlineImageOverlay(host)
      ..cacheImage('a', Uint8List.fromList([1, 2, 3, 4]))
      ..presentPlan([
        _place('a', 2, 1, 3, 2, InlineImageFit.cover),
      ], _box(cw: 10, ch: 20, insetX: 5, insetY: 7));

    final imgs = _imgs(host);
    expect(imgs, hasLength(1));
    final img = imgs.single;
    // left = host-local inset + col*cw; top = inset + row*ch.
    expect(img.style.left, '25px');
    expect(img.style.top, '27px');
    expect(img.style.width, '30px'); // cols*cw
    expect(img.style.height, '40px'); // rows*ch
    expect(img.style.getPropertyValue('object-fit'), 'cover');
    expect(img.alt, '', reason: 'decorative — semantics ride the separate DOM');

    overlay.dispose();
    host.remove();
  });

  test('positioned host uses local inset without double-counting its viewport '
      'origin', () {
    final host = _makeHost()
      ..setAttribute(
        'style',
        'margin-left:73px;margin-top:41px;width:400px;height:240px;'
            'box-sizing:border-box;border:7px solid transparent;'
            'padding:11px 17px 13px 19px;'
            'font-family:monospace;font-size:10px;line-height:20px;',
      );
    final metrics = DomCellMetrics(container: host);
    final box = metrics.measure();
    final overlay = InlineImageOverlay(host)
      ..cacheImage('positioned', Uint8List.fromList([1, 2, 3, 4]))
      ..presentPlan([_place('positioned', 2, 1, 3, 2)], box);
    addTearDown(() {
      overlay.dispose();
      metrics.dispose();
      host.remove();
    });

    final imageRect = _imgs(host).single.getBoundingClientRect();
    expect(box.cssCanvasInsetLeft, closeTo(19, 0.01));
    expect(box.cssCanvasInsetTop, closeTo(11, 0.01));
    expect(
      imageRect.left,
      closeTo(box.cssCanvasLeft + 2 * box.cssCellWidth, 0.5),
      reason: 'image viewport x matches the grid cell, not host x + grid x',
    );
    expect(
      imageRect.top,
      closeTo(box.cssCanvasTop + box.cssCellHeight, 0.5),
      reason: 'image viewport y matches the grid cell, not host y + grid y',
    );
    expect(imageRect.width, closeTo(3 * box.cssCellWidth, 0.5));
    expect(imageRect.height, closeTo(2 * box.cssCellHeight, 0.5));
  });

  test(
    'preserves embedder positioning and restores an owned static position',
    () {
      for (final position in const [
        'relative',
        'absolute',
        'fixed',
        'sticky',
      ]) {
        final positionedHost = _makeHost();
        positionedHost.style.setProperty('position', position);
        final positionedOverlay = InlineImageOverlay(positionedHost)
          ..presentPlan(const [], _box(hostPositionIsStatic: false));

        expect(positionedHost.style.getPropertyValue('position'), position);
        positionedOverlay.dispose();
        expect(positionedHost.style.getPropertyValue('position'), position);
        positionedHost.remove();
      }

      final stylesheetPositionedHost = _makeHost();
      final stylesheetPositionedOverlay = InlineImageOverlay(
        stylesheetPositionedHost,
      )..presentPlan(const [], _box(hostPositionIsStatic: false));
      expect(
        stylesheetPositionedHost.style.getPropertyValue('position'),
        isEmpty,
        reason: 'a non-static computed style must not be shadowed inline',
      );
      stylesheetPositionedOverlay.dispose();
      stylesheetPositionedHost.remove();

      final staticHost = _makeHost();
      staticHost.style.setProperty('position', 'static');
      final staticOverlay = InlineImageOverlay(staticHost)
        ..presentPlan(const [], _box());

      expect(staticHost.style.getPropertyValue('position'), 'relative');
      staticOverlay.dispose();
      expect(staticHost.style.getPropertyValue('position'), 'static');
      staticHost.remove();
    },
  );

  test('positions a computed-static inherited host and restores its exact '
      'inline token', () {
    final host = _makeHost()
      ..setAttribute(
        'style',
        'position:inherit;margin-left:53px;margin-top:31px;'
            'width:240px;height:120px;padding:7px 11px;'
            'font-family:monospace;font-size:10px;line-height:20px;',
      )
      ..style.setProperty('position', 'inherit', 'important');
    final metrics = DomCellMetrics(container: host);
    final box = metrics.measure();
    expect(box.hostPositionIsStatic, isTrue);
    expect(host.style.getPropertyValue('position'), 'inherit');
    expect(host.style.getPropertyPriority('position'), 'important');

    final overlay = InlineImageOverlay(host)
      ..cacheImage('inherited', Uint8List.fromList([1, 2, 3, 4]))
      ..presentPlan([_place('inherited', 2, 1, 1, 1)], box);

    expect(host.style.getPropertyValue('position'), 'relative');
    expect(host.style.getPropertyPriority('position'), isEmpty);
    final imageRect = _imgs(host).single.getBoundingClientRect();
    expect(
      imageRect.left,
      closeTo(box.cssCanvasLeft + 2 * box.cssCellWidth, 0.5),
    );
    expect(imageRect.top, closeTo(box.cssCanvasTop + box.cssCellHeight, 0.5));

    overlay.dispose();
    expect(host.style.getPropertyValue('position'), 'inherit');
    expect(host.style.getPropertyPriority('position'), 'important');
    metrics.dispose();
    host.remove();
  });

  test('same id at two positions yields two distinct <img> elements', () {
    final host = _makeHost();
    final overlay = InlineImageOverlay(host)
      ..cacheImage('logo', Uint8List.fromList([9, 9, 9]))
      ..presentPlan([
        _place('logo', 0, 0, 2, 1),
        _place('logo', 10, 0, 2, 1),
      ], _box());

    final imgs = _imgs(host);
    expect(
      imgs,
      hasLength(2),
      reason: 'one element per placement, shared bytes',
    );
    expect(imgs.map((e) => e.style.left).toSet(), {'0px', '100px'});

    overlay.dispose();
    host.remove();
  });

  test('a placement that disappears drops its <img>', () {
    final host = _makeHost();
    final overlay = InlineImageOverlay(host)
      ..cacheImage('a', Uint8List.fromList([1]))
      ..presentPlan([_place('a', 0, 0, 1, 1)], _box());
    expect(_imgs(host), hasLength(1));

    overlay.presentPlan(const [], _box()); // image gone this frame
    expect(_imgs(host), isEmpty, reason: 'unplaced images are removed');

    overlay.dispose();
    host.remove();
  });

  test('a moving image keeps one element, repositioned', () {
    final host = _makeHost();
    final overlay = InlineImageOverlay(host)
      ..cacheImage('a', Uint8List.fromList([1]))
      ..presentPlan([_place('a', 0, 0, 2, 2)], _box(cw: 10, ch: 20));
    expect(_imgs(host).single.style.left, '0px');

    overlay.presentPlan([_place('a', 4, 0, 2, 2)], _box(cw: 10, ch: 20));
    final imgs = _imgs(host);
    expect(imgs, hasLength(1), reason: 'reused, not recreated');
    expect(imgs.single.style.left, '40px', reason: 'repositioned');

    overlay.dispose();
    host.remove();
  });

  test('a placement whose bytes have not arrived renders nothing yet', () {
    final host = _makeHost();
    final overlay = InlineImageOverlay(host)
      ..presentPlan([_place('missing', 0, 0, 1, 1)], _box());
    expect(_imgs(host), isEmpty, reason: 'waits for the InlineImageFrame');

    // Once cached, a later frame renders it.
    overlay
      ..cacheImage('missing', Uint8List.fromList([1]))
      ..presentPlan([_place('missing', 0, 0, 1, 1)], _box());
    expect(_imgs(host), hasLength(1));

    overlay.dispose();
    host.remove();
  });

  test('byte budget evicts the oldest stale blob deterministically', () {
    final host = _makeHost();
    final overlay = InlineImageOverlay(
      host,
      cachePolicy: const InlineImageCachePolicy(maxEntries: 512, maxBytes: 8),
    );
    overlay
      ..cacheImage('oldest', Uint8List(6))
      ..presentPlan([_place('oldest', 0, 0, 1, 1)], _box())
      ..cacheImage('newer', Uint8List(2))
      ..presentPlan([_place('newer', 0, 0, 1, 1)], _box())
      ..cacheImage('placed', Uint8List(3))
      ..presentPlan([_place('placed', 0, 0, 1, 1)], _box());

    expect(overlay.cachedImageCount, 2);
    expect(overlay.cachedImageBytes, 5);

    overlay.presentPlan([_place('oldest', 0, 0, 1, 1)], _box());
    expect(_imgs(host), isEmpty, reason: 'the oldest stale blob was evicted');

    overlay.presentPlan([_place('newer', 0, 0, 1, 1)], _box());
    expect(_imgs(host), hasLength(1), reason: 'newer stale blob was retained');

    overlay.dispose();
    host.remove();
  });

  test('an oversized pending image is rejected without retaining bytes', () {
    final host = _makeHost();
    final overlay = InlineImageOverlay(
      host,
      cachePolicy: const InlineImageCachePolicy(maxEntries: 512, maxBytes: 8),
    );

    expect(overlay.cacheImage('oversized', Uint8List(9)), isFalse);
    expect(overlay.pendingImageCount, 0);
    expect(overlay.pendingImageBytes, 0);
    expect(overlay.cachedImageCount, 0);
    expect(overlay.cachedImageBytes, 0);
    overlay.presentPlan([_place('oversized', 0, 0, 1, 1)], _box());
    expect(_imgs(host), isEmpty, reason: 'excess content degrades to blank');

    overlay.dispose();
    host.remove();
  });

  test('an image-only stream is bounded to one pending plan batch', () {
    final host = _makeHost();
    final overlay = InlineImageOverlay(
      host,
      cachePolicy: const InlineImageCachePolicy(maxEntries: 2, maxBytes: 8),
    );

    expect(overlay.cacheImage('a', Uint8List(6)), isTrue);
    expect(overlay.cacheImage('b', Uint8List(2)), isTrue);
    expect(overlay.cacheImage('c', Uint8List(1)), isFalse);
    expect(overlay.pendingImageCount, 2);
    expect(overlay.pendingImageBytes, 8);
    expect(overlay.cachedImageCount, 0, reason: 'no plan has committed them');

    overlay.presentPlan(const [], _box());
    expect(overlay.pendingImageCount, 0, reason: 'the next plan clears batch');
    expect(overlay.pendingImageBytes, 0);

    overlay.dispose();
    host.remove();
  });

  test('resize reapply does not consume the next plan image batch', () {
    final host = _makeHost();
    final overlay = InlineImageOverlay(host);

    overlay.cacheImage('next', Uint8List.fromList([1, 2, 3]));
    overlay.reapply(_box(cw: 12, ch: 24));

    expect(overlay.pendingImageCount, 1);
    expect(overlay.cachedImageCount, 0);

    overlay.presentPlan([_place('next', 1, 1, 2, 1)], _box());
    expect(overlay.pendingImageCount, 0);
    expect(overlay.cachedImageCount, 1);
    expect(_imgs(host), hasLength(1));

    overlay.dispose();
    host.remove();
  });

  test('dispose removes the overlay layer from the host', () {
    final host = _makeHost();
    final overlay = InlineImageOverlay(host)
      ..cacheImage('a', Uint8List.fromList([1]))
      ..presentPlan([_place('a', 0, 0, 1, 1)], _box());
    expect(host.children.length, 1, reason: 'the overlay div');

    overlay.dispose();
    expect(host.children.length, 0, reason: 'overlay removed on dispose');
    host.remove();
  });
}
