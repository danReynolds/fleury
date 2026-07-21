// A minimal three-pane chat layout that pressure-tests every widget
// added to fleury so far:
//
//   - Container + BoxBorder draw the visible pane boundaries.
//   - ListView (with external FocusNode) drives the channel sidebar
//     and the message log.
//   - TextInput (with external FocusNode) is the composer at the
//     bottom.
//   - FocusTraversalGroup wraps the panes so arrow chords that escape
//     a focused widget (left/right from a vertical ListView; up at
//     the top of the composer-adjacent list) move focus directly to
//     the spatial neighbor — no Tab cycling needed.
//   - A static hint line surfaces the bindings at the bottom. (The
//     auto-discovering KeyHintBar lives in fleury_widgets.)
//   - Wrapping Text inside ListView lets long messages span multiple
//     rows without manual line management.
//
// How to run (from packages/fleury):
//
//   dart pub get
//   dart run example/chat_demo.dart
//
//   Left / Right  move focus between sidebar / messages
//   Up / Down     move the cursor within the focused list,
//                 or escape to the pane above/below at boundaries
//   Enter         in sidebar: pick a channel; in composer: send
//   Ctrl+C        exit

import 'package:fleury/fleury.dart';

Future<void> main() =>
    runApp(const FleuryApp(title: 'Chat demo', home: ChatApp()));
// Ctrl+C is a framework-level exit guard in runApp — apps don't need
// to wire it themselves.

class ChatApp extends StatefulWidget {
  const ChatApp({super.key});

  @override
  State<ChatApp> createState() => _ChatAppState();
}

class _ChatAppState extends State<ChatApp> {
  final _sidebarFocus = FocusNode(debugLabel: 'sidebar');
  final _messagesFocus = FocusNode(debugLabel: 'messages');
  final _composerFocus = FocusNode(debugLabel: 'composer');
  final _composerCtrl = TextEditingController();

  final List<String> _channels = [
    '#family',
    '#work',
    '#climbing-crew',
    '#old-roommates',
  ];

  // Per-channel message log. New messages append.
  final Map<int, List<String>> _messages = {
    0: ['mom: dont forget grandmas birthday'],
    1: ['carol: standup is moved to 11', 'you: ack'],
    2: [
      'jess: should we go saturday? weather looks decent',
      'dan: yeah im in. ill bring the rope',
      'you: nice, ill meet you at the trailhead at 8',
    ],
    3: ['sam: anyone heard from alex lately?'],
  };

  int _activeChannel = 2;

  @override
  void dispose() {
    _sidebarFocus.dispose();
    _messagesFocus.dispose();
    _composerFocus.dispose();
    _composerCtrl.dispose();
    super.dispose();
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _messages.putIfAbsent(_activeChannel, () => <String>[]);
      _messages[_activeChannel]!.add('you: $text');
      _composerCtrl.clear();
    });
  }

  // Focus.of(context) participates in InheritedNotifier dependency
  // tracking, so this build runs on every focus change automatically —
  // no manual listener needed.
  bool _isFocused(BuildContext context, FocusNode node) =>
      Focus.of(context).focusedNode == node;

  BoxBorder _borderFor(BuildContext context, FocusNode node) => BoxBorder(
    style: BorderStyle.rounded,
    cellStyle: CellStyle(
      foreground: AnsiColor(_isFocused(context, node) ? 14 : 8),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyCode.f1,
          label: 'help',
          onTrigger: () => _showHelp(context),
        ),
        KeyBinding(
          KeySequence.ctrl.k,
          label: 'switch channel',
          onTrigger: () => _showCommandPalette(context),
        ),
      ],
      child: FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 22, child: _buildSidebar(context)),
                  Expanded(child: _buildMessagePane(context)),
                ],
              ),
            ),
            _buildComposer(context),
            const Text('[F1] help  [Ctrl+K] switch channel', softWrap: false),
          ],
        ),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    // present() supplies no chrome — frame the dialog yourself.
    context.present<void>(
      const Container(
        border: BoxBorder(style: BorderStyle.rounded),
        padding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: SizedBox(
          width: 44,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ' Keyboard shortcuts',
                style: CellStyle(bold: true, foreground: AnsiColor(14)),
              ),
              Text(''),
              Text(' F1          this help'),
              Text(' Ctrl+K      command palette'),
              Text(' ←/→ ↑/↓    navigate panes / items'),
              Text(' Enter       pick channel / send message'),
              Text(' Esc         dismiss dialog / cancel'),
              Text(' Ctrl+C      exit'),
              Text(''),
              Text(' Esc to close', style: CellStyle(dim: true)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCommandPalette(BuildContext context) async {
    final pickedIndex = await context.present<int>(
      Container(
        border: const BoxBorder(style: BorderStyle.rounded),
        child: SizedBox(width: 40, child: _CommandPalette(channels: _channels)),
      ),
      alignment: Alignment.topCenter,
    );
    if (pickedIndex != null && mounted) {
      setState(() => _activeChannel = pickedIndex);
    }
  }

  Widget _buildSidebar(BuildContext context) {
    return Container(
      border: _borderFor(context, _sidebarFocus),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: ListView.builder(
        focusNode: _sidebarFocus,
        autofocus: true,
        itemCount: _channels.length,
        itemBuilder: (ctx, index, selected) {
          final isActive = index == _activeChannel;
          final prefix = isActive ? '* ' : '  ';
          final style = selected && _isFocused(context, _sidebarFocus)
              ? const CellStyle(inverse: true)
              : (isActive ? const CellStyle(bold: true) : CellStyle.empty);
          return Text(
            '$prefix${_channels[index]}',
            style: style,
            softWrap: false,
          );
        },
        onActivate: (index) => setState(() => _activeChannel = index),
      ),
    );
  }

  Widget _buildMessagePane(BuildContext context) {
    final messages = _messages[_activeChannel] ?? const <String>[];
    return Container(
      border: _borderFor(context, _messagesFocus),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: channel name + a tiny "live" spinner that
          // demonstrates the discrete animation lane integrated
          // into a real layout.
          Row(
            children: [
              Expanded(
                child: Text(
                  ' ${_channels[_activeChannel]} ',
                  style: const CellStyle(bold: true),
                ),
              ),
              const Spinner(),
            ],
          ),
          Expanded(
            child: ListView.builder(
              focusNode: _messagesFocus,
              // Up at row 0 / down at the last row escapes to
              // neighboring panes via the FocusTraversalGroup above.
              edgeBehavior: EdgeBehavior.bubble,
              itemCount: messages.length,
              itemBuilder: (ctx, index, selected) {
                final style = selected && _isFocused(context, _messagesFocus)
                    ? const CellStyle(inverse: true)
                    : CellStyle.empty;
                return Text(messages[index], style: style);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(BuildContext context) {
    return Container(
      border: _borderFor(context, _composerFocus),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: TextInput(
        focusNode: _composerFocus,
        controller: _composerCtrl,
        onSubmit: _send,
      ),
    );
  }
}

/// Channel-switching command palette. Top-anchored, filtered as the
/// user types, Enter picks. Demonstrates a stateful modal with a
/// TextInput + ListView talking to each other through local state,
/// closing via `context.pop(channelIndex)`.
class _CommandPalette extends StatefulWidget {
  const _CommandPalette({required this.channels});
  final List<String> channels;

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final _query = TextEditingController();
  final _list = ListController(selectedIndex: 0);
  final _inputFocus = FocusNode(debugLabel: 'palette-input');
  late List<int> _matches;

  @override
  void initState() {
    super.initState();
    _matches = List<int>.generate(widget.channels.length, (i) => i);
    _query.addListener(_recompute);
    // The modal chrome's autofocus claimed focus during this frame's
    // mount; schedule a follow-up to move it into the TextInput so
    // the user can start typing immediately. We can't call
    // requestFocus from initState because _inputFocus isn't attached
    // to a manager until the Focus widget below first builds.
    Future<void>.microtask(() {
      if (mounted) _inputFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _query.removeListener(_recompute);
    _query.dispose();
    _list.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _recompute() {
    final q = _query.text.toLowerCase();
    setState(() {
      _matches = [
        for (var i = 0; i < widget.channels.length; i++)
          if (q.isEmpty || widget.channels[i].toLowerCase().contains(q)) i,
      ];
      // Clamp the highlight so it doesn't dangle past the matches.
      if (_list.selectedIndex == null ||
          _list.selectedIndex! >= _matches.length) {
        _list.selectedIndex = _matches.isEmpty ? null : 0;
      }
    });
  }

  void _commit(BuildContext context) {
    final i = _list.selectedIndex;
    if (i == null || i >= _matches.length) return;
    context.pop(_matches[i]);
  }

  void _move(int delta) {
    final cur = _list.selectedIndex;
    if (cur == null || _matches.isEmpty) return;
    _list.selectedIndex = (cur + delta).clamp(0, _matches.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    // TextInput owns focus while the palette is up. Up/Down bubble
    // out of it (TextInput only consumes Left/Right for cursor
    // movement); this KeyBindings catches them and routes them to
    // the filtered-match list. Enter is handled by TextInput.onSubmit
    // which commits the current highlight.
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyCode.arrowUp,
          onTrigger: () => _move(-1),
          hideFromHintBar: true,
        ),
        KeyBinding(
          KeyCode.arrowDown,
          onTrigger: () => _move(1),
          hideFromHintBar: true,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextInput(
            focusNode: _inputFocus,
            controller: _query,
            onSubmit: (_) => _commit(context),
          ),
          const Text(''),
          SizedBox(
            height: 8,
            child: ListView.builder(
              controller: _list,
              itemCount: _matches.length,
              itemBuilder: (_, row, selected) {
                final channelIndex = _matches[row];
                return Text(
                  ' ${widget.channels[channelIndex]}',
                  style: selected
                      ? const CellStyle(inverse: true)
                      : CellStyle.empty,
                  softWrap: false,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
