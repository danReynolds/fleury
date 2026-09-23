import 'package:fleury/fleury.dart';
import 'package:fleury_test/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

// Every construct, and the boundaries an append can land on: mid-line, inside
// an open fence, right after a newline, around CRLF and blank lines.
const _corpus = '''# Title with [a link](https://example.com/a)

Intro paragraph with **bold**, `code`, and [two](https://example.com/b).
- bullet one
  - nested bullet [three](https://example.com/c)
1. ordered one
10. ordered ten
> quoted [four](https://example.com/d)
---
```dart
final x = 1; // [not a link](https://example.com/x)

  indented code
```
## Section\r
text after crlf\r

```
unterminated fence line one
unterminated fence line two''';

String _render(FleuryTester tester, Widget widget, CellSize size) {
  tester.pumpWidget(widget);
  return tester.renderToString(size: size);
}

List<String> _semantics(FleuryTester tester) => [
  for (final node in tester.semantics().nodes)
    '${node.role.name}|${node.label}|${node.value}|${node.state}',
];

void main() {
  for (final chunk in [1, 3, 7, 29, 1000]) {
    testWidgets('MarkdownView streamed in $chunk-char chunks matches a fresh '
        'parse at every step', (tester) {
      const size = CellSize(60, 40);
      final fresh = FleuryTester(viewportSize: size);
      addTearDown(fresh.dispose);
      for (var end = 0; end <= _corpus.length; end += chunk) {
        final prefix = _corpus.substring(0, end);
        final streamed = _render(tester, MarkdownView(markdown: prefix), size);
        // A new key per step: the reference must be a full parse, not a
        // second stream.
        final expected = _render(
          fresh,
          MarkdownView(key: ValueKey(end), markdown: prefix),
          size,
        );
        expect(streamed, expected, reason: 'prefix length $end');
        expect(_semantics(tester), _semantics(fresh), reason: 'at $end');
      }
    });

    testWidgets('MarkdownText streamed in $chunk-char chunks matches a fresh '
        'render at every step', (tester) {
      const size = CellSize(60, 40);
      final fresh = FleuryTester(viewportSize: size);
      addTearDown(fresh.dispose);
      for (var end = 0; end <= _corpus.length; end += chunk) {
        final prefix = _corpus.substring(0, end);
        final streamed = _render(tester, MarkdownText(prefix), size);
        final expected = _render(
          fresh,
          MarkdownText(prefix, key: ValueKey(end)),
          size,
        );
        expect(streamed, expected, reason: 'prefix length $end');
        expect(_semantics(tester), _semantics(fresh), reason: 'at $end');
      }
    });
  }

  testWidgets('an edit that is not an append re-parses from scratch', (tester) {
    const size = CellSize(40, 10);
    final fresh = FleuryTester(viewportSize: size);
    addTearDown(fresh.dispose);
    for (final (from, to) in [
      ('# One\ntwo', '# Uno\ntwo'),
      ('```\ncode', 'text\ncode'),
      ('a\nb\nc', 'a\nb'),
    ]) {
      _render(tester, MarkdownView(markdown: from), size);
      expect(
        _render(tester, MarkdownView(markdown: to), size),
        _render(fresh, MarkdownView(key: ValueKey(to), markdown: to), size),
      );
      _render(tester, MarkdownText(from), size);
      expect(
        _render(tester, MarkdownText(to), size),
        _render(fresh, MarkdownText(to, key: ValueKey(to)), size),
      );
    }
  });

  test('the corpus exercises every construct the stream must preserve', () {
    final whole = parseMarkdownDocument(_corpus);
    expect(whole.headingCount, 2, reason: 'a CRLF heading still counts');
    expect(whole.codeBlockCount, 2, reason: 'one closed, one unterminated');
    expect(
      whole.links.map((link) => link.url),
      [
        'https://example.com/a',
        'https://example.com/b',
        'https://example.com/c',
        'https://example.com/d',
      ],
      reason: 'the link inside the fence is code, not a link',
    );
  });
}
