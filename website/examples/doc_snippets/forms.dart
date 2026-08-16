// Compile-checked source behind the Forms & validation guide. It demonstrates
// app-owned values, composable fields, validation, and submit feedback.
// Guarded by ../test/doc_snippets_test.dart.

import 'package:fleury/fleury.dart';
import 'package:fleury_widgets/fleury_widgets.dart';

void main() => runApp(formsDemoApp());

Widget formsDemoApp() =>
    const FleuryApp(title: 'Create project', home: ProjectForm());

class ProjectForm extends StatefulWidget {
  const ProjectForm({super.key});

  @override
  State<ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends State<ProjectForm> {
  final _form = FormController();
  final _name = TextEditingController();
  final _slug = TextEditingController();
  bool _private = true;
  String _status = 'Fill in the project details';

  @override
  void dispose() {
    _form.dispose();
    _name.dispose();
    _slug.dispose();
    super.dispose();
  }

  void _submit() => setState(() {
    _status = 'Created ${_name.text.trim()}';
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text('Create project'),
        Form(
          controller: _form,
          onSubmit: _submit,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Name'),
              FormField(
                validator: () =>
                    _name.text.trim().isEmpty ? 'Enter a project name.' : null,
                child: TextInput(
                  controller: _name,
                  autofocus: true,
                  semanticLabel: 'Name',
                  placeholder: 'Fleury app',
                ),
              ),
              const Text('Slug'),
              FormField(
                validator: () =>
                    RegExp(r'^[a-z0-9-]+$').hasMatch(_slug.text.trim())
                    ? null
                    : 'Use lowercase letters, numbers, and hyphens.',
                child: TextInput(
                  controller: _slug,
                  semanticLabel: 'Slug',
                  placeholder: 'fleury-app',
                  onSubmit: (_) => _form.submit(),
                ),
              ),
              FormField(
                child: Checkbox(
                  value: _private,
                  label: 'Private project',
                  onChanged: (value) => setState(() => _private = value),
                ),
              ),
              ListenableBuilder(
                listenable: _form,
                builder: (context, child) => Button(
                  label: _form.isSubmitting ? 'Creating…' : 'Create',
                  onPressed: _form.isSubmitting ? null : _form.submit,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Text('status: $_status'),
      ],
    ),
  );
}
