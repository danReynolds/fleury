import 'package:fleury/fleury_core.dart';

import 'scaffold.dart';

/// A coding-agent TUI styled after Claude Code / Gemini CLI: a full-width
/// conversation transcript where the agent's turn streams in as prose, tool
/// calls (`⏺ Read(...)` with `⎿` results), a live todo list, and a colored
/// diff — with a bordered prompt box and a context/status line at the bottom.
///
/// The session is scripted and replayable (no live LLM backend) so it runs
/// identically in a terminal or in the browser over `fleury serve`. Press Enter
/// on the prompt to advance to the next scripted turn; replies stream in block
/// by block.
class AgentApp extends StatelessWidget {
  const AgentApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const SampleScaffold(child: _AgentBody());
}

class _AgentBody extends StatefulWidget {
  const _AgentBody();

  @override
  State<_AgentBody> createState() => _AgentBodyState();
}

class _AgentBodyState extends State<_AgentBody>
    with SingleTickerProviderStateMixin {
  final ListController _scroll = ListController(pinToBottom: true);
  final TextEditingController _input = TextEditingController();
  final List<_Block> _blocks = <_Block>[];
  final List<_Block> _pending = <_Block>[];

  Ticker? _ticker;
  int _lastRevealMs = 0;
  int _turnIndex = 0;
  int _inputTokens = 9200;
  int _outputTokens = 3100;

  static const int _revealMs = 420;
  static const int _contextLimit = 200000;

  @override
  void initState() {
    super.initState();
    // Seed the opening turn so a headless render shows a populated transcript;
    // the reply streams in via the ticker once a TuiBinding exists.
    _startTurn(auto: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ticker == null && TuiBinding.maybeOf(context) != null) {
      _ticker = createTicker(_onTick)..start();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  bool get _working => _pending.isNotEmpty;
  int get _contextUsed => _inputTokens + _outputTokens;

  void _onTick(Duration elapsed) {
    if (_pending.isEmpty) return;
    if (elapsed.inMilliseconds - _lastRevealMs < _revealMs) return;
    _lastRevealMs = elapsed.inMilliseconds;
    setState(_revealNext);
  }

  void _revealNext() {
    final block = _pending.removeAt(0);
    _blocks.add(block);
    _outputTokens += block.weight;
  }

  void _onSubmit(String text) {
    if (_working) return; // let the current reply finish first
    final typed = text.trim();
    _input.clear();
    _startTurn(typedPrompt: typed.isEmpty ? null : typed);
  }

  void _startTurn({String? typedPrompt, bool auto = false}) {
    final turn =
        _turnIndex < _script.length ? _script[_turnIndex] : _fallbackTurn;
    _turnIndex++;
    final prompt = typedPrompt ?? turn.prompt;
    setState(() {
      _blocks.add(_UserBlock(prompt));
      _inputTokens += prompt.length ~/ 3 + 40;
      _pending.addAll(turn.steps);
      // Reveal the first reply line immediately on the synchronous seed so the
      // transcript isn't just a lone user prompt before the ticker starts.
      if (auto && _pending.isNotEmpty) _revealNext();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _banner(theme),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            itemCount: _blocks.length,
            itemBuilder: (context, i, selected) =>
                _blocks[i].build(context, theme),
          ),
        ),
        const SizedBox(height: 1),
        _inputBox(theme),
        _statusLine(theme),
      ],
    );
  }

  Widget _banner(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('✻ ',
                style:
                    CellStyle(foreground: theme.colorScheme.primary, bold: true)),
            Text('Fleury Code',
                style: CellStyle(
                    bold: true, foreground: theme.colorScheme.foreground)),
            const Expanded(child: SizedBox.shrink()),
            Text('~/my-app',
                style: CellStyle(foreground: theme.colorScheme.info)),
          ],
        ),
        Text('  scripted demo · press Enter to advance the session',
            style: theme.mutedStyle),
      ],
    );
  }

  Widget _inputBox(ThemeData theme) {
    return Container(
      border: BoxBorder(
        style: BorderStyle.rounded,
        cellStyle: _working
            ? theme.mutedStyle
            : CellStyle(foreground: theme.colorScheme.primary),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Row(
        children: <Widget>[
          Text('› ',
              style:
                  CellStyle(foreground: theme.colorScheme.primary, bold: true)),
          Expanded(
            child: TextInput(
              controller: _input,
              autofocus: true,
              placeholder: _working
                  ? 'streaming reply…'
                  : 'Ask Fleury to change the code, then press Enter',
              onSubmit: _onSubmit,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusLine(ThemeData theme) {
    final pct = (_contextUsed / _contextLimit * 100).toStringAsFixed(0);
    final usedK = (_contextUsed / 1000).toStringAsFixed(1);
    return Row(
      children: <Widget>[
        Text(' claude-opus-4-8', style: theme.mutedStyle),
        Text('  ·  ${usedK}k/200k context ($pct%)', style: theme.mutedStyle),
        const Expanded(child: SizedBox.shrink()),
        Text(
          _working ? '⋯ working   ' : '⏵ ready   ',
          style: CellStyle(
              foreground: _working
                  ? theme.colorScheme.warning
                  : theme.colorScheme.success),
        ),
        Text('q quit', style: theme.mutedStyle),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Conversation blocks — each renders one entry in the Claude-Code-style flow.
// ---------------------------------------------------------------------------

sealed class _Block {
  /// Output-token weight added to the running context meter when revealed.
  int get weight;
  Widget build(BuildContext context, ThemeData theme);
}

/// `⏺ ` accent bullet + a body that wraps with a hanging indent.
Widget _bulleted(ThemeData theme, String body,
    {CellStyle style = CellStyle.empty}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text('⏺ ', style: CellStyle(foreground: theme.colorScheme.primary)),
      Expanded(child: Text(body, style: style)),
    ],
  );
}

class _UserBlock extends _Block {
  _UserBlock(this.text);
  final String text;

  @override
  int get weight => 0;

  @override
  Widget build(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('› ',
              style:
                  CellStyle(foreground: theme.colorScheme.primary, bold: true)),
          Expanded(
            child: Text(text,
                style: CellStyle(
                    bold: true, foreground: theme.colorScheme.foreground)),
          ),
        ],
      ),
    );
  }
}

class _SayBlock extends _Block {
  _SayBlock(this.text);
  final String text;

  @override
  int get weight => text.length ~/ 3 + 20;

  @override
  Widget build(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: _bulleted(theme, text),
    );
  }
}

class _ToolBlock extends _Block {
  _ToolBlock(this.title, {this.result});
  final String title;
  final String? result;

  @override
  int get weight => 28;

  @override
  Widget build(BuildContext context, ThemeData theme) {
    final lines =
        result == null ? const <String>[] : result!.split('\n');
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _bulleted(theme, title,
              style: CellStyle(foreground: theme.colorScheme.foreground)),
          for (var i = 0; i < lines.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(i == 0 ? '  ⎿  ' : '     ', style: theme.mutedStyle),
                Expanded(child: Text(lines[i], style: theme.mutedStyle)),
              ],
            ),
        ],
      ),
    );
  }
}

enum _Todo { done, active, pending }

class _TodoBlock extends _Block {
  _TodoBlock(this.items);
  final List<(_Todo, String)> items;

  @override
  int get weight => 14;

  @override
  Widget build(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _bulleted(theme, 'Update Todos',
              style: CellStyle(foreground: theme.colorScheme.foreground)),
          for (var i = 0; i < items.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(i == 0 ? '  ⎿  ' : '     ', style: theme.mutedStyle),
                Text('${_glyph(items[i].$1)} ',
                    style: _todoStyle(theme, items[i].$1)),
                Expanded(
                    child: Text(items[i].$2,
                        style: _todoStyle(theme, items[i].$1))),
              ],
            ),
        ],
      ),
    );
  }

  static String _glyph(_Todo t) => switch (t) {
        _Todo.done => '☒',
        _Todo.active => '▶',
        _Todo.pending => '☐',
      };

  static CellStyle _todoStyle(ThemeData theme, _Todo t) => switch (t) {
        _Todo.done => theme.mutedStyle,
        _Todo.active =>
          CellStyle(foreground: theme.colorScheme.primary, bold: true),
        _Todo.pending => CellStyle(foreground: theme.colorScheme.foreground),
      };
}

enum _DiffKind { add, del, ctx }

class _Diff {
  const _Diff(this.gutter, this.kind, this.text);
  final String gutter;
  final _DiffKind kind;
  final String text;
}

class _DiffBlock extends _Block {
  _DiffBlock(this.title, this.lines, this.summary);
  final String title;
  final List<_Diff> lines;
  final String summary;

  @override
  int get weight => 42;

  @override
  Widget build(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _bulleted(theme, title,
              style: CellStyle(foreground: theme.colorScheme.foreground)),
          Padding(
            padding: const EdgeInsets.only(left: 5, top: 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[for (final d in lines) _diffRow(theme, d)],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('  ⎿  ', style: theme.mutedStyle),
              Expanded(child: Text(summary, style: theme.mutedStyle)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _diffRow(ThemeData theme, _Diff d) {
    final (sign, style) = switch (d.kind) {
      _DiffKind.add => ('+', CellStyle(foreground: theme.colorScheme.success)),
      _DiffKind.del => ('-', CellStyle(foreground: theme.colorScheme.error)),
      _DiffKind.ctx => (' ', theme.mutedStyle),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(d.gutter.padLeft(3), style: theme.mutedStyle),
        Text(' $sign ', style: style),
        Expanded(child: Text(d.text, style: style)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Scripted conversation.
// ---------------------------------------------------------------------------

class _Turn {
  const _Turn(this.prompt, this.steps);
  final String prompt;
  final List<_Block> steps;
}

final List<_Turn> _script = <_Turn>[
  _Turn(
    'Add a --version flag to the CLI that prints the package version.',
    <_Block>[
      _SayBlock(
          "I'll add a `--version` flag. Let me see how the CLI parses arguments "
          'and where the version comes from before touching anything.'),
      _TodoBlock(const <(_Todo, String)>[
        (_Todo.active, 'Inspect CLI argument parsing'),
        (_Todo.pending, 'Read the version from pubspec'),
        (_Todo.pending, 'Handle the --version flag'),
        (_Todo.pending, 'Add a regression test'),
        (_Todo.pending, 'Run the test suite'),
      ]),
      _ToolBlock('Read(lib/main.dart)', result: 'Read 48 lines'),
      _ToolBlock('Read(pubspec.yaml)',
          result: 'Read 14 lines · version: 1.4.0'),
      _SayBlock(
          'Found it — `main()` switches on `args[0]`, and the version lives in '
          'pubspec.yaml. I\'ll read it at build time and intercept `--version` '
          'before the switch so it works no matter the subcommand.'),
      _DiffBlock(
        'Update(lib/main.dart)',
        const <_Diff>[
          _Diff('1', _DiffKind.ctx, "import 'dart:io';"),
          _Diff('2', _DiffKind.add, "import 'src/version.dart';"),
          _Diff('', _DiffKind.ctx, ''),
          _Diff('8', _DiffKind.ctx, 'Future<void> main(List<String> args) {'),
          _Diff('9', _DiffKind.add, "  if (args.contains('--version')) {"),
          _Diff('10', _DiffKind.add, '    stdout.writeln(packageVersion);'),
          _Diff('11', _DiffKind.add, '    return;'),
          _Diff('12', _DiffKind.add, '  }'),
        ],
        'Updated lib/main.dart with 6 additions',
      ),
      _TodoBlock(const <(_Todo, String)>[
        (_Todo.done, 'Inspect CLI argument parsing'),
        (_Todo.done, 'Read the version from pubspec'),
        (_Todo.done, 'Handle the --version flag'),
        (_Todo.active, 'Add a regression test'),
        (_Todo.pending, 'Run the test suite'),
      ]),
      _SayBlock(
          'Done — `my-app --version` now prints `1.4.0`. Want me to add a test '
          'to lock it in?'),
    ],
  ),
  _Turn(
    'Yes, add a test and run it.',
    <_Block>[
      _SayBlock(
          'Adding a test that runs the CLI with `--version`, captures stdout, '
          'and asserts the version string.'),
      _ToolBlock('Write(test/version_test.dart)', result: 'Wrote 18 lines'),
      _ToolBlock('Bash(dart test ./test)',
          result: 'Running tests…\n00:01 +13: All tests passed!'),
      _TodoBlock(const <(_Todo, String)>[
        (_Todo.done, 'Inspect CLI argument parsing'),
        (_Todo.done, 'Read the version from pubspec'),
        (_Todo.done, 'Handle the --version flag'),
        (_Todo.done, 'Add a regression test'),
        (_Todo.done, 'Run the test suite'),
      ]),
      _SayBlock(
          'All 13 tests pass, including the new `--version` test. The flag is '
          'implemented, wired before the subcommand switch, and covered. ✓'),
    ],
  ),
];

final _Turn _fallbackTurn = _Turn(
  '(scripted demo — type anything)',
  <_Block>[
    _SayBlock(
        "That's the end of this scripted demo. In a real session this is where "
        "I'd plan, edit, and verify your next request — streaming the work as "
        'it happens.'),
  ],
);
