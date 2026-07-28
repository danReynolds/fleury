// RFC 0019 §6.3 — one ambient policy reaches every geometry consumer.
//
// Widgets resolve the surface's TextPresentationPolicy from MediaQuery at
// build and pass it explicitly into their render objects; an explicit
// `policy:` on the widget overrides the whole object. With no MediaQuery (or
// the default capabilities) everything measures with the spec policy —
// byte-identical to pre-policy behaviour.

import 'package:fleury/fleury.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

/// A surface whose probe measured every emoji class narrow (terminal A).
const _narrowEmojiPolicy = TextPresentationPolicy(
  widths: CellWidthPolicy(
    emojiPresentation: CellWidth.one,
    emojiVariationSequence: CellWidth.one,
  ),
);

Widget _onSurface(TextPresentationPolicy policy, Widget child) => MediaQuery(
  data: MediaQueryData(
    size: const CellSize(20, 4),
    capabilities: SurfaceCapabilities(textPolicy: policy),
  ),
  child: child,
);

void main() {
  group('ambient width policy', () {
    testWidgets('Text measures with the surface policy', (tester) {
      tester.pumpWidget(
        _onSurface(
          _narrowEmojiPolicy,
          const Row(children: <Widget>[Text('🙂'), Text('X')]),
        ),
      );
      final buffer = tester.render(size: const CellSize(20, 4));
      expect(
        buffer.atColRow(1, 0).grapheme,
        'X',
        reason:
            'a narrow-emoji surface lays the smiley out in ONE cell, so '
            'X lands in column 1',
      );
    });

    testWidgets('the spec default keeps emoji at two cells', (tester) {
      tester.pumpWidget(const Row(children: <Widget>[Text('🙂'), Text('X')]));
      final buffer = tester.render(size: const CellSize(20, 4));
      expect(
        buffer.atColRow(2, 0).grapheme,
        'X',
        reason: 'unprobed surfaces are byte-identical to pre-policy behaviour',
      );
    });

    testWidgets('an explicit widget policy overrides the ambient one', (
      tester,
    ) {
      tester.pumpWidget(
        _onSurface(
          _narrowEmojiPolicy,
          const Row(
            children: <Widget>[
              Text('🙂', policy: TextPresentationPolicy.spec),
              Text('X'),
            ],
          ),
        ),
      );
      final buffer = tester.render(size: const CellSize(20, 4));
      expect(
        buffer.atColRow(2, 0).grapheme,
        'X',
        reason: 'the explicit policy pins measurement against the surface',
      );
    });

    testWidgets('RichText follows the ambient policy too', (tester) {
      tester.pumpWidget(
        _onSurface(
          _narrowEmojiPolicy,
          const Row(
            children: <Widget>[
              RichText(text: TextSpan(text: '🙂')),
              Text('X'),
            ],
          ),
        ),
      );
      final buffer = tester.render(size: const CellSize(20, 4));
      expect(
        buffer.atColRow(1, 0).grapheme,
        'X',
        reason:
            'every geometry consumer shares the one surface policy — an '
            'ambient Text beside a spec RichText would disagree internally, '
            'which is worse than disagreeing with the terminal',
      );
    });

    testWidgets('TextInput caret math shares the surface policy', (tester) {
      final controller = TextEditingController(text: '🙂ab');
      tester.pumpWidget(
        _onSurface(
          _narrowEmojiPolicy,
          SizedBox(
            width: 12,
            child: TextInput(controller: controller, autofocus: true),
          ),
        ),
      );
      final buffer = tester.render(size: const CellSize(12, 3));
      // The smiley occupies one cell on this surface, so 'a' renders in
      // column 1 — display and caret math both run on the ambient policy.
      expect(buffer.atColRow(1, 0).grapheme, 'a');
      expect(buffer.atColRow(2, 0).grapheme, 'b');
    });
  });
}
