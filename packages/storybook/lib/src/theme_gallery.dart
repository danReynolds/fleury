import 'package:fleury/fleury.dart';

/// A live preview of every built-in [ThemePalettes] theme. Each card renders
/// sample widgets *in its own palette* (wrapped in a [Theme]) so the look of
/// each is visible at a glance — the storybook's "Themes" story.
class ThemeGallery extends StatelessWidget {
  const ThemeGallery({super.key, this.themes = ThemePalettes.all});

  final List<NamedTheme> themes;

  @override
  Widget build(BuildContext context) => ScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final named in themes)
          Theme(data: named.data, child: _ThemeCard(named: named)),
      ],
    ),
  );
}

/// One theme's sample card. The enclosing [Theme] supplies the palette, so
/// `context.colors`/`context.theme` here resolve to *this* card's scheme.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.named});

  final NamedTheme named;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final theme = context.theme;
    final isLight = named.data.brightness == Brightness.light;
    return Container(
      color: cs.background,
      padding: const EdgeInsets.symmetric(horizontal: 1),
      margin: const EdgeInsets.only(bottom: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            isLight ? '${named.name}  (light)' : named.name,
            style: CellStyle(foreground: cs.foreground, bold: true),
          ),
          // Role swatches: each role's name rendered in its own colour, with a
          // block glyph so the hue reads even against the background.
          Wrap(
            children: <Widget>[
              _swatch('primary', cs.primary),
              _swatch('focus', cs.focus),
              _swatch('success', cs.success),
              _swatch('warning', cs.warning),
              _swatch('error', cs.error),
              _swatch('info', cs.info),
            ],
          ),
          Text(
            'The quick brown fox jumps over the lazy dog',
            style: CellStyle(foreground: cs.foreground),
          ),
          Text(
            'muted secondary — hints, separators, disabled rows',
            style: theme.mutedStyle,
          ),
          Row(
            children: <Widget>[
              Text(' selected ', style: theme.selectionStyle),
              const SizedBox(width: 2),
              Text(
                'focused',
                style: theme.focusedStyle.merge(
                  CellStyle(foreground: cs.focus),
                ),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              Text('✓ success   ', style: CellStyle(foreground: cs.success)),
              Text('⚠ warning   ', style: CellStyle(foreground: cs.warning)),
              Text('✗ error   ', style: CellStyle(foreground: cs.error)),
              Text('ℹ info', style: CellStyle(foreground: cs.info)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _swatch(String label, Color color) => Padding(
    padding: const EdgeInsets.only(right: 2),
    child: Text('▉ $label', style: CellStyle(foreground: color)),
  );
}
