import 'package:fleury/fleury_core.dart';

// Return your app from buildApp; Fleury Pad supplies main() and the browser host.
Widget buildApp() => Theme(
  data: ThemeData.dark(),
  child: const FocusTraversalGroup(child: Counter()),
);

class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int _count = 0;
  final _draft = TextEditingController();

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Hello, Fleury Pad!', style: CellStyle(bold: true)),
          const SizedBox(height: 1),
          Text('Count: $_count'),
          Button(
            child: const Text('Increment'),
            onPressed: () => setState(() => _count++),
          ),
          const SizedBox(height: 2),
          TextArea(controller: _draft, placeholder: 'Write a draft…', minLines: 3, maxLines: 3),
        ],
      ),
    );
  }
}
