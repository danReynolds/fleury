// Compile-checked source for the docs tutorial "A filterable list"
// (website/src/content/docs/tutorial.mdx). The prose walks through this
// program in steps, then shows the `app` region below as the finished
// lib/app.dart. It is guarded by `dart analyze` (see
// ../test/doc_snippets_test.dart) so the tutorial can't drift from a real,
// compiling Fleury app. Keep the step fences in sync when this file changes.
// It imports the web-safe library, like Getting started's lib/app.dart, so
// the tutorial keeps that file compiling for the optional browser bundle.

// #docregion app
import 'package:fleury/fleury_core.dart';

const _languages = [
  'Dart',
  'Rust',
  'Go',
  'Python',
  'TypeScript',
  'Elixir',
  'Zig',
  'Swift',
  'Kotlin',
  'Haskell',
];

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const FleuryApp(title: 'Filter', home: FilterApp());
  }
}

class FilterApp extends StatefulWidget {
  const FilterApp({super.key});

  @override
  State<FilterApp> createState() => _FilterAppState();
}

class _FilterAppState extends State<FilterApp> {
  String _query = '';

  List<String> get _matches => _languages
      .where((name) => name.toLowerCase().contains(_query.toLowerCase()))
      .toList();

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextInput(
            autofocus: true,
            placeholder: 'Filter languages…',
            onChanged: (value) => setState(() => _query = value),
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

// #enddocregion app
