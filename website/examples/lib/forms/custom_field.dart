// dart format width=60
import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

class CustomField extends StatefulWidget {
  const CustomField({super.key});

  @override
  State<CustomField> createState() => _CustomFieldState();
}

class _CustomFieldState extends State<CustomField> {
  final form = FormController();
  num start = 5;
  num end = 3;
  String status = 'Set an end greater than the start';

  @override
  void dispose() {
    form.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Form(
      controller: form,
      onSubmit: () => setState(
        () => status = 'Saved range $start–$end',
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Range'),
          FormField.builder(
            validator: () => end > start
                ? null
                : 'End must be greater than start.',
            builder: (context, field) => Semantics(
              role: SemanticRole.region,
              label: 'Range',
              validationError: field.error,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Stepper(
                    label: 'Start',
                    value: start,
                    min: 0,
                    max: 9,
                    focusNode: field.focusNode,
                    onChanged: (value) {
                      setState(() => start = value);
                      field.valueChanged();
                    },
                  ),
                  Stepper(
                    label: 'End',
                    value: end,
                    min: 0,
                    max: 9,
                    onChanged: (value) {
                      setState(() => end = value);
                      field.valueChanged();
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 1),
          const _SaveRangeButton(),
          const SizedBox(height: 1),
          Text(status),
        ],
      ),
    ),
  );
}

class _SaveRangeButton extends StatelessWidget {
  const _SaveRangeButton();

  @override
  Widget build(BuildContext context) {
    // Form.of also rebuilds this widget when the controller changes.
    final form = Form.of(context);
    return Button(
      text: 'Save range',
      onPressed: form.isBusy ? null : form.submit,
    );
  }
}
