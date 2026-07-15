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
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

MeasuredCellBox _box({
  double cw = 10,
  double ch = 20,
  double ox = 0,
  double oy = 0,
}) => MeasuredCellBox(
  cssCellWidth: cw,
  cssCellHeight: ch,
  cssCanvasWidth: cw * 80,
  cssCanvasHeight: ch * 24,
  devicePixelRatio: 1,
  cols: 80,
  rows: 24,
  cssCanvasLeft: ox,
  cssCanvasTop: oy,
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
      ..apply([
        _place('a', 2, 1, 3, 2, InlineImageFit.cover),
      ], _box(cw: 10, ch: 20, ox: 5, oy: 7));

    final imgs = _imgs(host);
    expect(imgs, hasLength(1));
    final img = imgs.single;
    // left = canvasLeft + col*cw = 5 + 2*10; top = 7 + 1*20.
    expect(img.style.left, '25px');
    expect(img.style.top, '27px');
    expect(img.style.width, '30px'); // cols*cw
    expect(img.style.height, '40px'); // rows*ch
    expect(img.style.getPropertyValue('object-fit'), 'cover');
    expect(img.alt, '', reason: 'decorative — semantics ride the separate DOM');

    overlay.dispose();
    host.remove();
  });

  test('same id at two positions yields two distinct <img> elements', () {
    final host = _makeHost();
    final overlay = InlineImageOverlay(host)
      ..cacheImage('logo', Uint8List.fromList([9, 9, 9]))
      ..apply([
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
      ..apply([_place('a', 0, 0, 1, 1)], _box());
    expect(_imgs(host), hasLength(1));

    overlay.apply(const [], _box()); // image gone this frame
    expect(_imgs(host), isEmpty, reason: 'unplaced images are removed');

    overlay.dispose();
    host.remove();
  });

  test('a moving image keeps one element, repositioned', () {
    final host = _makeHost();
    final overlay = InlineImageOverlay(host)
      ..cacheImage('a', Uint8List.fromList([1]))
      ..apply([_place('a', 0, 0, 2, 2)], _box(cw: 10, ch: 20));
    expect(_imgs(host).single.style.left, '0px');

    overlay.apply([_place('a', 4, 0, 2, 2)], _box(cw: 10, ch: 20));
    final imgs = _imgs(host);
    expect(imgs, hasLength(1), reason: 'reused, not recreated');
    expect(imgs.single.style.left, '40px', reason: 'repositioned');

    overlay.dispose();
    host.remove();
  });

  test('a placement whose bytes have not arrived renders nothing yet', () {
    final host = _makeHost();
    final overlay = InlineImageOverlay(host)
      ..apply([_place('missing', 0, 0, 1, 1)], _box());
    expect(_imgs(host), isEmpty, reason: 'waits for the InlineImageFrame');

    // Once cached, a later frame renders it.
    overlay
      ..cacheImage('missing', Uint8List.fromList([1]))
      ..apply([_place('missing', 0, 0, 1, 1)], _box());
    expect(_imgs(host), hasLength(1));

    overlay.dispose();
    host.remove();
  });

  test('byte budget evicts the oldest stale blob deterministically', () {
    final host = _makeHost();
    final overlay =
        InlineImageOverlay(
            host,
            cachePolicy: const InlineImageCachePolicy(
              maxEntries: 512,
              maxBytes: 8,
            ),
          )
          ..cacheImage('oldest', Uint8List(6))
          ..cacheImage('newer', Uint8List(2))
          ..cacheImage('placed', Uint8List(3))
          ..apply([_place('placed', 0, 0, 1, 1)], _box());

    expect(overlay.cachedImageCount, 2);
    expect(overlay.cachedImageBytes, 5);

    overlay.apply([_place('oldest', 0, 0, 1, 1)], _box());
    expect(_imgs(host), isEmpty, reason: 'the oldest stale blob was evicted');

    overlay.apply([_place('newer', 0, 0, 1, 1)], _box());
    expect(_imgs(host), hasLength(1), reason: 'newer stale blob was retained');

    overlay.dispose();
    host.remove();
  });

  test('oversized placed image survives while every stale blob is evicted', () {
    final host = _makeHost();
    final overlay =
        InlineImageOverlay(
            host,
            cachePolicy: const InlineImageCachePolicy(
              maxEntries: 512,
              maxBytes: 8,
            ),
          )
          ..cacheImage('stale', Uint8List(4))
          ..cacheImage('oversized', Uint8List(9))
          ..apply([_place('oversized', 0, 0, 1, 1)], _box());

    expect(_imgs(host), hasLength(1), reason: 'on-screen image is preserved');
    expect(overlay.cachedImageCount, 1, reason: 'stale cache was drained');
    expect(
      overlay.cachedImageBytes,
      9,
      reason: 'placed image may exceed budget',
    );

    overlay.apply(const [], _box());
    expect(overlay.cachedImageCount, 0);
    expect(overlay.cachedImageBytes, 0);

    overlay.dispose();
    host.remove();
  });

  test('dispose removes the overlay layer from the host', () {
    final host = _makeHost();
    final overlay = InlineImageOverlay(host)
      ..cacheImage('a', Uint8List.fromList([1]))
      ..apply([_place('a', 0, 0, 1, 1)], _box());
    expect(host.children.length, 1, reason: 'the overlay div');

    overlay.dispose();
    expect(host.children.length, 0, reason: 'overlay removed on dispose');
    host.remove();
  });
}
