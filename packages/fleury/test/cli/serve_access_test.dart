import 'dart:math';

import 'package:fleury/src/cli/serve_access.dart';
import 'package:test/test.dart';

void main() {
  test('loopback hosts are local; everything else is a network bind', () {
    for (final host in ['localhost', '127.0.0.1', '::1', '127.0.0.2']) {
      expect(isLoopbackServeHost(host), isTrue, reason: host);
    }
    for (final host in ['0.0.0.0', '::', '192.168.1.20', 'example.com']) {
      expect(isLoopbackServeHost(host), isFalse, reason: host);
    }
  });

  test('a generated token is 128 random bits, hex-encoded', () {
    final token = generateServeToken();
    expect(token, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(generateServeToken(), isNot(token));
    // Deterministic under an injected source: every byte is two hex digits.
    expect(generateServeToken(Random(1)), generateServeToken(Random(1)));
  });

  test('only the exact token is admitted', () {
    const token = '0123456789abcdef0123456789abcdef';
    expect(serveTokenMatches(token, token), isTrue);
    expect(serveTokenMatches(token, null), isFalse);
    expect(serveTokenMatches(token, ''), isFalse);
    expect(serveTokenMatches(token, token.substring(1)), isFalse);
    expect(serveTokenMatches(token, '${token}0'), isFalse);
    expect(serveTokenMatches(token, '1${token.substring(1)}'), isFalse);
    expect(serveTokenMatches(token, '${token.substring(0, 31)}0'), isFalse);
  });

  test('the browser URL carries the token and brackets IPv6 hosts', () {
    expect(serveBrowserUrl('127.0.0.1', 5777, null), 'http://127.0.0.1:5777');
    expect(
      serveBrowserUrl('0.0.0.0', 8080, 'a b&c'),
      'http://0.0.0.0:8080/?token=a+b%26c',
    );
    expect(serveBrowserUrl('::1', 5777, null), 'http://[::1]:5777');
    expect(
      Uri.parse(serveBrowserUrl('::', 80, 'x')).queryParameters['token'],
      'x',
    );
  });
}
