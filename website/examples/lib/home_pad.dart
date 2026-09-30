import 'package:fleury/fleury_core.dart';

class HelloFleury extends StatefulWidget {
  const HelloFleury({super.key});

  @override
  State<HelloFleury> createState() => _HelloFleuryState();
}

class _HelloFleuryState extends State<HelloFleury> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      border: const BoxBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hello, Fleury!',
            style: CellStyle(foreground: colors.primary, bold: true),
          ),
          const SizedBox(height: 1),
          Text('Pressed $count ${count == 1 ? 'time' : 'times'}'),
          const SizedBox(height: 1),
          Button(
            text: 'Press me',
            autofocus: true,
            onPressed: () => setState(() => count++),
          ),
        ],
      ),
    );
  }
}
