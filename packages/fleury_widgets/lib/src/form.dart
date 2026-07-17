import 'dart:async' show FutureOr, unawaited;

import 'package:fleury/fleury_core.dart';

// The path-field `mustExist` check is the Form's only platform coupling. A
// conditional import swaps in the native (dart:io) probe when available and the
// web stub otherwise, so the whole FormPanel compiles to JavaScript.
import 'form_path_probe.dart' if (dart.library.io) 'form_path_probe_io.dart';

import 'calendar_heatmap.dart' show CalendarWeekStart;
import 'controls.dart' show Button, ButtonVariant, Checkbox;
import 'date_picker.dart' show DatePicker;
import 'number_input.dart' show NumberInput;
import 'password_input.dart' show PasswordInput;
import 'select.dart' show Select, SelectOption;

enum FormFieldType {
  text,
  number,
  date,
  path,
  secret,
  select,
  multiSelect,
  checkbox,
}

enum FormPanelLayout { fullScreen, inline }

enum FormPathKind { any, file, directory }

typedef FormFieldValidator = String? Function(Object? value, FormValues values);
typedef FormFieldAsyncValidator =
    FutureOr<String?> Function(Object? value, FormValues values);

final class FormOption {
  const FormOption({
    required this.value,
    required this.label,
    this.enabled = true,
  });

  final Object? value;
  final String label;
  final bool enabled;
}

final class FormFieldSpec {
  const FormFieldSpec._({
    required this.id,
    required this.label,
    required this.type,
    required this.initialValue,
    this.placeholder = '',
    this.options = const [],
    this.required = false,
    this.min,
    this.max,
    this.allowNegative = true,
    this.allowDecimal = false,
    this.firstDate,
    this.lastDate,
    this.weekStartsOn = CalendarWeekStart.sunday,
    this.pathKind = FormPathKind.any,
    this.mustExist = false,
    this.allowRelative = true,
    this.minSelected,
    this.maxSelected,
    this.validator,
    this.asyncValidator,
  });

  factory FormFieldSpec.text({
    required String id,
    required String label,
    String initialValue = '',
    String placeholder = '',
    bool required = false,
    FormFieldValidator? validator,
    FormFieldAsyncValidator? asyncValidator,
  }) {
    return FormFieldSpec._(
      id: id,
      label: label,
      type: FormFieldType.text,
      initialValue: initialValue,
      placeholder: placeholder,
      required: required,
      validator: validator,
      asyncValidator: asyncValidator,
    );
  }

  factory FormFieldSpec.secret({
    required String id,
    required String label,
    String initialValue = '',
    String placeholder = '',
    bool required = false,
    FormFieldValidator? validator,
    FormFieldAsyncValidator? asyncValidator,
  }) {
    return FormFieldSpec._(
      id: id,
      label: label,
      type: FormFieldType.secret,
      initialValue: initialValue,
      placeholder: placeholder,
      required: required,
      validator: validator,
      asyncValidator: asyncValidator,
    );
  }

  factory FormFieldSpec.number({
    required String id,
    required String label,
    num? initialValue,
    String placeholder = '',
    bool required = false,
    num? min,
    num? max,
    bool allowNegative = true,
    bool allowDecimal = false,
    FormFieldValidator? validator,
    FormFieldAsyncValidator? asyncValidator,
  }) {
    return FormFieldSpec._(
      id: id,
      label: label,
      type: FormFieldType.number,
      initialValue: initialValue,
      placeholder: placeholder,
      required: required,
      min: min,
      max: max,
      allowNegative: allowNegative,
      allowDecimal: allowDecimal,
      validator: validator,
      asyncValidator: asyncValidator,
    );
  }

  factory FormFieldSpec.date({
    required String id,
    required String label,
    required DateTime initialValue,
    String placeholder = 'YYYY-MM-DD',
    bool required = false,
    DateTime? firstDate,
    DateTime? lastDate,
    CalendarWeekStart weekStartsOn = CalendarWeekStart.sunday,
    FormFieldValidator? validator,
    FormFieldAsyncValidator? asyncValidator,
  }) {
    return FormFieldSpec._(
      id: id,
      label: label,
      type: FormFieldType.date,
      initialValue: _dateOnly(initialValue),
      placeholder: placeholder,
      required: required,
      firstDate: firstDate == null ? null : _dateOnly(firstDate),
      lastDate: lastDate == null ? null : _dateOnly(lastDate),
      weekStartsOn: weekStartsOn,
      validator: validator,
      asyncValidator: asyncValidator,
    );
  }

  factory FormFieldSpec.path({
    required String id,
    required String label,
    String initialValue = '',
    String placeholder = 'path/to/file',
    bool required = false,
    FormPathKind pathKind = FormPathKind.any,
    bool mustExist = false,
    bool allowRelative = true,
    FormFieldValidator? validator,
    FormFieldAsyncValidator? asyncValidator,
  }) {
    return FormFieldSpec._(
      id: id,
      label: label,
      type: FormFieldType.path,
      initialValue: initialValue,
      placeholder: placeholder,
      required: required,
      pathKind: pathKind,
      mustExist: mustExist,
      allowRelative: allowRelative,
      validator: validator,
      asyncValidator: asyncValidator,
    );
  }

  factory FormFieldSpec.select({
    required String id,
    required String label,
    required List<FormOption> options,
    Object? initialValue,
    String placeholder = 'Select...',
    bool required = false,
    FormFieldValidator? validator,
    FormFieldAsyncValidator? asyncValidator,
  }) {
    return FormFieldSpec._(
      id: id,
      label: label,
      type: FormFieldType.select,
      initialValue: initialValue,
      placeholder: placeholder,
      options: List<FormOption>.unmodifiable(options),
      required: required,
      validator: validator,
      asyncValidator: asyncValidator,
    );
  }

  factory FormFieldSpec.multiSelect({
    required String id,
    required String label,
    required List<FormOption> options,
    List<Object?> initialValues = const <Object?>[],
    String placeholder = 'Select one or more...',
    bool required = false,
    int? minSelected,
    int? maxSelected,
    FormFieldValidator? validator,
    FormFieldAsyncValidator? asyncValidator,
  }) {
    return FormFieldSpec._(
      id: id,
      label: label,
      type: FormFieldType.multiSelect,
      initialValue: List<Object?>.unmodifiable(initialValues),
      placeholder: placeholder,
      options: List<FormOption>.unmodifiable(options),
      required: required,
      minSelected: minSelected,
      maxSelected: maxSelected,
      validator: validator,
      asyncValidator: asyncValidator,
    );
  }

  factory FormFieldSpec.checkbox({
    required String id,
    required String label,
    bool initialValue = false,
    bool required = false,
    FormFieldValidator? validator,
    FormFieldAsyncValidator? asyncValidator,
  }) {
    return FormFieldSpec._(
      id: id,
      label: label,
      type: FormFieldType.checkbox,
      initialValue: initialValue,
      required: required,
      validator: validator,
      asyncValidator: asyncValidator,
    );
  }

  final String id;
  final String label;
  final FormFieldType type;
  final Object? initialValue;
  final String placeholder;
  final List<FormOption> options;
  final bool required;
  final num? min;
  final num? max;
  final bool allowNegative;
  final bool allowDecimal;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final CalendarWeekStart weekStartsOn;
  final FormPathKind pathKind;
  final bool mustExist;
  final bool allowRelative;
  final int? minSelected;
  final int? maxSelected;
  final FormFieldValidator? validator;
  final FormFieldAsyncValidator? asyncValidator;

  bool get redacted => type == FormFieldType.secret;
}

final class FormDefinition {
  FormDefinition({
    required List<FormFieldSpec> fields,
    this.title = 'Form',
    this.submitLabel = 'Submit',
    this.cancelLabel = 'Cancel',
    this.showCancel = true,
  }) : fields = List<FormFieldSpec>.unmodifiable(fields);

  final String title;
  final List<FormFieldSpec> fields;
  final String submitLabel;
  final String cancelLabel;
  final bool showCancel;

  bool get hasAsyncValidators =>
      fields.any((field) => field.asyncValidator != null);

  FormFieldSpec field(String id) {
    for (final field in fields) {
      if (field.id == id) return field;
    }
    throw StateError('Unknown form field "$id".');
  }
}

final class FormWizardStep {
  const FormWizardStep({
    required this.id,
    required this.title,
    required this.fieldIds,
    this.description = '',
  });

  final String id;
  final String title;
  final String description;
  final List<String> fieldIds;
}

class FormWizardController extends ChangeNotifier {
  FormWizardController({int initialStepIndex = 0})
    : _currentStepIndex = initialStepIndex < 0 ? 0 : initialStepIndex;

  int _currentStepIndex;
  bool _disposed = false;

  int get currentStepIndex => _currentStepIndex;

  bool get canGoBack => _currentStepIndex > 0;

  bool canGoNext({required int stepCount}) =>
      stepCount > 0 && _currentStepIndex < stepCount - 1;

  bool goTo(int stepIndex, {required int stepCount}) {
    _checkNotDisposed();
    if (stepCount <= 0) return false;
    final next = stepIndex.clamp(0, stepCount - 1).toInt();
    if (next == _currentStepIndex) return false;
    _currentStepIndex = next;
    notifyListeners();
    return true;
  }

  bool next({required int stepCount}) {
    _checkNotDisposed();
    if (!canGoNext(stepCount: stepCount)) return false;
    _currentStepIndex += 1;
    notifyListeners();
    return true;
  }

  bool previous() {
    _checkNotDisposed();
    if (!canGoBack) return false;
    _currentStepIndex -= 1;
    notifyListeners();
    return true;
  }

  void reset({int stepIndex = 0, required int stepCount}) {
    _checkNotDisposed();
    final next = stepCount <= 0 ? 0 : stepIndex.clamp(0, stepCount - 1).toInt();
    if (next == _currentStepIndex) return;
    _currentStepIndex = next;
    notifyListeners();
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('FormWizardController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

final class FormValues {
  FormValues(Map<String, Object?> values)
    : _values = Map<String, Object?>.unmodifiable(values);

  final Map<String, Object?> _values;

  Map<String, Object?> get asMap => Map.unmodifiable(_values);

  Object? operator [](String fieldId) => _values[fieldId];

  String text(String fieldId) => (_values[fieldId] ?? '').toString();

  bool boolValue(String fieldId) => _values[fieldId] == true;

  DateTime? dateValue(String fieldId) => _parseDateValue(_values[fieldId]);

  String path(String fieldId) => (_values[fieldId] ?? '').toString();

  List<Object?> listValue(String fieldId) =>
      _multiSelectValues(_values[fieldId]);
}

final class FormSnapshot {
  FormSnapshot._({
    required this.title,
    required this.submitLabel,
    required this.cancelLabel,
    required this.showCancel,
    required List<FormFieldSnapshot> fields,
    required Map<String, String> errors,
    required this.dirty,
    required this.submitted,
    required this.validating,
    required this.hasAsyncValidators,
  }) : fields = List<FormFieldSnapshot>.unmodifiable(fields),
       errors = Map<String, String>.unmodifiable(errors);

  factory FormSnapshot._from(
    FormDefinition definition,
    Map<String, Object?> values,
    Map<String, String> errors, {
    required Set<String> validatingFieldIds,
    required bool dirty,
    required bool submitted,
  }) {
    return FormSnapshot._(
      title: definition.title,
      submitLabel: definition.submitLabel,
      cancelLabel: definition.cancelLabel,
      showCancel: definition.showCancel,
      fields: [
        for (final field in definition.fields)
          FormFieldSnapshot._from(
            field,
            value: values[field.id],
            error: errors[field.id],
            validating: validatingFieldIds.contains(field.id),
          ),
      ],
      errors: errors,
      dirty: dirty,
      submitted: submitted,
      validating: validatingFieldIds.isNotEmpty,
      hasAsyncValidators: definition.hasAsyncValidators,
    );
  }

  final String title;
  final String submitLabel;
  final String cancelLabel;
  final bool showCancel;
  final List<FormFieldSnapshot> fields;
  final Map<String, String> errors;
  final bool dirty;
  final bool submitted;
  final bool validating;
  final bool hasAsyncValidators;

  int get fieldCount => fields.length;
  int get errorCount => errors.length;
  bool get valid => errors.isEmpty && !validating;

  Map<String, Object?> get safeValueMap {
    return Map<String, Object?>.unmodifiable({
      for (final field in fields) field.id: field.value,
    });
  }

  FormFieldSnapshot field(String id) {
    for (final field in fields) {
      if (field.id == id) return field;
    }
    throw StateError('Unknown form field "$id".');
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'title': title,
      'submitLabel': submitLabel,
      'cancelLabel': cancelLabel,
      'showCancel': showCancel,
      'fieldCount': fieldCount,
      'errorCount': errorCount,
      'dirty': dirty,
      'submitted': submitted,
      'validating': validating,
      'hasAsyncValidators': hasAsyncValidators,
      'valid': valid,
      'fields': <Object?>[for (final field in fields) field.toJson()],
      if (errors.isNotEmpty) 'errors': errors,
    };
  }
}

final class FormFieldSnapshot {
  FormFieldSnapshot._({
    required this.id,
    required this.label,
    required this.type,
    required this.value,
    required this.displayValue,
    required this.placeholder,
    required List<FormOption> options,
    required this.required,
    required this.min,
    required this.max,
    required this.allowNegative,
    required this.allowDecimal,
    required this.firstDate,
    required this.lastDate,
    required this.weekStartsOn,
    required this.pathKind,
    required this.mustExist,
    required this.allowRelative,
    required this.minSelected,
    required this.maxSelected,
    required this.hasAsyncValidator,
    required this.validating,
    required this.redacted,
    required this.hasValue,
    required this.error,
  }) : options = List<FormOption>.unmodifiable(options);

  factory FormFieldSnapshot._from(
    FormFieldSpec field, {
    required Object? value,
    required String? error,
    required bool validating,
  }) {
    return FormFieldSnapshot._(
      id: field.id,
      label: field.label,
      type: field.type,
      value: field.redacted ? null : value,
      displayValue: _displayFormValue(field, value),
      placeholder: field.placeholder,
      options: field.options,
      required: field.required,
      min: field.min,
      max: field.max,
      allowNegative: field.allowNegative,
      allowDecimal: field.allowDecimal,
      firstDate: field.firstDate,
      lastDate: field.lastDate,
      weekStartsOn: field.weekStartsOn,
      pathKind: field.pathKind,
      mustExist: field.mustExist,
      allowRelative: field.allowRelative,
      minSelected: field.minSelected,
      maxSelected: field.maxSelected,
      hasAsyncValidator: field.asyncValidator != null,
      validating: validating,
      redacted: field.redacted,
      hasValue: !_isFormValueEmpty(field, value),
      error: error,
    );
  }

  final String id;
  final String label;
  final FormFieldType type;

  /// The current machine value when it is safe to expose.
  ///
  /// Secret fields return `null` here. Use [FormController.values] when app
  /// code intentionally needs raw values for submission.
  final Object? value;

  /// The current human-facing value when it is safe to expose.
  ///
  /// Select fields use the option label, checkboxes use `yes`/`no`, and secret
  /// fields return `null`.
  final String? displayValue;
  final String placeholder;
  final List<FormOption> options;
  final bool required;
  final num? min;
  final num? max;
  final bool allowNegative;
  final bool allowDecimal;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final CalendarWeekStart weekStartsOn;
  final FormPathKind pathKind;
  final bool mustExist;
  final bool allowRelative;
  final int? minSelected;
  final int? maxSelected;
  final bool hasAsyncValidator;
  final bool validating;
  final bool redacted;
  final bool hasValue;
  final String? error;

  int get optionCount => options.length;
  int get enabledOptionCount =>
      options.where((option) => option.enabled).length;
  int get selectedOptionCount =>
      type == FormFieldType.multiSelect ? _multiSelectValues(value).length : 0;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'type': type.name,
      if (value != null && type != FormFieldType.date) 'value': value,
      if (displayValue != null) 'displayValue': displayValue,
      if (placeholder.isNotEmpty) 'placeholder': placeholder,
      'required': required,
      if (type == FormFieldType.number && min != null) 'min': min,
      if (type == FormFieldType.number && max != null) 'max': max,
      if (type == FormFieldType.number) 'allowNegative': allowNegative,
      if (type == FormFieldType.number) 'allowDecimal': allowDecimal,
      if (type == FormFieldType.date && value != null)
        'value': _dateDisplayValue(value),
      if (type == FormFieldType.date && firstDate != null)
        'firstDate': _formatDate(firstDate!),
      if (type == FormFieldType.date && lastDate != null)
        'lastDate': _formatDate(lastDate!),
      if (type == FormFieldType.date) 'weekStartsOn': weekStartsOn.name,
      if (type == FormFieldType.path) 'pathKind': pathKind.name,
      if (type == FormFieldType.path) 'mustExist': mustExist,
      if (type == FormFieldType.path) 'allowRelative': allowRelative,
      if (type == FormFieldType.multiSelect)
        'selectedOptionCount': selectedOptionCount,
      if (type == FormFieldType.multiSelect && minSelected != null)
        'minSelected': minSelected,
      if (type == FormFieldType.multiSelect && maxSelected != null)
        'maxSelected': maxSelected,
      if (hasAsyncValidator) 'hasAsyncValidator': true,
      if (validating) 'validating': true,
      'redacted': redacted,
      if (redacted) 'valueRedacted': true,
      'hasValue': hasValue,
      if (error != null) 'error': error,
      if (options.isNotEmpty) 'optionCount': optionCount,
      if (options.isNotEmpty) 'enabledOptionCount': enabledOptionCount,
    };
  }
}

final class FormSubmitResult {
  const FormSubmitResult({
    required this.valid,
    required this.values,
    required this.errors,
  });

  final bool valid;
  final FormValues values;
  final Map<String, String> errors;
}

class FormController extends ChangeNotifier {
  FormController(this.definition) {
    for (final field in definition.fields) {
      _values[field.id] = _normalizeFormValue(field, field.initialValue);
    }
  }

  final FormDefinition definition;
  final Map<String, Object?> _values = <String, Object?>{};
  final Map<String, String> _errors = <String, String>{};
  final Set<String> _validatingFieldIds = <String>{};
  bool _dirty = false;
  bool _submitted = false;
  int _validationGeneration = 0;
  bool _disposed = false;

  FormValues get values => FormValues(_values);
  Map<String, String> get errors => Map.unmodifiable(_errors);
  Set<String> get validatingFieldIds => Set.unmodifiable(_validatingFieldIds);
  FormSnapshot get snapshot => FormSnapshot._from(
    definition,
    _values,
    _errors,
    validatingFieldIds: _validatingFieldIds,
    dirty: _dirty,
    submitted: _submitted,
  );
  bool get dirty => _dirty;
  bool get submitted => _submitted;
  bool get validating => _validatingFieldIds.isNotEmpty;
  bool get hasAsyncValidators => definition.hasAsyncValidators;

  Object? value(String fieldId) => _values[fieldId];

  String? error(String fieldId) => _errors[fieldId];
  bool fieldValidating(String fieldId) => _validatingFieldIds.contains(fieldId);

  void setError(String fieldId, String error) {
    _checkNotDisposed();
    definition.field(fieldId);
    _errors[fieldId] = error;
    _validatingFieldIds.remove(fieldId);
    notifyListeners();
  }

  void setValue(String fieldId, Object? value) {
    _checkNotDisposed();
    final field = definition.field(fieldId);
    final normalized = _normalizeFormValue(field, value);
    if (_values[fieldId] == normalized) return;
    _validationGeneration += 1;
    _values[fieldId] = normalized;
    _validatingFieldIds.clear();
    _dirty = true;
    if (_errors.containsKey(fieldId)) {
      final nextError = _validateField(field);
      if (nextError == null) {
        _errors.remove(fieldId);
      } else {
        _errors[fieldId] = nextError;
      }
    }
    notifyListeners();
  }

  void reset({Map<String, Object?> values = const <String, Object?>{}}) {
    _checkNotDisposed();
    for (final fieldId in values.keys) {
      definition.field(fieldId);
    }
    _values
      ..clear()
      ..addEntries(
        definition.fields.map(
          (field) => MapEntry(
            field.id,
            _normalizeFormValue(
              field,
              values.containsKey(field.id)
                  ? values[field.id]
                  : field.initialValue,
            ),
          ),
        ),
      );
    _errors.clear();
    _validatingFieldIds.clear();
    _validationGeneration += 1;
    _dirty = false;
    _submitted = false;
    notifyListeners();
  }

  bool validate() {
    _checkNotDisposed();
    _validationGeneration += 1;
    _validatingFieldIds.clear();
    _errors.clear();
    for (final field in definition.fields) {
      final error = _validateField(field);
      if (error != null) _errors[field.id] = error;
    }
    notifyListeners();
    return _errors.isEmpty;
  }

  String? validateField(String fieldId) {
    _checkNotDisposed();
    _validationGeneration += 1;
    final field = definition.field(fieldId);
    _validatingFieldIds.remove(field.id);
    final error = _validateField(field);
    if (error == null) {
      _errors.remove(field.id);
    } else {
      _errors[field.id] = error;
    }
    notifyListeners();
    return error;
  }

  FormSubmitResult submit() {
    _checkNotDisposed();
    _submitted = true;
    final valid = validate();
    return FormSubmitResult(valid: valid, values: values, errors: errors);
  }

  Future<bool> validateAsync() async {
    _checkNotDisposed();
    validate();
    final pending = <FormFieldSpec>[
      for (final field in definition.fields)
        if (field.asyncValidator != null && !_errors.containsKey(field.id))
          field,
    ];
    if (pending.isEmpty) return _errors.isEmpty;

    final generation = ++_validationGeneration;
    final valuesSnapshot = values;
    _validatingFieldIds
      ..clear()
      ..addAll(pending.map((field) => field.id));
    notifyListeners();

    final results = await Future.wait(
      pending.map((field) => _validateFieldAsyncAgainst(field, valuesSnapshot)),
    );
    if (_disposed || generation != _validationGeneration) {
      return _errors.isEmpty;
    }

    for (final result in results) {
      if (result.error == null) {
        _errors.remove(result.fieldId);
      } else {
        _errors[result.fieldId] = result.error!;
      }
    }
    _validatingFieldIds.clear();
    notifyListeners();
    return _errors.isEmpty;
  }

  Future<String?> validateFieldAsync(String fieldId) async {
    _checkNotDisposed();
    final field = definition.field(fieldId);
    final syncError = validateField(field.id);
    if (syncError != null || field.asyncValidator == null) return syncError;

    final generation = ++_validationGeneration;
    final valuesSnapshot = values;
    _validatingFieldIds
      ..clear()
      ..add(field.id);
    notifyListeners();

    final result = await _validateFieldAsyncAgainst(field, valuesSnapshot);
    if (_disposed || generation != _validationGeneration) {
      return _errors[field.id];
    }

    if (result.error == null) {
      _errors.remove(field.id);
    } else {
      _errors[field.id] = result.error!;
    }
    _validatingFieldIds.remove(field.id);
    notifyListeners();
    return result.error;
  }

  Future<FormSubmitResult> submitAsync() async {
    _checkNotDisposed();
    _submitted = true;
    notifyListeners();
    final valid = await validateAsync();
    return FormSubmitResult(valid: valid, values: values, errors: errors);
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('FormController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _validationGeneration += 1;
    _validatingFieldIds.clear();
    super.dispose();
  }

  Future<_AsyncValidationResult> _validateFieldAsyncAgainst(
    FormFieldSpec field,
    FormValues values,
  ) async {
    try {
      final error = await field.asyncValidator?.call(values[field.id], values);
      return _AsyncValidationResult(field.id, error);
    } catch (_) {
      return _AsyncValidationResult(
        field.id,
        '${field.label} validation failed.',
      );
    }
  }

  String? _validateField(FormFieldSpec field) {
    final value = _values[field.id];
    if (field.required && _isFormValueEmpty(field, value)) {
      if (field.type == FormFieldType.checkbox) {
        return '${field.label} must be accepted.';
      }
      return '${field.label} is required.';
    }
    if (field.type == FormFieldType.number &&
        !_isFormValueEmpty(field, value)) {
      final parsed = _parseNumberValue(field, value);
      if (parsed == null) {
        return field.allowDecimal
            ? '${field.label} must be a number.'
            : '${field.label} must be a whole number.';
      }
      if (field.min != null && parsed < field.min!) {
        return '${field.label} must be at least ${field.min}.';
      }
      if (field.max != null && parsed > field.max!) {
        return '${field.label} must be at most ${field.max}.';
      }
    }
    if (field.type == FormFieldType.date && !_isFormValueEmpty(field, value)) {
      final parsed = _parseDateValue(value);
      if (parsed == null) {
        return '${field.label} must be a date in YYYY-MM-DD format.';
      }
      if (field.firstDate != null && parsed.isBefore(field.firstDate!)) {
        return '${field.label} must be on or after ${_formatDate(field.firstDate!)}.';
      }
      if (field.lastDate != null && parsed.isAfter(field.lastDate!)) {
        return '${field.label} must be on or before ${_formatDate(field.lastDate!)}.';
      }
    }
    if (field.type == FormFieldType.path && !_isFormValueEmpty(field, value)) {
      final path = value.toString().trim();
      if (!field.allowRelative && !_isAbsolutePath(path)) {
        return '${field.label} must be an absolute path.';
      }
      if (field.mustExist) {
        // Native probes the filesystem; on the web this is a no-op (a browser
        // can't see the server's files), so `mustExist` is skipped there.
        final error = probeFormPathExistence(
          path: path,
          requireFile: field.pathKind == FormPathKind.file,
          requireDirectory: field.pathKind == FormPathKind.directory,
          label: field.label,
        );
        if (error != null) return error;
      }
    }
    if (field.type == FormFieldType.multiSelect) {
      final selected = _multiSelectValues(value);
      if (field.minSelected != null && selected.length < field.minSelected!) {
        return '${field.label} must include at least ${field.minSelected} options.';
      }
      if (field.maxSelected != null && selected.length > field.maxSelected!) {
        return '${field.label} must include at most ${field.maxSelected} options.';
      }
      for (final value in selected) {
        final option = _formOptionForValue(field, value);
        if (option == null) {
          return '${field.label} includes an unknown option.';
        }
        if (!option.enabled) {
          return '${field.label} includes a disabled option.';
        }
      }
    }
    return field.validator?.call(value, values);
  }
}

final class _AsyncValidationResult {
  const _AsyncValidationResult(this.fieldId, this.error);

  final String fieldId;
  final String? error;
}

final class FormPrompt {
  const FormPrompt({required this.field, required this.value, this.error});

  final FormFieldSpec field;
  final Object? value;
  final String? error;

  String get label => field.label;
  String get fieldId => field.id;
  bool get required => field.required;
  bool get redacted => field.redacted;
  List<FormOption> get options => field.options;
}

class FormPromptSession {
  FormPromptSession({required this.definition, FormController? controller})
    : controller = controller ?? FormController(definition);

  final FormDefinition definition;
  final FormController controller;
  int _index = 0;
  bool _cancelled = false;
  FormSubmitResult? _result;

  bool get cancelled => _cancelled;
  bool get completed => _result != null;
  FormSubmitResult? get result => _result;

  /// Semantic representation of the prompt-mode form projection.
  ///
  /// This mirrors [FormPanel]'s roles and redaction behavior so prompt-mode
  /// fallback, tests, and future adapters use the same meaning layer as the
  /// visual form.
  SemanticTree get semanticTree {
    return SemanticTree(
      root: SemanticNode(
        id: const SemanticNodeId('form-prompt-root'),
        role: SemanticRole.app,
        children: [_semanticFormNode()],
      ),
    );
  }

  /// Text-first accessibility/fallback snapshot for the current prompt state.
  AccessibilitySnapshot get accessibilitySnapshot =>
      semanticTree.toAccessibilitySnapshot();

  FormPrompt? get currentPrompt {
    if (_cancelled || completed || _index >= definition.fields.length) {
      return null;
    }
    final field = definition.fields[_index];
    return FormPrompt(
      field: field,
      value: controller.value(field.id),
      error: controller.error(field.id),
    );
  }

  FormSubmitResult? submitCurrent(String input) {
    final prompt = currentPrompt;
    if (prompt == null) return _result;
    final parsed = _parseInput(prompt.field, input);
    if (parsed._error != null) {
      controller.setError(prompt.field.id, parsed._error);
      return null;
    }
    controller.setValue(prompt.field.id, parsed.value);
    final error = controller.validateField(prompt.field.id);
    if (error != null) return null;
    _index += 1;
    if (_index >= definition.fields.length) {
      _result = controller.submit();
      return _result;
    }
    return null;
  }

  Future<FormSubmitResult?> submitCurrentAsync(String input) async {
    final prompt = currentPrompt;
    if (prompt == null) return _result;
    final parsed = _parseInput(prompt.field, input);
    if (parsed._error != null) {
      controller.setError(prompt.field.id, parsed._error);
      return null;
    }
    controller.setValue(prompt.field.id, parsed.value);
    final error = await controller.validateFieldAsync(prompt.field.id);
    if (error != null) return null;
    _index += 1;
    if (_index >= definition.fields.length) {
      _result = await controller.submitAsync();
      return _result;
    }
    return null;
  }

  void cancel() {
    _cancelled = true;
  }

  SemanticNode _semanticFormNode() {
    final prompt = currentPrompt;
    final snapshot = controller.snapshot;
    return SemanticNode(
      id: SemanticNodeId('form-prompt-${definition.title}'),
      role: SemanticRole.form,
      label: definition.title,
      enabled: !_cancelled,
      busy: snapshot.validating,
      actions: {
        if (!completed && !_cancelled) SemanticAction.submit,
        if (definition.showCancel && !completed && !_cancelled)
          SemanticAction.cancel,
      },
      state: SemanticState({
        'fieldCount': snapshot.fieldCount,
        'errorCount': snapshot.errorCount,
        'dirty': snapshot.dirty,
        'submitted': snapshot.submitted,
        'validating': snapshot.validating,
        'hasAsyncValidators': snapshot.hasAsyncValidators,
        'valid': snapshot.valid,
        'layout': 'prompt',
        'completed': completed,
        'cancelled': _cancelled,
        if (prompt != null) 'activeFieldId': prompt.fieldId,
        if (prompt != null) 'activePromptIndex': _index,
      }),
      children: <SemanticNode>[
        for (var i = 0; i < definition.fields.length; i++)
          _semanticFieldNode(definition.fields[i], i),
      ],
    );
  }

  SemanticNode _semanticFieldNode(FormFieldSpec field, int index) {
    final current = currentPrompt?.fieldId == field.id;
    final snapshot = controller.snapshot.field(field.id);
    return SemanticNode(
      id: SemanticNodeId('form-prompt-field-${field.id}'),
      role: SemanticRole.formField,
      label: field.label,
      value: snapshot.displayValue,
      selected: current,
      busy: snapshot.validating,
      validationError: snapshot.error,
      actions: current && !completed && !_cancelled
          ? const {SemanticAction.focus, SemanticAction.submit}
          : const {SemanticAction.focus},
      state: SemanticState({
        'fieldId': snapshot.id,
        'fieldType': snapshot.type.name,
        'required': snapshot.required,
        'hasAsyncValidator': snapshot.hasAsyncValidator,
        'validating': snapshot.validating,
        if (snapshot.type == FormFieldType.number && snapshot.min != null)
          'min': snapshot.min,
        if (snapshot.type == FormFieldType.number && snapshot.max != null)
          'max': snapshot.max,
        if (snapshot.type == FormFieldType.number)
          'allowNegative': snapshot.allowNegative,
        if (snapshot.type == FormFieldType.number)
          'allowDecimal': snapshot.allowDecimal,
        if (snapshot.type == FormFieldType.date && snapshot.firstDate != null)
          'firstDate': _formatDate(snapshot.firstDate!),
        if (snapshot.type == FormFieldType.date && snapshot.lastDate != null)
          'lastDate': _formatDate(snapshot.lastDate!),
        if (snapshot.type == FormFieldType.date)
          'weekStartsOn': snapshot.weekStartsOn.name,
        if (snapshot.type == FormFieldType.path)
          'pathKind': snapshot.pathKind.name,
        if (snapshot.type == FormFieldType.path)
          'mustExist': snapshot.mustExist,
        if (snapshot.type == FormFieldType.path)
          'allowRelative': snapshot.allowRelative,
        'redacted': snapshot.redacted,
        'redactedValue': snapshot.redacted,
        'clipboardRedacted': snapshot.redacted,
        'hasValue': snapshot.hasValue,
        'activePrompt': current,
        'promptPosition': index + 1,
        'promptCount': definition.fields.length,
        if (snapshot.options.isNotEmpty) 'optionCount': snapshot.optionCount,
        if (snapshot.type == FormFieldType.multiSelect)
          'selectedOptionCount': snapshot.selectedOptionCount,
        if (snapshot.type == FormFieldType.multiSelect &&
            snapshot.minSelected != null)
          'minSelected': snapshot.minSelected,
        if (snapshot.type == FormFieldType.multiSelect &&
            snapshot.maxSelected != null)
          'maxSelected': snapshot.maxSelected,
      }),
    );
  }

  _PromptParseResult _parseInput(FormFieldSpec field, String input) {
    final text = input.trim();
    if (text.isEmpty && controller.value(field.id) != null) {
      return _PromptParseResult(controller.value(field.id));
    }
    return switch (field.type) {
      FormFieldType.text || FormFieldType.secret => _PromptParseResult(input),
      FormFieldType.number => _parseNumber(field, text),
      FormFieldType.date => _parseDate(field, text),
      FormFieldType.path => _PromptParseResult(text),
      FormFieldType.checkbox => _parseCheckbox(text),
      FormFieldType.select => _parseSelect(field, text),
      FormFieldType.multiSelect => _parseMultiSelect(field, text),
    };
  }

  _PromptParseResult _parseNumber(FormFieldSpec field, String text) {
    if (text.isEmpty) return const _PromptParseResult(null);
    final parsed = _parseNumberText(field, text);
    if (parsed == null) {
      return _PromptParseResult.error(
        field.allowDecimal ? 'Enter a valid number.' : 'Enter a whole number.',
      );
    }
    return _PromptParseResult(parsed);
  }

  _PromptParseResult _parseDate(FormFieldSpec field, String text) {
    if (text.isEmpty) return const _PromptParseResult(null);
    final parsed = _parseDateText(text);
    if (parsed == null) {
      return const _PromptParseResult.error('Enter a date as YYYY-MM-DD.');
    }
    return _PromptParseResult(parsed);
  }

  _PromptParseResult _parseCheckbox(String text) {
    final normalized = text.toLowerCase();
    if (const {'y', 'yes', 'true', '1', 'on'}.contains(normalized)) {
      return const _PromptParseResult(true);
    }
    if (const {'n', 'no', 'false', '0', 'off'}.contains(normalized)) {
      return const _PromptParseResult(false);
    }
    return const _PromptParseResult.error('Enter yes or no.');
  }

  _PromptParseResult _parseSelect(FormFieldSpec field, String text) {
    for (final option in field.options) {
      if (!option.enabled) continue;
      if (option.label.toLowerCase() == text.toLowerCase() ||
          option.value.toString().toLowerCase() == text.toLowerCase()) {
        return _PromptParseResult(option.value);
      }
    }
    return const _PromptParseResult.error('Choose one of the listed options.');
  }

  _PromptParseResult _parseMultiSelect(FormFieldSpec field, String text) {
    if (text.isEmpty) return const _PromptParseResult(<Object?>[]);
    final values = <Object?>[];
    for (final token in text.split(',')) {
      final item = token.trim();
      if (item.isEmpty) continue;
      final option = _formOptionForInput(field, item);
      if (option == null) {
        return const _PromptParseResult.error(
          'Choose one or more listed options.',
        );
      }
      if (!values.contains(option.value)) values.add(option.value);
    }
    return _PromptParseResult(List<Object?>.unmodifiable(values));
  }
}

final class _PromptParseResult {
  const _PromptParseResult(this.value) : _error = null;
  const _PromptParseResult.error(String error) : value = null, _error = error;

  final Object? value;
  final String? _error;
}

/// Renders a [FormDefinition] as an interactive Fleury form.
///
/// A panel owns field focus, validation display, submit/cancel actions, and
/// optional form-level semantics. Provide a [FormController] when the parent
/// needs to read or mutate values directly; otherwise the panel creates one
/// from [definition].
class FormPanel extends StatefulWidget {
  const FormPanel({
    super.key,
    required this.definition,
    this.controller,
    this.fieldIds,
    this.layout = FormPanelLayout.fullScreen,
    this.onSubmit,
    this.onCancel,
    this.autofocus = true,
    this.fieldWidth = 28,
    this.showTitle = true,
    this.showActions = true,
    this.includeFormSemantics = true,
  });

  /// The form schema, including fields, labels, defaults, and validators.
  final FormDefinition definition;

  /// External form state. If omitted, the panel creates and owns a controller.
  final FormController? controller;

  /// Optional ordered subset of fields to show from [definition].
  final List<String>? fieldIds;

  /// Whether to render the panel as a full-screen form or inline group.
  final FormPanelLayout layout;

  /// Called when the user submits the form, after validation runs.
  final void Function(FormSubmitResult result)? onSubmit;

  /// Called when the user cancels the form.
  final void Function()? onCancel;

  /// Whether the first visible field requests focus on mount.
  final bool autofocus;

  /// Preferred input width for text-like fields, in cells.
  final int fieldWidth;

  /// Whether to render the form title.
  final bool showTitle;

  /// Whether to render submit/cancel actions.
  final bool showActions;

  /// Whether to expose a semantic form node around the rendered fields.
  final bool includeFormSemantics;

  @override
  State<FormPanel> createState() => _FormPanelState();
}

class _FormPanelState extends State<FormPanel> {
  late FormController _controller;
  bool _ownsController = false;
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, FocusNode> _fieldFocusNodes = {};

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller ?? FormController(widget.definition));
    _ownsController = widget.controller == null;
    _syncFieldFocusNodes();
    _syncTextControllers();
  }

  @override
  void didUpdateWidget(covariant FormPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller ||
        widget.definition != oldWidget.definition) {
      _controller.removeListener(_onControllerChange);
      if (_ownsController) _controller.dispose();
      _attachController(widget.controller ?? FormController(widget.definition));
      _ownsController = widget.controller == null;
    }
    _syncFieldFocusNodes();
    _syncTextControllers();
  }

  void _attachController(FormController controller) {
    _controller = controller;
    _controller.addListener(_onControllerChange);
  }

  void _onControllerChange() {
    if (!mounted) return;
    _syncTextControllers();
    setState(() {});
  }

  void _syncTextControllers() {
    final textFields = <String, FormFieldSpec>{
      for (final field in _visibleFields)
        if (field.type == FormFieldType.text ||
            field.type == FormFieldType.number ||
            field.type == FormFieldType.path ||
            field.type == FormFieldType.secret)
          field.id: field,
    };
    for (final id in _textControllers.keys.toList()) {
      if (!textFields.containsKey(id)) {
        _textControllers.remove(id)?.dispose();
      }
    }
    for (final entry in textFields.entries) {
      final id = entry.key;
      final field = entry.value;
      final controller = _textControllers[id];
      final text = _formControlText(field, _controller.value(id));
      if (controller == null) {
        final next = TextEditingController(text: text);
        if (field.type != FormFieldType.number) {
          next.addListener(() => _controller.setValue(id, next.text));
        }
        _textControllers[id] = next;
      } else if (controller.text != text) {
        controller
          ..text = text
          ..caretOffset = text.length;
      }
    }
  }

  void _syncFieldFocusNodes() {
    final fieldIds = _visibleFields.map((field) => field.id).toSet();
    for (final id in _fieldFocusNodes.keys.toList()) {
      if (!fieldIds.contains(id)) {
        _fieldFocusNodes.remove(id)?.dispose();
      }
    }
    for (final id in fieldIds) {
      _fieldFocusNodes.putIfAbsent(
        id,
        () => FocusNode(debugLabel: 'form-field:$id'),
      );
    }
  }

  List<FormFieldSpec> get _visibleFields {
    final fieldIds = widget.fieldIds;
    if (fieldIds == null) return widget.definition.fields;
    return [for (final id in fieldIds) widget.definition.field(id)];
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    if (_ownsController) _controller.dispose();
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    for (final node in _fieldFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (_controller.validating) return;
    if (_controller.hasAsyncValidators) {
      unawaited(_submitAsync());
      return;
    }
    final result = _controller.submit();
    widget.onSubmit?.call(result);
  }

  Future<void> _submitAsync() async {
    if (_controller.validating) return;
    final result = await _controller.submitAsync();
    if (!mounted) return;
    widget.onSubmit?.call(result);
  }

  void _cancel() {
    widget.onCancel?.call();
  }

  void _focusField(String fieldId) {
    _fieldFocusNodes[fieldId]?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    Focus.maybeOf(context);
    final errors = _controller.errors;
    final snapshot = _controller.snapshot;
    final visibleFields = _visibleFields;
    final content = FocusTraversalGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showTitle && widget.definition.title.isNotEmpty)
            Text(widget.definition.title, style: const CellStyle(bold: true)),
          for (var i = 0; i < visibleFields.length; i++)
            _field(visibleFields[i], autofocus: i == 0),
          if (widget.showActions) _actions(),
        ],
      ),
    );
    if (!widget.includeFormSemantics) return content;
    return Semantics(
      role: SemanticRole.form,
      label: widget.definition.title,
      busy: _controller.validating,
      actions: {
        SemanticAction.submit,
        if (widget.definition.showCancel) SemanticAction.cancel,
      },
      state: SemanticState({
        'fieldCount': widget.definition.fields.length,
        'visibleFieldCount': visibleFields.length,
        'errorCount': errors.length,
        'dirty': _controller.dirty,
        'submitted': _controller.submitted,
        'validating': _controller.validating,
        'hasAsyncValidators': _controller.hasAsyncValidators,
        'valid': snapshot.valid,
        'layout': widget.layout.name,
      }),
      onAction: (action) {
        if (action == SemanticAction.submit) {
          if (_controller.hasAsyncValidators) return _submitAsync();
          _submit();
        } else if (action == SemanticAction.cancel) {
          _cancel();
        }
      },
      child: content,
    );
  }

  Widget _field(FormFieldSpec field, {required bool autofocus}) {
    final snapshot = _controller.snapshot.field(field.id);
    final error = snapshot.error;
    final child = _control(field, autofocus: widget.autofocus && autofocus);
    final focusNode = _fieldFocusNodes[field.id];
    final requiredMarker = field.required ? ' *' : '';
    final label = '${field.label}$requiredMarker';
    final fieldSemantics = Semantics(
      role: SemanticRole.formField,
      label: field.label,
      value: snapshot.displayValue,
      validationError: error,
      focused: focusNode?.hasFocus ?? false,
      busy: snapshot.validating,
      actions: const {SemanticAction.focus},
      onAction: (action) {
        if (action == SemanticAction.focus) {
          _focusField(field.id);
        }
      },
      state: SemanticState({
        'fieldId': snapshot.id,
        'fieldType': snapshot.type.name,
        'required': snapshot.required,
        'hasAsyncValidator': snapshot.hasAsyncValidator,
        'validating': snapshot.validating,
        if (snapshot.type == FormFieldType.number && snapshot.min != null)
          'min': snapshot.min,
        if (snapshot.type == FormFieldType.number && snapshot.max != null)
          'max': snapshot.max,
        if (snapshot.type == FormFieldType.number)
          'allowNegative': snapshot.allowNegative,
        if (snapshot.type == FormFieldType.number)
          'allowDecimal': snapshot.allowDecimal,
        if (snapshot.type == FormFieldType.date && snapshot.firstDate != null)
          'firstDate': _formatDate(snapshot.firstDate!),
        if (snapshot.type == FormFieldType.date && snapshot.lastDate != null)
          'lastDate': _formatDate(snapshot.lastDate!),
        if (snapshot.type == FormFieldType.date)
          'weekStartsOn': snapshot.weekStartsOn.name,
        if (snapshot.type == FormFieldType.path)
          'pathKind': snapshot.pathKind.name,
        if (snapshot.type == FormFieldType.path)
          'mustExist': snapshot.mustExist,
        if (snapshot.type == FormFieldType.path)
          'allowRelative': snapshot.allowRelative,
        'redacted': snapshot.redacted,
        'redactedValue': snapshot.redacted,
        'clipboardRedacted': snapshot.redacted,
        'hasValue': snapshot.hasValue,
        if (snapshot.options.isNotEmpty) 'optionCount': snapshot.optionCount,
        if (snapshot.type == FormFieldType.multiSelect)
          'selectedOptionCount': snapshot.selectedOptionCount,
        if (snapshot.type == FormFieldType.multiSelect &&
            snapshot.minSelected != null)
          'minSelected': snapshot.minSelected,
        if (snapshot.type == FormFieldType.multiSelect &&
            snapshot.maxSelected != null)
          'maxSelected': snapshot.maxSelected,
      }),
      child: widget.layout == FormPanelLayout.inline
          ? Row(
              children: [
                SizedBox(width: 16, child: Text('$label:')),
                SizedBox(width: widget.fieldWidth, child: child),
                if (error != null)
                  Text(
                    '  $error',
                    style: CellStyle(
                      foreground: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (field.type != FormFieldType.checkbox) Text(label),
                SizedBox(width: widget.fieldWidth, child: child),
                if (error != null)
                  Text(
                    error,
                    style: CellStyle(
                      foreground: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
    );
    return fieldSemantics;
  }

  Widget _control(FormFieldSpec field, {required bool autofocus}) {
    final error = _controller.error(field.id);
    final focusNode = _fieldFocusNodes[field.id];
    return switch (field.type) {
      FormFieldType.text => TextInput(
        controller: _textControllers[field.id],
        focusNode: focusNode,
        autofocus: autofocus,
        placeholder: field.placeholder,
        validationError: error,
        onSubmit: (_) => _submit(),
      ),
      FormFieldType.number => NumberInput(
        controller: _textControllers[field.id],
        focusNode: focusNode,
        autofocus: autofocus,
        placeholder: field.placeholder,
        min: field.min,
        max: field.max,
        allowNegative: field.allowNegative,
        allowDecimal: field.allowDecimal,
        onChanged: (value) => _controller.setValue(field.id, value),
        onSubmit: (value) {
          _controller.setValue(field.id, value);
          _submit();
        },
      ),
      FormFieldType.date => DatePicker(
        value:
            _parseDateValue(_controller.value(field.id)) ??
            _dateOnly(field.initialValue as DateTime),
        firstDate: field.firstDate,
        lastDate: field.lastDate,
        weekStartsOn: field.weekStartsOn,
        label: field.label,
        focusNode: focusNode,
        autofocus: autofocus,
        onChanged: (value) => _controller.setValue(field.id, _dateOnly(value)),
      ),
      FormFieldType.path => TextInput(
        controller: _textControllers[field.id],
        focusNode: focusNode,
        autofocus: autofocus,
        placeholder: field.placeholder,
        validationError: error,
        onSubmit: (_) => _submit(),
      ),
      FormFieldType.secret => PasswordInput(
        controller: _textControllers[field.id],
        focusNode: focusNode,
        autofocus: autofocus,
        placeholder: field.placeholder,
        validationError: error,
        onSubmit: (_) => _submit(),
      ),
      FormFieldType.select => Select<Object?>(
        value: _controller.value(field.id),
        options: [
          for (final option in field.options)
            SelectOption<Object?>(
              value: option.value,
              label: option.label,
              enabled: option.enabled,
            ),
        ],
        placeholder: field.placeholder,
        focusNode: focusNode,
        autofocus: autofocus,
        onChanged: (value) => _controller.setValue(field.id, value),
      ),
      FormFieldType.multiSelect => _FormMultiSelectControl(
        field: field,
        values: _multiSelectValues(_controller.value(field.id)),
        focusNode: focusNode,
        autofocus: autofocus,
        onChanged: (values) => _controller.setValue(field.id, values),
      ),
      FormFieldType.checkbox => Checkbox(
        value: _controller.value(field.id) == true,
        label: field.required ? '${field.label} *' : field.label,
        focusNode: focusNode,
        autofocus: autofocus,
        onChanged: (value) => _controller.setValue(field.id, value),
      ),
    };
  }

  Widget _actions() {
    return Row(
      children: [
        Button(
          label: widget.definition.submitLabel,
          variant: ButtonVariant.primary,
          onPressed: _submit,
        ),
        if (widget.definition.showCancel) ...[
          const SizedBox(width: 1),
          Button(
            label: widget.definition.cancelLabel,
            onPressed: widget.onCancel,
          ),
        ],
      ],
    );
  }
}

class FormWizard extends StatefulWidget {
  const FormWizard({
    super.key,
    required this.definition,
    required this.steps,
    this.controller,
    this.wizardController,
    this.layout = FormPanelLayout.fullScreen,
    this.onSubmit,
    this.onCancel,
    this.autofocus = true,
    this.fieldWidth = 28,
    this.nextLabel = 'Next',
    this.backLabel = 'Back',
  });

  final FormDefinition definition;
  final List<FormWizardStep> steps;
  final FormController? controller;
  final FormWizardController? wizardController;
  final FormPanelLayout layout;
  final void Function(FormSubmitResult result)? onSubmit;
  final void Function()? onCancel;
  final bool autofocus;
  final int fieldWidth;
  final String nextLabel;
  final String backLabel;

  @override
  State<FormWizard> createState() => _FormWizardState();
}

class _FormWizardState extends State<FormWizard> {
  late FormController _controller;
  late FormWizardController _wizard;
  bool _ownsController = false;
  bool _ownsWizard = false;

  @override
  void initState() {
    super.initState();
    // Initialize both late fields before any listener registration or
    // validation can throw. The framework disposes a partially mounted State,
    // so every field read by dispose must already be safe at that boundary.
    _controller = widget.controller ?? FormController(widget.definition);
    _ownsController = widget.controller == null;
    _wizard = widget.wizardController ?? FormWizardController();
    _ownsWizard = widget.wizardController == null;
    _controller.addListener(_onStateChange);
    _wizard.addListener(_onStateChange);
    // Validate only after every teardown dependency is initialized. Failed
    // mounts are rolled back and disposed by the framework; keeping dispose
    // safe preserves the original error and releases the listeners above.
    _validateSteps();
    _clampWizardIndex();
  }

  @override
  void didUpdateWidget(covariant FormWizard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _validateSteps();
    if (widget.controller != oldWidget.controller ||
        widget.definition != oldWidget.definition) {
      _controller.removeListener(_onStateChange);
      if (_ownsController) _controller.dispose();
      _attachController(widget.controller ?? FormController(widget.definition));
      _ownsController = widget.controller == null;
    }
    if (widget.wizardController != oldWidget.wizardController) {
      _wizard.removeListener(_onStateChange);
      if (_ownsWizard) _wizard.dispose();
      _attachWizardController(
        widget.wizardController ?? FormWizardController(),
      );
      _ownsWizard = widget.wizardController == null;
    }
    _clampWizardIndex();
  }

  void _attachController(FormController controller) {
    _controller = controller;
    _controller.addListener(_onStateChange);
  }

  void _attachWizardController(FormWizardController controller) {
    _wizard = controller;
    _wizard.addListener(_onStateChange);
  }

  void _onStateChange() {
    if (!mounted) return;
    setState(() {});
  }

  void _validateSteps() {
    if (widget.steps.isEmpty) {
      throw StateError('FormWizard requires at least one step.');
    }
    final stepIds = <String>{};
    final coveredFieldIds = <String>{};
    final knownFieldIds = {
      for (final field in widget.definition.fields) field.id,
    };
    for (final step in widget.steps) {
      if (step.id.trim().isEmpty) {
        throw StateError('FormWizard step ids must not be empty.');
      }
      if (!stepIds.add(step.id)) {
        throw StateError('FormWizard step "${step.id}" is duplicated.');
      }
      if (step.fieldIds.isEmpty) {
        throw StateError('FormWizard step "${step.id}" has no fields.');
      }
      for (final fieldId in step.fieldIds) {
        if (!knownFieldIds.contains(fieldId)) {
          throw StateError(
            'FormWizard step "${step.id}" references unknown field "$fieldId".',
          );
        }
        if (!coveredFieldIds.add(fieldId)) {
          throw StateError(
            'FormWizard field "$fieldId" appears in more than one step.',
          );
        }
      }
    }
    final missing = [
      for (final field in widget.definition.fields)
        if (!coveredFieldIds.contains(field.id)) field.id,
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'FormWizard steps must include every form field. '
        'Missing: ${missing.join(', ')}.',
      );
    }
  }

  void _clampWizardIndex() {
    _wizard.goTo(_wizard.currentStepIndex, stepCount: widget.steps.length);
  }

  @override
  void dispose() {
    _controller.removeListener(_onStateChange);
    if (_ownsController) _controller.dispose();
    _wizard.removeListener(_onStateChange);
    if (_ownsWizard) _wizard.dispose();
    super.dispose();
  }

  int get _stepIndex =>
      _wizard.currentStepIndex.clamp(0, widget.steps.length - 1).toInt();

  FormWizardStep get _step => widget.steps[_stepIndex];
  bool get _isLastStep => _stepIndex == widget.steps.length - 1;
  bool get _canGoBack => _wizard.canGoBack;

  bool _stepHasAsyncValidators(FormWizardStep step) {
    return step.fieldIds.any(
      (fieldId) => widget.definition.field(fieldId).asyncValidator != null,
    );
  }

  bool _validateCurrentStep(FormWizardStep step) {
    var valid = true;
    for (final fieldId in step.fieldIds) {
      if (_controller.validateField(fieldId) != null) valid = false;
    }
    return valid;
  }

  Future<bool> _validateCurrentStepAsync(FormWizardStep step) async {
    var valid = true;
    for (final fieldId in step.fieldIds) {
      final error = await _controller.validateFieldAsync(fieldId);
      if (!mounted) return false;
      if (error != null) valid = false;
    }
    return valid;
  }

  void _next() {
    unawaited(_advanceNext());
  }

  Future<void> _advanceNext() async {
    if (_controller.validating || _isLastStep) return;
    final step = _step;
    final valid = _stepHasAsyncValidators(step)
        ? await _validateCurrentStepAsync(step)
        : _validateCurrentStep(step);
    if (!mounted) return;
    if (valid) {
      _wizard.next(stepCount: widget.steps.length);
    }
  }

  void _previous() {
    if (_controller.validating) return;
    _wizard.previous();
  }

  void _submit() {
    if (_controller.validating) return;
    if (_controller.hasAsyncValidators) {
      unawaited(_submitAsync());
      return;
    }
    final result = _controller.submit();
    widget.onSubmit?.call(result);
  }

  Future<void> _invokeSubmit() async {
    if (_controller.hasAsyncValidators) {
      await _submitAsync();
      return;
    }
    _submit();
  }

  Future<void> _submitAsync() async {
    if (_controller.validating) return;
    final result = await _controller.submitAsync();
    if (!mounted) return;
    widget.onSubmit?.call(result);
  }

  void _cancel() {
    widget.onCancel?.call();
  }

  @override
  Widget build(BuildContext context) {
    final step = _step;
    final stepIndex = _stepIndex;
    final snapshot = _controller.snapshot;
    return Semantics(
      role: SemanticRole.form,
      label: widget.definition.title,
      busy: _controller.validating,
      actions: {
        if (_canGoBack) SemanticAction.decrement,
        if (!_isLastStep) SemanticAction.increment,
        if (_isLastStep) SemanticAction.submit,
        if (widget.definition.showCancel) SemanticAction.cancel,
      },
      state: SemanticState({
        'fieldCount': widget.definition.fields.length,
        'visibleFieldCount': step.fieldIds.length,
        'errorCount': _controller.errors.length,
        'dirty': _controller.dirty,
        'submitted': _controller.submitted,
        'validating': _controller.validating,
        'hasAsyncValidators': _controller.hasAsyncValidators,
        'valid': snapshot.valid,
        'layout': 'wizard',
        'stepCount': widget.steps.length,
        'currentStepIndex': stepIndex,
        'currentStepPosition': stepIndex + 1,
        'currentStepId': step.id,
        'currentStepTitle': step.title,
        'canGoBack': _canGoBack,
        'canGoForward': !_isLastStep,
      }),
      onAction: (action) async {
        switch (action) {
          case SemanticAction.increment:
            await _advanceNext();
            return;
          case SemanticAction.decrement:
            _previous();
            return;
          case SemanticAction.submit:
            await _invokeSubmit();
            return;
          case SemanticAction.cancel:
            _cancel();
            return;
          case _:
            return;
        }
      },
      child: FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.definition.title.isNotEmpty)
              Text(widget.definition.title, style: const CellStyle(bold: true)),
            _stepHeader(step, stepIndex),
            FormPanel(
              definition: widget.definition,
              controller: _controller,
              fieldIds: step.fieldIds,
              layout: widget.layout,
              autofocus: widget.autofocus,
              fieldWidth: widget.fieldWidth,
              showTitle: false,
              showActions: false,
              includeFormSemantics: false,
            ),
            _actions(),
          ],
        ),
      ),
    );
  }

  Widget _stepHeader(FormWizardStep step, int stepIndex) {
    return Semantics(
      role: SemanticRole.region,
      label: step.title,
      selected: true,
      state: SemanticState({
        'stepId': step.id,
        'stepIndex': stepIndex,
        'stepPosition': stepIndex + 1,
        'stepCount': widget.steps.length,
        'fieldCount': step.fieldIds.length,
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Step ${stepIndex + 1}/${widget.steps.length}: ${step.title}',
            style: const CellStyle(bold: true),
          ),
          if (step.description.isNotEmpty)
            Text(step.description, style: const CellStyle(dim: true)),
        ],
      ),
    );
  }

  Widget _actions() {
    return Row(
      children: [
        Button(
          label: widget.backLabel,
          onPressed: _canGoBack && !_controller.validating ? _previous : null,
        ),
        const SizedBox(width: 1),
        Button(
          label: _isLastStep ? widget.definition.submitLabel : widget.nextLabel,
          variant: ButtonVariant.primary,
          onPressed: _controller.validating
              ? null
              : _isLastStep
              ? _submit
              : _next,
        ),
        if (widget.definition.showCancel) ...[
          const SizedBox(width: 1),
          Button(label: widget.definition.cancelLabel, onPressed: _cancel),
        ],
      ],
    );
  }
}

class _FormMultiSelectControl extends StatefulWidget {
  const _FormMultiSelectControl({
    required this.field,
    required this.values,
    required this.onChanged,
    this.focusNode,
    this.autofocus = false,
  });

  final FormFieldSpec field;
  final List<Object?> values;
  final void Function(List<Object?> values) onChanged;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<_FormMultiSelectControl> createState() =>
      _FormMultiSelectControlState();
}

class _FormMultiSelectControlState extends State<_FormMultiSelectControl>
    implements TextInputClaimant {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  int _highlightedIndex = 0;

  @override
  void initState() {
    super.initState();
    _attachFocusNode(widget.focusNode);
    _highlightedIndex = _initialIndex();
  }

  @override
  void didUpdateWidget(covariant _FormMultiSelectControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _detachFocusNode();
      _attachFocusNode(widget.focusNode);
    }
    _highlightedIndex = _clampToEnabled(_highlightedIndex);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Focus.maybeOf(context);
  }

  void _attachFocusNode(FocusNode? node) {
    _focusNode = node ?? FocusNode(debugLabel: 'form-multi-select');
    _ownsFocusNode = node == null;
    _focusNode.textInputClaimant = this;
  }

  void _detachFocusNode() {
    _focusNode.textInputClaimant = null;
    if (_ownsFocusNode) _focusNode.dispose();
  }

  int _initialIndex() {
    for (var i = 0; i < widget.field.options.length; i++) {
      if (widget.values.contains(widget.field.options[i].value) &&
          widget.field.options[i].enabled) {
        return i;
      }
    }
    return _clampToEnabled(0);
  }

  int _clampToEnabled(int index) {
    if (widget.field.options.isEmpty) return 0;
    final clamped = index.clamp(0, widget.field.options.length - 1);
    if (widget.field.options[clamped].enabled) return clamped;
    for (var i = clamped + 1; i < widget.field.options.length; i++) {
      if (widget.field.options[i].enabled) return i;
    }
    for (var i = clamped - 1; i >= 0; i--) {
      if (widget.field.options[i].enabled) return i;
    }
    return clamped;
  }

  int? _step(int direction) {
    var i = _highlightedIndex + direction;
    while (i >= 0 && i < widget.field.options.length) {
      if (widget.field.options[i].enabled) return i;
      i += direction;
    }
    return null;
  }

  void _moveTo(int index) {
    setState(() => _highlightedIndex = _clampToEnabled(index));
  }

  void _toggleHighlighted() {
    if (widget.field.options.isEmpty) return;
    final option = widget.field.options[_highlightedIndex];
    if (!option.enabled) return;
    final values = widget.values.toList();
    if (values.contains(option.value)) {
      values.remove(option.value);
    } else {
      values.add(option.value);
    }
    widget.onChanged(List<Object?>.unmodifiable(values));
  }

  KeyEventResult _onKey(KeyEvent event) {
    switch (event.keyCode) {
      case KeyCode.arrowUp:
        final previous = _step(-1);
        if (previous != null) _moveTo(previous);
        return KeyEventResult.handled;
      case KeyCode.arrowDown:
        final next = _step(1);
        if (next != null) _moveTo(next);
        return KeyEventResult.handled;
      case KeyCode.home:
        _moveTo(0);
        return KeyEventResult.handled;
      case KeyCode.end:
        _moveTo(widget.field.options.length - 1);
        return KeyEventResult.handled;
      case KeyCode.enter:
        _toggleHighlighted();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  KeyEventResult onTextInput(String text) {
    if (text == ' ') {
      _toggleHighlighted();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  KeyEventResult onPaste(String text) => KeyEventResult.ignored;

  @override
  void dispose() {
    _detachFocusNode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focused = _focusNode.hasFocus;
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKey: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.field.options.isEmpty) Text(widget.field.placeholder),
          for (var i = 0; i < widget.field.options.length; i++)
            _optionRow(theme, i, focused),
        ],
      ),
    );
  }

  Widget _optionRow(ThemeData theme, int index, bool focused) {
    final option = widget.field.options[index];
    final selected = widget.values.contains(option.value);
    final highlighted = focused && index == _highlightedIndex;
    final style = !option.enabled
        ? theme.mutedStyle
        : highlighted
        ? theme.selectionStyle
        : CellStyle.empty;
    return GestureDetector(
      onTap: option.enabled
          ? () {
              _focusNode.requestFocus();
              setState(() => _highlightedIndex = index);
              _toggleHighlighted();
            }
          : null,
      child: Text('${selected ? '[x]' : '[ ]'} ${option.label}', style: style),
    );
  }
}

bool _isFormValueEmpty(FormFieldSpec field, Object? value) {
  return switch (field.type) {
    FormFieldType.text ||
    FormFieldType.secret => value == null || value.toString().trim().isEmpty,
    FormFieldType.number => value == null || value.toString().trim().isEmpty,
    FormFieldType.date => value == null || value.toString().trim().isEmpty,
    FormFieldType.path => value == null || value.toString().trim().isEmpty,
    FormFieldType.select => value == null,
    FormFieldType.multiSelect => _multiSelectValues(value).isEmpty,
    FormFieldType.checkbox => value != true,
  };
}

Object? _normalizeFormValue(FormFieldSpec field, Object? value) {
  if (field.type == FormFieldType.date && value is DateTime) {
    return _dateOnly(value);
  }
  if (field.type == FormFieldType.multiSelect) {
    return _multiSelectValues(value);
  }
  return value;
}

String? _displayFormValue(FormFieldSpec field, Object? value) {
  if (field.redacted || value == null) return null;
  return switch (field.type) {
    FormFieldType.select => _formOptionLabel(field, value),
    FormFieldType.multiSelect => _multiSelectDisplayValue(field, value),
    FormFieldType.checkbox => value == true ? 'yes' : 'no',
    FormFieldType.number => _numberDisplayValue(field, value),
    FormFieldType.date => _dateDisplayValue(value),
    FormFieldType.path => sanitizeForDisplay(value.toString()),
    FormFieldType.text || FormFieldType.secret => value.toString(),
  };
}

String _formControlText(FormFieldSpec field, Object? value) {
  if (value == null) return '';
  if (field.type == FormFieldType.number) {
    return _numberDisplayValue(field, value);
  }
  if (field.type == FormFieldType.date) {
    return _dateDisplayValue(value);
  }
  return value.toString();
}

String _numberDisplayValue(FormFieldSpec field, Object? value) {
  final parsed = _parseNumberValue(field, value);
  if (parsed == null) return value.toString();
  if (!field.allowDecimal && parsed is int) return parsed.toString();
  if (!field.allowDecimal && parsed == parsed.truncateToDouble()) {
    return parsed.toInt().toString();
  }
  return parsed.toString();
}

num? _parseNumberValue(FormFieldSpec field, Object? value) {
  if (value is num) return value;
  return _parseNumberText(field, value?.toString().trim() ?? '');
}

num? _parseNumberText(FormFieldSpec field, String text) {
  if (text.isEmpty || text == '-' || text == '.' || text == '-.') return null;
  return field.allowDecimal ? num.tryParse(text) : int.tryParse(text);
}

String _dateDisplayValue(Object? value) {
  final parsed = _parseDateValue(value);
  return parsed == null ? value.toString() : _formatDate(parsed);
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime? _parseDateValue(Object? value) {
  if (value is DateTime) return _dateOnly(value);
  return _parseDateText(value?.toString().trim() ?? '');
}

DateTime? _parseDateText(String text) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return null;
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

String _formatDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

bool _isAbsolutePath(String path) {
  if (path.startsWith('/')) return true;
  return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) || path.startsWith(r'\\');
}

String _formOptionLabel(FormFieldSpec field, Object? value) {
  final option = _formOptionForValue(field, value);
  if (option != null) return option.label;
  return value.toString();
}

FormOption? _formOptionForValue(FormFieldSpec field, Object? value) {
  for (final option in field.options) {
    if (option.value == value) return option;
  }
  return null;
}

FormOption? _formOptionForInput(FormFieldSpec field, String input) {
  final normalized = input.toLowerCase();
  for (final option in field.options) {
    if (!option.enabled) continue;
    if (option.label.toLowerCase() == normalized ||
        option.value.toString().toLowerCase() == normalized) {
      return option;
    }
  }
  return null;
}

List<Object?> _multiSelectValues(Object? value) {
  if (value == null) return const <Object?>[];
  if (value is Iterable) {
    final values = <Object?>[];
    for (final item in value.cast<Object?>()) {
      if (!values.contains(item)) values.add(item);
    }
    return List<Object?>.unmodifiable(values);
  }
  return List<Object?>.unmodifiable(<Object?>[value]);
}

String? _multiSelectDisplayValue(FormFieldSpec field, Object? value) {
  final values = _multiSelectValues(value);
  if (values.isEmpty) return null;
  return values.map((value) => _formOptionLabel(field, value)).join(', ');
}
