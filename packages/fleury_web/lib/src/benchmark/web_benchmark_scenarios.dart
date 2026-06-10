import 'package:fleury/fleury_host.dart';

/// Browser benchmark scenario behavior.
enum WebBenchmarkScenarioKind {
  normal,
  noOp,
  singleDirtyCell,
  dirtyRow,
  fullFrameChurn,
  scrollRowChurn,
  scrollKeyed,
  cursorBlink,
  textInputBurst,
  resizeBurst,
}

/// Product-shaped browser scenario metadata used by the retained DOM harness.
final class WebBenchmarkScenario {
  const WebBenchmarkScenario({
    required this.id,
    required this.label,
    required this.kind,
    required this.cols,
    required this.rows,
    required this.defaultFrames,
    required this.description,
  });

  final String id;
  final String label;
  final WebBenchmarkScenarioKind kind;
  final int cols;
  final int rows;
  final int defaultFrames;
  final String description;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'kind': kind.name,
      'cols': cols,
      'rows': rows,
      'defaultFrames': defaultFrames,
      'description': description,
    };
  }
}

const webBenchmarkScenarios = <WebBenchmarkScenario>[
  WebBenchmarkScenario(
    id: 'normal-80x24',
    label: '80x24 normal app interaction',
    kind: WebBenchmarkScenarioKind.normal,
    cols: 80,
    rows: 24,
    defaultFrames: 24,
    description:
        'Small dashboard-style app with log, command, and status regions.',
  ),
  WebBenchmarkScenario(
    id: 'large-160x50',
    label: '160x50 large viewport',
    kind: WebBenchmarkScenarioKind.dirtyRow,
    cols: 160,
    rows: 50,
    defaultFrames: 32,
    description: 'Large operational grid with one dirty row per frame.',
  ),
  WebBenchmarkScenario(
    id: 'stress-300x100',
    label: '300x100 stress viewport',
    kind: WebBenchmarkScenarioKind.fullFrameChurn,
    cols: 300,
    rows: 100,
    defaultFrames: 16,
    description: 'Very large retained grid with full-frame text churn.',
  ),
  WebBenchmarkScenario(
    id: 'noop-160x50',
    label: '160x50 no-op frame',
    kind: WebBenchmarkScenarioKind.noOp,
    cols: 160,
    rows: 50,
    defaultFrames: 24,
    description: 'Repeated host frame requests without widget state changes.',
  ),
  WebBenchmarkScenario(
    id: 'single-dirty-cell-160x50',
    label: '160x50 single dirty cell',
    kind: WebBenchmarkScenarioKind.singleDirtyCell,
    cols: 160,
    rows: 50,
    defaultFrames: 32,
    description:
        'One counter cell changes while the surrounding grid is stable.',
  ),
  WebBenchmarkScenario(
    id: 'dirty-row-160x50',
    label: '160x50 dirty row',
    kind: WebBenchmarkScenarioKind.dirtyRow,
    cols: 160,
    rows: 50,
    defaultFrames: 32,
    description: 'One full row changes per frame.',
  ),
  WebBenchmarkScenario(
    id: 'full-frame-churn-160x50',
    label: '160x50 full-frame churn',
    kind: WebBenchmarkScenarioKind.fullFrameChurn,
    cols: 160,
    rows: 50,
    defaultFrames: 24,
    description: 'Every visible row changes on every frame.',
  ),
  WebBenchmarkScenario(
    id: 'scroll-row-churn-160x50',
    label: '160x50 scroll-like row churn',
    kind: WebBenchmarkScenarioKind.scrollRowChurn,
    cols: 160,
    rows: 50,
    defaultFrames: 32,
    description: 'Log viewport shifts by one row per frame.',
  ),
  WebBenchmarkScenario(
    id: 'scroll-keyed-160x50',
    label: '160x50 keyed scrolling log',
    kind: WebBenchmarkScenarioKind.scrollKeyed,
    cols: 160,
    rows: 50,
    defaultFrames: 32,
    description:
        'Same shifting viewport as scroll-row-churn, written the idiomatic '
        'way: rows keyed by absolute log index behind per-row repaint '
        'boundaries, so unchanged lines move instead of rebuilding.',
  ),
  WebBenchmarkScenario(
    id: 'cursor-blink-80x24',
    label: '80x24 cursor blink',
    kind: WebBenchmarkScenarioKind.cursorBlink,
    cols: 80,
    rows: 24,
    defaultFrames: 24,
    description: 'Focused input cursor style toggles while text is stable.',
  ),
  WebBenchmarkScenario(
    id: 'text-input-burst-80x24',
    label: '80x24 text input burst',
    kind: WebBenchmarkScenarioKind.textInputBurst,
    cols: 80,
    rows: 24,
    defaultFrames: 20,
    description: 'Hidden browser textarea dispatches printable input events.',
  ),
  WebBenchmarkScenario(
    id: 'resize-burst',
    label: 'Resize burst',
    kind: WebBenchmarkScenarioKind.resizeBurst,
    cols: 80,
    rows: 24,
    defaultFrames: 12,
    description: 'Host container alternates between small and large viewports.',
  ),
];

WebBenchmarkScenario? webBenchmarkScenarioById(String id) {
  for (final scenario in webBenchmarkScenarios) {
    if (scenario.id == id) return scenario;
  }
  return null;
}

/// Stateful benchmark driver used by browser captures.
///
/// Most scenarios intentionally rebuild from the root so they measure app-like
/// churn. The row-local scenarios are different: their product contract is that
/// one visible row changes per step. Driving those changes through row-local
/// state keeps the benchmark focused on retained presentation and semantics
/// rather than repeatedly rebuilding an otherwise stable 50-row widget list.
final class DrivenWebBenchmarkScenario extends StatefulWidget {
  const DrivenWebBenchmarkScenario({
    super.key,
    required this.scenario,
    required this.textInputController,
  });

  final WebBenchmarkScenario scenario;
  final TextEditingController textInputController;

  @override
  DrivenWebBenchmarkScenarioState createState() =>
      DrivenWebBenchmarkScenarioState();
}

final class DrivenWebBenchmarkScenarioState
    extends State<DrivenWebBenchmarkScenario> {
  var _step = 0;
  List<GlobalKey<_DrivenRowState>> _rowKeys = const [];

  /// Advances the scenario by one benchmark step.
  void advance(int step) {
    _step = step;
    switch (widget.scenario.kind) {
      case WebBenchmarkScenarioKind.dirtyRow:
        _advanceDirtyRow(step);
      case WebBenchmarkScenarioKind.singleDirtyCell:
        _advanceSingleDirtyCell(step);
      case WebBenchmarkScenarioKind.normal:
      case WebBenchmarkScenarioKind.noOp:
      case WebBenchmarkScenarioKind.fullFrameChurn:
      case WebBenchmarkScenarioKind.scrollRowChurn:
      case WebBenchmarkScenarioKind.scrollKeyed:
      case WebBenchmarkScenarioKind.cursorBlink:
      case WebBenchmarkScenarioKind.textInputBurst:
      case WebBenchmarkScenarioKind.resizeBurst:
        setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _ensureRowKeys();
  }

  @override
  void didUpdateWidget(covariant DrivenWebBenchmarkScenario oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scenario.kind != widget.scenario.kind ||
        oldWidget.scenario.rows != widget.scenario.rows) {
      _rowKeys = const [];
      _ensureRowKeys();
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureRowKeys();
    return switch (widget.scenario.kind) {
      WebBenchmarkScenarioKind.dirtyRow ||
      WebBenchmarkScenarioKind.singleDirtyCell => Column(
        children: [
          for (var row = 0; row < widget.scenario.rows; row++)
            _DrivenRow(
              key: _rowKeys[row],
              scenario: widget.scenario,
              row: row,
              initialStep: _step,
            ),
        ],
      ),
      _ => buildWebBenchmarkScenarioWidget(
        widget.scenario,
        step: _step,
        textInputController: widget.textInputController,
      ),
    };
  }

  bool get _usesRowDriver {
    return switch (widget.scenario.kind) {
      WebBenchmarkScenarioKind.dirtyRow ||
      WebBenchmarkScenarioKind.singleDirtyCell => true,
      _ => false,
    };
  }

  void _ensureRowKeys() {
    if (!_usesRowDriver) return;
    if (_rowKeys.length == widget.scenario.rows) return;
    _rowKeys = [
      for (var row = 0; row < widget.scenario.rows; row++)
        GlobalKey<_DrivenRowState>(),
    ];
  }

  void _advanceDirtyRow(int step) {
    if (widget.scenario.rows <= 0) return;
    final previousDirtyRow = (step - 1) % widget.scenario.rows;
    final nextDirtyRow = step % widget.scenario.rows;
    _rowKeys[previousDirtyRow].currentState?.advance(step);
    if (nextDirtyRow != previousDirtyRow) {
      _rowKeys[nextDirtyRow].currentState?.advance(step);
    }
  }

  void _advanceSingleDirtyCell(int step) {
    if (widget.scenario.rows <= 0) return;
    final dirtyRow = widget.scenario.rows ~/ 2;
    _rowKeys[dirtyRow].currentState?.advance(step);
  }
}

final class _DrivenRow extends StatefulWidget {
  const _DrivenRow({
    super.key,
    required this.scenario,
    required this.row,
    required this.initialStep,
  });

  final WebBenchmarkScenario scenario;
  final int row;
  final int initialStep;

  @override
  State<_DrivenRow> createState() => _DrivenRowState();
}

final class _DrivenRowState extends State<_DrivenRow> {
  late int _step;
  late bool _active;

  void advance(int step) {
    final nextActive = _activeFor(step);
    if (_active == nextActive && (!_active || _step == step)) return;
    setState(() {
      _active = nextActive;
      if (nextActive) _step = step;
    });
  }

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep;
    _active = _activeFor(widget.initialStep);
  }

  @override
  void didUpdateWidget(covariant _DrivenRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scenario.kind != widget.scenario.kind ||
        oldWidget.scenario.rows != widget.scenario.rows ||
        oldWidget.row != widget.row) {
      _step = widget.initialStep;
      _active = _activeFor(widget.initialStep);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Text(_line(_lineText(), widget.scenario.cols)),
    );
  }

  bool _activeFor(int step) {
    return switch (widget.scenario.kind) {
      WebBenchmarkScenarioKind.dirtyRow =>
        widget.row == step % widget.scenario.rows,
      WebBenchmarkScenarioKind.singleDirtyCell =>
        widget.row == widget.scenario.rows ~/ 2,
      _ => false,
    };
  }

  String _lineText() {
    return switch (widget.scenario.kind) {
      WebBenchmarkScenarioKind.singleDirtyCell =>
        'row ${_num(widget.row)} '
            'metric ${_active ? _step % 10 : 0} stable payload',
      WebBenchmarkScenarioKind.dirtyRow =>
        _active
            ? 'row ${_num(widget.row)} dirty step ${_num(_step)} '
                  'value ${_num(_step * 13)}'
            : 'row ${_num(widget.row)} stable payload stable payload stable',
      _ => 'row ${_num(widget.row)}',
    };
  }
}

/// Builds the Fleury widget tree for [scenario] at [step].
Widget buildWebBenchmarkScenarioWidget(
  WebBenchmarkScenario scenario, {
  required int step,
  TextEditingController? textInputController,
}) {
  return switch (scenario.kind) {
    WebBenchmarkScenarioKind.normal => _normalApp(scenario, step),
    WebBenchmarkScenarioKind.noOp => _dirtyRowGrid(scenario, 0),
    WebBenchmarkScenarioKind.singleDirtyCell => _singleDirtyCellGrid(
      scenario,
      step,
    ),
    WebBenchmarkScenarioKind.dirtyRow => _dirtyRowGrid(scenario, step),
    WebBenchmarkScenarioKind.fullFrameChurn => _fullFrameGrid(scenario, step),
    WebBenchmarkScenarioKind.scrollRowChurn => _scrollGrid(scenario, step),
    WebBenchmarkScenarioKind.scrollKeyed => _scrollKeyedGrid(scenario, step),
    WebBenchmarkScenarioKind.cursorBlink => _cursorBlink(
      scenario,
      step,
      textInputController,
    ),
    WebBenchmarkScenarioKind.textInputBurst => _textInputBurst(
      scenario,
      step,
      textInputController,
    ),
    WebBenchmarkScenarioKind.resizeBurst => _normalApp(scenario, step),
  };
}

Widget _normalApp(WebBenchmarkScenario scenario, int step) {
  final logRows = (scenario.rows - 7).clamp(1, scenario.rows);
  return Column(
    children: [
      Text(
        _line(
          'fleury web benchmark ${scenario.cols}x${scenario.rows} step $step',
          scenario.cols,
        ),
        style: const CellStyle(bold: true, foreground: AnsiColor(4)),
      ),
      Text(_line('status ready | queue ${(step * 7) % 31}', scenario.cols)),
      Text(_line('command deploy --target web --step $step', scenario.cols)),
      Text(_line('', scenario.cols)),
      for (var row = 0; row < logRows; row++)
        Text(_line(_logLine(row + step, step), scenario.cols)),
      Text(_line('', scenario.cols)),
      Text(
        _line(
          'footer latency budget 16.67ms | semantic presenter on',
          scenario.cols,
        ),
        style: const CellStyle(dim: true),
      ),
    ],
  );
}

Widget _singleDirtyCellGrid(WebBenchmarkScenario scenario, int step) {
  final dirtyRow = (scenario.rows / 2).floor();
  return Column(
    children: [
      for (var row = 0; row < scenario.rows; row++)
        RepaintBoundary(
          child: Text(
            _line(
              row == dirtyRow
                  ? 'row ${_num(row)} metric ${step % 10} stable payload'
                  : 'row ${_num(row)} metric 0 stable payload',
              scenario.cols,
            ),
          ),
        ),
    ],
  );
}

Widget _dirtyRowGrid(WebBenchmarkScenario scenario, int step) {
  final dirtyRow = step % scenario.rows;
  return Column(
    children: [
      for (var row = 0; row < scenario.rows; row++)
        RepaintBoundary(
          child: Text(
            _line(
              row == dirtyRow
                  ? 'row ${_num(row)} dirty step ${_num(step)} '
                        'value ${_num(step * 13)}'
                  : 'row ${_num(row)} stable payload stable payload stable',
              scenario.cols,
            ),
          ),
        ),
    ],
  );
}

Widget _fullFrameGrid(WebBenchmarkScenario scenario, int step) {
  return Column(
    children: [
      for (var row = 0; row < scenario.rows; row++)
        Text(_line(_fullFrameLine(row, step), scenario.cols)),
    ],
  );
}

Widget _scrollGrid(WebBenchmarkScenario scenario, int step) {
  return Column(
    children: [
      // A line's content is keyed by its ABSOLUTE log index only (step 0):
      // stepping the viewport shows the same lines one row higher, which is
      // what "Log viewport shifts by one row per frame" means. Content that
      // also mutates per step is the full-frame-churn scenario's job.
      for (var row = 0; row < scenario.rows; row++)
        Text(_line(_logLine(row + step, 0), scenario.cols)),
    ],
  );
}

Widget _scrollKeyedGrid(WebBenchmarkScenario scenario, int step) {
  return Column(
    children: [
      // The idiomatic scrolling log: each visible line is keyed by its
      // ABSOLUTE log index behind its own repaint boundary. Stepping the
      // viewport shifts which keys are visible; keyed reconciliation moves
      // the 49 surviving elements (their widgets compare equal, so no
      // rebuild) and the boundary caches blit at the new offsets instead of
      // re-walking paint.
      for (var row = 0; row < scenario.rows; row++)
        RepaintBoundary(
          key: ValueKey(row + step),
          child: Text(_line(_logLine(row + step, 0), scenario.cols)),
        ),
    ],
  );
}

Widget _cursorBlink(
  WebBenchmarkScenario scenario,
  int step,
  TextEditingController? controller,
) {
  final inputController = controller ?? TextEditingController(text: 'deploy');
  return Column(
    children: [
      Text(_line('cursor blink step $step', scenario.cols)),
      SizedBox(
        width: scenario.cols,
        child: TextInput(
          controller: inputController,
          autofocus: true,
          enableBlink: false,
          cursorStyle: CellStyle(inverse: step.isEven),
        ),
      ),
      for (var row = 2; row < scenario.rows; row++)
        Text(_line('stable row ${_num(row)}', scenario.cols)),
    ],
  );
}

Widget _textInputBurst(
  WebBenchmarkScenario scenario,
  int step,
  TextEditingController? controller,
) {
  final inputController = controller ?? TextEditingController();
  return Column(
    children: [
      Text(_line('text input burst step $step', scenario.cols)),
      SizedBox(
        width: scenario.cols,
        child: TextInput(
          controller: inputController,
          autofocus: true,
          enableBlink: false,
          placeholder: 'type...',
        ),
      ),
      Text(_line('text length ${inputController.text.length}', scenario.cols)),
      for (var row = 3; row < scenario.rows; row++)
        Text(_line(_logLine(row + step, step), scenario.cols)),
    ],
  );
}

String _fullFrameLine(int row, int step) {
  final seed = row * 97 + step * 131;
  return 'row ${_num(row)} step ${_num(step)} '
      'cpu ${seed % 100} mem ${(seed * 3) % 1000} '
      'trace ${(seed * 17).toRadixString(16)} '
      'payload ${_token(seed)} ${_token(seed + 1)} ${_token(seed + 2)}';
}

String _logLine(int row, int step) {
  final seed = row * 53 + step * 11;
  return '[${_num(row)}] service-${seed % 9} '
      'request=${(seed * 19).toRadixString(16)} '
      'status=${seed.isEven ? 'ok' : 'wait'} '
      'queue=${seed % 41} retries=${seed % 3}';
}

String _token(int value) => (value * 2654435761 & 0xfffffff).toRadixString(16);

String _num(int value) => value.toString().padLeft(3, '0');

String _line(String text, int width) {
  if (width <= 0) return '';
  if (text.length == width) return text;
  if (text.length > width) return text.substring(0, width);
  return text.padRight(width);
}
