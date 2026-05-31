import 'package:fleury/fleury.dart';

/// One entry in a [CommandPalette].
class Command {
  const Command({
    required this.label,
    required this.onInvoke,
    this.description,
  });

  /// Text shown (and matched against the query).
  final String label;

  /// Optional secondary text shown after the label.
  final String? description;

  /// Run when the command is chosen.
  final void Function() onInvoke;
}

bool _isSubsequence(String needle, String hay) {
  var i = 0;
  for (var j = 0; j < hay.length && i < needle.length; j++) {
    if (hay[j] == needle[i]) i++;
  }
  return i == needle.length;
}

List<Command> _match(List<Command> all, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return all;
  return [
    for (final c in all)
      if (_isSubsequence(q, c.label.toLowerCase())) c,
  ];
}

/// A fuzzy command palette: a filter input above a live-filtered list.
/// Type to narrow (case-insensitive subsequence match), Up/Down to move,
/// Enter to run the highlighted command. It is plain modal content — show
/// it like any modal — `present` it — and it closes itself on invoke:
///
/// ```dart
/// context.present<void>(CommandPalette(commands: [
///   Command(label: 'Open File', onInvoke: openFile),
///   Command(label: 'Quit', onInvoke: quit),
/// ]));
/// ```
///
/// (Esc dismissal comes from the modal route; the palette adds nothing
/// there.) Built on core primitives — `TextInput` for the query,
/// `ListView` for the results — so there's no bespoke "show" entry point.
class CommandPalette extends StatefulWidget {
  const CommandPalette({
    super.key,
    required this.commands,
    this.placeholder = 'Search commands…',
    this.width = 50,
    this.maxVisible = 8,
  });

  final List<Command> commands;
  final String placeholder;
  final int width;
  final int maxVisible;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _query = TextEditingController();
  final _list = ListController(selectedIndex: 0);
  late List<Command> _filtered = widget.commands;

  @override
  void initState() {
    super.initState();
    _query.addListener(_onQuery);
  }

  void _onQuery() {
    setState(() {
      _filtered = _match(widget.commands, _query.text);
      _list.selectedIndex = _filtered.isEmpty ? null : 0;
    });
  }

  void _move(int delta) {
    if (_filtered.isEmpty) return;
    final current = _list.selectedIndex ?? 0;
    _list.selectedIndex = (current + delta).clamp(0, _filtered.length - 1);
  }

  void _invoke() {
    final i = _list.selectedIndex;
    if (i == null || i < 0 || i >= _filtered.length) return;
    final command = _filtered[i];
    Navigator.of(context).pop();
    command.onInvoke();
  }

  @override
  void dispose() {
    _query.removeListener(_onQuery);
    _query.dispose();
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _filtered.isEmpty
        ? 1
        : (_filtered.length > widget.maxVisible
              ? widget.maxVisible
              : _filtered.length);
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyChord.key(KeyCode.arrowUp),
          onEvent: (_) {
            _move(-1);
          },
          hideFromHintBar: true,
        ),
        KeyBinding(
          KeyChord.key(KeyCode.arrowDown),
          onEvent: (_) {
            _move(1);
          },
          hideFromHintBar: true,
        ),
      ],
      // The palette owns its own frame — present() supplies no chrome.
      child: Container(
        border: BoxBorder(style: theme.borderStyle),
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: SizedBox(
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextInput(
                controller: _query,
                autofocus: true,
                onSubmit: (_) => _invoke(),
              ),
              const SizedBox(height: 1),
              SizedBox(
                height: visible,
                child: _filtered.isEmpty
                    ? Text(
                        _query.text.isEmpty
                            ? widget.placeholder
                            : 'No matching commands',
                      )
                    : ListView.builder(
                        controller: _list,
                        itemCount: _filtered.length,
                        itemBuilder: (_, i, selected) {
                          final command = _filtered[i];
                          final desc = command.description;
                          final label = desc == null
                              ? command.label
                              : '${command.label}  $desc';
                          return Text(
                            '${selected ? '› ' : '  '}$label',
                            style: selected
                                ? theme.selectionStyle
                                : CellStyle.empty,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
