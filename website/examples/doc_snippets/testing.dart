import 'package:fleury/fleury.dart';

import '../lib/testing_guide.dart';

void main() => runApp(
  const FleuryApp(title: 'Draft editor', home: TestingEditorDemo()),
  mode: const TerminalMode(mouse: true),
);
