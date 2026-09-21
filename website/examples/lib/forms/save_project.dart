// dart format width=60
import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

// A local service simulation; this demo sends no requests.
enum SaveScenario { success, nameTaken, offline }

enum SaveReply { saved, nameTaken }

class ServiceUnavailable implements Exception {}

Future<SaveReply> simulateSave(
  String name,
  SaveScenario scenario,
) async {
  await Future<void>.delayed(const Duration(seconds: 1));
  if (scenario == SaveScenario.offline) {
    throw ServiceUnavailable();
  }
  return scenario == SaveScenario.nameTaken
      ? SaveReply.nameTaken
      : SaveReply.saved;
}

class SaveProject extends StatefulWidget {
  const SaveProject({super.key, this.save = simulateSave});

  final Future<SaveReply> Function(String, SaveScenario)
  save;

  @override
  State<SaveProject> createState() => _SaveProjectState();
}

class _SaveProjectState extends State<SaveProject> {
  final form = FormController();
  final name = TextEditingController(text: 'Atlas');
  SaveScenario scenario = SaveScenario.success;
  String? nameError;
  String status = 'Ready to save';

  Future<void> save() async {
    // Snapshot the submitted value before the asynchronous work.
    final submittedName = name.text.trim();
    setState(() => status = 'Saving $submittedName…');
    try {
      final reply = await widget.save(
        submittedName,
        scenario,
      );
      if (!mounted) return;
      if (reply == SaveReply.nameTaken) {
        setState(() {
          nameError = 'That name is taken. Try another.';
          status = 'Choose another name';
        });
        // submit() applies this error, focuses Name, and returns false.
        return;
      }
      // Success-only actions (including closing a dialog) belong here.
      setState(() => status = 'Saved $submittedName');
    } on ServiceUnavailable {
      if (mounted) {
        setState(
          () => status =
              'Offline. Your draft is kept. Retry.',
        );
      }
      rethrow; // An awaiting caller must not mistake this for success.
    }
  }

  Future<void> submit() async {
    try {
      await form.submit();
    } on ServiceUnavailable {
      // save() already displayed this expected failure. Keep the UI open.
    }
  }

  @override
  void dispose() {
    form.dispose();
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: NotifierBuilder(
      notifier: form,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Simulated server response'),
          Select<SaveScenario>(
            semanticLabel: 'Server response',
            value: scenario,
            onChanged: form.isBusy
                ? null
                : (value) =>
                      setState(() => scenario = value),
            options: const [
              SelectOption(
                value: SaveScenario.success,
                label: 'Success',
              ),
              SelectOption(
                value: SaveScenario.nameTaken,
                label: 'Name taken',
              ),
              SelectOption(
                value: SaveScenario.offline,
                label: 'Offline',
              ),
            ],
          ),
          const SizedBox(height: 1),
          Form(
            controller: form,
            onSubmit: save,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Name'),
                FormField(
                  error: nameError,
                  validator: () => name.text.trim().isEmpty
                      ? 'Enter a project name.'
                      : null,
                  child: TextInput(
                    controller: name,
                    semanticLabel: 'Name',
                    readOnly: form.isSubmitting,
                    onChanged: (_) =>
                        setState(() => nameError = null),
                    onSubmit: (_) => submit(),
                  ),
                ),
                const SizedBox(height: 1),
                Button(
                  text: form.isBusy ? 'Saving…' : 'Save',
                  onPressed: form.isBusy ? null : submit,
                ),
              ],
            ),
          ),
          const SizedBox(height: 1),
          Text(status),
        ],
      ),
    ),
  );
}
