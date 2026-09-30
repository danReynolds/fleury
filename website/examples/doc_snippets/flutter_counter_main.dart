// The runnable Fleury counter from "Coming from Flutter": the page joins this
// file's region with the widget classes in lib/flutter_map.dart, which the
// live demo runs.
// #docregion counter
import 'package:fleury/fleury.dart';
// #enddocregion counter
import 'package:fleury_doc_examples/flutter_map.dart';

// #docregion counter
void main() => runApp(const FleuryApp(title: 'Counter', home: Counter()));
// #enddocregion counter
