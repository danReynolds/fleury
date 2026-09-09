/// Delimited-text encoding shared by every widget that exports rows
/// (`DataTable`, `Table`). Each widget keeps its own public format enum —
/// the wire rules live here once so the two cannot drift.
///
/// Not exported from the package: call it through the widget's own
/// `export*Rows` function.
library;

import 'package:fleury/fleury_core.dart';

final _ansiEscapePattern = RegExp(
  r'\x1B(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\)|[@-_])',
);

/// One cell as it goes on the clipboard: ANSI stripped, then collapsed to a
/// single line so a cell can never forge a row break.
String sanitizeExportField(String field) =>
    sanitizeSingleLine(field.replaceAll(_ansiEscapePattern, ''));

/// One export row. Fields are sanitized, and for [csv] also quoted.
String formatExportLine(Iterable<String> fields, {required bool csv}) {
  return fields
      .map((field) => formatExportField(field, csv: csv))
      .join(csv ? ',' : '\t');
}

/// One export cell, sanitized and — for [csv] — quoted when it carries a
/// delimiter or a quote of its own.
String formatExportField(String field, {required bool csv}) {
  final sanitized = sanitizeExportField(field);
  if (!csv) return sanitized;
  if (!sanitized.contains(',') && !sanitized.contains('"')) return sanitized;
  return '"${sanitized.replaceAll('"', '""')}"';
}
