import 'focus.dart';
import 'framework.dart';

/// Internal bridge used by first-party value controls inside a form field.
///
/// Application code should use `FormField`, not this protocol. It lives in
/// core so controls such as [TextInput] can participate without depending on
/// the higher-level `fleury_widgets` package.
abstract interface class FormControlRegistration {
  /// The error currently exposed by the enclosing field.
  String? get error;

  /// Claims this field for one logical value control.
  void claim(
    Object control, {
    required FocusNode focusNode,
    required bool enabled,
    String? validationError,
  });

  /// Updates a control claim after focus, enabled, or intrinsic error changes.
  void updateClaim(
    Object control, {
    required FocusNode focusNode,
    required bool enabled,
    String? validationError,
  });

  /// Releases a previously claimed field.
  void release(Object control);

  /// Reports that the app-owned value represented by this control changed.
  void controlValueChanged(Object control);
}

/// Publishes the current form-field registration to one control subtree.
///
/// This is framework plumbing for `fleury_widgets.FormField`. A control only
/// participates when it is below this scope; being below a `Form` alone does
/// not alter its behavior.
class FormControlScope extends InheritedWidget {
  const FormControlScope({
    super.key,
    required this.registration,
    required this.error,
    required super.child,
  });

  final FormControlRegistration registration;
  final String? error;

  static FormControlRegistration? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<FormControlScope>()
      ?.registration;

  @override
  bool updateShouldNotify(FormControlScope oldWidget) =>
      error != oldWidget.error ||
      !identical(registration, oldWidget.registration);
}
