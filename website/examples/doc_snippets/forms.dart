// The guide, browser demo, and this native entry point share the same widget.
import 'package:fleury/fleury.dart';
import '../lib/forms/project_form.dart';

void main() => runApp(formsDemoApp());

Widget formsDemoApp() =>
    const FleuryApp(title: 'Create project', home: ProjectForm());
