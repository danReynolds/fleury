// Terminal entry point for the same task browser shown in the guide.
import 'package:fleury/fleury.dart';
import '../lib/lists/task_browser.dart';

void main() => runApp(listsDemoApp());

Widget listsDemoApp() => const FleuryApp(
  title: 'Tasks',
  home: Padding(padding: EdgeInsets.all(1), child: TaskBrowser()),
);
