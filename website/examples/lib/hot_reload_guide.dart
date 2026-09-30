import 'package:fleury/fleury_core.dart';

class HotReloadNotes extends StatefulWidget {
  const HotReloadNotes({super.key, required this.heading});

  final String heading;

  @override
  State<HotReloadNotes> createState() => _HotReloadNotesState();
}

class _HotReloadNotesState extends State<HotReloadNotes> {
  static const _notes = ['Inbox', 'Release notes', 'Ideas'];
  final _drafts = List.generate(_notes.length, (_) => TextEditingController());
  final _draftFocus = FocusNode();
  final _list = ListController();
  var _selected = 0;

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    _draftFocus.dispose();
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const headingStyle = CellStyle(bold: true);
    return FocusTraversalGroup(
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.heading, style: headingStyle),
            const SizedBox(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 16,
                    child: ListView.builder(
                      controller: _list,
                      autofocus: true,
                      itemCount: _notes.length,
                      onSelect: (index) {
                        setState(() => _selected = index);
                        _draftFocus.requestFocus();
                      },
                      itemBuilder: (_, index, highlighted) => Text(
                        '${_selected == index ? '›' : ' '} ${_notes[index]}',
                        style: highlighted
                            ? theme.selectionStyle
                            : theme.textStyle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(_notes[_selected], style: theme.mutedStyle),
                        const SizedBox(height: 1),
                        TextArea(
                          controller: _drafts[_selected],
                          focusNode: _draftFocus,
                          placeholder: 'Write a draft…',
                          semanticLabel: 'Draft',
                          minLines: 3,
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
