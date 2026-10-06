import 'package:fleury/fleury_core.dart';

class SaveStatus extends StatefulWidget {
  const SaveStatus({super.key, required this.save});
  final Future<void> Function() save;

  @override
  State<SaveStatus> createState() => _SaveStatusState();
}

class _SaveStatusState extends State<SaveStatus> {
  Future<void>? request;

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: request,
    builder: (context, snapshot) {
      final saving = snapshot.connectionState == ConnectionState.waiting;
      final status = saving
          ? 'Saving…'
          : snapshot.hasError
          ? 'Save failed'
          : snapshot.connectionState == ConnectionState.done
          ? 'Saved'
          : 'Ready';
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Button(
            text: 'Save',
            onPressed: saving
                ? null
                : () => setState(() => request = widget.save()),
          ),
          Text(status),
        ],
      );
    },
  );
}
