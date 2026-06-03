import 'dart:async';
import 'dart:io';

import 'package:fleury/fleury.dart';
import 'package:fleury/fleury_test.dart';
import 'package:fleury_widgets/fleury_widgets.dart';
import 'package:test/test.dart';

FormDefinition _connectionForm() {
  return FormDefinition(
    title: 'Connection setup',
    submitLabel: 'Connect',
    fields: [
      FormFieldSpec.text(
        id: 'project',
        label: 'Project',
        placeholder: 'my-project',
        required: true,
      ),
      FormFieldSpec.select(
        id: 'environment',
        label: 'Environment',
        initialValue: 'dev',
        required: true,
        options: const [
          FormOption(value: 'dev', label: 'Development'),
          FormOption(value: 'prod', label: 'Production'),
        ],
      ),
      FormFieldSpec.select(
        id: 'region',
        label: 'Region',
        initialValue: 'us-east-1',
        required: true,
        options: const [
          FormOption(value: 'us-east-1', label: 'US East'),
          FormOption(value: 'eu-west-1', label: 'EU West'),
        ],
      ),
      FormFieldSpec.secret(
        id: 'apiKey',
        label: 'API key',
        placeholder: 'token',
        required: true,
      ),
      FormFieldSpec.checkbox(
        id: 'confirm',
        label: 'I understand this changes remote state',
        required: true,
      ),
    ],
  );
}

FormDefinition _numericForm() {
  return FormDefinition(
    title: 'Retry policy',
    submitLabel: 'Apply',
    fields: [
      FormFieldSpec.number(
        id: 'retries',
        label: 'Retry limit',
        initialValue: 2,
        min: 0,
        max: 5,
        allowNegative: false,
        required: true,
      ),
      FormFieldSpec.number(
        id: 'ratio',
        label: 'Backoff ratio',
        initialValue: 1.5,
        min: 1,
        max: 4,
        allowDecimal: true,
      ),
    ],
  );
}

FormDefinition _dateForm() {
  return FormDefinition(
    title: 'Schedule',
    submitLabel: 'Save',
    fields: [
      FormFieldSpec.date(
        id: 'start',
        label: 'Start date',
        initialValue: DateTime(2024, 3, 15),
        firstDate: DateTime(2024, 3, 1),
        lastDate: DateTime(2024, 3, 31),
        weekStartsOn: CalendarWeekStart.monday,
        required: true,
      ),
    ],
  );
}

FormDefinition _multiSelectForm() {
  return FormDefinition(
    title: 'Capabilities',
    submitLabel: 'Apply',
    fields: [
      FormFieldSpec.multiSelect(
        id: 'capabilities',
        label: 'Capabilities',
        initialValues: const ['logs'],
        required: true,
        minSelected: 1,
        maxSelected: 2,
        options: const [
          FormOption(value: 'logs', label: 'Logs'),
          FormOption(value: 'metrics', label: 'Metrics'),
          FormOption(value: 'traces', label: 'Traces'),
          FormOption(value: 'deploy', label: 'Deploy', enabled: false),
        ],
      ),
    ],
  );
}

FormDefinition _pathForm(String initialPath) {
  return FormDefinition(
    title: 'Config path',
    submitLabel: 'Save',
    fields: [
      FormFieldSpec.path(
        id: 'configPath',
        label: 'Config path',
        initialValue: initialPath,
        placeholder: '/path/to/config.json',
        required: true,
        pathKind: FormPathKind.file,
        mustExist: true,
        allowRelative: false,
      ),
    ],
  );
}

FormDefinition _asyncProjectForm({
  required FutureOr<String?> Function(Object? value, FormValues values)
  validator,
}) {
  return FormDefinition(
    title: 'Async project',
    submitLabel: 'Save',
    fields: [
      FormFieldSpec.text(
        id: 'project',
        label: 'Project',
        required: true,
        asyncValidator: validator,
      ),
    ],
  );
}

FormDefinition _asyncWizardForm({
  required FutureOr<String?> Function(Object? value, FormValues values)
  validator,
}) {
  return FormDefinition(
    title: 'Async wizard',
    submitLabel: 'Save',
    fields: [
      FormFieldSpec.text(
        id: 'project',
        label: 'Project',
        required: true,
        asyncValidator: validator,
      ),
      FormFieldSpec.checkbox(id: 'confirm', label: 'Confirm', required: true),
    ],
  );
}

const _connectionWizardSteps = [
  FormWizardStep(
    id: 'identity',
    title: 'Identity',
    fieldIds: ['project', 'environment', 'region'],
  ),
  FormWizardStep(
    id: 'credentials',
    title: 'Credentials',
    fieldIds: ['apiKey', 'confirm'],
  ),
];

const _asyncWizardSteps = [
  FormWizardStep(id: 'project', title: 'Project', fieldIds: ['project']),
  FormWizardStep(id: 'confirm', title: 'Confirm', fieldIds: ['confirm']),
];

String _screen(FleuryTester tester, {int cols = 80, int rows = 16}) {
  return tester.renderToString(size: CellSize(cols, rows), emptyMark: ' ');
}

Matcher _stateError(String message) {
  return throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );
}

void main() {
  group('FormWizardController lifecycle', () {
    test('dispose is idempotent and keeps final readable state', () {
      final controller = FormWizardController(initialStepIndex: 1);

      controller.dispose();
      controller.dispose();

      expect(controller.currentStepIndex, 1);
      expect(controller.canGoBack, isTrue);
      expect(controller.canGoNext(stepCount: 3), isTrue);
    });

    test('mutating after dispose throws a lifecycle error', () {
      final controller = FormWizardController(initialStepIndex: 1)..dispose();

      const message = 'FormWizardController has been disposed.';
      expect(() => controller.goTo(0, stepCount: 2), _stateError(message));
      expect(() => controller.next(stepCount: 2), _stateError(message));
      expect(controller.previous, _stateError(message));
      expect(() => controller.reset(stepCount: 2), _stateError(message));
    });
  });

  group('FormController lifecycle', () {
    test('dispose is idempotent and keeps final readable state', () {
      final controller = FormController(_connectionForm())
        ..setValue('project', 'dune')
        ..setValue('apiKey', 'secret-token')
        ..setValue('confirm', true);
      final result = controller.submit();
      controller.setError('region', 'Region blocked.');

      controller.dispose();
      controller.dispose();

      expect(result.valid, isTrue);
      expect(controller.values.text('project'), 'dune');
      expect(controller.values.text('apiKey'), 'secret-token');
      expect(controller.error('region'), 'Region blocked.');
      expect(controller.dirty, isTrue);
      expect(controller.submitted, isTrue);
      expect(controller.validating, isFalse);

      final snapshot = controller.snapshot;
      expect(snapshot.submitted, isTrue);
      expect(snapshot.validating, isFalse);
      expect(snapshot.field('project').displayValue, 'dune');
      expect(snapshot.field('region').error, 'Region blocked.');
    });

    test('mutating after dispose throws a lifecycle error', () async {
      final controller = FormController(
        _asyncProjectForm(validator: (value, values) => null),
      )..dispose();

      const message = 'FormController has been disposed.';
      expect(
        () => controller.setError('project', 'Taken'),
        _stateError(message),
      );
      expect(
        () => controller.setValue('project', 'dune'),
        _stateError(message),
      );
      expect(() => controller.reset(), _stateError(message));
      expect(controller.validate, _stateError(message));
      expect(() => controller.validateField('project'), _stateError(message));
      expect(controller.submit, _stateError(message));
      await expectLater(controller.validateAsync(), _stateError(message));
      await expectLater(
        controller.validateFieldAsync('project'),
        _stateError(message),
      );
      await expectLater(controller.submitAsync(), _stateError(message));
    });

    test(
      'dispose clears validating state and ignores late async validation',
      () async {
        final completer = Completer<String?>();
        final controller = FormController(
          _asyncProjectForm(validator: (value, values) => completer.future),
        )..setValue('project', 'dune');

        final validation = controller.validateAsync();
        expect(controller.validating, isTrue);
        expect(controller.snapshot.field('project').validating, isTrue);

        controller.dispose();
        expect(controller.validating, isFalse);
        expect(controller.snapshot.field('project').validating, isFalse);

        completer.complete('Project is already claimed.');
        expect(await validation, isTrue);
        expect(controller.error('project'), isNull);
        expect(controller.validating, isFalse);
      },
    );

    test('dispose ignores late async submit results', () async {
      final completer = Completer<String?>();
      final controller = FormController(
        _asyncProjectForm(validator: (value, values) => completer.future),
      )..setValue('project', 'dune');

      final submission = controller.submitAsync();
      expect(controller.submitted, isTrue);
      expect(controller.validating, isTrue);

      controller.dispose();
      completer.complete('Project is already claimed.');

      final result = await submission;
      expect(result.valid, isTrue);
      expect(result.values.text('project'), 'dune');
      expect(result.errors, isEmpty);
      expect(controller.error('project'), isNull);
      expect(controller.validating, isFalse);
    });
  });

  test('controller snapshot exposes safe field state and reset semantics', () {
    final definition = _connectionForm();
    final controller = FormController(definition);

    var snapshot = controller.snapshot;
    expect(snapshot.title, 'Connection setup');
    expect(snapshot.fieldCount, 5);
    expect(snapshot.valid, isTrue);
    expect(snapshot.safeValueMap['apiKey'], isNull);
    expect(snapshot.field('environment').value, 'dev');
    expect(snapshot.field('environment').displayValue, 'Development');
    expect(snapshot.field('apiKey').redacted, isTrue);
    expect(snapshot.field('apiKey').displayValue, isNull);

    controller
      ..setValue('project', 'dune')
      ..setValue('environment', 'prod')
      ..setValue('apiKey', 'secret-token');

    snapshot = controller.snapshot;
    expect(snapshot.dirty, isTrue);
    expect(snapshot.field('project').displayValue, 'dune');
    expect(snapshot.field('environment').displayValue, 'Production');
    expect(snapshot.field('apiKey').hasValue, isTrue);
    expect(snapshot.field('apiKey').value, isNull);
    expect(snapshot.toJson().toString(), isNot(contains('secret-token')));

    final result = controller.submit();
    expect(result.valid, isFalse);
    snapshot = controller.snapshot;
    expect(snapshot.submitted, isTrue);
    expect(snapshot.errorCount, 1);
    expect(
      snapshot.field('confirm').error,
      'I understand this changes remote state must be accepted.',
    );

    controller.reset(values: {'project': 'restored'});
    snapshot = controller.snapshot;
    expect(snapshot.dirty, isFalse);
    expect(snapshot.submitted, isFalse);
    expect(snapshot.errorCount, 0);
    expect(snapshot.field('project').displayValue, 'restored');
    expect(snapshot.field('environment').value, 'dev');
  });

  test('number fields expose typed snapshots and validation bounds', () {
    final definition = _numericForm();
    final controller = FormController(definition);

    var snapshot = controller.snapshot;
    final retries = snapshot.field('retries');
    expect(retries.type, FormFieldType.number);
    expect(retries.value, 2);
    expect(retries.displayValue, '2');
    expect(retries.min, 0);
    expect(retries.max, 5);
    expect(retries.allowNegative, isFalse);
    expect(retries.allowDecimal, isFalse);

    controller.setValue('retries', 8);
    expect(
      controller.validateField('retries'),
      'Retry limit must be at most 5.',
    );
    snapshot = controller.snapshot;
    expect(snapshot.valid, isFalse);
    expect(snapshot.field('retries').error, 'Retry limit must be at most 5.');
    expect(snapshot.toJson()['fields'].toString(), contains('allowNegative'));

    controller
      ..setValue('retries', 'bad')
      ..setValue('ratio', '2.25');
    expect(
      controller.validateField('retries'),
      'Retry limit must be a whole number.',
    );
    expect(controller.validateField('ratio'), isNull);
  });

  test('date fields expose typed snapshots and validation bounds', () {
    final definition = _dateForm();
    final controller = FormController(definition);

    var snapshot = controller.snapshot;
    final start = snapshot.field('start');
    expect(start.type, FormFieldType.date);
    expect(start.value, DateTime(2024, 3, 15));
    expect(start.displayValue, '2024-03-15');
    expect(start.firstDate, DateTime(2024, 3, 1));
    expect(start.lastDate, DateTime(2024, 3, 31));
    expect(start.weekStartsOn, CalendarWeekStart.monday);
    expect(controller.values.dateValue('start'), DateTime(2024, 3, 15));
    expect(snapshot.toJson()['fields'].toString(), contains('2024-03-15'));

    controller.setValue('start', '2024-04-01');
    expect(
      controller.validateField('start'),
      'Start date must be on or before 2024-03-31.',
    );

    controller.setValue('start', 'not-a-date');
    expect(
      controller.validateField('start'),
      'Start date must be a date in YYYY-MM-DD format.',
    );

    controller.setValue('start', DateTime(2024, 3, 20, 15, 45));
    expect(controller.validateField('start'), isNull);
    snapshot = controller.snapshot;
    expect(snapshot.field('start').value, DateTime(2024, 3, 20));
    expect(snapshot.field('start').displayValue, '2024-03-20');
  });

  test('multi-select fields expose safe list snapshots and validation', () {
    final definition = _multiSelectForm();
    final controller = FormController(definition);

    var snapshot = controller.snapshot;
    final capabilities = snapshot.field('capabilities');
    expect(capabilities.type, FormFieldType.multiSelect);
    expect(capabilities.value, ['logs']);
    expect(capabilities.displayValue, 'Logs');
    expect(capabilities.optionCount, 4);
    expect(capabilities.enabledOptionCount, 3);
    expect(capabilities.selectedOptionCount, 1);
    expect(capabilities.minSelected, 1);
    expect(capabilities.maxSelected, 2);
    expect(controller.values.listValue('capabilities'), ['logs']);
    expect(
      snapshot.toJson()['fields'].toString(),
      contains('selectedOptionCount'),
    );

    controller.setValue('capabilities', const ['logs', 'metrics', 'traces']);
    expect(
      controller.validateField('capabilities'),
      'Capabilities must include at most 2 options.',
    );

    controller.setValue('capabilities', const ['deploy']);
    expect(
      controller.validateField('capabilities'),
      'Capabilities includes a disabled option.',
    );

    controller.setValue('capabilities', const ['unknown']);
    expect(
      controller.validateField('capabilities'),
      'Capabilities includes an unknown option.',
    );

    controller.setValue('capabilities', const ['metrics', 'traces']);
    expect(controller.validateField('capabilities'), isNull);
    snapshot = controller.snapshot;
    expect(snapshot.field('capabilities').displayValue, 'Metrics, Traces');
    expect(snapshot.field('capabilities').selectedOptionCount, 2);
  });

  test('path fields expose safe snapshots and filesystem validation', () {
    final temp = Directory.systemTemp.createTempSync('fleury_form_path_');
    try {
      final file = File('${temp.path}${Platform.pathSeparator}config.json')
        ..writeAsStringSync('{}');
      final definition = _pathForm(file.path);
      final controller = FormController(definition);

      var snapshot = controller.snapshot;
      final path = snapshot.field('configPath');
      expect(path.type, FormFieldType.path);
      expect(path.value, file.path);
      expect(path.displayValue, file.path);
      expect(path.pathKind, FormPathKind.file);
      expect(path.mustExist, isTrue);
      expect(path.allowRelative, isFalse);
      expect(controller.values.path('configPath'), file.path);
      expect(snapshot.toJson()['fields'].toString(), contains('pathKind'));

      controller.setValue('configPath', 'relative/config.json');
      expect(
        controller.validateField('configPath'),
        'Config path must be an absolute path.',
      );

      controller.setValue(
        'configPath',
        '${temp.path}${Platform.pathSeparator}missing.json',
      );
      expect(controller.validateField('configPath'), 'Config path must exist.');

      controller.setValue('configPath', temp.path);
      expect(
        controller.validateField('configPath'),
        'Config path must be a file.',
      );

      controller.setValue('configPath', file.path);
      expect(controller.validateField('configPath'), isNull);
      snapshot = controller.snapshot;
      expect(snapshot.field('configPath').displayValue, file.path);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('async validators expose validating snapshots and errors', () async {
    final completer = Completer<String?>();
    final definition = _asyncProjectForm(
      validator: (value, values) => value == 'dune' ? completer.future : null,
    );
    final controller = FormController(definition)..setValue('project', 'dune');

    final validation = controller.validateAsync();
    var snapshot = controller.snapshot;
    expect(snapshot.validating, isTrue);
    expect(snapshot.valid, isFalse);
    expect(snapshot.hasAsyncValidators, isTrue);
    expect(snapshot.field('project').hasAsyncValidator, isTrue);
    expect(snapshot.field('project').validating, isTrue);

    completer.complete('Project is already claimed.');
    expect(await validation, isFalse);
    snapshot = controller.snapshot;
    expect(snapshot.validating, isFalse);
    expect(snapshot.field('project').error, 'Project is already claimed.');

    controller.setValue('project', 'fleury');
    final result = await controller.submitAsync();
    expect(result.valid, isTrue);
    expect(result.values.text('project'), 'fleury');
    expect(controller.snapshot.submitted, isTrue);
  });

  testWidgets('renders a full-screen form with aggregate and field semantics', (
    tester,
  ) {
    final definition = _connectionForm();
    final controller = FormController(definition);
    tester.pumpWidget(
      FormPanel(definition: definition, controller: controller),
    );

    final output = _screen(tester);
    expect(output, contains('Connection setup'));
    expect(output, contains('Project *'));
    expect(output, contains('Environment *'));
    expect(output, contains('API key *'));
    expect(output, contains('[ Connect ]'));

    final form = tester.semantics().single(
      role: SemanticRole.form,
      label: 'Connection setup',
      action: SemanticAction.submit,
    );
    expect(form.actions, contains(SemanticAction.cancel));
    expect(form.state['fieldCount'], 5);
    expect(form.state['errorCount'], 0);
    expect(form.state['layout'], 'fullScreen');

    final project = tester.semantics().single(
      role: SemanticRole.formField,
      label: 'Project',
    );
    expect(project.value, '');
    expect(project.state['fieldId'], 'project');
    expect(project.state['required'], isTrue);
    expect(project.state['redacted'], isFalse);

    final apiKey = tester.semantics().single(
      role: SemanticRole.formField,
      label: 'API key',
    );
    expect(apiKey.value, isNull);
    expect(apiKey.state['redacted'], isTrue);
    expect(apiKey.state['redactedValue'], isTrue);
    expect(apiKey.state['clipboardRedacted'], isTrue);
    expect(
      tester
          .accessibilitySnapshot()
          .single(
            role: SemanticRole.formField,
            label: 'API key',
            valueRedacted: true,
          )
          .value,
      isNull,
    );
  });

  testWidgets('typing and submit button produce a valid submit result', (
    tester,
  ) {
    final definition = _connectionForm();
    final controller = FormController(definition);
    FormSubmitResult? submitted;
    tester.pumpWidget(
      FormPanel(
        definition: definition,
        controller: controller,
        onSubmit: (result) => submitted = result,
      ),
    );

    tester.type('dune');
    expect(controller.value('project'), 'dune');
    controller
      ..setValue('environment', 'prod')
      ..setValue('region', 'eu-west-1')
      ..setValue('apiKey', 'secret-token')
      ..setValue('confirm', true);
    tester.pump();

    _screen(tester);
    for (var i = 0; i < 5; i++) {
      tester.sendKey(const KeyEvent(keyCode: KeyCode.tab));
    }
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));

    expect(submitted, isNotNull);
    expect(submitted!.valid, isTrue);
    expect(submitted!.values.text('project'), 'dune');
    expect(submitted!.values['environment'], 'prod');
    expect(submitted!.values.boolValue('confirm'), isTrue);
  });

  testWidgets('controller reset updates mounted text controls and semantics', (
    tester,
  ) {
    final definition = _connectionForm();
    final controller = FormController(definition);
    tester.pumpWidget(
      FormPanel(definition: definition, controller: controller),
    );

    tester.type('dune');
    expect(controller.value('project'), 'dune');

    controller.reset(values: {'project': 'restored'});
    tester.pump();

    expect(_screen(tester), contains('restored'));
    final project = tester.semantics().single(
      role: SemanticRole.formField,
      label: 'Project',
      value: 'restored',
    );
    expect(project.state['hasValue'], isTrue);
    expect(project.state['redactedValue'], isFalse);
  });

  testWidgets('semantic submit and cancel use form callbacks', (tester) async {
    final definition = _connectionForm();
    final controller = FormController(definition);
    FormSubmitResult? submitted;
    var cancelled = false;
    tester.pumpWidget(
      FormPanel(
        definition: definition,
        controller: controller,
        onSubmit: (result) => submitted = result,
        onCancel: () => cancelled = true,
      ),
    );

    controller
      ..setValue('project', 'dune')
      ..setValue('environment', 'prod')
      ..setValue('region', 'eu-west-1')
      ..setValue('apiKey', 'secret-token')
      ..setValue('confirm', true);
    tester.pump();

    final submit = await tester.invokeSemanticAction(
      SemanticAction.submit,
      role: SemanticRole.form,
      label: 'Connection setup',
    );

    expect(submit.completed, isTrue);
    expect(submitted, isNotNull);
    expect(submitted!.valid, isTrue);
    expect(submitted!.values.text('project'), 'dune');

    final cancel = await tester.invokeSemanticAction(
      SemanticAction.cancel,
      role: SemanticRole.form,
      label: 'Connection setup',
    );

    expect(cancel.completed, isTrue);
    expect(cancelled, isTrue);
  });

  testWidgets('semantic submit waits for async form validation', (
    tester,
  ) async {
    final completer = Completer<String?>();
    final definition = _asyncProjectForm(
      validator: (value, values) => completer.future,
    );
    final controller = FormController(definition)..setValue('project', 'dune');
    FormSubmitResult? submitted;
    tester.pumpWidget(
      FormPanel(
        definition: definition,
        controller: controller,
        onSubmit: (result) => submitted = result,
      ),
    );

    final invocation = tester.invokeSemanticAction(
      SemanticAction.submit,
      role: SemanticRole.form,
      label: 'Async project',
    );
    await Future<void>.delayed(Duration.zero);
    tester.pump();

    var form = tester.semantics().single(role: SemanticRole.form);
    expect(form.busy, isTrue);
    expect(form.state['validating'], isTrue);
    expect(form.state['hasAsyncValidators'], isTrue);
    final field = tester.semantics().single(
      role: SemanticRole.formField,
      label: 'Project',
    );
    expect(field.busy, isTrue);
    expect(field.state['hasAsyncValidator'], isTrue);
    expect(
      tester
          .accessibilitySnapshot()
          .single(role: SemanticRole.formField, label: 'Project')
          .states,
      contains('async validation'),
    );

    completer.complete(null);
    final result = await invocation;
    tester.pump();

    expect(result.completed, isTrue);
    expect(submitted, isNotNull);
    expect(submitted!.valid, isTrue);
    form = tester.semantics().single(role: SemanticRole.form);
    expect(form.busy, isFalse);
  });

  testWidgets('wizard renders one form step at a time and gates navigation', (
    tester,
  ) async {
    final definition = _connectionForm();
    final formController = FormController(definition);
    final wizardController = FormWizardController();
    FormSubmitResult? submitted;
    var cancelled = false;
    tester.pumpWidget(
      FormWizard(
        definition: definition,
        steps: _connectionWizardSteps,
        controller: formController,
        wizardController: wizardController,
        onSubmit: (result) => submitted = result,
        onCancel: () => cancelled = true,
      ),
    );

    expect(_screen(tester), contains('Step 1/2: Identity'));
    var form = tester.semantics().single(
      role: SemanticRole.form,
      label: 'Connection setup',
      action: SemanticAction.increment,
    );
    expect(form.state['layout'], 'wizard');
    expect(form.state['fieldCount'], 5);
    expect(form.state['visibleFieldCount'], 3);
    expect(form.state['stepCount'], 2);
    expect(form.state['currentStepId'], 'identity');
    expect(form.state['canGoBack'], isFalse);
    expect(form.state['canGoForward'], isTrue);
    var fallback = tester.accessibilitySnapshot().single(
      role: SemanticRole.form,
      label: 'Connection setup',
      action: SemanticAction.increment,
    );
    var fallbackState = fallback.states.join('\n');
    expect(fallbackState, contains('layout wizard'));
    expect(fallbackState, contains('3 visible fields'));
    expect(fallbackState, contains('step 1 of 2'));
    expect(fallbackState, contains('current step Identity'));
    expect(fallbackState, contains('current step id identity'));
    expect(fallbackState, contains('can go forward'));
    expect(
      tester.semantics().where(role: SemanticRole.formField, label: 'Project'),
      hasLength(1),
    );
    expect(
      tester.semantics().where(role: SemanticRole.formField, label: 'API key'),
      isEmpty,
    );

    final blocked = await tester.invokeSemanticAction(
      SemanticAction.increment,
      role: SemanticRole.form,
      label: 'Connection setup',
    );
    tester.pump();

    expect(blocked.completed, isTrue);
    expect(wizardController.currentStepIndex, 0);
    expect(formController.error('project'), 'Project is required.');

    formController.setValue('project', 'dune');
    tester.pump();
    final next = await tester.invokeSemanticAction(
      SemanticAction.increment,
      role: SemanticRole.form,
      label: 'Connection setup',
    );
    tester.pump();

    expect(next.completed, isTrue);
    expect(wizardController.currentStepIndex, 1);
    expect(_screen(tester), contains('Step 2/2: Credentials'));
    form = tester.semantics().single(
      role: SemanticRole.form,
      label: 'Connection setup',
      action: SemanticAction.submit,
    );
    expect(form.actions, contains(SemanticAction.decrement));
    expect(form.state['currentStepId'], 'credentials');
    fallback = tester.accessibilitySnapshot().single(
      role: SemanticRole.form,
      label: 'Connection setup',
      action: SemanticAction.submit,
    );
    fallbackState = fallback.states.join('\n');
    expect(fallbackState, contains('2 visible fields'));
    expect(fallbackState, contains('step 2 of 2'));
    expect(fallbackState, contains('current step Credentials'));
    expect(fallbackState, contains('current step id credentials'));
    expect(fallbackState, contains('can go back'));
    expect(
      tester.semantics().where(role: SemanticRole.formField, label: 'Project'),
      isEmpty,
    );
    expect(
      tester.semantics().where(role: SemanticRole.formField, label: 'API key'),
      hasLength(1),
    );

    final invalidSubmit = await tester.invokeSemanticAction(
      SemanticAction.submit,
      role: SemanticRole.form,
      label: 'Connection setup',
    );
    tester.pump();

    expect(invalidSubmit.completed, isTrue);
    expect(submitted, isNotNull);
    expect(submitted!.valid, isFalse);
    expect(formController.snapshot.submitted, isTrue);

    formController
      ..setValue('apiKey', 'secret-token')
      ..setValue('confirm', true);
    tester.pump();
    final validSubmit = await tester.invokeSemanticAction(
      SemanticAction.submit,
      role: SemanticRole.form,
      label: 'Connection setup',
    );
    tester.pump();

    expect(validSubmit.completed, isTrue);
    expect(submitted!.valid, isTrue);
    expect(submitted!.values.text('project'), 'dune');

    final cancel = await tester.invokeSemanticAction(
      SemanticAction.cancel,
      role: SemanticRole.form,
      label: 'Connection setup',
    );
    expect(cancel.completed, isTrue);
    expect(cancelled, isTrue);
  });

  testWidgets('wizard next waits for async field validators', (tester) async {
    final completer = Completer<String?>();
    final definition = _asyncWizardForm(
      validator: (value, values) => completer.future,
    );
    final formController = FormController(definition)
      ..setValue('project', 'dune');
    final wizardController = FormWizardController();
    tester.pumpWidget(
      FormWizard(
        definition: definition,
        steps: _asyncWizardSteps,
        controller: formController,
        wizardController: wizardController,
      ),
    );

    final invocation = tester.invokeSemanticAction(
      SemanticAction.increment,
      role: SemanticRole.form,
      label: 'Async wizard',
    );
    await Future<void>.delayed(Duration.zero);
    tester.pump();

    var form = tester.semantics().single(role: SemanticRole.form);
    expect(form.busy, isTrue);
    expect(form.state['validating'], isTrue);
    expect(wizardController.currentStepIndex, 0);

    completer.complete(null);
    final result = await invocation;
    tester.pump();

    expect(result.completed, isTrue);
    expect(wizardController.currentStepIndex, 1);
    form = tester.semantics().single(role: SemanticRole.form);
    expect(form.busy, isFalse);
    expect(form.state['currentStepId'], 'confirm');
  });

  testWidgets('wizard requires every field to appear exactly once', (tester) {
    final definition = _connectionForm();

    expect(
      () => tester.pumpWidget(
        FormWizard(
          definition: definition,
          steps: const [
            FormWizardStep(
              id: 'partial',
              title: 'Partial',
              fieldIds: ['project'],
            ),
          ],
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Missing: environment, region, apiKey, confirm.'),
        ),
      ),
    );
  });

  testWidgets('semantic focus moves focus to the requested form field', (
    tester,
  ) async {
    final definition = _connectionForm();
    tester.pumpWidget(FormPanel(definition: definition, autofocus: false));

    final result = await tester.invokeSemanticAction(
      SemanticAction.focus,
      role: SemanticRole.formField,
      label: 'API key',
    );

    expect(result.completed, isTrue);
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.formField, label: 'API key')
          .focused,
      isTrue,
    );
  });

  testWidgets('validation errors surface through form-field semantics', (
    tester,
  ) {
    final definition = _connectionForm();
    final controller = FormController(definition);
    tester.pumpWidget(
      FormPanel(definition: definition, controller: controller),
    );

    final result = controller.submit();
    tester.pump();

    expect(result.valid, isFalse);
    final form = tester.semantics().single(role: SemanticRole.form);
    expect(form.state['errorCount'], 3);
    expect(form.state['submitted'], isTrue);
    expect(form.state['valid'], isFalse);

    final project = tester.semantics().single(
      role: SemanticRole.formField,
      label: 'Project',
      validationError: 'Project is required.',
    );
    expect(project.state['hasValue'], isFalse);

    final apiKey = tester.semantics().single(
      role: SemanticRole.formField,
      label: 'API key',
      validationError: 'API key is required.',
    );
    expect(apiKey.value, isNull);

    controller.setValue('project', 'dune');
    tester.pump();
    expect(controller.error('project'), isNull);
  });

  testWidgets('number fields render, clamp on submit, and expose semantics', (
    tester,
  ) {
    final definition = _numericForm();
    final controller = FormController(definition);
    FormSubmitResult? submitted;
    tester.pumpWidget(
      FormPanel(
        definition: definition,
        controller: controller,
        onSubmit: (result) => submitted = result,
      ),
    );

    expect(_screen(tester), contains('Retry limit *'));
    var retries = tester.semantics().single(
      role: SemanticRole.formField,
      label: 'Retry limit',
      value: '2',
    );
    expect(retries.state['fieldType'], 'number');
    expect(retries.state['min'], 0);
    expect(retries.state['max'], 5);
    expect(retries.state['allowNegative'], isFalse);
    expect(retries.state['allowDecimal'], isFalse);

    tester.type('9');
    expect(controller.value('retries'), 29);
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));

    expect(submitted, isNotNull);
    expect(submitted!.valid, isTrue);
    expect(submitted!.values['retries'], 5);
    tester.pump();
    retries = tester.semantics().single(
      role: SemanticRole.formField,
      label: 'Retry limit',
      value: '5',
    );
    expect(retries.state['hasValue'], isTrue);
  });

  testWidgets('date fields render through DatePicker and expose semantics', (
    tester,
  ) async {
    final definition = _dateForm();
    final controller = FormController(definition);
    tester.pumpWidget(
      FormPanel(definition: definition, controller: controller),
    );

    expect(_screen(tester), contains('Start date *'));
    final field = tester.semantics().single(
      role: SemanticRole.formField,
      label: 'Start date',
      value: '2024-03-15',
    );
    expect(field.state['fieldType'], 'date');
    expect(field.state['firstDate'], '2024-03-01');
    expect(field.state['lastDate'], '2024-03-31');
    expect(field.state['weekStartsOn'], 'monday');

    final picker = tester.semantics().single(
      role: SemanticRole.datePicker,
      label: 'Start date',
      value: '2024-03-15',
      action: SemanticAction.increment,
    );
    expect(picker.state['selectedDate'], '2024-03-15');

    final increment = await tester.invokeSemanticAction(
      SemanticAction.increment,
      role: SemanticRole.datePicker,
      label: 'Start date',
    );

    expect(increment.completed, isTrue);
    expect(controller.values.dateValue('start'), DateTime(2024, 3, 16));
    expect(
      tester
          .accessibilitySnapshot()
          .single(role: SemanticRole.formField, label: 'Start date')
          .states,
      contains('field type date'),
    );
  });

  testWidgets('multi-select fields render, toggle, and expose semantics', (
    tester,
  ) {
    final definition = _multiSelectForm();
    final controller = FormController(definition);
    tester.pumpWidget(
      FormPanel(definition: definition, controller: controller),
    );

    expect(_screen(tester), contains('[x] Logs'));
    expect(_screen(tester), contains('[ ] Metrics'));

    var field = tester.semantics().single(
      role: SemanticRole.formField,
      label: 'Capabilities',
      value: 'Logs',
    );
    expect(field.state['fieldType'], 'multiSelect');
    expect(field.state['optionCount'], 4);
    expect(field.state['selectedOptionCount'], 1);
    expect(field.state['minSelected'], 1);
    expect(field.state['maxSelected'], 2);

    tester.sendKey(const KeyEvent(keyCode: KeyCode.arrowDown));
    tester.sendKey(const KeyEvent(keyCode: KeyCode.enter));
    tester.pump();

    expect(controller.values.listValue('capabilities'), ['logs', 'metrics']);
    field = tester.semantics().single(
      role: SemanticRole.formField,
      label: 'Capabilities',
      value: 'Logs, Metrics',
    );
    expect(field.state['selectedOptionCount'], 2);
    expect(
      tester
          .accessibilitySnapshot()
          .single(role: SemanticRole.formField, label: 'Capabilities')
          .states,
      contains('2 selected'),
    );
  });

  testWidgets('path fields render through text input and expose semantics', (
    tester,
  ) {
    final temp = Directory.systemTemp.createTempSync('fleury_form_path_');
    try {
      final file = File('${temp.path}${Platform.pathSeparator}config.json')
        ..writeAsStringSync('{}');
      final definition = _pathForm(file.path);
      final controller = FormController(definition);
      tester.pumpWidget(
        FormPanel(
          definition: definition,
          controller: controller,
          fieldWidth: file.path.length + 2,
        ),
      );

      final field = tester.semantics().single(
        role: SemanticRole.formField,
        label: 'Config path',
        value: file.path,
      );
      expect(field.state['fieldType'], 'path');
      expect(field.state['pathKind'], 'file');
      expect(field.state['mustExist'], isTrue);
      expect(field.state['allowRelative'], isFalse);
      expect(
        tester
            .accessibilitySnapshot()
            .single(role: SemanticRole.formField, label: 'Config path')
            .states,
        contains('absolute path required'),
      );
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('prompt session uses the same definition, defaults, and validation', () {
    final session = FormPromptSession(definition: _connectionForm());

    expect(session.currentPrompt!.fieldId, 'project');
    expect(session.submitCurrent(''), isNull);
    expect(session.currentPrompt!.error, 'Project is required.');

    expect(session.submitCurrent('dune'), isNull);
    expect(session.currentPrompt!.fieldId, 'environment');
    expect(session.submitCurrent('Production'), isNull);
    expect(session.currentPrompt!.fieldId, 'region');
    expect(session.submitCurrent('eu-west-1'), isNull);
    expect(session.currentPrompt!.fieldId, 'apiKey');
    expect(session.currentPrompt!.redacted, isTrue);
    expect(session.submitCurrent('secret-token'), isNull);
    expect(session.currentPrompt!.fieldId, 'confirm');

    final result = session.submitCurrent('yes');
    expect(result, isNotNull);
    expect(result!.valid, isTrue);
    expect(result.values.text('project'), 'dune');
    expect(result.values['environment'], 'prod');
    expect(result.values['region'], 'eu-west-1');
    expect(result.values.boolValue('confirm'), isTrue);
    expect(session.completed, isTrue);
  });

  test('prompt session parses number fields through the shared definition', () {
    final session = FormPromptSession(definition: _numericForm());

    expect(session.currentPrompt!.fieldId, 'retries');
    expect(session.submitCurrent('bad'), isNull);
    expect(session.currentPrompt!.error, 'Enter a whole number.');
    expect(session.submitCurrent('4'), isNull);
    expect(session.currentPrompt!.fieldId, 'ratio');
    expect(session.submitCurrent('2.25'), isNotNull);
    expect(session.result!.valid, isTrue);
    expect(session.result!.values['retries'], 4);
    expect(session.result!.values['ratio'], 2.25);

    final accessibility = session.accessibilitySnapshot;
    expect(
      accessibility
          .single(role: SemanticRole.formField, label: 'Backoff ratio')
          .value,
      '2.25',
    );
  });

  test('prompt session parses date fields through the shared definition', () {
    final session = FormPromptSession(definition: _dateForm());

    expect(session.currentPrompt!.fieldId, 'start');
    expect(session.submitCurrent('bad'), isNull);
    expect(session.currentPrompt!.error, 'Enter a date as YYYY-MM-DD.');
    expect(session.submitCurrent('2024-04-01'), isNull);
    expect(
      session.currentPrompt!.error,
      'Start date must be on or before 2024-03-31.',
    );
    final result = session.submitCurrent('2024-03-20');
    expect(result, isNotNull);
    expect(result!.valid, isTrue);
    expect(result.values.dateValue('start'), DateTime(2024, 3, 20));

    final accessibility = session.accessibilitySnapshot;
    expect(
      accessibility
          .single(role: SemanticRole.formField, label: 'Start date')
          .value,
      '2024-03-20',
    );
  });

  test('prompt session parses path fields through the shared definition', () {
    final temp = Directory.systemTemp.createTempSync('fleury_form_path_');
    try {
      final file = File('${temp.path}${Platform.pathSeparator}config.json')
        ..writeAsStringSync('{}');
      final session = FormPromptSession(definition: _pathForm(file.path));

      expect(session.currentPrompt!.fieldId, 'configPath');
      expect(session.submitCurrent('relative/config.json'), isNull);
      expect(
        session.currentPrompt!.error,
        'Config path must be an absolute path.',
      );

      final result = session.submitCurrent(file.path);
      expect(result, isNotNull);
      expect(result!.valid, isTrue);
      expect(result.values.path('configPath'), file.path);

      final accessibility = session.accessibilitySnapshot;
      final field = accessibility.single(
        role: SemanticRole.formField,
        label: 'Config path',
      );
      expect(field.value, file.path);
      expect(field.states, contains('path kind file'));
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test(
    'prompt session awaits async validators through the shared definition',
    () async {
      final definition = _asyncProjectForm(
        validator: (value, values) async =>
            value == 'taken' ? 'Project is already claimed.' : null,
      );
      final session = FormPromptSession(definition: definition);

      expect(session.currentPrompt!.fieldId, 'project');
      expect(await session.submitCurrentAsync('taken'), isNull);
      expect(session.currentPrompt!.error, 'Project is already claimed.');

      final result = await session.submitCurrentAsync('fleury');
      expect(result, isNotNull);
      expect(result!.valid, isTrue);
      expect(result.values.text('project'), 'fleury');
      expect(session.completed, isTrue);
    },
  );

  test(
    'prompt session parses multi-select fields through the shared definition',
    () {
      final session = FormPromptSession(definition: _multiSelectForm());

      expect(session.currentPrompt!.fieldId, 'capabilities');
      expect(session.submitCurrent('Deploy'), isNull);
      expect(
        session.currentPrompt!.error,
        'Choose one or more listed options.',
      );

      final result = session.submitCurrent('Metrics, Traces');
      expect(result, isNotNull);
      expect(result!.valid, isTrue);
      expect(result.values.listValue('capabilities'), ['metrics', 'traces']);

      final accessibility = session.accessibilitySnapshot;
      final field = accessibility.single(
        role: SemanticRole.formField,
        label: 'Capabilities',
      );
      expect(field.value, 'Metrics, Traces');
      expect(field.states, contains('2 selected'));
    },
  );

  test('prompt session exposes semantic and accessibility fallback state', () {
    final session = FormPromptSession(definition: _connectionForm());

    var tree = session.semanticTree;
    var form = tree.single(
      role: SemanticRole.form,
      label: 'Connection setup',
      action: SemanticAction.submit,
    );
    expect(form.actions, contains(SemanticAction.cancel));
    expect(form.state['layout'], 'prompt');
    expect(form.state['activeFieldId'], 'project');

    var project = tree.single(
      role: SemanticRole.formField,
      label: 'Project',
      selected: true,
    );
    expect(project.state['activePrompt'], isTrue);
    expect(project.state['promptPosition'], 1);
    expect(project.state['promptCount'], 5);

    var accessibility = session.accessibilitySnapshot;
    var prompt = accessibility.single(
      role: SemanticRole.formField,
      label: 'Project',
    );
    expect(prompt.states, contains('active prompt'));
    expect(prompt.states, contains('prompt 1 of 5'));
    expect(prompt.states, contains('required'));
    expect(accessibility.toPlainText(), contains('layout prompt'));

    expect(session.submitCurrent(''), isNull);
    accessibility = session.accessibilitySnapshot;
    prompt = accessibility.single(
      role: SemanticRole.formField,
      label: 'Project',
    );
    expect(prompt.validationError, 'Project is required.');
    expect(prompt.announcement, contains('error: Project is required.'));

    expect(session.submitCurrent('dune'), isNull);
    expect(session.submitCurrent('Production'), isNull);
    accessibility = session.accessibilitySnapshot;
    final environment = accessibility.single(
      role: SemanticRole.formField,
      label: 'Environment',
    );
    expect(environment.value, 'Production');

    expect(session.submitCurrent('eu-west-1'), isNull);
    expect(session.currentPrompt!.fieldId, 'apiKey');
    expect(session.submitCurrent('secret-token'), isNull);
    accessibility = session.accessibilitySnapshot;
    final apiKey = accessibility.single(
      role: SemanticRole.formField,
      label: 'API key',
    );
    expect(apiKey.value, isNull);
    expect(apiKey.states, contains('secret'));
    expect(apiKey.states, contains('value redacted'));
    expect(accessibility.toPlainText(), isNot(contains('secret-token')));

    final result = session.submitCurrent('yes');
    expect(result, isNotNull);
    form = session.semanticTree.single(role: SemanticRole.form);
    expect(form.state['completed'], isTrue);
    expect(form.actions, isEmpty);
  });

  testWidgets('inline layout keeps the same semantic contract', (tester) {
    final definition = _connectionForm();
    tester.pumpWidget(
      FormPanel(definition: definition, layout: FormPanelLayout.inline),
    );

    final output = _screen(tester);
    expect(output, contains('Project *:'));
    expect(output, contains('Environment *:'));

    final form = tester.semantics().single(role: SemanticRole.form);
    expect(form.state['layout'], 'inline');
    expect(form.state['fieldCount'], 5);
  });
}
