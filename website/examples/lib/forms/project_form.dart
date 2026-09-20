// dart format width=60
import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

class ProjectForm extends StatefulWidget {
  const ProjectForm({super.key});

  @override
  State<ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends State<ProjectForm> {
  final form = FormController();
  final name = TextEditingController();
  final slug = TextEditingController();
  String status = 'Fill in the project details';

  @override
  void dispose() {
    form.dispose();
    name.dispose();
    slug.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Form(
      controller: form,
      onSubmit: () => setState(() {
        status =
            'Created ${name.text.trim()} '
            '(${slug.text.trim()})';
      }),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Name'),
          FormField(
            validator: () => name.text.trim().isEmpty
                ? 'Enter a project name.'
                : null,
            child: TextInput(
              controller: name,
              semanticLabel: 'Name',
              autofocus: true,
            ),
          ),
          const SizedBox(height: 1),
          const Text('Slug'),
          FormField(
            validator: () =>
                RegExp(
                  r'^[a-z0-9-]+$',
                ).hasMatch(slug.text.trim())
                ? null
                : 'Use lowercase letters, numbers, and hyphens.',
            child: TextInput(
              controller: slug,
              semanticLabel: 'Slug',
              onSubmit: (_) => form.submit(),
            ),
          ),
          const SizedBox(height: 1),
          Button(text: 'Create', onPressed: form.submit),
          const SizedBox(height: 1),
          Text('status: $status'),
        ],
      ),
    ),
  );
}
