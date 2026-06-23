// Compile-checked source for the docs tutorial "A filterable list"
// (website/src/content/docs/tutorial.md). The prose walks through this program
// in steps; this file is the finished result and is guarded by `dart analyze`
// (see ../test/doc_snippets_test.dart) so the tutorial can't drift from a real,
// compiling Fleury app. Keep the two in sync when either changes.

import 'package:fleury/fleury.dart';

const _languages = [
  'Dart', 'Rust', 'Go', 'Python', 'TypeScript',
  'Elixir', 'Zig', 'Swift', 'Kotlin', 'Haskell',
];

void main() => runTui(const FilterApp());

class FilterApp extends StatefulWidget {
  const FilterApp({super.key});

  @override
  State<FilterApp> createState() => _FilterAppState();
}

class _FilterAppState extends State<FilterApp> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> get _matches {
    final query = _controller.text.toLowerCase();
    return _languages
        .where((name) => name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextInput(
            controller: _controller,
            autofocus: true,
            placeholder: 'Filter languages…',
          ),
          const SizedBox(height: 1),
          Text(
            '${matches.length} of ${_languages.length}',
            style: const CellStyle(dim: true),
          ),
          const SizedBox(height: 1),
          Expanded(
            child: matches.isEmpty
                ? const Text('No matches', style: CellStyle(dim: true))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final name in matches) Text(name)],
                  ),
          ),
        ],
      ),
    );
  }
}
