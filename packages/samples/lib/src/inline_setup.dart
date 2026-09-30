import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

/// The host decides how to provide the space requested by each page.
enum InlineSetupStep {
  configure(17),
  review(21);

  const InlineSetupStep(this.rows);
  final int rows;
}

enum ProjectTemplate {
  cli('CLI', 'A command you can run from your terminal.'),
  library('Library', 'A Dart package other projects can import.');

  const ProjectTemplate(this.label, this.description);
  final String label;
  final String description;
}

/// A generated configuration, held in memory. Neither host writes files.
final class InlineSetupResult {
  const InlineSetupResult({
    required this.name,
    required this.template,
    required this.includeTests,
  });

  final String name;
  final ProjectTemplate template;
  final bool includeTests;

  List<String> get files => [
    'pubspec.yaml',
    '${template == ProjectTemplate.cli ? 'bin' : 'lib'}/$name.dart',
    if (includeTests) 'test/${name}_test.dart',
  ];

  String get manifest => [
    'name: $name',
    'version: 0.1.0',
    '',
    'environment:',
    "  sdk: '^3.10.4'",
    if (includeTests) ...['', 'dev_dependencies:', "  test: '^1.26.3'"],
  ].join('\n');

  String get summary =>
      '✓ Configuration ready for $name\n'
      '  ${template.label} · ${files.length} files'
      '${includeTests ? ' · Tests included' : ''}';
}

/// Shared setup flow for the inline terminal command and browser preview.
///
/// The host handles viewport changes and the final result. This widget owns
/// only the form, validation, focus, and review. Escape goes back from review
/// or cancels from setup; null is the cancelled result.
class InlineSetup extends StatefulWidget {
  const InlineSetup({
    super.key,
    required this.onComplete,
    this.onStepChanged,
    this.onOpenPager,
  });

  final void Function(InlineSetupResult? result) onComplete;
  final void Function(InlineSetupStep step)? onStepChanged;

  /// Native hosts can lend the terminal to a pager without replacing this form.
  final Future<void> Function(InlineSetupResult result)? onOpenPager;

  @override
  State<InlineSetup> createState() => _InlineSetupState();
}

class _InlineSetupState extends State<InlineSetup> {
  final _name = TextEditingController(text: 'orbit');
  final _nameFocus = FocusNode(debugLabel: 'Project name');
  var _template = ProjectTemplate.cli;
  var _tests = true;
  var _step = InlineSetupStep.configure;
  String? _error;
  var _finished = false;
  var _openingPager = false;
  String? _pagerMessage;

  Future<void> _openPager() async {
    if (_openingPager) return;
    _openingPager = true;
    try {
      await widget.onOpenPager!(_result);
      if (mounted)
        setState(
          () => _pagerMessage = 'Back from less. Your setup is unchanged.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () =>
              _pagerMessage = 'Could not open less. You can still review here.',
        );
    } finally {
      _openingPager = false;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  InlineSetupResult get _result => InlineSetupResult(
    name: _name.text.trim(),
    template: _template,
    includeTests: _tests,
  );

  void _review() {
    final name = _name.text.trim();
    if (!RegExp(r'^[a-z][a-z0-9_]{0,31}$').hasMatch(name)) {
      setState(
        () => _error = name.isEmpty
            ? 'Give your project a name.'
            : 'Use 1–32 lowercase letters, numbers or underscores; start with a letter.',
      );
      _nameFocus.requestFocus();
      return;
    }
    _changeStep(InlineSetupStep.review);
  }

  void _changeStep(InlineSetupStep step) {
    setState(() {
      _step = step;
      if (step == InlineSetupStep.configure) _pagerMessage = null;
    });
    widget.onStepChanged?.call(step);
  }

  void _complete(InlineSetupResult? result) {
    if (_finished) return;
    _finished = true;
    widget.onComplete(result);
  }

  void _escape() {
    if (_step == InlineSetupStep.review) {
      _changeStep(InlineSetupStep.configure);
    } else {
      _complete(null);
    }
  }

  // Inherit the host theme. With Fleury's defaults, unpainted cells use the
  // terminal's own foreground/background instead of a rectangular demo fill.
  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    child: KeyBindings(
      bindings: [KeyBinding(KeySequence.escape, onTrigger: (_) => _escape())],
      child: LayoutBuilder(
        builder: (_, constraints) =>
            _body(compact: (constraints.maxRows ?? 12) < 12),
      ),
    ),
  );

  Widget _body({required bool compact}) => Padding(
    padding: EdgeInsets.symmetric(horizontal: 2, vertical: compact ? 0 : 1),
    child: Column(
      // A page owns its focus lifecycle. Remove the old controls
      // before mounting the new page's autofocus candidate.
      key: ValueKey(_step),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Project setup', style: _accent)),
            Text(
              _step == InlineSetupStep.configure ? '1 / 2' : '2 / 2',
              style: _muted,
            ),
          ],
        ),
        SizedBox(height: compact ? 0 : 1),
        Expanded(
          child: ScrollView(
            scrollbar: true,
            child: _step == InlineSetupStep.configure
                ? _configure()
                : _reviewContent(),
          ),
        ),
        SizedBox(height: compact ? 0 : 1),
        Wrap(
          spacing: 2,
          runSpacing: 0,
          children: [
            _step == InlineSetupStep.configure
                ? _action('Review →', _review, primary: true)
                : _action(
                    'Generate config',
                    () => _complete(_result),
                    primary: true,
                    autofocus: true,
                  ),
            if (_step == InlineSetupStep.review && widget.onOpenPager != null)
              _action('View in pager', _openPager),
            if (_step == InlineSetupStep.review)
              _action('Back', () => _changeStep(InlineSetupStep.configure)),
            _action('Cancel', () => _complete(null)),
          ],
        ),
      ],
    ),
  );

  Widget _configure() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Project name'),
      SizedBox(
        width: 40,
        child: TextInput(
          controller: _name,
          focusNode: _nameFocus,
          autofocus: true,
          semanticLabel: 'Project name',
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmit: (_) => _review(),
        ),
      ),
      if (_error != null)
        Text(
          _error!,
          style: const CellStyle(foreground: AnsiColor(1), underline: true),
        ),
      const SizedBox(height: 1),
      const Text('Template'),
      LayoutBuilder(
        builder: (_, constraints) => RadioGroup<ProjectTemplate>(
          semanticLabel: 'Project template',
          axis: (constraints.maxCols ?? 40) < 32
              ? Axis.vertical
              : Axis.horizontal,
          value: _template,
          onChanged: (value) => setState(() => _template = value),
          options: [
            for (final template in ProjectTemplate.values)
              RadioOption(value: template, label: template.label),
          ],
        ),
      ),
      Text(_template.description, style: _muted),
      const SizedBox(height: 1),
      Checkbox(
        value: _tests,
        label: 'Include tests',
        onChanged: (value) => setState(() => _tests = value),
      ),
    ],
  );

  Widget _reviewContent() {
    final result = _result;
    final tree = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${result.name}/', style: _accent),
        for (var i = 0; i < result.files.length; i++)
          Text(
            '${i == result.files.length - 1 ? '└' : '├'}─ ${result.files[i]}',
          ),
        const SizedBox(height: 1),
        Text('${result.template.label} template', style: _muted),
      ],
    );
    final manifest = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('pubspec.yaml', style: _muted),
        const SizedBox(height: 1),
        Text(result.manifest),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_pagerMessage != null) ...[
          Text(_pagerMessage!, style: _muted),
          const SizedBox(height: 1),
        ],
        const Text('Your project, at a glance.'),
        const SizedBox(height: 1),
        LayoutBuilder(
          builder: (_, constraints) => (constraints.maxCols ?? 0) >= 70
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: tree),
                    const SizedBox(width: 3),
                    Expanded(child: manifest),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [tree, const SizedBox(height: 1), manifest],
                ),
        ),
      ],
    );
  }
}

const _accent = CellStyle(bold: true);
const _muted = CellStyle(dim: true);

Widget _action(
  String label,
  void Function() action, {
  bool primary = false,
  bool autofocus = false,
}) => Button(
  key: ValueKey(label),
  text: label,
  autofocus: autofocus,
  onPressed: action,
  style: CellStyle.interactive(
    base: primary ? _accent : const CellStyle(),
    focused: const CellStyle(inverse: true, bold: true),
    hovered: const CellStyle(underline: true),
  ),
);

/// Browser presentation of the command lifecycle. The shell lines are a scene;
/// [InlineSetup] is the same interactive form used by the native command.
class InlineSetupPreview extends StatefulWidget {
  const InlineSetupPreview({super.key, this.fullScreen = false});

  /// Illustrates an alternate-screen session using the same form. The web
  /// host still owns a DOM element; it does not switch a terminal buffer.
  final bool fullScreen;

  @override
  State<InlineSetupPreview> createState() => _InlineSetupPreviewState();
}

class _InlineSetupPreviewState extends State<InlineSetupPreview> {
  InlineSetupResult? _result;
  var _finished = false;
  var _step = InlineSetupStep.configure;
  var _started = false;

  bool get _running => (!widget.fullScreen || _started) && !_finished;

  void _reset() => setState(() {
    _result = null;
    _finished = false;
    _step = InlineSetupStep.configure;
    _started = true;
  });

  @override
  Widget build(BuildContext context) => Theme(
    data: const ThemeData(),
    child: FocusTraversalGroup(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.fullScreen || !_running) ...[
              const Text(r'~/projects $ ls', style: _muted),
              const Text('notes/    sandbox/', style: _muted),
              const SizedBox(height: 1),
              Text(
                widget.fullScreen
                    ? r'~/projects $ project-setup --full-screen'
                    : r'~/projects $ project-setup',
              ),
            ],
            if (widget.fullScreen && !_started) ...[
              const SizedBox(height: 1),
              Button(text: 'Run command', autofocus: true, onPressed: _reset),
            ],
            if (_running)
              Flexible(
                fit: widget.fullScreen ? FlexFit.tight : FlexFit.loose,
                child: SizedBox(
                  height: widget.fullScreen ? null : _step.rows,
                  child: InlineSetup(
                    onStepChanged: (step) => setState(() => _step = step),
                    onComplete: (result) => setState(() {
                      _result = result;
                      _finished = true;
                    }),
                  ),
                ),
              ),
            if (_finished) ...[
              const SizedBox(height: 1),
              Text(
                _result?.summary ?? 'Setup cancelled.',
                style: _result == null ? _muted : _accent,
              ),
              const SizedBox(height: 1),
              const Text(r'~/projects $ ▌'),
              const SizedBox(height: 2),
              Button(text: 'Run again', autofocus: true, onPressed: _reset),
            ],
          ],
        ),
      ),
    ),
  );
}
