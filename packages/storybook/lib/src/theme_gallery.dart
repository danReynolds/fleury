import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

/// Previews one built-in [ThemePalettes] theme at a time on a mock app built
/// from real widgets, with a dropdown to switch palettes — so you can see how a
/// theme reads on actual UI, not just swatches. The storybook's "Themes" story.
///
/// The dropdown live-previews: arrowing through it re-themes the sample
/// immediately, Enter keeps the choice, Esc puts the previous one back.
class ThemeGallery extends StatefulWidget {
  const ThemeGallery({super.key, this.themes = ThemePalettes.all});

  final List<NamedTheme> themes;

  @override
  State<ThemeGallery> createState() => _ThemeGalleryState();
}

class _ThemeGalleryState extends State<ThemeGallery> {
  /// The committed choice — what the dropdown displays.
  int _applied = 0;

  /// What the sample renders: the highlighted option while the list is open,
  /// otherwise [_applied]. Select rewinds this for us when the list is
  /// dismissed, so it can never strand a preview.
  int _shown = 0;

  @override
  Widget build(BuildContext context) {
    final themes = widget.themes;
    if (themes.isEmpty) return const Text('No themes registered.');
    final selected = themes[_shown.clamp(0, themes.length - 1)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The switcher stays outside the previewed Theme, so it always renders
        // in the storybook's own chrome rather than the theme under test.
        Row(
          children: <Widget>[
            const Text('Theme:  '),
            Select<int>(
              options: <SelectOption<int>>[
                for (final (i, named) in themes.indexed)
                  SelectOption<int>(value: i, label: named.name),
              ],
              value: _applied,
              onChanged: (i) => setState(() {
                _applied = i;
                _shown = i;
              }),
              onHighlightChanged: (i) => setState(() => _shown = i),
              semanticLabel: 'Preview theme',
            ),
          ],
        ),
        const SizedBox(height: 1),
        Theme(data: selected.data, child: const _ThemeSample()),
      ],
    );
  }
}

/// A mock app rendered in the ambient theme: two panes of real widgets plus a
/// legend of the palette's roles and text styles.
class _ThemeSample extends StatelessWidget {
  const _ThemeSample();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.colors.background,
      padding: const EdgeInsets.all(1),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Side by side once both panes fit comfortably; stacked when the
          // preview pane is narrow.
          final wide = (constraints.maxCols ?? 0) >= 78;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const <Widget>[
                    Expanded(child: _ConsolePane()),
                    SizedBox(width: 1),
                    Expanded(child: _ActivityPane()),
                  ],
                )
              else ...const <Widget>[
                _ConsolePane(),
                SizedBox(height: 1),
                _ActivityPane(),
              ],
              const SizedBox(height: 1),
              const _PaletteLegend(),
            ],
          );
        },
      ),
    );
  }
}

/// The "active" pane — focused, so its border and title take the theme accent.
class _ConsolePane extends StatelessWidget {
  const _ConsolePane();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final theme = context.theme;
    return Panel(
      title: 'Deploy Console',
      focused: true,
      expandChild: false,
      trailing: Text('prod', style: CellStyle(foreground: cs.warning)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(' SERVICE      STATUS      CPU', style: theme.mutedStyle),
          // The first row uses selectionStyle — the theme's "this is the
          // current row" treatment, the thing a list or table leans on.
          _ServiceRow(
            name: 'api-gateway',
            status: '✓ running',
            cpu: '42%',
            statusColor: cs.success,
            style: theme.selectionStyle,
          ),
          _ServiceRow(
            name: 'worker-01',
            status: '✓ running',
            cpu: '18%',
            statusColor: cs.success,
          ),
          _ServiceRow(
            name: 'cache-02',
            status: '⚠ degraded',
            cpu: '91%',
            statusColor: cs.warning,
          ),
          _ServiceRow(
            name: 'relay-03',
            status: '✗ failed',
            cpu: '  —',
            statusColor: cs.error,
          ),
          const SizedBox(height: 1),
          Text('Rolling out  62%', style: CellStyle(foreground: cs.foreground)),
          ProgressBar(value: 0.62),
          const SizedBox(height: 1),
          Wrap(
            children: <Widget>[
              _button('Deploy', ButtonVariant.primary),
              _button('Retry', ButtonVariant.normal),
              _button('Approve', ButtonVariant.success),
              _button('Cancel', ButtonVariant.error),
            ],
          ),
        ],
      ),
    );
  }

  Widget _button(String label, ButtonVariant variant) => Padding(
    padding: const EdgeInsets.only(right: 1),
    child: Button(label: label, variant: variant, onPressed: () {}),
  );
}

/// One row of the services table.
class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.name,
    required this.status,
    required this.cpu,
    required this.statusColor,
    this.style,
  });

  final String name;
  final String status;
  final String cpu;
  final Color statusColor;
  final CellStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? CellStyle(foreground: context.colors.foreground);
    return Row(
      children: <Widget>[
        Text(' ${name.padRight(13)}', style: base),
        // The status keeps its role colour, merged onto the row style so a
        // selected row still reads as selected.
        Text(
          status.padRight(12),
          style: base.merge(CellStyle(foreground: statusColor)),
        ),
        Text(cpu, style: base),
      ],
    );
  }
}

/// A quieter secondary pane: unfocused, so its chrome stays muted.
class _ActivityPane extends StatelessWidget {
  const _ActivityPane();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Panel(
      title: 'Activity',
      expandChild: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _LogLine(time: '09:24', mark: '✓', text: 'build passed', color: cs.success),
          _LogLine(time: '09:25', mark: 'ℹ', text: 'pushing image', color: cs.info),
          _LogLine(
            time: '09:26',
            mark: '⚠',
            text: 'retrying node-3',
            color: cs.warning,
          ),
          _LogLine(
            time: '09:27',
            mark: '✗',
            text: 'rollback armed',
            color: cs.error,
          ),
          const SizedBox(height: 1),
          Text('4 events · 1 failing', style: context.theme.mutedStyle),
        ],
      ),
    );
  }
}

/// One activity line: muted timestamp, role-coloured mark, plain message.
class _LogLine extends StatelessWidget {
  const _LogLine({
    required this.time,
    required this.mark,
    required this.text,
    required this.color,
  });

  final String time;
  final String mark;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(' $time ', style: context.theme.mutedStyle),
        Text('$mark ', style: CellStyle(foreground: color)),
        Text(text, style: CellStyle(foreground: context.colors.foreground)),
      ],
    );
  }
}

/// Legend: every colour role, then the three text styles a theme defines.
class _PaletteLegend extends StatelessWidget {
  const _PaletteLegend();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final theme = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
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
        Wrap(
          children: <Widget>[
            Text('muted  ', style: theme.mutedStyle),
            Text(' selected ', style: theme.selectionStyle),
            Text('  focused', style: theme.focusedStyle),
          ],
        ),
      ],
    );
  }

  Widget _swatch(String label, Color color) => Padding(
    padding: const EdgeInsets.only(right: 2),
    child: Text('▉ $label', style: CellStyle(foreground: color)),
  );
}
