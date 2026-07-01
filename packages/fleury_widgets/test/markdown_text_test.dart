// MarkdownText: verifies the block + inline parser via the rendered
// cell grid. We don't try to lock the visual layout pixel-exact —
// that's brittle when the parser learns new tricks. Instead each test
// asserts the property that matters: the right glyphs land, the right
// style flags are set, and unsupported syntax falls through as text.

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

/// Walks every cell of the test buffer and returns true if any cell's
/// style satisfies [check] AND its grapheme is in [graphemes].
bool _anyCellMatches(
  CellBuffer buf,
  Set<String> graphemes,
  bool Function(CellStyle) check,
) {
  for (var r = 0; r < buf.size.rows; r++) {
    for (var c = 0; c < buf.size.cols; c++) {
      final cell = buf.atColRow(c, r);
      if (cell.grapheme == null) continue;
      if (!graphemes.contains(cell.grapheme)) continue;
      if (check(cell.style)) return true;
    }
  }
  return false;
}

void main() {
  group('MarkdownText — inline', () {
    testWidgets('**bold** renders the inner text with bold style', (tester) {
      tester.pumpWidget(const MarkdownText('hello **world** !'));
      final buf = tester.render(size: const CellSize(40, 1));
      expect(
        _anyCellMatches(buf, {'w', 'o', 'r', 'l', 'd'}, (s) => s.bold),
        isTrue,
      );
      expect(
        _anyCellMatches(buf, {'h', 'e'}, (s) => s.bold),
        isFalse,
        reason: 'text outside the markers stays plain',
      );
    });

    testWidgets('*italic* and _italic_ both render italic', (tester) {
      tester.pumpWidget(const MarkdownText('one *two* three _four_ five'));
      final buf = tester.render(size: const CellSize(40, 1));
      expect(_anyCellMatches(buf, {'t', 'w', 'o'}, (s) => s.italic), isTrue);
      expect(
        _anyCellMatches(buf, {'f', 'o', 'u', 'r'}, (s) => s.italic),
        isTrue,
      );
    });

    testWidgets('~~strike~~ renders strikethrough', (tester) {
      tester.pumpWidget(const MarkdownText('keep ~~drop~~ keep'));
      final buf = tester.render(size: const CellSize(40, 1));
      expect(
        _anyCellMatches(buf, {'d', 'r', 'o', 'p'}, (s) => s.strikethrough),
        isTrue,
      );
    });

    testWidgets('`code` renders with a code background tone', (tester) {
      tester.pumpWidget(const MarkdownText('run `cmd` now'));
      final buf = tester.render(size: const CellSize(40, 1));
      expect(
        _anyCellMatches(buf, {'c', 'm', 'd'}, (s) => s.background != null),
        isTrue,
      );
    });

    testWidgets('[text](url) underlines the label and shows the url dim', (
      tester,
    ) {
      tester.pumpWidget(
        const MarkdownText('see [docs](https://fleury.dev) here'),
      );
      final buf = tester.render(size: const CellSize(60, 1));
      expect(
        _anyCellMatches(buf, {'d', 'o', 'c', 's'}, (s) => s.underline),
        isTrue,
        reason: 'link text is underlined',
      );
      expect(
        _anyCellMatches(buf, {'h', 't', 'p', 's'}, (s) => s.dim),
        isTrue,
        reason: 'url shown as dim trailing parenthetical',
      );
    });

    testWidgets('link semantics expose safe visible-url fallback policy', (
      tester,
    ) {
      tester.pumpWidget(
        const MarkdownText('see [docs](https://fleury.dev) here'),
      );

      final link = tester.semantics().single(
        role: SemanticRole.link,
        label: 'docs',
      );

      expect(link.value, 'https://fleury.dev');
      expect(link.state.terminalCapability, 'osc8Hyperlinks');
      expect(link.state.capabilityRequirement, 'prohibited');
      expect(link.state.capabilityResolution, 'disabledByPolicy');
      expect(link.state.activeFallback, 'visible URL');
      expect(link.state.values['linkScheme'], 'https');
      expect(link.state.values['safeLinkScheme'], isTrue);
      expect(link.state.values['osc8Policy'], 'disabledByDefault');
    });

    testWidgets('link semantics flag custom schemes as not safe for OSC 8', (
      tester,
    ) {
      tester.pumpWidget(
        const MarkdownText('run [local](myapp://open/project) manually'),
      );

      final link = tester.semantics().single(
        role: SemanticRole.link,
        label: 'local',
      );

      expect(link.value, 'myapp://open/project');
      expect(link.state.capabilityResolution, 'disabledByPolicy');
      expect(link.state.activeFallback, 'visible URL');
      expect(link.state.values['linkScheme'], 'myapp');
      expect(link.state.values['safeLinkScheme'], isFalse);
    });

    testWidgets('code fences do not expose markdown link semantics', (tester) {
      tester.pumpWidget(
        const MarkdownText('```\n[docs](https://fleury.dev)\n```'),
      );

      expect(tester.semantics().byRole(SemanticRole.link), isEmpty);
    });

    testWidgets('unbalanced markup is left as literal text', (tester) {
      // *hello — no closing star — should NOT enter italic state and
      // emit raw text instead.
      tester.pumpWidget(const MarkdownText('a*b c d'));
      final buf = tester.render(size: const CellSize(10, 1));
      // The '*' itself should be rendered (no markup matched).
      expect(
        _anyCellMatches(buf, {'*'}, (_) => true),
        isTrue,
        reason: 'unmatched delimiter falls through as literal',
      );
    });
  });

  group('MarkdownText — blocks', () {
    testWidgets('# heading renders bold + inverse + a color tint', (tester) {
      tester.pumpWidget(const MarkdownText('# Title\nbody'));
      final buf = tester.render(size: const CellSize(20, 2));
      expect(
        _anyCellMatches(buf, {
          'T',
          'i',
          't',
          'l',
          'e',
        }, (s) => s.bold && s.inverse && s.foreground != null),
        isTrue,
      );
    });

    testWidgets('## heading renders bold + underline + a color tint', (tester) {
      tester.pumpWidget(const MarkdownText('## Sub'));
      final buf = tester.render(size: const CellSize(20, 1));
      expect(
        _anyCellMatches(buf, {
          'S',
          'u',
          'b',
        }, (s) => s.bold && s.underline && !s.inverse && s.foreground != null),
        isTrue,
      );
    });

    testWidgets('### heading recedes to bold + underline, no color', (tester) {
      tester.pumpWidget(const MarkdownText('### Deep'));
      final buf = tester.render(size: const CellSize(20, 1));
      expect(
        _anyCellMatches(buf, {
          'D',
          'e',
          'p',
        }, (s) => s.bold && s.underline && s.foreground == null),
        isTrue,
      );
    });

    testWidgets('bullet list prefixes each item with •', (tester) {
      tester.pumpWidget(const MarkdownText('- one\n- two'));
      final buf = tester.render(size: const CellSize(20, 2));
      expect(_anyCellMatches(buf, {'•'}, (_) => true), isTrue);
    });

    testWidgets('ordered list keeps the number + period', (tester) {
      tester.pumpWidget(const MarkdownText('1. first\n2. second'));
      final buf = tester.render(size: const CellSize(20, 2));
      // First row should contain '1' and '.'.
      var sawNumber = false;
      for (var c = 0; c < 20; c++) {
        if (buf.atColRow(c, 0).grapheme == '1' &&
            buf.atColRow(c + 1, 0).grapheme == '.') {
          sawNumber = true;
        }
      }
      expect(sawNumber, isTrue);
    });

    testWidgets('blockquote prefixes with │ and dims the body', (tester) {
      tester.pumpWidget(const MarkdownText('> quoted line'));
      final buf = tester.render(size: const CellSize(40, 1));
      expect(_anyCellMatches(buf, {'│'}, (s) => s.dim), isTrue);
    });

    testWidgets('horizontal rule emits a dim ─ row', (tester) {
      tester.pumpWidget(const MarkdownText('above\n---\nbelow'));
      final buf = tester.render(size: const CellSize(20, 3));
      expect(_anyCellMatches(buf, {'─'}, (s) => s.dim), isTrue);
    });

    testWidgets('fenced code block preserves whitespace + bg tone', (tester) {
      tester.pumpWidget(const MarkdownText('```\n  indent\n```'));
      final buf = tester.render(size: const CellSize(20, 3));
      expect(
        _anyCellMatches(buf, {'i', 'n', 'd', 'e'}, (s) => s.background != null),
        isTrue,
      );
    });
  });
}
