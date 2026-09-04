/// Cross-package implementation hooks used by Fleury's first-party packages.
///
/// These APIs are not part of the application-facing widget surface.
library;

export 'src/rendering/cell.dart' show CellStyleState, resolveCellStyle;
export 'src/rendering/text_projection.dart' show projectText;
export 'src/widgets/form_control.dart'
    show FormControlRegistration, FormControlScope;
