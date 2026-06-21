import 'package:fleury/fleury_host.dart';

final _optionLabelLineBreakPattern = RegExp(r'[\r\n\t]');

/// Sanitizes a provider/app-supplied option or menu label for single-line
/// display and semantics.
///
/// Option labels are data, not authored UI copy: completion providers,
/// dynamic menus, and select options routinely carry strings sourced from
/// files, processes, or models. The render path therefore strips terminal
/// escapes and collapses line breaks the same way the data widgets
/// (tables, logs, messages) already do. Values that get *inserted* (a
/// picked option's replacement text) are intentionally left alone — they
/// are application data, and the editing engine owns their display.
String sanitizeOptionLabel(String text) =>
    sanitizeForDisplay(text.replaceAll(_optionLabelLineBreakPattern, ' '));
