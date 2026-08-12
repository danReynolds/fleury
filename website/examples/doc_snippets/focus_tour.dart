// Compile-checked source behind the Focus management guide.

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

/// A compact focus explorer. [FleuryApp] supplies traversal for the screen.
class FocusExplorerExample extends StatefulWidget {
  const FocusExplorerExample({super.key});

  @override
  State<FocusExplorerExample> createState() => _FocusExplorerExampleState();
}

class _FocusExplorerExampleState extends State<FocusExplorerExample> {
  String _activeRegion = 'Files';
  String _lastAction = 'New file is focused';

  void _markRegion(String name, bool focused) {
    if (!focused || _activeRegion == name) return;
    setState(() => _activeRegion = name);
  }

  void _act(String action) => setState(() => _lastAction = action);

  Future<void> _openDialog() async {
    setState(() {
      _activeRegion = 'Dialog';
      _lastAction = 'Dialog focus is trapped';
    });
    final published = await Navigator.of(
      context,
    ).present<bool>(const _PublishDialog(), transition: RouteTransition.none);
    if (!mounted) return;
    setState(() {
      _activeRegion = 'Preview';
      _lastAction = published == true ? 'Published' : 'Publish canceled';
    });
  }

  Widget _actionButton({
    required String label,
    required void Function() onPressed,
    bool autofocus = false,
  }) => SizedBox(
    width: 14,
    child: Button(label: label, autofocus: autofocus, onPressed: onPressed),
  );

  Widget _region({required String name, required List<Widget> controls}) =>
      Panel(
        title: name,
        focused: _activeRegion == name,
        child: FocusDetector(
          onFocusChange: (focused) => _markRegion(name, focused),
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: controls,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'AUTOMATIC · TAB READS · ARROWS MOVE',
        style: CellStyle(bold: true),
      ),
      Text('active: $_activeRegion', style: const CellStyle(dim: true)),
      const SizedBox(height: 1),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _region(
                name: 'Files',
                controls: [
                  _actionButton(
                    label: 'New file',
                    autofocus: true,
                    onPressed: () => _act('Created a file'),
                  ),
                  _actionButton(
                    label: 'Open file',
                    onPressed: () => _act('Opened a file'),
                  ),
                  _actionButton(
                    label: 'Settings',
                    onPressed: () => _act('Opened settings'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: _region(
                name: 'Preview',
                controls: [
                  _actionButton(
                    label: 'Refresh',
                    onPressed: () => _act('Refreshed preview'),
                  ),
                  _actionButton(
                    label: 'Inspect',
                    onPressed: () => _act('Opened inspector'),
                  ),
                  _actionButton(label: 'Publish…', onPressed: _openDialog),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 1),
      Text('last: $_lastAction'),
    ],
  );
}

class _PublishDialog extends StatelessWidget {
  const _PublishDialog();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 38,
    height: 8,
    child: Panel(
      title: 'Publish?',
      focused: true,
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Column(
          children: [
            const Text('Tab stays inside this dialog.'),
            const SizedBox(height: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Button(
                  label: 'Cancel',
                  autofocus: true,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                const SizedBox(width: 1),
                Button(
                  label: 'Publish',
                  variant: ButtonVariant.primary,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// A complete app gets sequential and spatial traversal without screen-level
/// focus wiring.
Widget focusExplorerApp() =>
    const FleuryApp(title: 'Workspace', home: FocusExplorerExample());

/// Shows that [FocusDetector] observes a subtree boundary, not every move
/// between descendants.
class FocusBoundaryExample extends StatefulWidget {
  const FocusBoundaryExample({super.key});

  @override
  State<FocusBoundaryExample> createState() => _FocusBoundaryExampleState();
}

class _FocusBoundaryExampleState extends State<FocusBoundaryExample> {
  bool _inside = false;
  int _changes = 0;

  void _onFocusChange(bool inside) => setState(() {
    _inside = inside;
    _changes++;
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('editor: ${_inside ? 'active' : 'inactive'}'),
      Text('boundary changes: $_changes'),
      FocusDetector(
        onFocusChange: _onFocusChange,
        child: Column(
          children: [
            Button(label: 'Title', autofocus: true, onPressed: () {}),
            Button(label: 'Body', onPressed: () {}),
          ],
        ),
      ),
      Button(label: 'Preview', onPressed: () {}),
    ],
  );
}

/// The programmatic-focus pattern used later in the guide.
class EditorFocusExample extends StatefulWidget {
  const EditorFocusExample({super.key});

  @override
  State<EditorFocusExample> createState() => _EditorFocusExampleState();
}

class _EditorFocusExampleState extends State<EditorFocusExample> {
  final _searchFocus = FocusNode(debugLabel: 'search');
  String _lastAction = 'Focus search is focused';

  void focusSearch() {
    _searchFocus.requestFocus();
    setState(() => _lastAction = 'Focus moved to Search files');
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Button(
            label: 'Focus search',
            autofocus: true,
            onPressed: focusSearch,
          ),
          SizedBox(
            width: 24,
            child: TextInput(
              focusNode: _searchFocus,
              semanticLabel: 'Search files',
              placeholder: 'Search files',
              onChanged: (_) {},
            ),
          ),
        ],
      ),
      Text(_lastAction),
    ],
  );

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }
}
