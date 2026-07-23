import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

/// Previews one built-in [ThemePalettes] theme at a time on a slice of real
/// widgets, with a dropdown to switch palettes — so you can see how each theme
/// looks on actual UI, not just swatches. The storybook's "Themes" story.
class ThemeGallery extends StatefulWidget {
  const ThemeGallery({super.key, this.themes = ThemePalettes.all});

  final List<NamedTheme> themes;

  @override
  State<ThemeGallery> createState() => _ThemeGalleryState();
}

class _ThemeGalleryState extends State<ThemeGallery> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final themes = widget.themes;
    final index = _index.clamp(0, themes.length - 1);
    final selected = themes[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The switcher stays outside the previewed Theme, so it always renders
        // in the storybook's own chrome.
        Row(
          children: <Widget>[
            const Text('Theme:  '),
            Select<int>(
              options: <SelectOption<int>>[
                for (final (i, named) in themes.indexed)
                  SelectOption<int>(value: i, label: named.name),
              ],
              value: index,
              onChanged: (i) => setState(() => _index = i),
              semanticLabel: 'Preview theme',
            ),
          ],
        ),
        const SizedBox(height: 1),
        // The sample UI, rendered in the selected palette.
        Theme(data: selected.data, child: const _ThemeSample()),
      ],
    );
  }
}

/// A representative slice of UI rendered in the ambient theme.
class _ThemeSample extends StatelessWidget {
  const _ThemeSample();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final theme = context.theme;
    return Container(
      color: cs.background,
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Deploy Console',
            style: CellStyle(foreground: cs.foreground, bold: true),
          ),
          Text('one app, two surfaces', style: theme.mutedStyle),
          const SizedBox(height: 1),
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
          const SizedBox(height: 1),
          Wrap(
            children: <Widget>[
              _button('Deploy', ButtonVariant.primary),
              _button('Retry', ButtonVariant.normal),
              _button('Approve', ButtonVariant.success),
              _button('Cancel', ButtonVariant.error),
            ],
          ),
          const SizedBox(height: 1),
          SizedBox(width: 40, child: ProgressBar(value: 0.62)),
          const SizedBox(height: 1),
          Text('  NAME         STATUS', style: theme.mutedStyle),
          Text('  api-gateway  running', style: theme.selectionStyle),
          Text(
            '  worker-01    running',
            style: CellStyle(foreground: cs.foreground),
          ),
          const SizedBox(height: 1),
          Wrap(
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

  Widget _button(String label, ButtonVariant variant) => Padding(
    padding: const EdgeInsets.only(right: 1),
    child: Button(label: label, variant: variant, onPressed: () {}),
  );
}
