// Core-only application composition. No storage or companion packages.
// Run from packages/fleury: dart run example/core_editor.dart
import 'package:fleury/fleury.dart';

void main() => runApp(const CoreEditor());

class CoreEditor extends StatefulWidget {
  const CoreEditor({super.key});

  @override
  State<CoreEditor> createState() => _CoreEditorState();
}

class _CoreEditorState extends State<CoreEditor> {
  final _items = <String, String>{'Greeting': 'Hello', 'Language': 'Dart'};
  final _search = TextEditingController();
  final _draft = TextEditingController();
  final _searchFocus = FocusNode();
  final _listFocus = FocusNode();
  final _list = ListController();
  String? _editing;
  bool _confirm = false;
  String _notice = '';

  List<String> get _visible => _items.keys
      .where((name) => name.toLowerCase().contains(_search.text.toLowerCase()))
      .toList();

  void _open(int index) => setState(() {
    _editing = _visible[index];
    _draft.text = _items[_editing]!;
  });

  void _close() => setState(() {
    _editing = null;
    _confirm = false;
    _draft.text = '';
  });

  void _save() {
    _items[_editing!] = _draft.text;
    _notice = 'Saved';
    _close();
  }

  @override
  void dispose() {
    _search.dispose();
    _draft.dispose();
    _searchFocus.dispose();
    _listFocus.dispose();
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusTraversalGroup(
      child: Center(
        child: ConstrainedBox(
          maxWidth: 56,
          maxHeight: 18,
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: _editing == null ? _browse(theme) : _editor(theme),
          ),
        ),
      ),
    );
  }

  Widget _browse(ThemeData theme) {
    final names = _visible;
    return KeyBindings(
      bindings: [
        KeyBinding(.up, onTrigger: (_) => _searchFocus.requestFocus()),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Notes', style: const CellStyle(bold: true)),
          KeyBindings(
            bindings: [
              KeyBinding(
                .down,
                onTrigger: (_) {
                  if (names.isNotEmpty) _listFocus.requestFocus();
                },
              ),
            ],
            child: TextInput(
              controller: _search,
              focusNode: _searchFocus,
              autofocus: true,
              placeholder: 'Find a note…',
              semanticLabel: 'Search',
              onChanged: (_) => setState(() => _list.selectedIndex = 0),
            ),
          ),
          const SizedBox(height: 1),
          Expanded(
            child: names.isEmpty
                ? const Text('No matches. Change or clear the search.')
                : ListView.separated(
                    controller: _list,
                    focusNode: _listFocus,
                    itemCount: names.length,
                    onActivate: _open,
                    itemBuilder: (_, index, selected) => Text(
                      names[index],
                      style: selected ? theme.selectionStyle : CellStyle.none,
                    ),
                    separatorBuilder: (_, index) => const SizedBox(height: 1),
                  ),
          ),
          if (_notice.isNotEmpty)
            Text(
              _notice,
              style: CellStyle(foreground: theme.colorScheme.success),
            ),
          Text(
            '↑↓ move · Enter edit · Tab focus · Ctrl+C quit',
            style: theme.mutedStyle,
          ),
        ],
      ),
    );
  }

  Widget _editor(ThemeData theme) {
    if (_confirm) {
      return KeyBindings(
        bindings: [
          KeyBinding(
            .escape,
            onTrigger: (_) => setState(() => _confirm = false),
          ),
        ],
        child: Container(
          border: const BoxBorder(),
          padding: const EdgeInsets.all(1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Delete $_editing?', style: const CellStyle(bold: true)),
              const SizedBox(height: 1),
              Wrap(
                spacing: 2,
                children: [
                  Button(
                    label: 'Cancel',
                    autofocus: true,
                    onPressed: () => setState(() => _confirm = false),
                  ),
                  Button(
                    label: 'Delete',
                    variant: ButtonVariant.error,
                    onPressed: () {
                      _items.remove(_editing);
                      _notice = 'Deleted';
                      _close();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return KeyBindings(
      bindings: [
        KeyBinding(.ctrl.s, onTrigger: (_) => _save()),
        KeyBinding(.escape, onTrigger: (_) => _close()),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_editing!, style: const CellStyle(bold: true)),
          const SizedBox(height: 1),
          TextInput(
            controller: _draft,
            autofocus: true,
            semanticLabel: 'Value',
            // This small demo accepts paste synchronously. Production editors
            // with unbounded documents should keep the default chunked policy.
            pastePolicy: const TextPastePolicy.immediate(),
            onSubmit: (_) => _save(),
          ),
          const SizedBox(height: 1),
          Wrap(
            spacing: 2,
            children: [
              Button(
                label: 'Ctrl+S Save',
                variant: ButtonVariant.primary,
                onPressed: _save,
              ),
              Button(label: 'Cancel', onPressed: _close),
              Button(
                label: 'Delete…',
                variant: ButtonVariant.error,
                onPressed: () => setState(() => _confirm = true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
