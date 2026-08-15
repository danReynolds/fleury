// Compile-checked source behind the Forms & validation guide. It demonstrates
// a declarative form, custom validation, typed values, and submit feedback.
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
  late final FormDefinition _definition = FormDefinition(
    title: 'Create project',
    submitLabel: 'Create',
    showCancel: false,
    fields: [
      FormFieldSpec.text(id: 'name', label: 'Name', required: true),
      FormFieldSpec.text(
        id: 'slug',
        label: 'Slug',
        required: true,
        validator: (value, _) {
          final slug = (value ?? '').toString();
          return RegExp(r'^[a-z0-9-]+$').hasMatch(slug)
              ? null
              : 'Use lowercase letters, numbers, and hyphens';
        },
      ),
      FormFieldSpec.checkbox(id: 'private', label: 'Private project'),
    ],
  );

  String _status = 'Fill in the project details';

  void _submit(FormSubmitResult result) {
    setState(() {
      _status = result.valid
          ? 'Created ${result.values.text('name')}'
          : 'Fix ${result.errors.length} field(s)';
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormPanel(
          definition: _definition,
          layout: FormPanelLayout.inline,
          fieldWidth: 26,
          onSubmit: _submit,
        ),
        const Spacer(),
        Text('status: $_status'),
      ],
    ),
  );
}
