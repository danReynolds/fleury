// Compile-checked source behind the core-widget guides: Lists & scrolling,
// Loading data, Input & gestures, and the RichText section of Theming. Exercises
// LayoutBuilder, RichText/TextSpan, StreamBuilder, FutureBuilder, ListView.builder,
// GestureDetector, and MouseRegion against the real API. Guarded by
// ../test/doc_snippets_test.dart so those guides can't drift. See README.md.

import 'package:fleury/fleury.dart';

void main() => runApp(const DemoApp(), mode: const TerminalMode(mouse: true));

class DemoApp extends StatefulWidget {
  const DemoApp({super.key});

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  bool _hovered = false;
  late final Future<List<String>> _items = _load();

  Future<List<String>> _load() async => const ['one', 'two', 'three'];

  Stream<int> get _ticks =>
      Stream<int>.periodic(const Duration(seconds: 1), (n) => n);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: const TextSpan(
              children: [
                TextSpan(text: 'status '),
                TextSpan(text: 'ok', style: CellStyle(bold: true)),
              ],
            ),
          ),
          StreamBuilder<int>(
            stream: _ticks,
            initialData: 0,
            builder: (context, snapshot) => Text('tick ${snapshot.data}'),
          ),
          Expanded(
            child: FutureBuilder<List<String>>(
              future: _items,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Text('Loading…');
                }
                if (snapshot.hasError) {
                  return Text('Failed: ${snapshot.error}');
                }
                final items = snapshot.data!;
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i, selected) => GestureDetector(
                    onTap: () {},
                    child: MouseRegion(
                      onEnter: () => setState(() => _hovered = true),
                      onExit: () => setState(() => _hovered = false),
                      child: Text(
                        items[i],
                        style: selected || _hovered
                            ? const CellStyle(inverse: true)
                            : CellStyle.empty,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
