import 'package:fleury/fleury_core.dart';
import 'package:fleury_themes/fleury_themes.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

/// A live theme studio: compare every bundled community theme against one
/// consistent UI, or edit a small custom theme and watch it update in place.
class ThemingShowcaseApp extends StatefulWidget {
  const ThemingShowcaseApp({super.key});

  @override
  State<ThemingShowcaseApp> createState() => _ThemingShowcaseAppState();
}

enum _PaletteRole { primary, focus, success, warning, error, info }

extension on _PaletteRole {
  String get label => switch (this) {
    _PaletteRole.primary => 'Primary',
    _PaletteRole.focus => 'Focus',
    _PaletteRole.success => 'Success',
    _PaletteRole.warning => 'Warning',
    _PaletteRole.error => 'Error',
    _PaletteRole.info => 'Info',
  };

  String get purpose => switch (this) {
    _PaletteRole.primary => 'Headings, selected values, and primary actions.',
    _PaletteRole.focus => 'Keyboard focus and active regions.',
    _PaletteRole.success => 'Successful and healthy states.',
    _PaletteRole.warning => 'Warnings and attention states.',
    _PaletteRole.error => 'Errors and invalid controls.',
    _PaletteRole.info => 'Informational status.',
  };
}

class _ThemingShowcaseAppState extends State<ThemingShowcaseApp> {
  static final int _customIndex = fleuryThemes.length;
  static const _palette = <Color>[
    AnsiColor(0),
    AnsiColor(1),
    AnsiColor(2),
    AnsiColor(3),
    AnsiColor(4),
    AnsiColor(5),
    AnsiColor(6),
    AnsiColor(7),
    AnsiColor(8),
    AnsiColor(9),
    AnsiColor(10),
    AnsiColor(11),
    AnsiColor(12),
    AnsiColor(13),
    AnsiColor(14),
    AnsiColor(15),
  ];

  final _service = TextEditingController(text: 'api-gateway');
  int _appliedThemeIndex = 0;
  int _shownThemeIndex = 0;
  Brightness _brightness = Brightness.dark;
  BorderStyle _borderStyle = BorderStyle.rounded;
  Color _primary = const AnsiColor(6);
  Color _focus = const AnsiColor(14);
  Color _success = const AnsiColor(10);
  Color _warning = const AnsiColor(11);
  Color _error = const AnsiColor(9);
  Color _info = const AnsiColor(14);
  _PaletteRole _paletteRole = _PaletteRole.primary;
  String _environment = 'Production';
  bool _logs = true;
  bool _autoDeploy = true;
  num _replicas = 3;
  String _status = 'Ready to deploy';

  bool get _isCustom => _shownThemeIndex == _customIndex;

  ThemeData get _customTheme {
    final dark = _brightness == Brightness.dark;
    final foreground = dark ? const AnsiColor(15) : const AnsiColor(0);
    final background = dark ? const AnsiColor(0) : const AnsiColor(15);
    final surface = dark ? const AnsiColor(8) : const AnsiColor(7);
    return ThemeData(
      brightness: _brightness,
      textStyle: CellStyle(foreground: foreground),
      mutedStyle: const CellStyle(foreground: AnsiColor(8), dim: true),
      selectionStyle: const CellStyle(inverse: true, bold: true),
      focusedStyle: CellStyle(foreground: _focus, bold: true),
      errorStyle: CellStyle(foreground: _error, underline: true),
      interactiveStyle: CellStyle.interactive(
        focused: CellStyle(foreground: _focus, bold: true),
        selected: CellStyle(foreground: _primary, bold: true),
        invalid: CellStyle(foreground: _error, underline: true),
        disabled: const CellStyle(dim: true),
      ),
      borderStyle: _borderStyle,
      colorScheme: ColorScheme(
        foreground: foreground,
        background: background,
        surface: surface,
        primary: _primary,
        focus: _focus,
        success: _success,
        warning: _warning,
        error: _error,
        info: _info,
      ),
    );
  }

  ThemeData get _activeTheme =>
      _isCustom ? _customTheme : fleuryThemes[_shownThemeIndex].data;

  String get _activeName =>
      _isCustom ? 'Custom' : fleuryThemes[_shownThemeIndex].name;

  Color get _paletteColor => switch (_paletteRole) {
    _PaletteRole.primary => _primary,
    _PaletteRole.focus => _focus,
    _PaletteRole.success => _success,
    _PaletteRole.warning => _warning,
    _PaletteRole.error => _error,
    _PaletteRole.info => _info,
  };

  void _setPaletteColor(Color color) => setState(() {
    switch (_paletteRole) {
      case _PaletteRole.primary:
        _primary = color;
        break;
      case _PaletteRole.focus:
        _focus = color;
        break;
      case _PaletteRole.success:
        _success = color;
        break;
      case _PaletteRole.warning:
        _warning = color;
        break;
      case _PaletteRole.error:
        _error = color;
        break;
      case _PaletteRole.info:
        _info = color;
        break;
    }
  });

  void _resetCustom() => setState(() {
    _brightness = Brightness.dark;
    _borderStyle = BorderStyle.rounded;
    _primary = const AnsiColor(6);
    _focus = const AnsiColor(14);
    _success = const AnsiColor(10);
    _warning = const AnsiColor(11);
    _error = const AnsiColor(9);
    _info = const AnsiColor(14);
  });

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _activeTheme;
    return Theme(
      data: theme,
      child: Container(
        color: theme.colorScheme.background,
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('THEME STUDIO', style: CellStyle(bold: true)),
            Row(
              children: <Widget>[
                const Text('Theme  '),
                Select<int>(
                  autofocus: true,
                  semanticLabel: 'Theme',
                  value: _appliedThemeIndex,
                  options: <SelectOption<int>>[
                    for (final (index, theme) in fleuryThemes.indexed)
                      SelectOption(value: index, label: theme.name),
                    SelectOption(value: _customIndex, label: 'Custom'),
                  ],
                  onHighlightChanged: (value) {
                    if (value != null) {
                      setState(() => _shownThemeIndex = value);
                    }
                  },
                  onChanged: (value) => setState(() {
                    _appliedThemeIndex = value;
                    _shownThemeIndex = value;
                  }),
                ),
                const SizedBox(width: 2),
                Text(
                  _isCustom
                      ? 'Edit primary, focus, and status colors live.'
                      : 'The same UI, rendered by $_activeName.',
                  style: theme.mutedStyle,
                ),
              ],
            ),
            const SizedBox(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: 39,
                    child: _isCustom
                        ? _customEditor()
                        : const _ThemeRoleInspector(),
                  ),
                  const SizedBox(width: 1),
                  Expanded(child: _widgetGallery(theme)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customEditor() => Panel(
    title: 'CUSTOM THEME',
    child: Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const SizedBox(width: 8, child: Text('Mode')),
              const SizedBox(width: 1),
              Select<Brightness>(
                semanticLabel: 'Brightness',
                value: _brightness,
                options: const <SelectOption<Brightness>>[
                  SelectOption(value: Brightness.dark, label: 'Dark'),
                  SelectOption(value: Brightness.light, label: 'Light'),
                ],
                onChanged: (value) => setState(() => _brightness = value),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              const SizedBox(width: 8, child: Text('Border')),
              const SizedBox(width: 1),
              Select<BorderStyle>(
                semanticLabel: 'Border',
                value: _borderStyle,
                options: <SelectOption<BorderStyle>>[
                  for (final style in BorderStyle.values)
                    SelectOption(value: style, label: _borderLabel(style)),
                ],
                onChanged: (value) => setState(() => _borderStyle = value),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Row(
            children: <Widget>[
              const SizedBox(width: 8, child: Text('Preview')),
              const SizedBox(width: 1),
              Container(
                width: 22,
                height: 3,
                alignment: Alignment.center,
                border: BoxBorder(
                  style: _borderStyle,
                  cellStyle: CellStyle(foreground: _primary),
                ),
                child: Text('${_borderLabel(_borderStyle)} border'),
              ),
            ],
          ),
          const SizedBox(height: 1),
          const Text('Theme colors', style: CellStyle(bold: true)),
          Row(
            children: <Widget>[
              const SizedBox(width: 8, child: Text('Role')),
              const SizedBox(width: 1),
              Select<_PaletteRole>(
                semanticLabel: 'Palette role',
                value: _paletteRole,
                options: <SelectOption<_PaletteRole>>[
                  for (final role in _PaletteRole.values)
                    SelectOption(value: role, label: role.label),
                ],
                onChanged: (value) => setState(() => _paletteRole = value),
              ),
            ],
          ),
          Text(_paletteRole.purpose, style: context.theme.mutedStyle),
          const SizedBox(height: 1),
          Text(
            '${_paletteRole.label} color',
            style: const CellStyle(bold: true),
          ),
          const Text('ANSI palette'),
          ColorPicker(
            value: _paletteColor,
            colors: _palette,
            columns: 4,
            swatchWidth: 3,
            semanticLabel: '${_paletteRole.label} color',
            semanticColorLabelBuilder: (color, _) =>
                '${_paletteRole.label}: ${_colorLabel(color)}',
            onChanged: _setPaletteColor,
          ),
          const SizedBox(height: 1),
          Button(label: 'Reset custom theme', onPressed: _resetCustom),
        ],
      ),
    ),
  );

  Widget _widgetGallery(ThemeData theme) => Panel(
    title: 'LIVE WIDGET GALLERY',
    child: Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _galleryHeading(theme, 'Form controls'),
          const SizedBox(height: 1),
          _galleryRow(
            'Service',
            SizedBox(
              width: 27,
              child: FormField(
                error: _service.text.trim().isEmpty
                    ? 'Service name is required.'
                    : null,
                child: TextInput(
                  controller: _service,
                  semanticLabel: 'Service name',
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
          ),
          _galleryRow(
            'Environment',
            Select<String>(
              semanticLabel: 'Environment',
              value: _environment,
              options: const <SelectOption<String>>[
                SelectOption(value: 'Development', label: 'Development'),
                SelectOption(value: 'Staging', label: 'Staging'),
                SelectOption(value: 'Production', label: 'Production'),
              ],
              onChanged: (value) => setState(() => _environment = value),
            ),
          ),
          _galleryRow(
            'Logging',
            Checkbox(
              value: _logs,
              label: 'Enabled',
              onChanged: (value) => setState(() => _logs = value),
            ),
          ),
          _galleryRow(
            'Automation',
            Switch(
              value: _autoDeploy,
              label: 'Auto deploy',
              onChanged: (value) => setState(() => _autoDeploy = value),
            ),
          ),
          _galleryRow(
            'Replicas',
            Stepper(
              value: _replicas,
              min: 1,
              max: 9,
              onChanged: (value) => setState(() => _replicas = value),
            ),
          ),
          const SizedBox(height: 1),
          _galleryHeading(theme, 'Status and progress'),
          const SizedBox(height: 1),
          _galleryRow(
            'CPU',
            const SizedBox(
              width: 34,
              child: Gauge(value: 0.68, showPercentage: true),
            ),
          ),
          _galleryRow(
            'Deployment',
            const Row(
              children: <Widget>[
                SizedBox(width: 28, child: ProgressBar(value: 0.42)),
                Text(' 42%'),
              ],
            ),
          ),
          _galleryRow(
            'States',
            Wrap(
              children: <Widget>[
                Text(
                  'success  ',
                  style: CellStyle(foreground: theme.colorScheme.success),
                ),
                Text(
                  'warning  ',
                  style: CellStyle(foreground: theme.colorScheme.warning),
                ),
                Text(
                  'error  ',
                  style: CellStyle(foreground: theme.colorScheme.error),
                ),
                Text(
                  'info',
                  style: CellStyle(foreground: theme.colorScheme.info),
                ),
              ],
            ),
          ),
          const SizedBox(height: 1),
          _galleryHeading(theme, 'Data and actions'),
          const SizedBox(height: 1),
          _galleryRow(
            'Selected',
            Text('api-gateway  healthy  42%', style: theme.selectionStyle),
          ),
          _galleryRow(
            'Default',
            Text('worker-01    running  18%', style: theme.textStyle),
          ),
          _galleryRow(
            'Muted',
            Text('cron-cleanup paused    0%', style: theme.mutedStyle),
          ),
          const SizedBox(height: 1),
          _galleryRow(
            'Actions',
            Row(
              children: <Widget>[
                Button(
                  label: 'Deploy',
                  variant: ButtonVariant.primary,
                  onPressed: () => setState(() => _status = 'Deploy queued'),
                ),
                const SizedBox(width: 1),
                const Button(label: 'Unavailable', onPressed: null),
              ],
            ),
          ),
          _galleryRow('Result', Text(_status, style: theme.mutedStyle)),
        ],
      ),
    ),
  );

  Widget _galleryHeading(ThemeData theme, String label) => Text(
    label,
    style: CellStyle(foreground: theme.colorScheme.primary, bold: true),
  );

  Widget _galleryRow(String label, Widget child) => Row(
    children: <Widget>[
      SizedBox(width: 13, child: Text(label)),
      const SizedBox(width: 1),
      child,
    ],
  );
}

String _borderLabel(BorderStyle style) => switch (style) {
  BorderStyle.single => 'Single-line',
  BorderStyle.double => 'Double-line',
  BorderStyle.rounded => 'Rounded',
  BorderStyle.ascii => 'ASCII',
};

String _colorLabel(Color color) {
  final rgb = color.toRgb();
  final hex = <int>[rgb.r, rgb.g, rgb.b]
      .map((channel) => channel.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
  return color is AnsiColor ? 'ANSI ${color.index} (#$hex)' : '#$hex';
}

class _ThemeRoleInspector extends StatelessWidget {
  const _ThemeRoleInspector();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = context.colors;
    return Panel(
      title: 'SEMANTIC ROLES',
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Typography'),
            Text('Default application text', style: theme.textStyle),
            Text('Muted hints and metadata', style: theme.mutedStyle),
            Text('Selected row or item', style: theme.selectionStyle),
            Text('Focused region', style: theme.focusedStyle),
            Text('Validation message', style: theme.errorStyle),
            const SizedBox(height: 1),
            const Text('Color scheme'),
            _swatch('primary', colors.primary),
            _swatch('focus', colors.focus),
            _swatch('success', colors.success),
            _swatch('warning', colors.warning),
            _swatch('error', colors.error),
            _swatch('info', colors.info),
            const SizedBox(height: 1),
            Text(
              '${theme.brightness.name} · ${theme.borderStyle.name} borders',
              style: theme.mutedStyle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _swatch(String label, Color color) =>
      Text('██ $label', style: CellStyle(foreground: color));
}
