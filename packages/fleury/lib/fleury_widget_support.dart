/// Supported, platform-neutral contracts for authors of reusable widgets.
///
/// Application UI normally imports `fleury_core.dart`. Import this library
/// alongside it when implementing controls, forms, or custom cell painting.
/// These contracts follow Fleury's package compatibility guarantees, including
/// for third-party widget libraries; they are not lockstep implementation hooks.
/// Implementation render classes and source/display mappings stay private.
library;

import 'src/rendering/text_projection.dart' show projectText;
import 'src/rendering/width_policy.dart' show TextPresentationPolicy;

export 'src/rendering/cell.dart' show CellStyleState, resolveCellStyle;
export 'src/rendering/scroll_reveal.dart' show revealInScrollViews;
export 'src/widgets/focusable_control.dart' show FocusableControl;
export 'src/widgets/form_control.dart'
    show FormControlRegistration, FormControlScope;
export 'src/widgets/framework.dart' show dependOnScope, readScope;

/// The display spelling to measure and paint under [policy].
///
/// Keep the original text for copy, selection, and semantics. This function
/// only applies the surface's authorized text projection; it does not sanitize
/// untrusted text. Use `sanitizeSingleLine` first for a single-line label.
String projectDisplayText(
  String text, {
  required TextPresentationPolicy policy,
}) => projectText(text, policy: policy).displayText;
