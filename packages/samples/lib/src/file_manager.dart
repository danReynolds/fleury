import 'dart:convert';

import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

import 'scaffold.dart';

/// A two-pane keyboard file manager: an expandable file tree on the left and a
/// content preview on the right that adapts to the file type (CodeView,
/// MarkdownView, or JsonView). The filesystem is an in-memory sample project,
/// so the demo runs identically in a terminal or in the browser over
/// `fleury serve` — no host filesystem access.
class FileManagerApp extends StatelessWidget {
  const FileManagerApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const SampleScaffold(child: _FileManagerBody());
}

class _FileManagerBody extends StatefulWidget {
  const _FileManagerBody();

  @override
  State<_FileManagerBody> createState() => _FileManagerBodyState();
}

class _FileManagerBodyState extends State<_FileManagerBody> {
  late final List<TreeNode<_FsNode>> _roots = _sampleProject
      .map(_toTreeNode)
      .toList();

  // Start with a file open so the preview pane isn't empty on first paint.
  _FsNode? _selected = _find(_sampleProject, 'README.md');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _header(theme),
        const SizedBox(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                flex: 2,
                child: Panel(
                  title: 'Explorer',
                  // No type-ahead: the footer advertises a bare-printable
                  // quit key ('q'), which a type-ahead tree would swallow.
                  child: Tree<_FsNode>(
                    semanticLabel: 'my-app',
                    roots: _roots,
                    autofocus: true,
                    typeahead: false,
                    onSelect: (node) {
                      final fs = node.value;
                      if (fs != null && !fs.isDir) {
                        setState(() => _selected = fs);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 1),
              Expanded(
                flex: 3,
                child: Panel(
                  title: _selected?.path ?? 'Preview',
                  trailing: Text(
                    _selected == null ? '' : _kindLabel(_selected!),
                    style: theme.mutedStyle,
                  ),
                  child: _preview(theme),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 1),
        Text(
          ' q quit   ↑/↓ navigate   → expand   ← collapse   Enter open file',
          style: theme.mutedStyle,
        ),
      ],
    );
  }

  Widget _header(ThemeData theme) {
    return Row(
      children: <Widget>[
        Text('▌ ', style: CellStyle(foreground: theme.colorScheme.primary)),
        Text(
          'Fleury Files',
          style: CellStyle(bold: true, foreground: theme.colorScheme.primary),
        ),
        Text('   my-app', style: theme.mutedStyle),
        const Expanded(child: SizedBox.shrink()),
        Text('${_countFiles(_sampleProject)} files', style: theme.mutedStyle),
      ],
    );
  }

  Widget _preview(ThemeData theme) {
    final node = _selected;
    if (node == null) {
      return const Center(child: Text('Select a file to preview'));
    }
    final name = node.name;
    if (name.endsWith('.md')) {
      return MarkdownView(markdown: node.content ?? '');
    }
    if (name.endsWith('.json')) {
      Object? decoded;
      try {
        decoded = jsonDecode(node.content ?? 'null');
      } catch (_) {
        decoded = node.content;
      }
      return JsonView(value: decoded, initialExpandedDepth: 3);
    }
    return CodeView(
      source: node.content ?? '',
      language: node.language,
      filePath: node.path,
      semanticLabel: name,
    );
  }

  String _kindLabel(_FsNode node) {
    if (node.name.endsWith('.md')) return 'markdown';
    if (node.name.endsWith('.json')) return 'json';
    return node.language ?? 'text';
  }
}

// ---------------------------------------------------------------------------
// In-memory sample filesystem.
// ---------------------------------------------------------------------------

class _FsNode {
  _FsNode.dir(this.name, this.path, this.children)
    : isDir = true,
      content = null,
      language = null;

  _FsNode.file(this.name, this.path, this.content, {this.language})
    : isDir = false,
      children = const <_FsNode>[];

  final String name;
  final String path;
  final bool isDir;
  final List<_FsNode> children;
  final String? content;
  final String? language;
}

TreeNode<_FsNode> _toTreeNode(_FsNode n) => TreeNode<_FsNode>(
  n.isDir ? '${n.name}/' : n.name,
  value: n,
  children: n.children.map(_toTreeNode).toList(),
);

_FsNode? _find(List<_FsNode> nodes, String name) {
  for (final n in nodes) {
    if (n.name == name) return n;
    final hit = _find(n.children, name);
    if (hit != null) return hit;
  }
  return null;
}

int _countFiles(List<_FsNode> nodes) => nodes.fold<int>(
  0,
  (sum, n) => sum + (n.isDir ? _countFiles(n.children) : 1),
);

final List<_FsNode> _sampleProject = <_FsNode>[
  _FsNode.dir('lib', 'my-app/lib', <_FsNode>[
    _FsNode.file(
      'main.dart',
      'my-app/lib/main.dart',
      _mainDart,
      language: 'dart',
    ),
    _FsNode.dir('src', 'my-app/lib/src', <_FsNode>[
      _FsNode.file(
        'app.dart',
        'my-app/lib/src/app.dart',
        _appDart,
        language: 'dart',
      ),
      _FsNode.file(
        'counter.dart',
        'my-app/lib/src/counter.dart',
        _counterDart,
        language: 'dart',
      ),
    ]),
  ]),
  _FsNode.dir('test', 'my-app/test', <_FsNode>[
    _FsNode.file(
      'counter_test.dart',
      'my-app/test/counter_test.dart',
      _counterTestDart,
      language: 'dart',
    ),
  ]),
  _FsNode.dir('assets', 'my-app/assets', <_FsNode>[
    _FsNode.file(
      'config.json',
      'my-app/assets/config.json',
      _configJson,
      language: 'json',
    ),
  ]),
  _FsNode.file('README.md', 'my-app/README.md', _readmeMd),
  _FsNode.file(
    'pubspec.yaml',
    'my-app/pubspec.yaml',
    _pubspecYaml,
    language: 'yaml',
  ),
];

const String _readmeMd = '''
# my-app

A tiny counter built with the **Fleury** TUI framework.

## Run

```sh
dart run lib/main.dart
```

## Layout

- `lib/` — application source
- `test/` — unit tests
- `assets/config.json` — runtime configuration

> Browse this tree on the left; the preview adapts to each file type.
''';

const String _mainDart = '''
import 'package:fleury/fleury.dart';

import 'src/app.dart';

Future<void> main() async {
  // Typed printables arrive as TextInputEvents, so a quit key is a
  // widget-level KeyBinding: a focused text field keeps claiming the
  // character, and requestExit() ends the app cleanly otherwise.
  await runApp(
    KeyBindings(
      bindings: [
        KeyBinding(KeySequence.q, onTrigger: () => requestExit(), label: 'Quit'),
      ],
      child: const CounterApp(),
    ),
  );
}
''';

const String _appDart = '''
import 'package:fleury/fleury_core.dart';

import 'counter.dart';

class CounterApp extends StatefulWidget {
  const CounterApp({super.key});

  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  final Counter _counter = Counter();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('count: \${_counter.value}'),
    );
  }
}
''';

const String _counterDart = '''
/// A trivially small model — incremented from the app.
class Counter {
  int _value = 0;

  int get value => _value;

  void increment() => _value++;
  void reset() => _value = 0;
}
''';

const String _counterTestDart = '''
import 'package:test/test.dart';

import '../lib/src/counter.dart';

void main() {
  test('increment bumps the value', () {
    final c = Counter();
    c.increment();
    expect(c.value, 1);
  });

  test('reset returns to zero', () {
    final c = Counter()..increment();
    c.reset();
    expect(c.value, 0);
  });
}
''';

const String _configJson = '''
{
  "name": "my-app",
  "version": "1.4.0",
  "theme": {
    "mode": "dark",
    "accent": "#3DDC97"
  },
  "features": {
    "telemetry": false,
    "autosave": true,
    "maxHistory": 50
  },
  "keybindings": ["q:quit", "r:reset", "?:help"]
}
''';

const String _pubspecYaml = '''
name: my_app
description: A tiny counter built with Fleury.
version: 1.4.0
publish_to: none

environment:
  sdk: ^3.10.0

dependencies:
  fleury:
    path: ../fleury

dev_dependencies:
  test: ^1.26.0
''';
