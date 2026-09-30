/// Implementation hooks for Fleury's own tests and profiling tools.
///
/// Reusable widget packages must use the supported `fleury_widget_support.dart`
/// contracts instead. These implementation hooks have no compatibility promise.
library;

export 'src/rendering/cell.dart' show CellStyleState, resolveCellStyle;
export 'src/rendering/text_projection.dart' show projectText;
export 'src/widgets/form_control.dart'
    show FormControlRegistration, FormControlScope;
export 'src/widgets/pointer.dart' show RenderPointerListener;
export 'src/widgets/focusable_control.dart' show FocusableControl;
export 'src/widgets/framework.dart' show dependOnScope, readScope;
export 'src/rendering/scroll_reveal.dart' show revealInScrollViews;
