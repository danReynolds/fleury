// Sanity checks on the embedded HTML page served by `fleury serve`.
// The page is hand-written and could easily rot; these tests catch
// the load-bearing pieces.

import 'package:fleury/src/remote/serve_index_html.dart';
import 'package:test/test.dart';

void main() {
  group('serveIndexHtml', () {
    test('is non-empty and well-formed at the boundaries', () {
      expect(serveIndexHtml, isNotEmpty);
      expect(serveIndexHtml.trimLeft(), startsWith('<!doctype html>'));
      expect(serveIndexHtml.trimRight(), endsWith('</html>'));
    });

    test('mirrors the wire-protocol frame constants from Dart', () {
      // If these drift from `remote_protocol.dart`, the JS client will
      // talk a different protocol than the Dart end and nothing
      // useful renders. Lock the type bytes.
      expect(serveIndexHtml, contains('INIT: 0x01'));
      expect(serveIndexHtml, contains('INPUT: 0x02'));
      expect(serveIndexHtml, contains('RESIZE: 0x03'));
      expect(serveIndexHtml, contains('OUTPUT: 0x10'));
      expect(serveIndexHtml, contains('BYE: 0x11'));
    });

    test('loads xterm.js + the fit addon', () {
      expect(serveIndexHtml, contains('xterm@'));
      expect(serveIndexHtml, contains('addon-fit'));
    });

    test('opens a WebSocket to /ws (same host) and forwards INPUT/RESIZE', () {
      expect(serveIndexHtml, contains("location.host + '/ws'"));
      expect(serveIndexHtml, contains('encodeFrame(FRAME.INPUT'));
      expect(serveIndexHtml, contains('encodeFrame(FRAME.RESIZE'));
      expect(serveIndexHtml, contains('encodeFrame(FRAME.INIT'));
    });

    test('uses binary WebSocket frames (arraybuffer), not text', () {
      expect(serveIndexHtml, contains("binaryType = 'arraybuffer'"));
    });

    test('bounds incoming frame payload sizes', () {
      expect(serveIndexHtml, contains('MAX_FRAME_PAYLOAD = 64 * 1024 * 1024'));
      expect(serveIndexHtml, contains('new DataView'));
      expect(serveIndexHtml, contains('getUint32(1, false)'));
      expect(serveIndexHtml, contains("ws.close(1009, 'frame too large')"));
    });

    test('writes OUTPUT frames into the terminal', () {
      expect(serveIndexHtml, contains('term.write'));
      expect(serveIndexHtml, contains('FRAME.OUTPUT'));
    });
  });
}
