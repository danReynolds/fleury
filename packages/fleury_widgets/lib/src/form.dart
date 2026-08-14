import 'dart:async' show FutureOr, scheduleMicrotask, unawaited;

import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_internal.dart';

/// Coordinates validation and submission for one mounted [Form].
///
/// A controller owns no field values. Application state remains the source of
/// truth; the controller only drives the form that is currently attached to
/// it. Create it once in `State`, pass it to [Form], and dispose it alongside
/// that state when external access is useful. Omit it for forms that submit
/// through [Form.of] from inside their subtree.
final class FormController extends ChangeNotifier {
  _FormHost? _host;
  bool _submitting = false;
  bool _disposed = false;
  Future<bool>? _submission;
  int _submissionGeneration = 0;

  /// Whether this controller currently belongs to a mounted form.
  bool get isAttached => _host != null;

  /// Whether [submit] is currently awaiting the form's submit callback.
  bool get isSubmitting => _submitting;

  /// Validates every mounted, enabled field and focuses the first invalid one.
  bool validate() => _requireHost().validate();

  /// Validates the form and, only when valid, awaits its submit callback.
  ///
  /// Concurrent calls share one submission. The returned value is true when
  /// the callback ran successfully and false when validation rejected it.
  Future<bool> submit() {
    final active = _submission;
    if (active != null) return active;
    final generation = ++_submissionGeneration;
    final future = Future<bool>.microtask(() => _runSubmission(generation));
    _submission = future;
    return future;
  }

  Future<bool> _runSubmission(int generation) async {
    try {
      final host = _requireHost();
      if (!host.validate()) return false;
      _setSubmitting(true);
      await host.submit();
      return true;
    } finally {
      if (_submissionGeneration == generation) {
        _submission = null;
        if (!_disposed) _setSubmitting(false);
      }
    }
  }

  /// Hides validator-generated errors without changing application values.
  ///
  /// Controlled errors passed to [FormField.error] remain visible until the
  /// application clears them.
  void clearErrors() => _requireHost().clearErrors();

  _FormHost _requireHost() {
    if (_disposed) {
      throw StateError('FormController was used after dispose().');
    }
    final host = _host;
    if (host == null) {
      throw StateError(
        'FormController is not attached to a mounted Form. Pass it to '
        'Form(controller: ...), or call Form.of(context) inside the form.',
      );
    }
    return host;
  }

  void _attach(_FormHost host) {
    if (_disposed) {
      throw StateError('A disposed FormController cannot attach to a Form.');
    }
    final current = _host;
    if (current != null && !identical(current, host)) {
      throw StateError(
        'A FormController can be attached to only one mounted Form at a time.',
      );
    }
    _host = host;
  }

  void _detach(_FormHost host) {
    if (identical(_host, host)) _host = null;
    if (_submitting) {
      _submissionGeneration++;
      _submission = null;
      _setSubmitting(false);
    }
  }

  void _setSubmitting(bool value) {
    if (_submitting == value) return;
    _submitting = value;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_host != null) {
      throw StateError(
        'Do not dispose a FormController while its Form is still mounted.',
      );
    }
    _disposed = true;
    super.dispose();
  }
}

abstract interface class _FormHost {
  bool validate();
  FutureOr<void> submit();
  void clearErrors();
}

/// A behavioral boundary that coordinates descendant [FormField] widgets.
///
/// [Form] owns no values and imposes no panel, wizard, or field layout. Values
/// stay in ordinary application state and validators close over that state.
class Form extends StatefulWidget {
  /// Creates a behavioral form boundary around [child].
  const Form({
    super.key,
    this.controller,
    this.semanticLabel,
    required this.onSubmit,
    required this.child,
  });

  /// Optional externally-owned command surface.
  ///
  /// When omitted, [Form] creates one that descendants can read with [of].
  final FormController? controller;

  /// Accessible name for this form when the surrounding heading is not enough.
  final String? semanticLabel;

  /// Called after every mounted, enabled field validates successfully.
  final FutureOr<void> Function() onSubmit;

  /// The application-defined form layout.
  final Widget child;

  /// The controller for the nearest enclosing form.
  static FormController of(BuildContext context) {
    final controller = maybeOf(context);
    if (controller == null) {
      throw StateError('Form.of(context) called without an enclosing Form.');
    }
    return controller;
  }

  /// The controller for the nearest enclosing form, if one exists.
  static FormController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FormScope>()?.controller;

  @override
  State<Form> createState() => _FormWidgetState();
}

final class _FormWidgetState extends State<Form> implements _FormHost {
  late FormController _controller;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    _attach(widget.controller);
  }

  void _attach(FormController? controller) {
    _controller = controller ?? FormController();
    _ownsController = controller == null;
    _controller._attach(this);
  }

  @override
  void didUpdateWidget(Form oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == oldWidget.controller) return;
    _controller._detach(this);
    if (_ownsController) _controller.dispose();
    _attach(widget.controller);
  }

  List<FormFieldState> _fieldsInTraversalOrder() {
    final fields = <FormFieldState>[];
    void visit(Element element) {
      if (!identical(element, context) && element.widget is Form) return;
      if (element is StatefulElement && element.state is FormFieldState) {
        fields.add(element.state as FormFieldState);
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return fields;
  }

  @override
  bool validate() {
    FormFieldState? firstInvalid;
    for (final field in _fieldsInTraversalOrder()) {
      if (!field.validate()) firstInvalid ??= field;
    }
    firstInvalid?.focusNode.requestFocus();
    return firstInvalid == null;
  }

  @override
  FutureOr<void> submit() => widget.onSubmit();

  @override
  void clearErrors() {
    for (final field in _fieldsInTraversalOrder()) {
      field._clearValidatorError();
    }
  }

  @override
  void dispose() {
    _controller._detach(this);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    child: widget.child,
    builder: (context, child) => _FormScope(
      controller: _controller,
      child: Semantics(
        role: SemanticRole.form,
        label: widget.semanticLabel,
        busy: _controller.isSubmitting,
        actions: _controller.isSubmitting
            ? const <SemanticAction>{}
            : const <SemanticAction>{SemanticAction.submit},
        onAction: (action) {
          if (action == SemanticAction.submit) {
            unawaited(_controller.submit());
          }
        },
        child: child!,
      ),
    ),
  );
}

final class _FormScope extends InheritedWidget {
  const _FormScope({required this.controller, required super.child});

  final FormController controller;

  @override
  bool updateShouldNotify(_FormScope oldWidget) =>
      !identical(controller, oldWidget.controller);
}

/// One validated value in a [Form].
///
/// The ordinary constructor discovers exactly one first-party value control
/// inside [child], so no binding argument or specialized wrapper is needed.
/// Use [FormField.builder] for a custom or multi-control value.
class FormField extends StatefulWidget {
  /// Creates a field that automatically integrates one aware control in
  /// [child].
  const FormField({
    super.key,
    required Widget this.child,
    this.validator,
    this.error,
    this.enabled = true,
    this.showErrorMessage = true,
    this.errorBuilder,
  }) : builder = null,
       focusNode = null;

  /// Creates a field whose custom control is built from its live state.
  ///
  /// Use this for one logical value represented by a custom or multi-control
  /// widget. The builder must call [FormFieldState.valueChanged] when its
  /// app-owned value changes.
  const FormField.builder({
    super.key,
    required Widget Function(BuildContext context, FormFieldState field)
    this.builder,
    this.validator,
    this.error,
    this.enabled = true,
    this.focusNode,
    this.showErrorMessage = true,
    this.errorBuilder,
  }) : child = null;

  /// Subtree containing the field's one automatically integrated control.
  final Widget? child;

  /// Custom-control builder used by [FormField.builder].
  final Widget Function(BuildContext context, FormFieldState field)? builder;

  /// Returns the current error by reading application-owned state.
  final String? Function()? validator;

  /// Controlled external error, typically returned by a server.
  final String? error;

  /// Disabled fields are skipped by validation and first-invalid focus.
  final bool enabled;

  /// Focus destination for [FormField.builder].
  final FocusNode? focusNode;

  /// Whether the field renders its current error below the control.
  final bool showErrorMessage;

  /// Optional replacement for the default styled error text.
  final Widget Function(BuildContext context, String error)? errorBuilder;

  @override
  State<FormField> createState() => FormFieldState();
}

/// Current validation state exposed by [FormField.builder].
final class FormFieldState extends State<FormField>
    implements FormControlRegistration {
  FocusNode? _ownedFocusNode;
  final List<_FormControlClaim> _controlClaims = <_FormControlClaim>[];
  String? _validatorError;
  bool _validatorErrorVisible = false;
  bool _claimCheckScheduled = false;

  _FormControlClaim? get _controlClaim =>
      _controlClaims.isEmpty ? null : _controlClaims.last;

  /// The error currently visible for this field.
  @override
  String? get error {
    if (!enabled) return null;
    return widget.error ??
        _controlClaim?.validationError ??
        (_validatorErrorVisible ? _validatorError : null);
  }

  /// Whether this field participates in validation.
  bool get enabled =>
      widget.enabled &&
      (widget.builder != null || _controlClaim?.enabled != false);

  /// The focus destination used when this is the first invalid field.
  FocusNode get focusNode =>
      widget.focusNode ??
      _controlClaim?.focusNode ??
      (_ownedFocusNode ??= FocusNode(debugLabel: 'form-field'));

  /// Reports that the app-owned value represented by a custom field changed.
  ///
  /// Once a validator error has been shown, changes revalidate this field so
  /// stale feedback clears promptly. Controlled [FormField.error] values stay
  /// visible until the application updates them.
  void valueChanged() {
    if (!enabled || !_validatorErrorVisible) return;
    _runValidator(reveal: true);
  }

  /// Validates this field and reveals its current error.
  bool validate() {
    if (!enabled) {
      _setValidatorState(error: null, visible: false);
      return true;
    }
    _runValidator(reveal: true);
    return error == null;
  }

  void _runValidator({required bool reveal}) {
    final next = widget.validator?.call();
    _setValidatorState(error: next, visible: reveal);
  }

  void _setValidatorState({required String? error, required bool visible}) {
    if (_validatorError == error && _validatorErrorVisible == visible) return;
    setState(() {
      _validatorError = error;
      _validatorErrorVisible = visible;
    });
  }

  void _clearValidatorError() =>
      _setValidatorState(error: null, visible: false);

  @override
  void didUpdateWidget(FormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // didUpdateWidget is followed by build, so update derived validation state
    // directly instead of scheduling a redundant setState rebuild.
    if (!widget.enabled && oldWidget.enabled) {
      _validatorError = null;
      _validatorErrorVisible = false;
    } else if (_validatorErrorVisible &&
        widget.validator != oldWidget.validator) {
      _validatorError = widget.validator?.call();
    }
  }

  @override
  void claim(
    Object control, {
    required FocusNode focusNode,
    required bool enabled,
    String? validationError,
  }) {
    final existing = _findControlClaim(control);
    final controlClaim =
        existing ??
        _FormControlClaim(
          control: control,
          focusNode: focusNode,
          enabled: enabled,
          validationError: validationError,
        );
    if (existing == null) _controlClaims.add(controlClaim);
    _updateControlClaim(
      controlClaim,
      focusNode: focusNode,
      enabled: enabled,
      validationError: validationError,
    );
    _scheduleClaimCheck();
  }

  @override
  void updateClaim(
    Object control, {
    required FocusNode focusNode,
    required bool enabled,
    String? validationError,
  }) {
    final controlClaim = _findControlClaim(control);
    if (controlClaim == null) {
      claim(
        control,
        focusNode: focusNode,
        enabled: enabled,
        validationError: validationError,
      );
      return;
    }
    _updateControlClaim(
      controlClaim,
      focusNode: focusNode,
      enabled: enabled,
      validationError: validationError,
    );
  }

  void _updateControlClaim(
    _FormControlClaim controlClaim, {
    required FocusNode focusNode,
    required bool enabled,
    required String? validationError,
  }) {
    final changed =
        !identical(controlClaim.focusNode, focusNode) ||
        controlClaim.enabled != enabled ||
        controlClaim.validationError != validationError;
    if (!changed) return;
    setState(() {
      controlClaim
        ..focusNode = focusNode
        ..enabled = enabled
        ..validationError = validationError;
    });
  }

  @override
  void release(Object control) {
    final index = _controlClaims.indexWhere(
      (claim) => identical(claim.control, control),
    );
    if (index < 0) return;
    if (mounted) {
      setState(() => _controlClaims.removeAt(index));
    } else {
      _controlClaims.removeAt(index);
    }
  }

  @override
  void controlValueChanged(Object control) {
    if (_findControlClaim(control) != null) valueChanged();
  }

  _FormControlClaim? _findControlClaim(Object control) {
    for (final claim in _controlClaims) {
      if (identical(claim.control, control)) return claim;
    }
    return null;
  }

  void _scheduleClaimCheck() {
    if (_claimCheckScheduled || widget.builder != null) return;
    _claimCheckScheduled = true;
    scheduleMicrotask(() {
      _claimCheckScheduled = false;
      assert(() {
        if (!mounted) return true;
        if (_controlClaims.isEmpty) {
          throw StateError(
            'FormField(child: ...) did not find a form-aware control. Use '
            'FormField.builder for a custom value control.',
          );
        }
        if (_controlClaims.length > 1) {
          throw StateError(
            'FormField(child: ...) found more than one form-aware control. '
            'Use FormField.builder for a composite value and choose its focus '
            'and change behavior explicitly.',
          );
        }
        return true;
      }());
    });
  }

  Widget _buildError(BuildContext context, String currentError) {
    final custom = widget.errorBuilder;
    if (custom != null) return custom(context, currentError);
    return ExcludeSemantics(
      child: Text(currentError, style: Theme.of(context).errorStyle),
    );
  }

  @override
  void dispose() {
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleClaimCheck();
    final child = widget.builder == null
        ? FormControlScope(
            registration: this,
            error: error,
            child: widget.child!,
          )
        : widget.builder!(context, this);
    if (!widget.showErrorMessage) return child;
    final currentError = error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        child,
        if (currentError != null) _buildError(context, currentError),
      ],
    );
  }
}

final class _FormControlClaim {
  _FormControlClaim({
    required this.control,
    required this.focusNode,
    required this.enabled,
    required this.validationError,
  });

  final Object control;
  FocusNode focusNode;
  bool enabled;
  String? validationError;
}
