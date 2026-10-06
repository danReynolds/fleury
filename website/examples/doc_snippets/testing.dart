import 'package:fleury/fleury.dart';
import 'package:fleury_doc_examples/testing/editor_demo.dart';

void main() => runApp(
  const FleuryApp(title: 'Draft editor', home: TestingEditorDemo()),
  mode: const TerminalMode(mouse: true),
);
