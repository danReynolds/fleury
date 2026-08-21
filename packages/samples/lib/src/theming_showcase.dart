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
  String _environment = 'Production';
  bool _logs = true;
  bool _autoDeploy = true;
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
      interactiveStyle: CellStyle.state(
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
                  onHighlightChanged: (value) =>
                      setState(() => _shownThemeIndex = value),
                  onChanged: (value) => setState(() {
                    _appliedThemeIndex = value;
                    _shownThemeIndex = value;
                  }),
                ),
                const SizedBox(width: 2),
                Text(
                  _isCustom
                      ? 'Edit colors, brightness, and borders live.'
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
                    width: 43,
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
              const SizedBox(width: 9, child: Text('Mode')),
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
              const SizedBox(width: 9, child: Text('Border')),
              Select<BorderStyle>(
                semanticLabel: 'Border',
                value: _borderStyle,
                options: <SelectOption<BorderStyle>>[
                  for (final style in BorderStyle.values)
                    SelectOption(value: style, label: style.name),
                ],
                onChanged: (value) => setState(() => _borderStyle = value),
              ),
            ],
          ),
          const SizedBox(height: 1),
          _colorField('Accent', 'Accent color', _primary, (color) {
            setState(() => _primary = color);
          }),
          _colorField('Focus', 'Focus color', _focus, (color) {
            setState(() => _focus = color);
          }),
          _colorField('Success', 'Success color', _success, (color) {
            setState(() => _success = color);
          }),
          _colorField('Warning', 'Warning color', _warning, (color) {
            setState(() => _warning = color);
          }),
          _colorField('Error', 'Error color', _error, (color) {
            setState(() => _error = color);
          }),
          _colorField('Info', 'Info color', _info, (color) {
            setState(() => _info = color);
          }),
          const SizedBox(height: 1),
          Button(label: 'Reset custom theme', onPressed: _resetCustom),
        ],
      ),
    ),
  );

  Widget _colorField(
    String label,
    String semanticLabel,
    Color value,
    void Function(Color) onChanged,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      SizedBox(width: 9, child: Text(label)),
      ColorPicker(
        value: value,
        colors: _palette,
        columns: 8,
        swatchWidth: 1,
        semanticLabel: semanticLabel,
        semanticColorLabelBuilder: (_, index) => '$label option ${index + 1}',
        onChanged: onChanged,
      ),
    ],
  );

  Widget _widgetGallery(ThemeData theme) => Panel(
    title: 'LIVE WIDGET GALLERY',
    child: Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Form controls', style: theme.focusedStyle),
          Row(
            children: <Widget>[
              const SizedBox(width: 11, child: Text('Service')),
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
            ],
          ),
          Row(
            children: <Widget>[
              const SizedBox(width: 11, child: Text('Environment')),
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
            ],
          ),
          Row(
            children: <Widget>[
              Checkbox(
                value: _logs,
                label: 'Logs',
                onChanged: (value) => setState(() => _logs = value),
              ),
              const SizedBox(width: 3),
              Switch(
                value: _autoDeploy,
                label: 'Auto deploy',
                onChanged: (value) => setState(() => _autoDeploy = value),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text('Status and progress', style: theme.focusedStyle),
          const SizedBox(width: 39, child: Gauge(value: 0.68, label: 'CPU')),
          const SizedBox(width: 39, child: ProgressBar(value: 0.42)),
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
          const SizedBox(height: 1),
          Text('Data and actions', style: theme.focusedStyle),
          Text('> api-gateway   healthy   42%', style: theme.selectionStyle),
          Text('  worker-01     running   18%', style: theme.textStyle),
          Text('  cron-cleanup  paused     0%', style: theme.mutedStyle),
          const SizedBox(height: 1),
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
          Text(_status, style: theme.mutedStyle),
        ],
      ),
    ),
  );
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
