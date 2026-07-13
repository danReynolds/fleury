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

/// True if any painted cell carries a [CellStyle.linkUri] (optionally equal to
/// [uri]). Position-independent, so link assertions don't hinge on where the
/// label lands.
bool _anyLinkedCell(CellBuffer buf, [String? uri]) {
  for (var r = 0; r < buf.size.rows; r++) {
    for (var c = 0; c < buf.size.cols; c++) {
      final link = buf.atColRow(c, r).style.linkUri;
      if (link != null && (uri == null || link == uri)) return true;
    }
  }
  return false;
}

/// Wraps [child] in a MediaQuery whose surface reports [hyperlinks] — a
/// supporting surface (browser anchors / an OSC-8 terminal) vs. a plain one —
/// so the producer gate in MarkdownText sees the capability under test.
Widget _surface(Widget child, {required bool hyperlinks}) => MediaQuery(
  data: MediaQueryData(
    size: const CellSize(80, 24),
    capabilities: SurfaceCapabilities(hyperlinks: hyperlinks),
  ),
  child: child,
);

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

    testWidgets(
      'non-supporting surface: no linkUri, visible-url fallback, osc8Policy '
      'unsupported',
      (tester) {
        tester.pumpWidget(
          _surface(
            const MarkdownText('see [docs](https://fleury.dev) here'),
            hyperlinks: false,
          ),
        );
        final buf = tester.render(size: const CellSize(60, 1));

        // Producer gate: the surface can't render a link, so no cell is linked
        // even though the scheme is safe — it stays plain underline + the url.
        expect(_anyLinkedCell(buf), isFalse);
        expect(
          _anyCellMatches(buf, {'d', 'o', 'c', 's'}, (s) => s.underline),
          isTrue,
        );
        expect(
          _anyCellMatches(buf, {'h', 't', 'p', 's'}, (s) => s.dim),
          isTrue,
          reason: 'inspectable (url) suffix is always shown for a dead link',
        );

        final link = tester.semantics().single(
          role: SemanticRole.link,
          label: 'docs',
        );
        // The URL stays agent/AT-legible via value regardless of surface.
        expect(link.value, 'https://fleury.dev');
        expect(link.state.terminalCapability, 'osc8Hyperlinks');
        expect(link.state.capabilityRequirement, 'prohibited');
        expect(link.state.capabilityResolution, 'disabledByPolicy');
        expect(link.state.activeFallback, 'visible URL');
        expect(link.state.values['linkScheme'], 'https');
        expect(link.state.values['safeLinkScheme'], isTrue);
        expect(link.state.values['osc8Policy'], 'unsupported');
      },
    );

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

  group('MarkdownText — hyperlinks (OSC 8)', () {
    testWidgets(
      'supporting surface + safe scheme: link run carries linkUri, url suffix '
      'kept, osc8Policy supported',
      (tester) {
        tester.pumpWidget(
          _surface(
            const MarkdownText('see [fleury](https://fleury.dev) here'),
            hyperlinks: true,
          ),
        );
        final buf = tester.render(size: const CellSize(60, 1));

        // The link label cells carry the OSC 8 target AND stay underlined.
        expect(
          _anyCellMatches(
            buf,
            {'f', 'l', 'e', 'u', 'r', 'y'},
            (s) => s.linkUri == 'https://fleury.dev' && s.underline,
          ),
          isTrue,
          reason: 'label run is a live link',
        );
        // Default keeps the inspectable url suffix (dim, and NOT itself linked).
        expect(
          _anyCellMatches(buf, {'.', 'd', 'e', 'v'}, (s) => s.dim),
          isTrue,
          reason: 'the ( url ) suffix is shown by default',
        );

        final link = tester.semantics().single(
          role: SemanticRole.link,
          label: 'fleury',
        );
        expect(link.value, 'https://fleury.dev');
        expect(link.state.values['safeLinkScheme'], isTrue);
        expect(link.state.values['osc8Policy'], 'supported');
      },
    );

    testWidgets(
      'a multi-word link carries linkUri across its internal spaces',
      (tester) {
        // Regression: the link label's spaces used to render unlinked, so a
        // multi-word link split into one anchor per word. The whole phrase —
        // words AND the spaces between them — must carry the link.
        tester.pumpWidget(
          _surface(
            const MarkdownText(
              '[open an issue](https://x)',
              inlineLinkUrls: false, // drop the (url) suffix; only the label paints
            ),
            hyperlinks: true,
          ),
        );
        final buf = tester.render(size: const CellSize(40, 1));
        expect(
          _anyCellMatches(
            buf,
            {'o', 'p', 'e', 'n', 'a', 'i', 's', 'u'},
            (s) => s.linkUri == 'https://x' && s.underline,
          ),
          isTrue,
          reason: 'the label words are linked',
        );
        expect(
          _anyCellMatches(
            buf,
            {' '},
            (s) => s.linkUri == 'https://x' && s.underline,
          ),
          isTrue,
          reason: 'the spaces INSIDE the link are linked too (contiguous run)',
        );
      },
    );

    testWidgets(
      'inlineLinkUrls:false drops the suffix for a live link (url is redundant)',
      (tester) {
        tester.pumpWidget(
          _surface(
            const MarkdownText(
              'see [fleury](https://fleury.dev) here',
              inlineLinkUrls: false,
            ),
            hyperlinks: true,
          ),
        );
        final buf = tester.render(size: const CellSize(60, 1));

        expect(_anyLinkedCell(buf, 'https://fleury.dev'), isTrue);
        // With the suffix gone the url's '/' never paints: text is "see fleury
        // here". (The label 'fleury' has no slash.)
        expect(
          _anyCellMatches(buf, {'/'}, (_) => true),
          isFalse,
          reason: 'no ( url ) suffix, so the scheme slashes are absent',
        );
      },
    );

    testWidgets(
      'a lone suffix-less live link keeps its linkUri (single-child collapse)',
      (tester) {
        // The whole inline is one span, exercising the children.length == 1
        // path — which must not drop the link style.
        tester.pumpWidget(
          _surface(
            const MarkdownText(
              '[fleury](https://fleury.dev)',
              inlineLinkUrls: false,
            ),
            hyperlinks: true,
          ),
        );
        final buf = tester.render(size: const CellSize(20, 1));
        expect(
          _anyCellMatches(
            buf,
            {'f', 'l', 'e', 'u', 'r', 'y'},
            (s) => s.linkUri == 'https://fleury.dev' && s.underline,
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      'supporting surface still refuses an un-allow-listed scheme '
      '(osc8Policy disabledByPolicy)',
      (tester) {
        tester.pumpWidget(
          _surface(
            const MarkdownText('grab [file](ftp://host.example/x) now'),
            hyperlinks: true,
          ),
        );
        final buf = tester.render(size: const CellSize(60, 1));

        // Scheme blocked at the producer: nothing gets a linkUri, but the
        // fallback (underline label + visible url) is intact.
        expect(_anyLinkedCell(buf), isFalse);
        expect(
          _anyCellMatches(buf, {'f', 'i', 'l', 'e'}, (s) => s.underline),
          isTrue,
        );

        final link = tester.semantics().single(
          role: SemanticRole.link,
          label: 'file',
        );
        expect(link.value, 'ftp://host.example/x');
        expect(link.state.values['linkScheme'], 'ftp');
        expect(link.state.values['safeLinkScheme'], isFalse);
        expect(link.state.values['osc8Policy'], 'disabledByPolicy');
      },
    );

    testWidgets(
      'FULL LOOP: one MarkdownText link reaches the terminal (OSC 8) and the '
      'wire mirror',
      (tester) {
        const size = CellSize(40, 1);
        tester.pumpWidget(
          _surface(
            const MarkdownText('[fleury](https://fleury.dev)'),
            hyperlinks: true,
          ),
        );
        final next = tester.render(size: size);

        // (1) PRODUCER — the painted link cell carries the OSC 8 target.
        expect(
          _anyLinkedCell(next, 'https://fleury.dev'),
          isTrue,
          reason: 'MarkdownText set linkUri on the link run',
        );

        // (2) TERMINAL — AnsiRenderer(hyperlinks: true) emits the OSC 8 open.
        final sink = StringAnsiSink();
        AnsiRenderer(hyperlinks: true).renderDiff(CellBuffer(size), next, sink);
        expect(
          sink.output,
          contains('\x1B]8;;https://fleury.dev\x1B\\'),
          reason: 'the diff opens a real OSC 8 hyperlink for the run',
        );

        // (3) WIRE — build a v4 plan, round-trip the bytes, apply to a client
        // mirror; the decoded mirror cell carries the link (the browser <a>
        // rendering of it is covered in fleury_web).
        final plan = buildRemotePlan(
          CellBuffer(size),
          next,
          fullRepaint: true,
          includeLinks: true,
        );
        final mirror = CellBuffer(size);
        applyRemotePlanToBuffer(
          decodeRemotePlan(encodeRemotePlan(plan)),
          mirror,
        );
        expect(
          _anyLinkedCell(mirror, 'https://fleury.dev'),
          isTrue,
          reason: 'the decoded client mirror carries the link across the wire',
        );
      },
    );
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
