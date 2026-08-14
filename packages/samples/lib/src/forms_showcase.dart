import 'dart:async' show scheduleMicrotask, unawaited;

import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart';

import 'scaffold.dart';

/// A browser-safe service-deployment flow that exercises Fleury forms in a
/// believable multi-screen application.
class FormsShowcaseApp extends StatelessWidget {
  const FormsShowcaseApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const SampleScaffold(child: _FormsShowcaseBody());
}

class _FormsShowcaseBody extends StatefulWidget {
  const _FormsShowcaseBody();

  @override
  State<_FormsShowcaseBody> createState() => _FormsShowcaseBodyState();
}

class _FormsShowcaseBodyState extends State<_FormsShowcaseBody> {
  final _draft = _ServiceDraft();

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _reset() {
    _draft.reset();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(1),
    child: Navigator(
      transition: RouteTransition.slide,
      home: _ServiceDetailsScreen(draft: _draft, onReset: _reset),
    ),
  );
}

class _ServiceDraft {
  final name = TextEditingController();
  final description = TextEditingController(
    text: 'Processes incoming webhook events.',
  );

  bool private = true;
  String environment = 'Production';
  String region = 'Toronto';
  num replicas = 2;
  Set<String> telemetry = <String>{'Logs', 'Metrics'};
  bool autoDeploy = true;
  bool confirmed = false;

  void reset() {
    name.text = '';
    description.text = 'Processes incoming webhook events.';
    private = true;
    environment = 'Production';
    region = 'Toronto';
    replicas = 2;
    telemetry = <String>{'Logs', 'Metrics'};
    autoDeploy = true;
    confirmed = false;
  }

  void dispose() {
    name.dispose();
    description.dispose();
  }
}

class _ServiceDetailsScreen extends StatefulWidget {
  const _ServiceDetailsScreen({required this.draft, required this.onReset});

  final _ServiceDraft draft;
  final void Function() onReset;

  @override
  State<_ServiceDetailsScreen> createState() => _ServiceDetailsScreenState();
}

class _ServiceDetailsScreenState extends State<_ServiceDetailsScreen> {
  final _form = FormController();
  String? _nameError;

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    if (widget.draft.name.text.trim().toLowerCase() == 'fleury') {
      setState(() => _nameError = 'That service name is already in use.');
      scheduleMicrotask(_form.validate);
      return;
    }
    unawaited(
      context.push<void>(
        _DeploymentScreen(draft: widget.draft, onReset: widget.onReset),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _ShowcaseScreen(
    step: 1,
    title: 'Service details',
    description: 'Start with the identity and visibility of the service.',
    child: Form(
      controller: _form,
      semanticLabel: 'Create service details',
      onSubmit: _continue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Name'),
          FormField(
            error: _nameError,
            validator: () => widget.draft.name.text.trim().isEmpty
                ? 'Enter a service name.'
                : null,
            child: SizedBox(
              width: 42,
              child: TextInput(
                controller: widget.draft.name,
                autofocus: true,
                semanticLabel: 'Service name',
                placeholder: 'webhook-worker',
                onChanged: (_) {
                  if (_nameError != null) {
                    setState(() => _nameError = null);
                  }
                },
                onSubmit: (_) => _form.submit(),
              ),
            ),
          ),
          const SizedBox(height: 1),
          const Text('Description'),
          FormField(
            validator: () => widget.draft.description.text.trim().length < 10
                ? 'Add a little more detail.'
                : null,
            child: SizedBox(
              width: 52,
              child: TextArea(
                controller: widget.draft.description,
                semanticLabel: 'Description',
                minLines: 2,
                maxLines: 2,
              ),
            ),
          ),
          FormField(
            child: Checkbox(
              value: widget.draft.private,
              label: 'Private service',
              onChanged: (value) =>
                  setState(() => widget.draft.private = value),
            ),
          ),
          const Text('Tip: try the reserved name “fleury”.'),
          const SizedBox(height: 1),
          _SubmitButton(controller: _form, label: 'Continue'),
        ],
      ),
    ),
  );
}

class _DeploymentScreen extends StatefulWidget {
  const _DeploymentScreen({required this.draft, required this.onReset});

  final _ServiceDraft draft;
  final void Function() onReset;

  @override
  State<_DeploymentScreen> createState() => _DeploymentScreenState();
}

class _DeploymentScreenState extends State<_DeploymentScreen> {
  final _form = FormController();

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  void _continue() {
    unawaited(
      context.push<void>(
        _ReviewScreen(draft: widget.draft, onReset: widget.onReset),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _ShowcaseScreen(
    step: 2,
    title: 'Deployment',
    description: 'Choose where and how the service runs.',
    child: Form(
      controller: _form,
      semanticLabel: 'Create service deployment',
      onSubmit: _continue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Environment'),
          FormField(
            child: Select<String>(
              value: widget.draft.environment,
              semanticLabel: 'Environment',
              autofocus: true,
              options: const <SelectOption<String>>[
                SelectOption(value: 'Production', label: 'Production'),
                SelectOption(value: 'Staging', label: 'Staging'),
                SelectOption(value: 'Development', label: 'Development'),
              ],
              onChanged: (value) =>
                  setState(() => widget.draft.environment = value),
            ),
          ),
          const SizedBox(height: 1),
          const Text('Region'),
          FormField(
            child: RadioGroup<String>(
              value: widget.draft.region,
              semanticLabel: 'Region',
              axis: Axis.horizontal,
              options: const <RadioOption<String>>[
                RadioOption(value: 'Toronto', label: 'Toronto'),
                RadioOption(value: 'Virginia', label: 'Virginia'),
                RadioOption(value: 'Frankfurt', label: 'Frankfurt'),
              ],
              onChanged: (value) => setState(() => widget.draft.region = value),
            ),
          ),
          FormField(
            child: Stepper(
              value: widget.draft.replicas,
              label: 'Replicas',
              min: 1,
              max: 8,
              onChanged: (value) =>
                  setState(() => widget.draft.replicas = value),
            ),
          ),
          const SizedBox(height: 1),
          const Text('Telemetry'),
          FormField(
            validator: () => widget.draft.telemetry.isEmpty
                ? 'Choose at least one signal.'
                : null,
            child: MultiSelect<String>(
              values: widget.draft.telemetry,
              semanticLabel: 'Telemetry',
              options: const <SelectOption<String>>[
                SelectOption(value: 'Logs', label: 'Logs'),
                SelectOption(value: 'Metrics', label: 'Metrics'),
                SelectOption(value: 'Traces', label: 'Traces'),
              ],
              onChanged: (values) =>
                  setState(() => widget.draft.telemetry = values),
            ),
          ),
          FormField(
            child: Switch(
              value: widget.draft.autoDeploy,
              label: 'Deploy on merge',
              onChanged: (value) =>
                  setState(() => widget.draft.autoDeploy = value),
            ),
          ),
          const SizedBox(height: 1),
          _FormActions(
            controller: _form,
            nextLabel: 'Review',
            onBack: context.pop,
          ),
        ],
      ),
    ),
  );
}

class _ReviewScreen extends StatefulWidget {
  const _ReviewScreen({required this.draft, required this.onReset});

  final _ServiceDraft draft;
  final void Function() onReset;

  @override
  State<_ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<_ReviewScreen> {
  final _form = FormController();

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  Future<void> _deploy() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    unawaited(
      context.pushReplacement<void>(
        _SuccessScreen(draft: widget.draft, onReset: widget.onReset),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return _ShowcaseScreen(
      step: 3,
      title: 'Review',
      description: 'Confirm the complete deployment before it starts.',
      child: Form(
        controller: _form,
        semanticLabel: 'Review service',
        onSubmit: _deploy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Service      ${draft.name.text.trim()}'),
            Text('Access       ${draft.private ? 'Private' : 'Public'}'),
            Text('Target       ${draft.environment} / ${draft.region}'),
            Text('Replicas     ${draft.replicas.toInt()}'),
            Text('Telemetry    ${draft.telemetry.join(', ')}'),
            Text('Auto deploy  ${draft.autoDeploy ? 'On' : 'Off'}'),
            const SizedBox(height: 1),
            FormField(
              validator: () =>
                  draft.confirmed ? null : 'Confirm the production deployment.',
              child: Checkbox(
                value: draft.confirmed,
                autofocus: true,
                label: 'I reviewed these settings',
                onChanged: (value) => setState(() => draft.confirmed = value),
              ),
            ),
            const SizedBox(height: 1),
            _FormActions(
              controller: _form,
              nextLabel: 'Deploy service',
              onBack: context.pop,
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessScreen extends StatelessWidget {
  const _SuccessScreen({required this.draft, required this.onReset});

  final _ServiceDraft draft;
  final void Function() onReset;

  void _createAnother(BuildContext context) {
    onReset();
    context.popToRoot();
  }

  @override
  Widget build(BuildContext context) => _ShowcaseScreen(
    step: 3,
    title: 'Service deployed',
    description: 'The form values survived the complete route flow.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('✓ DEPLOYMENT COMPLETE'),
        const SizedBox(height: 1),
        Text('${draft.name.text.trim()} is live in ${draft.region}.'),
        Text('${draft.replicas.toInt()} replicas · ${draft.environment}'),
        const SizedBox(height: 2),
        Button(
          autofocus: true,
          label: 'Create another',
          onPressed: () => _createAnother(context),
        ),
      ],
    ),
  );
}

class _ShowcaseScreen extends StatelessWidget {
  const _ShowcaseScreen({
    required this.step,
    required this.title,
    required this.description,
    required this.child,
  });

  final int step;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Row(
        children: <Widget>[
          const Text('FLEURY DEPLOY'),
          const Spacer(),
          Text('STEP $step OF 3', style: Theme.of(context).mutedStyle),
        ],
      ),
      const SizedBox(height: 1),
      Expanded(
        child: Panel(
          title: title,
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(description, style: Theme.of(context).mutedStyle),
                const SizedBox(height: 1),
                child,
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 1),
      const Text('Tab moves · Enter activates · Esc goes back'),
    ],
  );
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.controller, required this.label});

  final FormController controller;
  final String label;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, child) => Button(
      label: controller.isSubmitting ? 'Checking…' : label,
      onPressed: controller.isSubmitting ? null : controller.submit,
    ),
  );
}

class _FormActions extends StatelessWidget {
  const _FormActions({
    required this.controller,
    required this.nextLabel,
    required this.onBack,
  });

  final FormController controller;
  final String nextLabel;
  final void Function() onBack;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, child) => Row(
      children: <Widget>[
        Button(
          label: 'Back',
          onPressed: controller.isSubmitting ? null : onBack,
        ),
        const SizedBox(width: 2),
        Button(
          label: controller.isSubmitting ? 'Working…' : nextLabel,
          onPressed: controller.isSubmitting ? null : controller.submit,
        ),
      ],
    ),
  );
}
