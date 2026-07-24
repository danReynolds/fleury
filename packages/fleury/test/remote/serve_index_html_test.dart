// Sanity checks on the page served by `fleury serve`. The page hosts the
// fleury web renderer (the embedded dart2js client), not a terminal
// emulator — these tests catch the load-bearing pieces.

import 'package:fleury/src/remote/remote_client_asset.dart';
import 'package:fleury/src/remote/serve_index_html.dart';
import 'package:fleury/src/remote/serve_mono_font_asset.dart';
import 'package:test/test.dart';

void main() {
  group('serveIndexHtml', () {
    test('is non-empty and well-formed at the boundaries', () {
      expect(serveIndexHtml, isNotEmpty);
      expect(serveIndexHtml.trimLeft(), startsWith('<!doctype html>'));
      expect(serveIndexHtml.trimRight(), endsWith('</html>'));
    });

    test('hosts the fleury surface element and loads the client bundle', () {
      expect(serveIndexHtml, contains('id="fleury-remote"'));
      expect(serveIndexHtml, contains('<script src="/remote_client.js">'));
      expect(serveClientJsPath, '/remote_client.js');
    });

    test('ships an embedded subset mono font for the browser surface', () {
      final bytes = serveMonoFontBytes();
      // A real, non-trivial woff2 (magic bytes "wOF2").
      expect(bytes.length, greaterThan(20000));
      expect(String.fromCharCodes(bytes.take(4)), 'wOF2');
      // The shell declares and uses it, served locally (no CDN).
      expect(serveMonoFontPath, '/fleury-mono.woff2');
      expect(serveIndexHtml, contains('@font-face'));
      expect(serveIndexHtml, contains('FleuryMono'));
      expect(serveIndexHtml, contains(serveMonoFontPath));
    });

    test('uses deterministic terminal font shaping', () {
      expect(serveIndexHtml, contains('font-kerning: none'));
      expect(serveIndexHtml, contains('font-variant-ligatures: none'));
      expect(
        serveIndexHtml,
        contains('font-feature-settings: "liga" 0, "clig" 0'),
      );
    });

    test('carries no terminal-emulator dependency', () {
      // The whole point of the structured client: no xterm, no CDN.
      expect(serveIndexHtml, isNot(contains('xterm')));
      expect(serveIndexHtml, isNot(contains('cdn.jsdelivr.net')));
      expect(serveIndexHtml, isNot(contains('CanvasAddon')));
    });
  });

  group('remoteClientJs', () {
    test('decodes to a non-trivial JS bundle', () {
      final js = remoteClientJs();
      expect(js.length, greaterThan(10000));
      // dart2js output starts with a self-invoking function preamble.
      final head = String.fromCharCodes(js.take(64));
      expect(head, anyOf(contains('function'), contains('(')));
    });
  });
}
