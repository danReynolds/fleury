import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

void main() {
  group('isSafeLinkScheme — canonical safe-link-scheme predicate', () {
    test('the default-safe schemes pass', () {
      expect(isSafeLinkScheme('https://fleury.dev'), isTrue);
      expect(isSafeLinkScheme('http://example.com/a'), isTrue);
      expect(isSafeLinkScheme('mailto:a@b.com'), isTrue);
    });

    test('the canonical set is exactly {https, http, mailto}', () {
      expect(kSafeLinkSchemes, {'https', 'http', 'mailto'});
    });

    test('file: and custom schemes are NOT in the default set', () {
      // RFC 0013 gates file:/custom behind explicit opt-in; the default denies.
      expect(isSafeLinkScheme('file:///etc/hosts'), isFalse);
      expect(isSafeLinkScheme('myapp://open/project'), isFalse);
      expect(isSafeLinkScheme('ftp://host.example/x'), isFalse);
    });

    test('the classic XSS scheme vectors fail closed', () {
      expect(isSafeLinkScheme('javascript:alert(1)'), isFalse);
      expect(isSafeLinkScheme('data:text/html;base64,PHN2Zz4='), isFalse);
      expect(isSafeLinkScheme('vbscript:msgbox(1)'), isFalse);
    });

    test('case is normalized (exact match, lowercased)', () {
      expect(isSafeLinkScheme('HTTPS://fleury.dev'), isTrue);
      expect(isSafeLinkScheme('MailTo:a@b.com'), isTrue);
      expect(isSafeLinkScheme('JavaScript:alert(1)'), isFalse);
    });

    test('a no-colon or empty-scheme URI is default-denied, never crashes', () {
      expect(isSafeLinkScheme(''), isFalse);
      expect(isSafeLinkScheme('example.com'), isFalse); // relative, no scheme
      expect(isSafeLinkScheme('/path/only'), isFalse);
      expect(isSafeLinkScheme(':x'), isFalse); // empty scheme
      expect(isSafeLinkScheme('://nohost'), isFalse);
    });

    test('only the first colon delimits the scheme — no prefix smuggling', () {
      // A safe-looking fragment after the true scheme cannot pass the check.
      expect(isSafeLinkScheme('javascript:https://ok'), isFalse);
      expect(isSafeLinkScheme('java	script:alert(1)'), isFalse);
      // A leading space makes the scheme literally " https" — not a match.
      expect(isSafeLinkScheme(' https://fleury.dev'), isFalse);
    });

    test('a unicode colon is not an ASCII scheme delimiter', () {
      // U+A789 (꞉) is not ':'; there is no ASCII colon, so it is scheme-less.
      expect(isSafeLinkScheme('https꞉//fleury.dev'), isFalse);
    });
  });
}
