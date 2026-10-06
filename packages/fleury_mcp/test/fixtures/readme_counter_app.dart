// The README's "Your app needs no MCP code" counter, from its first import to
// the end, verbatim: readme_example_e2e_test.dart fails if the two differ, and
// drives this app to check the README's "What the agent sees" output.

import 'package:fleury/fleury.dart';

void main() => runApp(const CounterApp());

class CounterApp extends StatefulWidget {
  const CounterApp({super.key});
  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  int _count = 0;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text('Count: $_count'),
      Button(
        text: 'Increment',
        onPressed: () => setState(() => _count++),
      ),
    ],
  );
}
