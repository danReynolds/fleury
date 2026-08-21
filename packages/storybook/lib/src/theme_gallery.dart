import 'package:fleury/fleury.dart';
import 'package:fleury_themes/fleury_themes.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

/// A styleguide for one theme from `fleury_themes` at a time, with a
/// dropdown to switch palettes — the storybook's "Themes" story.
///
/// Two halves, because they answer different questions. A small mock app shows
/// how a theme *reads* on real UI; the labelled reference below it shows what a
/// theme *controls*. The reference is deliberately exhaustive: every
/// [ColorScheme] role and every [ThemeData] style field appears with its name
/// next to it, so a theme author can see the whole surface they own rather than
/// inferring it from a screenshot.
///
/// The dropdown live-previews: arrowing through it re-themes everything
/// immediately, Enter keeps the choice, Esc puts the previous one back.
class ThemeGallery extends StatefulWidget {
  const ThemeGallery({super.key, this.themes = fleuryThemes});

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
            const Text('   '),
            Text(
              selected.data.brightness.name,
              style: Theme.of(context).mutedStyle,
            ),
          ],
        ),
        // No gap here: the styleguide's own padding and its first section
        // heading already supply one, and three stacked blanks read as a bug.
        Theme(data: selected.data, child: const _ThemeStyleguide()),
      ],
    );
  }
}

/// A section heading in the styleguide. Muted and uppercase so it reads as
/// chrome rather than as themed content.
class _Section extends StatelessWidget {
  const _Section(this.label, {this.note});

  final String label;

  /// What this section is demonstrating, in the theme's own vocabulary.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final muted = context.theme.mutedStyle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 1),
        Text(label.toUpperCase(), style: muted),
        if (note != null) Text(note!, style: muted),
      ],
    );
  }
}

/// A caption under a demo, naming the thing above it.
class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text('  $text', style: context.theme.mutedStyle);
}

class _ThemeStyleguide extends StatelessWidget {
  const _ThemeStyleguide();

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
              const _Section('In context', note: 'the same theme on real UI'),
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
              // The captions name which pane is which, so the focus chrome
              // reads as a demonstrated state rather than an accident of
              // where the cursor happens to be.
              _Caption(
                '${wide ? 'left' : 'top'}: active — border + title take '
                '`focus`',
              ),
              _Caption(
                '${wide ? 'right' : 'below'}: at rest — border takes '
                '`mutedStyle`',
              ),
              const _Caption('both: borderStyle draws the frame'),
              const _ColourRoles(),
              const _TextStyles(),
              const _Controls(),
            ],
          );
        },
      ),
    );
  }
}

/// Every [ColorScheme] role, named. The nullable roles say so explicitly —
/// "unset" is a real, deliberate value (it means the terminal's own colour).
class _ColourRoles extends StatelessWidget {
  const _ColourRoles();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _Section('Colour roles', note: 'ColorScheme'),
        Wrap(
          children: <Widget>[
            _swatch(context, 'primary', cs.primary),
            _swatch(context, 'focus', cs.focus),
            _swatch(context, 'success', cs.success),
          ],
        ),
        Wrap(
          children: <Widget>[
            _swatch(context, 'warning', cs.warning),
            _swatch(context, 'error', cs.error),
            _swatch(context, 'info', cs.info),
          ],
        ),
        Wrap(
          children: <Widget>[
            _swatch(context, 'foreground', cs.foreground),
            _swatch(context, 'background', cs.background),
            _swatch(context, 'surface', cs.surface),
          ],
        ),
      ],
    );
  }

  Widget _swatch(BuildContext context, String label, Color? color) => Padding(
    padding: const EdgeInsets.only(right: 2),
    child: color == null
        // An unset role is not a missing one: it means "use the terminal's
        // own", which is the right default for foreground/background.
        ? Text('· $label unset', style: context.theme.mutedStyle)
        : Text('▉ $label', style: CellStyle(foreground: color)),
  );
}

/// The [ThemeData] text styles, each shown applied and named after the
/// field that produced it.
class _TextStyles extends StatelessWidget {
  const _TextStyles();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _Section('Text styles', note: 'ThemeData'),
        // One shape for every row so the labels form a column — the
        // sample is padded to a fixed width rather than each row spacing
        // itself, which is what threw the alignment off.
        _sample(context, theme.textStyle, 'textStyle'),
        _sample(context, theme.mutedStyle, 'mutedStyle'),
        _sample(context, theme.selectionStyle, 'selectionStyle'),
        _sample(context, theme.focusedStyle, 'focusedStyle'),
        _sample(context, theme.errorStyle, 'errorStyle'),
      ],
    );
  }

  /// One style row: the sample in [style], then the field name that produced
  /// it. The sample is padded to a fixed width so the names align.
  Widget _sample(BuildContext context, CellStyle style, String field) => Row(
    children: <Widget>[
      Text('  the quick brown fox  '.padRight(25), style: style),
      Text('  $field', style: context.theme.mutedStyle),
    ],
  );
}

/// Widgets whose theming isn't visible in the mock app above: interactive
/// states and the raised `surface` fill.
class _Controls extends StatefulWidget {
  const _Controls();

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  final _query = TextEditingController(text: 'search query');
  bool _checked = true;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _Section('Controls', note: 'tab in to see focus treatment'),
        SizedBox(
          width: 30,
          child: TextInput(
            controller: _query,
            semanticLabel: 'Styleguide input',
          ),
        ),
        const _Caption('TextInput · focused / hovered'),
        Row(
          children: <Widget>[
            Checkbox(
              value: _checked,
              onChanged: (value) => setState(() => _checked = value),
              label: 'selected',
            ),
            const Text('   '),
            const Checkbox(value: false, onChanged: null, label: 'disabled'),
          ],
        ),
        const _Caption('Checkbox · selected / disabled'),
        SizedBox(
          width: 30,
          child: TextInput(
            placeholder: 'invalid control',
            validationError: 'Required',
            semanticLabel: 'Invalid styleguide input',
          ),
        ),
        const _Caption('TextInput · invalid'),
        _Caption(
          context.theme.controlStyle == null
              ? 'controlStyle · unset (widget defaults)'
              : 'controlStyle · ThemeData.controlStyle',
        ),
        const SizedBox(height: 1),
        // `surface` is the one role with no place in the mock app: it fills
        // dialogs and popups, which need an opaque backdrop rather than the
        // terminal's own background.
        SizedBox(
          width: 34,
          child: Container.filled(
            padding: const EdgeInsets.all(1),
            child: Text(
              'raised surface — dialogs, popups',
              style: CellStyle(foreground: context.colors.foreground),
            ),
          ),
        ),
        const _Caption('Surface · ColorScheme.surface'),
      ],
    );
  }
}

/// The "active" pane — focus pinned on, so its border and title take the
/// theme accent regardless of where real focus is.
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

/// A quieter secondary pane: at rest, so its chrome stays muted.
class _ActivityPane extends StatelessWidget {
  const _ActivityPane();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Panel(
      title: 'Activity',
      focused: false,
      expandChild: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _LogLine(
            time: '09:24',
            mark: '✓',
            text: 'build passed',
            color: cs.success,
          ),
          _LogLine(
            time: '09:25',
            mark: 'ℹ',
            text: 'pushing image',
            color: cs.info,
          ),
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
